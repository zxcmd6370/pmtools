// Pmtools — Millennium client module.
//
// The client module runs in the main Steam client UI context (library, etc.).
// Two jobs here:
//   1. Register the plugin entrypoint so Millennium's frontend shim has a
//      valid module for the plugin.
//   2. Boot-time store-data pre-warm. The library detail page fetches per-app
//      store data on every open (store.steampowered.com/api/libraryappdetails
//      + steamcommunity.com ajaxgetbadgeinfo). Games owned the normal way feel
//      instant because those responses are already in Steam's webhelper HTTP
//      cache; freshly unlocked games hit a cold cache, so the first open pays
//      1-2s of sequential round-trips (repeat opens are instant once cached).
//      The webkit module's pre-warm only runs in store/welcome windows — it
//      NEVER fires in the library. This module runs in the library context at
//      boot, so the warm-up lives here. One pass per Steam session, a few
//      requests at a time, timeouts on every request, and transient failures
//      are retried (the backend and Steam's network stack may not be ready at
//      the moment the client module first boots).

const MILLENNIUM_IS_CLIENT_MODULE = true;
const pluginName = "Pmtools";

function InitializePlugins() {
  let _a, _b;
  (_a = (window.PLUGIN_LIST || (window.PLUGIN_LIST = {})))[pluginName] || (_a[pluginName] = {});
  (_b = (window.MILLENNIUM_PLUGIN_SETTINGS_STORE || (window.MILLENNIUM_PLUGIN_SETTINGS_STORE = {})))[pluginName] || (_b[pluginName] = {});
}

InitializePlugins();

const __call_server_method__ = (methodName, kwargs) =>
  Millennium.callServerMethod(pluginName, methodName, kwargs);

function PluginEntryPointMain() {
  const module = {};

  module.default = async function ClientModuleEntryPoint() {
    // No client-side UI — the store-page UI lives in webkit.js. Kick off the
    // library-context store-data warm-up so first detail-page opens are fast.
    prewarmStoreData();
  };

  return module;
}

function ExecutePluginModule() {
  const MillenniumStore = window.MILLENNIUM_PLUGIN_SETTINGS_STORE[pluginName];
  MillenniumStore.OnPluginConfigChange = function OnPluginConfigChange() {};

  const PluginModule = PluginEntryPointMain();

  Object.assign(window.PLUGIN_LIST[pluginName], {
    ...PluginModule,
    __millennium_internal_plugin_name_do_not_use_or_change__: pluginName,
  });

  PluginModule.default();
}

ExecutePluginModule();

// ── Boot-time store-data pre-warm ────────────────────────────────────────────
// The flag is only set once the warm-up actually completes with at least one
// successful fetch. If the backend or Steam's network stack isn't ready when
// the client module first boots, the pass fails and a later retry takes over.

function prewarmDone() {
  try {
    return sessionStorage.getItem("__pmtoolsClientStorePrewarmed") === "1";
  } catch (_) {
    return false;
  }
}

function markPrewarmDone() {
  try {
    sessionStorage.setItem("__pmtoolsClientStorePrewarmed", "1");
  } catch (_) {}
}

async function prewarmStoreData() {
  if (prewarmDone()) return;

  const MAX_ATTEMPTS = 6;

  for (let attempt = 0; attempt < MAX_ATTEMPTS && !prewarmDone(); attempt++) {
    let ok = false;

    try {
      ok = await prewarmOnce();
    } catch (_) {
      /* retry below */
    }

    if (ok) {
      markPrewarmDone();
      return;
    }

    // Backend may still be booting — wait before the next attempt (longer
    // each time so we don't hammer Steam's network at startup).
    await new Promise(function (res) {
      setTimeout(res, 15000 * (attempt + 1));
    });
  }
}

async function prewarmOnce() {
  const body = await Millennium.callServerMethod(pluginName, "ListPmtoolsInstalled", {});
  let list = null;

  try {
    list = JSON.parse(body);
  } catch (_) {}

  const apps = (list && list.apps) || [];
  if (!apps.length) return true; // nothing to warm — treat as done

  // A fetch that hangs (no timeout) would stall the whole warm-up — Steam's
  // endpoints occasionally drop connections. Bound every request.
  function fetchTimeout(url, ms) {
    const ctrl = new AbortController();
    const t = setTimeout(function () {
      ctrl.abort();
    }, ms);

    return fetch(url, { credentials: "include", signal: ctrl.signal }).finally(function () {
      clearTimeout(t);
    });
  }

  // Resolve the user's profile URL via a JSON endpoint (the /my/ alias
  // redirects to /profiles/<steamid>/ and JSON endpoints carry CORS headers,
  // unlike HTML pages), so badge pre-fetches use the exact URL the detail
  // page requests. App 440 is just a probe; the response is discarded. At
  // boot the community session cookie may not be set yet, so this probe runs
  // in PARALLEL with the library-appdetails warm (which needs no cookie) and
  // retries with backoff before giving up on badges.
  const profileP = (async function () {
    let p = "";

    for (let attempt = 0; attempt < 5 && !p; attempt++) {
      if (attempt) {
        await new Promise(function (res) {
          setTimeout(res, 20000 * attempt);
        });
      }

      try {
        const r = await fetchTimeout("https://steamcommunity.com/my/ajaxgetbadgeinfo/440/", 15000);
        const m = /profiles\/(\d+)/.exec(r.url || "");
        if (m) p = m[1];
      } catch (_) {}
    }

    return p;
  })();

  const CONCURRENCY = 3;
  const PAUSE_MS = 150;

  // Steam sets <html lang> to the client's language — the same value the
  // detail page bakes into its own requests, so the cache key matches.
  const lang = (document.documentElement && document.documentElement.lang) || "english";

  let idx = 0;
  let successes = 0;

  async function worker() {
    while (idx < apps.length) {
      const id = apps[idx++].appid;

      try {
        const resp = await fetchTimeout(
          "https://store.steampowered.com/api/libraryappdetails/?appid=" +
            id +
            "&l=" +
            encodeURIComponent(lang),
          15000
        );

        await resp.text(); // drain — the response only helps once cached

        if (resp.status === 200) successes++;

        if (resp.status === 429) {
          // rate-limited — back off a moment before continuing
          await new Promise(function (res) {
            setTimeout(res, 1500);
          });
        }
      } catch (_) {
        /* transient blip — retried on the next attempt */
      }

      await new Promise(function (res) {
        setTimeout(res, PAUSE_MS);
      });
    }
  }

  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, apps.length) }, worker));

  // Badge pre-fetch only after the profile resolves (community cookie
  // settled) — the library warm above is never blocked on it.
  const profile = await profileP;

  if (profile) {
    let bidx = 0;

    async function badgeWorker() {
      while (bidx < apps.length) {
        const id = apps[bidx++].appid;

        try {
          const resp = await fetchTimeout(
            "https://steamcommunity.com/profiles/" + profile + "/ajaxgetbadgeinfo/" + id + "/",
            15000
          );

          await resp.text();

          if (resp.status === 429) {
            await new Promise(function (res) {
              setTimeout(res, 1500);
            });
          }
        } catch (_) {}

        await new Promise(function (res) {
          setTimeout(res, PAUSE_MS);
        });
      }
    }

    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, apps.length) }, badgeWorker));
  }

  try {
    console.log(
      "[Pmtools] store data pre-warmed for " +
        apps.length +
        " game(s)" +
        (successes ? " (" + successes + " cached)" : " (no profile)")
    );
  } catch (_) {}

  // Only "done" if the library warm actually fetched something — otherwise a
  // later retry takes another shot (Steam's network may not have been ready).
  return successes > 0;
}