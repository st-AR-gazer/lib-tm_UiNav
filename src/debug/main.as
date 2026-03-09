namespace UiNav {
namespace Debug {

    enum Mode {
        ML = 0,
        ControlTree = 1
    }

    class MlStyleCaptureEntry {
        string name;
        string type;
        string controlId;
        string selector;
        string selectorIdChain;
        string selectorMixedChain;
        string indexPath;
        string uiPath;
        int layerIx = -1;
        int appKind = 0;
        string snapshotJson;
    }

    class MlLayerFavorite {
        int appKind = 0;
        string layerId;
        int layerIx = -1;
        string label;
    }

    class MlValueLock {
        string id;
        bool enabled = true;
        int appKind = 0;
        int layerIx = -1;
        string path;
        int valueKind = 0; // 1 = label, 2 = entry
        string lockedValue;
        string label;
    }

    class MlBrowserEntry {
        string url;
        string source;
        string kind;
    }

    class MlFlatRow {
        bool isLayer = false;
        int depth = 0;
        int layerIx = -1;
        string path;
        string uiPath;
        string label;
        bool hasChildren = false;
        bool visible = true;
        string tag;
    }

    class ControlTreeFlatRow {
        int depth = 0;
        int rootIx = -1;
        string relPath;
        string displayPath;
        string uiPath;
        string label;
        bool hasChildren = false;
        bool visible = true;
    }

    class ControlTreeOverlayRootsCacheEntry {
        uint epoch = 0;
        uint mobilsLen = 0;
        uint scanIx = 0;
        bool complete = false;
        array<int> rootIxs;
    }

    Mode g_Mode = Mode::ML;

    string g_MlSearch = "";
    bool g_MlPickMode = false;
    bool g_MlPickNextClick = false;
    int g_MlViewLayerIndex = -1;
    int g_MlTreeHeight = 600;
    int g_MlTreeWidth = 420;
    bool g_MlCollapseAll = false;
    bool g_MlNodeFocusActive = false;
    int g_MlNodeFocusAppKind = 0;
    int g_MlNodeFocusLayerIx = -1;
    string g_MlNodeFocusPath = "";
    string g_MlNodeFocusUiPath = "";
    string g_MlNodeFocusStatus = "";
    bool g_MlSplitterDragging = false;
    float g_MlSplitterLastX = 0.0f;
    CGameManialinkControl@ g_SelectedMlNode = null;
    string g_SelectedMlUiPath = "";
    string g_SelectedMlPath = "";
    int g_SelectedMlLayerIx = -1;
    int g_MlActiveAppKind = 0; // 0 = playground, 1 = menu
    int g_SelectedMlAppKind = 0;
    uint g_MlTreeOpenEpoch = 0;
    uint g_MlSearchCacheEpoch = 0;
    uint g_MlSubtreeCacheLastClearMs = 0;
    uint g_MlInspectableCacheEpoch = 0;
    uint g_MlInspectableCacheStampMs = 0;
    bool g_MlInspectableCacheValid = false;
    bool g_MlInspectablePlayground = false;
    bool g_MlInspectableMenu = false;
    bool g_MlInspectableEditor = false;
    array<MlLayerFavorite@> g_MlLayerFavorites;
    bool g_MlLayerFavoritesLoaded = false;
    string g_MlLayerFavoritesStatus = "";
    array<MlValueLock@> g_MlValueLocks;
    bool g_MlValueLocksLoaded = false;
    string g_MlValueLocksStatus = "";
    string g_MlValueLockDraft = "";
    string g_MlValueLockDraftKey = "";
    array<MlBrowserEntry@> g_MlBrowserEntries;
    string g_MlBrowserSelectedUrl = "";
    string g_MlBrowserSearch = "";
    string g_MlBrowserStatus = "";
    uint g_MlBrowserLastRefreshMs = 0;
    bool g_MlBrowserSplitterDragging = false;
    float g_MlBrowserSplitterLastX = 0.0f;
    dictionary g_MlBrowserResolvedPathCache;
    UI::Texture@ g_MlBrowserPreviewTexture = null;
    string g_MlBrowserPreviewTextureUrl = "";
    string g_MlBrowserPreviewError = "";
    bool g_MlBrowserLoadPreviewRequested = false;
    array<string> g_MlBrowserFavorites;
    bool g_MlBrowserFavoritesLoaded = false;
    array<MlFlatRow@> g_MlFlatRows;
    bool g_MlFlatDirty = true;
    string g_MlFlatFilterKey = "";
    int g_MlFlatViewLayer = -9999;
    int g_MlFlatAppKind = -1;
    uint g_MlFlatEpoch = 0;
    uint g_MlFlatLastBuildMs = 0;
    bool g_MlFlatRowsTruncated = false;

    string g_ControlTreeSearch = "";
    bool g_ControlTreePickMode = false;
    bool g_ControlTreePickNextClick = false;
    int g_ControlTreeOverlay = -1;
    int g_ControlTreeTreeHeight = 600;
    int g_ControlTreeTreeWidth = 420;
    bool g_ControlTreeCollapseAll = false;
    bool g_ControlTreeNodeFocusActive = false;
    uint g_ControlTreeNodeFocusOverlay = 16;
    int g_ControlTreeNodeFocusRootIx = -1;
    string g_ControlTreeNodeFocusPath = "";
    string g_ControlTreeNodeFocusUiPath = "";
    bool g_ControlTreeSplitterDragging = false;
    float g_ControlTreeSplitterLastX = 0.0f;
    CControlBase@ g_SelectedControlTreeNode = null;
    string g_SelectedControlTreeUiPath = "";
    int g_SelectedControlTreeRootIx = -1;
    uint g_SelectedControlTreeOverlayAtSel = 16;
    string g_SelectedControlTreePath = "";
    string g_SelectedControlTreeDisplayPath = "";
    uint g_ControlTreeSearchCacheEpoch = 0;
    uint g_ControlTreeSubtreeCacheLastClearMs = 0;
    array<ControlTreeFlatRow@> g_ControlTreeFlatRows;
    bool g_ControlTreeFlatDirty = true;
    string g_ControlTreeFlatFilterKey = "";
    uint g_ControlTreeFlatOverlay = 0;
    string g_ControlTreeFlatStartPath = "";
    uint g_ControlTreeFlatEpoch = 0;
    uint g_ControlTreeFlatLastBuildMs = 0;
    bool g_ControlTreeFlatRowsTruncated = false;

    string g_MlSnippetKey = "";
    string g_MlSnippetEdit = "";
    string g_ControlTreeSnippetKey = "";
    string g_ControlTreeSnippetEdit = "";

    dictionary g_ControlTreeOverlayRootsCache;

    [Setting hidden name="UiNav debug ML tree width"]
    int S_MlTreeWidth = 420;

    [Setting hidden name="UiNav debug ControlTree tree width"]
    int S_ControlTreeTreeWidth = 420;

    [Setting hidden name="UiNav debug search cache refresh ms"]
    uint S_DebugSearchCacheRefreshMs = 800;

    [Setting hidden name="UiNav debug ML search global"]
    bool S_MlSearchGlobal = false;

    [Setting hidden name="UiNav debug tree node cache ttl ms"]
    uint S_DebugTreeNodeCacheTtlMs = 0;

    [Setting hidden name="UiNav debug tree inline text"]
    bool S_DebugTreeInlineText = false;

    [Setting hidden name="UiNav debug tree row budget (0 = unlimited)"]
    int S_DebugTreeRowBudget = 800;

    [Setting hidden name="UiNav debug ControlTree hide empty roots"]
    bool S_ControlTreeHideEmptyRoots = true;

    [Setting hidden name="UiNav debug ControlTree overlay root scan budget"]
    uint S_ControlTreeOverlayRootScanBudget = 2048;

    bool g_WidthsInit = false;

    int g_MlRowsRendered = 0;
    bool g_MlRowsTruncated = false;
    int g_ControlTreeRowsRendered = 0;
    bool g_ControlTreeRowsTruncated = false;

    [Setting hidden name="UiNav debug notes file path"]
    string S_MlNotesPath = IO::FromStorageFolder("UiNavMlNotes.cfg");

    [Setting hidden name="UiNav debug favorite layers"]
    string S_MlFavoriteLayers = "";

    [Setting hidden name="UiNav debug ML value locks"]
    string S_MlValueLocks = "";

    [Setting hidden name="UiNav debug ML browser include live layers"]
    bool S_MlBrowserIncludeLiveLayers = true;

    [Setting hidden name="UiNav debug ML browser include filesystem"]
    bool S_MlBrowserIncludeFilesystem = true;

    [Setting hidden name="UiNav debug ML browser include Nadeo Fids tree"]
    bool S_MlBrowserIncludeNadeoFidsTree = true;

    [Setting hidden name="UiNav debug ML browser assets root"]
    string S_MlBrowserAssetsRoot = "";

    [Setting hidden name="UiNav debug ML browser recursive"]
    bool S_MlBrowserRecursive = true;

    [Setting hidden name="UiNav debug ML browser max files"]
    int S_MlBrowserMaxFiles = 6000;

    [Setting hidden name="UiNav debug ML browser max Nadeo Fids files"]
    int S_MlBrowserMaxNadeoFidsFiles = 50000;

    [Setting hidden name="UiNav debug ML browser verbose logs"]
    bool S_MlBrowserVerboseLogs = true;

    [Setting hidden name="UiNav debug ML browser use Fids resolution"]
    bool S_MlBrowserUseFidsResolution = false;

    [Setting hidden name="UiNav debug ML browser allow Fids extraction"]
    bool S_MlBrowserAllowFidExtract = true;

    [Setting hidden name="UiNav debug ML browser use DDS decoder fallback"]
    bool S_MlBrowserUseDdsDecoder = true;

    [Setting hidden name="UiNav debug ML browser auto preview on select"]
    bool S_MlBrowserAutoPreview = false;

    [Setting hidden name="UiNav debug ML browser list width"]
    int S_MlBrowserListWidth = 420;

    [Setting hidden name="UiNav debug ML browser favorites"]
    string S_MlBrowserFavorites = "";

    [Setting hidden name="UiNav debug snapshot file path"]
    string S_MlSnapshotPath = IO::FromStorageFolder("Exports/ManiaLinks/uinav_ml_snapshot.json");

    [Setting hidden name="UiNav debug snapshot include children"]
    bool S_MlSnapshotIncludeChildren = true;

    [Setting hidden name="UiNav debug snapshot max depth"]
    int S_MlSnapshotMaxDepth = 2;

    [Setting hidden name="UiNav debug snapshot apply include children"]
    bool S_MlSnapshotApplyChildren = false;

    string g_MlSnapshotApplySelector = "";
    string g_MlSnapshotStatus = "";

    [Setting hidden name="UiNav debug style pack file path"]
    string S_MlStylePackPath = IO::FromStorageFolder("Exports/ManiaLinks/uinav_ml_style_pack.json");

    [Setting hidden name="UiNav debug style pack include children"]
    bool S_MlStylePackIncludeChildren = false;

    [Setting hidden name="UiNav debug style pack max depth"]
    int S_MlStylePackMaxDepth = 1;

    [Setting hidden name="UiNav debug style pack include text values"]
    bool S_MlStylePackIncludeTextValues = false;

    [Setting hidden name="UiNav debug style pack apply children"]
    bool S_MlStylePackApplyChildren = false;

    array<MlStyleCaptureEntry@> g_MlStylePackEntries;
    string g_MlStylePackStatus = "";

    [Setting hidden name="ML dump file path"]
    string S_MlDumpPath = IO::FromStorageFolder("Exports/Dumps/uinav_ml_dump.txt");

    [Setting hidden name="ML dump depth"]
    int S_MlDumpDepth = 8;

    [Setting hidden name="ML dump layer index (-1 = all)"]
    int S_MlDumpLayerIndex = -1;

    [Setting hidden name="ML dump selector chains"]
    string S_MlDumpSelectorChains = "";

    [Setting hidden name="ML dump selector children only"]
    bool S_MlDumpSelectorChildrenOnly = true;

    [Setting hidden name="ML dump only open paths"]
    bool S_MlDumpOnlyOpenPaths = false;

    [Setting hidden name="ControlTree dump file path"]
    string S_ControlTreeDumpPath = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_dump.txt");

    [Setting hidden name="ControlTree dump overlay"]
    uint S_ControlTreeDumpOverlay = 16;

    [Setting hidden name="ControlTree dump depth"]
    int S_ControlTreeDumpDepth = 6;

    [Setting hidden name="ControlTree dump start path"]
    string S_ControlTreeDumpStartPath = "";

    string g_LastMlDumpStatus = "";
    string g_LastMlDumpPath = "";
    uint g_LastMlDumpLines = 0;

    string g_LastMlPageDumpStatus = "";
    string g_LastMlPageDumpPath = "";
    uint g_LastMlPageDumpChars = 0;

    string g_LastControlTreeDumpStatus = "";
    string g_LastControlTreeDumpPath = "";
    uint g_LastControlTreeDumpLines = 0;

    [Setting hidden name="UiNav debug: diag step logs"]
    bool S_DiagStepLogs = false;

    [Setting hidden name="UiNav debug: diag verbose (spammy)"]
    bool S_DiagVerbose = false;

    [Setting hidden name="UiNav debug: breadcrumb file enabled"]
    bool S_DiagBreadcrumbFile = false;

    [Setting hidden name="UiNav debug: breadcrumb file path"]
    string S_DiagBreadcrumbPath = IO::FromStorageFolder("Diagnostics/uinav_debug_breadcrumb.txt");

    [Setting hidden name="UiNav debug: breadcrumb throttle (ms, 0 = always)"]
    uint S_DiagBreadcrumbThrottleMs = 25;

    uint g_DiagBreadcrumbLastWriteMs = 0;
    string g_DiagBreadcrumbLastStep = "";
    string g_DiagBreadcrumbLastFn = "";
    string g_UiNavOwnedLayerCleanupStatus = "";

    void _DiagBreadcrumb(const string &in step, const string &in fn = "UiNavDebug", bool forceWrite = false) {
        g_DiagBreadcrumbLastStep = step;
        g_DiagBreadcrumbLastFn = fn;

        if (!S_DiagBreadcrumbFile) return;
        if (S_DiagBreadcrumbPath.Length == 0) return;

        uint now = Time::Now;
        if (!forceWrite && S_DiagBreadcrumbThrottleMs > 0) {
            uint delta = now - g_DiagBreadcrumbLastWriteMs;
            if (delta < S_DiagBreadcrumbThrottleMs) return;
        }

        g_DiagBreadcrumbLastWriteMs = now;

        string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
        string msg = ts + " | " + g_DiagBreadcrumbLastFn + " | " + g_DiagBreadcrumbLastStep + "\n";
        msg += "mode=" + (g_Mode == Mode::ML ? "ML" : "ControlTree")
            + " mlAppKind=" + g_MlActiveAppKind
            + " mlSearchLen=" + g_MlSearch.Length
            + " mlViewLayerIx=" + g_MlViewLayerIndex
            + " controlTreeOverlay=" + g_ControlTreeOverlay
            + " controlTreeSearchLen=" + g_ControlTreeSearch.Length
            + " selMl=" + g_SelectedMlUiPath
            + " selControlTree=" + g_SelectedControlTreeUiPath
            + "\n";
        _IO::File::WriteFile(S_DiagBreadcrumbPath, msg, false);
    }

    bool _DiagShouldLog(bool force = false) {
        if (!S_DiagStepLogs) return false;
        if (S_DiagVerbose) return true;
        return force;
    }

    void _DiagStep(const string &in step, const string &in fn = "UiNavDebug", bool force = false) {
        _DiagBreadcrumb(step, fn, force);
        if (!_DiagShouldLog(force)) return;
        log("UiNavDebug STEP " + step, LogLevel::Info, -1, fn);
    }

    string _NormPathForCompare(const string &in p) {
        string n = p.Trim();
        n = n.Replace("\\", "/");
        return n.ToLower();
    }

    string _MigratePathSettingValue(const string &in cur, const string &in oldRel, const string &in newRel) {
        string newAbs = IO::FromStorageFolder(newRel);
        string oldAbs = IO::FromStorageFolder(oldRel);
        string curTrim = cur.Trim();
        if (curTrim.Length == 0) {
            return newAbs;
        }

        string normCur = _NormPathForCompare(curTrim);
        if (normCur == _NormPathForCompare(oldAbs) || normCur == oldRel.ToLower()) {
            return newAbs;
        }
        return curTrim;
    }

    void _MigrateLegacyLogOutputPaths() {
        S_MlSnapshotPath = _MigratePathSettingValue(S_MlSnapshotPath, "Logs/uinav_ml_snapshot.json", "Exports/ManiaLinks/uinav_ml_snapshot.json");
        S_MlStylePackPath = _MigratePathSettingValue(S_MlStylePackPath, "Logs/uinav_ml_style_pack.json", "Exports/ManiaLinks/uinav_ml_style_pack.json");
        S_MlDumpPath = _MigratePathSettingValue(S_MlDumpPath, "Logs/uinav_ml_dump.txt", "Exports/Dumps/uinav_ml_dump.txt");
        S_ControlTreeDumpPath = _MigratePathSettingValue(S_ControlTreeDumpPath, "Logs/uinav_control_tree_dump.txt", "Exports/Dumps/uinav_control_tree_dump.txt");
        S_DiagBreadcrumbPath = _MigratePathSettingValue(S_DiagBreadcrumbPath, "Logs/uinav_debug_breadcrumb.txt", "Diagnostics/uinav_debug_breadcrumb.txt");
    }

    void _EnsureUiStateInit() {
        if (!g_WidthsInit) {
            g_MlTreeWidth = S_MlTreeWidth;
            g_ControlTreeTreeWidth = S_ControlTreeTreeWidth;
            _MigrateLegacyLogOutputPaths();
            g_WidthsInit = true;
        }
    }

    void _RenderDiagnosticsPanel() {
        string bcIndicator = S_DiagBreadcrumbFile
            ? "  \\$9fd" + Icons::Play + "\\$z"
            : "  \\$888" + Icons::Stop + "\\$z";
        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader(Icons::Wrench + " Crash Breadcrumbs" + bcIndicator + "##diag-bc")) {
            S_DiagBreadcrumbFile = UI::Checkbox("Enabled##diag-bc", S_DiagBreadcrumbFile);
            if (UI::IsItemHovered()) UI::SetTooltip("Write last-known step to a file for post-crash analysis");

            UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 38.0f);
            S_DiagBreadcrumbPath = UI::InputText("##diag-bc-path", S_DiagBreadcrumbPath);
            if (UI::IsItemHovered()) UI::SetTooltip(S_DiagBreadcrumbPath);
            UI::SameLine();
            if (UI::Button(Icons::FolderOpenO + "##diag-bc-open")) {
                string folder = Path::GetDirectoryName(S_DiagBreadcrumbPath);
                if (folder.Length == 0) folder = IO::FromStorageFolder("Diagnostics");
                _IO::OpenFolder(folder, true);
            }
            if (UI::IsItemHovered()) UI::SetTooltip("Open breadcrumb folder");

            UI::SetNextItemWidth(120.0f);
            int bcThrottle = int(S_DiagBreadcrumbThrottleMs);
            bcThrottle = UI::InputInt("Throttle (ms)##diag-bc", bcThrottle);
            if (bcThrottle < 0) bcThrottle = 0;
            S_DiagBreadcrumbThrottleMs = uint(bcThrottle);

            if (g_DiagBreadcrumbLastStep.Length > 0) {
                string lastInfo = "\\$bff" + Icons::ChevronRight + "\\$z " + g_DiagBreadcrumbLastStep;
                if (g_DiagBreadcrumbLastFn.Length > 0) lastInfo += "  \\$888(" + g_DiagBreadcrumbLastFn + ")\\$z";
                UI::Text(lastInfo);
            } else {
                UI::TextDisabled("No breadcrumb step recorded yet.");
            }
        }

        string trCountLabel = "  \\$888[" + UiNav::Trace::g_Buf.Length + "/" + UiNav::Trace::S_MaxEntries + "]\\$z";
        string trIndicator = UiNav::Trace::Enabled()
            ? "  \\$9fd" + Icons::Play + "\\$z"
            : "  \\$888" + Icons::Stop + "\\$z";
        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader(Icons::Refresh + " Trace Ring Buffer" + trIndicator + trCountLabel + "##diag-tr")) {
            UiNav::Trace::S_Enabled = UI::Checkbox("Enabled##diag-tr", UiNav::Trace::S_Enabled);
            UI::SameLine();
            UI::SetNextItemWidth(120.0f);
            int trMax = int(UiNav::Trace::S_MaxEntries);
            trMax = UI::InputInt("Max entries##diag-tr", trMax);
            if (trMax < 0) trMax = 0;
            UiNav::Trace::S_MaxEntries = uint(trMax);

            if (UI::Button(Icons::Play + " Dump##diag-tr")) UiNav::Trace::DumpToLog();
            if (UI::IsItemHovered()) UI::SetTooltip("Dump trace entries to Openplanet log");
            UI::SameLine();
            if (UI::Button(Icons::TrashO + " Clear##diag-tr")) UiNav::Trace::Clear();
            if (UI::IsItemHovered()) UI::SetTooltip("Clear all trace entries");
            UI::SameLine();
            if (UI::Button(Icons::Clipboard + " Copy##diag-tr")) {
                string traceText = "";
                uint trN = UiNav::Trace::g_Buf.Length;
                if (trN > 0) {
                    if (!UiNav::Trace::g_Filled) {
                        for (uint ti = 0; ti < trN; ++ti) {
                            auto te = UiNav::Trace::g_Buf[ti];
                            if (te !is null) traceText += tostring(te.ms) + " " + te.msg + "\n";
                        }
                    } else {
                        for (uint ti = 0; ti < trN; ++ti) {
                            uint tix = (UiNav::Trace::g_NextIx + ti) % trN;
                            auto te = UiNav::Trace::g_Buf[tix];
                            if (te !is null) traceText += tostring(te.ms) + " " + te.msg + "\n";
                        }
                    }
                }
                IO::SetClipboard(traceText.Length > 0 ? traceText : "(empty trace)");
            }
            if (UI::IsItemHovered()) UI::SetTooltip("Copy trace buffer to clipboard");

            float trViewH = 180.0f;
            if (UI::BeginChild("##diag-tr-viewer", vec2(0, trViewH), true)) {
                uint trN = UiNav::Trace::g_Buf.Length;
                if (trN == 0) {
                    UI::TextDisabled("Trace is empty.");
                    UI::TextDisabled("Enable trace and interact with UiNav to populate.");
                } else if (!UiNav::Trace::g_Filled) {
                    for (uint ti = 0; ti < trN; ++ti) {
                        auto te = UiNav::Trace::g_Buf[ti];
                        if (te is null) continue;
                        UI::Text("\\$888" + tostring(te.ms) + "\\$z " + te.msg);
                    }
                } else {
                    for (uint ti = 0; ti < trN; ++ti) {
                        uint tix = (UiNav::Trace::g_NextIx + ti) % trN;
                        auto te = UiNav::Trace::g_Buf[tix];
                        if (te is null) continue;
                        UI::Text("\\$888" + tostring(te.ms) + "\\$z " + te.msg);
                    }
                }
            }
            UI::EndChild();
        }

        string slIndicator = S_DiagStepLogs
            ? "  \\$9fd" + Icons::Play + "\\$z"
            : "  \\$888" + Icons::Stop + "\\$z";
        UI::SetNextItemOpen(false, UI::Cond::Appearing);
        if (UI::CollapsingHeader(Icons::Cog + " Step Logging" + slIndicator + "##diag-sl")) {
            S_DiagStepLogs = UI::Checkbox("Enable step logs##diag-sl", S_DiagStepLogs);
            if (UI::IsItemHovered()) UI::SetTooltip("Log per-operation diagnostic steps to Openplanet log");
            UI::SameLine();
            S_DiagVerbose = UI::Checkbox("Verbose##diag-sl", S_DiagVerbose);
            if (UI::IsItemHovered()) UI::SetTooltip("Include all verbose steps (very spammy!)");
            UI::TextDisabled("Step logs write per-operation entries to the Openplanet log.");
            if (S_DiagVerbose) {
                UI::Text("\\$fa0" + Icons::ExclamationTriangle + " Verbose mode active \\$888- expect heavy log output.\\$z");
            }
        }

        UI::SetNextItemOpen(false, UI::Cond::Appearing);
        if (UI::CollapsingHeader(Icons::Exchange + " Request Pump Policy##diag-rp")) {
            int policy = UiNav::Dump::GetRequestPumpPolicy();
            const string[] policyLabels = {"Disabled", "Dev-only", "Always"};
            const string[] policyColors = {"\\$888", "\\$fd8", "\\$9fd"};

            UI::SetNextItemWidth(200.0f);
            policy = UI::SliderInt("##diag-rp-slider", policy, 0, 2);
            UiNav::Dump::SetRequestPumpPolicy(policy);
            if (policy >= 0 && policy < int(policyLabels.Length)) {
                UI::SameLine();
                UI::Text(policyColors[policy] + policyLabels[policy] + "\\$z");
            }

            bool pumpActive = UiNav::Dump::RequestPumpEnabledNow();
            UI::Text("Pump: " + (pumpActive
                ? "\\$9fd" + Icons::Play + " Active\\$z"
                : "\\$888" + Icons::Stop + " Inactive\\$z"));
        }
    }

    void _DestroyAllUiNavOwnedLayersNow() {
        UiNav::Layers::DestroyAllOwned();
        uint swept = UiNav::Layers::LastDestroyAllOwnedSweepCount();
        g_UiNavOwnedLayerCleanupStatus = "Destroyed all UiNav-owned layers (registry + prefix sweep: " + swept + ").";
        UI::ShowNotification("UiNav", g_UiNavOwnedLayerCleanupStatus, 4500);
    }

    void _RenderUiNavOwnedLayersCleanupBar() {
        if (UI::Button("Destroy all UiNav layers")) {
            _DestroyAllUiNavOwnedLayersNow();
        }
        UI::SameLine();
        UI::TextDisabled("Clears plugin-owned layers (typically UiNav_*)");
        if (g_UiNavOwnedLayerCleanupStatus.Length > 0) UI::Text(g_UiNavOwnedLayerCleanupStatus);
    }

    void RenderGeneralSettingsUI() {
        _EnsureUiStateInit();
        bool open = UI::BeginChild(
            "##uinav-settings-general-root",
            vec2(0, 0),
            false,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (open) {
            UI::Text("UiNav - General");
            UI::TextDisabled("Shared maintenance actions for all UiNav debug tools.");
            bool showDevTabs = S_ShowUiNavDev;
            showDevTabs = UI::Checkbox("Show dev tabs", showDevTabs);
            if (showDevTabs != S_ShowUiNavDev) S_ShowUiNavDev = showDevTabs;
            UI::TextDisabled("Enables: Selector, ManiaLink UI, ControlTree UI, ManiaLink Builder, ManiaLink Browser, Diagnostics.");
            UI::Separator();
            _RenderUiNavOwnedLayersCleanupBar();
        }
        UI::EndChild();
    }

    void RenderManiaLinkUiSettingsUI() {
        _EnsureUiStateInit();
        bool open = UI::BeginChild(
            "##uinav-settings-ml-root",
            vec2(0, 0),
            false,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (open) {
            UI::Text("UiNav - ManiaLink UI Inspector");
            _RenderMlTab();
        }
        UI::EndChild();
    }

    void RenderControlTreeUiSettingsUI() {
        _EnsureUiStateInit();
        bool open = UI::BeginChild(
            "##uinav-settings-controltree-root",
            vec2(0, 0),
            false,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (open) {
            UI::Text("UiNav - ControlTree UI Inspector");
            _RenderControlTreeTab();
        }
        UI::EndChild();
    }

    void RenderManiaLinkBrowserSettingsUI() {
        _EnsureUiStateInit();
        bool open = UI::BeginChild(
            "##uinav-settings-browser-root",
            vec2(0, 0),
            false,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (open) {
            UI::Text("UiNav - ManiaLink Browser");
            _RenderMlBrowserTab();
        }
        UI::EndChild();
    }

    void RenderDiagnosticsSettingsUI() {
        _EnsureUiStateInit();
        bool diagOpen = UI::BeginChild(
            "##uinav-settings-diag-root",
            vec2(0, 0),
            false
        );
        if (diagOpen) {
            UI::Text("UiNav - Diagnostics");
            UI::TextDisabled("Crash breadcrumbs, trace buffer, and runtime diagnostics.");
            UI::Separator();
            _RenderDiagnosticsPanel();
        }
        UI::EndChild();
    }

}
}
