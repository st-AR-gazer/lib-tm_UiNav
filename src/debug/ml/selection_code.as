namespace UiNav {
namespace Debug {

    void _RenderMlSelectionCode(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Generate a UiNav target snippet for this selection.");
        UI::Text("Target snippet (ManiaLink UI)");

        string layerName = _ExtractMlNameFromLayer(ctx.layer);
        string snippet = _BuildMlTargetSnippet(ctx.rootId, ctx.idChain, ctx.mixedChain, g_SelectedMlLayerIx, layerName);
        string snippetKey = "" + g_SelectedMlLayerIx + "|" + ctx.rootId + "|" + ctx.idChain + "|" + ctx.mixedChain;
        if (snippetKey != g_MlSnippetKey) {
            g_MlSnippetKey = snippetKey;
            g_MlSnippetEdit = snippet;
        }

        float snippetH = UI::GetContentRegionAvail().y;
        if (snippetH < 360.0f) snippetH = 360.0f;
        g_MlSnippetEdit = UI::InputTextMultiline("##ml-snippet-edit", g_MlSnippetEdit, vec2(0, snippetH));
    }

}
}
