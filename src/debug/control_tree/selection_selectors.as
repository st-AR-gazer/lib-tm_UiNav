namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionSelectors(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Copy selectors and paths used for searching or building targets.");
        _ControlTreeCopyLine("selector", ctx.selector, "controlTree-target-selector");
        _ControlTreeCopyLine("descendant id selector", ctx.idQuery, "controlTree-target-id-selector");
        _ControlTreeCopyLine("index path", ctx.indexPath, "controlTree-target-index");
        _ControlTreeCopyLine("mixed selector", ctx.mixedPath, "controlTree-target-mixed");
        _ControlTreeCopyLine("relative path", ctx.relPath, "controlTree-target-rel");
        _ControlTreeCopyLine("display path", ctx.dispPath, "controlTree-target-disp");
        _ControlTreeCopyLine("UI path key", ctx.uiPath, "controlTree-target-ui");
        _ControlTreeCopyLine("IdName", ctx.selIdName, "controlTree-target-id");
        _ControlTreeCopyLine("search query", ctx.idQuery, "controlTree-target-search");

        string reqDeclLine = "UiNav::ControlTreeReq@ req = UiNav::ControlTreeReq();";
        string reqOverlayLine = "req.overlay = " + g_SelectedControlTreeOverlayAtSel + ";";
        string reqRootLine = g_SelectedControlTreeRootIx >= 0 ? ("req.rootIx = " + g_SelectedControlTreeRootIx + ";") : "";
        string specDeclLine = "UiNav::ControlTreeSpec@ controlTree = UiNav::ControlTreeSpec();";
        string specReqLine = "@controlTree.req = req;";
        string targetPath = ctx.selector;
        string safePath = _EscapeCodeString(targetPath);
        string specPathLine = "controlTree.selector = \"" + safePath + "\";";
        string specPayload = reqDeclLine + "\n" + reqOverlayLine + "\n\n" + specDeclLine + "\n" + specReqLine + "\n" + specPathLine;
        if (reqRootLine.Length > 0) specPayload = reqDeclLine + "\n" + reqOverlayLine + "\n" + reqRootLine + "\n\n" + specDeclLine + "\n" + specReqLine + "\n" + specPathLine;
        _ControlTreeCopyActionText("ControlTreeSpec lines", specPayload, "controlTree-spec-lines-copy");
        UI::BeginChild("##controlTree-spec-lines", vec2(0, reqRootLine.Length > 0 ? 126.0f : 108.0f), true);
        UI::Text(reqDeclLine);
        UI::Text(reqOverlayLine);
        if (reqRootLine.Length > 0) UI::Text(reqRootLine);
        UI::Text("");
        UI::Text(specDeclLine);
        UI::Text(specReqLine);
        UI::Text(specPathLine);
        UI::EndChild();

        if (ctx.dispPath.Length > 0) {
            UI::Separator();
            UI::Text("Full display path");
            UI::BeginChild("##controlTree-full-display-path", vec2(0, 66), true);
            UI::TextWrapped(ctx.dispPath);
            UI::EndChild();
        }
    }

}
}
