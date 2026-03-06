namespace UiNav {
namespace Dump {

    enum RequestPumpPolicy {
        Disabled = 0,
        DevOnly = 1,
        Always = 2
    }

    [Setting hidden name="UiNav dump request pump policy (0=off,1=dev-only,2=always)"]
    int S_RequestPumpPolicy = int(RequestPumpPolicy::DevOnly);

    [Setting hidden name="UiNav dump request poll (ms)"]
    uint S_RequestPollMs = 200;

    [Setting hidden name="UiNav dump default storage dir"]
    string S_DefaultDumpRelDir = "opdev/uinav/dumps";

    const string kReqRelDir = "opdev/uinav/requests";
    const string kRespRelDir = "opdev/uinav/responses";

    uint g_LastPollMs = 0;
    string g_LastDumpStatus = "";
    string g_LastDumpPath = "";

    bool RequestPumpEnabledNow() {
        if (S_RequestPumpPolicy <= int(RequestPumpPolicy::Disabled)) return false;
        if (S_RequestPumpPolicy >= int(RequestPumpPolicy::Always)) return true;
        return S_ShowUiNavDev;
    }

    int GetRequestPumpPolicy() {
        return S_RequestPumpPolicy;
    }

    void SetRequestPumpPolicy(int policy) {
        if (policy < int(RequestPumpPolicy::Disabled)) policy = int(RequestPumpPolicy::Disabled);
        if (policy > int(RequestPumpPolicy::Always)) policy = int(RequestPumpPolicy::Always);
        S_RequestPumpPolicy = policy;
    }

    class _DumpBudget {
        uint startedAtMs = 0;
        uint maxElapsedMs = 250;
        uint maxNodes = 3500;
        uint nodesVisited = 0;
        bool truncatedByNodeLimit = false;
        bool truncatedByTimeLimit = false;

        bool _check_limits() {
            if (nodesVisited >= maxNodes) {
                truncatedByNodeLimit = true;
                return false;
            }
            if (Time::Now - startedAtMs >= maxElapsedMs) {
                truncatedByTimeLimit = true;
                return false;
            }
            return true;
        }

        bool try_enter_node() {
            if (!_check_limits()) return false;
            nodesVisited++;
            return true;
        }

        bool should_stop() {
            return !_check_limits();
        }

        bool was_truncated() {
            return truncatedByNodeLimit || truncatedByTimeLimit;
        }
    }

    string _ts_utc() {
        return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%SZ", Time::Stamp);
    }

    void _trace_swallowed(const string &in where) {
        UiNav::Trace::Add("Dump catch: " + where);
    }

    string _storage(const string &in rel) {
        return IO::FromStorageFolder(rel);
    }

    bool _is_json_file(const string &in p) {
        if (p.Length < 5) return false;
        return p.SubStr(p.Length - 5).ToLower() == ".json";
    }

    bool _is_abs_path(const string &in p) {
        if (p.Length < 1) return false;
        if (p[0] == 47 || p[0] == 92) return true; // '/' or '\'
        if (p.Length >= 2 && p[1] == 58) return true; // 'C:'
        return false;
    }

    void _ensure_dir_abs(const string &in p) {
        if (p.Length == 0) return;
        if (!IO::FolderExists(p)) IO::CreateFolder(p, true);
    }

    string _sanitize_file_name(const string &in raw) {
        string s = raw.Trim();
        if (s.Length == 0) return "";
        return Path::SanitizeFileName(s);
    }

    string _default_dump_file_name() {
        return "ui_dump_" + Time::FormatStringUTC("%Y%m%d-%H%M%S", Time::Stamp) + ".txt";
    }

    string _path_without_ext(const string &in p) {
        int slash = p.LastIndexOf("/");
        int bslash = p.LastIndexOf("\\");
        int sep = Math::Max(slash, bslash);
        int dot = p.LastIndexOf(".");
        if (dot <= sep) return p;
        return p.SubStr(0, dot);
    }

    string _read_file_text(const string &in p) {
        if (!IO::FileExists(p)) return "";
        IO::File f(p, IO::FileMode::Read);
        string txt = f.ReadToEnd();
        f.Close();
        return txt;
    }

    void _write_file_text(const string &in p, const string &in txt) {
        _IO::File::WriteFile(p, txt, false);
    }

    void _consume_request_file(const string &in reqFileAbs) {
        try {
            if (IO::FileExists(reqFileAbs)) IO::Delete(reqFileAbs);
        } catch {
            _trace_swallowed("_consume_request_file");
        }
    }

    string _jstr(const Json::Value@ obj, const string &in key, const string &in fallback = "") {
        try {
            if (obj is null || !obj.HasKey(key)) return fallback;
            return string(obj[key]);
        } catch {
            return fallback;
        }
    }

    int _jint(const Json::Value@ obj, const string &in key, int fallback = 0) {
        try {
            if (obj is null || !obj.HasKey(key)) return fallback;
            return int(obj[key]);
        } catch {
            return fallback;
        }
    }

    bool _jbool(const Json::Value@ obj, const string &in key, bool fallback = false) {
        try {
            if (obj is null || !obj.HasKey(key)) return fallback;
            return bool(obj[key]);
        } catch {
            string s = _jstr(obj, key, fallback ? "true" : "false").ToLower();
            return s == "1" || s == "true" || s == "yes";
        }
    }

    string _short(const string &in s, uint maxLen = 180) {
        string safe = UiNav::CleanUiFormatting(s);
        safe = safe.Replace("\r", "\\r");
        safe = safe.Replace("\n", "\\n");
        safe = safe.Replace("\t", "\\t");
        safe = safe.Replace("\"", "'");
        int maxLenInt = int(maxLen);
        if (int(safe.Length) > maxLenInt) safe = safe.SubStr(0, maxLenInt) + "...";
        return safe;
    }

    string _resolve_dump_path(const Json::Value@ data) {
        string outputPath = _jstr(data, "output_path", _jstr(data, "path", "")).Trim();
        if (outputPath.Length > 0) {
            if (!_is_abs_path(outputPath)) outputPath = _storage(outputPath);
            string folder = Path::GetDirectoryName(outputPath);
            if (folder.Length > 0) _ensure_dir_abs(folder);
            return outputPath;
        }

        string outputDir = _jstr(data, "output_dir", "").Trim();
        if (outputDir.Length == 0) outputDir = _storage(S_DefaultDumpRelDir);
        else if (!_is_abs_path(outputDir)) outputDir = _storage(outputDir);
        _ensure_dir_abs(outputDir);

        string fileName = _sanitize_file_name(_jstr(data, "file_name", ""));
        if (fileName.Length == 0) fileName = _default_dump_file_name();
        if (!fileName.EndsWith(".txt")) fileName += ".txt";
        return Path::Join(outputDir, fileName);
    }

    void _append_ml_node_lines(CGameManialinkControl@ n, const string &in path, int depth, int maxDepth, array<string>@ lines, _DumpBudget@ budget) {
        if (budget is null || budget.should_stop()) return;
        if (n is null || depth > maxDepth) return;
        if (!budget.try_enter_node()) return;

        string line = "  " + path + " : " + UiNav::ML::TypeName(n);
        if (n.ControlId.Length > 0) line += " #" + n.ControlId;
        line += " vis=" + (n.Visible ? "true" : "false");

        string t = "";
        try {
            t = UiNav::ML::ReadText(n);
        } catch {
            t = "";
            _trace_swallowed("_append_ml_node_lines/ReadText");
        }
        t = _short(t, 140);
        if (t.Length > 0) line += " text=\"" + t + "\"";
        lines.InsertLast(line);

        uint len = UiNav::ML::_ChildrenLen(n);
        for (uint i = 0; i < len; i++) {
            if (budget.should_stop()) break;
            _append_ml_node_lines(UiNav::ML::_ChildAt(n, i), path + "/" + i, depth + 1, maxDepth, lines, budget);
        }
    }

    void _append_controlTree_node_lines(CControlBase@ n, const string &in path, int depth, int maxDepth, array<string>@ lines, _DumpBudget@ budget) {
        if (budget is null || budget.should_stop()) return;
        if (n is null || depth > maxDepth) return;
        if (!budget.try_enter_node()) return;

        string line = "  " + path + " : " + UiNav::NodeTypeName(n);
        line += " vis=" + (n.IsVisible ? "true" : "false");
        line += " hiddenExt=" + (n.IsHiddenExternal ? "true" : "false");

        string t = _short(UiNav::ReadText(n), 140);
        if (t.Length > 0) line += " text=\"" + t + "\"";
        lines.InsertLast(line);

        uint len = UiNav::_ChildrenLen(n);
        for (uint i = 0; i < len; i++) {
            if (budget.should_stop()) break;
            _append_controlTree_node_lines(UiNav::_ChildAt(n, i), path + "/" + i, depth + 1, maxDepth, lines, budget);
        }
    }

    

    Json::Value@ _dump_ui_internal(const Json::Value@ data) {
        Json::Value@ respObj = Json::Object();
        Json::Value@ dataObj = Json::Object();
        respObj["success"] = false;
        respObj["error"] = "";
        respObj["data"] = dataObj;

        bool includeMl = _jbool(data, "include_ml", true);
        bool includeControlTree = _jbool(data, "include_control_tree", false);
        bool includeLayerPages = _jbool(data, "include_layer_pages", false);

        int maxDepth = _jint(data, "max_depth", 8);
        if (maxDepth < 1) maxDepth = 1;
        if (maxDepth > 16) maxDepth = 16;

        int maxNodes = _jint(data, "max_nodes", 3500);
        if (maxNodes < 200) maxNodes = 200;
        if (maxNodes > 20000) maxNodes = 20000;

        int maxElapsedMs = _jint(data, "max_elapsed_ms", 250);
        if (maxElapsedMs < 25) maxElapsedMs = 25;
        if (maxElapsedMs > 900) maxElapsedMs = 900;

        int layerIx = _jint(data, "layer_ix", -1);
        int overlayRaw = _jint(data, "overlay", 16);
        if (overlayRaw < 0) overlayRaw = 0;
        uint overlay = uint(overlayRaw);

        if (!includeMl && !includeControlTree) {
            respObj["error"] = "Nothing to dump: both include_ml and include_control_tree are false.";
            return respObj;
        }

        string outputPath = _resolve_dump_path(data);
        if (outputPath.Length == 0) {
            respObj["error"] = "Failed to resolve output path.";
            return respObj;
        }

        array<string> lines;
        lines.InsertLast("UiNav UI dump @ " + _ts_utc());
        lines.InsertLast("options: include_ml=" + tostring(includeMl) + ", include_control_tree=" + tostring(includeControlTree)
            + ", include_layer_pages=" + tostring(includeLayerPages) + ", max_depth=" + tostring(maxDepth)
            + ", layer_ix=" + tostring(layerIx) + ", overlay=" + tostring(overlay)
            + ", max_nodes=" + tostring(maxNodes) + ", max_elapsed_ms=" + tostring(maxElapsedMs));
        lines.InsertLast("");

        _DumpBudget@ budget = _DumpBudget();
        budget.startedAtMs = Time::Now;
        budget.maxNodes = uint(maxNodes);
        budget.maxElapsedMs = uint(maxElapsedMs);

        int mlLayers = 0;
        int mlLayersDumped = 0;
        int controlTreeRoots = 0;
        int layerPagesWritten = 0;

        if (includeMl) {
            lines.InsertLast("== ML ==");
            CGameManiaApp@ app = UiNav::Layers::GetManiaApp();
            string appSource = "playground";
            if (app is null) {
                @app = UiNav::Layers::GetManiaAppMenu();
                appSource = "menu";
            }
            if (app is null) {
                lines.InsertLast("ManiaApp unavailable (playground+menu).");
            } else {
                lines.InsertLast("ManiaApp source: " + appSource);
                auto layers = app.UILayers;
                mlLayers = int(layers.Length);
                lines.InsertLast("UILayers: " + layers.Length);

                int startIx = 0;
                int endIx = int(layers.Length) - 1;
                if (layerIx >= 0) {
                    if (layerIx >= int(layers.Length)) {
                        lines.InsertLast("Requested layer_ix is out of range: " + layerIx);
                        startIx = 0;
                        endIx = -1;
                    } else {
                        startIx = layerIx;
                        endIx = layerIx;
                    }
                }

                string pageBase = _path_without_ext(outputPath);
                for (int i = startIx; i <= endIx; i++) {
                    if (i < 0 || i >= int(layers.Length)) continue;
                    auto layer = layers[uint(i)];
                    if (layer is null) {
                        lines.InsertLast("Layer[" + i + "]: <null>");
                        continue;
                    }

                    mlLayersDumped++;
                    string layerLine = "Layer[" + i + "]";
                    layerLine += " visible=" + (layer.IsVisible ? "true" : "false");
                    layerLine += " hasLocalPage=" + ((layer.LocalPage !is null) ? "true" : "false");
                    lines.InsertLast(layerLine);

                    CGameManialinkFrame@ root = UiNav::ML::GetRootFrame(layer);
                    if (root is null) {
                        lines.InsertLast("  root=<null>");
                    } else {
                        _append_ml_node_lines(root, "MLRoot", 0, maxDepth, lines, budget);
                    }

                    if (budget.was_truncated()) {
                        lines.InsertLast("  NOTE: traversal truncated by budget while dumping ML tree.");
                        break;
                    }

                    if (includeLayerPages) {
                        string page = "";
                        try {
                            page = layer.ManialinkPage;
                            if (page.Length == 0) page = layer.ManialinkPageUtf8;
                        } catch {
                            page = "";
                            _trace_swallowed("_dump_ui_internal/layer_page");
                        }
                        if (page.Length > 0) {
                            string pagePath = pageBase + ".layer-" + i + ".xml";
                            _write_file_text(pagePath, page);
                            layerPagesWritten++;
                            lines.InsertLast("  page_xml=" + pagePath + " chars=" + page.Length);
                        } else {
                            lines.InsertLast("  page_xml=<empty>");
                        }
                    }
                }
            }
            lines.InsertLast("");
        }

        if (includeControlTree) {
            lines.InsertLast("== ControlTree Overlay ==");
            CScene2d@ scene;
            if (!UiNav::_GetScene2d(overlay, scene)) {
                lines.InsertLast("Overlay unavailable: " + overlay);
            } else {
                lines.InsertLast("Overlay " + overlay + " roots: " + scene.Mobils.Length);
                for (uint i = 0; i < scene.Mobils.Length; i++) {
                    CControlFrame@ root = UiNav::_RootFromMobil(scene, i);
                    if (root is null) continue;
                    controlTreeRoots++;
                    _append_controlTree_node_lines(root, "root[" + i + "]", 0, maxDepth, lines, budget);
                    if (budget.was_truncated()) {
                        lines.InsertLast("NOTE: traversal truncated by budget while dumping ControlTree tree.");
                        break;
                    }
                }
            }
            lines.InsertLast("");
        }

        string outText = "";
        for (uint i = 0; i < lines.Length; i++) outText += lines[i] + "\n";
        _IO::File::WriteFile(outputPath, outText, false);

        dataObj["output_path"] = outputPath;
        dataObj["line_count"] = int(lines.Length);
        dataObj["ml_layers"] = mlLayers;
        dataObj["ml_layers_dumped"] = mlLayersDumped;
        dataObj["control_tree_roots"] = controlTreeRoots;
        dataObj["layer_pages_written"] = layerPagesWritten;
        dataObj["nodes_visited"] = int(budget.nodesVisited);
        dataObj["truncated"] = budget.was_truncated();
        dataObj["truncated_by_node_limit"] = budget.truncatedByNodeLimit;
        dataObj["truncated_by_time_limit"] = budget.truncatedByTimeLimit;
        respObj["data"] = dataObj;
        respObj["success"] = true;

        g_LastDumpPath = outputPath;
        string trunc = budget.was_truncated() ? " (truncated)" : "";
        g_LastDumpStatus = "Wrote " + lines.Length + " lines to " + outputPath + trunc;
        return respObj;
    }

    Json::Value@ DumpUi() {
        return _dump_ui_internal(null);
    }

    Json::Value@ DumpUiWithOptions(const Json::Value@ data) {
        return _dump_ui_internal(data);
    }

    string DumpUiToFile(
        const string &in outputPath = "",
        int maxDepth = 8,
        int layerIx = -1,
        bool includeControlTree = false,
        uint overlay = 16,
        bool includeLayerPages = false
    ) {
        Json::Value@ data = Json::Object();
        if (outputPath.Length > 0) data["output_path"] = outputPath;
        data["max_depth"] = maxDepth;
        data["layer_ix"] = layerIx;
        data["overlay"] = int(overlay);
        data["include_ml"] = true;
        data["include_control_tree"] = includeControlTree;
        data["include_layer_pages"] = includeLayerPages;

        Json::Value@ resp = _dump_ui_internal(data);
        if (!_jbool(resp, "success", false)) return "";
        Json::Value@ dataObj = null;
        try {
            @dataObj = resp["data"];
        } catch {
            @dataObj = null;
            _trace_swallowed("DumpUIToFileResp/data");
        }
        return _jstr(dataObj, "output_path", "");
    }

    string GetLastDumpStatus() {
        return g_LastDumpStatus;
    }

    string GetLastDumpPath() {
        return g_LastDumpPath;
    }

    string _resolve_input_path(const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length == 0) return "";
        if (!_is_abs_path(p)) p = _storage(p);
        return p;
    }

    string _default_named_file(const string &in prefix, const string &in extWithDot) {
        return prefix + "_" + Time::FormatStringUTC("%Y%m%d-%H%M%S", Time::Stamp) + extWithDot;
    }

    string _resolve_action_output_path(const Json::Value@ data, const string &in defaultName, const string &in defaultExtWithDot) {
        string outputPath = _jstr(data, "output_path", "").Trim();
        if (outputPath.Length > 0) {
            if (!_is_abs_path(outputPath)) outputPath = _storage(outputPath);
            string folder = Path::GetDirectoryName(outputPath);
            if (folder.Length > 0) _ensure_dir_abs(folder);
            return outputPath;
        }

        string outputDir = _jstr(data, "output_dir", "").Trim();
        if (outputDir.Length == 0) outputDir = _storage(S_DefaultDumpRelDir);
        else if (!_is_abs_path(outputDir)) outputDir = _storage(outputDir);
        _ensure_dir_abs(outputDir);

        string fileName = _sanitize_file_name(_jstr(data, "file_name", ""));
        if (fileName.Length == 0) fileName = defaultName;
        if (defaultExtWithDot.Length > 0 && !fileName.ToLower().EndsWith(defaultExtWithDot.ToLower())) {
            fileName += defaultExtWithDot;
        }
        return Path::Join(outputDir, fileName);
    }

    Json::Value@ _new_action_resp() {
        Json::Value@ respObj = Json::Object();
        respObj["success"] = false;
        respObj["error"] = "";
        respObj["data"] = Json::Object();
        return respObj;
    }

    uint _count_occurs_lc(const string &in lowerHaystack, const string &in lowerNeedle) {
        if (lowerHaystack.Length == 0 || lowerNeedle.Length == 0) return 0;
        uint count = 0;
        int from = 0;
        int needleLen = int(lowerNeedle.Length);
        while (from <= int(lowerHaystack.Length) - needleLen) {
            string rest = lowerHaystack.SubStr(from);
            int rel = rest.IndexOf(lowerNeedle);
            if (rel < 0) break;
            count++;
            from += rel + needleLen;
        }
        return count;
    }

    int _line_count(const string &in raw) {
        if (raw.Length == 0) return 0;
        int lines = 1;
        int rawLen = int(raw.Length);
        for (int i = 0; i < rawLen; ++i) {
            if (int(raw[uint(i)]) == 10) lines++;
        }
        return lines;
    }

    string _extract_manialink_name(const string &in xml) {
        if (xml.Length == 0) return "";
        string lower = xml.ToLower();
        int mlIx = lower.IndexOf("<manialink");
        if (mlIx < 0) return "";
        int endRel = xml.SubStr(mlIx).IndexOf(">");
        if (endRel < 0) return "";
        int endIx = mlIx + endRel;
        string head = xml.SubStr(mlIx, endIx - mlIx);
        string headLower = head.ToLower();
        int nameIx = headLower.IndexOf("name=\"");
        if (nameIx < 0) return "";
        int valStart = nameIx + 6;
        int valEndRel = head.SubStr(valStart).IndexOf("\"");
        if (valEndRel < 0) return "";
        int valEnd = valStart + valEndRel;
        if (valEnd <= valStart) return "";
        return head.SubStr(valStart, valEnd - valStart);
    }

    void _collect_xml_stats(const string &in xml, Json::Value@ outStats) {
        if (outStats is null) return;
        string lower = xml.ToLower();
        outStats["chars"] = xml.Length;
        outStats["lines"] = _line_count(xml);
        outStats["manialink_name"] = _extract_manialink_name(xml);

        outStats["tag_frame"] = int(_count_occurs_lc(lower, "<frame"));
        outStats["tag_quad"] = int(_count_occurs_lc(lower, "<quad"));
        outStats["tag_label"] = int(_count_occurs_lc(lower, "<label"));
        outStats["tag_entry"] = int(_count_occurs_lc(lower, "<entry"));
        outStats["tag_textedit"] = int(_count_occurs_lc(lower, "<textedit"));
        outStats["tag_camera"] = int(_count_occurs_lc(lower, "<camera"));
        outStats["tag_framemodel"] = int(_count_occurs_lc(lower, "<framemodel"));
        outStats["tag_frameinstance"] = int(_count_occurs_lc(lower, "<frameinstance"));
        outStats["tag_script"] = int(_count_occurs_lc(lower, "<script"));
        outStats["tag_stylesheet"] = int(_count_occurs_lc(lower, "<stylesheet"));

        outStats["attr_z_index"] = int(_count_occurs_lc(lower, " z-index=\""));
        outStats["attr_z"] = int(_count_occurs_lc(lower, " z=\""));
        outStats["attr_hidden"] = int(_count_occurs_lc(lower, " hidden=\""));
        outStats["attr_visible"] = int(_count_occurs_lc(lower, " visible=\""));
        outStats["attr_scriptevents"] = int(_count_occurs_lc(lower, " scriptevents=\""));
        outStats["attr_data"] = int(_count_occurs_lc(lower, " data-"));
        outStats["attr_fullscreen"] = int(_count_occurs_lc(lower, " fullscreen=\""));
        outStats["attr_autoscale"] = int(_count_occurs_lc(lower, " autoscale=\""));
    }

    bool _read_layer_xml_from_live(int appKind, int layerIx, string &out xmlOut, string &out errOut) {
        xmlOut = "";
        errOut = "";
        if (layerIx < 0) {
            errOut = "layer_ix must be >= 0.";
            return false;
        }
        auto layer = UiNav::Debug::_GetMlLayerByIx(appKind, layerIx);
        if (layer is null) {
            errOut = "Layer not found for app_kind=" + appKind + ", layer_ix=" + layerIx + ".";
            return false;
        }
        try {
            xmlOut = layer.ManialinkPageUtf8;
            if (xmlOut.Length == 0) xmlOut = "" + layer.ManialinkPage;
        } catch {
            xmlOut = "";
        }
        if (xmlOut.Length == 0) {
            errOut = "Layer page XML is empty.";
            return false;
        }
        return true;
    }

    void _merge_req_field_if_missing(Json::Value@ dst, const Json::Value@ src, const string &in key) {
        try {
            if (dst is null || src is null) return;
            if (!dst.HasKey(key) && src.HasKey(key)) dst[key] = src[key];
        } catch {
            _trace_swallowed("_merge_req_field_if_missing/" + key);
            return;
        }
    }

    void _merge_flat_req_fields(Json::Value@ data, const Json::Value@ req) {
        _merge_req_field_if_missing(data, req, "include_ml");
        _merge_req_field_if_missing(data, req, "include_control_tree");
        _merge_req_field_if_missing(data, req, "include_layer_pages");
        _merge_req_field_if_missing(data, req, "max_depth");
        _merge_req_field_if_missing(data, req, "max_nodes");
        _merge_req_field_if_missing(data, req, "max_elapsed_ms");
        _merge_req_field_if_missing(data, req, "layer_ix");
        _merge_req_field_if_missing(data, req, "overlay");
        _merge_req_field_if_missing(data, req, "output_path");
        _merge_req_field_if_missing(data, req, "output_dir");
        _merge_req_field_if_missing(data, req, "file_name");

        _merge_req_field_if_missing(data, req, "app_kind");
        _merge_req_field_if_missing(data, req, "write_file");
        _merge_req_field_if_missing(data, req, "include_xml");
        _merge_req_field_if_missing(data, req, "layer_xml_path");
        _merge_req_field_if_missing(data, req, "layer_xml_output_path");
    }

    void _process_request_file(const string &in reqFileAbs, const string &in respDirAbs) {
        string raw = _read_file_text(reqFileAbs);
        if (raw.Length == 0) {
            _consume_request_file(reqFileAbs);
            return;
        }

        Json::Value@ req = null;
        Json::Value@ resp = Json::Object();
        string reqId = Text::Format("%08x", Math::Rand(0, 0x7fffffff));
        string action = "dump_ui";

        try {
            @req = Json::Parse(raw);
            reqId = _jstr(req, "request_id", reqId);
            action = _jstr(req, "action", "dump_ui");
        } catch {
            resp["request_id"] = reqId;
            resp["action"] = action;
            resp["success"] = false;
            resp["error"] = "Invalid JSON request: " + reqFileAbs;
            resp["data"] = Json::Object();
            _write_file_text(Path::Join(respDirAbs, "req-" + reqId + ".json"), Json::Write(resp));
            _consume_request_file(reqFileAbs);
            return;
        }

        Json::Value@ data = null;
        try {
            if (req !is null && req.HasKey("data")) @data = req["data"];
        } catch {
            @data = null;
            _trace_swallowed("_process_request_file/data");
        }
        if (data is null) @data = Json::Object();
        _merge_flat_req_fields(data, req);

        string actionLower = action.ToLower();
        string actionOut = action;
        Json::Value@ inner = null;

        if (actionLower == "dump_ui" || actionLower == "dump-ui") {
            actionOut = "dump_ui";
            @inner = _dump_ui_internal(data);
        } else {
            resp["request_id"] = reqId;
            resp["action"] = action;
            resp["success"] = false;
            resp["error"] = "Unknown action for UiNav dump pump: " + action
                + " (supported: dump_ui)";
            resp["data"] = Json::Object();
            _write_file_text(Path::Join(respDirAbs, "req-" + reqId + ".json"), Json::Write(resp));
            _consume_request_file(reqFileAbs);
            return;
        }

        bool ok = _jbool(inner, "success", false);
        string err = _jstr(inner, "error", "");
        Json::Value@ innerData = Json::Object();
        try {
            if (inner !is null && inner.HasKey("data")) @innerData = inner["data"];
        } catch {
            @innerData = Json::Object();
            _trace_swallowed("_process_request_file/innerData");
        }
        if (innerData is null) @innerData = Json::Object();

        resp["request_id"] = reqId;
        resp["action"] = actionOut;
        resp["success"] = ok;
        resp["error"] = err;
        resp["ts_utc"] = _ts_utc();
        resp["data"] = innerData;
        _write_file_text(Path::Join(respDirAbs, "req-" + reqId + ".json"), Json::Write(resp));
        _consume_request_file(reqFileAbs);
    }

    void TickRequestPump() {
        if (!RequestPumpEnabledNow()) return;

        uint now = Time::Now;
        if (now - g_LastPollMs < S_RequestPollMs) return;
        g_LastPollMs = now;

        string reqDirAbs = _storage(kReqRelDir);
        string respDirAbs = _storage(kRespRelDir);
        _ensure_dir_abs(reqDirAbs);
        _ensure_dir_abs(respDirAbs);

        array<string> reqFiles = IO::IndexFolder(reqDirAbs, false);
        reqFiles.SortAsc();
        for (uint i = 0; i < reqFiles.Length; i++) {
            string reqFileAbs = reqFiles[i];
            if (!_is_json_file(reqFileAbs)) continue;
            _process_request_file(reqFileAbs, respDirAbs);
            break;
        }
    }

}
}
