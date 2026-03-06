namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionExport(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Snapshots and dump/export tools.");

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Snapshot")) {
            UI::TextDisabled("Capture selected ControlTree node details for sharing/logging.");
            g_ControlTreeSnapshotIncludeChildren = UI::Checkbox("Include children in snapshot", g_ControlTreeSnapshotIncludeChildren);
            g_ControlTreeSnapshotMaxDepth = UI::SliderInt("Snapshot max depth", g_ControlTreeSnapshotMaxDepth, 0, 12);
            g_ControlTreeSnapshotPath = UI::InputText("Snapshot file path", g_ControlTreeSnapshotPath);

            _RefreshControlTreeSnapshotPreview(ctx.sel);
            UI::Text("Snapshot bytes: " + g_ControlTreeSnapshotPreview.Length);
            if (_ControlTreeCopyActionText("Snapshot", g_ControlTreeSnapshotPreview, "controlTree-snapshot-copy")) {
                _RefreshControlTreeSnapshotPreview(ctx.sel);
                g_ControlTreeSnapshotStatus = "Copied ControlTree snapshot to clipboard.";
            }
            UI::SameLine();
            if (UI::Button("Save snapshot file")) {
                _RefreshControlTreeSnapshotPreview(ctx.sel);
                string outPath = g_ControlTreeSnapshotPath.Trim();
                if (outPath.Length == 0) outPath = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_snapshot.txt");
                _IO::File::WriteFile(outPath, g_ControlTreeSnapshotPreview, false);
                g_ControlTreeSnapshotStatus = "Saved snapshot to " + outPath;
            }
            UI::SameLine();
            if (UI::Button("Open snapshot folder")) {
                string outPath = g_ControlTreeSnapshotPath.Trim();
                if (outPath.Length == 0) outPath = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_snapshot.txt");
                string folder = Path::GetDirectoryName(outPath);
                if (folder.Length == 0) folder = IO::FromStorageFolder("Exports/Dumps");
                _IO::OpenFolder(folder, true);
            }
            if (g_ControlTreeSnapshotStatus.Length > 0) UI::Text(g_ControlTreeSnapshotStatus);

            float snapH = UI::GetContentRegionAvail().y;
            if (snapH < 140.0f) snapH = 140.0f;
            g_ControlTreeSnapshotPreview = UI::InputTextMultiline("##controlTree-snapshot-preview", g_ControlTreeSnapshotPreview, vec2(0, snapH));
        }

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Dump")) {
            UI::Text("Selected subtree dump");
            S_ControlTreeDumpPath = UI::InputText("Dump file path", S_ControlTreeDumpPath);
            S_ControlTreeDumpDepth = UI::SliderInt("Dump depth", S_ControlTreeDumpDepth, 1, 12);
            if (UI::Button("Dump selected subtree")) {
                string path = S_ControlTreeDumpPath;
                if (path.Length == 0) path = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_dump.txt");
                int maxDepth = S_ControlTreeDumpDepth;
                if (maxDepth < 1) maxDepth = 1;
                if (maxDepth > 32) maxDepth = 32;

                array<string> lines;
                lines.Reserve(256);
                string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
                lines.InsertLast("UiNav ControlTree dump @ " + ts);
                lines.InsertLast("Overlay: " + g_SelectedControlTreeOverlayAtSel);
                string startPath = g_SelectedControlTreePath;
                if (startPath.Length == 0 && g_SelectedControlTreeRootIx >= 0) startPath = "root[" + g_SelectedControlTreeRootIx + "]";
                _DumpControlTreeSubtreeLines(ctx.sel, startPath, 0, maxDepth, lines);
                _FinalizeControlTreeDump(path, lines);
                g_ControlTreeSelectionStatus = g_LastControlTreeDumpStatus;
            }
            UI::SameLine();
            if (UI::Button("Open dump folder##controlTree-selection")) {
                string dumpPath = S_ControlTreeDumpPath;
                if (dumpPath.Length == 0) dumpPath = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_dump.txt");
                string folder = Path::GetDirectoryName(dumpPath);
                if (folder.Length == 0) folder = IO::FromStorageFolder("Exports/Dumps");
                _IO::OpenFolder(folder, true);
            }

            UI::Separator();
            UI::Text("Overlay/start-path dump");
            if (UI::Button("Use selected overlay for overlay dump")) {
                S_ControlTreeDumpOverlay = g_SelectedControlTreeOverlayAtSel;
            }
            _RenderControlTreeDumpControls();
        }

        if (g_ControlTreeSelectionStatus.Length > 0) UI::Text(g_ControlTreeSelectionStatus);
    }

}
}
