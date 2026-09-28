// Pmtools — in-Steam unlock plugin UI.
//
// This file is the plugin's *webkit module*: Millennium's webkit world manager
// serves it over its FTP route and injects it into the store-page context via
// CDP (Page.addScriptToEvaluateOnNewDocument), which is exempt from the store
// page's Content-Security-Policy. That is why the UI must live here rather
// than in a plain <script> tag — the add_browser_js route is CSP-blocked.
//
// Visual design: themed modals (gradient backgrounds, rounded corners, blur
// backdrops, slideUp animation), Font Awesome icon buttons, a card button
// grid, and native-looking store-page buttons pinned into Steam's button row.
//
// The UI talks to the Lua backend via Millennium.callServerMethod.

var MILLENNIUM_IS_CLIENT_MODULE = false;
var pluginName = "Pmtools";

// ── Pmtools UI ──────────────────────────────────────────────────────────────

function PmtoolsEntryPoint() {
  "use strict";

  function call(method, params) {
    return Millennium.callServerMethod(pluginName, method, params || {});
  }

  async function rpc(method, params) {
    const body = await call(method, params || {});
    try {
      return JSON.parse(body);
    } catch {
      return { success: false, error: "bad-response" };
    }
  }

  function backendLog(msg) {
    try {
      console.log("[Pmtools] " + msg);
    } catch (_) {}
  }

  // ── i18n ────────────────────────────────────────────────────────────────────

  const STRINGS = {
    en: {
      appName: "Pmtools",
      add: "Add via Pmtools",
      remove: "Remove",
      removeShort: "Remove",
      settings: "Settings",
      settingsTitle: "Pmtools · Settings",
      close: "Close",
      theme: "Theme",
      language: "Language",
      uiScale: "UI scale",
      sources: "Sources",
      restartSteam: "Restart Steam",
      restartQuestion: "Restart Steam now?",
      restartYes: "Restart",
      restartNo: "Later",
      addTitle: "Pmtools · Add",
      addSource: "Source",
      addStart: "Start",
      addCancel: "Cancel",
      addDone: "Done",
      statusQueued: "Queued…",
      statusDownloading: "Downloading…",
      statusExtracting: "Extracting…",
      statusInstalling: "Installing…",
      statusDone: "Game added!",
      statusApplying: "Applying\u2026",
      statusApplied: "Game added!",
      statusApplyFailed: "Failed to apply",
      installedTitle: "Unlocked games",
      installedEmpty: "No unlocked games yet.",
      installedSearch: "Search games…",
      noMatches: "No matches.",
      disabled: "disabled",
      loading: "Loading…",
      statusFailed: "Failed",
      statusNoLua: "No {appid}.lua found in the bundle",
      statusNoUrl: "This source has no URL for this game",
      statusInProgress: "A download is already in progress",
      statusUnknownSource: "Unknown source",
      errorMissingAppid: "Could not read the app id from this page",
      errorBackend: "Pmtools backend unavailable",
      errorBackendHint: "Make sure the plugin is enabled and restart Steam.",
      addedNote: "",
      confirmRemove: "Remove Pmtools from this game?",
      confirmRemoveNamed: 'Remove "{name}" via Pmtools?',
      removed: "Removed.",
      removedNote: "",
      emptySources: "No sources available. Check backend/sources.local.json.",
      statusChecking: "Checking sources…",
      statusNotAvailable: "not available",
      statusNoSource: "No source has this game right now.",
      statusLimitReached: "Daily download limit reached — try again tomorrow.",
      statusLimitReachedShort: "daily limit reached",
      usageHint: "{name}: {remaining} of {limit} downloads left today",
      usageShort: "{remaining} of {limit} left today",
      usageKeyExpires: "key expires {date}",
      apiKeyUpdate: "Update API key",
      apiKeyPlaceholder: "Paste new API key…",
      apiKeySave: "Save",
      apiKeyCancel: "Cancel",
      apiKeySaved: "API key updated.",
      apiKeyError: "Could not save the key.",
      noApiKey: "No API key set — add one to download",
      detailsHint: "Click for details",
      lowUsageWarn: "Only {remaining} downloads left today on {name}. Start anyway?",
      confirmContinue: "Continue",
      confirmCancel: "Cancel",
      settingsHint: "Preferences for Pmtools.",
      installed: "Added",
      notInstalled: "Not added",
      ready: "Ready",
      back: "Back",
      unlockedCount: "{count} unlocked games",
      refresh: "Refresh",
      titleRefresh: "Refresh titles from Steam",
      titleOpenStore: "Open in Steam store",
      sortRecent: "Recently added",
      sortAlpha: "A–Z",
      sortDisabled: "Disabled first",
      filterAll: "All",
      filterEnabled: "Enabled",
      filterDisabled: "Disabled",
      removeFailed: "Remove failed.",
      healthOnline: "Online",
      healthOffline: "Offline",
      healthLatency: "{ms} ms",
      healthAvailability: "{pct}% available",
      healthLastOk: "last success {time}",
      healthLastFail: "last failure {time}",
      healthRefresh: "catalog refresh {time}",
      healthNever: "never",
      healthPending: "not checked yet — appears after the next store check",
      sourceEnabled: "Enabled",
      sourceDisabled: "Disabled",
      sourceToggleOff: "Disable this source",
      sourceToggleOn: "Enable this source",
      sourceToggleFailed: "Could not update the source.",
      updateAvailable: "Update available: v{current} → v{latest}",
      updateDownload: "Download update",
      updateCheckFailed: "Could not check for updates.",

      retry: "Retry",
      sourceLoading: "Loading sources…",
      sourcesLoadFailed: "Could not load sources.",
      installedLoadFailed: "Could not load unlocked games.",
      usageUnavailable: "Usage unavailable",

      vaultTitle: "Cloud Sync",
      vaultHint: "Backup manifests & save files directly to your personal storage.",
      vaultProvider: "Storage Target",
      vaultLocal: "Local Folder / NAS",
      vaultGdrive: "Google Drive",
      vaultWebdav: "WebDAV / Nextcloud",
      vaultSaveTest: "Save & Test",
      vaultBackupAll: "Vault Entire Library",
      vaultRestoreAll: "Restore All from Vault",
      vaultSyncGame: "Vault game",
      vaultConfirmBackupAll: "Backup manifests and save files for all unlocked games to your personal storage?",
      vaultConfirmRestoreAll: "Restore all games' manifests and saves from your personal vault into Steam?",
      vaultStatusNotConfigured: "Setup",
      vaultStatusDisabled: "Disabled",
      vaultStorageSection: "Storage Target & Credentials",
      vaultSyncSection: "Cloud Sync & Recovery",
      vaultOfflineSection: "Offline JSON Backup",
      vaultOfflineHint: "Export or import game unlock configurations as a standalone JSON file.",
      vaultExportJson: "Export JSON",
      vaultImportJson: "Import JSON",
    },
    "zh-Hans": {
      appName: "Pmtools",
      add: "通过 Pmtools 添加",
      remove: "移除",
      removeShort: "移除",
      settings: "设置",
      settingsTitle: "Pmtools · 设置",
      close: "关闭",
      theme: "主题",
      language: "语言",
      uiScale: "界面缩放",
      sources: "来源",
      restartSteam: "重启 Steam",
      restartQuestion: "立即重启 Steam？",
      restartYes: "重启",
      restartNo: "稍后",
      addTitle: "Pmtools · 添加",
      addSource: "来源",
      addStart: "开始",
      addCancel: "取消",
      addDone: "完成",
      statusQueued: "排队中…",
      statusDownloading: "下载中…",
      statusExtracting: "解压中…",
      statusInstalling: "安装中…",
      statusDone: "游戏已添加！",
      statusApplying: "应用中\u2026",
      statusApplied: "游戏已添加！",
      statusApplyFailed: "应用失败",
      installedTitle: "已解锁的游戏",
      installedEmpty: "还没有已解锁的游戏。",
      installedSearch: "搜索游戏…",
      noMatches: "无匹配结果。",
      disabled: "已禁用",
      loading: "加载中…",
      statusFailed: "失败",
      statusNoLua: "包中未找到 {appid}.lua",
      statusNoUrl: "该来源没有此游戏的链接",
      statusInProgress: "已有下载正在进行",
      statusUnknownSource: "未知来源",
      errorMissingAppid: "无法从本页读取 App ID",
      errorBackend: "Pmtools 后端不可用",
      errorBackendHint: "请确认插件已启用并重启 Steam。",
      addedNote: "",
      confirmRemove: "要从该游戏移除 Pmtools 吗？",
      confirmRemoveNamed: '通过 Pmtools 移除 "{name}"？',
      removed: "已移除。",
      removedNote: "",
      emptySources: "没有可用来源。请检查 backend/sources.local.json。",
      statusChecking: "正在检查来源…",
      statusNotAvailable: "不可用",
      statusNoSource: "目前没有来源收录该游戏。",
      statusLimitReached: "今日下载额度已用完，请明天再试。",
      statusLimitReachedShort: "今日额度已用完",
      usageHint: "{name}：今日剩余 {remaining}/{limit} 次下载",
      usageShort: "今日剩余 {remaining}/{limit}",
      usageKeyExpires: "密钥将于 {date} 到期",
      apiKeyUpdate: "更新 API 密钥",
      apiKeyPlaceholder: "粘贴新的 API 密钥…",
      apiKeySave: "保存",
      apiKeyCancel: "取消",
      apiKeySaved: "API 密钥已更新。",
      apiKeyError: "无法保存密钥。",
      noApiKey: "未设置 API 密钥 — 添加后即可下载",
      detailsHint: "点击查看详情",
      lowUsageWarn: "{name} 今日仅剩 {remaining} 次下载，仍要继续吗？",
      confirmContinue: "继续",
      confirmCancel: "取消",
      settingsHint: "Pmtools 的偏好设置。",
      installed: "已添加",
      notInstalled: "未添加",
      ready: "就绪",
      back: "返回",
      unlockedCount: "{count} 个已解锁游戏",
      refresh: "刷新",
      titleRefresh: "从 Steam 刷新标题",
      titleOpenStore: "在商店中打开",
      sortRecent: "最近添加",
      sortAlpha: "A–Z",
      sortDisabled: "已禁用优先",
      filterAll: "全部",
      filterEnabled: "已启用",
      filterDisabled: "已禁用",
      removeFailed: "移除失败。",
      healthOnline: "在线",
      healthOffline: "离线",
      healthLatency: "{ms} 毫秒",
      healthAvailability: "可用率 {pct}%",
      healthLastOk: "上次成功 {time}",
      healthLastFail: "上次失败 {time}",
      healthRefresh: "目录刷新 {time}",
      healthNever: "从未",
      healthPending: "尚未检测 — 下次商店检测后显示",
      sourceEnabled: "已启用",
      sourceDisabled: "已禁用",
      sourceToggleOff: "禁用此来源",
      sourceToggleOn: "启用此来源",
      sourceToggleFailed: "无法更新该来源。",
      updateAvailable: "发现新版本：v{current} → v{latest}",
      updateDownload: "下载更新",
      updateCheckFailed: "无法检查更新。",
      usageUnavailable: "使用情况不可用",

      vaultTitle: "云同步",
      vaultHint: "将清单与存档直接备份至您自己的个人云或本地存储。",
      vaultProvider: "存储目标",
      vaultLocal: "本地目录 / NAS",
      vaultGdrive: "谷歌云盘 (Google Drive)",
      vaultWebdav: "WebDAV / Nextcloud",
      vaultSaveTest: "保存并测试连接",
      vaultBackupAll: "备份整个库至保险箱",
      vaultRestoreAll: "从保险箱恢复所有游戏",
      vaultSyncGame: "备份此游戏",
      vaultConfirmBackupAll: "要将所有已解锁游戏的清单和存档备份到您的个人存储吗？",
      vaultConfirmRestoreAll: "要从您的个人保险箱恢复所有游戏的清单和存档到 Steam 吗？",
      vaultStatusNotConfigured: "去设置",
      vaultStatusDisabled: "已禁用",
      vaultStorageSection: "存储目标与凭据",
      vaultSyncSection: "云同步与恢复",
      vaultOfflineSection: "离线 JSON 备份",
      vaultOfflineHint: "将游戏配置导出或导入为独立的 JSON 文件。",
      vaultExportJson: "导出 JSON",
      vaultImportJson: "导入 JSON",
    },
  };

  let activeLang = "en";
  let loadedSettings = null;
  let backendVersion = null;

  function detectLanguage() {
    const nav = (navigator.language || "en").toLowerCase();
    return nav.startsWith("zh") ? "zh-Hans" : "en";
  }

  function tr(key, vars) {
    let text = (STRINGS[activeLang] && STRINGS[activeLang][key]) || STRINGS.en[key] || key;
    if (vars) {
      for (const [k, v] of Object.entries(vars)) {
        text = text.replace(new RegExp("\\{" + k + "\\}", "g"), String(v));
      }
    }
    return text;
  }

  // ── Themes ──────────────────────────────────────────────────────────────────

  const THEMES = [
    {
      value: "original", name: "Original",
      bgPrimary: "#1b2838", bgSecondary: "#2a475e", bgTertiary: "rgba(31, 57, 82, 0.86)",
      bgHover: "rgba(68, 112, 153, 0.86)", bgContainer: "rgba(24, 45, 63, 0.6)",
      accent: "#66c0f4", accentLight: "#a4d7f5", accentDark: "#4a9ece",
      border: "rgba(102,192,244,0.3)", borderHover: "rgba(102,192,244,0.8)",
      text: "#fff", textSecondary: "#dddddd",
      gradient: "linear-gradient(135deg, #66c0f4 0%, #a4d7f5 100%)",
      gradientLight: "linear-gradient(135deg, #a4d7f5 0%, #7dd4ff 100%)",
      shadow: "rgba(102,192,244,0.4)", shadowHover: "rgba(102,192,244,0.6)",
    },
    {
      value: "dark", name: "Dark",
      bgPrimary: "#1a1a1a", bgSecondary: "#2a2a2a", bgTertiary: "rgba(15, 15, 15, 0.95)",
      bgHover: "rgba(26, 26, 26, 0.95)", bgContainer: "rgba(15,15,15,0.6)",
      accent: "#888888", accentLight: "#aaaaaa", accentDark: "#666666",
      border: "rgba(136, 136, 136, 0.3)", borderHover: "rgba(136, 136, 136, 0.8)",
      text: "#fff", textSecondary: "#c7d5e0",
      gradient: "linear-gradient(135deg, #aaaaaa 0%, #888888 100%)",
      gradientLight: "linear-gradient(135deg, #cccccc 0%, #aaaaaa 100%)",
      shadow: "rgba(136, 136, 136, 0.4)", shadowHover: "rgba(136, 136, 136, 0.6)",
    },
    {
      value: "light", name: "Light",
      bgPrimary: "#f5f5f5", bgSecondary: "#ffffff", bgTertiary: "rgba(255, 255, 255, 0.95)",
      bgHover: "rgba(240, 240, 240, 0.95)", bgContainer: "rgba(230, 230, 235, 0.8)",
      accent: "#0056b3", accentLight: "#0077e6", accentDark: "#003d82",
      border: "rgba(0, 86, 179, 0.4)", borderHover: "rgba(0, 86, 179, 0.8)",
      text: "#1a202c", textSecondary: "#4a5568",
      gradient: "linear-gradient(135deg, #0077e6 0%, #0056b3 100%)",
      gradientLight: "linear-gradient(135deg, #0099ff 0%, #0077e6 100%)",
      shadow: "rgba(0, 86, 179, 0.25)", shadowHover: "rgba(0, 86, 179, 0.4)",
    },
    {
      value: "purple", name: "Purple",
      bgPrimary: "#1a1a1a", bgSecondary: "#2a2a2a", bgTertiary: "rgba(15, 15, 15, 0.95)",
      bgHover: "rgba(26, 26, 26, 0.95)", bgContainer: "rgba(15,15,15,0.6)",
      accent: "#a78bfa", accentLight: "#c4b5fd", accentDark: "#8b5cf6",
      border: "rgba(167, 139, 250, 0.3)", borderHover: "rgba(167, 139, 250, 0.8)",
      text: "#fff", textSecondary: "#c7d5e0",
      gradient: "linear-gradient(135deg, #a78bfa 0%, #c4b5fd 100%)",
      gradientLight: "linear-gradient(135deg, #c4b5fd 0%, #b8a0ff 100%)",
      shadow: "rgba(167, 139, 250, 0.4)", shadowHover: "rgba(167, 139, 250, 0.6)",
    },
    {
      value: "space", name: "Space",
      bgPrimary: "#0a0e27", bgSecondary: "#1a1f3a", bgTertiary: "rgba(10, 14, 39, 0.9)",
      bgHover: "rgba(26, 31, 58, 0.9)", bgContainer: "rgba(10, 14, 39, 0.6)",
      accent: "#6366f1", accentLight: "#818cf8", accentDark: "#4f46e5",
      border: "rgba(99, 102, 241, 0.3)", borderHover: "rgba(99, 102, 241, 0.8)",
      text: "#ffffff", textSecondary: "#e0e7ff",
      gradient: "linear-gradient(135deg, #6366f1 0%, #818cf8 100%)",
      gradientLight: "linear-gradient(135deg, #818cf8 0%, #a5b4fc 100%)",
      shadow: "rgba(99, 102, 241, 0.4)", shadowHover: "rgba(99, 102, 241, 0.6)",
    },
    {
      value: "ocean", name: "Ocean",
      bgPrimary: "#0f172a", bgSecondary: "#1e293b", bgTertiary: "rgba(15, 23, 42, 0.9)",
      bgHover: "rgba(30, 41, 59, 0.9)", bgContainer: "rgba(15, 23, 42, 0.6)",
      accent: "#06b6d4", accentLight: "#22d3ee", accentDark: "#0891b2",
      border: "rgba(6, 182, 212, 0.3)", borderHover: "rgba(6, 182, 212, 0.8)",
      text: "#ffffff", textSecondary: "#cbd5e1",
      gradient: "linear-gradient(135deg, #06b6d4 0%, #22d3ee 100%)",
      gradientLight: "linear-gradient(135deg, #22d3ee 0%, #67e8f9 100%)",
      shadow: "rgba(6, 182, 212, 0.4)", shadowHover: "rgba(6, 182, 212, 0.6)",
    },
    {
      value: "forest", name: "Forest",
      bgPrimary: "#0f1f0f", bgSecondary: "#1a2e1a", bgTertiary: "rgba(15, 31, 15, 0.9)",
      bgHover: "rgba(26, 46, 26, 0.9)", bgContainer: "rgba(15, 31, 15, 0.6)",
      accent: "#10b981", accentLight: "#34d399", accentDark: "#059669",
      border: "rgba(16, 185, 129, 0.3)", borderHover: "rgba(16, 185, 129, 0.8)",
      text: "#ffffff", textSecondary: "#d1fae5",
      gradient: "linear-gradient(135deg, #10b981 0%, #34d399 100%)",
      gradientLight: "linear-gradient(135deg, #34d399 0%, #6ee7b7 100%)",
      shadow: "rgba(16, 185, 129, 0.4)", shadowHover: "rgba(16, 185, 129, 0.6)",
    },
    {
      value: "rosepine", name: "Rose Pine",
      bgPrimary: "#191724", bgSecondary: "#26233a", bgTertiary: "rgba(25, 23, 36, 0.9)",
      bgHover: "rgba(38, 35, 58, 0.9)", bgContainer: "rgba(25, 23, 36, 0.6)",
      accent: "#ea9a97", accentLight: "#f5e0dc", accentDark: "#eb6f92",
      border: "rgba(234, 154, 151, 0.3)", borderHover: "rgba(234, 154, 151, 0.8)",
      text: "#e0def4", textSecondary: "#c4b1cd",
      gradient: "linear-gradient(135deg, #ea9a97 0%, #f5e0dc 100%)",
      gradientLight: "linear-gradient(135deg, #f5e0dc 0%, #ebbcba 100%)",
      shadow: "rgba(234, 154, 151, 0.4)", shadowHover: "rgba(234, 154, 151, 0.6)",
    },
    {
      value: "catppuccin", name: "Catppuccin",
      bgPrimary: "#1e1e2e", bgSecondary: "#313244", bgTertiary: "rgba(30, 30, 46, 0.9)",
      bgHover: "rgba(49, 50, 68, 0.9)", bgContainer: "rgba(30, 30, 46, 0.6)",
      accent: "#89b4fa", accentLight: "#cba6f7", accentDark: "#74c7ec",
      border: "rgba(137, 180, 250, 0.3)", borderHover: "rgba(137, 180, 250, 0.8)",
      text: "#cdd6f4", textSecondary: "#b6bfe8",
      gradient: "linear-gradient(135deg, #89b4fa 0%, #cba6f7 100%)",
      gradientLight: "linear-gradient(135deg, #cba6f7 0%, #f5c2e7 100%)",
      shadow: "rgba(137, 180, 250, 0.4)", shadowHover: "rgba(137, 180, 250, 0.6)",
    },
    {
      value: "dracula", name: "Dracula",
      bgPrimary: "#282a36", bgSecondary: "#44475a", bgTertiary: "rgba(40, 42, 54, 0.9)",
      bgHover: "rgba(68, 71, 90, 0.9)", bgContainer: "rgba(40, 42, 54, 0.6)",
      accent: "#ff79c6", accentLight: "#f1fa8c", accentDark: "#bd93f9",
      border: "rgba(255, 121, 198, 0.3)", borderHover: "rgba(255, 121, 198, 0.8)",
      text: "#f8f8f2", textSecondary: "#e0e0e0",
      gradient: "linear-gradient(135deg, #ff79c6 0%, #bd93f9 100%)",
      gradientLight: "linear-gradient(135deg, #f1fa8c 0%, #ff79c6 100%)",
      shadow: "rgba(255, 121, 198, 0.4)", shadowHover: "rgba(255, 121, 198, 0.6)",
    },
    {
      value: "christmas", name: "Christmas",
      bgPrimary: "#0d2818", bgSecondary: "#1a4d2e", bgTertiary: "rgba(13, 40, 24, 0.9)",
      bgHover: "rgba(26, 77, 46, 0.9)", bgContainer: "rgba(13, 40, 24, 0.6)",
      accent: "#dc2626", accentLight: "#f87171", accentDark: "#b91c1c",
      border: "rgba(220, 38, 38, 0.3)", borderHover: "rgba(220, 38, 38, 0.8)",
      text: "#ffffff", textSecondary: "#d4d4d4",
      gradient: "linear-gradient(135deg, #dc2626 0%, #f87171 100%)",
      gradientLight: "linear-gradient(135deg, #f87171 0%, #fca5a5 100%)",
      shadow: "rgba(220, 38, 38, 0.4)", shadowHover: "rgba(220, 38, 38, 0.6)",
    },
  ];

  function getTheme(key) {
    return THEMES.find((t) => t.value === key) || THEMES[0];
  }

  function hexToRgb(hex) {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result
      ? [parseInt(result[1], 16), parseInt(result[2], 16), parseInt(result[3], 16)]
      : [102, 192, 244];
  }

  function getThemeColors() {
    const theme = getTheme((loadedSettings && loadedSettings.theme) || "original");
    const rgb = hexToRgb(theme.accent);
    return {
      theme,
      modalBg: `linear-gradient(160deg, ${theme.bgPrimary} 0%, ${theme.bgSecondary} 55%, rgba(${rgb.join(",")}, 0.32) 100%)`,
      border: theme.accent,
      borderRgba: theme.border,
      text: theme.text,
      textSecondary: theme.textSecondary,
      accent: theme.accent,
      accentLight: theme.accentLight,
      gradient: theme.gradient,
      gradientLight: theme.gradientLight,
      shadow: theme.shadow,
      shadowHover: theme.shadowHover,
      shadowRgba: theme.shadow.replace("0.4", "0.3"),
      bgContainer: theme.bgContainer,
      bgTertiary: theme.bgTertiary,
      bgHover: theme.bgHover,
      rgbString: rgb.join(","),
    };
  }

  // ── Chrome styles (scoped) ──────────────────────────────────────────────────

  const CHROME_CSS = `
  @keyframes pmtoolsSlideUp {
    from { opacity: 0; transform: scale(0.92) translateY(0.571em); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }
  @keyframes pmtoolsFade {
    from { opacity: 0; }
    to { opacity: 1; }
  }
  @keyframes pmtoolsShimmer {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
  }
  @keyframes pmtoolsPop {
    0% { transform: scale(0.4); opacity: 0; }
    60% { transform: scale(1.15); opacity: 1; }
    100% { transform: scale(1); opacity: 1; }
  }
  @keyframes pmtoolsToastIn {
    from { opacity: 0; transform: translateX(1.5em); }
    to { opacity: 1; transform: translateX(0); }
  }
  @keyframes pmtoolsPageInRight {
    from { opacity: 0; transform: translateX(1.5em); }
    to { opacity: 1; transform: translateX(0); }
  }
  @keyframes pmtoolsPageInLeft {
    from { opacity: 0; transform: translateX(-1.5em); }
    to { opacity: 1; transform: translateX(0); }
  }
  @keyframes pmtoolsTitleSwap {
    from { opacity: 0; transform: translateY(0.286em) scale(0.96); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }
  .pmtools-page-in-right { animation: pmtoolsPageInRight 0.22s cubic-bezier(0.22, 1, 0.36, 1); will-change: transform, opacity; }
  .pmtools-page-in-left { animation: pmtoolsPageInLeft 0.22s cubic-bezier(0.22, 1, 0.36, 1); will-change: transform, opacity; }
  @keyframes pmtoolsPageOut {
    from { opacity: 1; transform: scale(1); }
    to { opacity: 0; transform: scale(0.97); }
  }
  .pmtools-page-out { animation: pmtoolsPageOut 0.06s ease-out forwards; will-change: transform, opacity; }
  /* Smooth expand/collapse for source health details */
  @keyframes pmtoolsDetailsIn {
    from { opacity: 0; transform: translateY(-0.4em); max-height: 0; }
    to { opacity: 1; transform: translateY(0); max-height: 10em; }
  }
  @keyframes pmtoolsDetailsOut {
    from { opacity: 1; transform: translateY(0); max-height: 10em; }
    to { opacity: 0; transform: translateY(-0.4em); max-height: 0; }
  }
  /* Section entrance stagger */
  @keyframes pmtoolsSectionIn {
    from { opacity: 0; transform: translateY(0.5em); }
    to { opacity: 1; transform: translateY(0); }
  }
  .pmtools-section {
    animation: pmtoolsSectionIn 0.3s cubic-bezier(0.22, 1, 0.36, 1) both;
  }
  .pmtools-section:nth-child(1) { animation-delay: 0ms; }
  .pmtools-section:nth-child(2) { animation-delay: 40ms; }
  .pmtools-section:nth-child(3) { animation-delay: 80ms; }
  .pmtools-section:nth-child(4) { animation-delay: 120ms; }
  .pmtools-section:nth-child(5) { animation-delay: 160ms; }
  .pmtools-section:nth-child(6) { animation-delay: 200ms; }
  .pmtools-section:nth-child(7) { animation-delay: 240ms; }
  /* Micro-interaction: icon pulse on data arrival */
  @keyframes pmtoolsIconPulse {
    0% { transform: scale(1); }
    50% { transform: scale(1.15); }
    100% { transform: scale(1); }
  }
  .pmtools-icon-pulse i {
    animation: pmtoolsIconPulse 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }
  /* Smooth badge count update */
  @keyframes pmtoolsBadgePop {
    0% { transform: scale(1); }
    40% { transform: scale(1.2); }
    100% { transform: scale(1); }
  }
  .pmtools-unlocked-badge.updated {
    animation: pmtoolsBadgePop 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }
  @keyframes pmtoolsProgressStripe {
    from { background-position: 0 0; }
    to { background-position: 2em 0; }
  }
  @keyframes pmtoolsSpin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
  .pmtools-icon-btn.spinning i {
    display: inline-block;
    animation: pmtoolsSpin 0.8s linear infinite;
  }
  /* Smooth row remove animation */
  @keyframes pmtoolsRowRemove {
    to { opacity: 0; transform: translateX(1em); height: 0; padding: 0; margin: 0; border-width: 0; }
  }
  .pmtools-row-removing {
    animation: pmtoolsRowRemove 0.25s cubic-bezier(0.22, 1, 0.36, 1) forwards;
    overflow: hidden;
  }
  /* Toast enter/exit improvements */
  @keyframes pmtoolsToastOut {
    to { opacity: 0; transform: translateX(1.5em) scale(0.95); }
  }
  /* Confirm overlay backdrop pulse */
  @keyframes pmtoolsOverlayPulse {
    from { opacity: 0; }
    to { opacity: 1; }
  }
  /* Toggle switch ripple effect */
  @keyframes pmtoolsToggleRipple {
    0% { box-shadow: 0 0 0 0 rgba(var(--ig-rgb), 0.4); }
    100% { box-shadow: 0 0 0 0.8em rgba(var(--ig-rgb), 0); }
  }
  .pmtools-source-toggle.on {
    animation: pmtoolsToggleRipple 0.4s ease-out;
  }
  /* Skeleton loading placeholders */
  .pmtools-skeleton {
    background: var(--ig-bg-tertiary);
    border-radius: 0.286em;
    position: relative;
    overflow: hidden;
  }
  .pmtools-skeleton::after {
    content: "";
    position: absolute;
    inset: 0;
    background: linear-gradient(90deg, transparent 0%, var(--ig-bg-secondary) 40%, var(--ig-bg-secondary) 60%, transparent 100%);
    background-size: 200% 100%;
    animation: pmtoolsShimmer 1.5s ease-in-out infinite;
  }
  .pmtools-skel-card {
    flex-direction: column;
    gap: 0.286em;
    padding: 0.429em 0.571em;
  }
  .pmtools-skel-card .pmtools-skel-img {
    width: 100%;
    aspect-ratio: 16/9;
    border-radius: 0.286em;
  }
  .pmtools-skel-card .pmtools-skel-text {
    height: 0.786em;
    width: 70%;
    margin: 0 auto;
    border-radius: 0.143em;
  }
  .pmtools-skel-card .pmtools-skel-meta {
    height: 0.643em;
    width: 40%;
    margin: 0 auto;
    border-radius: 0.143em;
  }
  .pmtools-skel-row {
    align-items: center;
    padding: 0.357em 0.571em;
  }
  .pmtools-skel-row .pmtools-skel-name {
    height: 0.786em;
    flex: 1;
    border-radius: 0.143em;
  }
  .pmtools-skel-row .pmtools-skel-btn {
    height: 1.6em;
    width: 3.5em;
    border-radius: 0.214em;
    flex-shrink: 0;
  }
  /* Stagger for skeleton cards/rows */
  @keyframes pmtoolsSkelIn {
    from { opacity: 0; transform: scale(0.95); }
    to { opacity: 1; transform: scale(1); }
  }
  .pmtools-skeleton {
    animation: pmtoolsSkelIn 0.2s cubic-bezier(0.22,1,0.36,1) both;
  }
  /* Source health skeleton */
  .pmtools-skel-source .pmtools-skel-name {
    height: 0.857em;
    width: 5em;
    border-radius: 0.143em;
  }
  .pmtools-skel-source .pmtools-skel-badge {
    height: 1.2em;
    width: 3em;
    border-radius: 0.214em;
    margin-left: auto;
  }
  .pmtools-skel-source .pmtools-skel-toggle {
    height: 1.2em;
    width: 2.2em;
    border-radius: 0.214em;
    flex-shrink: 0;
  }
  /* Error retry state */
  .pmtools-error-box {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.571em;
    padding: 0.857em 0;
    animation: pmtoolsSkelIn 0.2s cubic-bezier(0.22,1,0.36,1) both;
  }
  .pmtools-error-box .pmtools-error-icon {
    font-size: 1.5em;
    color: var(--ig-text-secondary);
    opacity: 0.6;
  }
  .pmtools-error-box .pmtools-error-msg {
    font-size: 0.786em;
    color: var(--ig-text-secondary);
    text-align: center;
  }
  .pmtools-retry-btn {
    background: var(--ig-bg-tertiary);
    color: var(--ig-text);
    border: 1px solid var(--ig-border);
    border-radius: 0.286em;
    padding: 0.357em 1em;
    font-size: 0.786em;
    cursor: pointer;
    transition: background 0.15s ease, border-color 0.15s ease, transform 0.1s ease;
    touch-action: manipulation;
  }
  .pmtools-retry-btn:hover {
    background: var(--ig-bg-secondary);
    border-color: var(--ig-accent);
  }
  .pmtools-retry-btn:active {
    transform: scale(0.96);
    transition-duration: 0ms;
  }
  /* Scale base: every em below is relative to this font-size. --ig-scale is a
     user-controlled setting (Settings → UI scale slider), so the whole UI can
     be sized to taste instead of being locked to one pixel size. */
  .pmtools-overlay, .pmtools-quick-menu {
    font-size: 14px;
    font-size: calc(14px * var(--ig-scale));
    -webkit-user-select: none;
    user-select: none;
  }
  .pmtools-overlay {
    position: fixed; inset: 0; z-index: 2147483000;
    background: linear-gradient(135deg, rgba(var(--ig-rgb), 0.42) 0%, rgba(0, 0, 0, 0.78) 100%);
    backdrop-filter: blur(12px);
    display: flex; align-items: center; justify-content: center;
    font-family: "Motiva Sans", Arial, sans-serif;
    animation: pmtoolsFade 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }
  @keyframes pmtoolsModalIn {
    from { opacity: 0; transform: scale(0.92) translateY(0.571em); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }
  .pmtools-modal {
    position: relative; border-radius: 1.286em; padding: 1.429em 1.286em;
    background: var(--ig-modal-bg);
    color: var(--ig-text);
    border: 1px solid var(--ig-border);
    box-shadow: 0 1.714em 5.714em rgba(0,0,0,0.65), 0 0 0 1px var(--ig-shadow);
    animation: pmtoolsModalIn 0.25s cubic-bezier(0.22, 1, 0.36, 1);
    /* Fixed-size box: every page inside (settings, unlocked games) renders in
       the same modal size, with the body scrolling if content overflows. */
    display: flex; flex-direction: column;
    height: min(49em, calc(100vh - 4em));
  }
  .pmtools-modal > div:nth-child(2) { flex: 1 1 auto; min-height: 0; }
  .pmtools-modal.pmtools-dialog { height: auto; }
  .pmtools-quick-menu { background: var(--ig-modal-bg); color: var(--ig-text); border: 1px solid var(--ig-border); }
  .pmtools-modal-header {
    display: flex; justify-content: space-between; align-items: center;
    flex-wrap: nowrap; min-width: 0; flex-shrink: 0; gap: 0.714em;
    margin-bottom: 1.429em; padding-bottom: 1.143em; border-bottom: 1px solid var(--ig-border);
    overflow: visible;
  }
  .pmtools-modal-title {
    display: flex; align-items: center; gap: 0.455em; font-size: 1.571em; font-weight: 600;
    color: var(--ig-text);
    min-width: 0; flex: 1 1 auto;
    white-space: nowrap; overflow: visible;
    padding: 4px 6px 4px 6px;
  }
  .pmtools-modal-title > span:not(.pmtools-version-badge) {
    display: inline-block;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
    flex: 1 1 auto;
    background: var(--ig-gradient);
    -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .pmtools-modal-title i {
    color: var(--ig-accent); -webkit-text-fill-color: var(--ig-accent); font-size: 0.909em;
    flex-shrink: 0;
  }
  .pmtools-modal-title img {
    width: 40px; height: 40px; object-fit: contain; border-radius: 0;
    -webkit-text-fill-color: initial; flex-shrink: 0;
    margin: 4px 8px 4px 6px;
    box-shadow: none;
    filter: drop-shadow(0 0 6px rgba(79, 172, 254, 0.8)) drop-shadow(0 0 16px rgba(79, 172, 254, 0.45));
    overflow: visible;
  }
  .pmtools-version-badge {
    font-size: 0.5em; font-weight: 500; padding: 0.15em 0.5em;
    border-radius: 0.6em; background: rgba(var(--ig-rgb), 0.15);
    color: var(--ig-accent); -webkit-text-fill-color: var(--ig-accent); opacity: 0.7; margin-left: 0.2em;
    vertical-align: middle; letter-spacing: 0.03em; background-clip: unset; -webkit-background-clip: unset;
    flex-shrink: 0; white-space: nowrap;
  }
  .pmtools-modal:not([data-page="main"]) .pmtools-version-badge {
    display: none !important;
  }
  .pmtools-icon-btn {
    display: flex; align-items: center; justify-content: center;
    width: 2.333em; height: 2.333em;
    background: rgba(var(--ig-rgb), 0.1);
    border: 1px solid var(--ig-border);
    border-radius: 0.667em; color: var(--ig-accent);
    font-size: 1.286em; text-decoration: none;
    transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.2s ease;
    cursor: pointer; touch-action: manipulation;
  }
  .pmtools-icon-btn:hover { color: var(--ig-accent); -webkit-text-fill-color: var(--ig-accent); border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.22); transform: translateY(-0.056em); box-shadow: 0 0.333em 0.889em rgba(var(--ig-rgb), 0.18); }
  .pmtools-icon-btn:active { transform: scale(0.92) translateY(0); transition-duration: 0ms; }
  .pmtools-icon-row { display: flex; gap: 0.857em; flex-shrink: 0; }
  .pmtools-unlocked-toggle {
    display: flex; align-items: center; gap: 0.714em; width: 100%;
    background: rgba(var(--ig-rgb), 0.06);
    border: 1px solid var(--ig-border); border-radius: 0.857em;
    color: var(--ig-text); font-size: 0.929em; font-weight: 500; cursor: pointer;
    padding: 0.786em 1em; text-align: left; font-family: inherit;
    transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s cubic-bezier(0.22, 1, 0.36, 1);
    touch-action: manipulation;
  }
  .pmtools-unlocked-toggle:hover { border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.16); transform: translateY(-0.08em); }
  .pmtools-unlocked-toggle:active { transform: scale(0.98); transition-duration: 0ms; }
  .pmtools-unlocked-toggle i {
    color: var(--ig-bg-primary); background: var(--ig-gradient);
    width: 2.4em; height: 2.4em; display: inline-flex; align-items: center; justify-content: center;
    border-radius: 0.75em; font-size: 0.857em; box-shadow: 0 0.3em 0.8em var(--ig-shadow); flex: none;
  }
  .pmtools-unlocked-badge {
    margin-left: auto; background: rgba(var(--ig-rgb), 0.12);
    border: 1px solid var(--ig-border); border-radius: 1em;
    padding: 0.154em 0.769em; font-size: 0.857em; color: var(--ig-text-secondary);
    min-width: 2em; text-align: center; flex: none;
  }
  .pmtools-section { margin-bottom: 1.143em; }
  .pmtools-panel {
    background: rgba(var(--ig-rgb), 0.08);
    border: 1px solid var(--ig-border);
    border-radius: 0.857em;
    padding: 1em 1.143em;
    margin-bottom: 1em;
  }
  .pmtools-section-label {
    font-size: 0.857em; color: var(--ig-text-secondary); margin-bottom: 0.667em;
    text-transform: uppercase; letter-spacing: 0.036em; font-weight: 600;
  }
  .pmtools-modal select {
    background-color: var(--ig-bg-tertiary); color: var(--ig-text);
    border: 1px solid var(--ig-border); border-radius: 0.214em;
    padding: 0.429em 0.571em; font-size: 1em; width: 100%;
  }
  .pmtools-modal select option { background-color: var(--ig-bg-primary); }
  .pmtools-themes { display: flex; flex-wrap: wrap; gap: 0.429em; }
  .pmtools-theme-chip {
    padding: 0.417em 0.833em; border-radius: 1em;
    border: 1px solid var(--ig-border);
    background: rgba(var(--ig-rgb), 0.06);
    color: var(--ig-text); font-size: 0.857em; cursor: pointer;
    transition: border-color 0.15s ease, background 0.15s ease, color 0.15s ease, transform 0.15s cubic-bezier(0.22, 1, 0.36, 1);
    touch-action: manipulation;
  }
  .pmtools-theme-chip:hover { border-color: var(--ig-accent); transform: translateY(-0.07em); }
  .pmtools-theme-chip:active { transform: scale(0.95); transition-duration: 0ms; }
  .pmtools-theme-chip.active { background: var(--ig-accent); color: var(--ig-bg-primary); border-color: var(--ig-accent); font-weight: 600; transform: scale(1.06); }
  .pmtools-status { margin: 0.769em 0; font-size: 0.929em; color: var(--ig-text-secondary); min-height: 1.385em; }
  .pmtools-status.error { color: #ff7b7b; }
  .pmtools-status.ok { color: #9bd89b; }
  @keyframes pmtoolsPulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
  .pmtools-progress { height: 0.571em; background: rgba(var(--ig-rgb), 0.15); border-radius: 0.286em; overflow: hidden; margin: 0.571em 0; box-shadow: inset 0 1px 3px rgba(0,0,0,0.3); }
  .pmtools-progress > div { height: 100%; width: 0%; background: var(--ig-gradient); background-size: 200% 100%; animation: pmtoolsShimmer 1.4s linear infinite; border-radius: 0.286em; transition: width 0.3s cubic-bezier(0.22, 1, 0.36, 1); box-shadow: 0 0 0.571em var(--ig-shadow); }
  .pmtools-actions { display: flex; justify-content: flex-end; gap: 0.571em; margin-top: 1.143em; }
  .pmtools-btn {
    display: inline-flex; align-items: center; gap: 0.462em;
    padding: 0.615em 1.231em; border: 1px solid var(--ig-border); border-radius: 0.692em;
    background: rgba(var(--ig-rgb), 0.08); color: var(--ig-text);
    font-size: 0.929em; font-weight: 500; cursor: pointer;
    transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.2s ease, filter 0.2s ease;
    touch-action: manipulation;
  }
  .pmtools-btn:hover { border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.18); transform: translateY(-0.08em); }
  .pmtools-btn:active { transform: scale(0.96); transition-duration: 0ms; }
  .pmtools-btn.primary { background: var(--ig-gradient); color: var(--ig-bg-primary); border-color: transparent; font-weight: 600; box-shadow: 0 0.286em 1em var(--ig-shadow); }
  .pmtools-btn.primary:hover { filter: brightness(1.12); }
  .pmtools-btn:disabled { opacity: 0.55; cursor: default; filter: none; }
  .pmtools-source-row {
    display: flex; justify-content: space-between; padding: 0.538em 0.769em; font-size: 0.929em;
    border: 1px solid var(--ig-border); border-radius: 0.769em; margin-bottom: 0.462em;
    background: rgba(var(--ig-rgb), 0.04);
    transition: border-color 0.15s ease, background 0.15s ease, transform 0.15s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.15s ease;
  }
  .pmtools-source-row:hover { border-color: var(--ig-accent); }
  .pmtools-source-row.pmtools-clickable:hover { border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.14); transform: translateY(-0.056em); box-shadow: 0 0.333em 0.889em rgba(var(--ig-rgb), 0.18); }
  .pmtools-source-row.pmtools-clickable:active { transform: scale(0.985); transition-duration: 0ms; }
  .pmtools-installed-list { padding-right: 0.462em; }
  .pmtools-installed-list::-webkit-scrollbar { width: 0.615em; }
  .pmtools-installed-list::-webkit-scrollbar-thumb { background: rgba(var(--ig-rgb), 0.35); border-radius: 0.308em; }
  .pmtools-installed-list::-webkit-scrollbar-track { background: rgba(var(--ig-rgb), 0.08); }
  .pmtools-source-row .kind { color: var(--ig-text-secondary); font-size: 0.923em; }
  .pmtools-source-row .kind.warn { color: #e8a34d; }
  .pmtools-source-row .enabled { color: #9bd89b; font-size: 0.923em; }
  .pmtools-source-row .enabled.off { color: var(--ig-text-secondary); }
  .pmtools-source-row.disabled { opacity: 0.62; }
  .pmtools-source-toggle {
    width: 2.1em; height: 1.2em; border-radius: 999px; padding: 0; flex-shrink: 0;
    border: 1px solid var(--ig-border); background: rgba(var(--ig-rgb), 0.16);
    position: relative; cursor: pointer;
    transition: background-color 0.2s cubic-bezier(0.22, 1, 0.36, 1), border-color 0.2s ease;
    touch-action: manipulation;
  }
  .pmtools-source-toggle::after {
    content: ""; position: absolute; top: 0.15em; left: 0.18em;
    width: 0.82em; height: 0.82em; border-radius: 50%;
    background: var(--ig-text-secondary);
    transition: transform 0.2s cubic-bezier(0.22, 1, 0.36, 1), background-color 0.15s ease;
  }
  .pmtools-source-toggle.on { background: var(--ig-accent); border-color: var(--ig-accent); }
  .pmtools-source-toggle.on::after { transform: translateX(0.92em); background: var(--ig-bg-primary); }
  .pmtools-source-toggle:disabled { opacity: 0.55; cursor: default; }
  .pmtools-header-btn {
    display: inline-flex; align-items: center; justify-content: center;
    width: 40px; height: 40px; border-radius: 10px;
    background: var(--ig-gradient);
    border: 1px solid var(--ig-border);
    color: var(--ig-bg-primary); cursor: pointer; font-size: 14px;
    box-shadow: 0 4px 10px var(--ig-shadow);
    transition: transform 0.15s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.2s ease, filter 0.2s ease;
    margin: auto 8px; touch-action: manipulation;
  }
  .pmtools-header-btn:hover { filter: brightness(1.2); transform: translateY(-1px); box-shadow: 0 6px 16px var(--ig-shadow), 0 0 12px rgba(var(--ig-rgb), 0.4); }
  .pmtools-header-btn:hover img { animation: pmtoolsLogoSpin 1.2s cubic-bezier(0.22, 1, 0.36, 1); }
  .pmtools-header-btn:active { transform: scale(0.9); transition-duration: 0ms; }
  @keyframes pmtoolsLogoSpin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
  .pmtools-store-btn {
    margin-right: 3px !important;
    background: var(--ig-gradient) !important;
    color: var(--ig-bg-primary) !important;
    border: 1px solid var(--ig-border) !important;
    text-shadow: none !important;
    box-shadow: 0 2px 8px var(--ig-shadow) !important;
  }
  .pmtools-store-btn:hover {
    background: var(--ig-gradient-light) !important;
    filter: brightness(1.08);
  }
  .pmtools-store-btn.pmtools-remove-state {
    background: linear-gradient(135deg, #d64545 0%, #a83232 100%) !important;
    color: #ffffff !important;
    border-color: rgba(214, 69, 69, 0.9) !important;
  }
  .pmtools-modal ::-webkit-scrollbar { width: 0.714em; }
  .pmtools-modal ::-webkit-scrollbar-thumb { background: rgba(var(--ig-rgb), 0.35); border-radius: 0.357em; }
  .pmtools-modal ::-webkit-scrollbar-thumb:hover { background: rgba(var(--ig-rgb), 0.55); }
  .pmtools-modal ::-webkit-scrollbar-track { background: rgba(var(--ig-rgb), 0.06); border-radius: 0.357em; }
  /* Smooth scroll for all overflow containers */
  .pmtools-modal [style*="overflow"] { scroll-behavior: smooth; }
  /* Keyboard focus ring for nav-friendly focus styles */
  .pmtools-btn:focus-visible, .pmtools-card:focus-visible, .pmtools-icon-btn:focus-visible,
  .pmtools-theme-chip:focus-visible, .pmtools-header-btn:focus-visible {
    outline: 2px solid var(--ig-accent); outline-offset: 2px;
  }
  .pmtools-alert-icon { animation: pmtoolsPop 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28); }
  /* Smooth color fade when the theme changes (interactive elements already
     transition on hover via their own transition rules). */
  .pmtools-modal, .pmtools-panel, .pmtools-source-row,
  .pmtools-quick-menu, .pmtools-modal select, .pmtools-modal-title,
  .pmtools-section-label, .pmtools-status {
    transition: background-color 0.35s ease, border-color 0.35s ease, color 0.35s ease;
  }
  @media (prefers-reduced-motion: reduce) {
    .pmtools-overlay, .pmtools-modal, .pmtools-progress > div, .pmtools-card::after,
    .pmtools-alert-icon, .pmtools-panel, .pmtools-source-row, .pmtools-quick-menu,
    .pmtools-modal select, .pmtools-modal-title, .pmtools-section-label, .pmtools-status,
    .pmtools-page-in-right, .pmtools-page-in-left, .pmtools-page-out {
      animation: none !important; transition: none !important;
    }
  }
  `;

  // ── Prism identity (v2) ────────────────────────────────────────────────────
  // A distinctive design layer on top of the base tokens: glass surfaces,
  // aurora glow driven by the theme accent, display typography, pill controls.
  // Keeps every class name so the JS markup is untouched — it only restyles.
  const CHROME_CSS_V2 = `
  @keyframes pmtoolsAurora1 {
    0% { opacity: 0.7; }
    50% { opacity: 1; }
    100% { opacity: 0.82; }
  }
  @keyframes pmtoolsAurora2 {
    0% { transform: translate(0, 0) scale(1); }
    50% { transform: translate(-5%, 4%) scale(1.1); }
    100% { transform: translate(3%, -3%) scale(0.94); }
  }
  @keyframes pmtoolsShine {
    0% { transform: translateX(-130%) skewX(-18deg); }
    100% { transform: translateX(230%) skewX(-18deg); }
  }
  .pmtools-overlay {
    font-family: "Inter", "Motiva Sans", Arial, sans-serif;
    background: linear-gradient(135deg, rgba(var(--ig-rgb), 0.48) 0%, rgba(6, 8, 18, 0.8) 55%, rgba(0, 0, 0, 0.9) 100%);
    backdrop-filter: blur(16px) saturate(1.25);
  }
  /* Glass modal with a living aurora lit by the theme accent. */
  .pmtools-modal {
    border-radius: 1.5em;
    border: 1px solid rgba(var(--ig-rgb), 0.5);
    box-shadow: 0 2em 6em rgba(0, 0, 0, 0.7), 0 0 3.4em rgba(var(--ig-rgb), 0.18), inset 0 1px 0 rgba(255, 255, 255, 0.08);
    overflow: hidden;
  }
  .pmtools-modal::before {
    content: ""; position: absolute; inset: 0; z-index: 0; pointer-events: none;
    background:
      radial-gradient(46% 60% at 8% 0%, rgba(var(--ig-rgb), 0.3), transparent 72%),
      radial-gradient(40% 52% at 94% 6%, rgba(var(--ig-rgb), 0.22), transparent 72%),
      radial-gradient(60% 65% at 50% 118%, rgba(var(--ig-rgb), 0.16), transparent 72%);
    animation: pmtoolsAurora1 15s ease-in-out infinite alternate;
  }
  .pmtools-modal::after {
    content: ""; position: absolute; width: 62%; height: 62%; right: -22%; top: -28%;
    background: radial-gradient(closest-side, rgba(var(--ig-rgb), 0.24), transparent 75%);
    pointer-events: none; z-index: 0;
    animation: pmtoolsAurora2 22s ease-in-out infinite alternate;
  }
  .pmtools-modal > * { position: relative; z-index: 1; }
  .pmtools-modal-header { border-bottom: 1px solid rgba(var(--ig-rgb), 0.22); flex-wrap: nowrap; min-width: 0; flex-shrink: 0; gap: 0.714em; overflow: visible; }
  .pmtools-modal-title {
    display: flex; align-items: center; gap: 0.455em;
    font-family: "Sora", "Inter", "Motiva Sans", sans-serif;
    font-weight: 700; letter-spacing: -0.015em; font-size: 1.6em;
    color: var(--ig-text);
    min-width: 0; flex: 1 1 auto;
    white-space: nowrap; overflow: visible;
    padding: 4px 6px 4px 6px;
  }
  .pmtools-modal-title > span:not(.pmtools-version-badge) {
    display: inline-block;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
    flex: 1 1 auto;
    /* NOTE: --ig-gradient-light is a full gradient value, NOT a color —
       nesting it here as a color stop makes the whole background invalid at
       computed-value time (unset), which with -webkit-text-fill-color:
       transparent leaves the title invisible until text selection repaints
       it. Use real colors for every stop. */
    background: linear-gradient(92deg, var(--ig-accent-light) 0%, var(--ig-accent) 45%, var(--ig-accent-light) 100%);
    -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .pmtools-modal-title i {
    color: var(--ig-accent); -webkit-text-fill-color: var(--ig-accent);
    font-size: 0.86em;
    filter: drop-shadow(0 0 0.45em rgba(var(--ig-rgb), 0.8));
    flex-shrink: 0;
  }
  .pmtools-modal-title img {
    width: 40px; height: 40px; object-fit: contain; border-radius: 0;
    -webkit-text-fill-color: initial; flex-shrink: 0;
    margin: 4px 8px 4px 6px;
    box-shadow: none;
    filter: drop-shadow(0 0 6px rgba(79, 172, 254, 0.8)) drop-shadow(0 0 16px rgba(79, 172, 254, 0.45));
    overflow: visible;
  }
  .pmtools-version-badge {
    font-size: 0.5em; font-weight: 600; padding: 0.15em 0.5em;
    border-radius: 0.6em; background: rgba(var(--ig-rgb), 0.12);
    color: var(--ig-accent); -webkit-text-fill-color: var(--ig-accent); opacity: 0.75; margin-left: 0.2em;
    vertical-align: middle; letter-spacing: 0.03em; background-clip: unset; -webkit-background-clip: unset;
    flex-shrink: 0; white-space: nowrap;
  }
  .pmtools-modal:not([data-page="main"]) .pmtools-version-badge {
    display: none !important;
  }
  .pmtools-icon-btn {
    border-radius: 0.9em;
    background: rgba(var(--ig-rgb), 0.08);
    border: 1px solid rgba(var(--ig-rgb), 0.3);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
  }
  .pmtools-icon-btn:hover {
    color: var(--ig-accent);
    -webkit-text-fill-color: var(--ig-accent);
    border-color: var(--ig-accent);
    background: rgba(var(--ig-rgb), 0.2);
    box-shadow: 0 0 0.95em rgba(var(--ig-rgb), 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.08);
  }
  /* Glass tiles for cards */
  .pmtools-card {
    border-radius: 1.5em;
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.13) 0%, rgba(var(--ig-rgb), 0.04) 100%);
    border: 1px solid rgba(var(--ig-rgb), 0.26);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.07);
  }
  .pmtools-card:hover {
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.2) 0%, rgba(var(--ig-rgb), 0.09) 100%);
    border-color: var(--ig-accent);
    transform: translateY(-0.3em);
    box-shadow: 0 1.1em 2.6em rgba(var(--ig-rgb), 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.09);
  }
  .pmtools-card i {
    border-radius: 1.35em;
    box-shadow: 0 0.55em 1.4em var(--ig-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.25);
  }
  .pmtools-panel {
    border-radius: 1.1em;
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.1) 0%, rgba(var(--ig-rgb), 0.035) 100%);
    border: 1px solid rgba(var(--ig-rgb), 0.22);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
  }
  .pmtools-unlocked-toggle {
    border-radius: 1.1em;
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.13) 0%, rgba(var(--ig-rgb), 0.04) 100%);
    border: 1px solid rgba(var(--ig-rgb), 0.26);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.07);
  }
  .pmtools-unlocked-toggle:hover {
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.2) 0%, rgba(var(--ig-rgb), 0.09) 100%);
    border-color: var(--ig-accent);
    box-shadow: 0 0.6em 1.6em rgba(var(--ig-rgb), 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.09);
  }
  .pmtools-unlocked-toggle i { border-radius: 1em; box-shadow: 0 0.4em 1em var(--ig-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.25); }
  .pmtools-section-label {
    font-family: "Sora", "Inter", sans-serif;
    letter-spacing: 0.16em;
    display: flex; align-items: center; gap: 0.6em;
  }
  .pmtools-section-label::before {
    content: ""; width: 0.55em; height: 0.55em; border-radius: 50%; flex: none;
    background: var(--ig-accent);
    box-shadow: 0 0 0.7em var(--ig-accent);
  }
  .pmtools-modal select {
    border-radius: 0.7em;
    border: 1px solid rgba(var(--ig-rgb), 0.3);
    background-color: var(--ig-bg-tertiary);
  }
  /* Pill chips with a glow on the active theme */
  .pmtools-theme-chip {
    border-radius: 999px;
    padding: 0.5em 1.15em;
    border: 1px solid rgba(var(--ig-rgb), 0.32);
    background: rgba(var(--ig-rgb), 0.07);
    font-family: "Inter", sans-serif;
  }
  .pmtools-theme-chip:hover {
    border-color: var(--ig-accent);
    box-shadow: 0 0 0.95em rgba(var(--ig-rgb), 0.3);
  }
  .pmtools-theme-chip.active {
    background: var(--ig-gradient);
    color: var(--ig-bg-primary);
    border-color: transparent;
    font-weight: 700;
    box-shadow: 0 0 1.2em var(--ig-shadow);
  }
  /* Status pills */
  .pmtools-status.ok, .pmtools-status.error {
    display: inline-flex; align-items: center; gap: 0.55em;
    padding: 0.32em 0.95em; border-radius: 999px; font-size: 0.857em;
  }
  .pmtools-status.ok::before, .pmtools-status.error::before {
    content: ""; width: 0.5em; height: 0.5em; border-radius: 50%; flex: none;
    background: currentColor; box-shadow: 0 0 0.55em currentColor;
  }
  .pmtools-status.ok {
    color: #7ee787;
    background: rgba(80, 200, 120, 0.12);
    border: 1px solid rgba(80, 200, 120, 0.4);
  }
  .pmtools-status.error {
    color: #ff8a8a;
    background: rgba(255, 90, 90, 0.12);
    border: 1px solid rgba(255, 90, 90, 0.4);
  }
  .pmtools-progress {
    height: 0.75em;
    border-radius: 999px;
    background: rgba(var(--ig-rgb), 0.15);
    box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.4);
  }
  .pmtools-progress > div {
    border-radius: 999px;
    box-shadow: 0 0 0.9em var(--ig-shadow);
  }
  /* Pill buttons with a shine sweep on primary */
  .pmtools-btn { border-radius: 999px; font-family: "Inter", sans-serif; }
  .pmtools-btn.primary {
    position: relative; overflow: hidden;
    box-shadow: 0 0.3em 1.2em var(--ig-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.25);
  }
  .pmtools-btn.primary::after {
    content: ""; position: absolute; top: 0; left: 0; width: 45%; height: 100%;
    background: linear-gradient(105deg, transparent, rgba(255, 255, 255, 0.4), transparent);
    animation: pmtoolsShine 2.6s ease-in-out infinite;
    pointer-events: none;
  }
  .pmtools-source-row {
    border-radius: 1em;
    background: linear-gradient(180deg, rgba(var(--ig-rgb), 0.08) 0%, rgba(var(--ig-rgb), 0.025) 100%);
    border: 1px solid rgba(var(--ig-rgb), 0.24);
  }
  .pmtools-source-row:hover { border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.11); }
  .pmtools-source-row.pmtools-clickable:hover { border-color: var(--ig-accent); background: rgba(var(--ig-rgb), 0.2); transform: translateY(-0.056em); box-shadow: 0 0 0.95em rgba(var(--ig-rgb), 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.08); }
  .pmtools-source-row .enabled {
    display: inline-flex; align-items: center; gap: 0.45em; color: #7ee787;
  }
  .pmtools-source-row .enabled::before {
    content: ""; width: 0.5em; height: 0.5em; border-radius: 50%;
    background: #7ee787; box-shadow: 0 0 0.55em #7ee787;
  }
  .pmtools-source-row .enabled.off { color: var(--ig-text-secondary); }
  .pmtools-source-row .enabled.off::before { background: var(--ig-text-secondary); box-shadow: none; }
  .pmtools-source-row.disabled { opacity: 0.62; }
  .pmtools-source-toggle {
    width: 2.1em; height: 1.2em; border-radius: 999px; padding: 0; flex-shrink: 0;
    border: 1px solid rgba(var(--ig-rgb), 0.35); background: rgba(var(--ig-rgb), 0.16);
    position: relative; cursor: pointer; transition: background-color 0.22s ease, border-color 0.22s ease;
  }
  .pmtools-source-toggle::after {
    content: ""; position: absolute; top: 0.15em; left: 0.18em;
    width: 0.82em; height: 0.82em; border-radius: 50%;
    background: var(--ig-text-secondary); transition: transform 0.22s ease, background-color 0.22s ease;
  }
  .pmtools-source-toggle.on { background: var(--ig-accent); border-color: var(--ig-accent); box-shadow: 0 0 0.6em rgba(var(--ig-rgb), 0.4); }
  .pmtools-source-toggle.on::after { transform: translateX(0.92em); background: var(--ig-bg-primary); transition: transform 0.25s cubic-bezier(0.22, 1, 0.36, 1), background-color 0.2s ease; }
  .pmtools-source-toggle:disabled { opacity: 0.55; cursor: default; }
  .pmtools-installed-list::-webkit-scrollbar, .pmtools-modal ::-webkit-scrollbar { width: 0.5em; }
  .pmtools-installed-list::-webkit-scrollbar-thumb, .pmtools-modal ::-webkit-scrollbar-thumb {
    background: linear-gradient(var(--ig-accent), rgba(var(--ig-rgb), 0.45));
    border-radius: 999px;
  }
  .pmtools-installed-list::-webkit-scrollbar-thumb:hover, .pmtools-modal ::-webkit-scrollbar-thumb:hover {
    background: linear-gradient(var(--ig-accent-light), var(--ig-accent));
  }
  .pmtools-header-btn { border-radius: 12px; transition: transform 0.15s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.2s ease, filter 0.2s ease; }
  .pmtools-header-btn:hover {
    filter: brightness(1.25);
    box-shadow: 0 6px 20px var(--ig-shadow), 0 0 16px rgba(var(--ig-rgb), 0.5);
  }
  .pmtools-header-btn:active { transform: scale(0.88); transition-duration: 0ms; }
  /* Toasts: rounded glass with a glow matching the border accent */
  [id="pmtools-toasts"] > div {
    border-radius: 1em !important;
    box-shadow: 0 0.8em 2.6em rgba(0, 0, 0, 0.5), 0 0 1.4em rgba(var(--ig-rgb), 0.2) !important;
  }
  /* Theme fades also cover the new surfaces */
  .pmtools-modal, .pmtools-panel, .pmtools-source-row,
  .pmtools-quick-menu, .pmtools-modal select, .pmtools-modal-title,
  .pmtools-section-label, .pmtools-status {
    transition: background-color 0.35s ease, border-color 0.35s ease, color 0.35s ease, box-shadow 0.35s ease;
  }
  /* Achievement-style unlock notification */
  @keyframes pmtoolsAchievementIn {
    from { opacity: 0; transform: translateY(-1em) scale(0.9); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }
  @keyframes pmtoolsAchievementOut {
    to { opacity: 0; transform: translateY(-0.5em) scale(0.95); }
  }
  @keyframes pmtoolsAchievementIconPop {
    0% { transform: scale(0.3) rotate(-20deg); opacity: 0; }
    60% { transform: scale(1.15) rotate(5deg); opacity: 1; }
    100% { transform: scale(1) rotate(0deg); opacity: 1; }
  }
  @keyframes pmtoolsAchievementShine {
    0% { background-position: -200% 0; }
    100% { background-position: 200% 0; }
  }
  .pmtools-achievement {
    position: fixed; bottom: 2em; left: 50%; transform: translateX(-50%);
    z-index: 2147483500; pointer-events: none;
    display: flex; align-items: center; gap: 0.8em;
    padding: 0.7em 1.5em 0.7em 0.9em;
    border-radius: 999px;
    background: linear-gradient(135deg, rgba(var(--ig-rgb), 0.95), rgba(var(--ig-rgb), 0.75));
    border: 1px solid var(--ig-accent);
    box-shadow: 0 0.6em 2em rgba(var(--ig-rgb), 0.5), 0 0 3em rgba(var(--ig-rgb), 0.2);
    backdrop-filter: blur(12px);
    font-family: "Sora", "Inter", sans-serif;
    color: var(--ig-text);
    animation: pmtoolsAchievementIn 0.4s cubic-bezier(0.22, 1, 0.36, 1);
    overflow: hidden;
  }
  .pmtools-achievement::after {
    content: ""; position: absolute; inset: 0;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.15), transparent);
    background-size: 200% 100%;
    animation: pmtoolsAchievementShine 1.5s ease-in-out 0.4s;
    pointer-events: none;
  }
  .pmtools-achievement-icon {
    width: 2.4em; height: 2.4em;
    background: var(--ig-gradient);
    border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 1.1em; color: var(--ig-bg-primary);
    box-shadow: 0 0.3em 0.8em rgba(var(--ig-rgb), 0.4);
    flex-shrink: 0;
    animation: pmtoolsAchievementIconPop 0.4s cubic-bezier(0.18, 0.89, 0.32, 1.28) 0.15s both;
  }
  .pmtools-achievement-text {
    display: flex; flex-direction: column; gap: 0.1em;
    min-width: 0; flex: 1 1 auto; overflow: hidden;
  }
  .pmtools-achievement-title {
    font-size: 0.7em; font-weight: 600; letter-spacing: 0.12em;
    text-transform: uppercase; opacity: 0.7;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0;
  }
  .pmtools-achievement-name {
    font-size: 0.95em; font-weight: 700;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0;
  }
  @media (prefers-reduced-motion: reduce) {
    .pmtools-modal::before, .pmtools-modal::after,
    .pmtools-btn.primary::after, .pmtools-achievement,
    .pmtools-achievement-icon, .pmtools-achievement::after { animation: none !important; }
  }
  `;

  function ensureStyles() {
    if (!document.getElementById("pmtools-chrome-styles")) {
      const style = document.createElement("style");
      style.id = "pmtools-chrome-styles";
      style.textContent = CHROME_CSS;
      document.head.appendChild(style);
    }
    if (!document.getElementById("pmtools-chrome-styles-v2")) {
      const v2 = document.createElement("style");
      v2.id = "pmtools-chrome-styles-v2";
      v2.textContent = CHROME_CSS_V2;
      document.head.appendChild(v2);
    }
  }

  function ensureFontAwesome() {
    if (!document.getElementById("pmtools-fontawesome")) {
      try {
        const link = document.createElement("link");
        link.id = "pmtools-fontawesome";
        link.rel = "stylesheet";
        link.href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css";
        link.crossOrigin = "anonymous";
        link.referrerPolicy = "no-referrer";
        document.head.appendChild(link);
      } catch (_) {}
    }
    // Distinctive display + UI fonts (Prism identity). Falls back gracefully.
    if (!document.getElementById("pmtools-fonts")) {
      try {
        const f = document.createElement("link");
        f.id = "pmtools-fonts";
        f.rel = "stylesheet";
        f.href =
          "https://fonts.googleapis.com/css2?family=Sora:wght@600;700;800&family=Inter:wght@400;500;600;700&display=swap";
        document.head.appendChild(f);
      } catch (_) {}
    }
  }

  function applyTheme() {
    const c = getThemeColors();
    const t = c.theme;
    const root = document.documentElement;
    root.style.setProperty("--ig-bg-primary", t.bgPrimary);
    root.style.setProperty("--ig-bg-secondary", t.bgSecondary);
    root.style.setProperty("--ig-bg-tertiary", t.bgTertiary);
    root.style.setProperty("--ig-accent", t.accent);
    root.style.setProperty("--ig-accent-light", t.accentLight);
    root.style.setProperty("--ig-text", t.text);
    root.style.setProperty("--ig-text-secondary", t.textSecondary);
    root.style.setProperty("--ig-border", t.border);
    root.style.setProperty("--ig-border-hover", t.borderHover);
    root.style.setProperty("--ig-gradient", t.gradient);
    root.style.setProperty("--ig-gradient-light", t.gradientLight);
    root.style.setProperty("--ig-shadow", t.shadow);
    root.style.setProperty("--ig-rgb", c.rgbString);
    root.style.setProperty("--ig-modal-bg", c.modalBg);
  }

  // ── Store-page UI ───────────────────────────────────────────────────────────

  // Return the first element matching any of the given selectors (in order),
  // or null. Steam reshuffles its DOM/CSS-module class names between releases,
  // so every store-page lookup goes through here: a redesign that breaks the
  // primary selector still lands on a fallback instead of silently dying.
  function firstMatch(selectors) {
    for (let i = 0; i < selectors.length; i++) {
      try {
        const el = document.querySelector(selectors[i]);
        if (el) return el;
      } catch (_) { /* bad selector — try the next one */ }
    }
    return null;
  }

  function getAppId() {
    const m = window.location.pathname.match(/\/app\/(\d+)/);
    if (m) return m[1];
    // Fallback: Steam pages carry a canonical link with the appid even if the
    // URL shape changes (e.g. /app/440/Team_Fortress_2 → a rewritten route).
    const canonical = document.querySelector('link[rel="canonical"]');
    if (canonical && canonical.href) {
      const cm = canonical.href.match(/\/app\/(\d+)/);
      if (cm) return cm[1];
    }
    return null;
  }

  let storeBtn = null;
  let runState = { appid: null, status: null };

  function getStoreContainer() {
    // Where the "Add via Pmtools" button slots in next to Steam's own
    // link/button row. SteamDB's container first, then the apphub info row,
    // then any row that still carries those markers.
    return firstMatch([
      ".steamdb-buttons",
      "[data-steamdb-buttons]",
      ".apphub_OtherSiteInfo",
      '[class*="apphub_OtherSiteInfo"]',
      '[class*="site_links"]',
      '[class*="store_actions"]',
      '[class*="purchase_actions"]',
    ]);
  }

  function getHeaderContainer() {
    // Where the settings gear goes. Known hashed class first, then the older
    // store header classes, then any class that still carries the
    // header-actions markers.
    return firstMatch([
      "._1wn1lBlAzl3HMRqS1llwie",
      ".apphub_HeaderTopRightActions",
      ".apphub_HeaderTopRight",
      '[class*="apphub_HeaderTopRight"]',
      '[class*="header_actions"]',
      '[class*="header_buttons"]',
    ]);
  }

  // The re-assert timer runs on every Steam page, so a missing container must
  // log ONCE per page, not every 1.5 s forever (that spams the webhelper log
  // on every context where the selectors don't apply).
  let headerMissingLogged = false;
  let storeMissingLogged = false;

  function ensureHeaderButton() {
    // Never let a DOM/selector failure break the rest of the injection.
    try {
      if (document.querySelector(".pmtools-header-btn")) return;
      const headerContainer = getHeaderContainer();
      if (!headerContainer) {
        // A Steam UI redesign can move the header actions — surface it in the
        // logs (once per page) instead of failing silently.
        if (!headerMissingLogged) {
          headerMissingLogged = true;
          backendLog("Header container not found — Steam DOM may have changed (selectors in getHeaderContainer)");
        }
        return;
      }
      headerMissingLogged = false;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "pmtools-header-btn";
      btn.title = tr("settings");
      btn.setAttribute("data-tooltip-text", tr("settings"));
      btn.innerHTML =
        '<img src="data:image/png;base64,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" style="width:100%;height:100%;object-fit:contain;padding:2px;box-sizing:border-box;" />';
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        showSettingsPopup();
      });
      headerContainer.appendChild(btn);
      window.__PmtoolsHeaderInserted = true;
      backendLog("Inserted store header button");
    } catch (err) {
      backendLog("Pmtools header button insert failed: " + err);
    }
  }

  // Steam's store page (React-driven) re-renders the game-page link row asynchronously
  // and does not tolerate foreign DOM being re-ordered after the fact — a MutationObserver
  // that re-appends our buttons on every childList change fights Steam's re-render and
  // pegs the renderer (page never finishes loading). We therefore pin ONCE at insert time
  // and re-assert only on navigation, never from a container observer.
  //
  // Note: we intentionally do NOT add our own "Restart Steam" button to the store row —
  // when the legacy LuaTools plugin is also installed it provides one, and two restart
  // buttons in the same row is confusing. Our restart action stays available in the
  // settings popup and the add-complete flow.
  function ensureStoreButton() {
    // Never let a DOM/selector failure break the rest of the injection.
    try {
    const container = getStoreContainer();
    if (!container) {
      if (!storeMissingLogged) {
        storeMissingLogged = true;
        backendLog("Store button container not found — Steam DOM may have changed (selectors in getStoreContainer)");
      }
      return;
    }
    storeMissingLogged = false;

    if (!document.querySelector(".pmtools-store-btn")) {
      const ref = container.querySelector("a");
      if (!storeBtn) {
        const btn = document.createElement("a");
        btn.href = "#";
        btn.className =
          (ref && ref.className ? ref.className + " " : "btnv6_blue_hoverfade btn_medium ") +
          "pmtools-store-btn";
        const span = document.createElement("span");
        btn.appendChild(span);
        btn.title = tr("add");
        btn.setAttribute("data-tooltip-text", tr("add"));
        btn.addEventListener("click", function (e) {
          e.preventDefault();
          onStoreButtonClick();
        });
        storeBtn = btn;
      }
      try {
        if (ref) {
          const cs = window.getComputedStyle(ref);
          storeBtn.style.marginLeft = cs.marginLeft;
          storeBtn.style.marginRight = cs.marginRight;
        }
      } catch (_) {}
      container.appendChild(storeBtn);
      backendLog("Inserted Pmtools store button");
    } else {
      if (!storeBtn) storeBtn = document.querySelector(".pmtools-store-btn");
    }

    refreshStoreButton();
    } catch (err) {
      backendLog("Pmtools store button insert failed: " + err);
    }
  }

  async function refreshStoreButton() {
    const appid = getAppId();
    if (!storeBtn) return;
    const span = storeBtn.querySelector("span");
    if (!span) return;
    if (!appid) {
      span.textContent = tr("add");
      return;
    }
    let added = false;
    try {
      const res = await rpc("HasPmtoolsForApp", { appid });
      added = !!(res && res.added);
    } catch (_) {}
    span.textContent = added ? tr("remove") : tr("add");
    storeBtn.title = added ? tr("remove") : tr("add");
    storeBtn.setAttribute("data-tooltip-text", added ? tr("remove") : tr("add"));
    storeBtn.classList.toggle("pmtools-remove-state", added);
  }

  async function onStoreButtonClick() {
    const appid = getAppId();
    if (!appid) {
      showToast(tr("errorMissingAppid"), false);
      return;
    }
    if (["downloading", "extracting", "installing"].includes(runState.status)) return;
    let added = false;
    try {
      const res = await rpc("HasPmtoolsForApp", { appid });
      added = !!(res && res.added);
    } catch (_) {}
    if (added) {
      const ok = await confirmPopup(tr("confirmRemove"), tr("confirmContinue"), tr("confirmCancel"));
      if (!ok) return;
      const res = await rpc("DeletePmtoolsForApp", { appid });
      showToast(tr("removed"), !!(res && res.success));
      refreshStoreButton();
      return;
    }
    openAddPopup(appid);
  }

  // ── Add popup ───────────────────────────────────────────────────────────────

  function openAddPopup(appid) {
    const c = getThemeColors();
    const overlay = document.createElement("div");
    overlay.className = "pmtools-overlay";

    const modal = document.createElement("div");
    modal.className = "pmtools-modal pmtools-dialog";
    modal.style.cssText = `width:32.857em;max-width:calc(100vw - 48px);`;

    const header = document.createElement("div");
    header.className = "pmtools-modal-header";
    const title = document.createElement("div");
    title.className = "pmtools-modal-title";
    title.innerHTML = '<i class="fa-solid fa-download"></i>';
    const titleText = document.createElement("span");
    titleText.style.cssText = "display:inline-block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0;flex:1 1 auto;";
    titleText.textContent = tr("addTitle") + " · " + appid;
    titleText.title = titleText.textContent;
    title.appendChild(titleText);
    // Resolve and show the game's real name in the header (same-origin fetch).
    fetch("/api/appdetails?appids=" + appid)
      .then(function (r) { return r.json(); })
      .then(function (j) {
        const v = j && j[appid];
        if (v && v.success && v.data && v.data.name) {
          titleText.textContent = v.data.name + " · " + appid;
          titleText.title = v.data.name + " · " + appid;
        }
      })
      .catch(function () {});

    const iconRow = document.createElement("div");
    iconRow.className = "pmtools-icon-row";
    const closeBtn = document.createElement("a");
    closeBtn.href = "#";
    closeBtn.className = "pmtools-icon-btn";
    closeBtn.innerHTML = '<i class="fa-solid fa-xmark"></i>';
    closeBtn.addEventListener("click", function (e) {
      e.preventDefault();
      overlay.remove();
      refreshStoreButton();
    });
    iconRow.appendChild(closeBtn);

    header.appendChild(title);
    header.appendChild(iconRow);
    modal.appendChild(header);

    const body = document.createElement("div");

    const sourceSection = document.createElement("div");
    sourceSection.className = "pmtools-section";
    const sourceLabel = document.createElement("div");
    sourceLabel.className = "pmtools-section-label";
    sourceLabel.textContent = tr("addSource");
    const sourceSel = document.createElement("select");
    sourceSection.appendChild(sourceLabel);
    sourceSection.appendChild(sourceSel);
    body.appendChild(sourceSection);

    const usageHint = document.createElement("div");
    usageHint.className = "pmtools-status";
    usageHint.style.cssText = "font-size:0.857em;margin:-0.429em 0 0.714em;min-height:0;";
    body.appendChild(usageHint);

    const status = document.createElement("div");
    status.className = "pmtools-status";
    status.textContent = "…";
    body.appendChild(status);

    const progress = document.createElement("div");
    progress.className = "pmtools-progress";
    progress.style.display = "none";
    const bar = document.createElement("div");
    progress.appendChild(bar);
    body.appendChild(progress);

    const actions = document.createElement("div");
    actions.className = "pmtools-actions";
    const cancelBtn = document.createElement("button");
    cancelBtn.className = "pmtools-btn";
    cancelBtn.innerHTML = '<i class="fa-solid fa-ban"></i><span>' + tr("addCancel") + "</span>";
    cancelBtn.style.display = "none";
    const startBtn = document.createElement("button");
    startBtn.className = "pmtools-btn primary";
    startBtn.innerHTML = '<i class="fa-solid fa-play"></i><span>' + tr("addStart") + "</span>";
    actions.appendChild(cancelBtn);
    actions.appendChild(startBtn);
    body.appendChild(actions);

    modal.appendChild(body);
    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    let pollTimer = null;
    let terminalBtn = null; // the Close/Done button shown when the flow ends
    let terminalFailed = false;
    let terminalDone = false; // guards stopPoll against double-firing (overlapping async polls)
    let usageMap = {}; // source id -> { used, limit, remaining, expiresAt }
    let lastBytes = 0; // progress-bar speed tracking: previous downloaded bytes + timestamp
    let lastTs = 0;

    function fmtBytes(n) {
      if (!isFinite(n) || n < 0) return "";
      if (n >= 1024 * 1024 * 1024) return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
      if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB";
      if (n >= 1024) return (n / 1024).toFixed(0) + " KB";
      return n + " B";
    }

    function close() {
      if (pollTimer) clearInterval(pollTimer);
      overlay.remove();
      refreshStoreButton();
    }

    cancelBtn.addEventListener("click", async function () {
      await rpc("CancelPmtoolsAdd", { appid });
      cancelBtn.disabled = true;
      status.textContent = tr("statusQueued");
    });

    setStatus(tr("statusChecking"));

    // Ask the backend which enabled sources actually have this game (lightweight
    // ranged probe), so the dropdown only offers sources that can deliver.
    rpc("GetPmtoolsSourceAvailability", { appid }).then(function (res) {
      const sources = (res && res.sources) || [];
      sourceSel.innerHTML = "";
      if (sources.length === 0) {
        setStatus(tr("emptySources"), true);
        startBtn.disabled = true;
        return;
      }
      usageMap = {};
      let firstAvailable = null;
      let hubcapDefault = null; // hubcap wins the default when a key is set AND it has the game
      let anyLimitReached = false;
      sources.forEach(function (s) {
        const opt = document.createElement("option");
        opt.value = s.id;
        if (s.available) {
          opt.textContent = s.name;
          if (!firstAvailable) firstAvailable = s.id;
          if (s.id === "hubcap" && s.hasKey) hubcapDefault = s.id;
        } else if (s.limitReached) {
          anyLimitReached = true;
          opt.textContent = s.name + " (" + tr("statusLimitReachedShort") + ")";
          opt.disabled = true;
        } else {
          opt.textContent = s.name + " (" + tr("statusNotAvailable") + ")";
          opt.disabled = true;
        }
        if (s.usage && s.usage.remaining != null) usageMap[s.id] = s.usage;
        sourceSel.appendChild(opt);
      });
      function showUsageHint() {
        const u = usageMap[sourceSel.value];
        const opt = sourceSel.selectedOptions && sourceSel.selectedOptions[0];
        usageHint.textContent = u && opt ? tr("usageHint", { name: opt.textContent, remaining: u.remaining, limit: u.limit }) : "";
      }
      if (firstAvailable) {
        // With an API key configured, Hubcap is the preferred source: its
        // manifests are always current, so the download never fails on a
        // stale manifest. Fall back to the first available source when
        // Hubcap is keyless or doesn't have this game.
        sourceSel.value = hubcapDefault || firstAvailable;
        showUsageHint();
        sourceSel.addEventListener("change", showUsageHint);
        setStatus("");
      } else {
        setStatus(anyLimitReached ? tr("statusLimitReached") : tr("statusNoSource"), true);
        startBtn.disabled = true;
      }
    });

    function setStatus(text, isError) {
      status.style.animation = "none";
      void status.offsetWidth;
      status.style.animation = "pmtoolsSectionIn 0.2s cubic-bezier(0.22,1,0.36,1)";
      status.textContent = text;
      status.className = "pmtools-status" + (isError ? " error" : "");
    }

    startBtn.addEventListener("click", function () {
      // Warn before spending the last few downloads of a limited source.
      const u = usageMap[sourceSel.value];
      if (u && u.remaining != null && u.remaining <= 5) {
        const opt = sourceSel.selectedOptions && sourceSel.selectedOptions[0];
        const name = opt ? opt.textContent : sourceSel.value;
        confirmPopup(tr("lowUsageWarn", { remaining: u.remaining, name: name }), tr("confirmContinue"), tr("confirmCancel")).then(function (ok) {
          if (ok) startAdd();
        });
        return;
      }
      startAdd();
    });

    function startAdd() {
      const sourceId = sourceSel.value;
      startBtn.disabled = true;
      cancelBtn.style.display = "";
      setStatus(tr("statusQueued"));
      progress.style.display = "";
      bar.style.width = "12%";
      lastBytes = 0;
      lastTs = 0;

      rpc("StartPmtoolsAdd", { appid, sourceId }).then(function (res) {
        if (!res || !res.success) {
          const map = {
            "unknown-source": tr("statusUnknownSource"),
            "already-in-progress": tr("statusInProgress"),
          };
          setStatus(map[res && res.error] || tr("statusFailed"), true);
          startBtn.disabled = false;
          return;
        }
        pollTimer = setInterval(poll, 1200);
      });
    }
    // Note: no "Restart Steam" button is ever offered here. Like LuaTools,
    // an add ends at its status line — the hot-reloading loader applies the
    // stplug-in script silently, so a restart is never needed. The manual
    // restart action stays in the settings header for when the user wants it.
    function stopPoll(success) {
      if (terminalDone) return; // a concurrent poll already ended the flow
      terminalDone = true;
      runState.appid = null;
      runState.status = null;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      cancelBtn.style.display = "none";
      startBtn.style.display = "none";
      terminalFailed = !success;
      if (success) {
        const doneBtn = document.createElement("button");
        doneBtn.className = "pmtools-btn primary";
        doneBtn.innerHTML = '<i class="fa-solid fa-check"></i><span>' + tr("addDone") + "</span>";
        doneBtn.addEventListener("click", close);
        actions.appendChild(doneBtn);
        terminalBtn = doneBtn;
        // Achievement-style unlock notification
        resolveGameName(appid).then(function (name) { showAchievement(name, appid); });
      } else {
        const closeBtn = document.createElement("button");
        closeBtn.className = "pmtools-btn";
        closeBtn.innerHTML = '<i class="fa-solid fa-xmark"></i><span>' + tr("close") + "</span>";
        closeBtn.addEventListener("click", close);
        actions.appendChild(closeBtn);
        terminalBtn = closeBtn;
      }
    }

    // After a failed attempt, changing the source resets the popup back to the
    // ready state (Start button visible) so the user can retry with another
    // source without closing and reopening the modal.
    function resetToSourcePicker() {
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      if (terminalBtn) {
        terminalBtn.remove();
        terminalBtn = null;
      }
      terminalDone = false; // allow the retry to end the flow again
      // drop any other terminal buttons stopPoll appended (e.g. Restart Steam)
      while (actions.children.length > 2) {
        actions.removeChild(actions.lastChild);
      }
      cancelBtn.style.display = "none";
      cancelBtn.disabled = false;
      startBtn.style.display = "";
      startBtn.disabled = false;
      progress.style.display = "none";
      bar.style.width = "0%";
      setStatus("…");
      terminalFailed = false;
    }

    sourceSel.addEventListener("change", function () {
      if (terminalFailed) resetToSourcePicker();
    });

    async function poll() {
      const res = await rpc("GetPmtoolsAddStatus", { appid });
      const st = res && res.state;
      if (!st) return;
      runState.appid = appid;
      runState.status = st.status;

      switch (st.status) {
        case "downloading":
          if (st.progress && st.progress.total > 0) {
            const pct = Math.max(3, Math.min(90, st.progress.pct));
            bar.style.width = pct + "%";
            let text = tr("statusDownloading") + " " + pct + "%";
            const dl = st.progress.downloaded || 0;
            const now = Date.now();
            if (lastTs && dl > 0 && dl >= lastBytes && now > lastTs) {
              const speed = (dl - lastBytes) / ((now - lastTs) / 1000);
              if (speed > 0) {
                const remaining = Math.max(0, st.progress.total - dl);
                text += " · " + fmtBytes(speed) + "/s";
                if (remaining > 0) text += " · " + fmtBytes(remaining) + " left";
              }
            }
            lastBytes = dl;
            lastTs = now;
            setStatus(text);
          } else {
            setStatus(tr("statusDownloading"));
            bar.style.width = "35%";
          }
          break;
        case "extracting":
          setStatus(tr("statusExtracting"));
          bar.style.width = "65%";
          break;
        case "installing":
          setStatus(tr("statusInstalling"));
          bar.style.width = "85%";
          break;
        case "done": {
          const apply = st.apply;
          if (apply === "applying") {
            setStatus(tr("statusApplying"));
            bar.style.width = "92%";
          } else if (apply === "applied") {
            setStatus(tr("statusApplied"), false);
            status.className = "pmtools-status ok";
            bar.style.width = "100%";
            stopPoll(true);
          } else if (apply === "failed") {
            setStatus(tr("statusApplyFailed"), false);
            status.className = "pmtools-status ok";
            bar.style.width = "100%";
            stopPoll(true);
          } else {
            setStatus(tr("statusDone"), false);
            status.className = "pmtools-status ok";
            bar.style.width = "100%";
            stopPoll(true);
          }
          break;
        }
        case "failed":
          const map = {
            "no-lua-in-bundle": tr("statusNoLua", { appid }),
            "no-url": tr("statusNoUrl"),
          };
          setStatus(map[st.error] || tr("statusFailed") + (st.error ? " (" + st.error + ")" : ""), true);
          stopPoll(false);
          break;
      }
    }
  }

  // ── Settings popup ──────────────────────────────────────────────────────────

  function showSettingsPopup() {
    if (document.querySelector(".pmtools-settings-overlay")) return;
    const c = getThemeColors();
    const overlay = document.createElement("div");
    overlay.className = "pmtools-overlay pmtools-settings-overlay";

    const modal = document.createElement("div");
    modal.className = "pmtools-modal";
    modal.setAttribute("data-page", "main");
    modal.style.cssText = `width:37.143em;max-width:calc(100vw - 48px);max-height:88vh;display:flex;flex-direction:column;padding:1.857em 1.857em;scroll-behavior:smooth;`;

    const header = document.createElement("div");
    header.className = "pmtools-modal-header";
    const title = document.createElement("div");
    title.className = "pmtools-modal-title";
    title.innerHTML = '<img src="data:image/png;base64,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" style="width:40px;height:40px;object-fit:contain;" />';
    const titleText = document.createElement("span");
    titleText.style.cssText = "display:inline-block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0;flex:1 1 auto;";
    titleText.textContent = tr("settingsTitle");
    titleText.title = titleText.textContent;
    title.appendChild(titleText);
    const verBadge = document.createElement("span");
    verBadge.className = "pmtools-version-badge";
    verBadge.textContent = backendVersion ? "v" + backendVersion : "";
    title.appendChild(verBadge);
    if (!backendVersion) {
      rpc("PmtoolsPing").then(function (p) {
        if (p && p.version) {
          backendVersion = p.version;
          if (modal.getAttribute("data-page") === "main") {
            verBadge.textContent = "v" + p.version;
            verBadge.style.removeProperty("display");
          } else {
            verBadge.textContent = "";
            verBadge.style.setProperty("display", "none", "important");
          }
        }
      }).catch(function () {});
    }

    const iconRow = document.createElement("div");
    iconRow.className = "pmtools-icon-row";

    const headerBackBtn = document.createElement("a");
    headerBackBtn.href = "#";
    headerBackBtn.className = "pmtools-icon-btn pmtools-back-btn";
    headerBackBtn.title = tr("back");
    headerBackBtn.innerHTML = '<i class="fa-solid fa-arrow-left"></i>';
    headerBackBtn.style.display = "none";
    iconRow.appendChild(headerBackBtn);

    const restartBtn = document.createElement("a");
    restartBtn.href = "#";
    restartBtn.className = "pmtools-icon-btn";
    restartBtn.title = tr("restartSteam");
    restartBtn.innerHTML = '<i class="fa-solid fa-rotate-right"></i>';
    restartBtn.addEventListener("click", function (e) {
      e.preventDefault();
      overlay.remove();
      askRestartConfirmation();
    });
    iconRow.appendChild(restartBtn);
    // Remove-the-current-game icon button, alongside the restart + close
    // buttons. Only visible while browsing a store page whose game is
    // unlocked — that's where the old big bottom-right remove tile lived.
    const removeBtn = document.createElement("a");
    removeBtn.href = "#";
    removeBtn.className = "pmtools-icon-btn";
    removeBtn.style.cssText = "display:none;background:rgba(214,69,69,0.16);color:#d64545;border-color:rgba(214,69,69,0.45);";
    removeBtn.title = tr("remove");
    removeBtn.innerHTML = '<i class="fa-solid fa-trash-can"></i>';
    removeBtn.addEventListener("click", function (e) {
      e.preventDefault();
      const appid = getAppId();
      if (!appid) return;
      // Confirm with the game's real name, e.g. Remove "Elden Ring" via
      // Pmtools? (falls back to the appid if Steam can't resolve it).
      resolveGameName(appid).then(function (name) {
        confirmPopup(tr("confirmRemoveNamed", { name: name }), tr("confirmContinue"), tr("confirmCancel")).then(function (ok) {
          if (!ok) return;
          rpc("DeletePmtoolsForApp", { appid: appid }).then(function (res) {
            showToast(tr("removed"), !!(res && res.success));
            refreshStoreButton();
            syncSettingsRemove(removeBtn);
          });
        });
      });
    });
    iconRow.appendChild(removeBtn);
    const closeBtn = document.createElement("a");
    closeBtn.href = "#";
    closeBtn.className = "pmtools-icon-btn";
    closeBtn.innerHTML = '<i class="fa-solid fa-xmark"></i>';
    closeBtn.addEventListener("click", function (e) {
      e.preventDefault();
      overlay.remove();
    });
    iconRow.appendChild(closeBtn);
    header.appendChild(title);
    header.appendChild(iconRow);
    modal.appendChild(header);

    const body = document.createElement("div");
    body.style.cssText = "overflow-y:auto;overflow-x:hidden;min-height:0;padding:0.714em 0.786em 0.857em 0.714em;scrollbar-gutter:stable;scroll-behavior:smooth;-webkit-overflow-scrolling:touch;";

    // Main settings page — swapped out entirely when a page (e.g. Unlocked games) is opened
    const mainPage = document.createElement("div");

    const hint = document.createElement("div");
    hint.className = "pmtools-status";
    hint.textContent = tr("settingsHint");
    mainPage.appendChild(hint);

    // Self-update banner — asks the backend for the latest published version
    // and shows a download link when a newer release exists. Silent on failure
    // (a network blip must never look like an update).
    const updateBanner = document.createElement("div");
    updateBanner.className = "pmtools-section";
    updateBanner.style.cssText = "display:none;align-items:center;gap:0.857em;margin:0 0 0.571em 0;padding:0.571em 0.857em;border-radius:0.429em;border:1px solid var(--ig-border);background:var(--ig-bg-tertiary);";
    const updateText = document.createElement("span");
    updateText.style.cssText = "flex:1;color:var(--ig-text);font-size:0.857em;";
    const updateLink = document.createElement("a");
    updateLink.href = "#";
    updateLink.className = "pmtools-icon-btn";
    updateLink.title = tr("updateDownload");
    updateLink.innerHTML = '<i class="fa-solid fa-download"></i>';
    updateLink.style.cssText = "width:auto;padding:0 0.857em;font-size:0.857em;border-radius:0.667em;flex-shrink:0;";
    updateLink.addEventListener("click", function (e) {
      e.preventDefault();
      updateLink.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i>';
      updateLink.style.pointerEvents = "none";
      rpc("SelfUpdatePmtools").then(function (res) {
        if (res && res.ok) {
          updateText.textContent = "Updated to v" + res.version + " — restarting Steam…";
          updateLink.innerHTML = '<i class="fa-solid fa-check"></i>';
        } else {
          updateText.textContent = "Update failed: " + (res && res.error || "unknown");
          updateLink.innerHTML = '<i class="fa-solid fa-download"></i>';
          updateLink.style.pointerEvents = "";
        }
      }).catch(function () {
        updateText.textContent = "Update failed: network error";
        updateLink.innerHTML = '<i class="fa-solid fa-download"></i>';
        updateLink.style.pointerEvents = "";
      });
    });
    updateBanner.appendChild(updateText);
    updateBanner.appendChild(updateLink);
    mainPage.appendChild(updateBanner);

    rpc("GetPmtoolsUpdateInfo").then(function (res) {
      if (res && res.ok && res.updateAvailable) {
        updateText.textContent = tr("updateAvailable", { current: res.current, latest: res.latest });
        updateLink.dataset.url = res.url || "https://pmtools.vercel.app/pmtools.zip";
        updateBanner.style.display = "";
      }
    }).catch(function () {
      // unreachable backend — keep the banner hidden
    });

    // Theme section
    const themeSection = document.createElement("div");
    themeSection.className = "pmtools-section";
    const themeLabel = document.createElement("div");
    themeLabel.className = "pmtools-section-label";
    themeLabel.textContent = tr("theme");
    const chips = document.createElement("div");
    chips.className = "pmtools-themes";
    themeSection.appendChild(themeLabel);
    themeSection.appendChild(chips);
    mainPage.appendChild(themeSection);

    const currentTheme = (loadedSettings && loadedSettings.theme) || "original";
    THEMES.forEach(function (t) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "pmtools-theme-chip" + (t.value === currentTheme ? " active" : "");
      chip.textContent = t.name;
      chip.style.setProperty("background", t.bgSecondary);
      chip.style.setProperty("color", t.accent);
      chip.addEventListener("click", function () {
        chips.querySelectorAll(".pmtools-theme-chip").forEach(function (ch) {
          ch.classList.remove("active");
        });
        chip.classList.add("active");
        loadedSettings = loadedSettings || {};
        loadedSettings.theme = t.value;
        applyTheme();
        rpc("SetPmtoolsSetting", { key: "theme", value: t.value });
      });
      chips.appendChild(chip);
    });

    // UI scale section — manual slider that drives --ig-scale live
    const scaleSection = document.createElement("div");
    scaleSection.className = "pmtools-section";
    scaleSection.style.cssText = "margin:0.857em 0.714em;";
    const scaleLabel = document.createElement("div");
    scaleLabel.className = "pmtools-section-label";
    scaleLabel.textContent = tr("uiScale");
    const scaleRow = document.createElement("div");
    scaleRow.className = "pmtools-source-row";
    scaleRow.style.cssText = "align-items:center;gap:2.5em;padding:0.714em 2em;";
    const scaleSlider = document.createElement("input");
    scaleSlider.type = "range";
    scaleSlider.min = "0.75";
    scaleSlider.max = "1.5";
    scaleSlider.step = "0.05";
    let savedScale = parseFloat(loadedSettings && loadedSettings.uiScale);
    if (!isFinite(savedScale) || savedScale <= 0) savedScale = 1;
    scaleSlider.value = String(Math.min(1.5, Math.max(0.75, savedScale)));
    scaleSlider.style.cssText = "flex:1;accent-color:var(--ig-accent);cursor:pointer;";
    const scaleValue = document.createElement("span");
    scaleValue.className = "pmtools-status";
    scaleValue.style.cssText = "font-size:0.857em;min-width:3.2em;text-align:right;margin:0;";
    function updateScaleLabel() {
      scaleValue.textContent = Math.round(parseFloat(scaleSlider.value) * 100) + "%";
    }
    updateScaleLabel();
    scaleSlider.addEventListener("input", function () {
      document.documentElement.style.setProperty("--ig-scale", scaleSlider.value);
      updateScaleLabel();
    });
    scaleSlider.addEventListener("change", function () {
      loadedSettings = loadedSettings || {};
      loadedSettings.uiScale = scaleSlider.value;
      rpc("SetPmtoolsSetting", { key: "uiScale", value: scaleSlider.value });
    });
    scaleRow.appendChild(scaleSlider);
    scaleRow.appendChild(scaleValue);
    scaleSection.appendChild(scaleLabel);
    scaleSection.appendChild(scaleRow);
    mainPage.appendChild(scaleSection);

    // ── Helper: poll cloud worker task ──────────────────────────────────────
    function pollCloudTask(taskId, onProgress, onDone) {
      let timer = null;
      let active = true;
      const poll = async function () {
        if (!active) return;
        try {
          const res = await rpc("GetPmtoolsCloudTaskStatus", { taskId: taskId });
          if (res && res.success && res.task) {
            const t = res.task;
            if (onProgress) onProgress(t);
            if (t.status === "completed" || t.status === "failed") {
              active = false;
              if (timer) clearInterval(timer);
              if (onDone) onDone(t);
              return;
            }
          }
        } catch (_) {}
      };
      timer = setInterval(poll, 700);
      poll();
    }

    // Sources section
    const srcSection = document.createElement("div");
    srcSection.className = "pmtools-section";
    const srcLabel = document.createElement("div");
    srcLabel.className = "pmtools-section-label";
    srcLabel.textContent = tr("sources");
    const srcStatus = document.createElement("div");
    srcStatus.className = "pmtools-status";
    srcStatus.style.cssText = "margin:0 0 0.571em 0;font-size:0.786em;";
    const srcList = document.createElement("div");
    srcSection.appendChild(srcLabel);
    srcSection.appendChild(srcStatus);
    srcSection.appendChild(srcList);
    mainPage.appendChild(srcSection);

    // Inline API-key editor (shown on key-based sources like Hubcap). Clicking
    // Save calls the backend, then the list re-renders with fresh quota data.
    function openKeyEditor(row, s) {
      const old = row.querySelector(".pmtools-key-editor");
      if (old) old.remove();
      const editor = document.createElement("div");
      editor.className = "pmtools-key-editor";
      editor.style.cssText = "display:flex;gap:0.429em;align-items:center;margin-top:0.571em;";
      const input = document.createElement("input");
      input.type = "text";
      input.spellcheck = false;
      input.autocomplete = "off";
      input.placeholder = tr("apiKeyPlaceholder");
      input.style.cssText =
        "flex:1;min-width:0;background-color:var(--ig-bg-tertiary);color:var(--ig-text);" +
        "border:1px solid var(--ig-border);border-radius:0.429em;padding:0.286em 0.571em;font-size:0.786em;";
      const saveBtn = document.createElement("button");
      saveBtn.type = "button";
      saveBtn.textContent = tr("apiKeySave");
      saveBtn.className = "pmtools-theme-chip";
      saveBtn.style.cssText = "font-size:0.786em;padding:0.3em 0.8em;";
      const cancelBtn = document.createElement("button");
      cancelBtn.type = "button";
      cancelBtn.textContent = tr("apiKeyCancel");
      cancelBtn.className = "pmtools-theme-chip";
      cancelBtn.style.cssText = "font-size:0.786em;padding:0.3em 0.8em;";
      cancelBtn.addEventListener("click", function () {
        editor.remove();
      });
      saveBtn.addEventListener("click", async function () {
        const key = input.value.trim();
        if (!key) {
          input.focus();
          return;
        }
        saveBtn.disabled = true;
        srcStatus.textContent = "";
        const res = await rpc("SetPmtoolsHubcapKey", { key: key });
        if (res && res.success) {
          renderSources();
          srcStatus.textContent = tr("apiKeySaved");
        } else {
          srcStatus.textContent = tr("apiKeyError");
          srcStatus.className = "pmtools-status error";
          saveBtn.disabled = false;
        }
      });
      editor.appendChild(input);
      editor.appendChild(saveBtn);
      editor.appendChild(cancelBtn);
      row.appendChild(editor);
      input.focus();
    }

    function renderSources() {
      srcStatus.textContent = "";
      srcStatus.className = "pmtools-status";
      // Show skeleton source rows while loading
      srcList.innerHTML = "";
      for (let i = 0; i < 3; i++) {
        const skel = document.createElement("div");
        skel.className = "pmtools-source-row pmtools-skeleton pmtools-skel-source";
        skel.style.animationDelay = (i * 40) + "ms";
        skel.innerHTML = '<div style="display:flex;align-items:center;width:100%;gap:0.571em;"><div class="pmtools-skel-name"></div><div class="pmtools-skel-badge"></div><div class="pmtools-skel-toggle"></div></div>';
        srcList.appendChild(skel);
      }
      rpc("GetPmtoolsSourceUsage").then(function (res) {
        const sources = (res && res.sources) || [];
        srcList.innerHTML = "";
        if (sources.length === 0) {
          const empty = document.createElement("div");
          empty.className = "pmtools-status error";
          empty.textContent = tr("emptySources");
          srcList.appendChild(empty);
          return;
        }
        sources.forEach(function (s) {
          const row = document.createElement("div");
          row.className = "pmtools-source-row" + (s.enabled === false ? " disabled" : "");
          row.style.cssText = "flex-direction:column;align-items:stretch;";
          const top = document.createElement("div");
          top.style.cssText = "display:flex;justify-content:space-between;align-items:center;gap:0.571em;";
          const name = document.createElement("span");
          name.textContent = s.name;
          const right = document.createElement("span");
          right.style.cssText = "display:inline-flex;align-items:center;gap:0.571em;";
          const badge = document.createElement("span");
          badge.className = s.enabled === false ? "enabled off" : "enabled";
          badge.textContent = s.enabled === false ? tr("sourceDisabled") : tr("ready");
          // Per-source enable/disable toggle switch.
          const toggle = document.createElement("button");
          toggle.type = "button";
          toggle.className = "pmtools-source-toggle" + (s.enabled === false ? "" : " on");
          toggle.setAttribute("role", "switch");
          toggle.setAttribute("aria-checked", String(s.enabled !== false));
          toggle.title = s.enabled === false ? tr("sourceToggleOn") : tr("sourceToggleOff");            toggle.addEventListener("click", function (e) {
            e.stopPropagation(); // don't expand the details row
            const next = s.enabled === false;
            toggle.disabled = true;
            // Support direct object args and wrapped payload for both bridges
            const toggleArgs = {
              id: s.id,
              enabled: next,
              payload: JSON.stringify({ id: s.id, enabled: next })
            };
            rpc("SetPmtoolsSourceEnabled", toggleArgs).then(function (res) {
              if (res && res.success) {
                // Update this row in place — a full renderSources() reload
                // flashes skeletons and refetches usage, which is visible.
                s.enabled = next;
                toggle.disabled = false;
                toggle.classList.toggle("on", next);
                toggle.setAttribute("aria-checked", String(next));
                toggle.title = next ? tr("sourceToggleOn") : tr("sourceToggleOff");
                badge.textContent = next ? tr("ready") : tr("sourceDisabled");
                badge.className = next ? "enabled" : "enabled off";
                row.classList.toggle("disabled", !next);
              } else {
                toggle.disabled = false;
                srcStatus.textContent = tr("sourceToggleFailed");
                srcStatus.className = "pmtools-status error";
              }
            });
          });
          right.appendChild(badge);
          right.appendChild(toggle);
          top.appendChild(name);
          top.appendChild(right);
          row.appendChild(top);
          // Hubcap's status line (quota + key expiry, or the no-key hint) is
          // ALWAYS visible — only the health details are hidden behind a click.
          if (s.id === "hubcap") {
            // Check key status first — independent if-blocks so each
            // state renders regardless of the others.
            if (s.keyInvalid) {
              // Server rejected the stored key (401/403) — say so instead of
              // showing a bogus usage line or an endless "checking…".
              const bad = document.createElement("div");
              bad.style.cssText = "margin-top:0.364em;padding:0.5em 0.714em;border-radius:0.429em;font-size:0.786em;background:rgba(255,80,60,0.12);border:1px solid rgba(255,80,60,0.3);color:#ff8866;display:flex;align-items:center;gap:0.5em;flex-wrap:wrap;";
              var badIcon = document.createElement("span");
              badIcon.innerHTML = '<i class="fa-solid fa-key" style="color:#ff6644;"></i>';
              bad.appendChild(badIcon);
              var badText = document.createElement("span");
              badText.textContent = "API key is invalid or expired.";
              bad.appendChild(badText);
              var badLink = document.createElement("a");
              badLink.href = "https://hubcapmanifest.com";
              badLink.target = "_blank";
              badLink.textContent = "Get new key \u2192";
              badLink.style.cssText = "color:var(--ig-accent);text-decoration:underline;font-weight:500;margin-left:auto;";
              bad.appendChild(badLink);
              row.appendChild(bad);
            }
            if (!s.hasKey) {
              const hint = document.createElement("div");
              hint.className = "kind warn";
              hint.style.cssText = "margin-top:0.364em;font-size:0.786em;display:flex;align-items:center;gap:0.5em;flex-wrap:wrap;";
              hint.textContent = tr("noApiKey");
              var noKeyLink = document.createElement("a");
              noKeyLink.href = "https://hubcapmanifest.com";
              noKeyLink.target = "_blank";
              noKeyLink.textContent = "Get key \u2192";
              noKeyLink.style.cssText = "color:var(--ig-accent);text-decoration:underline;font-weight:500;margin-left:auto;";
              hint.appendChild(noKeyLink);
              row.appendChild(hint);
            }
            // Discord community link for Hubcap
            var discordRow = document.createElement("div");
            discordRow.style.cssText = "margin-top:0.364em;font-size:0.714em;display:flex;align-items:center;gap:0.35em;";
            var discordIcon = document.createElement("span");
            discordIcon.innerHTML = '<i class="fa-brands fa-discord" style="color:#5865F2;"></i>';
            discordRow.appendChild(discordIcon);
            var discordLink = document.createElement("a");
            discordLink.href = "https://discord.gg/hubcapsmanifest";
            discordLink.target = "_blank";
            discordLink.textContent = "Join Discord";
            discordLink.style.cssText = "color:var(--ig-text-secondary);text-decoration:none;transition:color 0.2s;";
            discordLink.addEventListener("mouseenter", function () { discordLink.style.color = "#5865F2"; });
            discordLink.addEventListener("mouseleave", function () { discordLink.style.color = "var(--ig-text-secondary)"; });
            discordRow.appendChild(discordLink);
            row.appendChild(discordRow);
          }
          // Show usage for ALL sources that report it (hubcap, ignihub, etc.)
          if (s.usage) {
            const usageEl = document.createElement("div");
            usageEl.className = "kind";
            usageEl.style.cssText = "margin-top:0.364em;font-size:0.786em;";
            let usageText = tr("usageShort", { remaining: s.usage.remaining, limit: s.usage.limit });
            const expRaw = String(s.usage.expiresAt || "");
            if (/^\d{4}-\d{2}-\d{2}/.test(expRaw)) {
              usageText += " \u00b7 " + tr("usageKeyExpires", { date: expRaw.slice(0, 10) });
            }
            usageEl.textContent = usageText;
            row.appendChild(usageEl);
          } else if (s.hasKey && !s.usage && !s.keyInvalid) {
            // Usage not loaded yet - retry after a short delay
            const _retryId = s.id;
            const checkEl = document.createElement("div");
            checkEl.className = "kind";
            checkEl.style.cssText = "margin-top:0.364em;font-size:0.786em;display:flex;align-items:center;gap:0.4em;color:var(--ig-text-secondary);";
            checkEl.innerHTML = '<i class="fa-solid fa-key" style="font-size:0.8em;opacity:0.7;"></i> <span>Checking\u2026</span>';
            row.appendChild(checkEl);
            setTimeout(function() {
              rpc("GetPmtoolsSourceUsage").then(function(r2) {
                var found = ((r2 && r2.sources) || []).find(function(x) { return x.id === _retryId; });
                if (found && found.usage) {
                  checkEl.remove();
                  var u2 = document.createElement("div");
                  u2.className = "kind";
                  u2.style.cssText = "margin-top:0.364em;font-size:0.786em;";
                  var t2 = tr("usageShort", { remaining: found.usage.remaining, limit: found.usage.limit });
                  if (found.usage.expiresAt) {
                    t2 += " \u00b7 " + tr("usageKeyExpires", { date: String(found.usage.expiresAt).slice(0, 10) });
                  }
                  u2.textContent = t2;
                  row.appendChild(u2);
                } else if (found && found.keyInvalid) {
                  checkEl.remove();
                  renderSources();
                } else {
                  checkEl.innerHTML = '<i class="fa-solid fa-circle-exclamation" style="color:var(--ig-text-secondary);"></i> <span>' + tr("usageUnavailable") + '</span>';
                }
              }).catch(function() {
                checkEl.innerHTML = '<i class="fa-solid fa-circle-exclamation" style="color:var(--ig-text-secondary);"></i> <span>' + tr("usageUnavailable") + '</span>';
              });
            }, 2000);
          }

          // Health details live in a hidden container revealed on click.
          const details = document.createElement("div");
          details.className = "pmtools-source-details";
          details.style.display = "none";
          // health meta line (latency, availability, last success/failure)
          const h = s.health || {};
          function timeText(ts) {
            if (!ts) return tr("healthNever");
            const d = new Date(ts * 1000);
            return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
          }
          const metaBits = [];
          if (h.lastMs != null) metaBits.push(tr("healthLatency", { ms: h.lastMs }));
          if (h.availabilityPct != null) metaBits.push(tr("healthAvailability", { pct: h.availabilityPct }));
          if (h.lastOk) metaBits.push(tr("healthLastOk", { time: timeText(h.lastOk) }));
          if (h.lastFail) metaBits.push(tr("healthLastFail", { time: timeText(h.lastFail) }));
          if (h.lastRefresh) metaBits.push(tr("healthRefresh", { time: timeText(h.lastRefresh) }));
          if (metaBits.length > 0) {
            const meta = document.createElement("div");
            meta.className = "kind";
            meta.style.cssText = "margin-top:0.364em;font-size:0.786em;";
            meta.textContent = metaBits.join(" · ");
            details.appendChild(meta);
          } else {
            // No health recorded yet (fresh install, or source disabled so it
            // is never probed) — say so instead of revealing an empty panel.
            const pending = document.createElement("div");
            pending.className = "kind";
            pending.style.cssText = "margin-top:0.364em;font-size:0.786em;";
            pending.textContent = tr("healthPending");
            details.appendChild(pending);
          }
          row.appendChild(details);
          // Every source card is clickable (glow on hover). Single-click
          // expands/collapses the health details only. Key-gated sources get
          // an explicit "Edit key" button inside the details panel.
          if (s.keyGated) {
            const editBtn = document.createElement("button");
            editBtn.type = "button";
            editBtn.textContent = tr("apiKeyUpdate");
            editBtn.className = "pmtools-theme-chip";
            editBtn.style.cssText = "font-size:0.786em;padding:0.3em 0.8em;margin-top:0.571em;";
            editBtn.addEventListener("click", function (e) {
              e.stopPropagation();
              openKeyEditor(details, s);
            });
            details.appendChild(editBtn);
          }
          row.classList.add("pmtools-clickable");
          row.style.cursor = "pointer";
          row.title = tr("detailsHint");
          row.addEventListener("click", function (e) {
            if (e.target && e.target.closest && e.target.closest(".pmtools-key-editor")) return;
            const isOpen = details.style.display !== "none";
            if (isOpen) {
              details.style.animation = "pmtoolsDetailsOut 0.2s ease-out forwards";
              setTimeout(function () { details.style.display = "none"; details.style.animation = ""; }, 200);
            } else {
              details.style.display = "block";
              details.style.animation = "pmtoolsDetailsIn 0.25s cubic-bezier(0.22,1,0.36,1)";
            }
          });
          srcList.appendChild(row);
        });
      }).catch(function () {
        srcList.innerHTML = "";
        const box = document.createElement("div");
        box.className = "pmtools-error-box";
        const icon = document.createElement("div");
        icon.className = "pmtools-error-icon";
        icon.innerHTML = '<i class="fa-solid fa-plug-circle-xmark"></i>';
        box.appendChild(icon);
        const msg = document.createElement("div");
        msg.className = "pmtools-error-msg";
        msg.textContent = tr("sourcesLoadFailed");
        box.appendChild(msg);
        const retry = document.createElement("button");
        retry.type = "button";
        retry.className = "pmtools-retry-btn";
        retry.textContent = tr("retry");
        retry.addEventListener("click", function () { renderSources(); });
        box.appendChild(retry);
        srcList.appendChild(box);
      });
    }
    renderSources();

    // Unlocked games section — button switches the whole body to the list page
    const installedSection = document.createElement("div");
    installedSection.className = "pmtools-section pmtools-panel";
    const installedToggle = document.createElement("button");
    installedToggle.type = "button";
    installedToggle.className = "pmtools-unlocked-toggle";
    const installedToggleIcon = document.createElement("i");
    installedToggleIcon.className = "fa-solid fa-gamepad";
    const installedToggleLabel = document.createElement("span");
    installedToggleLabel.textContent = tr("installedTitle");
    const installedBadge = document.createElement("span");
    installedBadge.className = "pmtools-unlocked-badge";
    installedBadge.textContent = "0";
    installedToggle.appendChild(installedToggleIcon);
    installedToggle.appendChild(installedToggleLabel);
    installedToggle.appendChild(installedBadge);
    installedSection.appendChild(installedToggle);

    const unlockedPage = document.createElement("div");
    unlockedPage.style.display = "none";
    const installedToolbar = document.createElement("div");
    installedToolbar.style.cssText = "display:flex;gap:0.571em;margin-bottom:0.571em;align-items:center;";
    const installedSearch = document.createElement("input");
    installedSearch.type = "search";
    installedSearch.placeholder = tr("installedSearch");
    installedSearch.style.cssText =
      "flex:1;min-width:0;background-color:var(--ig-bg-tertiary);color:var(--ig-text);" +
      "border:1px solid var(--ig-border);border-radius:0.571em;padding:0.429em 0.714em;font-size:0.857em;";
    installedToolbar.appendChild(installedSearch);
    const refreshTitles = document.createElement("button");
    refreshTitles.type = "button";
    refreshTitles.className = "pmtools-icon-btn";
    refreshTitles.title = tr("titleRefresh");
    refreshTitles.innerHTML = '<i class="fa-solid fa-rotate-right"></i>';
    installedToolbar.appendChild(refreshTitles);

    // Bulk selection: select-all checkbox + bulk-remove button
    const bulkActions = document.createElement("div");
    bulkActions.style.cssText = "display:none;gap:0.429em;align-items:center;margin-left:0.286em;";
    const selectAllCb = document.createElement("input");
    selectAllCb.type = "checkbox";
    selectAllCb.style.cssText = "accent-color:var(--ig-accent);width:1em;height:1em;cursor:pointer;";
    selectAllCb.title = "Select all visible";
    const bulkRemoveBtn = document.createElement("button");
    bulkRemoveBtn.type = "button";
    bulkRemoveBtn.className = "pmtools-icon-btn";
    bulkRemoveBtn.title = "Remove selected";
    bulkRemoveBtn.innerHTML = '<i class="fa-solid fa-trash-can" style="color:var(--ig-text-secondary);"></i>';
    bulkRemoveBtn.style.display = "none";
    const bulkCount = document.createElement("span");
    bulkCount.style.cssText = "font-size:0.786em;color:var(--ig-text-secondary);white-space:nowrap;";
    bulkCount.textContent = "0 selected";
    bulkActions.appendChild(selectAllCb);
    bulkActions.appendChild(bulkRemoveBtn);
    bulkActions.appendChild(bulkCount);
    installedToolbar.appendChild(bulkActions);

    // Meta row: count + filter chips + sort
    const installedMeta = document.createElement("div");
    installedMeta.style.cssText = "display:flex;gap:0.571em;align-items:center;margin-bottom:0.571em;flex-wrap:wrap;";
    const installedCount = document.createElement("span");
    installedCount.className = "kind";
    installedCount.style.cssText = "font-size:0.786em;color:var(--ig-text-secondary);";
    installedCount.textContent = tr("unlockedCount", { count: 0 });
    installedMeta.appendChild(installedCount);
    const installedFilterWrap = document.createElement("div");
    installedFilterWrap.style.cssText = "display:flex;gap:0.286em;margin-left:auto;";
    let installedFilter = "all";
    ["all", "enabled", "disabled"].forEach(function (f) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "pmtools-theme-chip" + (f === "all" ? " active" : "");
      chip.style.cssText = "font-size:0.714em;padding:0.3em 0.8em;";
      chip.textContent = tr("filter" + f.charAt(0).toUpperCase() + f.slice(1));
      chip.addEventListener("click", function () {
        installedFilter = f;
        installedFilterWrap.querySelectorAll(".pmtools-theme-chip").forEach(function (c) { c.classList.remove("active"); });
        chip.classList.add("active");
        renderInstalled();
      });
      installedFilterWrap.appendChild(chip);
    });
    installedMeta.appendChild(installedFilterWrap);
    const installedSort = document.createElement("select");
    installedSort.style.cssText = "font-size:0.786em;max-width:10.5em;";
    [["recent", "sortRecent"], ["alpha", "sortAlpha"]].forEach(function (opt) {
      const o = document.createElement("option");
      o.value = opt[0];
      o.textContent = tr(opt[1]);
      installedSort.appendChild(o);
    });
    installedSort.addEventListener("change", renderInstalled);
    installedMeta.appendChild(installedSort);

    const installedList = document.createElement("div");
    unlockedPage.appendChild(installedToolbar);
    unlockedPage.appendChild(installedMeta);
    unlockedPage.appendChild(installedList);

    // Flag the old page for a quick fade-out, then reveal the new one with its
    // slide-in. Exit is fast so the swap never feels sluggish.
    function swapPage(hide, show, enterClass) {
      hide.classList.add("pmtools-page-out");
      setTimeout(function () {
        hide.classList.remove("pmtools-page-out", "pmtools-page-in-left", "pmtools-page-in-right");
        hide.style.display = "none";
        hide.style.willChange = "";
        show.style.display = "block";
        show.classList.remove("pmtools-page-in-left", "pmtools-page-in-right");
        void show.offsetWidth;
        show.classList.add(enterClass);
        // Only show tool version badge on main UI page, hide on all subpages
        const isMain = (show === mainPage);
        if (modal) {
          modal.setAttribute("data-page", isMain ? "main" : "subpage");
        }
        if (headerBackBtn) {
          headerBackBtn.style.display = isMain ? "none" : "";
        }
        if (verBadge) {
          if (isMain) {
            verBadge.style.removeProperty("display");
            verBadge.textContent = backendVersion ? "v" + backendVersion : "";
          } else {
            verBadge.style.setProperty("display", "none", "important");
            verBadge.textContent = "";
          }
        }
        // Re-trigger section stagger on the new page
        show.querySelectorAll(".pmtools-section").forEach(function (sec, i) {
          sec.style.animationDelay = (i * 35) + "ms";
        });
      }, 70);
    }

    installedToggle.addEventListener("click", function () {
      // Keep the box width identical to the settings page: the modal is
      // fit-width by default, but the unlocked page is usually narrower —
      // pin its min-width so the box never shrinks when switching.
      if (modal) modal.setAttribute("data-page", "subpage");
      if (headerBackBtn) headerBackBtn.style.display = "";
      if (verBadge) {
        verBadge.style.setProperty("display", "none", "important");
        verBadge.textContent = "";
      }
      unlockedPage.style.minWidth = mainPage.offsetWidth + "px";
      swapPage(mainPage, unlockedPage, "pmtools-page-in-right");
      titleText.style.animation = "none";
      void titleText.offsetWidth;
      titleText.style.animation = "pmtoolsTitleSwap 0.3s ease";
      titleText.textContent = tr("installedTitle");
      titleText.title = titleText.textContent;
      if (installedSearch.value) installedSearch.focus();
    });

    mainPage.appendChild(installedSection);

    // ── Cloud Vault navigation panel on Main Page ───────────────────────────
    const cloudVaultSection = document.createElement("div");
    cloudVaultSection.className = "pmtools-section pmtools-panel";
    const cloudVaultToggle = document.createElement("button");
    cloudVaultToggle.type = "button";
    cloudVaultToggle.className = "pmtools-unlocked-toggle pmtools-vault-toggle";
    const cloudVaultToggleIcon = document.createElement("i");
    cloudVaultToggleIcon.className = "fa-solid fa-cloud";
    const cloudVaultToggleLabel = document.createElement("span");
    cloudVaultToggleLabel.textContent = tr("vaultTitle");
    const cloudVaultBadge = document.createElement("span");
    cloudVaultBadge.className = "pmtools-unlocked-badge";
    cloudVaultBadge.textContent = "…";
    cloudVaultToggle.appendChild(cloudVaultToggleIcon);
    cloudVaultToggle.appendChild(cloudVaultToggleLabel);
    cloudVaultToggle.appendChild(cloudVaultBadge);
    cloudVaultSection.appendChild(cloudVaultToggle);
    mainPage.appendChild(cloudVaultSection);

    function updateCloudVaultBadge(cfg) {
      if (!cfg || !cfg.enabled) {
        cloudVaultBadge.textContent = tr("vaultStatusDisabled");
        return;
      }
      if (cfg.provider === "gdrive") {
        cloudVaultBadge.textContent = "Google Drive";
      } else if (cfg.provider === "webdav") {
        cloudVaultBadge.textContent = "WebDAV";
      } else if (cfg.provider === "local") {
        cloudVaultBadge.textContent = "Local";
      } else {
        cloudVaultBadge.textContent = tr("vaultStatusNotConfigured");
      }
    }

    // ── Dedicated Cloud Vault Sub-page ──────────────────────────────────────
    const cloudVaultPage = document.createElement("div");
    cloudVaultPage.style.display = "none";

    cloudVaultToggle.addEventListener("click", function () {
      if (modal) modal.setAttribute("data-page", "subpage");
      if (headerBackBtn) headerBackBtn.style.display = "";
      if (verBadge) {
        verBadge.style.setProperty("display", "none", "important");
        verBadge.textContent = "";
      }
      cloudVaultPage.style.minWidth = mainPage.offsetWidth + "px";
      swapPage(mainPage, cloudVaultPage, "pmtools-page-in-right");
      titleText.style.animation = "none";
      void titleText.offsetWidth;
      titleText.style.animation = "pmtoolsTitleSwap 0.3s ease";
      titleText.textContent = tr("vaultTitle");
      titleText.title = titleText.textContent;
    });

    function navigateBackToMain() {
      if (modal) modal.setAttribute("data-page", "main");
      if (verBadge) {
        verBadge.style.removeProperty("display");
        verBadge.textContent = backendVersion ? "v" + backendVersion : "";
      }
      if (headerBackBtn) headerBackBtn.style.display = "none";
      const activeSubPage = (cloudVaultPage && cloudVaultPage.style.display !== "none")
        ? cloudVaultPage
        : unlockedPage;
      swapPage(activeSubPage, mainPage, "pmtools-page-in-left");
      titleText.style.animation = "none";
      void titleText.offsetWidth;
      titleText.style.animation = "pmtoolsTitleSwap 0.3s ease";
      titleText.textContent = tr("settingsTitle");
      titleText.title = titleText.textContent;
    }

    headerBackBtn.addEventListener("click", function (e) {
      e.preventDefault();
      navigateBackToMain();
    });

    // ── Progress indicator ──────────────────────────────────────────────────
    const taskStatusBox = document.createElement("div");
    taskStatusBox.style.cssText = "display:none;background:var(--ig-bg-tertiary);border:1px solid var(--ig-border);border-radius:0.5em;padding:0.571em 0.857em;margin-bottom:0.857em;";
    const taskMsg = document.createElement("div");
    taskMsg.style.cssText = "font-size:0.786em;color:var(--ig-text);margin-bottom:0.357em;display:flex;justify-content:space-between;";
    const taskBarOuter = document.createElement("div");
    taskBarOuter.style.cssText = "width:100%;height:4px;background:rgba(255,255,255,0.08);border-radius:2px;overflow:hidden;";
    const taskBarInner = document.createElement("div");
    taskBarInner.style.cssText = "width:0%;height:100%;background:var(--ig-accent);transition:width 0.3s ease;";
    taskBarOuter.appendChild(taskBarInner);
    taskStatusBox.appendChild(taskMsg);
    taskStatusBox.appendChild(taskBarOuter);

    function showTaskProgress(message, pct, isError) {
      taskStatusBox.style.display = "block";
      taskMsg.innerHTML = `<span>${message}</span><span>${pct}%</span>`;
      taskBarInner.style.width = pct + "%";
      taskBarInner.style.background = isError ? "#d64545" : "var(--ig-accent)";
    }

    function hideTaskProgress() {
      setTimeout(function () {
        taskStatusBox.style.display = "none";
      }, 3500);
    }
    cloudVaultPage.appendChild(taskStatusBox);

    // ── Section 1: Storage Target & Credentials ─────────────────────────────
    const storageSection = document.createElement("div");
    storageSection.className = "pmtools-section pmtools-panel";

    const storageLabel = document.createElement("div");
    storageLabel.className = "pmtools-section-label";
    storageLabel.textContent = tr("vaultStorageSection");
    storageSection.appendChild(storageLabel);

    let activeProvider = "local";
    const providerChips = document.createElement("div");
    providerChips.style.cssText = "display:flex;gap:0.429em;flex-wrap:wrap;margin-bottom:0.857em;";

    const providerList = [
      { id: "local", icon: "fa-folder-open", name: tr("vaultLocal") },
      { id: "gdrive", icon: "fa-brands fa-google-drive", name: tr("vaultGdrive") },
      { id: "webdav", icon: "fa-server", name: tr("vaultWebdav") },
    ];

    const chipEls = {};
    providerList.forEach(function (p) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "pmtools-theme-chip" + (p.id === activeProvider ? " active" : "");
      chip.style.cssText = "font-size:0.786em;padding:0.35em 0.857em;display:inline-flex;align-items:center;gap:0.4em;";
      const iconClass = p.icon.indexOf("fa-") === 0 && (p.icon.indexOf("fa-brands") !== -1 || p.icon.indexOf("fa-solid") !== -1) ? p.icon : ("fa-solid " + p.icon);
      chip.innerHTML = '<i class="' + iconClass + '"></i><span>' + p.name + '</span>';
      chip.addEventListener("click", function () {
        activeProvider = p.id;
        for (const k in chipEls) {
          chipEls[k].classList.toggle("active", k === activeProvider);
        }
        renderConfigFields(activeProvider);
      });
      chipEls[p.id] = chip;
      providerChips.appendChild(chip);
    });
    storageSection.appendChild(providerChips);

    const configContainer = document.createElement("div");
    configContainer.style.cssText = "display:flex;flex-direction:column;gap:0.5em;margin-bottom:0.857em;";

    function createInputRow(labelText, placeholder, isPassword) {
      const row = document.createElement("div");
      row.style.cssText = "display:flex;align-items:center;gap:0.714em;";
      const lbl = document.createElement("span");
      lbl.style.cssText = "font-size:0.786em;color:var(--ig-text-secondary);min-width:7.6em;flex-shrink:0;";
      lbl.textContent = labelText;
      const inp = document.createElement("input");
      inp.type = isPassword ? "password" : "text";
      inp.spellcheck = false;
      inp.autocomplete = "off";
      inp.placeholder = placeholder;
      inp.style.cssText = "flex:1;min-width:0;background:var(--ig-bg-tertiary);color:var(--ig-text);border:1px solid var(--ig-border);border-radius:0.429em;padding:0.357em 0.571em;font-size:0.8em;outline:none;";
      row.appendChild(lbl);
      row.appendChild(inp);
      return { row: row, input: inp };
    }

    const localInput = createInputRow("Directory", "e.g. D:\\MyVault or \\\\NAS\\Share\\Vault", false);
    const webdavUrl = createInputRow("WebDAV URL", "https://my-cloud.com/remote.php/dav/files/user/Vault", false);
    const webdavUser = createInputRow("Username", "username", false);
    const webdavPass = createInputRow("Password", "password or token", true);

    const providerHint = document.createElement("div");
    providerHint.style.cssText = "font-size:0.75em;color:var(--ig-text-secondary);opacity:0.8;margin-top:0.2em;";

    function renderConfigFields(provider) {
      configContainer.innerHTML = "";
      if (provider === "local") {
        configContainer.appendChild(localInput.row);
        providerHint.textContent = "Manifests and saves sync directly to your chosen local directory or network SMB/NFS share.";
      } else if (provider === "gdrive") {
        const autoCard = document.createElement("div");
        autoCard.className = "pmtools-gdrive-autocard";
        autoCard.style.cssText = "display:flex;flex-direction:column;gap:0.6em;padding:0.85em 1em;background:var(--ig-bg-tertiary);border:1px solid var(--ig-border);border-radius:0.5em;font-size:0.85em;";
        autoCard.innerHTML = `
          <div style="display:flex;align-items:center;gap:0.6em;color:var(--ig-text);font-weight:600;font-size:13px;">
            <i class="fa-brands fa-google-drive" style="color:#4285F4;font-size:15px;"></i>
            <span>${activeLang === "zh-Hans" ? "Google 云端硬盘自动同步" : "Google Drive Automated Sync"}</span>
          </div>
          <div style="color:var(--ig-text-secondary);font-size:12px;line-height:1.45;">
            ${activeLang === "zh-Hans" 
              ? "Pmtools 会自动定位您的 Google 云端硬盘基目录，并在其中管理 <b>Pmtools</b> 目录架构：" 
              : "Pmtools automatically locates your Google Drive base directory and manages the <b>Pmtools</b> folder structure:"}
          </div>
          <div class="pmtools-file-tree" style="display:flex;flex-direction:column;gap:6px;padding:9px 12px;background:rgba(0,0,0,0.35);border:1px solid rgba(255,255,255,0.08);border-radius:6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;-webkit-font-smoothing:antialiased;">
            <div style="display:flex;align-items:center;gap:8px;font-size:12px;font-weight:600;color:var(--ig-text);">
              <i class="fa-solid fa-folder-open" style="color:#fbbf24;font-size:13px;width:14px;text-align:center;"></i>
              <span>[Google Drive] <span style="opacity:0.4;">\\</span> <span style="color:var(--ig-accent,#38bdf8);font-weight:700;">Pmtools</span></span>
            </div>
            <div style="display:flex;flex-direction:column;gap:6px;margin-left:7px;padding-left:14px;border-left:1.5px solid rgba(255,255,255,0.18);">
              <div style="display:flex;align-items:center;gap:8px;position:relative;font-size:12px;line-height:1.4;">
                <span style="position:absolute;left:-14px;top:50%;width:8px;height:1.5px;background:rgba(255,255,255,0.18);"></span>
                <i class="fa-solid fa-folder" style="color:#38bdf8;font-size:12px;width:14px;text-align:center;"></i>
                <span style="font-weight:600;color:var(--ig-text);letter-spacing:0.02em;">vault/</span>
                <span style="color:var(--ig-text-secondary);font-size:11px;opacity:0.85;">${activeLang === "zh-Hans" ? "— 存放游戏清单及配置" : "— game manifests & unlock config"}</span>
              </div>
              <div style="display:flex;align-items:center;gap:8px;position:relative;font-size:12px;line-height:1.4;">
                <span style="position:absolute;left:-14px;top:50%;width:8px;height:1.5px;background:rgba(255,255,255,0.18);"></span>
                <i class="fa-solid fa-folder" style="color:#34d399;font-size:12px;width:14px;text-align:center;"></i>
                <span style="font-weight:600;color:var(--ig-text);letter-spacing:0.02em;">save/</span>
                <span style="color:var(--ig-text-secondary);font-size:11px;opacity:0.85;">${activeLang === "zh-Hans" ? "— 存放游戏存档文件" : "— game save files & userdata"}</span>
              </div>
            </div>
          </div>
          <div style="display:flex;align-items:center;gap:6px;font-size:11.5px;color:var(--ig-text-secondary);opacity:0.85;line-height:1.4;">
            <i class="fa-solid fa-circle-check" style="color:#10b981;font-size:12px;"></i>
            <span>${activeLang === "zh-Hans"
              ? "无需手动配置路径。请确保已在当前电脑上运行 Google 云端硬盘客户端。"
              : "Zero configuration required. Ensure Google Drive for Desktop is running on your PC."}</span>
          </div>
        `;
        configContainer.appendChild(autoCard);
        providerHint.textContent = "";
      } else if (provider === "webdav") {
        configContainer.appendChild(webdavUrl.row);
        configContainer.appendChild(webdavUser.row);
        configContainer.appendChild(webdavPass.row);
        providerHint.textContent = "Direct HTTP WebDAV sync to Nextcloud, ownCloud, Fastmail, or custom WebDAV servers.";
      }
      configContainer.appendChild(providerHint);
    }
    storageSection.appendChild(configContainer);

    const saveTestBtn = document.createElement("button");
    saveTestBtn.type = "button";
    saveTestBtn.className = "pmtools-btn primary";
    saveTestBtn.style.cssText = "font-size:0.857em;padding:0.35em 0.95em;";
    saveTestBtn.innerHTML = '<i class="fa-solid fa-plug" style="margin-right:0.35em;"></i>' + tr("vaultSaveTest");

    saveTestBtn.addEventListener("click", async function () {
      saveTestBtn.disabled = true;
      showTaskProgress("Saving configuration...", 20, false);

      const payload = {
        provider: activeProvider,
        enabled: true,
        localPath: localInput.input.value.trim(),
        gdrive: {},
        webdav: {
          url: webdavUrl.input.value.trim(),
          username: webdavUser.input.value.trim(),
          password: webdavPass.input.value.trim(),
        },
      };

      const setRes = await rpc("SetPmtoolsCloudConfig", payload);
      if (!setRes || !setRes.success) {
        saveTestBtn.disabled = false;
        showTaskProgress("Failed to save config: " + (setRes && setRes.error), 100, true);
        hideTaskProgress();
        return;
      }

      updateCloudVaultBadge(payload);

      showTaskProgress("Testing connection to storage...", 50, false);
      const testRes = await rpc("TestPmtoolsCloudConnection");
      if (testRes && testRes.success && testRes.taskId) {
        pollCloudTask(testRes.taskId, function (t) {
          showTaskProgress(t.message || "Testing...", t.progress || 50, false);
        }, function (t) {
          saveTestBtn.disabled = false;
          if (t.status === "completed") {
            showTaskProgress("Connection verified! Storage ready.", 100, false);
            showToast("Connection successful!", true);
          } else {
            showTaskProgress("Connection failed: " + (t.error || "unknown error"), 100, true);
            showToast("Connection test failed", false);
          }
          hideTaskProgress();
        });
      } else {
        saveTestBtn.disabled = false;
        showTaskProgress("Failed to dispatch connection test.", 100, true);
        hideTaskProgress();
      }
    });

    storageSection.appendChild(saveTestBtn);
    cloudVaultPage.appendChild(storageSection);

    // ── Section 2: Library Sync (Manifests & Saves) ──────────────────────────
    const syncSection = document.createElement("div");
    syncSection.className = "pmtools-section pmtools-panel";

    const syncLabel = document.createElement("div");
    syncLabel.className = "pmtools-section-label";
    syncLabel.textContent = tr("vaultSyncSection");
    syncSection.appendChild(syncLabel);

    const syncHint = document.createElement("div");
    syncHint.style.cssText = "font-size:0.786em;color:var(--ig-text-secondary);margin-bottom:0.714em;";
    syncHint.textContent = tr("vaultHint");
    syncSection.appendChild(syncHint);

    const syncActionRow = document.createElement("div");
    syncActionRow.style.cssText = "display:flex;gap:0.571em;flex-wrap:wrap;";

    const backupAllBtn = document.createElement("button");
    backupAllBtn.type = "button";
    backupAllBtn.className = "pmtools-btn";
    backupAllBtn.style.cssText = "font-size:0.857em;padding:0.35em 0.857em;";
    backupAllBtn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up" style="margin-right:0.35em;"></i>' + tr("vaultBackupAll");
    backupAllBtn.addEventListener("click", async function () {
      const ok = await confirmPopup(tr("vaultConfirmBackupAll"), tr("confirmContinue"), tr("confirmCancel"));
      if (!ok) return;
      backupAllBtn.disabled = true;
      showTaskProgress("Starting full vault backup...", 5, false);

      const res = await rpc("BackupAllPmtoolsVault");
      if (res && res.success && res.taskId) {
        pollCloudTask(res.taskId, function (t) {
          showTaskProgress(t.message || "Vaulting games...", t.progress || 10, false);
        }, function (t) {
          backupAllBtn.disabled = false;
          if (t.status === "completed") {
            showTaskProgress("All games vaulted successfully!", 100, false);
            showToast("Full library vaulted to personal storage!", true);
          } else {
            showTaskProgress("Backup failed: " + (t.error || "unknown error"), 100, true);
            showToast("Vault backup failed", false);
          }
          hideTaskProgress();
        });
      } else {
        backupAllBtn.disabled = false;
        showTaskProgress("Failed to start backup.", 100, true);
        hideTaskProgress();
      }
    });

    const restoreAllBtn = document.createElement("button");
    restoreAllBtn.type = "button";
    restoreAllBtn.className = "pmtools-btn";
    restoreAllBtn.style.cssText = "font-size:0.857em;padding:0.35em 0.857em;";
    restoreAllBtn.innerHTML = '<i class="fa-solid fa-cloud-arrow-down" style="margin-right:0.35em;"></i>' + tr("vaultRestoreAll");
    restoreAllBtn.addEventListener("click", async function () {
      const ok = await confirmPopup(tr("vaultConfirmRestoreAll"), tr("confirmContinue"), tr("confirmCancel"));
      if (!ok) return;
      restoreAllBtn.disabled = true;
      showTaskProgress("Connecting to vault and preparing restore...", 5, false);

      const res = await rpc("RestoreAllPmtoolsVault");
      if (res && res.success && res.taskId) {
        pollCloudTask(res.taskId, function (t) {
          showTaskProgress(t.message || "Restoring games...", t.progress || 10, false);
        }, function (t) {
          restoreAllBtn.disabled = false;
          if (t.status === "completed") {
            showTaskProgress("All games restored! Restart Steam to refresh.", 100, false);
            showToast("All games restored from vault!", true);
          } else {
            showTaskProgress("Restore failed: " + (t.error || "unknown error"), 100, true);
            showToast("Vault restore failed", false);
          }
          hideTaskProgress();
        });
      } else {
        restoreAllBtn.disabled = false;
        showTaskProgress("Failed to start restore.", 100, true);
        hideTaskProgress();
      }
    });

    syncActionRow.appendChild(backupAllBtn);
    syncActionRow.appendChild(restoreAllBtn);
    syncSection.appendChild(syncActionRow);
    cloudVaultPage.appendChild(syncSection);

    // ── Section 3: Offline JSON Backup ──────────────────────────────────────
    const offlineSection = document.createElement("div");
    offlineSection.className = "pmtools-section pmtools-panel";

    const offlineLabel = document.createElement("div");
    offlineLabel.className = "pmtools-section-label";
    offlineLabel.textContent = tr("vaultOfflineSection");
    offlineSection.appendChild(offlineLabel);

    const offlineHint = document.createElement("div");
    offlineHint.style.cssText = "font-size:0.786em;color:var(--ig-text-secondary);margin-bottom:0.714em;";
    offlineHint.textContent = tr("vaultOfflineHint");
    offlineSection.appendChild(offlineHint);

    const offlineActionRow = document.createElement("div");
    offlineActionRow.style.cssText = "display:flex;gap:0.571em;flex-wrap:wrap;";

    const exportBtn = document.createElement("button");
    exportBtn.type = "button";
    exportBtn.className = "pmtools-theme-chip";
    exportBtn.style.cssText = "font-size:0.857em;padding:0.35em 0.857em;";
    exportBtn.innerHTML = '<i class="fa-solid fa-file-export" style="margin-right:0.3em;"></i>' + tr("vaultExportJson");
    exportBtn.addEventListener("click", function () {
      rpc("ExportPmtoolsGames").then(function (res) {
        if (res && res.ok && res.games) {
          const blob = new Blob([JSON.stringify(res.games, null, 2)], { type: "application/json" });
          const url = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = "pmtools-backup-" + new Date().toISOString().slice(0, 10) + ".json";
          a.click();
          URL.revokeObjectURL(url);
          showToast("Exported " + res.count + " game(s)", true);
        } else {
          showToast("Export failed", false);
        }
      }).catch(function () { showToast("Export failed", false); });
    });

    const importBtn = document.createElement("button");
    importBtn.type = "button";
    importBtn.className = "pmtools-theme-chip";
    importBtn.style.cssText = "font-size:0.857em;padding:0.35em 0.857em;";
    importBtn.innerHTML = '<i class="fa-solid fa-file-import" style="margin-right:0.3em;"></i>' + tr("vaultImportJson");
    importBtn.addEventListener("click", function () {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = ".json";
      input.addEventListener("change", function () {
        const file = input.files && input.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = function () {
          try {
            const data = JSON.parse(reader.result);
            rpc("ImportPmtoolsGames", data).then(function (res) {
              if (res && res.ok) {
                showToast("Imported " + res.imported + " new game(s)" + (res.skipped ? ", skipped " + res.skipped : ""), true);
              } else {
                showToast("Import failed", false);
              }
            }).catch(function () { showToast("Import failed", false); });
          } catch (_) {
            showToast("Invalid backup file", false);
          }
        };
        reader.readAsText(file);
      });
      input.click();
    });

    offlineActionRow.appendChild(exportBtn);
    offlineActionRow.appendChild(importBtn);
    offlineSection.appendChild(offlineActionRow);
    cloudVaultPage.appendChild(offlineSection);

    // Initial config load
    rpc("GetPmtoolsCloudConfig").then(function (res) {
      if (res && res.success && res.config) {
        const c = res.config;
        if (c.provider) {
          activeProvider = c.provider;
          for (const k in chipEls) {
            chipEls[k].classList.toggle("active", k === activeProvider);
          }
        }
        if (c.localPath) localInput.input.value = c.localPath;
        if (c.webdav) {
          webdavUrl.input.value = c.webdav.url || "";
          webdavUser.input.value = c.webdav.username || "";
          webdavPass.input.value = c.webdav.password ? "••••••••" : "";
        }
        renderConfigFields(activeProvider);
        updateCloudVaultBadge(c);
      } else {
        renderConfigFields("local");
        updateCloudVaultBadge(null);
      }
    }).catch(function () {
      renderConfigFields("local");
      updateCloudVaultBadge(null);
    });

    function formatBytes(bytes) {
      if (bytes < 1024) return bytes + " B";
      if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
      return (bytes / 1048576).toFixed(1) + " MB";
    }

    let installedApps = [];
    let installedNames = {}; // appid -> name (filled from the backend cache RPC)
    let selectedApps = {};   // appid -> true (bulk selection state)

    function updateBulkUI() {
      const count = Object.keys(selectedApps).length;
      bulkActions.style.display = (installedApps.length > 0) ? "flex" : "none";
      bulkRemoveBtn.style.display = count > 0 ? "" : "none";
      bulkCount.textContent = count > 0 ? count + " selected" : "";
    }

    function displayName(app) {
      const n = installedNames[app.appid];
      // No cached name? Show the appid itself — never a blank placeholder.
      const label = n || app.appid;
      return label + (app.disabled ? " (" + tr("disabled") + ")" : "");
    }

    function openStore(appid) {
      try {
        const w = window.open("https://store.steampowered.com/app/" + appid, "_blank");
        if (w) w.focus();
      } catch (_) {
        window.location.href = "https://store.steampowered.com/app/" + appid;
      }
    }

    function renderInstalled() {
      installedList.innerHTML = "";
      const q = (installedSearch.value || "").toLowerCase().trim();
      let rows = installedApps.filter(function (a) {
        if (installedFilter === "enabled" && a.disabled) return false;
        if (installedFilter === "disabled" && !a.disabled) return false;
        if (!q) return true;
        const name = (installedNames[a.appid] || "").toLowerCase();
        return name.indexOf(q) !== -1 || String(a.appid).indexOf(q) !== -1;
      });
      const sortMode = installedSort ? installedSort.value : "recent";
      rows = rows.slice().sort(function (a, b) {
        const na = (installedNames[a.appid] || a.appid).toLowerCase();
        const nb = (installedNames[b.appid] || b.appid).toLowerCase();
        if (sortMode === "disabled") {
          // Disabled items first, then alphabetical within each group
          const da = !!a.disabled, db = !!b.disabled;
          if (da !== db) return da ? -1 : 1;
        } else if (sortMode === "recent") {
          // Most recent first, then alphabetical within same time
          const ta = a.installedAt || 0, tb = b.installedAt || 0;
          if (ta !== tb) return tb - ta;
        }
        // Alpha is the primary sort for "alpha" mode, secondary for others
        return na < nb ? -1 : na > nb ? 1 : 0;
      });
      if (rows.length === 0) {
        const empty = document.createElement("div");
        empty.className = "pmtools-status";
        empty.textContent = installedApps.length === 0 ? tr("installedEmpty") : tr("noMatches");
        installedList.appendChild(empty);
        return;
      }
      rows.forEach(function (a, idx) {
        const row = document.createElement("div");
        row.className = "pmtools-source-row";
        row.style.cssText = "align-items:center;animation:pmtoolsSectionIn 0.2s cubic-bezier(0.22,1,0.36,1) both;animation-delay:" + Math.min(idx * 25, 250) + "ms;";
        row.dataset.appid = a.appid;
        const name = document.createElement("a");
        name.href = "https://store.steampowered.com/app/" + a.appid;
        name.target = "_blank";
        name.rel = "noopener";
        name.title = tr("titleOpenStore");
        name.className = "pmtools-installed-name";
        name.style.cssText =
          "min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-right:0.571em;" +
          "text-decoration:none;color:var(--ig-text);cursor:pointer;";
        name.textContent = displayName(a);
        name.addEventListener("click", function (e) {
          e.preventDefault();
          openStore(a.appid);
        });
        const rm = document.createElement("button");
        rm.className = "pmtools-btn";
        rm.style.cssText = "padding:0.273em 0.909em;font-size:0.786em;flex-shrink:0;";
        rm.innerHTML = '<i class="fa-solid fa-trash-can"></i><span>' + tr("removeShort") + "</span>";
        rm.addEventListener("click", async function () {
          const ok = await confirmPopup(tr("confirmRemove") + " " + (installedNames[a.appid] || a.appid) + "?", tr("confirmContinue"), tr("confirmCancel"));
          if (!ok) return;
          rm.disabled = true;
          const res = await rpc("DeletePmtoolsForApp", { appid: a.appid });
          if (!res || res.success !== true) {
            rm.disabled = false;
            showToast(tr("removeFailed"), false);
            return;
          }
          row.classList.add("pmtools-row-removing");
          setTimeout(function () {
            installedApps = installedApps.filter(function (x) { return x.appid !== a.appid; });
            installedBadge.textContent = installedApps.length;
            installedBadge.classList.remove("updated");
            void installedBadge.offsetWidth;
            installedBadge.classList.add("updated");
            installedCount.textContent = tr("unlockedCount", { count: installedApps.length });
            renderInstalled();
          }, 260);
        });
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.style.cssText = "accent-color:var(--ig-accent);width:0.929em;height:0.929em;cursor:pointer;margin-right:0.429em;flex-shrink:0;";
        cb.checked = !!selectedApps[a.appid];
        cb.addEventListener("change", function () {
          if (cb.checked) selectedApps[a.appid] = true; else delete selectedApps[a.appid];
          updateBulkUI();
        });
        const vaultBtn = document.createElement("button");
        vaultBtn.type = "button";
        vaultBtn.className = "pmtools-icon-btn";
        vaultBtn.style.cssText = "width:2.2em;height:2.2em;font-size:0.857em;flex-shrink:0;margin-right:0.429em;";
        vaultBtn.title = tr("vaultSyncGame");
        vaultBtn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
        vaultBtn.addEventListener("click", async function (e) {
          e.stopPropagation();
          vaultBtn.disabled = true;
          vaultBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i>';
          const res = await rpc("BackupPmtoolsGame", { appid: a.appid, title: displayName(a) });
          if (res && res.success && res.taskId) {
            pollCloudTask(res.taskId, null, function (t) {
              vaultBtn.disabled = false;
              if (t.status === "completed") {
                vaultBtn.innerHTML = '<i class="fa-solid fa-check" style="color:#5cd65c;"></i>';
                showToast(displayName(a) + " vaulted to personal storage!", true);
              } else {
                vaultBtn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
                showToast("Vault failed: " + (t.error || "error"), false);
              }
            });
          } else {
            vaultBtn.disabled = false;
            vaultBtn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
            showToast("Failed to dispatch vault task", false);
          }
        });

        row.appendChild(cb);
        row.appendChild(name);
        row.appendChild(vaultBtn);
        row.appendChild(rm);
        installedList.appendChild(row);
      });
      updateBulkUI();
    }

    // ── Select-all checkbox handler ─────────────────────────────────────────
    selectAllCb.addEventListener("change", function () {
      if (selectAllCb.checked) {
        // Select all currently visible rows
        const q = (installedSearch.value || "").toLowerCase().trim();
        installedApps.filter(function (a) {
          if (installedFilter === "enabled" && a.disabled) return false;
          if (installedFilter === "disabled" && !a.disabled) return false;
          if (!q) return true;
          const name = (installedNames[a.appid] || "").toLowerCase();
          return name.indexOf(q) !== -1 || String(a.appid).indexOf(q) !== -1;
        }).forEach(function (a) { selectedApps[a.appid] = true; });
      } else {
        selectedApps = {};
      }
      renderInstalled();
    });

    // ── Bulk remove handler ─────────────────────────────────────────────────
    bulkRemoveBtn.addEventListener("click", async function () {
      const ids = Object.keys(selectedApps);
      if (ids.length === 0) return;
      const ok = await confirmPopup(
        "Remove " + ids.length + " game(s) via Pmtools?",
        tr("confirmContinue"), tr("confirmCancel"));
      if (!ok) return;
      bulkRemoveBtn.disabled = true;
      rpc("BulkRemovePmtoolsGames", ids).then(function (res) {
        bulkRemoveBtn.disabled = false;
        if (res && res.ok) {
          showToast("Removed " + res.removed + " game(s)", true);
          installedApps = installedApps.filter(function (x) { return !selectedApps[x.appid]; });
          selectedApps = {};
          installedBadge.textContent = installedApps.length;
          installedCount.textContent = tr("unlockedCount", { count: installedApps.length });
          renderInstalled();
        } else {
          showToast(tr("removeFailed"), false);
        }
      }).catch(function () {
        bulkRemoveBtn.disabled = false;
        showToast(tr("removeFailed"), false);
      });
    });

    // Names come from the backend-managed cache (GetPmtoolsTitles) — a
    // PURE cache read that never hits Steam, so it's instant. Appids without
    // a cached name render as their appid; Refresh clears failures so the
    // cache can be re-populated (e.g. by the frontend's own Steam fetch).
    const TITLE_CHUNK = 25;
    // NB: Millennium's server bridge only forwards scalar args (arrays become
    // nil), so appids travel as a comma-joined string and the backend splits.
    // One pass over the appids is enough — the backend won't fill gaps on its
    // own anymore, so there's nothing to re-request.
    function requestTitles(appids) {
      if (!appids.length) return;
      const chunk = appids.slice(0, TITLE_CHUNK);
      const rest = appids.slice(TITLE_CHUNK);
      rpc("GetPmtoolsTitles", { appids: chunk.join(",") }).then(function (res) {
        if (res && res.success && res.titles) {
          for (const id in res.titles) installedNames[id] = res.titles[id];
          renderInstalled();
        }
        // Backend cache miss — fetch names directly from Steam's appdetails
        const missing = (res && Array.isArray(res.missing)) ? res.missing : [];
        if (missing.length) {
          let mIdx = 0;
          async function fetchName() {
            while (mIdx < missing.length) {
              const id = missing[mIdx++];
              try {
                const r = await fetch("/api/appdetails?appids=" + id);
                const j = await r.json();
                const v = j && j[id];
                if (v && v.success && v.data && v.data.name) {
                  installedNames[id] = v.data.name;
                }
              } catch (_) {}
            }
            renderInstalled();
            // Persist resolved names to backend cache for next time
            const toSave = {};
            missing.forEach(function (id) { if (installedNames[id]) toSave[id] = installedNames[id]; });
            if (Object.keys(toSave).length) {
              rpc("SavePmtoolsTitles", { payload: JSON.stringify({ names: toSave }) });
            }
          }
          Promise.all(Array.from({ length: Math.min(6, missing.length) }, fetchName));
        }
        if (rest.length) setTimeout(function () { requestTitles(rest); }, 120);
      });
    }

    installedSearch.addEventListener("input", renderInstalled);

    installedList.classList.add("pmtools-installed-list");
    // Show skeleton rows while loading
    for (let i = 0; i < 8; i++) {
      const skel = document.createElement("div");
      skel.className = "pmtools-source-row pmtools-skeleton pmtools-skel-row";
      skel.style.animationDelay = (i * 30) + "ms";
      skel.innerHTML = '<div class="pmtools-skel-name"></div><div class="pmtools-skel-btn"></div>';
      installedList.appendChild(skel);
    }
    rpc("ListPmtoolsInstalled").then(function (res) {
      installedApps = (res && res.apps) || [];
      installedBadge.textContent = installedApps.length;
      installedCount.textContent = tr("unlockedCount", { count: installedApps.length });
      renderInstalled();
      requestTitles(installedApps.filter(function (a) { return !installedNames[a.appid]; }).map(function (a) { return a.appid; }));
    }).catch(function () {
      installedList.innerHTML = "";
      const box = document.createElement("div");
      box.className = "pmtools-error-box";
      const icon = document.createElement("div");
      icon.className = "pmtools-error-icon";
      icon.innerHTML = '<i class="fa-solid fa-cloud-bolt"></i>';
      box.appendChild(icon);
      const msg = document.createElement("div");
      msg.className = "pmtools-error-msg";
      msg.textContent = tr("installedLoadFailed");
      box.appendChild(msg);
      const retry = document.createElement("button");
      retry.type = "button";
      retry.className = "pmtools-retry-btn";
      retry.textContent = tr("retry");
      retry.addEventListener("click", function () {
        installedList.innerHTML = "";
        // Re-trigger the whole load by re-running the initial setup
        location.reload();
      });
      box.appendChild(retry);
      installedList.appendChild(box);
    });

    refreshTitles.addEventListener("click", function () {
      refreshTitles.classList.add("spinning");
      const all = installedApps.map(function (a) { return a.appid; });
      rpc("RefreshPmtoolsTitles", { appids: all.join(",") }).then(function (res) {
        refreshTitles.classList.remove("spinning");
        if (res && res.success && res.titles) {
          for (const id in res.titles) installedNames[id] = res.titles[id];
          renderInstalled();
        }
      });
    });

    unlockedPage.style.display = "none";
    cloudVaultPage.style.display = "none";
    body.appendChild(unlockedPage);
    body.appendChild(cloudVaultPage);
    body.appendChild(mainPage);
    modal.appendChild(body);
    overlay.appendChild(modal);
    // The remove action lives in the header row (trash icon, next to restart
    // and close); sync its visibility with the current page's unlock state.
    syncSettingsRemove(removeBtn);
    document.body.appendChild(overlay);
  }

  // Show/hide the header trash (remove-current-game) button: only visible
  // while browsing a store page whose game is actually unlocked.
  function syncSettingsRemove(removeBtn) {
    const appid = getAppId();
    if (!appid || !removeBtn) {
      if (removeBtn) removeBtn.style.display = "none";
      return;
    }
    rpc("HasPmtoolsForApp", { appid: appid })
      .then(function (res) {
        const added = !!(res && res.added);
        removeBtn.style.display = added ? "" : "none";
      })
      .catch(function () {
        removeBtn.style.display = "none";
      });
  }

  // Resolve a game's name from Steam's same-origin appdetails endpoint, with
  // a per-appid cache so repeated confirmations don't re-fetch. Falls back to
  // the appid itself when Steam can't resolve it.
  const gameNameCache = {}; // appid -> resolved name (string)
  function resolveGameName(appid) {
    return new Promise(function (resolve) {
      if (gameNameCache[appid] !== undefined) {
        resolve(gameNameCache[appid] || appid);
        return;
      }
      fetch("/api/appdetails?appids=" + appid)
        .then(function (r) { return r.json(); })
        .then(function (j) {
          const v = j && j[appid];
          const name = v && v.success && v.data && v.data.name ? v.data.name : appid;
          gameNameCache[appid] = name;
          resolve(name);
        })
        .catch(function () {
          gameNameCache[appid] = appid;
          resolve(appid);
        });
    });
  }

  // ── Reusable popups ─────────────────────────────────────────────────────────

  // Non-blocking toast (top-right, auto-dismisses). Used for lightweight
  // feedback like "Removed." — confirms stay as popups.
  function showToast(message, isOk) {
    let host = document.getElementById("pmtools-toasts");
    if (!host) {
      host = document.createElement("div");
      host.id = "pmtools-toasts";
      host.style.cssText =
        "position:fixed;top:1.143em;right:1.143em;z-index:2147483500;" +
        "display:flex;flex-direction:column;gap:0.571em;align-items:flex-end;pointer-events:none;";
      document.body.appendChild(host);
    }
    const t = document.createElement("div");
    t.style.cssText =
      "pointer-events:auto;background:var(--ig-modal-bg);color:var(--ig-text);" +
      "border:1px solid var(--ig-border);border-left:0.286em solid " + (isOk ? "#9bd89b" : "#ff7b7b") + ";" +
      "border-radius:0.571em;padding:0.714em 1em;font-size:0.929em;max-width:24em;" +
      "box-shadow:0 0.714em 2.5em rgba(0,0,0,0.45);animation:pmtoolsToastIn 0.25s cubic-bezier(0.18, 0.89, 0.32, 1.28);";
    t.textContent = message;
    host.appendChild(t);
    function dismiss() {
      t.style.animation = "pmtoolsToastOut 0.25s cubic-bezier(0.22,1,0.36,1) forwards";
      setTimeout(function () { t.remove(); }, 260);
    }
    setTimeout(dismiss, 3500);
    t.addEventListener("click", dismiss);
    t.style.cursor = "pointer";
    t.style.transition = "border-color 0.15s ease";
  }

  // Steam-style achievement popup for game unlocks.
  function showAchievement(gameName, appid) {
    var el = document.createElement("div");
    el.className = "pmtools-achievement";
    var icon = document.createElement("div");
    icon.className = "pmtools-achievement-icon";
    icon.innerHTML = '<i class="fa-solid fa-trophy"></i>';
    var text = document.createElement("div");
    text.className = "pmtools-achievement-text";
    var title = document.createElement("div");
    title.className = "pmtools-achievement-title";
    title.textContent = "Game Unlocked";
    var name = document.createElement("div");
    name.className = "pmtools-achievement-name";
    name.textContent = (gameName || "Game") + (appid ? " · " + appid : "");
    text.appendChild(title);
    text.appendChild(name);
    el.appendChild(icon);
    el.appendChild(text);
    document.body.appendChild(el);
    setTimeout(function () {
      el.style.animation = "pmtoolsAchievementOut 0.35s ease forwards";
      setTimeout(function () { el.remove(); }, 360);
    }, 3500);
  }

  function confirmPopup(message, yesText, noText) {
    return new Promise(function (resolve) {
      const c = getThemeColors();
      const overlay = document.createElement("div");
      overlay.className = "pmtools-overlay";
      const modal = document.createElement("div");
      modal.className = "pmtools-modal pmtools-dialog";
      modal.style.cssText = `width:30em;max-width:calc(100vw - 48px);text-align:center;`;
      const icon = document.createElement("div");
      icon.className = "pmtools-alert-icon";
      icon.style.cssText = `color:${c.accent};font-size:2.286em;margin-bottom:0.714em;`;
      icon.innerHTML = '<i class="fa-solid fa-circle-question"></i>';
      const text = document.createElement("div");
      text.className = "pmtools-status";
      text.textContent = message;
      const actions = document.createElement("div");
      actions.className = "pmtools-actions";
      actions.style.justifyContent = "center";
      const noBtn = document.createElement("button");
      noBtn.className = "pmtools-btn";
      noBtn.textContent = noText || tr("restartNo");
      const yesBtn = document.createElement("button");
      yesBtn.className = "pmtools-btn primary";
      yesBtn.textContent = yesText || tr("restartYes");
      function closeConfirm(val) {
        modal.style.animation = "pmtoolsPageOut 0.12s ease-out forwards";
        overlay.style.transition = "opacity 0.15s ease";
        overlay.style.opacity = "0";
        setTimeout(function () { overlay.remove(); resolve(val); }, 160);
      }
      noBtn.addEventListener("click", function () { closeConfirm(false); });
      yesBtn.addEventListener("click", function () { closeConfirm(true); });
      actions.appendChild(noBtn);
      actions.appendChild(yesBtn);
      modal.appendChild(icon);
      modal.appendChild(text);
      modal.appendChild(actions);
      overlay.appendChild(modal);
      document.body.appendChild(overlay);
    });
  }

  function askRestartConfirmation() {
    confirmPopup(tr("restartQuestion"), tr("restartYes"), tr("restartNo")).then(function (ok) {
      if (ok) rpc("RestartSteam");
    });
  }

  // ── UI scale (manual) ──────────────────────────────────────────────────────

  // The plugin UI is sized in em against a 14px base font whose real size is
  // scaled by --ig-scale. The user controls the scale with the Settings →
  // "UI scale" slider (persisted as the uiScale setting); the value is applied
  // here and re-applied whenever the slider moves.
  function applyScale() {
    const raw = loadedSettings && loadedSettings.uiScale;
    let s = parseFloat(raw);
    if (!isFinite(s) || s <= 0) s = 1;
    s = Math.min(1.5, Math.max(0.75, s));
    document.documentElement.style.setProperty("--ig-scale", String(s));
  }

  async function boot() {
    backendLog("webkit module booting");
    // Remove stale error overlay from previous failed boot attempt
    var oldOverlay = document.querySelector('.pmtools-status.error');
    if (oldOverlay) { var p = oldOverlay.closest('.pmtools-overlay'); if (p) p.remove(); }

    // ── Render FIRST, validate later ──
    // The logo/store button must appear instantly. Previously everything
    // waited on the ping (up to 9s of retries on cold start). Render with
    // defaults now; re-apply real settings when they arrive.
    loadedSettings = null;
    activeLang = detectLanguage();
    ensureStyles();
    ensureFontAwesome();
    applyTheme();
    applyScale();
    ensureHeaderButton();
    ensureStoreButton();

    // Backend validation runs in the background.
    var pong = null;
    for (var _attempt = 0; _attempt < 3; _attempt++) {
      pong = await rpc("PmtoolsPing").catch(function () { return null; });
      if (pong && pong.ok) break;
      backendLog("ping attempt " + (_attempt+1) + " failed, retrying in 3s...");
      await new Promise(function (r) { setTimeout(r, 3000); });
    }
    backendLog("ping result: " + (pong ? JSON.stringify(pong) : "null"));
    if (pong && pong.version) backendVersion = pong.version;
    if (!pong || !pong.ok) {
      const el = document.createElement("div");
      el.className = "pmtools-overlay";
      el.style.cssText = "background:rgba(0,0,0,0.55);backdrop-filter:none;z-index:2147482999;";
      const box = document.createElement("div");
      box.className = "pmtools-modal pmtools-dialog";
      box.style.cssText = `width:30em;text-align:center;`;
      const txt = document.createElement("div");
      txt.className = "pmtools-status error";
      txt.textContent = tr("errorBackend") + " — " + tr("errorBackendHint");
      box.appendChild(txt);
      el.appendChild(box);
      document.body.appendChild(el);
      return;
    }
    const settingsRes = await rpc("GetPmtoolsSettings").catch(function () { return null; });
    loadedSettings = settingsRes && settingsRes.settings;
    activeLang = (loadedSettings && loadedSettings.language) || detectLanguage();
    applyTheme();
    applyScale();
    refreshStoreButton();
    prewarmTitles();
    prewarmStoreData();
  }

  // ── Boot-time title pre-warm ────────────────────────────────────────────────
  // Fill the backend's title cache in the background so the unlocked-games
  // page shows names instantly even on a cold cache. Runs once per store
  // context: enumerate installed apps, ask the backend what's missing
  // (cached-only read — instant), fetch those directly from Steam's
  // same-origin API (the same endpoint the Add popup uses) a few at a time,
  // then push the results back via SavePmtoolsTitles. Transient network
  // errors are skipped silently (the next boot retries); only Steam's
  // definitive success:false counts as a permanent failure.
  //
  // The webkit module is re-injected with a FRESH JS context on every page
  // navigation, so a window flag resets each time and the warm-up would
  // re-fire (up to 6 parallel store-API fetches per page open, competing
  // with Steam's own page data over the network). sessionStorage survives
  // navigations in the same tab — one warm-up per Steam session is enough;
  // the title cache is backend-persisted.
  let titlesPrewarmed = false;
  try {
    titlesPrewarmed = sessionStorage.getItem("__pmtoolsTitlesPrewarmed") === "1";
  } catch (_) { /* sessionStorage unavailable — warm up each boot */ }
  if (!titlesPrewarmed) {
    try { sessionStorage.setItem("__pmtoolsTitlesPrewarmed", "1"); } catch (_) {}
  }

  async function prewarmTitles() {
    if (titlesPrewarmed) return;
    titlesPrewarmed = true;
    try {
      const list = await rpc("ListPmtoolsInstalled");
      const apps = (list && list.apps) || [];
      if (!apps.length) return;
      const all = apps.map(function (a) { return a.appid; });
      const res = await rpc("GetPmtoolsTitles", { appids: all.join(",") });
      const missing = (res && Array.isArray(res.missing)) ? res.missing : [];
      if (missing.length) {
        // Steam's appdetails endpoint rate-limits batched requests to ~1 appid
        // per call, so fetch one per request — but several in parallel.
        const names = {};
        const failed = [];
        const CONCURRENCY = 6;
        let idx = 0;
        async function worker() {
          while (idx < missing.length) {
            const id = missing[idx++];
            try {
              const r = await fetch("/api/appdetails?appids=" + id);
              const j = await r.json();
              const v = j && j[id];
              if (v && v.success && v.data && v.data.name) {
                names[id] = v.data.name;
              } else if (v && v.success === false) {
                failed.push(id);
              }
            } catch (_) {
              // transient blip — leave for the next boot
            }
          }
        }
        await Promise.all(Array.from({ length: Math.min(CONCURRENCY, missing.length) }, worker));
        if (Object.keys(names).length || failed.length) {
          await rpc("SavePmtoolsTitles", { payload: JSON.stringify({ names: names, failed: failed }) });
        }
      }
      // Fresh installs have an empty health store (record_health only runs on
      // store-page checks/downloads), so warm it once at boot or the settings
      // list's click-to-expand health panel would be blank. This blocks the
      // Lua backend for up to 6s (probe deadline), so skip it if health data
      // already exists — the user has already probed at least once.
      try {
        const usage = await rpc("GetPmtoolsSourceUsage");
        const srcs = (usage && usage.sources) || [];
        const hasHealth = srcs.some(function (s) { return s.health && s.health.checks > 0; });
        if (!hasHealth) {
          rpc("GetPmtoolsSourceAvailability", { appid: apps[0].appid });
        }
      } catch (_) {}
    } catch (_) {
      // never break the store page over a background warm-up
    }
  }

  // ── Boot-time store-data pre-warm ──────────────────────────────────────────
  // The library detail page fetches per-app store data on every open
  // (store.steampowered.com/api/libraryappdetails + steamcommunity.com
  // ajaxgetbadgeinfo). Games owned the normal way feel instant because those
  // responses are already in Steam's webhelper HTTP cache; freshly unlocked
  // games hit a cold cache, so the first open pays 1-2s of sequential
  // round-trips (repeat opens are instant once cached). Warm the same
  // endpoints for every managed game right after boot so first opens are
  // instant too. One pass per Steam session (sessionStorage-guarded), a few
  // requests at a time, and transient failures are skipped — the next boot
  // retries.
  let storePrewarmed = false;
  try {
    storePrewarmed = sessionStorage.getItem("__pmtoolsStorePrewarmed") === "1";
  } catch (_) { /* sessionStorage unavailable — warm up each boot */ }
  if (!storePrewarmed) {
    try { sessionStorage.setItem("__pmtoolsStorePrewarmed", "1"); } catch (_) {}
  }

  async function prewarmStoreData() {
    if (storePrewarmed) return;
    storePrewarmed = true;
    try {
      const list = await rpc("ListPmtoolsInstalled");
      const apps = (list && list.apps) || [];
      if (!apps.length) return;
      // Resolve the user's profile URL via a JSON endpoint (the /my/ alias
      // redirects to /profiles/<steamid>/ and JSON endpoints carry CORS
      // headers, unlike HTML pages), so badge pre-fetches use the exact URL
      // the detail page requests — the redirect target is what the cache
      // keys on. App 440 is just a probe; the response is discarded. At boot
      // the community session cookie may not be set yet, so this probe runs
      // in PARALLEL with the library-appdetails warm (which needs no cookie)
      // and retries with backoff before giving up on badges.
      // A fetch that hangs (no timeout) would stall the entire warm-up —
      // Steam's endpoints occasionally drop connections. Bound every request.
      function fetchTimeout(url, ms) {
        const ctrl = new AbortController();
        const t = setTimeout(function () { ctrl.abort(); }, ms);
        return fetch(url, { credentials: "include", signal: ctrl.signal })
          .finally(function () { clearTimeout(t); });
      }
      const profileP = (async function () {
        let p = "";
        for (let attempt = 0; attempt < 5 && !p; attempt++) {
          if (attempt) await new Promise(function (res) { setTimeout(res, 20000 * attempt); });
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
      async function worker() {
        while (idx < apps.length) {
          const id = apps[idx++].appid;
          try {
            const resp = await fetchTimeout(
              "https://store.steampowered.com/api/libraryappdetails/?appid=" + id + "&l=" + encodeURIComponent(lang),
              15000);
            await resp.text(); // drain — the response only helps once cached
            if (resp.status === 429) {
              // rate-limited — back off a moment before continuing
              await new Promise(function (res) { setTimeout(res, 1500); });
            }
          } catch (_) { /* transient blip — the next boot retries */ }
          await new Promise(function (res) { setTimeout(res, PAUSE_MS); });
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
                15000);
              await resp.text();
              if (resp.status === 429) {
                await new Promise(function (res) { setTimeout(res, 1500); });
              }
            } catch (_) {}
            await new Promise(function (res) { setTimeout(res, PAUSE_MS); });
          }
        }
        await Promise.all(Array.from({ length: Math.min(CONCURRENCY, apps.length) }, badgeWorker));
      }
      backendLog("store data pre-warmed for " + apps.length + " game(s)" + (profile ? "" : " (no profile)"));
    } catch (_) {
      // never break the page over a background warm-up
    }
  }

  // ── Keyboard Navigation ──────────────────────────────────────────────────
  // Esc closes any open overlay; arrow keys navigate source list; Enter activates.
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      const overlay = document.querySelector(".pmtools-settings-overlay")
        || document.querySelector(".pmtools-add-overlay")
        || document.querySelector(".pmtools-overlay:not(.pmtools-settings-overlay):not(.pmtools-add-overlay)");
      if (overlay) {
        e.preventDefault();
        e.stopPropagation();
        const closeBtn = overlay.querySelector(".pmtools-icon-btn");
        if (closeBtn) closeBtn.click();
      }
    }
  }, true);

  // ── Steam Theme Sync ──────────────────────────────────────────────────────
  // Auto-detect Steam's theme preference and listen for changes.
  function syncSteamTheme() {
    try {
      const html = document.documentElement;
      if (!html) return;
      const isDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
      document.documentElement.style.setProperty("--ig-steam-theme", isDark ? "dark" : "light");
    } catch (_) {}
  }
  syncSteamTheme();
  try {
    if (window.matchMedia) {
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", syncSteamTheme);
    }
  } catch (_) {}

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  let lastPath = window.location.pathname;
  let insertTries = 0;
  setInterval(function () {
    if (window.location.pathname !== lastPath) {
      lastPath = window.location.pathname;
      window.__PmtoolsHeaderInserted = false;
      headerMissingLogged = false;
      storeMissingLogged = false;
      insertTries = 0;
      storeBtn = null;
      ensureHeaderButton();
      ensureStoreButton();
      refreshStoreButton();
      return;
    }
    // Keep trying to find the header container / store row (they load async).
    // The header button must ALWAYS be re-asserted when missing: Steam's React
    // re-render can remove it without a navigation, and __PmtoolsHeaderInserted
    // stays true, so it would never come back otherwise.
    if (!document.querySelector(".pmtools-header-btn")) {
      ensureHeaderButton();
    }
    // The store-row button is pinned once (Steam fights re-ordering), so keep
    // the retry budget for it — stop after ~3 minutes of failures.
    if (!document.querySelector(".pmtools-store-btn")) {
      insertTries++;
      if (insertTries > 120) return;
      ensureStoreButton();
    } else {
      insertTries = 0;
    }
  }, 1500);
}

// ── Millennium webkit-module contract ─────────────────────────────────────────

function InitializePlugins() {
  let _a, _b;
  (_a = (window.PLUGIN_LIST || (window.PLUGIN_LIST = {})))[pluginName] || (_a[pluginName] = {});
  (_b = (window.MILLENNIUM_PLUGIN_SETTINGS_STORE || (window.MILLENNIUM_PLUGIN_SETTINGS_STORE = {})))[pluginName] || (_b[pluginName] = {});
}
InitializePlugins();

var __call_server_method__ = (methodName, kwargs) => Millennium.callServerMethod(pluginName, methodName, kwargs);

function PluginEntryPointMain() {
  const module = {};
  module.default = PmtoolsEntryPoint;
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