namespace UiNav {
namespace Debug {

    void _UpdateMlPick(int appKind) {
        uint layersLen = _GetMlLayerCount(appKind);
        if (layersLen == 0) return;
        uint startIx = 0;
        uint endIx = layersLen;
        if (g_MlViewLayerIndex >= 0 && g_MlViewLayerIndex < int(layersLen)) {
            startIx = uint(g_MlViewLayerIndex);
            endIx = startIx + 1;
        }

        CGameManialinkControl@ found = null;
        string foundPath = "";
        int foundLayer = -1;
        int foundDepth = -1;

        for (uint i = startIx; i < endIx; ++i) {
            auto layer = _GetMlLayerByIx(appKind, int(i));
            if (layer is null || layer.LocalPage is null) continue;
            auto root = layer.LocalPage.MainFrame;
            if (root is null) continue;
            auto prev = found;
            _FindMlFocused(root, "", 0, found, foundPath, foundDepth, int(i));
            if (found !is prev) foundLayer = int(i);
        }

        if (found !is null) {
            string appPrefix = _MlAppPrefixByKind(appKind);
            string uiPath = (foundLayer >= 0) ? (appPrefix + "/L" + foundLayer) : "";
            if (uiPath.Length > 0 && foundPath.Length > 0) uiPath += "/" + foundPath;
            _SelectMl(found, foundPath, uiPath, foundLayer);
        }
    }

    void _FindMlFocused(CGameManialinkControl@ n, const string &in path, int depth,
                        CGameManialinkControl@ &out found, string &out foundPath, int &out foundDepth, int layerIx) {
        if (n is null) return;

        CGameManialinkFrame@ f = cast<CGameManialinkFrame@>(n);
        if (f !is null) {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                string childPath = (path.Length == 0) ? ("" + i) : (path + "/" + i);
                _FindMlFocused(ch, childPath, depth + 1, found, foundPath, foundDepth, layerIx);
            }
        }

        bool isFocused = false;
        if (f !is null) {
            isFocused = f.IsFocused;
        }

        if (isFocused && depth >= foundDepth) {
            @found = n;
            foundPath = path;
            foundDepth = depth;
        }
    }

}
}
