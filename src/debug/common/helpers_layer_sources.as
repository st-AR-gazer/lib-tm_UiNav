namespace UiNav {
namespace Debug {

    string _MlAppNameByKind(int appKind) {
        if (appKind == 1) return "menu";
        if (appKind == 2) return "editor";
        return "playground";
    }

    string _MlAppPrefixByKind(int appKind) {
        if (appKind == 1) return "M";
        if (appKind == 2) return "E";
        return "P";
    }

    CGameCtnEditorCommon@ _GetMlEditorCommon() {
        auto tm = cast<CTrackMania>(GetApp());
        if (tm is null || tm.Editor is null) return null;
        return cast<CGameCtnEditorCommon>(tm.Editor);
    }

    bool _MlSourceAvailable(int appKind) {
        if (appKind == 2) {
            auto editor = _GetMlEditorCommon();
            return editor !is null && editor.PluginMapType !is null;
        }
        return _GetMlManiaAppByKind(appKind) !is null;
    }

    CGameManiaApp@ _GetMlManiaAppByKind(int appKind) {
        if (appKind == 1) return UiNav::Layers::GetManiaAppMenu();
        if (appKind == 0) return UiNav::Layers::GetManiaAppPlayground();
        return null;
    }

    uint _GetMlLayerCount(int appKind) {
        if (appKind == 2) {
            auto editor = _GetMlEditorCommon();
            if (editor is null || editor.PluginMapType is null) return 0;
            return editor.PluginMapType.UILayers.Length;
        }

        auto app = _GetMlManiaAppByKind(appKind);
        if (app is null) return 0;
        return app.UILayers.Length;
    }

    CGameUILayer@ _GetMlLayerByIx(int appKind, int layerIx) {
        if (layerIx < 0) return null;
        uint ix = uint(layerIx);

        if (appKind == 2) {
            auto editor = _GetMlEditorCommon();
            if (editor is null || editor.PluginMapType is null) return null;
            auto layers = editor.PluginMapType.UILayers;
            if (ix >= layers.Length) return null;
            return layers[ix];
        }

        auto app = _GetMlManiaAppByKind(appKind);
        if (app is null) return null;
        auto layers = app.UILayers;
        if (ix >= layers.Length) return null;
        return layers[ix];
    }

    bool _MlLayerHasRoot(CGameUILayer@ layer) {
        if (layer is null || layer.LocalPage is null) return false;
        auto root = layer.LocalPage.MainFrame;
        if (root is null) return false;

        auto frame = cast<CGameManialinkFrame@>(root);
        if (frame is null) return true;
        if (frame.Controls.Length == 0) return false;
        for (uint i = 0; i < frame.Controls.Length; ++i) {
            if (frame.Controls[i] !is null) return true;
        }
        return false;
    }

    bool _MlHasInspectableDataRaw(int appKind) {
        uint len = _GetMlLayerCount(appKind);
        for (uint i = 0; i < len; ++i) {
            auto layer = _GetMlLayerByIx(appKind, int(i));
            if (_MlLayerHasRoot(layer)) return true;
        }
        return false;
    }

    void _MlRefreshInspectableDataCache() {
        uint epoch = UiNav::ContextEpoch();
        uint now = Time::Now;
        bool invalidate = !g_MlInspectableCacheValid || (g_MlInspectableCacheEpoch != epoch);

        if (!invalidate && S_DebugSearchCacheRefreshMs > 0) {
            uint age = now - g_MlInspectableCacheStampMs;
            if (age >= S_DebugSearchCacheRefreshMs) invalidate = true;
        }

        if (!invalidate) return;

        g_MlInspectablePlayground = _MlHasInspectableDataRaw(0);
        g_MlInspectableMenu = _MlHasInspectableDataRaw(1);
        g_MlInspectableEditor = _MlHasInspectableDataRaw(2);
        g_MlInspectableCacheEpoch = epoch;
        g_MlInspectableCacheStampMs = now;
        g_MlInspectableCacheValid = true;
    }

    bool _MlHasInspectableData(int appKind) {
        _MlRefreshInspectableDataCache();
        if (appKind == 1) return g_MlInspectableMenu;
        if (appKind == 2) return g_MlInspectableEditor;
        if (appKind == 0) return g_MlInspectablePlayground;
        return false;
    }

    bool _MlLooksLikeInt(const string &in raw) {
        string s = raw.Trim();
        if (s.Length == 0) return false;
        int start = 0;
        if (s.StartsWith("-")) {
            if (s.Length == 1) return false;
            start = 1;
        }
        for (int i = start; i < int(s.Length); ++i) {
            if ("0123456789".IndexOf(s.SubStr(i, 1)) < 0) return false;
        }
        return true;
    }

}
}
