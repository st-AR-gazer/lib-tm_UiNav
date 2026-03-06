namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionActions(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Live visibility toggles and navigation actions.");

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Visibility")) {
            if (UI::Button("Show selected")) _SetControlTreeVisibleSelf(ctx.sel, true);
            UI::SameLine();
            if (UI::Button("Hide selected")) _SetControlTreeVisibleSelf(ctx.sel, false);
            if (UI::Button("Show selected subtree")) _ControlTreeSetVisibleSubtree(ctx.sel, true);
            UI::SameLine();
            if (UI::Button("Hide selected subtree")) _ControlTreeSetVisibleSubtree(ctx.sel, false);
        }

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Navigation")) {
            if (UI::Button("Expand tree to selection")) {
                _ControlTreeExpandToUiPath(g_SelectedControlTreeUiPath);
                g_ControlTreeSelectionStatus = "Expanded tree to selected node.";
            }
            UI::SameLine();
            if (UI::Button("Focus selected overlay")) {
                g_ControlTreeOverlay = int(g_SelectedControlTreeOverlayAtSel);
                g_ControlTreeSelectionStatus = "Focused overlay " + g_SelectedControlTreeOverlayAtSel + ".";
            }
            if (UI::Button("Focus selected node")) {
                bool ok = _FocusSelectedControlTreeNode();
                g_ControlTreeSelectionStatus = ok ? "Focused selected node." : "Could not focus selected node.";
            }
            UI::SameLine();
            if (UI::Button("Clear node focus##controlTree")) {
                _ClearControlTreeNodeFocus();
                g_ControlTreeSelectionStatus = "Cleared node focus.";
            }
            if (UI::Button("Open NOD (selected)")) _OpenNodExplorer(ctx.sel);
            UI::SameLine();
            if (UI::Button("Clear selection##controlTree-actions")) _ClearControlTreeSelection();
        }

        if (g_ControlTreeSelectionStatus.Length > 0) UI::Text(g_ControlTreeSelectionStatus);
    }

}
}
