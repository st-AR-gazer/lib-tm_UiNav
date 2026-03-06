namespace UiNav {
namespace Debug {

    string _SearchNormalizeField(const string &in fieldRaw) {
        string f = fieldRaw.Trim().ToLower();
        if (f == "id") return "id";
        if (f == "text" || f == "txt") return "text";
        if (f == "class" || f == "classes" || f == "cls") return "class";
        if (f == "type" || f == "kind") return "type";
        if (f == "path" || f == "ui" || f == "node") return "path";
        if (f == "visible" || f == "vis") return "visible";
        return "";
    }

    array<string> _SearchTokenize(const string &in raw) {
        array<string> tokens;
        string cur = "";
        bool inQuote = false;
        int rawLen = int(raw.Length);
        for (int i = 0; i < rawLen; ++i) {
            string ch = raw.SubStr(i, 1);
            if (ch == "\"") {
                inQuote = !inQuote;
                continue;
            }
            bool isSpace = (ch == " " || ch == "\t" || ch == "\r" || ch == "\n");
            if (!inQuote && isSpace) {
                if (cur.Length > 0) {
                    tokens.InsertLast(cur);
                    cur = "";
                }
                continue;
            }
            cur += ch;
        }
        if (cur.Length > 0) tokens.InsertLast(cur);
        return tokens;
    }

    array<_SearchTerm@> _SearchParseTerms(const string &in raw) {
        array<_SearchTerm@> terms;
        string filter = raw.Trim();
        if (filter.Length == 0) return terms;

        auto toks = _SearchTokenize(filter);
        for (uint i = 0; i < toks.Length; ++i) {
            string tok = toks[i].Trim();
            if (tok.Length == 0) continue;

            _SearchTerm@ term = _SearchTerm();
            if (tok.StartsWith("-")) {
                term.negated = true;
                tok = tok.SubStr(1).Trim();
            }
            if (tok.Length == 0) continue;

            int colon = tok.IndexOf(":");
            if (colon > 0) {
                string field = _SearchNormalizeField(tok.SubStr(0, colon));
                if (field.Length > 0) {
                    term.field = field;
                    tok = tok.SubStr(colon + 1).Trim();
                }
            }

            if (tok.Length == 0) continue;
            term.value = tok.ToLower();
            terms.InsertLast(term);
        }
        return terms;
    }

    void _MlSearchTick(const string &in filterKey) {
        bool invalidate = false;
        if (filterKey != g_MlSubtreeMatchCacheFilter) {
            g_MlSubtreeMatchCacheFilter = filterKey;
            invalidate = true;
        }

        uint epoch = UiNav::ContextEpoch();
        if (epoch != g_MlSearchCacheEpoch) {
            g_MlSearchCacheEpoch = epoch;
            invalidate = true;
            _MlNodeDataCacheClear();
        }

        uint now = Time::Now;
        if (!invalidate && S_DebugSearchCacheRefreshMs > 0) {
            uint age = now - g_MlSubtreeCacheLastClearMs;
            if (age >= S_DebugSearchCacheRefreshMs) invalidate = true;
        }

        if (invalidate) {
            g_MlSubtreeMatchCache.DeleteAll();
            g_MlSubtreeCacheLastClearMs = now;
        }
    }

    void _ControlTreeSearchTick(const string &in filterKey) {
        bool invalidate = false;
        if (filterKey != g_ControlTreeSubtreeMatchCacheFilter) {
            g_ControlTreeSubtreeMatchCacheFilter = filterKey;
            invalidate = true;
        }

        uint epoch = UiNav::ContextEpoch();
        if (epoch != g_ControlTreeSearchCacheEpoch) {
            g_ControlTreeSearchCacheEpoch = epoch;
            invalidate = true;
            _ControlTreeNodeDataCacheClear();
        }

        uint now = Time::Now;
        if (!invalidate && S_DebugSearchCacheRefreshMs > 0) {
            uint age = now - g_ControlTreeSubtreeCacheLastClearMs;
            if (age >= S_DebugSearchCacheRefreshMs) invalidate = true;
        }

        if (invalidate) {
            g_ControlTreeSubtreeMatchCache.DeleteAll();
            g_ControlTreeSubtreeCacheLastClearMs = now;
        }
    }

    bool _SearchTextMatch(const string &in hay, const string &in querySpec) {
        string q = querySpec.Trim();
        if (q.Length == 0) return true;

        string[] ors = q.Split("|");
        for (uint i = 0; i < ors.Length; ++i) {
            string part = ors[i].Trim();
            if (part.Length == 0) continue;
            if (hay.Contains(part)) return true;
        }
        return false;
    }

    bool _SearchBoolMatch(const string &in querySpec, bool value) {
        string q = querySpec.Trim().ToLower();
        if (q == "1" || q == "true" || q == "yes" || q == "on" || q == "visible") return value;
        if (q == "0" || q == "false" || q == "no" || q == "off" || q == "hidden") return !value;
        return false;
    }

    bool _MlNodeMatches(CGameManialinkControl@ n, const string &in uiPath, const array<_SearchTerm@> &in terms) {
        if (n is null) return false;
        if (terms.Length == 0) return true;
        bool needText = false;
        bool needClasses = false;
        bool needVisible = false;
        for (uint i = 0; i < terms.Length; ++i) {
            auto term = terms[i];
            if (term is null) continue;
            if (term.field == "visible") needVisible = true;
            if (term.field == "text" || term.field == "any") needText = true;
            if (term.field == "class" || term.field == "any") needClasses = true;
        }

        auto data = _MlNodeData(n, uiPath, needText, needClasses, needVisible);
        if (data is null) return false;

        string id = data.id.ToLower();
        string text = data.hasText ? data.text.ToLower() : "";
        string cls = data.hasClasses ? data.classes : "";
        string type = data.type.ToLower();
        string path = uiPath.ToLower();
        bool vis = data.visible;

        for (uint i = 0; i < terms.Length; ++i) {
            auto term = terms[i];
            if (term is null || term.value.Length == 0) continue;
            bool matched = false;

            if (term.field == "visible") {
                matched = _SearchBoolMatch(term.value, vis);
            } else {
                if (term.field == "id" || term.field == "any") {
                    string idQuery = term.value;
                    if (idQuery.StartsWith("#")) idQuery = idQuery.SubStr(1);
                    if (id.Length > 0 && _SearchTextMatch(id, idQuery)) matched = true;
                    if (term.field == "id") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "type" || term.field == "any")) {
                    if (type.Length > 0 && _SearchTextMatch(type, term.value)) matched = true;
                    if (term.field == "type") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "class" || term.field == "any")) {
                    if (cls.Length > 0 && _SearchTextMatch(cls, term.value)) matched = true;
                    if (term.field == "class") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "path" || term.field == "any")) {
                    if (path.Length > 0 && _SearchTextMatch(path, term.value)) matched = true;
                    if (term.field == "path") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "text" || term.field == "any")) {
                    if (text.Length > 0 && _SearchTextMatch(text, term.value)) matched = true;
                    if (term.field == "text") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }
            }

            if (term.negated) {
                if (matched) return false;
            } else {
                if (!matched) return false;
            }
        }

        return true;
    }

    bool _ControlTreeNodeMatches(CControlBase@ n, const string &in uiPath, const string &in displayPath, const array<_SearchTerm@> &in terms) {
        if (n is null) return false;
        if (terms.Length == 0) return true;
        bool needId = false;
        bool needText = false;
        bool needVisible = false;
        for (uint i = 0; i < terms.Length; ++i) {
            auto term = terms[i];
            if (term is null) continue;
            if (term.field == "id" || term.field == "any") needId = true;
            if (term.field == "visible") needVisible = true;
            if (term.field == "text" || term.field == "any") needText = true;
        }

        auto data = _ControlTreeNodeData(n, uiPath, needText, needVisible, needId);
        if (data is null) return false;

        string id = data.hasId ? data.id : "";
        string text = data.hasText ? data.text.ToLower() : "";
        string type = data.type.ToLower();
        string path = uiPath.ToLower();
        string disp = displayPath.ToLower();
        bool vis = data.hasVisible ? data.visible : IsEffectivelyVisible(n);

        for (uint i = 0; i < terms.Length; ++i) {
            auto term = terms[i];
            if (term is null || term.value.Length == 0) continue;
            bool matched = false;

            if (term.field == "visible") {
                matched = _SearchBoolMatch(term.value, vis);
            } else {
                if (!matched && (term.field == "id" || term.field == "any")) {
                    string idQuery = term.value;
                    if (idQuery.StartsWith("#")) idQuery = idQuery.SubStr(1);
                    if (id.Length > 0 && _SearchTextMatch(id, idQuery)) matched = true;
                    if (term.field == "id") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "type" || term.field == "any")) {
                    if (type.Length > 0 && _SearchTextMatch(type, term.value)) matched = true;
                    if (term.field == "type") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "path" || term.field == "any")) {
                    if ((path.Length > 0 && _SearchTextMatch(path, term.value))
                        || (disp.Length > 0 && _SearchTextMatch(disp, term.value))) {
                        matched = true;
                    }
                    if (term.field == "path") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }

                if (!matched && (term.field == "text" || term.field == "any")) {
                    if (text.Length > 0 && _SearchTextMatch(text, term.value)) matched = true;
                    if (term.field == "text") {
                        if (term.negated ? matched : !matched) return false;
                        continue;
                    }
                }
            }

            if (term.negated) {
                if (matched) return false;
            } else {
                if (!matched) return false;
            }
        }

        return true;
    }

    bool _MlSubtreeMatchesCached(CGameManialinkControl@ n, const string &in uiPath, const string &in filter, const array<_SearchTerm@> &in terms) {
        if (n is null) return false;
        if (filter.Length == 0) return true;

        int cached = 0;
        if (g_MlSubtreeMatchCache.Exists(uiPath)) {
            g_MlSubtreeMatchCache.Get(uiPath, cached);
            return cached != 0;
        }

        bool ok = _MlNodeMatches(n, uiPath, terms);
        auto f = cast<CGameManialinkFrame@>(n);
        if (!ok && f !is null) {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                if (_MlSubtreeMatchesCached(ch, uiPath + "/" + i, filter, terms)) { ok = true; break; }
            }
        }

        g_MlSubtreeMatchCache.Set(uiPath, ok ? 1 : 0);
        return ok;
    }

    bool _MlSubtreeMatchesVisibleCached(CGameManialinkControl@ n, const string &in uiPath, const string &in filter,
                                        const array<_SearchTerm@> &in terms, bool allowChildren) {
        if (n is null) return false;
        if (filter.Length == 0) return true;

        string cacheKey = "v|" + (allowChildren ? "1|" : "0|") + uiPath;
        int cached = 0;
        if (g_MlSubtreeMatchCache.Exists(cacheKey)) {
            g_MlSubtreeMatchCache.Get(cacheKey, cached);
            return cached != 0;
        }

        bool ok = _MlNodeMatches(n, uiPath, terms);
        auto f = cast<CGameManialinkFrame@>(n);
        if (!ok && allowChildren && f !is null) {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                string childUi = uiPath + "/" + i;
                bool childAllow = _IsMlTreeOpen(childUi);
                if (_MlSubtreeMatchesVisibleCached(ch, childUi, filter, terms, childAllow)) {
                    ok = true;
                    break;
                }
            }
        }

        g_MlSubtreeMatchCache.Set(cacheKey, ok ? 1 : 0);
        return ok;
    }

    bool _ControlTreeSubtreeMatchesCached(CControlBase@ n, const string &in uiPath, const string &in displayPath, const string &in filter, const array<_SearchTerm@> &in terms) {
        if (n is null) return false;
        if (filter.Length == 0) return true;

        int cached = 0;
        if (g_ControlTreeSubtreeMatchCache.Exists(uiPath)) {
            g_ControlTreeSubtreeMatchCache.Get(uiPath, cached);
            return cached != 0;
        }

        bool ok = _ControlTreeNodeMatches(n, uiPath, displayPath, terms);
        if (!ok) {
            uint len = _ChildrenLen(n);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(n, i);
                if (ch is null) continue;
                string childUi = uiPath + "/" + i;
                string childDisplay = displayPath + "/" + i;
                if (_ControlTreeSubtreeMatchesCached(ch, childUi, childDisplay, filter, terms)) { ok = true; break; }
            }
        }

        g_ControlTreeSubtreeMatchCache.Set(uiPath, ok ? 1 : 0);
        return ok;
    }

    void _SetMlVisibleSelf(CGameManialinkControl@ n, bool vis) {
        if (n is null) return;
        n.Visible = vis;
        if (vis) UiNav::ML::Show(n); else UiNav::ML::Hide(n);
    }

    void _SetMlVisibleCascade(CGameManialinkControl@ n, bool vis) {
        if (n is null) return;
        _SetMlVisibleSelf(n, vis);
        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null) return;
        for (uint i = 0; i < f.Controls.Length; ++i) {
            auto ch = f.Controls[i];
            if (ch is null) continue;
            _SetMlVisibleCascade(ch, vis);
        }
    }

    void _SetControlTreeVisibleSelf(CControlBase@ n, bool vis) {
        if (n is null) return;
        n.IsHiddenExternal = !vis;
    }

    void _SetControlTreeVisibleCascade(CControlBase@ n, bool vis) {
        if (n is null) return;
        _SetControlTreeVisibleSelf(n, vis);
        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(n, i);
            if (ch is null) continue;
            _SetControlTreeVisibleCascade(ch, vis);
        }
    }

    string _MlFirstClassSelector(CGameManialinkControl@ n, string &out classList) {
        classList = "";
        if (n is null) return "";
        auto classes = n.ControlClasses;
        string firstClass = "";
        for (uint i = 0; i < classes.Length; ++i) {
            string c = classes[i];
            if (c.Length == 0) continue;
            if (classList.Length > 0) classList += ", ";
            classList += c;
            if (firstClass.Length == 0) firstClass = c;
        }
        if (firstClass.Length == 0) return "";
        return "." + firstClass;
    }

    array<string> _SplitLines(const string &in s) {
        string[] raw = s.Split("\n");
        array<string> parts;
        for (uint i = 0; i < raw.Length; ++i) {
            string line = raw[i].Trim();
            if (line.Length == 0) continue;
            parts.InsertLast(line);
        }
        return parts;
    }

    array<string> _SplitChain(const string &in s) {
        string[] raw = s.Split("/");
        array<string> parts;
        for (uint i = 0; i < raw.Length; ++i) {
            string part = raw[i].Trim();
            if (part.Length == 0) continue;
            parts.InsertLast(part);
        }
        return parts;
    }

    string _Vec2Str(const vec2 &in v) {
        return "" + v.x + ", " + v.y;
    }

    int _DrawMlSplitter(const string &in id, int treeWidth, float height) {
        const float w = 6.0f;
        UI::PushStyleColor(UI::Col::Button, vec4(0.25f, 0.25f, 0.28f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.35f, 0.35f, 0.40f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.45f, 0.45f, 0.50f, 1.0f));

        UI::Button(id, vec2(w, height));

        if (UI::IsItemHovered() || UI::IsItemActive()) {
            UI::SetMouseCursor(UI::MouseCursor::ResizeEW);
        }

        if (UI::IsItemActive()) {
            vec2 mp = UI::GetMousePos();
            if (!g_MlSplitterDragging) {
                g_MlSplitterDragging = true;
                g_MlSplitterLastX = mp.x;
            } else {
                float dx = mp.x - g_MlSplitterLastX;
                treeWidth += int(dx);
                g_MlSplitterLastX = mp.x;
            }
            if (treeWidth < 160) treeWidth = 160;
            if (treeWidth > 1200) treeWidth = 1200;
        } else {
            g_MlSplitterDragging = false;
        }

        UI::PopStyleColor(3);
        return treeWidth;
    }

    int _DrawControlTreeSplitter(const string &in id, int treeWidth, float height) {
        const float w = 6.0f;
        UI::PushStyleColor(UI::Col::Button, vec4(0.25f, 0.25f, 0.28f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.35f, 0.35f, 0.40f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.45f, 0.45f, 0.50f, 1.0f));

        UI::Button(id, vec2(w, height));

        if (UI::IsItemHovered() || UI::IsItemActive()) {
            UI::SetMouseCursor(UI::MouseCursor::ResizeEW);
        }

        if (UI::IsItemActive()) {
            vec2 mp = UI::GetMousePos();
            if (!g_ControlTreeSplitterDragging) {
                g_ControlTreeSplitterDragging = true;
                g_ControlTreeSplitterLastX = mp.x;
            } else {
                float dx = mp.x - g_ControlTreeSplitterLastX;
                treeWidth += int(dx);
                g_ControlTreeSplitterLastX = mp.x;
            }
            if (treeWidth < 160) treeWidth = 160;
            if (treeWidth > 1200) treeWidth = 1200;
        } else {
            g_ControlTreeSplitterDragging = false;
        }

        UI::PopStyleColor(3);
        return treeWidth;
    }

    int _DrawMlBrowserSplitter(const string &in id, int listWidth, float height) {
        const float w = 6.0f;
        UI::PushStyleColor(UI::Col::Button, vec4(0.25f, 0.25f, 0.28f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.35f, 0.35f, 0.40f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.45f, 0.45f, 0.50f, 1.0f));

        UI::Button(id, vec2(w, height));

        if (UI::IsItemHovered() || UI::IsItemActive()) {
            UI::SetMouseCursor(UI::MouseCursor::ResizeEW);
        }

        if (UI::IsItemActive()) {
            vec2 mp = UI::GetMousePos();
            if (!g_MlBrowserSplitterDragging) {
                g_MlBrowserSplitterDragging = true;
                g_MlBrowserSplitterLastX = mp.x;
            } else {
                float dx = mp.x - g_MlBrowserSplitterLastX;
                listWidth += int(dx);
                g_MlBrowserSplitterLastX = mp.x;
            }
            if (listWidth < 260) listWidth = 260;
            if (listWidth > 1200) listWidth = 1200;
        } else {
            g_MlBrowserSplitterDragging = false;
        }

        UI::PopStyleColor(3);
        return listWidth;
    }

}
}
