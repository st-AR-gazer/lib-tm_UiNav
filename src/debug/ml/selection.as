namespace UiNav {
namespace Debug {

    string g_MlControlTreePathLookupKey = "";
    string g_MlControlTreePathCached = "";
    string g_MlControlTreePathStatus = "";

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

    void _RenderMlSelectionHeader(MlSelectionContext@ ctx) {
        UI::BeginChild("##ml-selection-summary", vec2(0, 118), true);
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
        UI::EndChild();
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

        UI::BeginTabBar("##ml-selection-tabs");
        if (UI::BeginTabItem("Overview")) {
            _RenderMlSelectionOverview(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Selectors")) {
            _RenderMlSelectionSelectors(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Code")) {
            _RenderMlSelectionCode(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Actions")) {
            _RenderMlSelectionActions(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Export")) {
            _RenderMlSelectionExport(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Notes")) {
            _RenderMlSelectionNotes(ctx);
            UI::EndTabItem();
        }
        UI::EndTabBar();
    }

}
}
