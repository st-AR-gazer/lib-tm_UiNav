namespace UiNav {
namespace Debug {

    string g_MlControlTreePathLookupKey = "";
    string g_MlControlTreePathCached = "";
    string g_MlControlTreePathStatus = "";
    int g_MlSelectionTabSelectPending = -1;
    string g_MlSelectionTabContextKey = "";

    class MlLiveMetrics {
        bool ok = false;
        vec2 absPos = vec2();
        float absScale = 1.0f;
        vec2 absSize = vec2();
        vec2 boundsMin = vec2();
        vec2 boundsMax = vec2();
        float anchorX = 0.5f;
        float anchorY = 0.5f;
        string hAlign = "";
        string vAlign = "";
        bool selfHidden = false;
        bool hiddenByAncestor = false;
        bool underClipAncestor = false;
        int clipAncestorCount = 0;
    }

    class MlSelectionContext {
        CGameManialinkControl@ sel = null;
        CGameUILayer@ layer = null;
        CControlBase@ controlTree = null;
        string id;
        string text;
        string idSel;
        string rootId;
        string idChain;
        string mixedChain;
        string idList;
        string mlSelector;
        string classList;
        string classSel;
        string fullSel;
        string controlTreeDisplay;
    }

    bool _MlSelectionCopyValueText(const string &in display, const string &in payload, const string &in id, bool accent = false) {
        UI::PushID("ml-info-copy-" + id);
        if (payload.Length == 0) {
            UI::Text("<empty>");
            UI::PopID();
            return false;
        }

        if (accent) UI::TextWrapped("\\$9cf" + display + "\\$z");
        else UI::TextWrapped(display);

        bool hovered = UI::IsItemHovered();
        if (hovered) {
            UI::SetMouseCursor(UI::MouseCursor::Hand);
            UI::SetTooltip("Click to copy");
        }
        bool clicked = hovered && UI::IsMouseClicked(UI::MouseButton::Left);
        if (clicked) IO::SetClipboard(payload);
        UI::PopID();
        return clicked;
    }

    void _MlSelectionInfoLine(const string &in label, const string &in value, bool accent = false, const string &in id = "") {
        UI::TextDisabled(label + ":");
        UI::SameLine();
        string copyValue = value;
        string displayValue = value.Length > 0 ? value : "<empty>";
        string copyId = id.Length > 0 ? id : label;
        _MlSelectionCopyValueText(displayValue, copyValue, copyId, accent);
    }

    bool _MlCopyActionText(const string &in text, const string &in payload, const string &in id) {
        UI::PushID("ml-copy-action-" + id);
        if (payload.Length == 0) {
            UI::TextDisabled(text);
            UI::PopID();
            return false;
        }
        UI::TextWrapped("\\$9cf" + text + "\\$z");
        bool hovered = UI::IsItemHovered();
        if (hovered) {
            UI::SetMouseCursor(UI::MouseCursor::Hand);
            UI::SetTooltip("Click to copy");
        }
        bool clicked = hovered && UI::IsMouseClicked(UI::MouseButton::Left);
        if (clicked) IO::SetClipboard(payload);
        UI::PopID();
        return clicked;
    }

    void _MlResetControlTreePathLookup(const string &in key) {
        g_MlControlTreePathLookupKey = key;
        g_MlControlTreePathCached = "";
        g_MlControlTreePathStatus = "";
    }

    bool _MlTryResolveControlTreePath(CControlBase@ node, string &out display) {
        display = "";
        if (node is null) return false;
        uint controlTreeOverlay = 0;
        int controlTreeRootIx = -1;
        string controlTreeRel = "";
        if (!_FindControlTreePathForControlAnyOverlay(node, controlTreeOverlay, controlTreeRootIx, controlTreeRel)) return false;
        display = _ControlTreePathDisplay(controlTreeOverlay, controlTreeRootIx, controlTreeRel);
        return display.Length > 0;
    }

    array<string> _MlSelectedPathParts() {
        array<string> parts;
        string path = g_SelectedMlPath.Trim();
        if (path.Length == 0) return parts;
        auto raw = path.Split("/");
        for (uint i = 0; i < raw.Length; ++i) {
            string part = raw[i].Trim();
            if (part.Length == 0) continue;
            parts.InsertLast(part);
        }
        return parts;
    }

    string _MlPathSuffixRawFromParentDepth(int parentDepth) {
        if (parentDepth <= 0) return "";
        auto parts = _MlSelectedPathParts();
        if (parts.Length == 0) return "";
        int splitIx = int(parts.Length) - parentDepth;
        if (splitIx < 0) splitIx = 0;
        array<string> tail;
        for (int i = splitIx; i < int(parts.Length); ++i) {
            tail.InsertLast(parts[uint(i)]);
        }
        return _JoinParts(tail, "/");
    }

    string _MlPathSuffixMixedFromParentDepth(int parentDepth) {
        if (parentDepth <= 0) return "";
        auto parts = _MlSelectedPathParts();
        if (parts.Length == 0) return "";
        int splitIx = int(parts.Length) - parentDepth;
        if (splitIx < 0) splitIx = 0;

        auto root = _GetMlRootByLayerIx(g_SelectedMlLayerIx, g_SelectedMlAppKind);
        if (root is null) return "";

        CGameManialinkControl@ cur = root;
        array<string> tail;
        for (int i = 0; i < int(parts.Length); ++i) {
            int idx = Text::ParseInt(parts[uint(i)]);
            if (idx < 0) return "";

            auto frame = cast<CGameManialinkFrame@>(cur);
            if (frame is null) return "";
            if (uint(idx) >= frame.Controls.Length) return "";

            @cur = frame.Controls[uint(idx)];
            if (cur is null) return "";

            if (i < splitIx) continue;
            string token = cur.ControlId.Trim();
            if (token.Length > 0) tail.InsertLast("#" + token);
            else tail.InsertLast(parts[uint(i)]);
        }
        return _JoinParts(tail, "/");
    }

    string _MlPathSuffixForParentDepth(int parentDepth) {
        if (parentDepth <= 0) return "";
        string mixed = _MlPathSuffixMixedFromParentDepth(parentDepth);
        if (mixed.Length > 0) return mixed;
        return _MlPathSuffixRawFromParentDepth(parentDepth);
    }

    void _MlResolveControlTreePathNow(CGameManialinkControl@ selectedMl, CControlBase@ controlTree) {
        g_MlControlTreePathCached = "";
        g_MlControlTreePathStatus = "";

        string fullPath = "";
        if (_MlTryResolveControlTreePath(controlTree, fullPath)) {
            g_MlControlTreePathCached = fullPath;
            g_MlControlTreePathStatus = "Resolved.";
            return;
        }

        CGameManialinkControl@ curMl = selectedMl;
        int parentDepth = 0;
        while (curMl !is null) {
            CControlBase@ curCt = null;
            try {
                @curCt = curMl.Control;
            } catch {
                @curCt = null;
            }

            string parentPath = "";
            if (_MlTryResolveControlTreePath(curCt, parentPath)) {
                if (parentDepth <= 0) {
                    g_MlControlTreePathCached = parentPath;
                    g_MlControlTreePathStatus = "Resolved.";
                    return;
                }

                string suffix = _MlPathSuffixForParentDepth(parentDepth);
                if (suffix.Length > 0) {
                    g_MlControlTreePathCached = parentPath + " | ML suffix: " + suffix + " (partial)";
                } else {
                    g_MlControlTreePathCached = parentPath + " (partial)";
                }
                g_MlControlTreePathStatus = "Partial resolve only (ControlTree path reaches a parent; remaining path is ManiaLink-only).";
                return;
            }

            CGameManialinkFrame@ parent = null;
            bool parentOk = false;
            try {
                @parent = curMl.Parent;
                parentOk = true;
            } catch {
                parentOk = false;
            }
            if (!parentOk || parent is null) break;

            @curMl = cast<CGameManialinkControl@>(parent);
            parentDepth++;
            if (parentDepth > 128) break;
        }

        g_MlControlTreePathStatus = "No control tree resolvable.";
    }

    bool _MlActionText(const string &in text, const string &in id) {
        UI::PushID("ml-action-text-" + id);
        UI::Text("\\$9cf" + text + "\\$z");
        bool hovered = UI::IsItemHovered();
        if (hovered) {
            UI::SetMouseCursor(UI::MouseCursor::Hand);
            UI::SetTooltip("Click");
        }
        bool clicked = hovered && UI::IsMouseClicked(UI::MouseButton::Left);
        UI::PopID();
        return clicked;
    }

    void _MlSelectionCopyLine(const string &in label, const string &in value, const string &in id) {
        if (value.Length > 0) {
            UI::TextDisabled(label + ":");
            UI::SameLine();
            _MlCopyActionText(value, value, id);
            return;
        }
        UI::TextDisabled(label + ": <empty>");
    }

    bool _BuildMlSelectionContext(MlSelectionContext@ &out ctx, string &out err) {
        err = "";
        @ctx = null;

        auto sel = _ResolveSelectedMlNode(err);
        if (sel is null) return false;

        MlSelectionContext@ built = MlSelectionContext();
        @built.sel = sel;
        @built.layer = _GetMlLayerByIx(g_SelectedMlAppKind, g_SelectedMlLayerIx);

        built.id = UiNav::ML::ControlId(sel);
        built.text = UiNav::CleanUiFormatting(UiNav::ML::ReadText(sel));
        if (built.text.Length > 200) built.text = built.text.SubStr(0, 200) + "...";
        built.idSel = (built.id.Length > 0) ? ("#" + built.id) : "";

        _BuildMlChains(built.rootId, built.idChain, built.mixedChain, built.idList);
        built.mlSelector = _PickMlExportSelector(built.idChain, built.mixedChain);
        built.classSel = _MlFirstClassSelector(sel, built.classList);
        built.fullSel = _BuildMlFullSelectorPath(built.layer, built.rootId, built.idChain, built.mixedChain);

        @built.controlTree = UiNav::ML::_TryGetControl(sel);
        string ctLookupKey = g_SelectedMlAppKind + "|" + g_SelectedMlLayerIx + "|" + g_SelectedMlPath + "|" + g_SelectedMlUiPath;
        if (ctLookupKey != g_MlControlTreePathLookupKey) _MlResetControlTreePathLookup(ctLookupKey);
        if (built.sel !is null && g_MlControlTreePathCached.Length == 0 && g_MlControlTreePathStatus.Length == 0) {
            _MlResolveControlTreePathNow(built.sel, built.controlTree);
        }
        built.controlTreeDisplay = g_MlControlTreePathCached;

        @ctx = built;
        return true;
    }

    float _MlAnchorXFromLiveAlign(CGameManialinkControl::EAlignHorizontal a) {
        int v = int(a);
        if (v == 0) return 0.0f;
        if (v == 2) return 1.0f;
        return 0.5f;
    }

    float _MlAnchorYFromLiveAlign(CGameManialinkControl::EAlignVertical a) {
        int v = int(a);
        if (v == 0) return 0.0f;
        if (v == 2) return 1.0f;
        return 0.5f;
    }

    string _MlAlignHName(CGameManialinkControl::EAlignHorizontal a) {
        int v = int(a);
        if (v == 0) return "left";
        if (v == 1) return "center";
        if (v == 2) return "right";
        return "" + v;
    }

    string _MlAlignVName(CGameManialinkControl::EAlignVertical a) {
        int v = int(a);
        if (v == 0) return "top";
        if (v == 1) return "center";
        if (v == 2) return "bottom";
        if (v == 4) return "center2";
        return "" + v;
    }

    string _MlFmtVec2(const vec2 &in v) {
        return "(" + v.x + ", " + v.y + ")";
    }

    MlLiveMetrics@ _ComputeMlLiveMetrics(CGameManialinkControl@ sel) {
        auto m = MlLiveMetrics();
        if (sel is null) return m;

        vec2 absPos = vec2();
        vec2 size = vec2();
        float absScale = 1.0f;
        CGameManialinkControl::EAlignHorizontal ha = CGameManialinkControl::EAlignHorizontal(1);
        CGameManialinkControl::EAlignVertical va = CGameManialinkControl::EAlignVertical(1);

        bool ok = true;
        try { absPos = sel.AbsolutePosition_V3; } catch { ok = false; }
        try { size = sel.Size; } catch { ok = false; }
        try { absScale = sel.AbsoluteScale; } catch { absScale = 1.0f; }
        try { ha = sel.HorizontalAlign; } catch { ha = CGameManialinkControl::EAlignHorizontal(1); }
        try { va = sel.VerticalAlign; } catch { va = CGameManialinkControl::EAlignVertical(1); }

        bool selfVisible = true;
        try { selfVisible = sel.Visible; } catch { selfVisible = true; }

        bool hiddenByAncestor = false;
        int clipAnc = 0;
        CGameManialinkFrame@ parent = null;
        try { @parent = sel.Parent; } catch { @parent = null; }
        int guard = 0;
        while (parent !is null && guard < 256) {
            guard++;
            bool parentVisible = true;
            try { parentVisible = parent.Visible; } catch { parentVisible = true; }
            if (!parentVisible) hiddenByAncestor = true;

            bool clipActive = false;
            try { clipActive = parent.ClipWindowActive; } catch { clipActive = false; }
            if (clipActive) clipAnc++;

            try { @parent = parent.Parent; } catch { @parent = null; }
        }

        if (!ok) return m;

        m.ok = true;
        m.absPos = absPos;
        m.absScale = absScale;
        m.absSize = size * absScale;
        m.anchorX = _MlAnchorXFromLiveAlign(ha);
        m.anchorY = _MlAnchorYFromLiveAlign(va);
        m.hAlign = _MlAlignHName(ha);
        m.vAlign = _MlAlignVName(va);
        m.boundsMin = vec2(absPos.x - m.anchorX * m.absSize.x, absPos.y - (1.0f - m.anchorY) * m.absSize.y);
        m.boundsMax = vec2(absPos.x + (1.0f - m.anchorX) * m.absSize.x, absPos.y + m.anchorY * m.absSize.y);
        m.selfHidden = !selfVisible;
        m.hiddenByAncestor = hiddenByAncestor;
        m.clipAncestorCount = clipAnc;
        m.underClipAncestor = clipAnc > 0;
        return m;
    }

    string _BuildMlSelectionBoundsDataText(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return "";

        auto m = _ComputeMlLiveMetrics(ctx.sel);
        array<string> lines;
        string title = UiNav::ML::TypeName(ctx.sel);
        if (ctx.id.Length > 0) title += " #" + ctx.id;
        lines.InsertLast(title);

        if (m is null || !m.ok) {
            lines.InsertLast("Live geometry unavailable.");
        } else {
            lines.InsertLast("Abs pos: " + _MlFmtVec2(m.absPos));
            lines.InsertLast("Abs scale: " + m.absScale);
            lines.InsertLast("Abs size: " + _MlFmtVec2(m.absSize));
            lines.InsertLast("Bounds min: " + _MlFmtVec2(m.boundsMin));
            lines.InsertLast("Bounds max: " + _MlFmtVec2(m.boundsMax));
            vec2 sz = m.boundsMax - m.boundsMin;
            vec2 center = (m.boundsMin + m.boundsMax) * 0.5f;
            lines.InsertLast("Bounds size: " + _MlFmtVec2(sz));
            lines.InsertLast("Bounds center: " + _MlFmtVec2(center));
            lines.InsertLast("Anchor: (" + m.anchorX + ", " + m.anchorY + ") from halign=" + m.hAlign + " valign=" + m.vAlign);
            lines.InsertLast("Visibility: " + (m.selfHidden ? "self hidden" : "self visible")
                + " | " + (m.hiddenByAncestor ? "ancestor hidden" : "ancestors visible"));
            if (m.underClipAncestor) lines.InsertLast("Under clip ancestors: " + m.clipAncestorCount);
        }

        string outText = "";
        for (uint i = 0; i < lines.Length; ++i) outText += (i == 0 ? "" : "\n") + lines[i];
        return outText;
    }

    void _RenderMlSelectionSummaryContents(MlSelectionContext@ ctx, const string &in idPrefix = "ml-summary") {
        if (ctx is null || ctx.sel is null) return;

        string title = UiNav::ML::TypeName(ctx.sel);
        if (ctx.id.Length > 0) title += " #" + ctx.id;
        _MlSelectionCopyValueText(title, title, "ml-summary-title");

        string metaLine = "Layer " + g_SelectedMlLayerIx + " | App " + _MlAppNameByKind(g_SelectedMlAppKind)
            + " | Path " + (g_SelectedMlPath.Length > 0 ? g_SelectedMlPath : "<root>");
        _MlSelectionCopyValueText(metaLine, metaLine, "ml-summary-meta");

        string textValue = (ctx.text.Length > 0 ? ctx.text : "<empty>");
        _MlSelectionCopyValueText("Text: " + textValue, textValue, "ml-summary-text");

        if (ctx.mlSelector.Length > 0) {
            UI::TextDisabled("Selector:");
            UI::SameLine();
            _MlSelectionCopyValueText(ctx.mlSelector, ctx.mlSelector, "ml-summary-selector", true);
        } else {
            UI::TextDisabled("Selector:");
            UI::SameLine();
            _MlSelectionCopyValueText("<empty>", "<empty>", "ml-summary-selector-empty");
        }

        string ctPath = ctx.controlTreeDisplay;
        if (ctPath.Length == 0) {
            if (g_MlControlTreePathStatus.Length > 0) ctPath = g_MlControlTreePathStatus;
            else ctPath = "No control tree resolvable.";
        }
        UI::TextDisabled("ControlTree:");
        UI::SameLine();
        bool ctAccent = ctx.controlTreeDisplay.Length > 0;
        _MlSelectionCopyValueText(ctPath, ctPath, "ml-summary-controltree", ctAccent);
    }

    void _RenderMlSelectionHeader(MlSelectionContext@ ctx) {
        UI::BeginChild("##ml-selection-summary", vec2(0, 142), true);
        _RenderMlSelectionSummaryContents(ctx, "ml-header-summary");
        UI::EndChild();
    }

    void _EnsureMlSelectionTabPending() {
        string key = g_SelectedMlUiPath + "|" + g_SelectedMlPath + "|" + g_SelectedMlLayerIx + "|" + g_SelectedMlAppKind;
        if (g_MlSelectionTabContextKey == key) return;
        g_MlSelectionTabContextKey = key;
        g_MlSelectionTabSelectPending = 0;
    }

    void _RenderMlSelection() {
        if (g_SelectedMlUiPath.Length == 0) {
            UI::Text("No selection");
            return;
        }

        MlSelectionContext@ ctx = null;
        string selErr;
        if (!_BuildMlSelectionContext(ctx, selErr) || ctx is null) {
            _DiagBreadcrumb("ML selection: resolve failed: " + selErr, "_RenderMlSelection", /*forceWrite=*/true);
            UI::Text("Selection could not be resolved: " + selErr);
            if (UI::Button("Clear selection##ml")) _ClearMlSelection();
            return;
        }

        _RenderMlSelectionHeader(ctx);

        UI::Separator();
        UI::TextDisabled("Core: Overview | Selectors | Code");
        UI::TextDisabled("Advanced: Actions | Export | Notes");

        _EnsureMlSelectionTabPending();
        UI::BeginTabBar("##ml-selection-tabs");
        int flags = g_MlSelectionTabSelectPending == 0 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Overview", flags)) {
            if (g_MlSelectionTabSelectPending == 0) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionOverview(ctx);
            UI::EndTabItem();
        }
        flags = g_MlSelectionTabSelectPending == 1 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Selectors", flags)) {
            if (g_MlSelectionTabSelectPending == 1) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionSelectors(ctx);
            UI::EndTabItem();
        }
        flags = g_MlSelectionTabSelectPending == 2 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Code", flags)) {
            if (g_MlSelectionTabSelectPending == 2) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionCode(ctx);
            UI::EndTabItem();
        }
        flags = g_MlSelectionTabSelectPending == 3 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Actions", flags)) {
            if (g_MlSelectionTabSelectPending == 3) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionActions(ctx);
            UI::EndTabItem();
        }
        flags = g_MlSelectionTabSelectPending == 4 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Export", flags)) {
            if (g_MlSelectionTabSelectPending == 4) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionExport(ctx);
            UI::EndTabItem();
        }
        flags = g_MlSelectionTabSelectPending == 5 ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None;
        if (UI::BeginTabItem("Notes", flags)) {
            if (g_MlSelectionTabSelectPending == 5) g_MlSelectionTabSelectPending = -1;
            _RenderMlSelectionNotes(ctx);
            UI::EndTabItem();
        }
        UI::EndTabBar();
    }

}
}
