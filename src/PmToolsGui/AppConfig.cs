namespace PmToolsGui;

/// <summary>
/// Compiled-in client configuration. The Supabase URL and anon key are public
/// client values (they also ship in the luatools web bundle).
/// </summary>
public static class AppConfig
{
    public const string SupabaseUrl = "https://db.lua.tools";

    public const string SupabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NzYwMzkzNzYsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.f_-K38u3odjltP-g_67FVmG32Vg-_-k-lNBvIaVUVBM";

    public const string ApiBaseUrl = "https://lua.tools";

    // Bot-provisioned (Discord /login placeholder) accounts use this email domain. Detecting it on
    // startup lets the app prompt the user to re-link their full luatools account.
    public const string BotAccountEmailDomain = "@bot.lua.tools";

    // Hubcap (hubcapmanifest.com): the app talks to this directly with the user's own API key
    // (no luatools proxy). Key + stats are managed in Settings; key-gated source downloads hit it.
    public const string HubcapBaseUrl = "https://hubcapmanifest.com";

    /// <summary>Must be registered in Supabase Auth → Redirect URLs.</summary>
    public const int OAuthCallbackPort = 53789;
    public const string OAuthCallbackUrl = "http://localhost:53789/callback";

    // The standard luatools daily download cap (Hubcap-keyed downloads are exempt). Hardcoded here
    // because the web app enforces it inline with no API field exposing it; change in one place if it moves.
    public const int DailyDownloadLimit = 25;

    // Public upstream APIs the app calls directly (no luatools proxy needed for guest browsing).
    public const string SteamStoreSearchUrl = "https://store.steampowered.com/api/storesearch/";
    // Steam's storefront "featured categories" (top sellers, new releases, etc.). Drives the Add page's
    // featured strips. Public, no auth.
    public const string SteamFeaturedUrl = "https://store.steampowered.com/api/featuredcategories";

    // Community list of Steam "hardware" appids (Steam Deck, Index, controllers, VR headsets). Fetched
    // via GithubProxy (raw.githubusercontent.com → mirror fallback) and cached ~14 days, to filter
    // hardware out of featured/search. Array of { "appid": <long>, "name": ... } objects.
    public const string HardwareAppIdListUrl =
        "https://raw.githubusercontent.com/jsnli/steamappidlist/master/data/hardware_appid.json";

    // Steamless (atom0s): strips SteamStub DRM from a game's .exe. Downloaded via GithubProxy and
    // cached locally; the "Remove Steam DRM" Manage action runs Steamless.CLI.exe against the game's exe.
    public const string SteamlessRepo = "atom0s/Steamless";

    // CloudRedirect (Selectively11): the Mode page "Manage" button downloads the latest CloudRedirect.exe
    // GUI manager from here and launches it. (Separate from the CLI fixer used by the mode install flow.)
    public const string CloudRedirectRepo = "Selectively11/CloudRedirect";

    // SteamAutoCrack: the Downloads page button fetches this release and launches its GUI.
    public const string SteamAutoCrackRepo = "SteamAutoCracks/Steam-auto-crack";

    // DepotDownloaderMod: downloads raw depot content from Steam's CDN using depot keys + a local manifest.
    public const string DepotDownloaderRepo = "mendy-tools/DepotDownloaderMod";
    public const string ManifestBackendUrl = "http://167.235.229.108";
    public const string ManifestBackendUserAgent = "secretgoonpoon";

    // The donate-keys endpoint gates on a DIFFERENT User-Agent than the manifest backend (it 403s
    // otherwise). This matches the LuaTools plugin's config.USER_AGENT.
    public const string DonateKeysUserAgent = "discord(dot)gg/luatools";

    // ── Umami analytics (anonymous app-launch counting) ──────────────
    public const string UmamiHost = "https://analytics.lua.tools";
    public const string UmamiWebsiteId = "820d782c-a434-424f-9f90-dee83dc6032e";
    public const string UmamiHostname = "desktop.lua.tools";

    /// <summary>
    /// Public GitHub repos hosting Velopack release assets, in priority order.
    /// </summary>
    public static readonly string[] GithubReleasesRepos =
    [
        "https://github.com/madoiscool/PmTools",   // primary
        "https://github.com/mendy-tools/PmTools",  // backup
    ];

    /// <summary>The primary releases repo (first in <see cref="GithubReleasesRepos"/>).</summary>
    public static string GithubReleasesRepo => GithubReleasesRepos[0];

    // ── Plugin releases ──────────────
    public const string PluginReleasesOwner = "zxcmd6370";
    public const string PluginReleasesRepo = "LTSP";

    // ── GitHub proxy mirrors ──────────────
    public static readonly string[] GithubApiMirrors =
    [
        "https://lua.tools/api/gh/",
    ];
    public static readonly string[] GithubDownloadMirrors =
    [
        "https://ghproxy.net/",
        "https://ghfast.top/",
        "https://gh.ddlc.top/",
    ];
}
