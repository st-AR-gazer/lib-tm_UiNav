namespace UiNav {
namespace Debug {

    string _MlNoteAnchorToken(CGameManialinkControl@ n, int childIx = -1) {
        if (n is null) return "<null>";
        if (n.ControlId.Length > 0) return "#" + n.ControlId;
        string classList;
        string classSel = _MlFirstClassSelector(n, classList);
        if (classSel.Length > 0) return classSel;
        string token = "@" + UiNav::ML::TypeName(n);
        if (childIx >= 0) token += "[" + childIx + "]";
        return token;
    }

    string _MlBuildAnchor(CGameManialinkFrame@ root, const string &in idxPath) {
        if (root is null) return "";
        CGameManialinkControl@ cur = root;
        string anchor = _MlNoteAnchorToken(cur, -1);
        if (idxPath.Length == 0) return anchor;

        array<string>@ parts = idxPath.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) break;
            auto f = cast<CGameManialinkFrame@>(cur);
            if (f is null || uint(idx) >= f.Controls.Length) break;
            @cur = f.Controls[uint(idx)];
            if (cur is null) break;
            anchor += "/" + _MlNoteAnchorToken(cur, idx);
        }
        return anchor;
    }

    bool _MlGetActiveNotesTooltip(const string &in layerKey, const string &in anchor, CGameManialinkControl@ n, CGameManialinkFrame@ layerRoot,
                                  string &out tooltip, int &out count) {
        _MlNotesEnsureLoaded();
        tooltip = "";
        count = 0;
        for (uint i = 0; i < g_MlDebugNotes.Length; ++i) {
            auto note = g_MlDebugNotes[i];
            if (note is null) continue;
            if (note.layerKey != layerKey) continue;
            if (note.anchor != anchor) continue;
            if (!_MlNoteIsActive(note, n, layerRoot)) continue;
            string noteText = _MlNormalizeNoteText(note.text).Trim();
            if (noteText.Length == 0) continue;

            if (tooltip.Length > 0) tooltip += "\n\n";
            tooltip += noteText;
            count++;
        }
        return count > 0;
    }

    void _MlRenderNoteIndicator(const string &in layerKey, const string &in anchor, CGameManialinkControl@ n, CGameManialinkFrame@ layerRoot) {
        string tooltip;
        int count = 0;
        if (!_MlGetActiveNotesTooltip(layerKey, anchor, n, layerRoot, tooltip, count)) return;
        UI::SameLine();
        UI::Text("\\$ff0" + Icons::ExclamationTriangle + "\\$z " + count);
        if (UI::IsItemHovered()) {
            UI::BeginTooltip();
            UI::Text("UiNav note" + (count == 1 ? "" : "s"));
            UI::Separator();
            UI::PushTextWrapPos(420.0f);
            UI::TextWrapped(tooltip);
            UI::PopTextWrapPos();
            UI::EndTooltip();
        }
    }

    bool _GetSelectedMlLayerContext(CGameManiaApp@ &out app, CGameUILayer@ &out layer, CGameManialinkFrame@ &out root) {
        @app = _GetMlManiaAppByKind(g_SelectedMlAppKind);
        @layer = null;
        @root = null;
        @layer = _GetMlLayerByIx(g_SelectedMlAppKind, g_SelectedMlLayerIx);
        if (layer is null) return false;
        if (layer is null || layer.LocalPage is null) return false;
        @root = layer.LocalPage.MainFrame;
        return root !is null;
    }

    string _MlNewNoteId(const string &in layerKey, const string &in anchor, const string &in text) {
        return Crypto::MD5(layerKey + "|" + anchor + "|" + text + "|" + Time::Now + "|" + g_MlDebugNotes.Length);
    }

    void _ClearMlSelection() {
        @g_SelectedMlNode = null;
        g_SelectedMlUiPath = "";
        g_SelectedMlPath = "";
        g_SelectedMlLayerIx = -1;
        g_SelectedMlAppKind = 0;
    }

    void _SelectMl(CGameManialinkControl@ n, const string &in path, const string &in uiPath, int layerIx) {
        @g_SelectedMlNode = null;
        g_SelectedMlUiPath = uiPath;
        g_SelectedMlPath = path;
        g_SelectedMlLayerIx = layerIx;
        g_SelectedMlAppKind = g_MlActiveAppKind;

        if (UiNav::Builder::S_LiveLayerBoundsOverlayEnabled) {
            UiNav::Builder::RefreshLiveLayerBoundsOverlay(false, /*quiet=*/true);
        }
    }

    void _ClearControlTreeSelection() {
        @g_SelectedControlTreeNode = null;
        g_SelectedControlTreeUiPath = "";
        g_SelectedControlTreeRootIx = -1;
        if (g_ControlTreeOverlay >= 0) g_SelectedControlTreeOverlayAtSel = uint(g_ControlTreeOverlay);
        g_SelectedControlTreePath = "";
        g_SelectedControlTreeDisplayPath = "";
    }

    void _SelectControlTree(CControlBase@ n, const string &in path, const string &in displayPath,
                            const string &in uiPath, int rootIx, uint overlayAtSelection) {
        @g_SelectedControlTreeNode = null;
        g_SelectedControlTreeUiPath = uiPath;
        g_SelectedControlTreeRootIx = rootIx;
        g_SelectedControlTreeOverlayAtSel = overlayAtSelection;
        g_SelectedControlTreePath = path;
        g_SelectedControlTreeDisplayPath = displayPath;
    }

    string _NodePathParent(const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length == 0) return "";
        auto parts = p.Split("/");
        array<string> parent;
        if (parts.Length <= 1) return "";
        for (uint i = 0; i + 1 < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            parent.InsertLast(part);
        }
        return _JoinParts(parent, "/");
    }

    string _MlNodeFocusParentPathDisplay() {
        if (!g_MlNodeFocusActive || g_MlNodeFocusLayerIx < 0) return "";
        string base = _MlAppPrefixByKind(g_MlNodeFocusAppKind) + "/L" + g_MlNodeFocusLayerIx;
        string parentPath = _NodePathParent(g_MlNodeFocusPath);
        if (parentPath.Length > 0) return base + "/" + parentPath;
        return base;
    }

    string _ControlTreeNodeFocusParentPathDisplay() {
        if (!g_ControlTreeNodeFocusActive || g_ControlTreeNodeFocusRootIx < 0) return "";
        string base = "overlay[" + g_ControlTreeNodeFocusOverlay + "]/root[" + g_ControlTreeNodeFocusRootIx + "]";
        string parentPath = _NodePathParent(g_ControlTreeNodeFocusPath);
        if (parentPath.Length > 0) return base + "/" + parentPath;
        return base;
    }

    void _ClearMlNodeFocus() {
        g_MlNodeFocusActive = false;
        g_MlNodeFocusAppKind = 0;
        g_MlNodeFocusLayerIx = -1;
        g_MlNodeFocusPath = "";
        g_MlNodeFocusUiPath = "";
    }

    bool _FocusSelectedMlNode() {
        if (g_SelectedMlLayerIx < 0 || g_SelectedMlUiPath.Length == 0) return false;

        CGameManialinkFrame@ root = null;
        CGameManialinkControl@ node = null;
        if (!_ResolveMlNodeByPath(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, root, node) || node is null) {
            return false;
        }

        g_MlNodeFocusActive = true;
        g_MlNodeFocusAppKind = g_SelectedMlAppKind;
        g_MlNodeFocusLayerIx = g_SelectedMlLayerIx;
        g_MlNodeFocusPath = g_SelectedMlPath;
        g_MlNodeFocusUiPath = g_SelectedMlUiPath;
        g_MlViewLayerIndex = g_SelectedMlLayerIx;
        _SetMlTreeOpen(g_MlNodeFocusUiPath, true);
        return true;
    }

    void _ClearControlTreeNodeFocus() {
        g_ControlTreeNodeFocusActive = false;
        g_ControlTreeNodeFocusOverlay = 16;
        g_ControlTreeNodeFocusRootIx = -1;
        g_ControlTreeNodeFocusPath = "";
        g_ControlTreeNodeFocusUiPath = "";
    }

    bool _FocusSelectedControlTreeNode() {
        if (g_SelectedControlTreeRootIx < 0 || g_SelectedControlTreeUiPath.Length == 0) return false;

        CControlBase@ node = null;
        if (!_ResolveControlTreeNodeByPath(g_SelectedControlTreeOverlayAtSel, g_SelectedControlTreeRootIx, g_SelectedControlTreePath, node) || node is null) {
            return false;
        }

        g_ControlTreeNodeFocusActive = true;
        g_ControlTreeNodeFocusOverlay = g_SelectedControlTreeOverlayAtSel;
        g_ControlTreeNodeFocusRootIx = g_SelectedControlTreeRootIx;
        g_ControlTreeNodeFocusPath = g_SelectedControlTreePath;
        g_ControlTreeNodeFocusUiPath = g_SelectedControlTreeUiPath;
        g_ControlTreeOverlay = int(g_SelectedControlTreeOverlayAtSel);
        _SetControlTreeTreeOpen(g_ControlTreeNodeFocusUiPath, true);
        return true;
    }

    CGameManialinkControl@ _ResolveSelectedMlNode(string &out err) {
        err = "";
        if (g_SelectedMlUiPath.Length == 0) { err = "No selection"; return null; }
        if (g_SelectedMlLayerIx < 0) { err = "No selected layer"; return null; }

        auto layer = _GetMlLayerByIx(g_SelectedMlAppKind, g_SelectedMlLayerIx);
        if (layer is null || layer.LocalPage is null || layer.LocalPage.MainFrame is null) {
            err = "Layer has no LocalPage/MainFrame";
            return null;
        }

        CGameManialinkControl@ cur = layer.LocalPage.MainFrame;
        if (g_SelectedMlPath.Length == 0) return cur;

        string[] parts = g_SelectedMlPath.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) { err = "Invalid path segment: " + part; return null; }

            auto f = cast<CGameManialinkFrame@>(cur);
            if (f is null) { err = "Path points into non-frame"; return null; }
            if (uint(idx) >= f.Controls.Length) { err = "Path index out of range: " + part; return null; }

            @cur = f.Controls[uint(idx)];
            if (cur is null) { err = "Null child at index: " + part; return null; }
        }
        return cur;
    }

    CControlBase@ _ResolveSelectedControlTreeNode(string &out err) {
        err = "";
        if (g_SelectedControlTreeUiPath.Length == 0) { err = "No selection"; return null; }

        uint overlay = g_SelectedControlTreeOverlayAtSel;
        if (g_SelectedControlTreeRootIx >= 0) {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene)) { err = "No scene for overlay " + overlay; return null; }
            if (uint(g_SelectedControlTreeRootIx) >= scene.Mobils.Length) { err = "Root index out of range"; return null; }
            CControlFrame@ root = _RootFromMobil(scene, uint(g_SelectedControlTreeRootIx));
            if (root is null) { err = "Root is null"; return null; }

            CControlBase@ cur = cast<CControlBase@>(root);
            if (g_SelectedControlTreePath.Length == 0) return cur;

            string[] parts = g_SelectedControlTreePath.Split("/");
            for (uint i = 0; i < parts.Length; ++i) {
                string part = parts[i].Trim();
                if (part.Length == 0) continue;
                int idx = Text::ParseInt(part);
                if (idx < 0) { err = "Invalid path segment: " + part; return null; }

                uint len = _ChildrenLen(cur);
                if (uint(idx) >= len) { err = "Path index out of range: " + part; return null; }
                CControlBase@ ch = _ChildAt(cur, uint(idx));
                if (ch is null) { err = "Null child at index: " + part; return null; }
                @cur = ch;
            }
            return cur;
        }

        if (g_SelectedControlTreePath.Length > 0) {
            auto found = ResolvePathAnyRoot(g_SelectedControlTreePath, overlay, 64);
            if (found !is null) return found;
        }

        err = "Could not resolve selection";
        return null;
    }

    bool _ResolveMlNodeByPath(int appKind, int layerIx, const string &in path, CGameManialinkFrame@ &out root, CGameManialinkControl@ &out node) {
        @root = _GetMlRootByLayerIx(layerIx, appKind);
        @node = null;
        if (root is null) return false;

        @node = root;
        if (path.Length == 0) return true;

        string[] parts = path.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) return false;

            auto f = cast<CGameManialinkFrame@>(node);
            if (f is null) return false;
            if (uint(idx) >= f.Controls.Length) return false;

            @node = f.Controls[uint(idx)];
            if (node is null) return false;
        }
        return true;
    }

    bool _ResolveControlTreeNodeByPath(uint overlay, int rootIx, const string &in relPath, CControlBase@ &out node) {
        @node = null;
        if (rootIx < 0) return false;
        CScene2d@ scene;
        if (!_GetScene2d(overlay, scene) || scene is null) return false;
        if (uint(rootIx) >= scene.Mobils.Length) return false;

        CControlFrame@ root = _RootFromMobil(scene, uint(rootIx));
        if (root is null) return false;

        @node = cast<CControlBase@>(root);
        if (relPath.Length == 0) return true;

        string[] parts = relPath.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) return false;
            uint len = _ChildrenLen(node);
            if (uint(idx) >= len) return false;
            @node = _ChildAt(node, uint(idx));
            if (node is null) return false;
        }
        return true;
    }

    void _OpenNodExplorer(CGameManialinkControl@ n) {
        if (n is null) return;
#if SIG_DEVELOPER
        ExploreNod(n);
#endif
    }

    void _OpenNodExplorer(CControlBase@ n) {
        if (n is null) return;
#if SIG_DEVELOPER
        ExploreNod(n);
#endif
    }

    dictionary g_MlTreeOpen;
    dictionary g_ControlTreeTreeOpen;

    void _SetMlTreeOpen(const string &in uiPath, bool open) {
        if (uiPath.Length == 0) return;
        bool prev = false;
        bool had = g_MlTreeOpen.Get(uiPath, prev);
        g_MlTreeOpen.Set(uiPath, open);
        if (!had || prev != open) {
            g_MlFlatDirty = true;
            g_MlTreeOpenEpoch++;
        }
    }

    bool _IsMlTreeOpen(const string &in uiPath) {
        if (uiPath.Length == 0) return false;
        bool open = false;
        if (g_MlTreeOpen.Exists(uiPath)) {
            g_MlTreeOpen.Get(uiPath, open);
        }
        return open;
    }

    void _SetControlTreeTreeOpen(const string &in uiPath, bool open) {
        if (uiPath.Length == 0) return;
        bool prev = false;
        bool had = g_ControlTreeTreeOpen.Get(uiPath, prev);
        g_ControlTreeTreeOpen.Set(uiPath, open);
        if (!had || prev != open) g_ControlTreeFlatDirty = true;
    }

    bool _IsControlTreeTreeOpen(const string &in uiPath) {
        if (uiPath.Length == 0) return false;
        bool open = false;
        if (g_ControlTreeTreeOpen.Exists(uiPath)) {
            g_ControlTreeTreeOpen.Get(uiPath, open);
        }
        return open;
    }

    bool _NodButton(const string &in label, const vec2 &in size) {
        UI::PushStyleColor(UI::Col::Button, vec4(0.16f, 0.36f, 0.62f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.22f, 0.46f, 0.76f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.12f, 0.30f, 0.52f, 1.0f));
        bool pressed = UI::Button(label, size);
        UI::PopStyleColor(3);
        return pressed;
    }

    const float kTreeActionBtnWidth = 48.0f;
    const float kTreeActionBtnHeight = 11.0f;
    const float kTreeActionBtnFontSize = 10.5f;
    const float kTreeToggleBtnWidth = 10.0f;
    const float kTreeToggleBtnHeight = 12.0f;
    const float kTreeToggleBtnFontSize = 12.0f;

    void _DrawStackedTreeActionButtons(const string &in idBase, bool &out selectPressed, bool &out nodPressed) {
        selectPressed = false;
        nodPressed = false;

        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(2.0f, 1.0f));
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(2.0f, 1.0f));
        UI::PushFontSize(kTreeActionBtnFontSize);
        UI::BeginGroup();
        selectPressed = UI::Button("Select##sel-" + idBase, vec2(kTreeActionBtnWidth, kTreeActionBtnHeight));
        nodPressed = _NodButton("Nod##nod-" + idBase, vec2(kTreeActionBtnWidth, kTreeActionBtnHeight));
        UI::EndGroup();
        UI::PopFontSize();
        UI::PopStyleVar(2);
    }

    void _DrawStackedTreeActionButtonsSpacer() {
        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(2.0f, 1.0f));
        UI::BeginGroup();
        UI::Dummy(vec2(kTreeActionBtnWidth, kTreeActionBtnHeight));
        UI::Dummy(vec2(kTreeActionBtnWidth, kTreeActionBtnHeight));
        UI::EndGroup();
        UI::PopStyleVar();
    }

    bool _DrawTreeToggleButton(const string &in idBase, bool isOpen, bool enabled = true) {
        if (!enabled) {
            UI::Dummy(vec2(kTreeToggleBtnWidth, kTreeToggleBtnHeight));
            return false;
        }

        UI::PushID("tree-toggle-" + idBase);
        UI::PushFontSize(kTreeToggleBtnFontSize);
        UI::Text(isOpen ? Icons::ChevronDown : Icons::ChevronRight);
        bool hovered = UI::IsItemHovered();
        bool pressed = hovered && UI::IsMouseClicked(UI::MouseButton::Left);
        UI::PopFontSize();
        if (hovered) {
            UI::SetMouseCursor(UI::MouseCursor::Hand);
            UI::SetTooltip(isOpen ? "Collapse" : "Expand");
        }
        UI::PopID();
        return pressed;
    }

    void _TreeRowMouseActions(bool hovered, bool canOpen, bool &out openRequested, bool &out selectRequested) {
        openRequested = false;
        selectRequested = false;
        if (!hovered) return;

        if (canOpen && UI::IsMouseClicked(UI::MouseButton::Left)) {
            openRequested = true;
        }
        if (UI::IsMouseClicked(UI::MouseButton::Right)) {
            selectRequested = true;
        }
    }

    string _TypeColorCode(const string &in typeName) {
        string low = typeName.ToLower();
        if (low.Contains("frame")) return "\\$9fd";
        if (low.Contains("label") || low.Contains("text")) return "\\$bff";
        if (low.Contains("quad") || low.Contains("sprite") || low.Contains("image")) return "\\$fcb";
        if (low.Contains("entry") || low.Contains("input")) return "\\$fd8";
        if (low.Contains("gauge") || low.Contains("meter") || low.Contains("progress")) return "\\$fc8";
        return "\\$ddd";
    }

    string _ColorizeTypeName(const string &in typeName) {
        if (typeName.Length == 0) return "<unknown>";
        return _TypeColorCode(typeName) + typeName + "\\$z";
    }

    class _MlNodeDataEntry {
        uint epoch = 0;
        uint stampMs = 0;
        string id;
        string type;
        string label;
        bool visible = true;
        bool hasText = false;
        string text;
        bool hasClasses = false;
        string classes;
    }

    class _ControlTreeNodeDataEntry {
        uint epoch = 0;
        uint stampMs = 0;
        string type;
        string label;
        bool hasId = false;
        string id;
        bool hasVisible = false;
        bool visible = true;
        bool hasText = false;
        string text;
    }

    dictionary g_MlNodeDataCache;
    array<string> g_MlNodeDataCacheKeys;
    dictionary g_ControlTreeNodeDataCache;
    array<string> g_ControlTreeNodeDataCacheKeys;
    const uint kTreeNodeDataCacheMax = 12000;

    class _MlLayerNameCacheEntry {
        uint epoch = 0;
        CGameUILayer@ layer = null;
        string name;
    }

    dictionary g_MlLayerNameCache;

    string _TrimTreeText(const string &in raw) {
        string t = raw;
        if (t.Length > 60) t = t.SubStr(0, 60) + "...";
        return t;
    }

    void _MlNodeDataCacheInsert(const string &in key, _MlNodeDataEntry@ e) {
        bool exists = g_MlNodeDataCache.Exists(key);
        g_MlNodeDataCache.Set(key, @e);
        if (!exists) {
            g_MlNodeDataCacheKeys.InsertLast(key);
            if (g_MlNodeDataCacheKeys.Length > kTreeNodeDataCacheMax) {
                string victim = g_MlNodeDataCacheKeys[0];
                g_MlNodeDataCacheKeys.RemoveAt(0);
                g_MlNodeDataCache.Delete(victim);
            }
        }
    }

    void _ControlTreeNodeDataCacheInsert(const string &in key, _ControlTreeNodeDataEntry@ e) {
        bool exists = g_ControlTreeNodeDataCache.Exists(key);
        g_ControlTreeNodeDataCache.Set(key, @e);
        if (!exists) {
            g_ControlTreeNodeDataCacheKeys.InsertLast(key);
            if (g_ControlTreeNodeDataCacheKeys.Length > kTreeNodeDataCacheMax) {
                string victim = g_ControlTreeNodeDataCacheKeys[0];
                g_ControlTreeNodeDataCacheKeys.RemoveAt(0);
                g_ControlTreeNodeDataCache.Delete(victim);
            }
        }
    }

    void _MlNodeDataCacheClear() {
        g_MlNodeDataCache.DeleteAll();
        g_MlNodeDataCacheKeys.Resize(0);
    }

    void _ControlTreeNodeDataCacheClear() {
        g_ControlTreeNodeDataCache.DeleteAll();
        g_ControlTreeNodeDataCacheKeys.Resize(0);
    }

    _MlNodeDataEntry@ _MlNodeData(CGameManialinkControl@ n, const string &in uiPath, bool needText = false, bool needClasses = false, bool needVisible = false) {
        if (n is null) return null;

        uint epoch = g_MlSearchCacheEpoch;
        uint now = Time::Now;
        uint ttl = S_DebugTreeNodeCacheTtlMs;
        string key = uiPath;

        _MlNodeDataEntry@ e;
        bool valid = false;
        if (g_MlNodeDataCache.Get(key, @e) && e !is null) {
            uint age = now - e.stampMs;
            bool ttlOk = (ttl == 0 || age <= ttl);
            if (ttlOk && e.epoch == epoch) valid = true;
        }

        if (!valid || e is null) {
            @e = _MlNodeDataEntry();
            e.epoch = epoch;
            e.stampMs = now;
            e.id = n.ControlId;
            e.type = UiNav::ML::TypeName(n);
            e.label = _ColorizeTypeName(e.type);
            if (e.id.Length > 0) e.label += " #" + e.id;
            if (S_DebugTreeInlineText || needText) {
                e.text = UiNav::CleanUiFormatting(UiNav::ML::ReadText(n));
                e.hasText = true;
                if (S_DebugTreeInlineText && e.text.Length > 0) {
                    e.label += " | \"" + _TrimTreeText(e.text) + "\"";
                }
            }
            if (needClasses) {
                auto classes = n.ControlClasses;
                for (uint c = 0; c < classes.Length; ++c) {
                    string cc = classes[c].Trim().ToLower();
                    if (cc.Length == 0) continue;
                    if (e.classes.Length > 0) e.classes += " ";
                    e.classes += cc;
                }
                e.hasClasses = true;
            }
            if (needVisible) {
                e.visible = n.Visible;
            }
            _MlNodeDataCacheInsert(key, e);
            return e;
        }

        if ((S_DebugTreeInlineText || needText) && !e.hasText) {
            e.text = UiNav::CleanUiFormatting(UiNav::ML::ReadText(n));
            e.hasText = true;
            if (S_DebugTreeInlineText && e.text.Length > 0 && !e.label.Contains(" | \"")) {
                e.label += " | \"" + _TrimTreeText(e.text) + "\"";
            }
            e.stampMs = now;
        }
        if (needClasses && !e.hasClasses) {
            auto classes = n.ControlClasses;
            for (uint c = 0; c < classes.Length; ++c) {
                string cc = classes[c].Trim().ToLower();
                if (cc.Length == 0) continue;
                if (e.classes.Length > 0) e.classes += " ";
                e.classes += cc;
            }
            e.hasClasses = true;
            e.stampMs = now;
        }
        if (needVisible) {
            e.visible = n.Visible;
        }
        return e;
    }

    _ControlTreeNodeDataEntry@ _ControlTreeNodeData(CControlBase@ n, const string &in uiPath, bool needText = false, bool needVisible = false, bool needId = false) {
        if (n is null) return null;

        uint epoch = g_ControlTreeSearchCacheEpoch;
        uint now = Time::Now;
        uint ttl = S_DebugTreeNodeCacheTtlMs;
        string key = uiPath;

        _ControlTreeNodeDataEntry@ e;
        bool valid = false;
        if (g_ControlTreeNodeDataCache.Get(key, @e) && e !is null) {
            uint age = now - e.stampMs;
            bool ttlOk = (ttl == 0 || age <= ttl);
            if (ttlOk && e.epoch == epoch) valid = true;
        }

        if (!valid || e is null) {
            @e = _ControlTreeNodeDataEntry();
            e.epoch = epoch;
            e.stampMs = now;
            e.type = NodeTypeName(n);
            e.label = _ColorizeTypeName(e.type);
            string idNameDisplay = n.IdName.Trim();
            if (idNameDisplay.Length > 0) e.label += " #" + idNameDisplay;
            if (S_DebugTreeInlineText || needText) {
                e.text = CleanUiFormatting(ReadText(n));
                e.hasText = true;
                if (S_DebugTreeInlineText && e.text.Length > 0) {
                    e.label += " | \"" + _TrimTreeText(e.text) + "\"";
                }
            }
            if (needId) {
                string idName = n.IdName.Trim().ToLower();
                string stack = n.StackText.Trim().ToLower();
                if (idName.Length > 0) e.id = idName;
                if (stack.Length > 0) {
                    if (e.id.Length > 0) e.id += " ";
                    e.id += stack;
                }
                e.hasId = true;
            }
            if (needVisible) {
                e.visible = IsEffectivelyVisible(n);
                e.hasVisible = true;
            }
            _ControlTreeNodeDataCacheInsert(key, e);
            return e;
        }

        if ((S_DebugTreeInlineText || needText) && !e.hasText) {
            e.text = CleanUiFormatting(ReadText(n));
            e.hasText = true;
            if (S_DebugTreeInlineText && e.text.Length > 0 && !e.label.Contains(" | \"")) {
                e.label += " | \"" + _TrimTreeText(e.text) + "\"";
            }
            e.stampMs = now;
        }
        if (needId && !e.hasId) {
            string idName = n.IdName.Trim().ToLower();
            string stack = n.StackText.Trim().ToLower();
            e.id = "";
            if (idName.Length > 0) e.id = idName;
            if (stack.Length > 0) {
                if (e.id.Length > 0) e.id += " ";
                e.id += stack;
            }
            e.hasId = true;
        }
        if (needVisible) {
            e.visible = IsEffectivelyVisible(n);
            e.hasVisible = true;
        }
        return e;
    }

    string _MlLabel(CGameManialinkControl@ n, const string &in uiPath) {
        auto e = _MlNodeData(n, uiPath, S_DebugTreeInlineText, false, false);
        if (e is null) return "<null>";
        return e.label;
    }

    string _ControlTreeLabel(CControlBase@ n, const string &in uiPath) {
        auto e = _ControlTreeNodeData(n, uiPath, S_DebugTreeInlineText, false);
        if (e is null) return "<null>";
        return e.label;
    }

    class _SearchTerm {
        bool negated = false;
        string field = "any";
        string value = "";
    }

    

}
}
