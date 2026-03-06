namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionOverview(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Identity and live preview of the selected control.");
        _ControlTreeInfoLine("Type", NodeTypeName(ctx.sel), false, "overview-type");
        _ControlTreeInfoLine("IdName", ctx.selIdName, true, "overview-idname");
        _ControlTreeInfoLine("StackText", ctx.selStackText, false, "overview-stacktext");
        _ControlTreeInfoLine("Text", ctx.text, false, "overview-text");
        _ControlTreeInfoLine("Overlay", "" + g_SelectedControlTreeOverlayAtSel, false, "overview-overlay");
        _ControlTreeInfoLine("Root", "" + g_SelectedControlTreeRootIx, false, "overview-root");
        _ControlTreeInfoLine("Visible", ctx.isVisible ? "true" : "false", false, "overview-visible");
        _ControlTreeInfoLine("Children", "" + ctx.childCount, false, "overview-children");

        string notesTooltip;
        int activeCount = 0;
        if (_ControlTreeGetActiveNotesTooltip(g_SelectedControlTreeOverlayAtSel, g_SelectedControlTreeRootIx, ctx.relPath, ctx.sel, notesTooltip, activeCount)) {
            UI::Separator();
            UI::Text("Active notes: " + activeCount);
            UI::PushTextWrapPos(0.0f);
            UI::TextWrapped(notesTooltip);
            UI::PopTextWrapPos();
        }
    }

}
}
