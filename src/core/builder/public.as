namespace UiNav {
namespace Builder {

    int _FirstRootIx(const BuilderDocument@ doc) {
        if (doc is null) return -1;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto node = doc.nodes[i];
            if (node !is null && node.parentIx < 0) return int(i);
        }
        return -1;
    }

    void _FinalizeDocument(BuilderDocument@ doc) {
        if (doc is null) return;
        if (doc.scriptBlock is null) @doc.scriptBlock = BuilderScriptBlock();
        if (doc.stylesheetBlock is null) @doc.stylesheetBlock = BuilderStylesheetBlock();
        _RebuildNodeIndex(doc);
        if (doc.rootIx < 0 || doc.rootIx >= int(doc.nodes.Length)) {
            doc.rootIx = _FirstRootIx(doc);
        } else {
            auto root = doc.nodes[uint(doc.rootIx)];
            if (root is null || root.parentIx >= 0) doc.rootIx = _FirstRootIx(doc);
        }
    }

    string _NormalizePublicKind(const string &in kindRaw) {
        string kind = kindRaw.Trim().ToLower();
        if (kind.Length == 0) return "frame";
        if (_IsKnownKind(kind)) return kind;
        return "generic";
    }

    void _EnsureNodeDefaults(BuilderNode@ node) {
        if (node is null) return;
        if (node.typed is null) @node.typed = _NewTypedProps();

        string rawTag = node.tagName.Trim();
        string kind = _NormalizePublicKind(node.kind);
        if (kind == "generic" && rawTag.Length > 0 && rawTag.ToLower() != "generic") {
            node.kind = "generic";
        } else {
            node.kind = kind;
        }

        if (node.kind != "generic") {
            node.tagName = node.kind;
        } else if (rawTag.Length == 0) {
            node.tagName = "frame";
        }

        if (node.uid.Length == 0) {
            node.uid = "n" + (g_NextUid++);
        }
    }

    bool _DocUidExists(const BuilderDocument@ doc, const string &in uid) {
        if (doc is null || uid.Length == 0) return false;
        int dummy = -1;
        return doc.nodeByUid.Get(uid, dummy);
    }

    int _SiblingCount(const BuilderDocument@ doc, int parentIx) {
        if (doc is null) return 0;
        if (parentIx < 0) return _CountRootNodes(doc);
        if (parentIx >= int(doc.nodes.Length)) return 0;
        auto parent = doc.nodes[uint(parentIx)];
        if (parent is null) return 0;
        return int(parent.childIx.Length);
    }

    bool _BuilderJsonHas(const Json::Value@ obj, const string &in key) {
        try {
            return obj !is null && obj.HasKey(key);
        } catch {
            return false;
        }
    }

    string _BuilderJsonStr(const Json::Value@ obj, const string &in key, const string &in fallback = "") {
        try {
            if (!_BuilderJsonHas(obj, key)) return fallback;
            return string(obj[key]);
        } catch {
            return fallback;
        }
    }

    int _BuilderJsonInt(const Json::Value@ obj, const string &in key, int fallback = 0) {
        try {
            if (!_BuilderJsonHas(obj, key)) return fallback;
            return int(obj[key]);
        } catch {
            return fallback;
        }
    }

    float _BuilderJsonFloat(const Json::Value@ obj, const string &in key, float fallback = 0.0f) {
        try {
            if (!_BuilderJsonHas(obj, key)) return fallback;
            return float(obj[key]);
        } catch {
            return fallback;
        }
    }

    bool _BuilderJsonBool(const Json::Value@ obj, const string &in key, bool fallback = false) {
        try {
            if (!_BuilderJsonHas(obj, key)) return fallback;
            return bool(obj[key]);
        } catch {
            string raw = _BuilderJsonStr(obj, key, fallback ? "true" : "false").ToLower();
            return raw == "1" || raw == "true" || raw == "yes" || raw == "on";
        }
    }

    bool _BuilderJsonIsAbsPath(const string &in rawPath) {
        if (rawPath.Length < 1) return false;
        if (rawPath[0] == 47 || rawPath[0] == 92) return true;
        if (rawPath.Length >= 2 && rawPath[1] == 58) return true;
        return false;
    }

    string _BuilderJsonResolvePath(const string &in rawPath) {
        string path = rawPath.Trim();
        if (path.Length == 0) return IO::FromStorageFolder("Exports/Builder/uinav_builder_doc.json");
        if (_BuilderJsonIsAbsPath(path)) return path;
        return IO::FromStorageFolder(path);
    }

    Json::Value@ _BuilderStringArrayToJson(const array<string> &in values) {
        Json::Value@ outObj = Json::Object();
        outObj["count"] = int(values.Length);
        for (uint i = 0; i < values.Length; ++i) {
            outObj["i" + i] = values[i];
        }
        return outObj;
    }

    void _BuilderJsonToStringArray(const Json::Value@ obj, array<string> &out values) {
        values.Resize(0);
        if (obj is null) return;
        int count = _BuilderJsonInt(obj, "count", 0);
        if (count < 0) count = 0;
        for (int i = 0; i < count; ++i) {
            values.InsertLast(_BuilderJsonStr(obj, "i" + i, ""));
        }
    }

    Json::Value@ _BuilderIntArrayToJson(const array<int> &in values) {
        Json::Value@ outObj = Json::Object();
        outObj["count"] = int(values.Length);
        for (uint i = 0; i < values.Length; ++i) {
            outObj["i" + i] = values[i];
        }
        return outObj;
    }

    void _BuilderJsonToIntArray(const Json::Value@ obj, array<int> &out values) {
        values.Resize(0);
        if (obj is null) return;
        int count = _BuilderJsonInt(obj, "count", 0);
        if (count < 0) count = 0;
        for (int i = 0; i < count; ++i) {
            values.InsertLast(_BuilderJsonInt(obj, "i" + i, -1));
        }
    }

    Json::Value@ _BuilderRawAttrsToJson(const dictionary &in rawAttrs) {
        Json::Value@ outObj = Json::Object();
        array<string> keys = rawAttrs.GetKeys();
        keys.SortAsc();
        outObj["count"] = int(keys.Length);
        for (uint i = 0; i < keys.Length; ++i) {
            string value = "";
            rawAttrs.Get(keys[i], value);
            Json::Value@ item = Json::Object();
            item["key"] = keys[i];
            item["value"] = value;
            outObj["i" + i] = item;
        }
        return outObj;
    }

    void _BuilderJsonToRawAttrs(const Json::Value@ obj, dictionary &inout rawAttrs) {
        rawAttrs.DeleteAll();
        if (obj is null) return;
        int count = _BuilderJsonInt(obj, "count", 0);
        if (count < 0) count = 0;
        for (int i = 0; i < count; ++i) {
            const Json::Value@ item = obj["i" + i];
            if (item is null) continue;
            string key = _BuilderJsonStr(item, "key", "");
            if (key.Length == 0) continue;
            rawAttrs.Set(key, _BuilderJsonStr(item, "value", ""));
        }
    }

    Json::Value@ _BuilderTypedPropsToJson(const BuilderTypedProps@ typed) {
        Json::Value@ obj = Json::Object();
        if (typed is null) return obj;

        obj["size_x"] = typed.size.x;
        obj["size_y"] = typed.size.y;
        obj["pos_x"] = typed.pos.x;
        obj["pos_y"] = typed.pos.y;
        obj["z"] = typed.z;
        obj["scale"] = typed.scale;
        obj["rot"] = typed.rot;
        obj["visible"] = typed.visible;
        obj["h_align"] = typed.hAlign;
        obj["v_align"] = typed.vAlign;

        obj["clip_active"] = typed.clipActive;
        obj["clip_pos_x"] = typed.clipPos.x;
        obj["clip_pos_y"] = typed.clipPos.y;
        obj["clip_size_x"] = typed.clipSize.x;
        obj["clip_size_y"] = typed.clipSize.y;

        obj["image"] = typed.image;
        obj["image_focus"] = typed.imageFocus;
        obj["alpha_mask"] = typed.alphaMask;
        obj["style"] = typed.style;
        obj["sub_style"] = typed.subStyle;
        obj["bg_color"] = typed.bgColor;
        obj["bg_color_focus"] = typed.bgColorFocus;
        obj["modulate_color"] = typed.modulateColor;
        obj["colorize"] = typed.colorize;
        obj["opacity"] = typed.opacity;
        obj["keep_ratio_mode"] = typed.keepRatioMode;
        obj["blend_mode"] = typed.blendMode;

        obj["text"] = typed.text;
        obj["text_size"] = typed.textSize;
        obj["text_font"] = typed.textFont;
        obj["text_prefix"] = typed.textPrefix;
        obj["text_color"] = typed.textColor;
        obj["max_line"] = typed.maxLine;
        obj["auto_new_line"] = typed.autoNewLine;
        obj["line_spacing"] = typed.lineSpacing;
        obj["italic_slope"] = typed.italicSlope;
        obj["append_ellipsis"] = typed.appendEllipsis;

        obj["value"] = typed.value;
        obj["text_format"] = typed.textFormat;
        obj["max_length"] = typed.maxLength;
        return obj;
    }

    BuilderTypedProps@ _BuilderJsonToTypedProps(const Json::Value@ obj) {
        BuilderTypedProps@ typed = BuilderTypedProps();
        if (obj is null) return typed;

        typed.size = vec2(_BuilderJsonFloat(obj, "size_x", typed.size.x), _BuilderJsonFloat(obj, "size_y", typed.size.y));
        typed.pos = vec2(_BuilderJsonFloat(obj, "pos_x", typed.pos.x), _BuilderJsonFloat(obj, "pos_y", typed.pos.y));
        typed.z = _BuilderJsonFloat(obj, "z", typed.z);
        typed.scale = _BuilderJsonFloat(obj, "scale", typed.scale);
        typed.rot = _BuilderJsonFloat(obj, "rot", typed.rot);
        typed.visible = _BuilderJsonBool(obj, "visible", typed.visible);
        typed.hAlign = _BuilderJsonStr(obj, "h_align", typed.hAlign);
        typed.vAlign = _BuilderJsonStr(obj, "v_align", typed.vAlign);

        typed.clipActive = _BuilderJsonBool(obj, "clip_active", typed.clipActive);
        typed.clipPos = vec2(_BuilderJsonFloat(obj, "clip_pos_x", typed.clipPos.x), _BuilderJsonFloat(obj, "clip_pos_y", typed.clipPos.y));
        typed.clipSize = vec2(_BuilderJsonFloat(obj, "clip_size_x", typed.clipSize.x), _BuilderJsonFloat(obj, "clip_size_y", typed.clipSize.y));

        typed.image = _BuilderJsonStr(obj, "image", typed.image);
        typed.imageFocus = _BuilderJsonStr(obj, "image_focus", typed.imageFocus);
        typed.alphaMask = _BuilderJsonStr(obj, "alpha_mask", typed.alphaMask);
        typed.style = _BuilderJsonStr(obj, "style", typed.style);
        typed.subStyle = _BuilderJsonStr(obj, "sub_style", typed.subStyle);
        typed.bgColor = _BuilderJsonStr(obj, "bg_color", typed.bgColor);
        typed.bgColorFocus = _BuilderJsonStr(obj, "bg_color_focus", typed.bgColorFocus);
        typed.modulateColor = _BuilderJsonStr(obj, "modulate_color", typed.modulateColor);
        typed.colorize = _BuilderJsonStr(obj, "colorize", typed.colorize);
        typed.opacity = _BuilderJsonFloat(obj, "opacity", typed.opacity);
        typed.keepRatioMode = _BuilderJsonInt(obj, "keep_ratio_mode", typed.keepRatioMode);
        typed.blendMode = _BuilderJsonInt(obj, "blend_mode", typed.blendMode);

        typed.text = _BuilderJsonStr(obj, "text", typed.text);
        typed.textSize = _BuilderJsonFloat(obj, "text_size", typed.textSize);
        typed.textFont = _BuilderJsonStr(obj, "text_font", typed.textFont);
        typed.textPrefix = _BuilderJsonStr(obj, "text_prefix", typed.textPrefix);
        typed.textColor = _BuilderJsonStr(obj, "text_color", typed.textColor);
        typed.maxLine = _BuilderJsonInt(obj, "max_line", typed.maxLine);
        typed.autoNewLine = _BuilderJsonBool(obj, "auto_new_line", typed.autoNewLine);
        typed.lineSpacing = _BuilderJsonFloat(obj, "line_spacing", typed.lineSpacing);
        typed.italicSlope = _BuilderJsonFloat(obj, "italic_slope", typed.italicSlope);
        typed.appendEllipsis = _BuilderJsonBool(obj, "append_ellipsis", typed.appendEllipsis);

        typed.value = _BuilderJsonStr(obj, "value", typed.value);
        typed.textFormat = _BuilderJsonInt(obj, "text_format", typed.textFormat);
        typed.maxLength = _BuilderJsonInt(obj, "max_length", typed.maxLength);
        return typed;
    }

    Json::Value@ _BuilderNodeToJson(const BuilderNode@ node) {
        Json::Value@ obj = Json::Object();
        if (node is null) return obj;

        obj["uid"] = node.uid;
        obj["kind"] = node.kind;
        obj["control_id"] = node.controlId;
        obj["tag_name"] = node.tagName;
        obj["parent_ix"] = node.parentIx;
        obj["child_ix"] = _BuilderIntArrayToJson(node.childIx);
        obj["typed"] = _BuilderTypedPropsToJson(node.typed);
        obj["raw_attrs"] = _BuilderRawAttrsToJson(node.rawAttrs);
        obj["classes"] = _BuilderStringArrayToJson(node.classes);
        obj["script_events"] = node.scriptEvents;

        Json::Value@ fidelity = Json::Object();
        fidelity["level"] = node.fidelity.level;
        fidelity["reasons"] = _BuilderStringArrayToJson(node.fidelity.reasons);
        obj["fidelity"] = fidelity;

        Json::Value@ span = Json::Object();
        span["start"] = node.span.start;
        span["end"] = node.span.end;
        obj["span"] = span;
        return obj;
    }

    BuilderNode@ _BuilderJsonToNode(const Json::Value@ obj) {
        if (obj is null) return null;

        BuilderNode@ node = BuilderNode();
        node.uid = _BuilderJsonStr(obj, "uid", "");
        node.kind = _BuilderJsonStr(obj, "kind", "frame");
        node.controlId = _BuilderJsonStr(obj, "control_id", "");
        node.tagName = _BuilderJsonStr(obj, "tag_name", node.kind);
        node.parentIx = _BuilderJsonInt(obj, "parent_ix", -1);
        _BuilderJsonToIntArray(obj["child_ix"], node.childIx);
        @node.typed = _BuilderJsonToTypedProps(obj["typed"]);
        _BuilderJsonToRawAttrs(obj["raw_attrs"], node.rawAttrs);
        _BuilderJsonToStringArray(obj["classes"], node.classes);
        node.scriptEvents = _BuilderJsonBool(obj, "script_events", false);

        const Json::Value@ fidelity = obj["fidelity"];
        node.fidelity.level = _BuilderJsonInt(fidelity, "level", 0);
        _BuilderJsonToStringArray(fidelity["reasons"], node.fidelity.reasons);

        const Json::Value@ span = obj["span"];
        node.span.start = _BuilderJsonInt(span, "start", -1);
        node.span.end = _BuilderJsonInt(span, "end", -1);

        _EnsureNodeDefaults(node);
        return node;
    }

    Json::Value@ _BuilderDiagToJson(const BuilderDiagnostic@ diag) {
        Json::Value@ obj = Json::Object();
        if (diag is null) return obj;
        obj["code"] = diag.code;
        obj["severity"] = diag.severity;
        obj["message"] = diag.message;
        obj["node_uid"] = diag.nodeUid;
        return obj;
    }

    BuilderDiagnostic@ _BuilderJsonToDiag(const Json::Value@ obj) {
        if (obj is null) return null;
        BuilderDiagnostic@ diag = BuilderDiagnostic();
        diag.code = _BuilderJsonStr(obj, "code", "");
        diag.severity = _BuilderJsonStr(obj, "severity", "");
        diag.message = _BuilderJsonStr(obj, "message", "");
        diag.nodeUid = _BuilderJsonStr(obj, "node_uid", "");
        return diag;
    }

    Json::Value@ _BuilderDocumentToJson(const BuilderDocument@ doc) {
        if (doc is null) return null;

        Json::Value@ root = Json::Object();
        root["format"] = doc.format;
        root["schema_version"] = doc.schemaVersion;
        root["name"] = doc.name;
        root["source_kind"] = doc.sourceKind;
        root["source_label"] = doc.sourceLabel;
        root["root_ix"] = doc.rootIx;
        root["original_xml"] = doc.originalXml;
        root["dirty"] = doc.dirty;

        root["script_block"] = doc.scriptBlock is null ? "" : doc.scriptBlock.raw;
        root["stylesheet_block"] = doc.stylesheetBlock is null ? "" : doc.stylesheetBlock.raw;

        Json::Value@ nodes = Json::Object();
        nodes["count"] = int(doc.nodes.Length);
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            nodes["i" + i] = _BuilderNodeToJson(doc.nodes[i]);
        }
        root["nodes"] = nodes;

        Json::Value@ diags = Json::Object();
        diags["count"] = int(doc.diagnostics.Length);
        for (uint i = 0; i < doc.diagnostics.Length; ++i) {
            diags["i" + i] = _BuilderDiagToJson(doc.diagnostics[i]);
        }
        root["diagnostics"] = diags;
        return root;
    }

    BuilderDocument@ _BuilderDocumentFromJson(const Json::Value@ root, const string &in sourceKind = "import_json", const string &in sourceLabel = "") {
        if (root is null) return null;

        BuilderDocument@ doc = BuilderDocument();
        doc.format = _BuilderJsonStr(root, "format", doc.format);
        doc.schemaVersion = _BuilderJsonStr(root, "schema_version", doc.schemaVersion);
        doc.name = _BuilderJsonStr(root, "name", doc.name);
        doc.sourceKind = sourceKind.Length > 0 ? sourceKind : _BuilderJsonStr(root, "source_kind", doc.sourceKind);
        doc.sourceLabel = sourceLabel.Length > 0 ? sourceLabel : _BuilderJsonStr(root, "source_label", "");
        doc.rootIx = _BuilderJsonInt(root, "root_ix", -1);
        doc.originalXml = _BuilderJsonStr(root, "original_xml", "");
        doc.dirty = _BuilderJsonBool(root, "dirty", false);

        @doc.scriptBlock = BuilderScriptBlock();
        doc.scriptBlock.raw = _BuilderJsonStr(root, "script_block", "");
        @doc.stylesheetBlock = BuilderStylesheetBlock();
        doc.stylesheetBlock.raw = _BuilderJsonStr(root, "stylesheet_block", "");

        const Json::Value@ nodes = root["nodes"];
        int nodeCount = _BuilderJsonInt(nodes, "count", 0);
        if (nodeCount < 0) nodeCount = 0;
        for (int i = 0; i < nodeCount; ++i) {
            doc.nodes.InsertLast(_BuilderJsonToNode(nodes["i" + i]));
        }

        const Json::Value@ diags = root["diagnostics"];
        int diagCount = _BuilderJsonInt(diags, "count", 0);
        if (diagCount < 0) diagCount = 0;
        for (int i = 0; i < diagCount; ++i) {
            auto diag = _BuilderJsonToDiag(diags["i" + i]);
            if (diag !is null) doc.diagnostics.InsertLast(diag);
        }

        _FinalizeDocument(doc);
        return doc;
    }

    BuilderDocument@ NewDocument() {
        auto doc = _NewDocument();
        _FinalizeDocument(doc);
        return doc;
    }

    BuilderDocument@ CloneDocument(const BuilderDocument@ src) {
        auto doc = _CloneDocument(src);
        _FinalizeDocument(doc);
        return doc;
    }

    BuilderNode@ NewNode(const string &in kind = "frame") {
        string normalizedKind = _NormalizePublicKind(kind);
        auto node = _NewNode(normalizedKind);
        if (normalizedKind == "generic") {
            string rawTag = kind.Trim().ToLower();
            node.tagName = rawTag.Length == 0 ? "frame" : rawTag;
        } else {
            node.tagName = normalizedKind;
        }
        _EnsureNodeDefaults(node);
        _InitAuthoringDefaults(node, 0);
        return node;
    }

    BuilderDocument@ ImportXml(const string &in xmlText, const string &in sourceKind = "import_xml", const string &in sourceLabel = "") {
        auto doc = ImportFromXml(xmlText, sourceKind, sourceLabel);
        _FinalizeDocument(doc);
        return doc;
    }

    BuilderDocument@ ImportJson(const string &in jsonText, const string &in sourceKind = "import_json", const string &in sourceLabel = "") {
        string txt = jsonText.Trim();
        if (txt.Length == 0) return null;
        try {
            auto root = Json::Parse(txt);
            return _BuilderDocumentFromJson(root, sourceKind, sourceLabel);
        } catch {
            return null;
        }
    }

    string ExportXml(const BuilderDocument@ doc) {
        return ExportToXml(doc);
    }

    string ExportJson(const BuilderDocument@ doc) {
        auto root = _BuilderDocumentToJson(doc);
        if (root is null) return "";
        try {
            return Json::Write(root);
        } catch {
            return "";
        }
    }

    bool SaveJsonToFile(const BuilderDocument@ doc, const string &in path = "") {
        auto root = _BuilderDocumentToJson(doc);
        if (root is null) return false;
        string outPath = _BuilderJsonResolvePath(path);
        _IO::File::WriteJsonFile(outPath, root);
        return true;
    }

    BuilderDocument@ LoadJsonFromFile(const string &in path, const string &in sourceKind = "import_json_file", const string &in sourceLabel = "") {
        string inPath = _BuilderJsonResolvePath(path);
        if (!IO::FileExists(inPath)) return null;
        string txt = _IO::File::ReadFileToEnd(inPath);
        if (txt.Trim().Length == 0) return null;
        BuilderDocument@ doc = ImportJson(txt, sourceKind, sourceLabel.Length > 0 ? sourceLabel : inPath);
        if (doc is null) return null;
        if (doc.sourceLabel.Length == 0) doc.sourceLabel = inPath;
        return doc;
    }

    int AppendRoot(BuilderDocument@ doc, BuilderNode@ node) {
        return AppendChild(doc, -1, node);
    }

    int AppendChild(BuilderDocument@ doc, int parentIx, BuilderNode@ node) {
        if (doc is null || node is null) return -1;

        _FinalizeDocument(doc);
        if (parentIx >= int(doc.nodes.Length)) return -1;

        if (parentIx >= 0) {
            auto parent = doc.nodes[uint(parentIx)];
            if (!_NodeCanContainChildren(parent)) return -1;
        }

        _EnsureNodeDefaults(node);
        if (_DocUidExists(doc, node.uid)) node.uid = "n" + (g_NextUid++);

        node.parentIx = parentIx;
        node.childIx.Resize(0);

        int ix = int(doc.nodes.Length);
        doc.nodes.InsertLast(node);
        if (parentIx >= 0) {
            auto parent = doc.nodes[uint(parentIx)];
            if (parent !is null) parent.childIx.InsertLast(ix);
        }

        doc.nodeByUid.Set(node.uid, ix);
        if (parentIx < 0 && doc.rootIx < 0) doc.rootIx = ix;
        doc.dirty = true;
        return ix;
    }

    void _MarkDeleteRecursiveDoc(const BuilderDocument@ doc, int nodeIx, array<bool> &inout marks) {
        if (doc is null) return;
        if (nodeIx < 0 || nodeIx >= int(marks.Length)) return;
        if (marks[uint(nodeIx)]) return;
        marks[uint(nodeIx)] = true;

        auto node = doc.nodes[uint(nodeIx)];
        if (node is null) return;
        for (uint i = 0; i < node.childIx.Length; ++i) {
            _MarkDeleteRecursiveDoc(doc, node.childIx[i], marks);
        }
    }

    bool DeleteNode(BuilderDocument@ doc, int nodeIx) {
        if (doc is null) return false;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return false;

        array<bool> marks;
        marks.Resize(doc.nodes.Length);
        for (uint i = 0; i < marks.Length; ++i) marks[i] = false;
        _MarkDeleteRecursiveDoc(doc, nodeIx, marks);

        array<int> remap;
        remap.Resize(doc.nodes.Length);
        for (uint i = 0; i < remap.Length; ++i) remap[i] = -1;

        array<BuilderNode@> newNodes;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            if (marks[i]) continue;
            remap[i] = int(newNodes.Length);
            newNodes.InsertLast(_CloneNode(doc.nodes[i]));
        }

        for (uint i = 0; i < newNodes.Length; ++i) {
            auto node = newNodes[i];
            if (node is null) continue;
            if (node.parentIx >= 0) node.parentIx = remap[uint(node.parentIx)];

            array<int> children;
            for (uint c = 0; c < node.childIx.Length; ++c) {
                int oldIx = node.childIx[c];
                if (oldIx < 0 || oldIx >= int(remap.Length)) continue;
                int mapped = remap[uint(oldIx)];
                if (mapped >= 0) children.InsertLast(mapped);
            }
            node.childIx = children;
        }

        doc.nodes = newNodes;
        doc.dirty = true;
        _FinalizeDocument(doc);
        return true;
    }

    bool _IsAncestorDoc(const BuilderDocument@ doc, int nodeIx, int maybeAncestor) {
        if (doc is null) return false;
        if (nodeIx < 0 || maybeAncestor < 0) return false;
        if (nodeIx >= int(doc.nodes.Length) || maybeAncestor >= int(doc.nodes.Length)) return false;

        int cur = nodeIx;
        while (cur >= 0 && cur < int(doc.nodes.Length)) {
            if (cur == maybeAncestor) return true;
            auto node = doc.nodes[uint(cur)];
            if (node is null) break;
            cur = node.parentIx;
        }
        return false;
    }

    bool MoveNode(BuilderDocument@ doc, int nodeIx, int newParentIx) {
        if (doc is null) return false;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return false;
        if (newParentIx >= int(doc.nodes.Length)) return false;
        if (newParentIx == nodeIx) return false;
        if (newParentIx >= 0 && _IsAncestorDoc(doc, newParentIx, nodeIx)) return false;

        auto node = doc.nodes[uint(nodeIx)];
        if (node is null) return false;
        int oldParent = node.parentIx;
        if (oldParent == newParentIx) return true;

        if (newParentIx >= 0) {
            auto parent = doc.nodes[uint(newParentIx)];
            if (!_NodeCanContainChildren(parent)) return false;
        }

        if (oldParent >= 0) {
            auto oldNode = doc.nodes[uint(oldParent)];
            if (oldNode !is null) {
                for (uint i = 0; i < oldNode.childIx.Length; ++i) {
                    if (oldNode.childIx[i] == nodeIx) {
                        oldNode.childIx.RemoveAt(i);
                        break;
                    }
                }
            }
        }

        node.parentIx = newParentIx;
        if (newParentIx >= 0) {
            auto newParent = doc.nodes[uint(newParentIx)];
            if (newParent !is null) newParent.childIx.InsertLast(nodeIx);
        }

        doc.dirty = true;
        _FinalizeDocument(doc);
        return true;
    }

    int FindFirstById(const BuilderDocument@ doc, const string &in controlId) {
        if (doc is null || controlId.Length == 0) return -1;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto node = doc.nodes[i];
            if (node !is null && node.controlId == controlId) return int(i);
        }
        return -1;
    }

    bool _NodeHasClass(const BuilderNode@ node, const string &in cls) {
        if (node is null || cls.Length == 0) return false;
        for (uint i = 0; i < node.classes.Length; ++i) {
            if (node.classes[i] == cls) return true;
        }
        return false;
    }

    bool _MatchSelectorTok(const BuilderNode@ node, UiNav::ML::_Tok@ tok) {
        if (node is null || tok is null) return false;
        if (tok.isAny) return true;
        if (tok.isId) return node.controlId == tok.id;
        if (tok.isClass) return _NodeHasClass(node, tok.cls);
        return false;
    }

    int _PickNthMatchAmongChildren(const BuilderDocument@ doc, int parentIx, UiNav::ML::_Tok@ tok) {
        if (doc is null || tok is null) return -1;
        if (parentIx < 0 || parentIx >= int(doc.nodes.Length)) return -1;

        auto parent = doc.nodes[uint(parentIx)];
        if (parent is null) return -1;

        if (tok.isIndex) {
            if (tok.index < 0) return -1;
            uint ix = uint(tok.index);
            if (ix >= parent.childIx.Length) return -1;
            return parent.childIx[ix];
        }

        int wantNth = tok.nth;
        int found = 0;
        for (uint i = 0; i < parent.childIx.Length; ++i) {
            int childIx = parent.childIx[i];
            if (childIx < 0 || childIx >= int(doc.nodes.Length)) continue;
            auto child = doc.nodes[uint(childIx)];
            if (_MatchSelectorTok(child, tok)) {
                if (found == wantNth) return childIx;
                found++;
            }
        }
        return -1;
    }

    int _PickNthMatchDescendant(const BuilderDocument@ doc, int rootIx, UiNav::ML::_Tok@ tok) {
        if (doc is null || tok is null) return -1;
        if (rootIx < 0 || rootIx >= int(doc.nodes.Length)) return -1;

        array<int> q;
        q.InsertLast(rootIx);

        int wantNth = tok.nth;
        int found = 0;
        uint head = 0;
        while (head < q.Length) {
            int curIx = q[head++];
            if (curIx < 0 || curIx >= int(doc.nodes.Length)) continue;
            auto cur = doc.nodes[uint(curIx)];
            if (cur is null) continue;

            if (!tok.isIndex && _MatchSelectorTok(cur, tok)) {
                if (found == wantNth) return curIx;
                found++;
            }

            for (uint i = 0; i < cur.childIx.Length; ++i) {
                q.InsertLast(cur.childIx[i]);
            }
        }

        return -1;
    }

    int ResolveSelector(const BuilderDocument@ doc, const string &in selector, int startIx = -1) {
        if (doc is null) return -1;
        string sel = selector.Trim();
        if (sel.Length == 0) return -1;

        auto toks = UiNav::ML::_GetTokChainCached(sel);
        if (toks is null || toks.Length == 0) return -1;

        int curIx = startIx;
        if (curIx < 0) curIx = doc.rootIx >= 0 ? doc.rootIx : _FirstRootIx(doc);
        if (curIx < 0 || curIx >= int(doc.nodes.Length)) return -1;

        for (uint i = 0; i < toks.Length; ++i) {
            auto tok = toks[i];
            if (tok is null) return -1;
            if (tok.descendant) {
                curIx = _PickNthMatchDescendant(doc, curIx, tok);
            } else {
                if (i == 0 && !tok.isIndex) {
                    auto cur = doc.nodes[uint(curIx)];
                    if (_MatchSelectorTok(cur, tok)) continue;
                }
                curIx = _PickNthMatchAmongChildren(doc, curIx, tok);
            }
            if (curIx < 0) return -1;
        }

        return curIx;
    }

    int StripFrameClipping(BuilderDocument@ doc) {
        if (doc is null) return 0;
        int changed = _SetFrameClipActiveInDoc(doc, false);
        if (changed > 0) doc.dirty = true;
        return changed;
    }

    bool CenterRoots(BuilderDocument@ doc) {
        if (doc is null) return false;
        bool changed = _CenterDocumentRoots(doc);
        if (changed) doc.dirty = true;
        return changed;
    }

    BuilderDocument@ CloneLiveLayer(const ManiaLinkReq@ req, bool stripFrameClipping = true, bool centerRoots = false) {
        if (req is null) return null;

        int layerIx = -1;
        auto layer = UiNav::Layers::FindLayer(req, layerIx);
        if (layer is null || layer.LocalPage is null || layer.LocalPage.MainFrame is null) return null;

        auto doc = _NewDocument();
        doc.sourceKind = "import_live_tree";
        doc.sourceLabel = "source=" + tostring(int(req.source)) + " layer=" + layerIx;
        doc.originalXml = _GetLayerXml(layer);

        auto st = _LiveTreeCloneState();
        _AppendLiveTreeNode(doc, layer.LocalPage.MainFrame, -1, 0, st);
        if (st.truncated) {
            _AddDiag(doc, "clone.truncated", "warn", "Live tree clone truncated at node/depth budget.");
        }

        _FinalizeDocument(doc);
        if (stripFrameClipping) _SetFrameClipActiveInDoc(doc, false);
        if (centerRoots) _CenterDocumentRoots(doc);
        doc.dirty = false;
        return doc;
    }

    CGameUILayer@ MountOwned(const string &in key, const BuilderDocument@ doc, ManiaLinkSource source = ManiaLinkSource::CurrentApp, bool visible = true) {
        if (doc is null) return null;
        string xml = ExportXml(doc);
        if (xml.Length == 0) return null;
        return UiNav::Layers::EnsureOwned(key, xml, source, visible);
    }

}
}
