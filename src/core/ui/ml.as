namespace UiNav {
namespace ML {

    CGameManialinkFrame@ GetRootFrame(CGameUILayer@ layer) {
        if (layer is null) return null;
        auto page = layer.LocalPage;
        if (page is null) return null;
        return page.MainFrame;
    }

    uint _ChildrenLen(CGameManialinkControl@ node) {
        auto f = cast<CGameManialinkFrame>(node);
        if (f is null) return 0;
        return f.Controls.Length;
    }

    CGameManialinkControl@ _ChildAt(CGameManialinkControl@ node, uint idx) {
        auto f = cast<CGameManialinkFrame>(node);
        if (f is null) return null;
        if (idx >= f.Controls.Length) return null;
        return f.Controls[idx];
    }

    CControlBase@ _TryGetControl(CGameManialinkControl@ n) {
        if (n is null) return null;
        CControlBase@ c = null;
        try {
            @c = n.Control;
        } catch {
            @c = null;
        }
        return c;
    }

    CGameManialinkControl@ _TryGetParent(CGameManialinkControl@ n) {
        if (n is null) return null;
        CGameManialinkControl@ p = null;
        try {
            @p = n.Parent;
        } catch {
            @p = null;
        }
        return p;
    }

    string TypeName(CGameManialinkControl@ n) {
        if (n is null) return "null";
        if (cast<CGameManialinkFrame>(n) !is null) return "Frame";
        if (cast<CGameManialinkLabel>(n) !is null) return "Label";
        if (cast<CGameManialinkQuad>(n) !is null) return "Quad";
        if (cast<CGameManialinkEntry>(n) !is null) return "Entry";
        return "Control";
    }

    string ControlId(CGameManialinkControl@ n) {
        if (n is null) return "";
        try {
            return n.ControlId;
        } catch {
            return "";
        }
    }

    bool HasClass(CGameManialinkControl@ n, const string &in cls) {
        if (n is null || cls.Length == 0) return false;
        try {
            return n.HasClass(cls);
        } catch {
            return false;
        }
    }

    string _BuildIndexPath(CGameManialinkControl@ n) {
        if (n is null) return "";

        array<string> reversedParts;
        auto cur = n;
        uint depth = 0;
        while (cur !is null && depth < 256) {
            auto parent = _TryGetParent(cur);
            if (parent is null) break;

            auto pf = cast<CGameManialinkFrame@>(parent);
            if (pf is null) return "";

            int childIx = -1;
            for (uint i = 0; i < pf.Controls.Length; ++i) {
                if (pf.Controls[i] is cur) {
                    childIx = int(i);
                    break;
                }
            }
            if (childIx < 0) return "";

            reversedParts.InsertLast("" + childIx);
            @cur = parent;
            depth++;
        }

        if (depth >= 256) return "";
        if (reversedParts.Length == 0) return ".";

        string path = "";
        for (int i = int(reversedParts.Length) - 1; i >= 0; --i) {
            if (path.Length > 0) path += "/";
            path += reversedParts[uint(i)];
        }
        return path;
    }

    bool TryReadText(CGameManialinkControl@ n, string &out text) {
        text = "";
        if (n is null) return false;
        auto c = _TryGetControl(n);
        if (c is null) return false;
        return UiNav::TryReadText(c, text);
    }

    bool HasReadableText(CGameManialinkControl@ n) {
        string text;
        return TryReadText(n, text);
    }

    string ReadText(CGameManialinkControl@ n) {
        string text;
        if (!TryReadText(n, text)) return "";
        return text;
    }

    bool IsVisibleSelf(CGameManialinkControl@ n) {
        if (n is null) return false;
        try {
            return n.Visible;
        } catch {
            return false;
        }
    }

    bool IsEffectivelyVisible(CGameManialinkControl@ n) {
        if (!IsVisibleSelf(n)) return false;

        auto cur = _TryGetParent(n);
        uint depth = 0;
        while (cur !is null && depth < 256) {
            if (!IsVisibleSelf(cur)) return false;
            @cur = _TryGetParent(cur);
            depth++;
        }

        auto c = _TryGetControl(n);
        if (c !is null && !UiNav::IsEffectivelyVisible(c)) return false;
        return true;
    }

    CGameManialinkControl@ FindFirstById(CGameManialinkControl@ root, const string &in id) {
        if (root is null || id.Length == 0) return null;

        // BFS
        array<CGameManialinkControl@> q;
        q.InsertLast(root);

        uint head = 0;
        while (head < q.Length) {
            auto cur = q[head++];
            if (cur is null) continue;

            if (ControlId(cur) == id) return cur;

            uint len = _ChildrenLen(cur);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(cur, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }

        return null;
    }

    CGameManialinkControl@ FindFirstByClass(CGameManialinkControl@ root, const string &in cls) {
        if (root is null || cls.Length == 0) return null;

        array<CGameManialinkControl@> q;
        q.InsertLast(root);

        uint head = 0;
        while (head < q.Length) {
            auto cur = q[head++];
            if (cur is null) continue;

            if (HasClass(cur, cls)) return cur;

            uint len = _ChildrenLen(cur);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(cur, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }

        return null;
    }

    class _Tok {
        bool descendant = false;
        int  nth = 0;
        bool isIndex = false;
        int  index = -1;
        bool isId = false;
        string id;
        bool isClass = false;
        string cls;
        bool isAny = false;
    }

    bool _IsAllDigits(const string &in s) {
        int len = int(s.Length);
        if (len == 0) return false;
        for (int i = 0; i < len; ++i) {
            string ch = s.SubStr(i, 1);
            if (ch < "0" || ch > "9") return false;
        }
        return true;
    }

    _Tok@ _ParseTok(const string &in raw) {
        auto t = _Tok();
        string s = raw.Trim();

        if (s.StartsWith("**")) {
            t.descendant = true;
            s = s.SubStr(2).Trim();
        }

        int colon = s.LastIndexOf(":");
        if (colon > 0) {
            string right = s.SubStr(colon + 1).Trim();
            if (_IsAllDigits(right)) {
                t.nth = Text::ParseInt(right);
                s = s.SubStr(0, colon).Trim();
            }
        }

        if (s.Length == 0 || s == "*") {
            t.isAny = true;
            return t;
        }

        if (_IsAllDigits(s)) {
            t.isIndex = true;
            t.index = Text::ParseInt(s);
            return t;
        }

        if (s.StartsWith("#")) {
            t.isId = true;
            t.id = s.SubStr(1);
            return t;
        }

        if (s.StartsWith(".")) {
            t.isClass = true;
            t.cls = s.SubStr(1);
            return t;
        }

        return null;
    }

    bool _MatchTok(CGameManialinkControl@ n, _Tok@ tok) {
        if (n is null || tok is null) return false;
        if (tok.isAny) return true;
        if (tok.isId) return ControlId(n) == tok.id;
        if (tok.isClass) return HasClass(n, tok.cls);
        return false;
    }

    CGameManialinkControl@ _PickNthMatchAmongChildren(CGameManialinkControl@ parent, _Tok@ tok) {
        if (parent is null || tok is null) return null;
        auto f = cast<CGameManialinkFrame>(parent);
        if (f is null) return null;

        if (tok.isIndex) {
            if (tok.index < 0) return null;
            uint ix = uint(tok.index);
            if (ix >= f.Controls.Length) return null;
            return f.Controls[ix];
        }

        int wantNth = tok.nth;
        int found = 0;
        for (uint i = 0; i < f.Controls.Length; ++i) {
            auto ch = f.Controls[i];
            if (ch is null) continue;
            if (_MatchTok(ch, tok)) {
                if (found == wantNth) return ch;
                found++;
            }
        }
        return null;
    }

    CGameManialinkControl@ _PickNthMatchDescendant(CGameManialinkControl@ root, _Tok@ tok) {
        if (root is null || tok is null) return null;

        array<CGameManialinkControl@> q;
        q.InsertLast(root);

        int wantNth = tok.nth;
        int found = 0;

        uint head = 0;
        while (head < q.Length) {
            auto cur = q[head++];
            if (cur is null) continue;

            if (!tok.isIndex && _MatchTok(cur, tok)) {
                if (found == wantNth) return cur;
                found++;
            }

            uint len = _ChildrenLen(cur);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(cur, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }

        return null;
    }

    class _SelTokCacheNode {
        string key;
        _SelTokCacheNode@ prev = null;
        _SelTokCacheNode@ next = null;
    }

    dictionary g_SelTokCache;
    dictionary g_SelTokCacheNodes;
    _SelTokCacheNode@ g_SelTokCacheHead = null;
    _SelTokCacheNode@ g_SelTokCacheTail = null;
    uint g_SelTokCacheSize = 0;
    const uint kSelTokCacheMax = 512;
    uint g_SelTokCacheHits = 0;
    uint g_SelTokCacheMisses = 0;
    uint g_SelTokCacheEvictions = 0;

    void _SelTokCacheDetach(_SelTokCacheNode@ n) {
        if (n is null) return;

        if (n.prev !is null) @n.prev.next = n.next;
        else @g_SelTokCacheHead = n.next;

        if (n.next !is null) @n.next.prev = n.prev;
        else @g_SelTokCacheTail = n.prev;

        @n.prev = null;
        @n.next = null;
    }

    void _SelTokCacheAttachFront(_SelTokCacheNode@ n) {
        if (n is null) return;
        @n.prev = null;
        @n.next = g_SelTokCacheHead;
        if (g_SelTokCacheHead !is null) @g_SelTokCacheHead.prev = n;
        @g_SelTokCacheHead = n;
        if (g_SelTokCacheTail is null) @g_SelTokCacheTail = n;
    }

    void _SelTokCacheTouch(const string &in sel) {
        _SelTokCacheNode@ n;
        if (!g_SelTokCacheNodes.Get(sel, @n) || n is null) return;
        if (g_SelTokCacheHead is n) return;
        _SelTokCacheDetach(n);
        _SelTokCacheAttachFront(n);
    }

    void _SelTokCachePut(const string &in sel, array<_Tok@>@ toks) {
        if (sel.Length == 0 || toks is null) return;

        array<_Tok@>@ old;
        bool existed = g_SelTokCache.Get(sel, @old);
        g_SelTokCache.Set(sel, @toks);
        if (existed) {
            _SelTokCacheTouch(sel);
            return;
        }

        _SelTokCacheNode@ n = _SelTokCacheNode();
        n.key = sel;
        g_SelTokCacheNodes.Set(sel, @n);
        _SelTokCacheAttachFront(n);
        g_SelTokCacheSize++;

        if (g_SelTokCacheSize > kSelTokCacheMax && g_SelTokCacheTail !is null) {
            string victim = g_SelTokCacheTail.key;
            _SelTokCacheDetach(g_SelTokCacheTail);
            g_SelTokCache.Delete(victim);
            g_SelTokCacheNodes.Delete(victim);
            if (g_SelTokCacheSize > 0) g_SelTokCacheSize--;
            g_SelTokCacheEvictions++;
        }
    }

    uint SelectorCacheHits() { return g_SelTokCacheHits; }
    uint SelectorCacheMisses() { return g_SelTokCacheMisses; }
    uint SelectorCacheEvictions() { return g_SelTokCacheEvictions; }
    uint SelectorCacheSize() { return g_SelTokCacheSize; }
    float SelectorCacheHitRate() {
        uint total = g_SelTokCacheHits + g_SelTokCacheMisses;
        if (total == 0) return 0.0f;
        return float(g_SelTokCacheHits) / float(total);
    }

    void ResetSelectorCacheStats() {
        g_SelTokCacheHits = 0;
        g_SelTokCacheMisses = 0;
        g_SelTokCacheEvictions = 0;
    }

    array<_Tok@>@ _GetTokChainCached(const string &in sel) {
        array<_Tok@>@ toks;
        if (g_SelTokCache.Get(sel, @toks)) {
            g_SelTokCacheHits++;
            _SelTokCacheTouch(sel);
            return toks;
        }

        g_SelTokCacheMisses++;

        @toks = array<_Tok@>();
        string[] parts = sel.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            auto tok = _ParseTok(parts[i]);
            if (tok is null) return null;
            toks.InsertLast(tok);
        }

        _SelTokCachePut(sel, @toks);
        return toks;
    }

    CGameManialinkControl@ ResolveSelectorPrepared(array<_Tok@>@ toks, CGameManialinkControl@ start) {
        if (start is null) return null;
        if (toks is null) return null;
        if (toks.Length == 0) return start;

        CGameManialinkControl@ cur = start;

        for (uint i = 0; i < toks.Length; ++i) {
            auto tok = toks[i];
            if (tok is null) return null;

            if (tok.descendant) {
                @cur = _PickNthMatchDescendant(cur, tok);
            } else {
                if (i == 0 && !tok.isIndex && _MatchTok(cur, tok)) {
                    continue;
                }
                @cur = _PickNthMatchAmongChildren(cur, tok);
            }

            if (cur is null) return null;
        }

        return cur;
    }

    CGameManialinkControl@ ResolveSelector(const string &in selector, CGameManialinkControl@ start) {
        if (start is null) return null;
        string sel = selector.Trim();
        if (sel.Length == 0) return start;

        auto toks = _GetTokChainCached(sel);
        if (toks is null) return null;
        return ResolveSelectorPrepared(toks, start);
    }

    bool Show(CGameManialinkControl@ n) {
        if (n is null) return false;
        n.Show();
        return true;
    }

    bool Hide(CGameManialinkControl@ n) {
        if (n is null) return false;
        n.Hide();
        return true;
    }

    bool Click(CGameManialinkControl@ n, bool childFallback = true) {
        if (n is null) return false;

        auto c = _TryGetControl(n);
        if (c !is null) {
            return UiNav::ClickControlNode(c, childFallback);
        }

        return false;
    }

    bool CanClick(CGameManialinkControl@ n, bool childFallback = true) {
        if (n is null) return false;
        auto c = _TryGetControl(n);
        return c !is null && UiNav::CanClick(c, childFallback);
    }

    bool SetText(CGameManialinkControl@ n, const string &in text) {
        if (n is null) return false;

        CGameManialinkEntry@ e = cast<CGameManialinkEntry>(n);
        if (e !is null) {
            e.SetText(text, true);
            return true;
        }

        auto c = _TryGetControl(n);
        if (c is null) return false;
        return UiNav::SetTextControlNode(c, text);
    }

    bool CanSetText(CGameManialinkControl@ n) {
        if (n is null) return false;
        if (cast<CGameManialinkEntry>(n) !is null) return true;
        auto c = _TryGetControl(n);
        return c !is null && UiNav::CanSetText(c);
    }

    string g_SnapshotClipboardJson = "";

    bool _is_abs_path(const string &in p) {
        if (p.Length < 1) return false;
        if (p[0] == 47 || p[0] == 92) return true; // '/' or '\'
        if (p.Length >= 2 && p[1] == 58) return true; // 'C:'
        return false;
    }

    string _resolve_snapshot_path(const string &in p) {
        string path = p.Trim();
        if (path.Length == 0) return IO::FromStorageFolder("Exports/ManiaLinks/uinav_ml_snapshot.json");
        if (_is_abs_path(path)) return path;
        return IO::FromStorageFolder(path);
    }

    string _resolve_style_pack_path(const string &in p) {
        string path = p.Trim();
        if (path.Length == 0) return IO::FromStorageFolder("Exports/ManiaLinks/uinav_ml_style_pack.json");
        if (_is_abs_path(path)) return path;
        return IO::FromStorageFolder(path);
    }

    bool _jhas(const Json::Value@ obj, const string &in key) {
        try {
            return obj !is null && obj.HasKey(key);
        } catch {
            return false;
        }
    }

    string _jstr(const Json::Value@ obj, const string &in key, const string &in fallback = "") {
        try {
            if (!_jhas(obj, key)) return fallback;
            return string(obj[key]);
        } catch {
            return fallback;
        }
    }

    int _jint(const Json::Value@ obj, const string &in key, int fallback = 0) {
        try {
            if (!_jhas(obj, key)) return fallback;
            return int(obj[key]);
        } catch {
            return fallback;
        }
    }

    float _jfloat(const Json::Value@ obj, const string &in key, float fallback = 0.0f) {
        try {
            if (!_jhas(obj, key)) return fallback;
            return float(obj[key]);
        } catch {
            return fallback;
        }
    }

    bool _jbool(const Json::Value@ obj, const string &in key, bool fallback = false) {
        try {
            if (!_jhas(obj, key)) return fallback;
            return bool(obj[key]);
        } catch {
            string s = _jstr(obj, key, fallback ? "true" : "false").ToLower();
            return s == "1" || s == "true" || s == "yes";
        }
    }

    void _SnapshotNodeInto(CGameManialinkControl@ n, Json::Value@ outObj, bool includeChildren, int maxDepth, int depth, const string &in idxPath, bool includeTextValues = true) {
        if (n is null || outObj is null) return;

        outObj["format"] = "uinav_ml_snapshot_v1";
        outObj["type"] = TypeName(n);
        outObj["index_path"] = idxPath;
        outObj["control_id"] = n.ControlId;
        outObj["visible"] = n.Visible;
        outObj["relative_x"] = n.RelativePosition_V3.x;
        outObj["relative_y"] = n.RelativePosition_V3.y;
        outObj["size_x"] = n.Size.x;
        outObj["size_y"] = n.Size.y;
        outObj["z_index"] = n.ZIndex;
        outObj["h_align"] = int(n.HorizontalAlign);
        outObj["v_align"] = int(n.VerticalAlign);

        if (includeTextValues) {
            string text = ReadText(n);
            if (text.Length > 0) outObj["text"] = text;

            auto lbl = cast<CGameManialinkLabel@>(n);
            if (lbl !is null) outObj["label_value"] = lbl.Value;

            auto entry = cast<CGameManialinkEntry@>(n);
            if (entry !is null) outObj["entry_value"] = entry.Value;
        }

        auto classes = n.ControlClasses;
        if (classes.Length > 0) {
            Json::Value@ cls = Json::Object();
            cls["count"] = int(classes.Length);
            for (uint i = 0; i < classes.Length; ++i) {
                cls["i" + i] = classes[i];
            }
            outObj["classes"] = cls;
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
            string childPath = idxPath.Length == 0 ? ("" + i) : (idxPath + "/" + i);
            _SnapshotNodeInto(ch, child, includeChildren, maxDepth, depth + 1, childPath, includeTextValues);
            children["i" + i] = child;
        }
        outObj["children"] = children;
    }

    Json::Value@ SnapshotNode(CGameManialinkControl@ n, bool includeChildren = false, int maxDepth = 1) {
        if (n is null) return null;
        if (maxDepth < 0) maxDepth = 0;
        Json::Value@ snap = Json::Object();
        _SnapshotNodeInto(n, snap, includeChildren, maxDepth, 0, "", true);
        return snap;
    }

    Json::Value@ SnapshotStyleNode(CGameManialinkControl@ n, bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false) {
        if (n is null) return null;
        if (maxDepth < 0) maxDepth = 0;
        Json::Value@ snap = Json::Object();
        _SnapshotNodeInto(n, snap, includeChildren, maxDepth, 0, "", includeTextValues);
        snap["format"] = includeTextValues ? "uinav_ml_style_snapshot_v1_text" : "uinav_ml_style_snapshot_v1";
        return snap;
    }

    bool CopySnapshotToClipboard(CGameManialinkControl@ n, bool includeChildren = false, int maxDepth = 1) {
        auto snap = SnapshotNode(n, includeChildren, maxDepth);
        if (snap is null) return false;
        g_SnapshotClipboardJson = Json::Write(snap);
        return g_SnapshotClipboardJson.Length > 0;
    }

    string GetClipboardSnapshotJson() {
        return g_SnapshotClipboardJson;
    }

    Json::Value@ GetClipboardSnapshot() {
        if (g_SnapshotClipboardJson.Length == 0) return null;
        try { return Json::Parse(g_SnapshotClipboardJson); } catch { return null; }
    }

    bool SetClipboardSnapshot(const Json::Value@ snap) {
        if (snap is null) return false;
        g_SnapshotClipboardJson = Json::Write(snap);
        return g_SnapshotClipboardJson.Length > 0;
    }

    bool SetClipboardSnapshotJson(const string &in jsonText) {
        string txt = jsonText.Trim();
        if (txt.Length == 0) return false;
        try {
            auto parsed = Json::Parse(txt);
            return SetClipboardSnapshot(parsed);
        } catch {
            return false;
        }
    }

    bool SaveSnapshotToFile(CGameManialinkControl@ n, const string &in path, bool includeChildren = false, int maxDepth = 1) {
        auto snap = SnapshotNode(n, includeChildren, maxDepth);
        if (snap is null) return false;
        string outPath = _resolve_snapshot_path(path);
        _IO::File::WriteJsonFile(outPath, snap);
        return true;
    }

    bool SaveClipboardSnapshotToFile(const string &in path) {
        auto snap = GetClipboardSnapshot();
        if (snap is null) return false;
        string outPath = _resolve_snapshot_path(path);
        _IO::File::WriteJsonFile(outPath, snap);
        return true;
    }

    Json::Value@ LoadSnapshotFromFile(const string &in path) {
        string inPath = _resolve_snapshot_path(path);
        if (!IO::FileExists(inPath)) return null;
        string txt = _IO::File::ReadFileToEnd(inPath);
        if (txt.Length == 0) return null;
        try { return Json::Parse(txt); } catch { return null; }
    }

    Json::Value@ NewStylePack() {
        Json::Value@ pack = Json::Object();
        pack["format"] = "uinav_ml_style_pack_v1";
        pack["generated_at"] = Time::FormatString("%Y-%m-%d %H:%M:%S");
        pack["count"] = 0;
        Json::Value@ entries = Json::Object();
        entries["count"] = 0;
        pack["entries"] = entries;
        return pack;
    }

    int StylePackEntryCount(const Json::Value@ pack) {
        if (pack is null) return 0;
        if (!_jhas(pack, "entries")) return 0;
        const Json::Value@ entries = pack["entries"];
        int count = _jint(entries, "count", 0);
        if (count < 0) count = 0;
        return count;
    }

    bool _EnsureStylePack(Json::Value@ pack) {
        if (pack is null) return false;
        if (!_jhas(pack, "format")) pack["format"] = "uinav_ml_style_pack_v1";
        if (!_jhas(pack, "generated_at")) pack["generated_at"] = Time::FormatString("%Y-%m-%d %H:%M:%S");
        if (!_jhas(pack, "entries")) {
            Json::Value@ entries = Json::Object();
            entries["count"] = 0;
            pack["entries"] = entries;
        }
        int count = StylePackEntryCount(pack);
        pack["count"] = count;
        return true;
    }

    bool StylePackAddEntry(Json::Value@ pack, CGameManialinkControl@ n, const string &in selector = "", bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false, const string &in name = "") {
        if (n is null || !_EnsureStylePack(pack)) return false;

        int count = StylePackEntryCount(pack);
        Json::Value@ snap = SnapshotStyleNode(n, includeChildren, maxDepth, includeTextValues);
        if (snap is null) return false;

        string selectorTrim = selector.Trim();
        string indexPath = _BuildIndexPath(n);
        if (selectorTrim.Length == 0 && indexPath.Length == 0) return false;

        Json::Value@ entry = Json::Object();
        string type = TypeName(n);
        string entryName = name.Trim();
        if (entryName.Length == 0) {
            entryName = type;
            if (n.ControlId.Length > 0) entryName += " #" + n.ControlId;
        }

        entry["name"] = entryName;
        entry["type"] = type;
        entry["control_id"] = n.ControlId;
        entry["selector"] = selectorTrim;
        entry["index_path"] = indexPath;
        entry["snapshot"] = snap;

        Json::Value@ entries = pack["entries"];
        entries["i" + count] = entry;
        entries["count"] = count + 1;
        pack["entries"] = entries;
        pack["count"] = count + 1;
        return true;
    }

    bool StylePackAddEntryBySelector(Json::Value@ pack, CGameManialinkControl@ root, const string &in selector, bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false, const string &in name = "") {
        if (root is null) return false;
        string sel = selector.Trim();
        if (sel.Length == 0) return false;
        auto n = ResolveSelector(sel, root);
        if (n is null) return false;
        return StylePackAddEntry(pack, n, sel, includeChildren, maxDepth, includeTextValues, name);
    }

    int StylePackApply(CGameManialinkControl@ root, const Json::Value@ pack, bool applyChildren = false) {
        if (root is null || pack is null) return 0;
        if (!_jhas(pack, "entries")) return 0;

        const Json::Value@ entries = pack["entries"];
        int count = _jint(entries, "count", 0);
        if (count < 0) count = 0;

        int applied = 0;
        for (int i = 0; i < count; ++i) {
            string k = "i" + i;
            if (!_jhas(entries, k)) continue;
            const Json::Value@ entry = entries[k];
            if (entry is null) continue;

            string selector = _jstr(entry, "selector", "").Trim();
            string indexPath = _jstr(entry, "index_path", "").Trim();

            CGameManialinkControl@ dst = null;
            if (selector.Length > 0) {
                @dst = ResolveSelector(selector, root);
            }
            if (dst is null && indexPath == ".") {
                @dst = root;
            }
            if (dst is null && indexPath.Length > 0) {
                @dst = ResolveSelector(indexPath, root);
            }
            if (dst is null) continue;

            const Json::Value@ snap = null;
            if (_jhas(entry, "snapshot")) {
                @snap = entry["snapshot"];
            } else if (_jhas(entry, "snapshot_json")) {
                string snapJson = _jstr(entry, "snapshot_json", "");
                if (snapJson.Length > 0) {
                    try { @snap = Json::Parse(snapJson); } catch { @snap = null; }
                }
            }
            if (snap is null) continue;

            if (ApplySnapshotToNode(dst, snap, applyChildren)) {
                applied++;
            }
        }

        return applied;
    }

    string StylePackToJson(const Json::Value@ pack) {
        if (pack is null) return "";
        try { return Json::Write(pack); } catch { return ""; }
    }

    Json::Value@ StylePackFromJson(const string &in jsonText) {
        string txt = jsonText.Trim();
        if (txt.Length == 0) return null;
        try { return Json::Parse(txt); } catch { return null; }
    }

    bool SaveStylePackToFile(const Json::Value@ pack, const string &in path) {
        if (pack is null) return false;
        string outPath = _resolve_style_pack_path(path);
        _IO::File::WriteJsonFile(outPath, pack);
        return true;
    }

    Json::Value@ LoadStylePackFromFile(const string &in path) {
        string inPath = _resolve_style_pack_path(path);
        if (!IO::FileExists(inPath)) return null;
        string txt = _IO::File::ReadFileToEnd(inPath);
        if (txt.Length == 0) return null;
        try { return Json::Parse(txt); } catch { return null; }
    }

    bool _ApplySnapshotInto(CGameManialinkControl@ n, const Json::Value@ snap, bool applyChildren) {
        if (n is null || snap is null) return false;

        n.Visible = _jbool(snap, "visible", n.Visible);
        n.RelativePosition_V3 = vec2(
            _jfloat(snap, "relative_x", n.RelativePosition_V3.x),
            _jfloat(snap, "relative_y", n.RelativePosition_V3.y)
        );
        n.Size = vec2(
            _jfloat(snap, "size_x", n.Size.x),
            _jfloat(snap, "size_y", n.Size.y)
        );
        n.ZIndex = _jfloat(snap, "z_index", n.ZIndex);
        n.HorizontalAlign = CGameManialinkControl::EAlignHorizontal(_jint(snap, "h_align", int(n.HorizontalAlign)));
        n.VerticalAlign = CGameManialinkControl::EAlignVertical(_jint(snap, "v_align", int(n.VerticalAlign)));

        auto lbl = cast<CGameManialinkLabel@>(n);
        if (lbl !is null && _jhas(snap, "label_value")) {
            lbl.Value = _jstr(snap, "label_value", lbl.Value);
        }

        auto entry = cast<CGameManialinkEntry@>(n);
        if (entry !is null) {
            if (_jhas(snap, "entry_value")) {
                entry.SetText(_jstr(snap, "entry_value", entry.Value), true);
            } else if (_jhas(snap, "text")) {
                entry.SetText(_jstr(snap, "text", entry.Value), true);
            }
        }

        if (!applyChildren) return true;

        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null || !_jhas(snap, "children")) return true;

        const Json::Value@ children = snap["children"];
        int count = _jint(children, "count", int(f.Controls.Length));
        if (count < 0) count = 0;

        int cap = Math::Min(count, int(f.Controls.Length));
        for (int i = 0; i < cap; ++i) {
            string k = "i" + i;
            if (!_jhas(children, k)) continue;
            auto ch = f.Controls[uint(i)];
            if (ch is null) continue;
            _ApplySnapshotInto(ch, children[k], true);
        }

        return true;
    }

    bool ApplySnapshotToNode(CGameManialinkControl@ n, const Json::Value@ snap, bool applyChildren = false) {
        return _ApplySnapshotInto(n, snap, applyChildren);
    }

    bool ApplyClipboardSnapshot(CGameManialinkControl@ n, bool applyChildren = false) {
        auto snap = GetClipboardSnapshot();
        if (snap is null) return false;
        return ApplySnapshotToNode(n, snap, applyChildren);
    }

    

string _xml_escape(const string &in s) {
        string r = s;
        r = r.Replace("&", "&amp;");
        r = r.Replace("\"", "&quot;");
        r = r.Replace("<", "&lt;");
        r = r.Replace(">", "&gt;");
        return r;
    }

    string _snapshot_tag(const string &in rawType) {
        string t = rawType.Trim();
        if (t.Length == 0) return "frame";
        string tl = t.ToLower();
        if (tl == "frame") return "frame";
        if (tl == "label") return "label";
        if (tl == "quad") return "quad";
        if (tl == "entry") return "entry";
        if (tl.Contains("cgamemanialink")) {
            int ix = t.IndexOf("CGameManialink");
            if (ix >= 0) {
                string tail = t.SubStr(ix + 14).ToLower();
                if (tail.Length > 0) return tail;
            }
        }
        if (tl == "control") return "frame";
        return tl;
    }

    string _snapshot_to_xml_node(const Json::Value@ snap, bool includeChildren, int depth) {
        if (snap is null) return "";
        string indent = "";
        for (int i = 0; i < depth; ++i) indent += "  ";

        string tag = _snapshot_tag(_jstr(snap, "type", "frame"));
        string id = _jstr(snap, "control_id", "");
        float rx = _jfloat(snap, "relative_x", 0.0f);
        float ry = _jfloat(snap, "relative_y", 0.0f);
        float sx = _jfloat(snap, "size_x", 0.0f);
        float sy = _jfloat(snap, "size_y", 0.0f);
        float z = _jfloat(snap, "z_index", 0.0f);
        bool vis = _jbool(snap, "visible", true);

        string attrs = "";
        if (id.Length > 0) attrs += " id=\"" + _xml_escape(id) + "\"";
        attrs += " pos=\"" + rx + " " + ry + "\"";
        attrs += " size=\"" + sx + " " + sy + "\"";
        attrs += " z=\"" + z + "\"";
        if (!vis) attrs += " visible=\"0\"";

        string labelValue = _jstr(snap, "label_value", _jstr(snap, "text", ""));
        string entryValue = _jstr(snap, "entry_value", _jstr(snap, "text", ""));

        bool wantsChildren = includeChildren && _jhas(snap, "children");
        bool selfClosing = !wantsChildren;
        if (!selfClosing && tag != "frame" && tag != "manialink") {
            selfClosing = true;
        }

        if (tag == "label" && labelValue.Length > 0) attrs += " text=\"" + _xml_escape(labelValue) + "\"";
        if (tag == "entry" && entryValue.Length > 0) attrs += " default=\"" + _xml_escape(entryValue) + "\"";

        if (selfClosing) {
            return indent + "<" + tag + attrs + " />";
        }

        string xmlOut = indent + "<" + tag + attrs + ">\n";
        const Json::Value@ children = snap["children"];
        int count = _jint(children, "count", 0);
        if (count < 0) count = 0;
        for (int i = 0; i < count; ++i) {
            string k = "i" + i;
            if (!_jhas(children, k)) continue;
            string ch = _snapshot_to_xml_node(children[k], includeChildren, depth + 1);
            if (ch.Length > 0) xmlOut += ch + "\n";
        }
        xmlOut += indent + "</" + tag + ">";
        return xmlOut;
    }

    string SnapshotToXml(const Json::Value@ snap, bool includeChildren = true) {
        return _snapshot_to_xml_node(snap, includeChildren, 0);
    }

    string ClipboardSnapshotToXml(bool includeChildren = true) {
        auto snap = GetClipboardSnapshot();
        if (snap is null) return "";
        return SnapshotToXml(snap, includeChildren);
    }

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

    void DumpLayer(CGameUILayer@ layer, int maxDepth = 6) {
        if (layer is null) { log("DumpLayer: null layer", LogLevel::Debug, 5, "DumpLayer"); return; }
        auto root = GetRootFrame(layer);
        if (root is null) { log("DumpLayer: no root frame", LogLevel::Debug, 5, "DumpLayer"); return; }
        _DumpMlSubtree(root, "MLRoot", 0, maxDepth);
    }

    void _DumpMlSubtree(CGameManialinkControl@ n, const string &in path, int depth, int maxDepth) {
        if (n is null || depth > maxDepth) return;

        string id = n.ControlId;
        string type = TypeName(n);

        vec2 absPos = n.AbsolutePosition_V3;
        vec2 relPos = n.RelativePosition_V3;
        vec2 size = n.Size;
        float z = n.ZIndex;

        string cls = "";
        auto classes = n.ControlClasses;
        if (classes.Length > 0) cls = classes[0];

        auto controlTree = _TryGetControl(n);
        string controlTreeType = "";
        bool controlTreeVis = false;
        bool controlTreeHiddenExt = false;
        if (controlTree !is null) {
            controlTreeType = UiNav::NodeTypeName(controlTree);
            controlTreeVis = controlTree.IsVisible;
            controlTreeHiddenExt = controlTree.IsHiddenExternal;
        }

        string t = _ShortStr(CleanUiFormatting(ReadText(n)), 160);

        string line = path + " : " + type + " #" + id
            + " vis=" + (n.Visible ? "true" : "false")
            + " abs=(" + absPos.x + ", " + absPos.y + ")"
            + " rel=(" + relPos.x + ", " + relPos.y + ")"
            + " size=(" + size.x + ", " + size.y + ")"
            + " z=" + z;
        if (cls.Length > 0) line += " cls=" + cls;
        if (controlTreeType.Length > 0) line += " controlTree=" + controlTreeType + " controlTreeVis=" + (controlTreeVis ? "true" : "false") + " controlTreeHiddenExt=" + (controlTreeHiddenExt ? "true" : "false");
        if (t.Length > 0) line += " text=\"" + t + "\"";

        auto lbl = cast<CGameManialinkLabel@>(n);
        if (lbl !is null && lbl.Value.Length > 0) {
            line += " val=\"" + _ShortStr(lbl.Value, 140) + "\"";
        }
        auto entry = cast<CGameManialinkEntry@>(n);
        if (entry !is null && entry.Value.Length > 0) {
            line += " val=\"" + _ShortStr(entry.Value, 140) + "\"";
        }

        log(line, LogLevel::Debug, 18, "_DumpMlSubtree");

        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            _DumpMlSubtree(_ChildAt(n, i), path + "/" + i, depth + 1, maxDepth);
        }
    }

}
}
