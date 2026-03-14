namespace UiNav {
namespace Layers {

    [Setting hidden name="UiNav: enable layer req cache"]
    bool S_LayerReqCacheEnabled = true;

    [Setting hidden name="UiNav: persist layer req cache"]
    bool S_LayerReqCachePersist = true;

    [Setting hidden name="UiNav: layer req cache path"]
    string S_LayerReqCachePath = IO::FromStorageFolder("UiNav/LayerReqCache.cfg");

    [Setting hidden name="UiNav: layer req cache save throttle (ms)"]
    uint S_LayerReqCacheSaveThrottleMs = 5000;

    [Setting hidden name="UiNav: enable layer req frame memo"]
    bool S_LayerReqFrameMemoEnabled = true;

    [Setting hidden name="UiNav: layer req frame memo max entries"]
    uint S_LayerReqFrameMemoMax = 256;

    [Setting hidden name="UiNav: persist owned layers across reloads"]
    bool S_PersistOwnedLayersAcrossReloads = true;

    [Setting hidden name="UiNav: owned layers state path"]
    string S_OwnedLayersStatePath = IO::FromStorageFolder("UiNav/OwnedLayersState.json");

    class LayerReqCacheEntry {
        int lastIx = -1;
        CGameUILayer@ lastLayer = null;
        CGameManialinkPage@ lastLocalPage = null;
        uint lastOkMs = 0;
    }

    dictionary g_LayerReqCache;
    bool g_LayerReqCacheLoaded = false;
    bool g_LayerReqCacheDirty = false;
    uint g_LayerReqCacheLastSaveMs = 0;

    class LayerReqFrameMemoEntry {
        ManiaLinkSource source = ManiaLinkSource::CurrentApp;
        CGameManiaApp@ app = null;
        int layerIx = -1;
    }

    const int kLayerReqFrameMemoMiss = -2;
    dictionary g_LayerReqFrameMemo;
    array<string> g_LayerReqFrameMemoKeys;
    uint g_LayerReqFrameMemoAtMs = 0;
    uint g_LayerReqFrameMemoHits = 0;
    uint g_LayerReqFrameMemoMisses = 0;
    uint g_LayerReqFrameMemoNegativeHits = 0;

    uint g_LayerReqCacheHits = 0;
    uint g_LayerReqCacheMisses = 0;

    string _LayerReqKey(const ManiaLinkReq@ req) {
        if (req is null) return "";
        string k = "s=" + tostring(int(req.source));
        k += (req.mustBeVisible ? "|v1" : "|v0");
        k += (req.mustHaveLocalPage ? "|p1" : "|p0");
        if (req.pageNeedle.Length > 0) k += "|n=" + req.pageNeedle;
        if (req.rootControlId.Length > 0) k += "|id=" + req.rootControlId;
        return k;
    }

    string _LayerReqFrameMemoKey(const ManiaLinkReq@ req) {
        if (req is null) return "";
        string key = _LayerReqKey(req);
        if (key.Length == 0) return "";
        string hintsKey = _LayerReqHintsKey(req);
        if (hintsKey.Length > 0) key += "|h=" + hintsKey;
        return key;
    }

    void _AppendLayerIxHintUnique(array<int> &out hints, int ix) {
        if (ix < 0) return;
        for (uint i = 0; i < hints.Length; ++i) {
            if (hints[i] == ix) return;
        }
        hints.InsertLast(ix);
    }

    void _CollectLayerIxHints(const ManiaLinkReq@ req, array<int> &out hints) {
        hints.Resize(0);
        if (req is null) return;

        for (uint i = 0; i < req.layerIxHints.Length; ++i) {
            _AppendLayerIxHintUnique(hints, req.layerIxHints[i]);
        }
        _AppendLayerIxHintUnique(hints, req.layerIxHint);
    }

    string _LayerReqHintsKey(const ManiaLinkReq@ req) {
        array<int> hints;
        _CollectLayerIxHints(req, hints);
        if (hints.Length == 0) return "";

        string outKey = "";
        for (uint i = 0; i < hints.Length; ++i) {
            if (i > 0) outKey += ",";
            outKey += tostring(hints[i]);
        }
        return outKey;
    }

    void _ClearLayerReqFrameMemo() {
        g_LayerReqFrameMemo.DeleteAll();
        g_LayerReqFrameMemoKeys.Resize(0);
    }

    void _RotateLayerReqFrameMemoIfNeeded(uint nowMs) {
        if (g_LayerReqFrameMemoAtMs == nowMs) return;
        g_LayerReqFrameMemoAtMs = nowMs;
        _ClearLayerReqFrameMemo();
    }

    bool _TryLayerReqFrameMemo(const string &in key, ManiaLinkSource source, CGameManiaApp@ app, const ManiaLinkReq@ req, CGameUILayer@ &out layer, int &out layerIx) {
        layerIx = -1;
        @layer = null;
        if (!S_LayerReqFrameMemoEnabled) return false;
        if (key.Length == 0 || req is null) return false;

        _RotateLayerReqFrameMemoIfNeeded(Time::Now);

        LayerReqFrameMemoEntry@ e;
        if (!g_LayerReqFrameMemo.Get(key, @e) || e is null) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }
        if (e.source != source) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }
        if (e.app !is app) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }
        if (e.layerIx == kLayerReqFrameMemoMiss) {
            g_LayerReqFrameMemoNegativeHits++;
            return true;
        }
        uint layersLen = _LayerCountForSource(source, app);
        if (e.layerIx < 0 || e.layerIx >= int(layersLen)) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }

        auto cand = _LayerAtSource(source, app, uint(e.layerIx));
        if (cand is null) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }
        if (!_Matches(req, cand)) {
            g_LayerReqFrameMemoMisses++;
            return false;
        }

        layerIx = e.layerIx;
        @layer = cand;
        g_LayerReqFrameMemoHits++;
        return true;
    }

    void _SetLayerReqFrameMemo(const string &in key, ManiaLinkSource source, CGameManiaApp@ app, int layerIx) {
        if (!S_LayerReqFrameMemoEnabled) return;
        if (key.Length == 0) return;

        _RotateLayerReqFrameMemoIfNeeded(Time::Now);

        LayerReqFrameMemoEntry@ e;
        bool existed = g_LayerReqFrameMemo.Get(key, @e) && e !is null;
        if (!existed) {
            @e = LayerReqFrameMemoEntry();
            g_LayerReqFrameMemoKeys.InsertLast(key);
            if (S_LayerReqFrameMemoMax > 0 && g_LayerReqFrameMemoKeys.Length > S_LayerReqFrameMemoMax) {
                string old = g_LayerReqFrameMemoKeys[0];
                g_LayerReqFrameMemoKeys.RemoveAt(0);
                g_LayerReqFrameMemo.Delete(old);
            }
        }

        e.source = source;
        @e.app = app;
        e.layerIx = layerIx;
        g_LayerReqFrameMemo.Set(key, @e);
    }

    LayerReqCacheEntry@ _GetLayerReqCache(const string &in key, bool createIfMissing = false) {
        if (key.Length == 0) return null;
        LayerReqCacheEntry@ e;
        if (g_LayerReqCache.Get(key, @e)) return e;
        if (!createIfMissing) return null;
        @e = LayerReqCacheEntry();
        g_LayerReqCache.Set(key, @e);
        return e;
    }

    void _LoadLayerReqCache() {
        g_LayerReqCache.DeleteAll();
        if (!S_LayerReqCachePersist) return;
        if (S_LayerReqCachePath.Length == 0) return;
        if (!IO::FileExists(S_LayerReqCachePath)) return;

        IO::File f(S_LayerReqCachePath, IO::FileMode::Read);
        array<string>@ lines = f.ReadToEnd().Split("\n");
        f.Close();

        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i].Trim();
            if (ln.Length == 0 || ln.StartsWith("#")) continue;

            int sep = ln.IndexOf("\t");
            if (sep < 0) sep = ln.IndexOf("=");
            if (sep < 0) continue;

            string key = ln.SubStr(0, sep).Trim();
            string rhs = ln.SubStr(sep + 1).Trim();
            if (key.Length == 0 || rhs.Length == 0) continue;

            int ix = Text::ParseInt(rhs);
            if (ix < 0) continue;

            auto e = _GetLayerReqCache(key, true);
            if (e is null) continue;
            e.lastIx = ix;
        }
    }

    void _EnsureLayerReqCacheLoaded() {
        if (g_LayerReqCacheLoaded) return;
        g_LayerReqCacheLoaded = true;
        _LoadLayerReqCache();
    }

    void _SaveLayerReqCache() {
        if (!S_LayerReqCachePersist) return;
        if (S_LayerReqCachePath.Length == 0) return;

        string outText = "# UiNav LayerReqCache.cfg - generated by UiNav v2 (best-effort hints)\n";
        outText += "# Format: <LayerReqKey>\\t<UILayerIndex>\n";

        array<string> keys = g_LayerReqCache.GetKeys();
        keys.SortAsc();
        for (uint i = 0; i < keys.Length; ++i) {
            string key = keys[i];
            LayerReqCacheEntry@ e;
            if (!g_LayerReqCache.Get(key, @e) || e is null) continue;
            if (e.lastIx < 0) continue;
            outText += key + "\t" + tostring(e.lastIx) + "\n";
        }
        _IO::File::WriteFile(S_LayerReqCachePath, outText, false);
    }

    void _MarkLayerReqCacheDirty() {
        g_LayerReqCacheDirty = true;
    }

    void _MaybeSaveLayerReqCache() {
        if (!g_LayerReqCacheDirty) return;
        if (!S_LayerReqCachePersist) return;
        if (S_LayerReqCacheSaveThrottleMs > 0) {
            uint now = Time::Now;
            uint delta = now - g_LayerReqCacheLastSaveMs;
            if (delta < S_LayerReqCacheSaveThrottleMs) return;
            g_LayerReqCacheLastSaveMs = now;
        }
        _SaveLayerReqCache();
        g_LayerReqCacheDirty = false;
    }

    void OnContextEpochChanged() {
        _ClearLayerReqFrameMemo();

        array<string> keys = g_LayerReqCache.GetKeys();
        for (uint i = 0; i < keys.Length; ++i) {
            LayerReqCacheEntry@ e;
            if (!g_LayerReqCache.Get(keys[i], @e) || e is null) continue;
            @e.lastLayer = null;
            @e.lastLocalPage = null;
            e.lastOkMs = 0;
        }
    }

    uint LayerReqFrameMemoHits() { return g_LayerReqFrameMemoHits; }
    uint LayerReqFrameMemoMisses() { return g_LayerReqFrameMemoMisses; }
    uint LayerReqFrameMemoNegativeHits() { return g_LayerReqFrameMemoNegativeHits; }
    uint LayerReqCacheHits() { return g_LayerReqCacheHits; }
    uint LayerReqCacheMisses() { return g_LayerReqCacheMisses; }

    void ResetCacheStats() {
        g_LayerReqFrameMemoHits = 0;
        g_LayerReqFrameMemoMisses = 0;
        g_LayerReqFrameMemoNegativeHits = 0;
        g_LayerReqCacheHits = 0;
        g_LayerReqCacheMisses = 0;
    }

    CGameManiaApp@ GetManiaApp() {
        auto app = GetApp();
        auto ma = cast<CGameManiaApp>(app);
        if (ma !is null) return ma;

        auto tm = cast<CTrackMania>(app);
        if (tm !is null && tm.Network !is null && tm.Network.ClientManiaAppPlayground !is null) {
            @ma = cast<CGameManiaApp>(tm.Network.ClientManiaAppPlayground);
            if (ma !is null) return ma;
        }
        return null;
    }

    CGameManiaApp@ GetManiaApp(ManiaLinkSource source) {
        if (source == ManiaLinkSource::Menu) return GetManiaAppMenu();
        if (source == ManiaLinkSource::Playground) return GetManiaAppPlayground();
        return GetManiaApp();
    }

    CGameManiaApp@ GetManiaAppPlayground() {
        auto tm = GetTmApp();
        if (tm !is null && tm.Network !is null && tm.Network.ClientManiaAppPlayground !is null) {
            return cast<CGameManiaApp>(tm.Network.ClientManiaAppPlayground);
        }
        return null;
    }

    CGameManiaApp@ GetManiaAppMenu() {
        auto tm = GetTmApp();
        if (tm !is null && tm.MenuManager !is null && tm.MenuManager.MenuCustom_CurrentManiaApp !is null) {
            auto menuMa = cast<CGameManiaApp>(tm.MenuManager.MenuCustom_CurrentManiaApp);
            if (menuMa !is null) return menuMa;
        }

        auto app = GetApp();
        auto ma = cast<CGameManiaApp>(app);
        if (ma !is null) return ma;
        return null;
    }

    CTrackMania@ GetTmApp() {
        return cast<CTrackMania>(GetApp());
    }

    CGameCtnEditorCommon@ _GetEditorCommon() {
        auto tm = GetTmApp();
        if (tm is null || tm.Editor is null) return null;
        return cast<CGameCtnEditorCommon>(tm.Editor);
    }

    bool _ResolveLayerSource(ManiaLinkSource requested, ManiaLinkSource &out resolved, CGameManiaApp@ &out app) {
        resolved = requested;
        @app = null;

        if (requested == ManiaLinkSource::Menu) {
            @app = GetManiaAppMenu();
            return app !is null;
        }

        if (requested == ManiaLinkSource::Playground) {
            @app = GetManiaAppPlayground();
            return app !is null;
        }

        if (requested == ManiaLinkSource::Editor) {
            auto editor = _GetEditorCommon();
            return editor !is null && editor.PluginMapType !is null;
        }

        @app = GetManiaApp();
        if (app !is null) {
            auto menu = GetManiaAppMenu();
            if (menu !is null && app is menu) resolved = ManiaLinkSource::Menu;
            else {
                auto pg = GetManiaAppPlayground();
                if (pg !is null && app is pg) resolved = ManiaLinkSource::Playground;
            }
            return true;
        }

        auto editor = _GetEditorCommon();
        if (editor !is null && editor.PluginMapType !is null) {
            resolved = ManiaLinkSource::Editor;
            return true;
        }

        return false;
    }

    uint _LayerCountForSource(ManiaLinkSource source, CGameManiaApp@ app) {
        if (source == ManiaLinkSource::Editor) {
            auto editor = _GetEditorCommon();
            if (editor is null || editor.PluginMapType is null) return 0;
            return editor.PluginMapType.UILayers.Length;
        }

        if (app is null) return 0;
        return app.UILayers.Length;
    }

    CGameUILayer@ _LayerAtSource(ManiaLinkSource source, CGameManiaApp@ app, uint ix) {
        if (source == ManiaLinkSource::Editor) {
            auto editor = _GetEditorCommon();
            if (editor is null || editor.PluginMapType is null) return null;
            auto layers = editor.PluginMapType.UILayers;
            if (ix >= layers.Length) return null;
            return layers[ix];
        }

        if (app is null) return null;
        auto layers = app.UILayers;
        if (ix >= layers.Length) return null;
        return layers[ix];
    }

    CGamePlayground@ GetPlayground() {
        auto tm = GetTmApp();
        if (tm is null) return null;
        return tm.CurrentPlayground;
    }

    bool _LayerIsVisibleBestEffort(CGameUILayer@ layer) {
        if (layer is null) return false;
        return layer.IsVisible;
    }

    bool _LayerHasLocalPageBestEffort(CGameUILayer@ layer) {
        if (layer is null) return false;
        return layer.LocalPage !is null;
    }

    bool LayerLooksActiveBestEffort(CGameUILayer@ layer) {
        if (layer is null) return false;
        if (!_LayerIsVisibleBestEffort(layer)) return false;
        if (!_LayerHasLocalPageBestEffort(layer)) return false;

        auto page = layer.LocalPage;
        if (page is null) return false;
        return page.MainFrame !is null;
    }

    CGameUILayer@ FindLayer(const ManiaLinkReq@ req) {
        int ix = -1;
        return FindLayer(req, ix);
    }

    CGameUILayer@ FindLayer(const ManiaLinkReq@ req, int &out layerIx, const string &in preCacheKey = "", const string &in preFrameMemoKey = "") {
        layerIx = -1;
        if (req is null) return null;

        ManiaLinkSource source = req.source;
        CGameManiaApp@ app = null;
        if (!_ResolveLayerSource(req.source, source, app)) return null;

        uint layersLen = _LayerCountForSource(source, app);
        if (layersLen == 0) return null;

        _EnsureLayerReqCacheLoaded();

        string cacheKey = preCacheKey;
        if (cacheKey.Length == 0 && (S_LayerReqCacheEnabled || S_LayerReqCachePersist)) {
            cacheKey = _LayerReqKey(req);
        }

        string frameMemoKey = preFrameMemoKey;
        if (frameMemoKey.Length == 0 && S_LayerReqFrameMemoEnabled) {
            frameMemoKey = _LayerReqFrameMemoKey(req);
        }

        if (frameMemoKey.Length > 0) {
            CGameUILayer@ memoLayer = null;
            int memoIx = -1;
            if (_TryLayerReqFrameMemo(frameMemoKey, source, app, req, memoLayer, memoIx)) {
                layerIx = memoIx;
                return memoLayer;
            }
        }

        bool dynCacheAttempted = false;
        bool dynCacheHit = false;

        if (S_LayerReqCacheEnabled && cacheKey.Length > 0) {
            dynCacheAttempted = true;
            auto e = _GetLayerReqCache(cacheKey, false);
            if (e !is null) {
                int ix = e.lastIx;
                if (ix >= 0 && ix < int(layersLen)) {
                    auto cand = _LayerAtSource(source, app, uint(ix));
                    bool basicOk = true;
                    if (req.mustBeVisible && !_LayerIsVisibleBestEffort(cand)) basicOk = false;
                    if (basicOk && req.mustHaveLocalPage && !_LayerHasLocalPageBestEffort(cand)) basicOk = false;

                    if (basicOk && cand is e.lastLayer) {
                        if (!req.mustHaveLocalPage || (e.lastLocalPage !is null && cand.LocalPage is e.lastLocalPage)) {
                            layerIx = ix;
                            e.lastOkMs = Time::Now;
                            dynCacheHit = true;
                            g_LayerReqCacheHits++;
                            _SetLayerReqFrameMemo(frameMemoKey, source, app, layerIx);
                            return cand;
                        }
                    }

                    if (basicOk && _Matches(req, cand)) {
                        layerIx = ix;
                        @e.lastLayer = cand;
                        @e.lastLocalPage = cand.LocalPage;
                        e.lastOkMs = Time::Now;
                        dynCacheHit = true;
                        g_LayerReqCacheHits++;
                        _SetLayerReqFrameMemo(frameMemoKey, source, app, layerIx);
                        return cand;
                    }
                }
            }
        }

        if (dynCacheAttempted && !dynCacheHit) {
            g_LayerReqCacheMisses++;
        }

        array<int> layerHints;
        _CollectLayerIxHints(req, layerHints);
        for (uint h = 0; h < layerHints.Length; ++h) {
            int hintIx = layerHints[h];
            if (hintIx < 0) continue;
            uint ix = uint(hintIx);
            if (ix < layersLen) {
                auto cand = _LayerAtSource(source, app, ix);
                if (_Matches(req, cand)) {
                    layerIx = int(ix);
                    if (cacheKey.Length > 0) {
                        auto e = _GetLayerReqCache(cacheKey, /*createIfMissing=*/true);
                        if (e !is null && e.lastIx != layerIx) {
                            e.lastIx = layerIx;
                            _MarkLayerReqCacheDirty();
                        }
                        if (e !is null) {
                            @e.lastLayer = cand;
                            @e.lastLocalPage = cand.LocalPage;
                        }
                        if (e !is null) e.lastOkMs = Time::Now;
                    }
                    _MaybeSaveLayerReqCache();
                    _SetLayerReqFrameMemo(frameMemoKey, source, app, layerIx);
                    return cand;
                }
            }
        }

        for (uint i = 0; i < layersLen; ++i) {
            auto layer = _LayerAtSource(source, app, i);
            if (!_Matches(req, layer)) continue;

            layerIx = int(i);
            if (cacheKey.Length > 0) {
                auto e = _GetLayerReqCache(cacheKey, /*createIfMissing=*/true);
                if (e !is null && e.lastIx != layerIx) {
                    e.lastIx = layerIx;
                    _MarkLayerReqCacheDirty();
                }
                if (e !is null) {
                    @e.lastLayer = layer;
                    @e.lastLocalPage = layer.LocalPage;
                }
                if (e !is null) e.lastOkMs = Time::Now;
            }
            _MaybeSaveLayerReqCache();
            _SetLayerReqFrameMemo(frameMemoKey, source, app, layerIx);
            return layer;
        }

        _MaybeSaveLayerReqCache();
        _SetLayerReqFrameMemo(frameMemoKey, source, app, kLayerReqFrameMemoMiss);
        return null;
    }

    bool _Matches(const ManiaLinkReq@ req, CGameUILayer@ layer) {
        if (layer is null) return false;

        if (req.mustBeVisible) {
            if (!_LayerIsVisibleBestEffort(layer)) return false;
        }

        if (req.mustHaveLocalPage) {
            if (!_LayerHasLocalPageBestEffort(layer)) return false;
        }

        if (req.pageNeedle.Length > 0) {
            bool ok = false;
            string page = layer.ManialinkPage;
            if (page.IndexOf(req.pageNeedle) >= 0) ok = true;
            if (!ok) {
                string pageUtf8 = layer.ManialinkPageUtf8;
                if (pageUtf8.IndexOf(req.pageNeedle) >= 0) ok = true;
            }
            if (!ok) return false;
        }

        if (req.rootControlId.Length > 0) {
            if (layer.LocalPage is null) return false;
            auto root = layer.LocalPage.MainFrame;
            if (root is null) return false;

            if (UiNav::ML::FindFirstById(root, req.rootControlId) is null) return false;
        }

        return true;
    }

    class OwnedLayer {
        string scopeId;
        string key;
        CGameUILayer@ layer;
        ManiaLinkSource source = ManiaLinkSource::CurrentApp;
        string lastPage;
        bool visibleWanted = true;
        uint lastEnsureMs = 0;
        bool restorePending = false;
    }

    dictionary g_Owned;
    uint g_LastDestroyAllOwnedSweepCount = 0;
    bool g_OwnedStateLoaded = false;

    string _CurrentCallerScope() {
        Meta::Plugin@ plugin = Meta::ExecutingPlugin();
        string scopeId = "";
        if (plugin !is null) {
            try { scopeId = plugin.ID.Trim(); } catch { scopeId = ""; }
            if (scopeId.Length == 0) {
                try { scopeId = plugin.Name.Trim(); } catch { scopeId = ""; }
            }
        }
        if (scopeId.Length == 0) scopeId = "UiNav";
        return scopeId;
    }

    string _OwnedCompositeKey(const string &in scopeIdRaw, const string &in keyRaw) {
        string scopeId = scopeIdRaw.Trim();
        string key = keyRaw.Trim();
        if (scopeId.Length == 0 || key.Length == 0) return "";
        return scopeId + "|" + key;
    }

    bool _OwnedScopePluginLoaded(const string &in scopeIdRaw) {
        string scopeId = scopeIdRaw.Trim();
        if (scopeId.Length == 0) return false;
        return Meta::GetPluginFromID(scopeId) !is null;
    }

    string _OwnedLayersStatePath() {
        string path = S_OwnedLayersStatePath.Trim();
        if (path.Length == 0) path = IO::FromStorageFolder("UiNav/OwnedLayersState.json");
        return path;
    }

    void _ClearOwnedLayersStateFile() {
        string path = _OwnedLayersStatePath();
        if (path.Length == 0 || !IO::FileExists(path)) return;
        IO::Delete(path);
    }

    void _SaveOwnedLayersState() {
        if (!S_PersistOwnedLayersAcrossReloads) {
            _ClearOwnedLayersStateFile();
            return;
        }

        Json::Value@ root = Json::Object();
        Json::Value@ entries = Json::Object();
        int count = 0;

        array<string> keys = g_Owned.GetKeys();
        keys.SortAsc();
        for (uint i = 0; i < keys.Length; ++i) {
            auto ol = _GetOwnedByComposite(keys[i]);
            if (ol is null) continue;
            if (ol.scopeId.Trim().Length == 0) continue;
            if (ol.key.Trim().Length == 0) continue;
            if (ol.lastPage.Length == 0) continue;

            Json::Value@ item = Json::Object();
            item["scope"] = ol.scopeId;
            item["key"] = ol.key;
            item["source"] = int(ol.source);
            item["page"] = ol.lastPage;
            item["visible"] = ol.visibleWanted;
            entries["i" + count] = item;
            count++;
        }

        root["count"] = count;
        root["entries"] = entries;

        string path = _OwnedLayersStatePath();
        string folder = Path::GetDirectoryName(path);
        if (folder.Length > 0 && !IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        _IO::File::WriteFile(path, Json::Write(root), false);
    }

    void _LoadOwnedLayersState() {
        if (g_OwnedStateLoaded) return;
        g_OwnedStateLoaded = true;

        if (!S_PersistOwnedLayersAcrossReloads) return;

        string path = _OwnedLayersStatePath();
        if (path.Length == 0 || !IO::FileExists(path)) return;

        string raw = _IO::File::ReadFileToEnd(path).Trim();
        if (raw.Length == 0) return;

        Json::Value@ root = null;
        try {
            @root = Json::Parse(raw);
        } catch {
            @root = null;
        }
        if (root is null) return;

        int count = 0;
        try {
            count = int(root["count"]);
        } catch {
            count = 0;
        }
        if (count <= 0) return;

        const Json::Value@ entries = root["entries"];
        if (entries is null) return;

        for (int i = 0; i < count; ++i) {
            string itemKey = "i" + i;
            const Json::Value@ item = entries[itemKey];
            if (item is null) continue;

            string scopeId = "";
            string key = "";
            string page = "";
            bool visible = true;
            int sourceInt = int(ManiaLinkSource::CurrentApp);
            try { scopeId = string(item["scope"]); } catch { scopeId = ""; }
            try { key = string(item["key"]); } catch { key = ""; }
            try { page = string(item["page"]); } catch { page = ""; }
            try { visible = bool(item["visible"]); } catch { visible = true; }
            try { sourceInt = int(item["source"]); } catch { sourceInt = int(ManiaLinkSource::CurrentApp); }

            scopeId = scopeId.Trim();
            key = key.Trim();
            if (scopeId.Length == 0) scopeId = "UiNav";
            if (key.Length == 0 || page.Length == 0) continue;

            OwnedLayer@ ol = _GetOwned(scopeId, key);
            if (ol is null) {
                @ol = OwnedLayer();
                ol.scopeId = scopeId;
                ol.key = key;
                _SetOwned(scopeId, key, ol);
            }

            ol.scopeId = scopeId;
            ol.source = ManiaLinkSource(sourceInt);
            ol.lastPage = page;
            ol.visibleWanted = visible;
            ol.restorePending = true;
            @ol.layer = null;
        }
    }

    void TickOwnedRestore() {
        _LoadOwnedLayersState();

        array<string> keys = g_Owned.GetKeys();
        for (uint i = 0; i < keys.Length; ++i) {
            auto ol = _GetOwnedByComposite(keys[i]);
            if (ol is null) continue;
            if (!_OwnedScopePluginLoaded(ol.scopeId)) {
                if (ol.layer !is null) {
                    _DestroyOwnedLayerHandle(ol.layer);
                    @ol.layer = null;
                }
                ol.restorePending = true;
                continue;
            }
            if (!ol.restorePending) continue;
            if (ol.lastPage.Length == 0) {
                ol.restorePending = false;
                continue;
            }

            ManiaLinkSource resolved = ol.source;
            CGameManiaApp@ app = null;
            if (!_ResolveLayerSource(ol.source, resolved, app)) continue;

            auto layer = _EnsureAtResolvedSource(ol.scopeId, ol.key, ol.lastPage, resolved, app, ol.visibleWanted);
            if (layer !is null) {
                ol.restorePending = false;
            }
        }
    }

    void OnPluginUnload() {
        _SaveOwnedLayersState();
    }

    uint LastDestroyAllOwnedSweepCount() {
        return g_LastDestroyAllOwnedSweepCount;
    }

    OwnedLayer@ _GetOwnedByComposite(const string &in compositeKey) {
        if (compositeKey.Length == 0) return null;
        OwnedLayer@ outL;
        if (g_Owned.Get(compositeKey, @outL)) return outL;
        return null;
    }

    OwnedLayer@ _GetOwned(const string &in scopeId, const string &in key) {
        string compositeKey = _OwnedCompositeKey(scopeId, key);
        if (compositeKey.Length == 0) return null;
        return _GetOwnedByComposite(compositeKey);
    }

    bool _OwnedLayerHandleIsValid(OwnedLayer@ ol) {
        if (ol is null || ol.layer is null) return false;

        ManiaLinkSource resolved = ol.source;
        CGameManiaApp@ app = null;
        if (!_ResolveLayerSource(ol.source, resolved, app)) return false;
        return _LayerBelongsToSource(resolved, app, ol.layer);
    }

    CGameUILayer@ GetOwned(const string &in key) {
        auto ol = _GetOwned(_CurrentCallerScope(), key);
        if (ol is null) return null;
        if (!_OwnedLayerHandleIsValid(ol)) {
            @ol.layer = null;
            if (ol.lastPage.Length > 0) ol.restorePending = true;
            return null;
        }
        return ol.layer;
    }

    void _SetOwned(const string &in scopeId, const string &in key, OwnedLayer@ l) {
        string compositeKey = _OwnedCompositeKey(scopeId, key);
        if (compositeKey.Length == 0) return;
        g_Owned.Set(compositeKey, @l);
    }

    CGameManiaApp@ _ResolveOwnedLayerApp() {
        auto app = GetManiaApp();
        if (app !is null) return app;
        @app = GetManiaAppMenu();
        if (app !is null) return app;
        return GetManiaAppPlayground();
    }

    bool _LayerBelongsToEditor(CGameUILayer@ layer) {
        if (layer is null) return false;
        auto editor = _GetEditorCommon();
        if (editor is null || editor.PluginMapType is null) return false;
        auto layers = editor.PluginMapType.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            if (layers[i] is layer) return true;
        }
        return false;
    }

    bool _LayerBelongsToSource(ManiaLinkSource source, CGameManiaApp@ app, CGameUILayer@ layer) {
        if (source == ManiaLinkSource::Editor) return _LayerBelongsToEditor(layer);
        return _LayerBelongsToApp(app, layer);
    }

    CGameUILayer@ _CreateOwnedLayerAtSource(ManiaLinkSource source, CGameManiaApp@ app) {
        if (source == ManiaLinkSource::Editor) {
            auto editor = _GetEditorCommon();
            if (editor is null || editor.PluginMapType is null || editor.PluginMapType.UIManager is null) return null;
            return editor.PluginMapType.UIManager.UILayerCreate();
        }
        if (app is null) return null;
        return app.UILayerCreate();
    }

    bool _LayerBelongsToApp(CGameManiaApp@ app, CGameUILayer@ layer) {
        if (app is null || layer is null) return false;
        auto layers = app.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            if (layers[i] is layer) return true;
        }
        return false;
    }

    string _LayerPageText(CGameUILayer@ layer) {
        if (layer is null) return "";
        string page = "";
        try {
            page = layer.ManialinkPageUtf8;
        } catch {
            page = "";
        }
        if (page.Length == 0) {
            try {
                page = "" + layer.ManialinkPage;
            } catch {
                page = "";
            }
        }
        return page;
    }

    string _ExtractManialinkName(const string &in pageRaw) {
        if (pageRaw.Length == 0) return "";
        string page = pageRaw;
        if (page.Length > 8192) page = page.SubStr(0, 8192);

        string lower = page.ToLower();
        int mlIx = lower.IndexOf("<manialink");
        if (mlIx < 0) return "";

        string tail = page.SubStr(mlIx);
        int headEndRel = tail.IndexOf(">");
        if (headEndRel < 0) return "";

        string head = tail.SubStr(0, headEndRel);
        string headLower = head.ToLower();
        int nameIx = headLower.IndexOf("name=");
        if (nameIx < 0) return "";

        int pos = nameIx + 5;
        int headLen = int(head.Length);
        while (pos < headLen) {
            string ch = head.SubStr(pos, 1);
            if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") {
                pos++;
                continue;
            }
            break;
        }
        if (pos >= headLen) return "";

        string quote = head.SubStr(pos, 1);
        if (quote != "\"" && quote != "'") return "";

        int valStart = pos + 1;
        int valEndRel = head.SubStr(valStart).IndexOf(quote);
        if (valEndRel < 0) return "";

        return head.SubStr(valStart, valEndRel);
    }

    bool _LayerLooksUiNavOwnedByPrefix(CGameUILayer@ layer) {
        if (layer is null) return false;
        string page = _LayerPageText(layer);
        if (page.Length == 0) return false;
        string name = _ExtractManialinkName(page).Trim();
        if (name.Length < 6) return false;
        return name.SubStr(0, 6).ToLower() == "uinav_";
    }

    void _PushUniqueApp(array<CGameManiaApp@>@ apps, CGameManiaApp@ app) {
        if (apps is null || app is null) return;
        for (uint i = 0; i < apps.Length; ++i) {
            if (apps[i] is app) return;
        }
        apps.InsertLast(app);
    }

    int _DestroyUiNavPrefixedLayersInApp(CGameManiaApp@ app) {
        if (app is null) return 0;
        array<CGameUILayer@> victims;
        auto layers = app.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            auto layer = layers[i];
            if (layer is null) continue;
            if (_LayerLooksUiNavOwnedByPrefix(layer)) victims.InsertLast(layer);
        }

        int removed = 0;
        for (uint i = 0; i < victims.Length; ++i) {
            auto layer = victims[i];
            if (layer is null) continue;
            if (!_LayerBelongsToApp(app, layer)) continue;
            try {
                app.UILayerDestroy(layer);
                removed++;
            } catch {
                continue;
            }
        }
        return removed;
    }

    int _DestroyUiNavPrefixedLayersInEditor() {
        auto editor = _GetEditorCommon();
        if (editor is null || editor.PluginMapType is null || editor.PluginMapType.UIManager is null) return 0;

        array<CGameUILayer@> victims;
        auto layers = editor.PluginMapType.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            auto layer = layers[i];
            if (layer is null) continue;
            if (_LayerLooksUiNavOwnedByPrefix(layer)) victims.InsertLast(layer);
        }

        int removed = 0;
        for (uint i = 0; i < victims.Length; ++i) {
            auto layer = victims[i];
            if (layer is null || !_LayerBelongsToEditor(layer)) continue;
            try {
                editor.PluginMapType.UIManager.UILayerDestroy(layer);
                removed++;
            } catch {
                continue;
            }
        }
        return removed;
    }

    bool _DestroyOwnedLayerHandle(CGameUILayer@ layer) {
        if (layer is null) return false;

        auto editor = _GetEditorCommon();
        if (editor !is null && editor.PluginMapType !is null && editor.PluginMapType.UIManager !is null && _LayerBelongsToEditor(layer)) {
            editor.PluginMapType.UIManager.UILayerDestroy(layer);
            return true;
        }

        auto app = _ResolveOwnedLayerApp();
        if (app !is null && _LayerBelongsToApp(app, layer)) {
            app.UILayerDestroy(layer);
            return true;
        }

        auto pg = GetManiaAppPlayground();
        if (pg !is null && pg !is app && _LayerBelongsToApp(pg, layer)) {
            pg.UILayerDestroy(layer);
            return true;
        }

        auto menu = GetManiaAppMenu();
        if (menu !is null && menu !is app && menu !is pg && _LayerBelongsToApp(menu, layer)) {
            menu.UILayerDestroy(layer);
            return true;
        }

        return false;
    }

    CGameUILayer@ _EnsureAtResolvedSource(const string &in scopeId, const string &in key, const string &in page, ManiaLinkSource source, CGameManiaApp@ app, bool visible) {
        if (source != ManiaLinkSource::Editor && app is null) return null;

        OwnedLayer@ ol = _GetOwned(scopeId, key);

        if (ol is null) {
            @ol = OwnedLayer();
            ol.scopeId = scopeId;
            ol.key = key;
            _SetOwned(scopeId, key, ol);
        }
        ol.scopeId = scopeId;

        if (ol.layer !is null && !_LayerBelongsToSource(source, app, ol.layer)) {
            _DestroyOwnedLayerHandle(ol.layer);
            @ol.layer = null;
            ol.lastPage = "";
        }

        if (ol.layer is null) {
            @ol.layer = _CreateOwnedLayerAtSource(source, app);
            if (ol.layer is null) return null;
            ol.lastPage = "";
        }

        ol.source = source;
        ol.visibleWanted = visible;

        if (ol.layer !is null) {
            if (ol.lastPage != page) {
                ol.layer.ManialinkPage = page;
                ol.lastPage = page;
            }

            ol.layer.IsVisible = visible;
        }

        ol.lastEnsureMs = Time::Now;
        return ol.layer;
    }

    CGameUILayer@ _EnsureAtApp(const string &in scopeId, const string &in key, const string &in page, CGameManiaApp@ app, bool visible) {
        return _EnsureAtResolvedSource(scopeId, key, page, ManiaLinkSource::CurrentApp, app, visible);
    }

    CGameUILayer@ EnsureAtApp(const string &in key, const string &in page, CGameManiaApp@ app, bool visible = true) {
        return _EnsureAtApp(_CurrentCallerScope(), key, page, app, visible);
    }

    CGameUILayer@ Ensure(const string &in key, const string &in page, bool visible = true) {
        auto app = _ResolveOwnedLayerApp();
        return _EnsureAtApp(_CurrentCallerScope(), key, page, app, visible);
    }

    CGameUILayer@ EnsureOwned(const string &in key, const string &in page, ManiaLinkSource source = ManiaLinkSource::CurrentApp, bool visible = true) {
        ManiaLinkSource resolved = source;
        CGameManiaApp@ app = null;
        if (!_ResolveLayerSource(source, resolved, app)) return null;
        return _EnsureAtResolvedSource(_CurrentCallerScope(), key, page, resolved, app, visible);
    }

    bool Destroy(const string &in scopeId, const string &in key) {
        OwnedLayer@ ol = _GetOwned(scopeId, key);
        if (ol is null) return false;

        bool hadLayer = ol.layer !is null;
        bool removedLayer = false;
        if (ol.layer !is null) {
            removedLayer = _DestroyOwnedLayerHandle(ol.layer);
            @ol.layer = null;
        }

        string compositeKey = _OwnedCompositeKey(scopeId, key);
        if (compositeKey.Length > 0) g_Owned.Delete(compositeKey);
        return !hadLayer || removedLayer;
    }

    bool Destroy(const string &in key) {
        return Destroy(_CurrentCallerScope(), key);
    }

    bool DestroyOwned(const string &in key) {
        return Destroy(_CurrentCallerScope(), key);
    }

    void DestroyAllOwnedGlobal() {
        g_LastDestroyAllOwnedSweepCount = 0;

        array<string> keys = g_Owned.GetKeys();
        for (uint i = 0; i < keys.Length; ++i) {
            auto ol = _GetOwnedByComposite(keys[i]);
            if (ol is null) continue;
            Destroy(ol.scopeId, ol.key);
        }
        g_Owned.DeleteAll();

        array<CGameManiaApp@> apps;
        _PushUniqueApp(apps, GetManiaApp());
        _PushUniqueApp(apps, GetManiaAppMenu());
        _PushUniqueApp(apps, GetManiaAppPlayground());

        int removed = 0;
        for (uint i = 0; i < apps.Length; ++i) {
            removed += _DestroyUiNavPrefixedLayersInApp(apps[i]);
        }
        removed += _DestroyUiNavPrefixedLayersInEditor();
        if (removed < 0) removed = 0;
        g_LastDestroyAllOwnedSweepCount = uint(removed);
    }

    void DestroyAllOwned() {
        g_LastDestroyAllOwnedSweepCount = 0;

        string scopeId = _CurrentCallerScope();
        array<string> keys = g_Owned.GetKeys();
        uint removed = 0;
        for (uint i = 0; i < keys.Length; ++i) {
            auto ol = _GetOwnedByComposite(keys[i]);
            if (ol is null || ol.scopeId != scopeId) continue;
            if (Destroy(scopeId, ol.key)) removed++;
        }
        g_LastDestroyAllOwnedSweepCount = removed;
    }

}
}
