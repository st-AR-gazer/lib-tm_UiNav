namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionCode(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Generate a UiNav target snippet for this selected control.");
        UI::Text("Target snippet (ControlTree UI)");
        string snippet = _BuildControlTreeTargetSnippet(ctx.selIdName);
        string snippetKey = g_SelectedControlTreePath + "|" + g_SelectedControlTreeOverlayAtSel + "|" + ctx.selIdName;
        if (snippetKey != g_ControlTreeSnippetKey) {
            g_ControlTreeSnippetKey = snippetKey;
            g_ControlTreeSnippetEdit = snippet;
        }
        _ControlTreeCopyActionText("Snippet", g_ControlTreeSnippetEdit, "controlTree-snippet-copy");
        UI::SameLine();
        if (UI::Button("Reset to generated##controlTree")) g_ControlTreeSnippetEdit = snippet;
        float snippetH = UI::GetContentRegionAvail().y;
        if (snippetH < 220.0f) snippetH = 220.0f;
        g_ControlTreeSnippetEdit = UI::InputTextMultiline("##controlTree-snippet-edit", g_ControlTreeSnippetEdit, vec2(0, snippetH));
    }

}
}
