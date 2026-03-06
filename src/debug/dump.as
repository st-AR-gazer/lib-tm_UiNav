namespace UiNav {
namespace Debug {
    string _ShortStr(const string &in s, uint maxLen = 140) {
        string r = s;
        r = r.Replace("\r", "\\r");
        r = r.Replace("\n", "\\n");
        r = r.Replace("\t", "\\t");
        r = r.Replace("\"", "'");
        int maxLenInt = int(maxLen);
        if (int(r.Length) > maxLenInt) r = r.SubStr(0, maxLenInt) + "...";
        return r;
    }

    void _RenderMlDumpControls() {
        UI::Text("Dump ML UILayers to file");
        S_MlDumpPath = UI::InputText("Dump file path", S_MlDumpPath);
        S_MlDumpDepth = UI::SliderInt("Dump depth", S_MlDumpDepth, 1, 12);
        S_MlDumpOnlyOpenPaths = UI::Checkbox("Only dump open paths", S_MlDumpOnlyOpenPaths);
        S_MlDumpLayerIndex = UI::InputInt("Dump layer index (-1 = all)", S_MlDumpLayerIndex);
        UI::Text("Dump selector chains (one per line, use '/' for hierarchy)");
        S_MlDumpSelectorChains = UI::InputTextMultiline("##ml-dump-chains", S_MlDumpSelectorChains, vec2(0, 80));
        S_MlDumpSelectorChildrenOnly = UI::Checkbox("Dump selector children only", S_MlDumpSelectorChildrenOnly);
        if (UI::Button("Dump ML UILayers to file")) {
            DumpMlLayersToFile();
        }
        if (g_LastMlDumpStatus.Length > 0) UI::Text(g_LastMlDumpStatus);
    }

    void _RenderControlTreeDumpControls() {
        UI::Text("Dump ControlTree overlay to file");
        S_ControlTreeDumpPath = UI::InputText("ControlTree dump file path", S_ControlTreeDumpPath);
        int overlay = int(S_ControlTreeDumpOverlay);
        overlay = UI::InputInt("ControlTree overlay", overlay);
        if (overlay < 0) overlay = 0;
        S_ControlTreeDumpOverlay = uint(overlay);
        S_ControlTreeDumpDepth = UI::SliderInt("ControlTree dump depth", S_ControlTreeDumpDepth, 1, 12);
        S_ControlTreeDumpStartPath = UI::InputText("ControlTree start path (optional)", S_ControlTreeDumpStartPath);
        if (UI::Button("Dump ControlTree overlay to file")) {
            DumpControlTreeOverlayToFile();
        }
        if (g_LastControlTreeDumpStatus.Length > 0) UI::Text(g_LastControlTreeDumpStatus);
    }

    void DumpMlLayersToFile() {
        auto app = UiNav::Layers::GetManiaApp();
        if (app is null) {
            g_LastMlDumpStatus = "ML dump failed: ManiaApp is null";
            return;
        }
        _DumpMlLayersToFile(app);
    }

    void DumpMlSubtreeToFile(CGameManialinkControl@ root, const string &in label) {
        DumpMlSubtreeToFile(root, label, false, "");
    }

    void DumpMlSubtreeToFile(CGameManialinkControl@ root, const string &in label, bool onlyOpenPaths, const string &in uiPath) {
        if (root is null) {
            g_LastMlDumpStatus = "ML dump failed: selected node is null";
            return;
        }

        string path = S_MlDumpPath;
        if (path.Length == 0) {
            path = IO::FromStorageFolder("Exports/Dumps/uinav_ml_dump.txt");
        }

        int maxDepth = S_MlDumpDepth;
        if (maxDepth < 1) maxDepth = 1;
        if (maxDepth > 32) maxDepth = 32;

        array<string> lines;
        lines.Reserve(512);
        string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
        lines.InsertLast("UiNav ML dump @ " + ts);
        lines.InsertLast("Subtree: " + label + " type=" + UiNav::ML::TypeName(root) + " id=" + root.ControlId);
        _DumpMlSubtreeLines(root, label, 0, maxDepth, lines, onlyOpenPaths, uiPath);

        string content;
        for (uint i = 0; i < lines.Length; ++i) {
            content += lines[i] + "\n";
        }

        _IO::File::WriteFile(path, content, false);
        g_LastMlDumpPath = path;
        g_LastMlDumpLines = lines.Length;
        g_LastMlDumpStatus = "Wrote " + g_LastMlDumpLines + " lines to " + path;
    }

    void DumpControlTreeOverlayToFile() {
        _DumpControlTreeToFile();
    }

    void DumpMlLayerPageToFile(CGameUILayer@ layer, int layerIx, const string &in appPrefix) {
        g_LastMlPageDumpStatus = "";
        g_LastMlPageDumpPath = "";
        g_LastMlPageDumpChars = 0;

        if (layer is null) {
            g_LastMlPageDumpStatus = "ML page dump failed: selected layer is null";
            return;
        }

        string page = layer.ManialinkPageUtf8;
        if (page.Length == 0) page = "" + layer.ManialinkPage;
        if (page.Length == 0) {
            g_LastMlPageDumpStatus = "ML page dump failed: empty ManialinkPage";
            return;
        }

        string ts = Time::FormatString("%Y%m%d_%H%M%S");
        string path = IO::FromStorageFolder("Exports/ManiaLinks/Pages/uinav_ml_page_" + appPrefix + "_L" + layerIx + "_" + ts + ".xml");

        _IO::File::WriteFile(path, page, false);
        g_LastMlPageDumpPath = path;
        g_LastMlPageDumpChars = page.Length;
        g_LastMlPageDumpStatus = "Wrote " + g_LastMlPageDumpChars + " chars to " + path;
    }

    void DumpAllMlLayerPagesToFolder(int appKind, const string &in appPrefix) {
        g_LastMlPageDumpStatus = "";
        g_LastMlPageDumpPath = "";
        g_LastMlPageDumpChars = 0;

        uint layerCount = _GetMlLayerCount(appKind);
        if (layerCount == 0) {
            g_LastMlPageDumpStatus = "ML pages dump failed: no UILayers available";
            return;
        }

        string ts = Time::FormatString("%Y%m%d_%H%M%S");
        string folder = IO::FromStorageFolder("Exports/ManiaLinks/Pages/uinav_ml_pages_" + appPrefix + "_" + ts);
        if (!IO::FolderExists(folder)) IO::CreateFolder(folder, true);

        uint written = 0;
        uint totalChars = 0;

        for (uint i = 0; i < layerCount; ++i) {
            auto layer = _GetMlLayerByIx(appKind, int(i));
            if (layer is null) continue;

            string page = layer.ManialinkPageUtf8;
            if (page.Length == 0) page = "" + layer.ManialinkPage;
            if (page.Length == 0) continue;

            string layerName = _ExtractMlNameFromLayer(layer);
            string safeName = (layerName.Length == 0) ? "" : ("_" + Path::SanitizeFileName(layerName));
            string fileName = "L" + i + safeName + ".xml";
            string path = Path::Join(folder, fileName);

            _IO::File::WriteFile(path, page, false);
            written++;
            totalChars += page.Length;
        }

        g_LastMlPageDumpPath = folder;
        g_LastMlPageDumpChars = totalChars;
        g_LastMlPageDumpStatus = "Wrote " + written + " layer pages (" + totalChars + " chars) to " + folder;
    }

    string GetLastMlDumpStatus() { return g_LastMlDumpStatus; }
    string GetLastMlDumpPath() { return g_LastMlDumpPath; }
    uint GetLastMlDumpLines() { return g_LastMlDumpLines; }

    string GetLastMlPageDumpStatus() { return g_LastMlPageDumpStatus; }
    string GetLastMlPageDumpPath() { return g_LastMlPageDumpPath; }
    uint GetLastMlPageDumpChars() { return g_LastMlPageDumpChars; }

    string GetLastControlTreeDumpStatus() { return g_LastControlTreeDumpStatus; }
    string GetLastControlTreeDumpPath() { return g_LastControlTreeDumpPath; }
    uint GetLastControlTreeDumpLines() { return g_LastControlTreeDumpLines; }

    void _DumpMlLayersToFile(CGameManiaApp@ maniaApp) {
        if (maniaApp is null) {
            g_LastMlDumpStatus = "ML dump failed: ManiaApp is null";
            return;
        }

        string path = S_MlDumpPath;
        if (path.Length == 0) {
            path = IO::FromStorageFolder("Exports/Dumps/uinav_ml_dump.txt");
        }

        array<string> lines;
        lines.Reserve(2048);

        string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
        lines.InsertLast("UiNav ML dump @ " + ts);

        auto layers = maniaApp.UILayers;
        lines.InsertLast("UILayers: " + layers.Length);

        string appPrefix = (maniaApp is UiNav::Layers::GetManiaAppMenu()) ? "M" : "P";

        int maxDepth = S_MlDumpDepth;
        if (maxDepth < 1) maxDepth = 1;
        if (maxDepth > 32) maxDepth = 32;

        int dumpIx = S_MlDumpLayerIndex;
        if (dumpIx < -1) dumpIx = -1;
        if (dumpIx >= int(layers.Length)) dumpIx = -1;
        if (dumpIx >= 0) lines.InsertLast("Dumping only layer index: " + dumpIx);

        uint startIx = 0;
        uint endIx = layers.Length;
        if (dumpIx >= 0) {
            startIx = uint(dumpIx);
            endIx = startIx + 1;
        }

        for (uint i = startIx; i < endIx; ++i) {
            auto layer = layers[i];
            if (layer is null) {
                lines.InsertLast("Layer[" + i + "]: <null>");
                continue;
            }

            bool hasLocal = layer.LocalPage !is null;
            auto root = hasLocal ? layer.LocalPage.MainFrame : null;
            string rootId = (root !is null) ? root.ControlId : "<none>";

            string header =
                "Layer[" + i + "]"
              + " vis=" + (layer.IsVisible ? "true" : "false")
              + " local=" + (hasLocal ? "true" : "false")
              + " rootId=" + rootId;
            lines.InsertLast(header);

            if (root !is null) {
                string layerUiPath = appPrefix + "/L" + i;
                string chainSpec = S_MlDumpSelectorChains;
                if (chainSpec.Trim().Length > 0) {
                    auto chains = _SplitLines(chainSpec);
                    for (uint c = 0; c < chains.Length; ++c) {
                        string chain = chains[c].Trim();
                        if (chain.Length == 0) continue;
                        lines.InsertLast("  chain: " + chain);

                        auto steps = _SplitChain(chain);
                        CGameManialinkControl@ cur = root;
                        bool ok = true;
                        for (uint s = 0; s < steps.Length; ++s) {
                            string step = steps[s].Trim();
                            if (step.Length == 0) continue;
                            auto next = UiNav::ML::ResolveSelector(step, cur);
                            if (next is null) {
                                lines.InsertLast("    step \"" + step + "\" not found");
                                ok = false;
                                break;
                            }
                            lines.InsertLast("    step \"" + step + "\" -> " + UiNav::ML::TypeName(next) + " #" + next.ControlId);
                            @cur = next;
                        }
                        if (!ok || cur is null) continue;

                        if (S_MlDumpSelectorChildrenOnly) {
                            auto f = cast<CGameManialinkFrame@>(cur);
                            if (f is null) {
                                _DumpMlSubtreeLines(cur, "SEL", 0, maxDepth, lines, false, "");
                            } else {
                                for (uint j = 0; j < f.Controls.Length; ++j) {
                                    auto ch = f.Controls[j];
                                    if (ch is null) continue;
                                    _DumpMlSubtreeLines(ch, "SEL/" + j, 0, maxDepth, lines, false, "");
                                }
                            }
                        } else {
                            _DumpMlSubtreeLines(cur, "SEL", 0, maxDepth, lines, false, "");
                        }
                    }
                } else {
                    _DumpMlSubtreeLines(root, "MLRoot", 0, maxDepth, lines, S_MlDumpOnlyOpenPaths, layerUiPath);
                }
            }
        }

        string content;
        for (uint i = 0; i < lines.Length; ++i) {
            content += lines[i] + "\n";
        }

        _IO::File::WriteFile(path, content, false);
        g_LastMlDumpPath = path;
        g_LastMlDumpLines = lines.Length;
        g_LastMlDumpStatus = "Wrote " + g_LastMlDumpLines + " lines to " + path;
    }

    void _DumpMlSubtreeLines(CGameManialinkControl@ n, const string &in path, int depth, int maxDepth, array<string>@ lines,
                             bool onlyOpenPaths, const string &in uiPath) {
        if (n is null || depth > maxDepth || lines is null) return;

        string id = n.ControlId;
        string type = UiNav::ML::TypeName(n);
        string text = _ShortStr(UiNav::CleanUiFormatting(UiNav::ML::ReadText(n)), 120);

        vec2 absPos = n.AbsolutePosition_V3;
        vec2 relPos = n.RelativePosition_V3;
        vec2 size = n.Size;
        float z = n.ZIndex;

        string classList;
        string firstClassSel = _MlFirstClassSelector(n, classList);

        auto controlTree = n.Control;
        bool controlTreeHiddenExt = false;
        bool controlTreeVis = false;
        string controlTreeType = "";
        if (controlTree !is null) {
            controlTreeHiddenExt = controlTree.IsHiddenExternal;
            controlTreeVis = controlTree.IsVisible;
            controlTreeType = UiNav::NodeTypeName(controlTree);
        }

        string line = path + " : " + type + " #" + id
            + " vis=" + (n.Visible ? "true" : "false")
            + " abs=(" + _Vec2Str(absPos) + ")"
            + " rel=(" + _Vec2Str(relPos) + ")"
            + " size=(" + _Vec2Str(size) + ")"
            + " z=" + z;
        if (firstClassSel.Length > 0) line += " cls=" + firstClassSel.SubStr(1);
        if (classList.Length > 0 && classList.Length <= 120) line += " classes=[" + classList + "]";
        if (controlTreeType.Length > 0) line += " controlTree=" + controlTreeType + " controlTreeVis=" + (controlTreeVis ? "true" : "false") + " controlTreeHiddenExt=" + (controlTreeHiddenExt ? "true" : "false");
        if (text.Length > 0) line += " text=\"" + text + "\"";

        auto lbl = cast<CGameManialinkLabel@>(n);
        if (lbl !is null && lbl.Value.Length > 0) {
            line += " val=\"" + _ShortStr(lbl.Value, 140) + "\"";
        }
        auto entry = cast<CGameManialinkEntry@>(n);
        if (entry !is null && entry.Value.Length > 0) {
            line += " val=\"" + _ShortStr(entry.Value, 140) + "\"";
        }
        lines.InsertLast(line);

        if (depth >= maxDepth) return;
        if (onlyOpenPaths && uiPath.Length > 0 && !_IsMlTreeOpen(uiPath)) return;

        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null) return;

        for (uint i = 0; i < f.Controls.Length; ++i) {
            auto ch = f.Controls[i];
            if (ch is null) continue;
            _DumpMlSubtreeLines(ch, path + "/" + i, depth + 1, maxDepth, lines, onlyOpenPaths, uiPath + "/" + i);
        }
    }

    void _DumpControlTreeToFile() {
        string path = S_ControlTreeDumpPath;
        if (path.Length == 0) {
            path = IO::FromStorageFolder("Exports/Dumps/uinav_control_tree_dump.txt");
        }

        array<string> lines;
        lines.Reserve(2048);

        string ts = Time::FormatString("%Y-%m-%d %H:%M:%S");
        lines.InsertLast("UiNav ControlTree dump @ " + ts);
        lines.InsertLast("Overlay: " + S_ControlTreeDumpOverlay);

        int maxDepth = S_ControlTreeDumpDepth;
        if (maxDepth < 1) maxDepth = 1;
        if (maxDepth > 32) maxDepth = 32;

        string startPath = S_ControlTreeDumpStartPath.Trim();
        if (startPath.Length > 0) {
            CControlBase@ start = ResolvePathAnyRoot(startPath, S_ControlTreeDumpOverlay, 64);
            if (start is null) {
                lines.InsertLast("Start path not found: " + startPath);
                _FinalizeControlTreeDump(path, lines);
                return;
            }
            _DumpControlTreeSubtreeLines(start, startPath, 0, maxDepth, lines);
            _FinalizeControlTreeDump(path, lines);
            return;
        }

        CScene2d@ scene;
        if (!_GetScene2d(S_ControlTreeDumpOverlay, scene)) {
            lines.InsertLast("No scene for overlay " + S_ControlTreeDumpOverlay);
            _FinalizeControlTreeDump(path, lines);
            return;
        }

        for (uint i = 0; i < scene.Mobils.Length; ++i) {
            CControlFrame@ root = _RootFromMobil(scene, i);
            if (root is null) continue;
            _DumpControlTreeSubtreeLines(root, "root[" + i + "]", 0, maxDepth, lines);
        }

        _FinalizeControlTreeDump(path, lines);
    }

    void _FinalizeControlTreeDump(const string &in path, array<string>@ lines) {
        string content;
        for (uint i = 0; i < lines.Length; ++i) {
            content += lines[i] + "\n";
        }

        _IO::File::WriteFile(path, content, false);
        g_LastControlTreeDumpPath = path;
        g_LastControlTreeDumpLines = lines.Length;
        g_LastControlTreeDumpStatus = "Wrote " + g_LastControlTreeDumpLines + " lines to " + path;
    }

    void _DumpControlTreeSubtreeLines(CControlBase@ n, const string &in path, int depth, int maxDepth, array<string>@ lines) {
        if (n is null || depth > maxDepth || lines is null) return;

        string t = ReadText(n);
        string clean = CleanUiFormatting(t);
        if (clean.Length > 120) clean = clean.SubStr(0, 120) + "...";

        string line = path + " : " + NodeTypeName(n)
            + " vis=" + (IsEffectivelyVisible(n) ? "true" : "false");
        if (clean.Length > 0) line += " text=\"" + clean + "\"";
        lines.InsertLast(line);

        if (depth >= maxDepth) return;

        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(n, i);
            if (ch is null) continue;
            _DumpControlTreeSubtreeLines(ch, path + "/" + i, depth + 1, maxDepth, lines);
        }
    }

}
}
