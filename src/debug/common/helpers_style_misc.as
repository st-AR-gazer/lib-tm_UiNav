namespace UiNav {
namespace Debug {

    void _BuildMlChains(string &out rootId, string &out idChain, string &out mixedChain, string &out idList) {
        rootId = "";
        idChain = "";
        mixedChain = "";
        idList = "";

        if (g_SelectedMlLayerIx < 0 || g_SelectedMlUiPath.Length == 0) return;
        auto root = _GetMlRootByLayerIx(g_SelectedMlLayerIx, g_SelectedMlAppKind);
        if (root is null) return;
        rootId = root.ControlId;

        if (g_SelectedMlPath.Length == 0) return;

        string[] parts = g_SelectedMlPath.Split("/");
        CGameManialinkControl@ cur = root;
        array<string> idParts;
        array<string> mixedParts;
        array<string> idListParts;
        if (rootId.Length > 0) idListParts.InsertLast(rootId);

        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) return;

            auto f = cast<CGameManialinkFrame@>(cur);
            if (f is null) return;
            if (uint(idx) >= f.Controls.Length) return;

            @cur = f.Controls[uint(idx)];
            if (cur is null) return;

            if (cur.ControlId.Length > 0) {
                idParts.InsertLast("#" + cur.ControlId);
                mixedParts.InsertLast("#" + cur.ControlId);
                idListParts.InsertLast(cur.ControlId);
            } else {
                mixedParts.InsertLast(part);
            }
        }

        idChain = _JoinParts(idParts, "/");
        mixedChain = _JoinParts(mixedParts, "/");
        idList = _JoinParts(idListParts, " -> ");

        if (rootId.Length > 0) {
            if (idChain.Length > 0) idChain = "#" + rootId + "/" + idChain;
            else idChain = "#" + rootId;
            if (mixedChain.Length > 0) mixedChain = "#" + rootId + "/" + mixedChain;
            else mixedChain = "#" + rootId;
        }
    }

    CGameManialinkFrame@ _GetMlRootByLayerIx(int layerIx, int appKind) {
        auto layer = _GetMlLayerByIx(appKind, layerIx);
        if (layer is null || layer.LocalPage is null) return null;
        return layer.LocalPage.MainFrame;
    }

    string _MlSourceEnumExpr(int appKind) {
        if (appKind == 1) return "UiNav::ManiaLinkSource::Menu";
        if (appKind == 2) return "UiNav::ManiaLinkSource::Editor";
        return "UiNav::ManiaLinkSource::Playground";
    }

    string _BuildMlTargetSnippet(const string &in rootId, const string &in idChain, const string &in mixedChain, int layerIx, const string &in layerName) {
        string selector = _PickMlExportSelector(idChain, mixedChain);
        string safeLayerName = _EscapeCodeString(layerName);
        string safeRootId = _EscapeCodeString(rootId);
        string safeSelector = _EscapeCodeString(selector);

        string code = "";
        code += "UiNav::ManiaLinkReq@ req = UiNav::ManiaLinkReq();\n";
        code += "req.source = " + _MlSourceEnumExpr(g_SelectedMlAppKind) + ";\n";
        if (layerIx >= 0) {
            code += "req.layerIxHints.InsertLast(" + layerIx + ");\n";
        }
        if (layerName.Length > 0) {
            code += "req.pageNeedle = \"" + safeLayerName + "\";\n";
        }
        if (rootId.Length > 0) {
            code += "req.rootControlId = \"" + safeRootId + "\";\n";
        }
        code += "req.mustHaveLocalPage = true;\n";
        code += "\n";
        code += "UiNav::ManiaLinkSpec@ ml = UiNav::ManiaLinkSpec();\n";
        code += "@ml.req = req;\n";
        code += "ml.selector = \"" + safeSelector + "\";\n";
        if (idChain.Length > 0 && mixedChain.Length > 0 && mixedChain != idChain) {
            code += "// id-only: \"" + idChain + "\"\n";
        }
        code += "\n";
        code += "UiNav::Target@ t = UiNav::Target();\n";
        code += "t.name = \"MyTarget\";\n";
        code += "@t.ml = ml;\n";
        code += "t.pref = UiNav::BackendPref::PreferML;\n";
        return code;
    }

    string _BuildMlFullSelectorPath(CGameUILayer@ layer, const string &in rootId, const string &in idChain, const string &in mixedChain) {
        string selector = _PickMlExportSelector(idChain, mixedChain);

        string key = UiNav::LayerTags::KeyForLayer(layer, g_SelectedMlLayerIx);
        string s = "";
        s += "layerIx: " + g_SelectedMlLayerIx;
        if (key.Length > 0) s += "\nlayerKey: " + key;
        if (rootId.Length > 0) s += "\nrootId: " + rootId;
        if (selector.Length > 0) s += "\nselector: " + selector;
        if (idChain.Length > 0 && mixedChain.Length > 0 && mixedChain != idChain) {
            s += "\nselector(id-only): " + idChain;
        }
        return s;
    }

    string _PickMlExportSelector(const string &in idChain, const string &in mixedChain) {
        if (mixedChain.Length > 0 && mixedChain != idChain) return mixedChain;
        if (idChain.Length > 0) return idChain;
        if (mixedChain.Length > 0) return mixedChain;
        return g_SelectedMlPath;
    }

    bool _MlStylePackHasKey(const Json::Value@ obj, const string &in key) {
        try {
            return obj !is null && obj.HasKey(key);
        } catch {
            return false;
        }
    }

    string _MlStylePackReadStr(const Json::Value@ obj, const string &in key, const string &in fallback = "") {
        try {
            if (!_MlStylePackHasKey(obj, key)) return fallback;
            return string(obj[key]);
        } catch {
            return fallback;
        }
    }

    int _MlStylePackReadInt(const Json::Value@ obj, const string &in key, int fallback = 0) {
        try {
            if (!_MlStylePackHasKey(obj, key)) return fallback;
            return int(obj[key]);
        } catch {
            return fallback;
        }
    }

    bool _MlStylePackIsAbsPath(const string &in p) {
        if (p.Length < 1) return false;
        if (p[0] == 47 || p[0] == 92) return true;
        if (p.Length >= 2 && p[1] == 58) return true;
        return false;
    }

    string _MlStylePackResolvePath(const string &in p) {
        string path = p.Trim();
        if (path.Length == 0) return IO::FromStorageFolder("Exports/ManiaLinks/uinav_ml_style_pack.json");
        if (_MlStylePackIsAbsPath(path)) return path;
        return IO::FromStorageFolder(path);
    }

    void _MlStyleSnapshotInto(CGameManialinkControl@ n, Json::Value@ outObj, bool includeChildren, int maxDepth, int depth, bool includeTextValues) {
        if (n is null || outObj is null) return;

        outObj["format"] = "uinav_ml_style_snapshot_v1";
        outObj["type"] = UiNav::ML::TypeName(n);
        outObj["control_id"] = n.ControlId;
        outObj["visible"] = n.Visible;
        outObj["relative_x"] = n.RelativePosition_V3.x;
        outObj["relative_y"] = n.RelativePosition_V3.y;
        outObj["size_x"] = n.Size.x;
        outObj["size_y"] = n.Size.y;
        outObj["z_index"] = n.ZIndex;
        outObj["h_align"] = int(n.HorizontalAlign);
        outObj["v_align"] = int(n.VerticalAlign);

        auto classes = n.ControlClasses;
        if (classes.Length > 0) {
            Json::Value@ cls = Json::Object();
            cls["count"] = int(classes.Length);
            for (uint i = 0; i < classes.Length; ++i) {
                cls["i" + i] = classes[i];
            }
            outObj["classes"] = cls;
        }

        if (includeTextValues) {
            string text = UiNav::ML::ReadText(n);
            if (text.Length > 0) outObj["text"] = text;

            auto lbl = cast<CGameManialinkLabel@>(n);
            if (lbl !is null) outObj["label_value"] = lbl.Value;

            auto entry = cast<CGameManialinkEntry@>(n);
            if (entry !is null) outObj["entry_value"] = entry.Value;
        }

        if (!includeChildren || depth >= maxDepth) return;

        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null) return;

        Json::Value@ children = Json::Object();
        children["count"] = int(f.Controls.Length);
        for (uint i = 0; i < f.Controls.Length; ++i) {
            auto ch = f.Controls[i];
            if (ch is null) continue;
            Json::Value@ child = Json::Object();
            _MlStyleSnapshotInto(ch, child, includeChildren, maxDepth, depth + 1, includeTextValues);
            children["i" + i] = child;
        }
        outObj["children"] = children;
    }

    Json::Value@ _BuildMlStyleSnapshot(CGameManialinkControl@ n, bool includeChildren, int maxDepth, bool includeTextValues) {
        if (n is null) return null;
        if (maxDepth < 0) maxDepth = 0;
        Json::Value@ snap = Json::Object();
        _MlStyleSnapshotInto(n, snap, includeChildren, maxDepth, 0, includeTextValues);
        return snap;
    }

    bool _MlStylePackAddSelected(CGameManialinkControl@ sel) {
        if (sel is null) {
            g_MlStylePackStatus = "Style pack add failed: selection is null.";
            return false;
        }

        int maxDepth = S_MlStylePackMaxDepth;
        if (maxDepth < 0) maxDepth = 0;
        auto snap = _BuildMlStyleSnapshot(sel, S_MlStylePackIncludeChildren, maxDepth, S_MlStylePackIncludeTextValues);
        if (snap is null) {
            g_MlStylePackStatus = "Style pack add failed: snapshot build failed.";
            return false;
        }

        string rootId;
        string idChain;
        string mixedChain;
        string idList;
        _BuildMlChains(rootId, idChain, mixedChain, idList);
        string selector = _PickMlExportSelector(idChain, mixedChain);
        if (selector.Length == 0) selector = g_SelectedMlPath;

        MlStyleCaptureEntry@ entry = MlStyleCaptureEntry();
        entry.type = UiNav::ML::TypeName(sel);
        entry.controlId = sel.ControlId;
        entry.selector = selector;
        entry.selectorIdChain = idChain;
        entry.selectorMixedChain = mixedChain;
        entry.indexPath = g_SelectedMlPath;
        entry.uiPath = g_SelectedMlUiPath;
        entry.layerIx = g_SelectedMlLayerIx;
        entry.appKind = g_SelectedMlAppKind;
        entry.name = entry.type;
        if (entry.controlId.Length > 0) entry.name += " #" + entry.controlId;
        if (entry.selector.Length > 0) entry.name += " (" + entry.selector + ")";

        entry.snapshotJson = Json::Write(snap);
        if (entry.snapshotJson.Length == 0) {
            g_MlStylePackStatus = "Style pack add failed: snapshot serialization failed.";
            return false;
        }

        g_MlStylePackEntries.InsertLast(entry);
        g_MlStylePackStatus = "Added style entry #" + g_MlStylePackEntries.Length + ".";
        return true;
    }

    Json::Value@ _MlStylePackToJson() {
        Json::Value@ root = Json::Object();
        root["format"] = "uinav_ml_style_pack_v1";
        root["generated_at"] = Time::FormatString("%Y-%m-%d %H:%M:%S");
        root["count"] = int(g_MlStylePackEntries.Length);

        Json::Value@ entries = Json::Object();
        entries["count"] = int(g_MlStylePackEntries.Length);
        for (uint i = 0; i < g_MlStylePackEntries.Length; ++i) {
            auto e = g_MlStylePackEntries[i];
            if (e is null) continue;

            Json::Value@ item = Json::Object();
            item["name"] = e.name;
            item["type"] = e.type;
            item["control_id"] = e.controlId;
            item["selector"] = e.selector;
            item["selector_id_chain"] = e.selectorIdChain;
            item["selector_mixed_chain"] = e.selectorMixedChain;
            item["index_path"] = e.indexPath;
            item["ui_path"] = e.uiPath;
            item["layer_ix"] = e.layerIx;
            item["app_kind"] = e.appKind;

            bool wroteSnap = false;
            if (e.snapshotJson.Length > 0) {
                try {
                    auto snap = Json::Parse(e.snapshotJson);
                    if (snap !is null) {
                        item["snapshot"] = snap;
                        wroteSnap = true;
                    }
                } catch {
                    wroteSnap = false;
                }
            }
            if (!wroteSnap) item["snapshot_json"] = e.snapshotJson;
            entries["i" + i] = item;
        }

        root["entries"] = entries;
        return root;
    }

    bool _MlStylePackLoadFromJson(const Json::Value@ root) {
        if (root is null || !_MlStylePackHasKey(root, "entries")) return false;

        const Json::Value@ entries = root["entries"];
        int count = _MlStylePackReadInt(entries, "count", 0);
        if (count < 0) count = 0;

        array<MlStyleCaptureEntry@> loaded;
        for (int i = 0; i < count; ++i) {
            string k = "i" + i;
            if (!_MlStylePackHasKey(entries, k)) continue;
            const Json::Value@ item = entries[k];
            if (item is null) continue;

            MlStyleCaptureEntry@ e = MlStyleCaptureEntry();
            e.name = _MlStylePackReadStr(item, "name", "");
            e.type = _MlStylePackReadStr(item, "type", "");
            e.controlId = _MlStylePackReadStr(item, "control_id", "");
            e.selector = _MlStylePackReadStr(item, "selector", "");
            e.selectorIdChain = _MlStylePackReadStr(item, "selector_id_chain", "");
            e.selectorMixedChain = _MlStylePackReadStr(item, "selector_mixed_chain", "");
            e.indexPath = _MlStylePackReadStr(item, "index_path", "");
            e.uiPath = _MlStylePackReadStr(item, "ui_path", "");
            e.layerIx = _MlStylePackReadInt(item, "layer_ix", -1);
            e.appKind = _MlStylePackReadInt(item, "app_kind", 0);

            if (_MlStylePackHasKey(item, "snapshot")) {
                try {
                    e.snapshotJson = Json::Write(item["snapshot"]);
                } catch {
                    e.snapshotJson = "";
                }
            }
            if (e.snapshotJson.Length == 0) {
                e.snapshotJson = _MlStylePackReadStr(item, "snapshot_json", "");
            }
            if (e.snapshotJson.Length == 0) continue;

            if (e.name.Length == 0) {
                e.name = e.type;
                if (e.controlId.Length > 0) e.name += " #" + e.controlId;
            }
            loaded.InsertLast(e);
        }

        g_MlStylePackEntries.Resize(0);
        for (uint i = 0; i < loaded.Length; ++i) {
            g_MlStylePackEntries.InsertLast(loaded[i]);
        }
        return true;
    }

    bool _MlStylePackCopyJsonToClipboard() {
        auto pack = _MlStylePackToJson();
        if (pack is null) return false;
        string json = Json::Write(pack);
        if (json.Length == 0) return false;
        IO::SetClipboard(json);
        return true;
    }

    bool _MlStylePackSaveToFile(const string &in rawPath) {
        auto pack = _MlStylePackToJson();
        if (pack is null) return false;
        string path = _MlStylePackResolvePath(rawPath);
        _IO::File::WriteJsonFile(path, pack);
        return true;
    }

    bool _MlStylePackLoadFromFile(const string &in rawPath) {
        string path = _MlStylePackResolvePath(rawPath);
        if (!IO::FileExists(path)) return false;
        string txt = _IO::File::ReadFileToEnd(path);
        if (txt.Length == 0) return false;
        try {
            auto parsed = Json::Parse(txt);
            return _MlStylePackLoadFromJson(parsed);
        } catch {
            return false;
        }
    }

    int _MlStylePackApplyToSelectedLayer(bool applyChildren, int &out attempted) {
        attempted = 0;
        auto root = _GetMlRootByLayerIx(g_SelectedMlLayerIx, g_SelectedMlAppKind);
        if (root is null) {
            attempted = -1;
            return 0;
        }

        int applied = 0;
        for (uint i = 0; i < g_MlStylePackEntries.Length; ++i) {
            auto e = g_MlStylePackEntries[i];
            if (e is null) continue;
            attempted++;

            CGameManialinkControl@ dst = null;
            string selector = e.selector.Trim();
            if (selector.Length > 0) {
                @dst = UiNav::ML::ResolveSelector(selector, root);
            }
            if (dst is null && e.indexPath.Length > 0) {
                @dst = UiNav::ML::ResolveSelector(e.indexPath, root);
            }
            if (dst is null) continue;

            Json::Value@ snap = null;
            try {
                @snap = Json::Parse(e.snapshotJson);
            } catch {
                continue;
            }
            if (snap is null) continue;

            if (UiNav::ML::ApplySnapshotToNode(dst, snap, applyChildren)) {
                applied++;
            }
        }
        return applied;
    }

    string _EscapeCodeString(const string &in value) {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
    }

    string _BuildControlTreeMixedPathForSelection() {
        if (g_SelectedControlTreeRootIx < 0) return g_SelectedControlTreePath;

        CScene2d@ scene;
        if (!_GetScene2d(g_SelectedControlTreeOverlayAtSel, scene) || scene is null) return g_SelectedControlTreePath;
        uint rootIx = uint(g_SelectedControlTreeRootIx);
        if (rootIx >= scene.Mobils.Length) return g_SelectedControlTreePath;

        CControlFrame@ root = _RootFromMobil(scene, rootIx);
        if (root is null) return g_SelectedControlTreePath;

        array<string> tokens;
        string rootIdName = root.IdName.Trim();
        if (rootIdName.Length > 0) tokens.InsertLast("#" + rootIdName);

        CControlBase@ cur = cast<CControlBase@>(root);
        string relPath = g_SelectedControlTreePath.Trim();
        if (relPath.Length > 0) {
            auto parts = relPath.Split("/");
            for (uint i = 0; i < parts.Length; ++i) {
                string part = parts[i].Trim();
                if (part.Length == 0) continue;

                int idx = Text::ParseInt(part);
                if (idx < 0) {
                    tokens.InsertLast(part);
                    break;
                }

                uint uidx = uint(idx);
                if (cur is null || uidx >= _ChildrenLen(cur)) {
                    tokens.InsertLast(part);
                    break;
                }

                auto ch = _ChildAt(cur, uidx);
                if (ch is null) {
                    tokens.InsertLast(part);
                    break;
                }

                string idName = ch.IdName.Trim();
                if (idName.Length > 0) tokens.InsertLast("#" + idName);
                else tokens.InsertLast("" + idx);
                @cur = ch;
            }
        }

        return _JoinParts(tokens, "/");
    }

    string _BuildControlTreeTargetSnippet(const string &in selIdName = "") {
        string targetPath = _BuildControlTreeMixedPathForSelection();
        if (targetPath.Length == 0) targetPath = g_SelectedControlTreePath;

        string safePath = _EscapeCodeString(targetPath);
        string code = "";
        code += "UiNav::ControlTreeReq@ req = UiNav::ControlTreeReq();\n";
        code += "req.overlay = " + g_SelectedControlTreeOverlayAtSel + ";\n";
        if (g_SelectedControlTreeRootIx >= 0) code += "req.rootIx = " + g_SelectedControlTreeRootIx + ";\n";
        code += "\n";
        code += "UiNav::ControlTreeSpec@ controlTree = UiNav::ControlTreeSpec();\n";
        code += "@controlTree.req = req;\n";
        code += "controlTree.selector = \"" + safePath + "\";\n";
        code += "controlTree.requireVisible = true;\n";
        code += "\n";
        code += "UiNav::Target@ t = UiNav::Target();\n";
        code += "t.name = \"MyTarget\";\n";
        code += "@t.controlTree = controlTree;\n";
        code += "t.pref = UiNav::BackendPref::PreferControlTree;\n";
        return code;
    }

    string _CachedMlLayerName(CGameUILayer@ layer, int appKind, int layerIx) {
        if (layer is null || layerIx < 0) return "";
        string key = _MlAppPrefixByKind(appKind) + "/L" + layerIx;
        uint epoch = UiNav::ContextEpoch();

        _MlLayerNameCacheEntry@ e;
        if (g_MlLayerNameCache.Get(key, @e) && e !is null) {
            if (e.epoch == epoch && e.layer is layer) {
                return e.name;
            }
        }

        @e = _MlLayerNameCacheEntry();
        e.epoch = epoch;
        @e.layer = layer;
        e.name = _ExtractMlNameFromLayer(layer);
        g_MlLayerNameCache.Set(key, @e);
        return e.name;
    }

    string _ExtractMlNameFromLayer(CGameUILayer@ layer) {
        if (layer is null) return "";
        string page = layer.ManialinkPageUtf8;
        if (page.Length == 0) page = "" + layer.ManialinkPage;
        if (page.Length == 0) return "";
        if (page.Length > 4096) page = page.SubStr(0, 4096);
        int idx = _IndexOfFrom(page, "name=\"", 0);
        if (idx < 0) return "";
        idx += 6;
        int end = _IndexOfFrom(page, "\"", idx);
        if (end < 0 || end <= idx) return "";
        return page.SubStr(idx, end - idx);
    }

    int _IndexOfFrom(const string &in hay, const string &in needle, int start) {
        if (start < 0) start = 0;
        int hlen = int(hay.Length);
        int nlen = int(needle.Length);
        if (nlen == 0) return (start <= hlen ? start : -1);
        if (start > hlen - nlen) return -1;
        uint first = needle[0];
        int lastStart = hlen - nlen;
        for (int i = start; i <= lastStart; ++i) {
            if (hay[i] != first) continue;
            bool matches = true;
            for (int j = 1; j < nlen; ++j) {
                if (hay[i + j] != needle[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return i;
        }
        return -1;
    }

    string _JoinParts(const array<string> &in parts, const string &in sep) {
        if (parts.Length == 0) return "";
        string outStr = parts[0];
        for (uint i = 1; i < parts.Length; ++i) {
            outStr += sep + parts[i];
        }
        return outStr;
    }

    class _ControlTreePathSearchBudget {
        uint visited = 0;
        uint startedAt = 0;
        uint maxMs = 40;
        uint maxNodes = 120000;

        bool IsExhausted() const {
            if (visited >= maxNodes) return true;
            if (maxMs > 0 && (Time::Now - startedAt) > maxMs) return true;
            return false;
        }
    }

    bool _FindControlTreePathRecBudget(CControlBase@ cur, CControlBase@ target, const string &in relPath, string &out foundRelPath,
                                       _ControlTreePathSearchBudget@ budget) {
        if (cur is null || target is null) return false;
        if (budget is null) return false;
        if (budget.IsExhausted()) return false;
        budget.visited++;

        if (cur is target) {
            foundRelPath = relPath;
            return true;
        }

        uint len = _ChildrenLen(cur);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(cur, i);
            if (ch is null) continue;
            string childRel = relPath.Length == 0 ? ("" + i) : (relPath + "/" + i);
            if (_FindControlTreePathRecBudget(ch, target, childRel, foundRelPath, budget)) return true;
        }

        return false;
    }

    bool _FindControlTreePathRec(CControlBase@ cur, CControlBase@ target, const string &in relPath, string &out foundRelPath) {
        auto budget = _ControlTreePathSearchBudget();
        budget.startedAt = Time::Now;
        budget.maxMs = 40;
        budget.maxNodes = 120000;
        return _FindControlTreePathRecBudget(cur, target, relPath, foundRelPath, budget);
    }

    bool _FindControlTreePathForControlAtOverlayBudget(CControlBase@ target, uint overlay, int &out rootIx, string &out relPath,
                                                       _ControlTreePathSearchBudget@ budget) {
        rootIx = -1;
        relPath = "";
        if (target is null) return false;
        if (budget is null) return false;

        CScene2d@ scene;
        if (!_GetScene2d(overlay, scene) || scene is null) return false;

        for (uint i = 0; i < scene.Mobils.Length; ++i) {
            if (budget.IsExhausted()) return false;

            auto root = _RootFromMobil(scene, i);
            if (root is null) continue;

            string found = "";
            if (_FindControlTreePathRecBudget(root, target, "", found, budget)) {
                rootIx = int(i);
                relPath = found;
                return true;
            }
        }
        return false;
    }

    bool _FindControlTreePathForControlAtOverlay(CControlBase@ target, uint overlay, int &out rootIx, string &out relPath) {
        auto budget = _ControlTreePathSearchBudget();
        budget.startedAt = Time::Now;
        budget.maxMs = 40;
        budget.maxNodes = 120000;
        return _FindControlTreePathForControlAtOverlayBudget(target, overlay, rootIx, relPath, budget);
    }

    bool _FindControlTreePathForControlAnyOverlay(CControlBase@ target, uint &out overlay, int &out rootIx, string &out relPath) {
        overlay = 0;
        rootIx = -1;
        relPath = "";
        if (target is null) return false;

        CGameCtnApp@ app = GetApp();
        if (app is null || app.Viewport is null) return false;
        auto vp = cast<CDx11Viewport>(app.Viewport);
        if (vp is null) return false;

        auto budget = _ControlTreePathSearchBudget();
        budget.startedAt = Time::Now;
        budget.maxMs = 40;
        budget.maxNodes = 120000;
        for (uint ov = 0; ov < vp.Overlays.Length; ++ov) {
            if (budget.IsExhausted()) break;
            int r = -1;
            string p = "";
            if (_FindControlTreePathForControlAtOverlayBudget(target, ov, r, p, budget)) {
                overlay = ov;
                rootIx = r;
                relPath = p;
                return true;
            }
        }
        return false;
    }

    string _ControlTreePathDisplay(uint overlay, int rootIx, const string &in relPath) {
        string s = "overlay=" + overlay;
        if (rootIx >= 0) s += " root[" + rootIx + "]";
        if (relPath.Length > 0) s += "/" + relPath;
        return s;
    }

}
}
