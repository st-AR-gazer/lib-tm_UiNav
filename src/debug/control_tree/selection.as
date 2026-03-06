namespace UiNav {
namespace Debug {

    string g_ControlTreeSelectionStatus = "";
    bool g_ControlTreeSnapshotIncludeChildren = true;
    int g_ControlTreeSnapshotMaxDepth = 4;
    string g_ControlTreeSnapshotPath = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_snapshot.txt");
    string g_ControlTreeSnapshotStatus = "";
    string g_ControlTreeSnapshotPreview = "";
    string g_ControlTreeSnapshotPreviewKey = "";

    class ControlTreeSelectionContext {
        CControlBase@ sel = null;
        string text;
        string selIdName;
        string selStackText;
        uint childCount = 0;
        bool isVisible = false;
        string relPath;
        string dispPath;
        string uiPath;
        string mixedPath;
        string indexPath;
        string selector;
        string idQuery;
    }

    bool _ControlTreeSelectionCopyValueText(const string &in display, const string &in payload, const string &in id, bool accent = false) {
        UI::PushID("ct-info-copy-" + id);
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

    void _ControlTreeInfoLine(const string &in label, const string &in value, bool accent = false, const string &in id = "") {
        UI::TextDisabled(label + ":");
        UI::SameLine();
        string copyValue = value;
        string displayValue = value.Length > 0 ? value : "<empty>";
        string copyId = id.Length > 0 ? id : label;
        _ControlTreeSelectionCopyValueText(displayValue, copyValue, copyId, accent);
    }

    bool _ControlTreeCopyActionText(const string &in text, const string &in payload, const string &in id) {
        UI::PushID("ct-copy-action-" + id);
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

    void _ControlTreeCopyLine(const string &in label, const string &in value, const string &in btnId) {
        if (value.Length > 0) {
            UI::TextDisabled(label + ":");
            UI::SameLine();
            _ControlTreeCopyActionText(value, value, btnId);
            return;
        }
        UI::TextDisabled(label + ": <empty>");
    }

    string _ControlTreeShortText(const string &in raw, uint maxLen = 220) {
        string t = raw.Trim();
        int maxLenInt = int(maxLen);
        if (int(t.Length) > maxLenInt) t = t.SubStr(0, maxLenInt) + "...";
        return t;
    }

    void _ControlTreeSnapshotLinesRec(CControlBase@ n, const string &in relPath, int depth, int maxDepth, bool includeChildren, array<string>@ lines) {
        if (n is null || lines is null) return;
        if (depth > maxDepth) return;

        string ind = "";
        for (int i = 0; i < depth; ++i) ind += "  ";
        string idName = n.IdName.Trim();
        string stack = _ControlTreeShortText(CleanUiFormatting(n.StackText), 140);
        string text = _ControlTreeShortText(CleanUiFormatting(ReadText(n)), 160);
        bool vis = IsEffectivelyVisible(n);
        uint childCount = _ChildrenLen(n);

        string line = ind + relPath + " : " + NodeTypeName(n)
            + " vis=" + (vis ? "true" : "false")
            + " children=" + childCount;
        if (idName.Length > 0) line += " id=" + idName;
        lines.InsertLast(line);
        if (stack.Length > 0) lines.InsertLast(ind + "  stack=\"" + stack + "\"");
        if (text.Length > 0) lines.InsertLast(ind + "  text=\"" + text + "\"");

        if (!includeChildren || depth >= maxDepth) return;
        for (uint i = 0; i < childCount; ++i) {
            auto ch = _ChildAt(n, i);
            if (ch is null) continue;
            string childRel = relPath.Length == 0 ? ("" + i) : (relPath + "/" + i);
            _ControlTreeSnapshotLinesRec(ch, childRel, depth + 1, maxDepth, includeChildren, lines);
        }
    }

    string _BuildControlTreeSnapshotText(CControlBase@ n) {
        array<string> lines;
        lines.Reserve(256);
        string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
        string relPath = g_SelectedControlTreePath;
        if (relPath.Length == 0 && g_SelectedControlTreeRootIx >= 0) relPath = "root[" + g_SelectedControlTreeRootIx + "]";

        lines.InsertLast("UiNav ControlTree snapshot @ " + ts);
        lines.InsertLast("overlay=" + g_SelectedControlTreeOverlayAtSel + " root=" + g_SelectedControlTreeRootIx + " path=" + relPath);

        int maxDepth = g_ControlTreeSnapshotMaxDepth;
        if (maxDepth < 0) maxDepth = 0;
        if (maxDepth > 24) maxDepth = 24;
        _ControlTreeSnapshotLinesRec(n, relPath, 0, maxDepth, g_ControlTreeSnapshotIncludeChildren, lines);

        string outStr = "";
        for (uint i = 0; i < lines.Length; ++i) outStr += lines[i] + "\n";
        return outStr;
    }

    void _RefreshControlTreeSnapshotPreview(CControlBase@ sel) {
        string key = g_SelectedControlTreeUiPath
            + "|" + (g_ControlTreeSnapshotIncludeChildren ? "1" : "0")
            + "|" + g_ControlTreeSnapshotMaxDepth;
        if (key == g_ControlTreeSnapshotPreviewKey) return;
        g_ControlTreeSnapshotPreviewKey = key;
        g_ControlTreeSnapshotPreview = _BuildControlTreeSnapshotText(sel);
    }

    void _ControlTreeSetVisibleSubtree(CControlBase@ node, bool visible, int depth = 0, int maxDepth = 128) {
        if (node is null) return;
        if (depth > maxDepth) return;
        _SetControlTreeVisibleSelf(node, visible);
        uint len = _ChildrenLen(node);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(node, i);
            if (ch is null) continue;
            _ControlTreeSetVisibleSubtree(ch, visible, depth + 1, maxDepth);
        }
    }

    void _ControlTreeExpandToUiPath(const string &in rawUiPath) {
        string uiPath = rawUiPath.Trim();
        if (uiPath.Length == 0) return;
        auto parts = uiPath.Split("/");
        string cur = "";
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            if (cur.Length == 0) cur = part;
            else cur += "/" + part;
            _SetControlTreeTreeOpen(cur, true);
        }
    }

    bool _BuildControlTreeSelectionContext(ControlTreeSelectionContext@ &out ctx, string &out err) {
        err = "";
        @ctx = null;

        auto sel = _ResolveSelectedControlTreeNode(err);
        if (sel is null) return false;

        ControlTreeSelectionContext@ built = ControlTreeSelectionContext();
        @built.sel = sel;
        built.text = CleanUiFormatting(ReadText(sel));
        if (built.text.Length > 200) built.text = built.text.SubStr(0, 200) + "...";
        built.selIdName = sel.IdName.Trim();
        built.selStackText = _ControlTreeShortText(CleanUiFormatting(sel.StackText), 220);
        built.childCount = _ChildrenLen(sel);
        built.isVisible = IsEffectivelyVisible(sel);
        built.relPath = g_SelectedControlTreePath;
        built.dispPath = g_SelectedControlTreeDisplayPath;
        built.uiPath = g_SelectedControlTreeUiPath;
        built.mixedPath = _BuildControlTreeMixedPathForSelection();
        built.indexPath = built.relPath;
        built.selector = built.mixedPath.Length > 0 ? built.mixedPath : built.indexPath;
        built.idQuery = built.selIdName.Length > 0 ? ("**#" + built.selIdName) : "";

        @ctx = built;
        return true;
    }

    void _RenderControlTreeSelectionHeader(ControlTreeSelectionContext@ ctx) {
        UI::BeginChild("##controlTree-selection-summary", vec2(0, 118), true);
        string title = NodeTypeName(ctx.sel);
        if (ctx.selIdName.Length > 0) title += " #" + ctx.selIdName;
        _ControlTreeSelectionCopyValueText(title, title, "controlTree-summary-title");

        string metaLine = "Overlay " + g_SelectedControlTreeOverlayAtSel + " | Root " + g_SelectedControlTreeRootIx
            + " | Visible " + (ctx.isVisible ? "true" : "false") + " | Children " + ctx.childCount;
        _ControlTreeSelectionCopyValueText(metaLine, metaLine, "controlTree-summary-meta");

        if (ctx.selector.Length > 0) {
            UI::TextDisabled("Selector:");
            UI::SameLine();
            _ControlTreeSelectionCopyValueText(ctx.selector, ctx.selector, "controlTree-summary-selector", true);
        } else {
            UI::TextDisabled("Selector:");
            UI::SameLine();
            _ControlTreeSelectionCopyValueText("<empty>", "<empty>", "controlTree-summary-selector-empty");
        }
        string dispLine = "Display: " + (ctx.dispPath.Length > 0 ? ctx.dispPath : "<empty>");
        _ControlTreeSelectionCopyValueText(dispLine, (ctx.dispPath.Length > 0 ? ctx.dispPath : "<empty>"), "controlTree-summary-display");
        UI::EndChild();
    }

    void _RenderControlTreeSelection() {
        if (g_SelectedControlTreeUiPath.Length == 0) {
            UI::Text("No selection");
            return;
        }

        ControlTreeSelectionContext@ ctx = null;
        string selErr;
        if (!_BuildControlTreeSelectionContext(ctx, selErr) || ctx is null) {
            _DiagBreadcrumb("ControlTree selection: resolve failed: " + selErr, "_RenderControlTreeSelection", /*forceWrite=*/true);
            UI::Text("Selection could not be resolved: " + selErr);
            if (UI::Button("Clear selection##controlTree")) _ClearControlTreeSelection();
            return;
        }

        _RenderControlTreeSelectionHeader(ctx);

        UI::Separator();
        UI::TextDisabled("Core: Overview | Selectors | Code");
        UI::TextDisabled("Advanced: Actions | Export | Notes");

        UI::BeginTabBar("##controlTree-selection-tabs");
        if (UI::BeginTabItem("Overview")) {
            _RenderControlTreeSelectionOverview(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Selectors")) {
            _RenderControlTreeSelectionSelectors(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Code")) {
            _RenderControlTreeSelectionCode(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Actions")) {
            _RenderControlTreeSelectionActions(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Export")) {
            _RenderControlTreeSelectionExport(ctx);
            UI::EndTabItem();
        }
        if (UI::BeginTabItem("Notes")) {
            _RenderControlTreeSelectionNotes(ctx);
            UI::EndTabItem();
        }
        UI::EndTabBar();
    }

}
}
