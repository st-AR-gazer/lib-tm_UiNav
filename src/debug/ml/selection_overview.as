namespace UiNav {
namespace Debug {

    void _RenderMlSelectionOverview(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Identity, current value preview, and quick metadata.");
        _MlSelectionInfoLine("Layer", "" + g_SelectedMlLayerIx, false, "overview-layer");
        _MlSelectionInfoLine("App", _MlAppNameByKind(g_SelectedMlAppKind), false, "overview-app");
        _MlSelectionInfoLine("Type", UiNav::ML::TypeName(ctx.sel), false, "overview-type");
        _MlSelectionInfoLine("ControlId", ctx.id, true, "overview-controlid");
        _MlSelectionInfoLine("Text", ctx.text, false, "overview-text");
        _MlSelectionInfoLine("Index path", g_SelectedMlPath, false, "overview-index-path");
        _MlSelectionInfoLine("Class list", ctx.classList, false, "overview-class-list");
        _MlSelectionInfoLine("Class selector", ctx.classSel, false, "overview-class-selector");
        _MlSelectionInfoLine("Selector", ctx.mlSelector, true, "overview-selector");

        string ctPath = ctx.controlTreeDisplay;
        if (ctPath.Length == 0) {
            if (g_MlControlTreePathStatus.Length > 0) ctPath = g_MlControlTreePathStatus;
            else ctPath = "No control tree resolvable.";
        }
        bool ctPathIsResolved = ctx.controlTreeDisplay.Length > 0;
        _MlSelectionInfoLine("ControlTree path", ctPath, ctPathIsResolved, "overview-controltree-path");

        string tagKey = UiNav::LayerTags::KeyForLayer(ctx.layer, g_SelectedMlLayerIx);
        if (tagKey.Length > 0) {
            string tagVal = UiNav::LayerTags::GetTag(tagKey);
            string prevTag = tagVal;
            tagVal = UI::InputText("Warning note", tagVal);
            if (tagVal != prevTag) UiNav::LayerTags::SetTag(tagKey, tagVal);
            UI::Text("Tag key: " + tagKey);
        }
    }

}
}
