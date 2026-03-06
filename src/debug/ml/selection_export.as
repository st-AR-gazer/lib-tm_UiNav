namespace UiNav {
namespace Debug {

    void _RenderMlSelectionExport(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Snapshots, style packs, and dump/export tools.");

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Snapshot")) {
            UI::TextWrapped("Capture selected ML node data, save it, and apply it to another node.");

            S_MlSnapshotIncludeChildren = UI::Checkbox("Include children in snapshot", S_MlSnapshotIncludeChildren);
            S_MlSnapshotApplyChildren = UI::Checkbox("Apply children when pasting", S_MlSnapshotApplyChildren);
            S_MlSnapshotMaxDepth = UI::SliderInt("Snapshot max depth", S_MlSnapshotMaxDepth, 0, 12);
            S_MlSnapshotPath = UI::InputText("Snapshot file path", S_MlSnapshotPath);

            if (_MlActionText("Selected snapshot -> clipboard", "ml-snapshot-copy-selected")) {
                bool ok = UiNav::ML::CopySnapshotToClipboard(ctx.sel, S_MlSnapshotIncludeChildren, S_MlSnapshotMaxDepth);
                g_MlSnapshotStatus = ok ? "Copied snapshot to UiNav clipboard." : "Failed to snapshot selected node.";
            }
            UI::SameLine();
            if (UI::Button("Save selected snapshot")) {
                bool ok = UiNav::ML::SaveSnapshotToFile(ctx.sel, S_MlSnapshotPath, S_MlSnapshotIncludeChildren, S_MlSnapshotMaxDepth);
                g_MlSnapshotStatus = ok ? "Saved selected snapshot." : "Failed to save selected snapshot.";
            }

            if (UI::Button("Save clipboard snapshot")) {
                bool ok = UiNav::ML::SaveClipboardSnapshotToFile(S_MlSnapshotPath);
                g_MlSnapshotStatus = ok ? "Saved clipboard snapshot." : "No clipboard snapshot to save.";
            }
            UI::SameLine();
            if (UI::Button("Load file -> clipboard")) {
                auto loaded = UiNav::ML::LoadSnapshotFromFile(S_MlSnapshotPath);
                bool ok = UiNav::ML::SetClipboardSnapshot(loaded);
                g_MlSnapshotStatus = ok ? "Loaded snapshot file into clipboard." : "Failed to load snapshot file.";
            }

            string clipJson = UiNav::ML::GetClipboardSnapshotJson();
            UI::Text("Clipboard snapshot bytes: " + clipJson.Length);
            if (clipJson.Length > 0) {
                _MlCopyActionText("Clipboard JSON", clipJson, "ml-snapshot-copy-json");
                UI::SameLine();
                string xml = UiNav::ML::ClipboardSnapshotToXml(true);
                if (_MlCopyActionText("Clipboard XML snippet", xml, "ml-snapshot-copy-xml")) {
                    g_MlSnapshotStatus = xml.Length > 0 ? "Copied XML snippet." : "No XML snippet available.";
                }
            }

            UI::Separator();
            if (UI::Button("Apply clipboard -> selected")) {
                bool ok = UiNav::ML::ApplyClipboardSnapshot(ctx.sel, S_MlSnapshotApplyChildren);
                g_MlSnapshotStatus = ok ? "Applied clipboard snapshot to selected node." : "Failed to apply clipboard snapshot.";
            }

            g_MlSnapshotApplySelector = UI::InputText("Apply selector (current layer root)", g_MlSnapshotApplySelector);
            if (UI::Button("Apply clipboard -> selector")) {
                CGameManialinkFrame@ root = _GetMlRootByLayerIx(g_SelectedMlLayerIx, g_SelectedMlAppKind);

                if (root is null) {
                    g_MlSnapshotStatus = "Apply failed: selected layer root is unavailable.";
                } else {
                    string selSpec = g_MlSnapshotApplySelector.Trim();
                    if (selSpec.Length == 0) selSpec = g_SelectedMlPath;
                    auto dst = UiNav::ML::ResolveSelector(selSpec, root);
                    if (dst is null) {
                        g_MlSnapshotStatus = "Apply failed: selector did not resolve.";
                    } else {
                        bool ok = UiNav::ML::ApplyClipboardSnapshot(dst, S_MlSnapshotApplyChildren);
                        g_MlSnapshotStatus = ok ? "Applied clipboard snapshot to selector target." : "Apply failed on selector target.";
                    }
                }
            }

            if (g_MlSnapshotStatus.Length > 0) UI::Text(g_MlSnapshotStatus);
        }

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Style Pack")) {
            UI::TextWrapped("Capture style snapshots from multiple ManiaLink controls, then export or apply the full pack.");

            S_MlStylePackIncludeChildren = UI::Checkbox("Capture children", S_MlStylePackIncludeChildren);
            UI::SameLine();
            S_MlStylePackIncludeTextValues = UI::Checkbox("Include text values", S_MlStylePackIncludeTextValues);
            S_MlStylePackMaxDepth = UI::SliderInt("Capture max depth", S_MlStylePackMaxDepth, 0, 12);
            S_MlStylePackPath = UI::InputText("Style pack file path", S_MlStylePackPath);

            if (UI::Button("Add selected style")) {
                _MlStylePackAddSelected(ctx.sel);
            }
            UI::SameLine();
            if (UI::Button("Remove last##ml-style-pack")) {
                if (g_MlStylePackEntries.Length > 0) {
                    g_MlStylePackEntries.RemoveLast();
                    g_MlStylePackStatus = "Removed last style entry.";
                } else {
                    g_MlStylePackStatus = "Style pack is already empty.";
                }
            }
            UI::SameLine();
            if (UI::Button("Clear pack##ml-style-pack")) {
                g_MlStylePackEntries.Resize(0);
                g_MlStylePackStatus = "Cleared style pack.";
            }

            UI::Separator();
            if (_MlActionText("Pack JSON", "ml-style-pack-copy-json")) {
                bool ok = _MlStylePackCopyJsonToClipboard();
                g_MlStylePackStatus = ok ? "Copied style pack JSON." : "Failed to copy style pack JSON.";
            }
            UI::SameLine();
            if (UI::Button("Save pack file")) {
                bool ok = _MlStylePackSaveToFile(S_MlStylePackPath);
                g_MlStylePackStatus = ok ? "Saved style pack file." : "Failed to save style pack file.";
            }
            UI::SameLine();
            if (UI::Button("Load pack file")) {
                bool ok = _MlStylePackLoadFromFile(S_MlStylePackPath);
                g_MlStylePackStatus = ok
                    ? ("Loaded style pack entries: " + g_MlStylePackEntries.Length + ".")
                    : "Failed to load style pack file.";
            }

            UI::Separator();
            S_MlStylePackApplyChildren = UI::Checkbox("Apply children when applying pack", S_MlStylePackApplyChildren);
            if (UI::Button("Apply pack -> selected layer")) {
                int attempted = 0;
                int applied = _MlStylePackApplyToSelectedLayer(S_MlStylePackApplyChildren, attempted);
                if (attempted < 0) {
                    g_MlStylePackStatus = "Apply failed: selected layer root is unavailable.";
                } else if (attempted == 0) {
                    g_MlStylePackStatus = "No style entries to apply.";
                } else {
                    g_MlStylePackStatus = "Applied " + applied + " / " + attempted + " style entries.";
                }
            }

            UI::Text("Entries: " + g_MlStylePackEntries.Length);
            if (g_MlStylePackStatus.Length > 0) UI::Text(g_MlStylePackStatus);

            int removeIx = -1;
            float stylePackListH = UI::GetContentRegionAvail().y;
            if (stylePackListH < 120.0f) stylePackListH = 120.0f;
            UI::BeginChild("##ml-style-pack-list", vec2(0, stylePackListH), true);
            for (uint i = 0; i < g_MlStylePackEntries.Length; ++i) {
                auto e = g_MlStylePackEntries[i];
                if (e is null) continue;

                UI::PushID("ml-style-pack-entry-" + i);
                if (UI::Button("X")) removeIx = int(i);
                UI::SameLine();
                UI::Text("[" + i + "] " + e.name);

                if (e.selector.Length > 0) {
                    UI::Text("\\$999selector:\\$z " + e.selector);
                } else if (e.indexPath.Length > 0) {
                    UI::Text("\\$999index:\\$z " + e.indexPath);
                }
                UI::Text("\\$999layer:\\$z " + e.layerIx + "  \\$999app:\\$z " + _MlAppNameByKind(e.appKind));

                if (_MlCopyActionText("Selector", (e.selector.Length > 0 ? e.selector : e.indexPath), "ml-style-pack-entry-selector-" + i)) {
                    if (e.selector.Length > 0) {
                        g_MlStylePackStatus = "Copied selector.";
                    } else if (e.indexPath.Length > 0) {
                        g_MlStylePackStatus = "Copied index path.";
                    } else {
                        g_MlStylePackStatus = "Entry has no selector/index path.";
                    }
                }
                UI::SameLine();
                if (_MlCopyActionText("Snapshot JSON", e.snapshotJson, "ml-style-pack-entry-snap-" + i)) {
                    g_MlStylePackStatus = "Copied entry snapshot JSON.";
                }
                UI::Separator();
                UI::PopID();
            }
            UI::EndChild();

            if (removeIx >= 0 && removeIx < int(g_MlStylePackEntries.Length)) {
                g_MlStylePackEntries.RemoveAt(uint(removeIx));
                g_MlStylePackStatus = "Removed style entry #" + removeIx + ".";
            }
        }

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Dump")) {
            UI::Text("Dump selected layer subtree");
            S_MlDumpPath = UI::InputText("Dump file path", S_MlDumpPath);
            S_MlDumpDepth = UI::SliderInt("Dump depth", S_MlDumpDepth, 1, 12);
            S_MlDumpOnlyOpenPaths = UI::Checkbox("Only dump open paths", S_MlDumpOnlyOpenPaths);
            if (UI::Button("Dump layer subtree")) {
                CGameManialinkControl@ root = ctx.sel;
                auto layerRoot = _GetMlRootByLayerIx(g_SelectedMlLayerIx, g_SelectedMlAppKind);
                if (layerRoot !is null) @root = layerRoot;
                string appPrefix = _MlAppPrefixByKind(g_SelectedMlAppKind);
                string uiPath = (g_SelectedMlLayerIx >= 0) ? (appPrefix + "/L" + g_SelectedMlLayerIx) : "";
                DumpMlSubtreeToFile(root, "LAYER", S_MlDumpOnlyOpenPaths, uiPath);
            }
            UI::SameLine();
            if (UI::Button("Open dump folder")) {
                string dumpPath = S_MlDumpPath;
                if (dumpPath.Length == 0) dumpPath = IO::FromStorageFolder("Exports/Dumps/uinav_ml_dump.txt");
                string folder = Path::GetDirectoryName(dumpPath);
                if (folder.Length == 0) folder = IO::FromStorageFolder("Exports/Dumps");
                _IO::OpenFolder(folder, true);
            }
            if (g_LastMlDumpStatus.Length > 0) UI::Text(g_LastMlDumpStatus);

            UI::Separator();
            UI::Text("Dump selected layer ManialinkPage XML (styling)");
            if (UI::Button("Dump layer page XML")) {
                CGameUILayer@ layer = _GetMlLayerByIx(g_SelectedMlAppKind, g_SelectedMlLayerIx);
                string appPrefix = _MlAppPrefixByKind(g_SelectedMlAppKind);
                DumpMlLayerPageToFile(layer, g_SelectedMlLayerIx, appPrefix);
            }
            UI::SameLine();
            if (UI::Button("Dump ALL layer pages (slow)")) {
                string appPrefix = _MlAppPrefixByKind(g_SelectedMlAppKind);
                DumpAllMlLayerPagesToFolder(g_SelectedMlAppKind, appPrefix);
            }
            UI::SameLine();
            if (UI::Button("Open page exports##ml-page-dump")) {
                _IO::OpenFolder(IO::FromStorageFolder("Exports/ManiaLinks/Pages"), true);
            }
            if (g_LastMlPageDumpStatus.Length > 0) UI::Text(g_LastMlPageDumpStatus);
        }
    }

}
}
