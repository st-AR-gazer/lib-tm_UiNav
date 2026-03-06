namespace UiNav {
namespace CT {

    class _Tok {
        bool descendant = false;
        int nth = 0;
        bool isIndex = false;
        int index = -1;
        bool isId = false;
        string id;
        bool isAny = false;
        array<int> hints;
    }

    bool _IsAllDigits(const string &in raw) {
        string s = raw.Trim();
        if (s.Length == 0) return false;
        for (int i = 0; i < int(s.Length); ++i) {
            string ch = s.SubStr(i, 1);
            if (ch < "0" || ch > "9") return false;
        }
        return true;
    }

    string _IdLower(CControlBase@ n) {
        if (n is null) return "";
        return n.IdName.Trim().ToLower();
    }

    _Tok@ _ParseTok(const string &in raw) {
        auto t = _Tok();
        string s = raw.Trim();
        if (s.Length == 0) return null;

        if (s.IndexOf(">") >= 0) return null;

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

        string lower = s.ToLower();
        if (lower.StartsWith("overlay[") || lower.StartsWith("root[") || lower.StartsWith("id:")) return null;

        if (_IsAllDigits(s)) {
            if (t.descendant || t.nth != 0) return null;
            t.isIndex = true;
            t.index = Text::ParseInt(s);
            return t;
        }

        if (s.SubStr(0, 1) == "*") {
            t.isAny = true;
            _ParseWildcardHintsToken(s, t.hints);
            if (t.descendant && t.hints.Length > 0) return null;
            return t;
        }

        if (s.StartsWith("#")) {
            t.isId = true;
            t.id = s.SubStr(1).Trim();
            if (t.id.Length == 0) return null;
            return t;
        }

        return null;
    }

    array<_Tok@>@ _ParseSelector(const string &in selector) {
        string sel = selector.Trim();
        if (sel.Length == 0) return null;

        auto toks = array<_Tok@>();
        auto parts = sel.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            auto tok = _ParseTok(part);
            if (tok is null) return null;
            toks.InsertLast(tok);
        }

        if (toks.Length == 0) return null;
        return toks;
    }

    bool _SubtreeHasGuardPrefix(CControlBase@ n, const string &in guardLower, uint depth = 0) {
        if (n is null || guardLower.Length == 0 || depth > 64) return false;

        string text = UiNav::NormalizeForCompare(UiNav::ReadText(n)).ToLower();
        if (text.StartsWith(guardLower)) return true;

        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(n, i);
            if (_SubtreeHasGuardPrefix(ch, guardLower, depth + 1)) return true;
        }
        return false;
    }

    void _PushWildcardCandidates(array<CControlBase@> &out outCands, CControlBase@ cur, _Tok@ tok,
        ControlTreeSearchMode mode, const string &in guardLower)
    {
        if (cur is null || tok is null) return;

        uint len = _ChildrenLen(cur);
        if (len == 0) return;

        if (tok.hints.Length > 0) {
            for (uint i = 0; i < tok.hints.Length; ++i) {
                int hint = tok.hints[i];
                if (hint < 0) continue;
                auto ch = _ChildAt(cur, uint(hint));
                if (ch !is null) outCands.InsertLast(ch);
            }
            return;
        }

        if (mode == ControlTreeSearchMode::HintsOnly) return;

        if (mode == ControlTreeSearchMode::Exact) {
            auto ch = _ChildAt(cur, 0);
            if (ch !is null) outCands.InsertLast(ch);
            return;
        }

        array<CControlBase@> guarded;
        array<CControlBase@> rest;
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(cur, i);
            if (ch is null) continue;
            if (guardLower.Length > 0 && _SubtreeHasGuardPrefix(ch, guardLower)) guarded.InsertLast(ch);
            else rest.InsertLast(ch);
        }

        for (uint i = 0; i < guarded.Length; ++i) outCands.InsertLast(guarded[i]);
        for (uint i = 0; i < rest.Length; ++i) outCands.InsertLast(rest[i]);
    }

    void _PushIdCandidates(array<CControlBase@> &out outCands, CControlBase@ cur, _Tok@ tok, bool allowSelf) {
        if (cur is null || tok is null || !tok.isId) return;

        string want = tok.id.ToLower();
        if (allowSelf && _IdLower(cur) == want) outCands.InsertLast(cur);

        uint len = _ChildrenLen(cur);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(cur, i);
            if (ch is null) continue;
            if (_IdLower(ch) == want) outCands.InsertLast(ch);
        }
    }

    void _PushDescendantCandidates(array<CControlBase@> &out outCands, CControlBase@ cur, _Tok@ tok) {
        if (cur is null || tok is null) return;

        array<CControlBase@> q;
        q.InsertLast(cur);

        uint head = 0;
        while (head < q.Length) {
            auto node = q[head++];
            if (node is null) continue;

            bool matches = false;
            if (tok.isAny) matches = true;
            else if (tok.isId) matches = _IdLower(node) == tok.id.ToLower();
            if (matches) outCands.InsertLast(node);

            uint len = _ChildrenLen(node);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(node, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }
    }

    CControlBase@ _ResolveRec(CControlBase@ cur, array<_Tok@>@ toks, uint ix,
        ControlTreeSearchMode mode, const string &in guardLower)
    {
        if (cur is null || toks is null) return null;
        if (ix >= toks.Length) return cur;

        auto tok = toks[ix];
        if (tok is null) return null;

        if (tok.isIndex) {
            if (tok.index < 0) return null;
            return _ResolveRec(_ChildAt(cur, uint(tok.index)), toks, ix + 1, mode, guardLower);
        }

        array<CControlBase@> cands;
        if (tok.descendant) {
            _PushDescendantCandidates(cands, cur, tok);
        } else if (tok.isId) {
            _PushIdCandidates(cands, cur, tok, ix == 0);
        } else if (tok.isAny) {
            _PushWildcardCandidates(cands, cur, tok, mode, guardLower);
        }

        if (cands.Length == 0) return null;

        bool tryAll = tok.isAny
            && !tok.descendant
            && tok.hints.Length == 0
            && tok.nth == 0
            && mode == ControlTreeSearchMode::Smart;

        if (!tryAll) {
            if (tok.nth < 0 || tok.nth >= int(cands.Length)) return null;
            return _ResolveRec(cands[uint(tok.nth)], toks, ix + 1, mode, guardLower);
        }

        for (uint i = 0; i < cands.Length; ++i) {
            auto found = _ResolveRec(cands[i], toks, ix + 1, mode, guardLower);
            if (found !is null) return found;
        }
        return null;
    }

    CControlBase@ ResolveSelector(const string &in selector, CControlBase@ start,
        ControlTreeSearchMode mode = ControlTreeSearchMode::Exact, const string &in guardStartsWith = "")
    {
        if (start is null) return null;

        auto toks = _ParseSelector(selector);
        if (toks is null) return null;

        string guardLower = guardStartsWith.Trim().ToLower();
        return _ResolveRec(start, toks, 0, mode, guardLower);
    }

    CControlBase@ FindFirstByIdName(CControlBase@ root, const string &in idName) {
        if (root is null) return null;
        string want = idName.Trim().ToLower();
        if (want.Length == 0) return null;

        array<CControlBase@> q;
        q.InsertLast(root);

        uint head = 0;
        while (head < q.Length) {
            auto cur = q[head++];
            if (cur is null) continue;

            if (_IdLower(cur) == want) return cur;

            uint len = _ChildrenLen(cur);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(cur, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }

        return null;
    }

    bool IsEffectivelyVisible(CControlBase@ n) {
        return UiNav::IsEffectivelyVisible(n);
    }

}
}
