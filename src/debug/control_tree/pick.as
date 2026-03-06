namespace UiNav {
namespace Debug {

    void _UpdateControlTreePick() {
        uint overlayCount = 0;
        if (!_TryGetControlTreeOverlayCount(overlayCount) || overlayCount == 0) return;

        uint startOverlay = 0;
        uint endOverlay = overlayCount;
        if (g_ControlTreeOverlay >= 0) {
            if (uint(g_ControlTreeOverlay) >= overlayCount) return;
            startOverlay = uint(g_ControlTreeOverlay);
            endOverlay = startOverlay + 1;
        }

        CControlBase@ found = null;
        string foundPath = "";
        string foundDisplay = "";
        int foundDepth = -1;
        int foundRootIx = -1;
        uint foundOverlay = startOverlay;

        for (uint ov = startOverlay; ov < endOverlay; ++ov) {
            CScene2d@ scene;
            if (!_GetScene2d(ov, scene) || scene is null) continue;

            for (uint i = 0; i < scene.Mobils.Length; ++i) {
                CControlFrame@ root = _RootFromMobil(scene, i);
                if (root is null) continue;
                string rootPath = "overlay[" + ov + "]/root[" + i + "]";
                CControlBase@ prevFound = found;
                _FindControlTreeFocused(root, "", rootPath, 0, found, foundPath, foundDepth, foundDisplay, int(i), foundRootIx);
                if (found !is prevFound) foundOverlay = ov;
            }
        }

        if (found !is null) {
            string uiPath = (foundRootIx >= 0) ? ("O" + foundOverlay + "/root[" + foundRootIx + "]") : "";
            if (uiPath.Length > 0 && foundPath.Length > 0) uiPath += "/" + foundPath;
            _SelectControlTree(found, foundPath, foundDisplay, uiPath, foundRootIx, foundOverlay);
        }
    }

    void _FindControlTreeFocused(CControlBase@ n, const string &in relPath, const string &in displayPath, int depth,
                         CControlBase@ &out found, string &out foundPath, int &out foundDepth, string &out foundDisplay,
                         int rootIx, int &out foundRootIx) {
        if (n is null) return;

        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(n, i);
            if (ch is null) continue;
            string childRel = (relPath.Length == 0) ? ("" + i) : (relPath + "/" + i);
            string childDisp = displayPath + "/" + i;
            _FindControlTreeFocused(ch, childRel, childDisp, depth + 1, found, foundPath, foundDepth, foundDisplay, rootIx, foundRootIx);
        }

        bool isFocused = false;
        CControlFrame@ f = cast<CControlFrame@>(n);
        if (f !is null) {
            isFocused = f.IsFocused || f.IsSelected;
        }

        if (isFocused && depth >= foundDepth) {
            @found = n;
            foundPath = relPath;
            foundDepth = depth;
            foundDisplay = displayPath;
            foundRootIx = rootIx;
        }
    }

}
}
