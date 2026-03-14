namespace UiNav {

    CControlBase@ _ResolveClickableControlNode(CControlBase@ n, bool childFallback = true) {
        if (n is null) return null;

        if (cast<CControlQuad>(n) !is null) return n;
        if (cast<CControlButton>(n) !is null) return n;
        if (cast<CGameControlCardGeneric>(n) !is null) return n;

        if (!childFallback) return null;

        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            CControlBase@ ch = _ChildAt(n, i);
            if (ch is null) continue;

            if (cast<CControlQuad>(ch) !is null) return ch;
            if (cast<CControlButton>(ch) !is null) return ch;
            if (cast<CGameControlCardGeneric>(ch) !is null) return ch;
        }
        return null;
    }

    bool CanClick(CControlBase@ n, bool childFallback = true) {
        return _ResolveClickableControlNode(n, childFallback) !is null;
    }

    bool ClickControlNode(CControlBase@ n, bool childFallback = true) {
        auto target = _ResolveClickableControlNode(n, childFallback);
        if (target is null) return false;

        CControlQuad@ q = cast<CControlQuad>(target);
        if (q !is null) { q.OnAction(); return true; }

        CControlButton@ b = cast<CControlButton>(target);
        if (b !is null) { b.OnAction(); return true; }

        CGameControlCardGeneric@ card = cast<CGameControlCardGeneric>(target);
        if (card !is null) { card.OnAction(); return true; }

        return false;
    }

    bool CanSetText(CControlBase@ n) {
        if (n is null) return false;

        if (cast<CControlEntry>(n) !is null) return true;

        CControlFrame@ f = cast<CControlFrame>(n);
        if (f is null) return false;
        return cast<CControlEntry>(f.Nod) !is null;
    }

    bool SetTextControlNode(CControlBase@ n, const string &in text) {
        if (n is null) return false;

        CControlEntry@ e = cast<CControlEntry>(n);
        if (e !is null) {
            CGameManialinkEntry@ ml = cast<CGameManialinkEntry>(e.Nod);
            if (ml is null) return false;
            ml.SetText(text, true);
            return true;
        }

        CControlFrame@ f = cast<CControlFrame>(n);
        if (f !is null) {
            CControlEntry@ e2 = cast<CControlEntry>(f.Nod);
            if (e2 !is null) {
                CGameManialinkEntry@ ml2 = cast<CGameManialinkEntry>(e2.Nod);
                if (ml2 is null) return false;
                ml2.SetText(text, true);
                return true;
            }
        }
        return false;
    }

}
