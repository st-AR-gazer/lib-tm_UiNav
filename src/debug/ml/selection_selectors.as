namespace UiNav {
namespace Debug {

    void _RenderMlSelectionSelectors(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Copy selectors and index paths in different formats.");
        _MlSelectionCopyLine("ID selector", ctx.idSel, "ml-target-id");
        _MlSelectionCopyLine("class selector", ctx.classSel, "ml-target-class");
        _MlSelectionCopyLine("index path", g_SelectedMlPath, "ml-target-index");
        _MlSelectionCopyLine("root id", ctx.rootId, "ml-target-rootid");
        _MlSelectionCopyLine("id list", ctx.idList, "ml-target-idlist");
        _MlSelectionCopyLine("id chain", ctx.idChain, "ml-target-idchain");
        _MlSelectionCopyLine("mixed chain", ctx.mixedChain, "ml-target-mixed");
        _MlSelectionCopyLine("selector", ctx.mlSelector, "ml-target-selector");
        string controlTreePathDisplay = ctx.controlTreeDisplay;
        if (controlTreePathDisplay.Length == 0 && g_MlControlTreePathStatus.Length > 0) {
            controlTreePathDisplay = g_MlControlTreePathStatus;
        }
        _MlSelectionCopyLine("controlTree selector", controlTreePathDisplay, "ml-target-controltree");

        if (ctx.controlTreeDisplay.Length == 0) {
            if (_MlActionText("Resolve ControlTree selector", "ml-target-controltree-resolve")) {
                _MlResolveControlTreePathNow(ctx.sel, ctx.controlTree);
                ctx.controlTreeDisplay = g_MlControlTreePathCached;
            }
            if (g_MlControlTreePathStatus.Length > 0) UI::TextDisabled(g_MlControlTreePathStatus);
        }

        if (ctx.fullSel.Length > 0) {
            UI::Separator();
            _MlCopyActionText("Full selector path", ctx.fullSel, "ml-target-fullsel");
            UI::BeginChild("##ml-fullsel", vec2(0, 120), true);
            UI::TextWrapped(ctx.fullSel);
            UI::EndChild();
        }
    }

}
}
