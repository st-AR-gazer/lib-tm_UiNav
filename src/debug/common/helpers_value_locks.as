namespace UiNav {
namespace Debug {

    int _MlValueLockKindForNode(CGameManialinkControl@ n) {
        if (n is null) return 0;
        if (cast<CGameManialinkLabel@>(n) !is null) return 1;
        if (cast<CGameManialinkEntry@>(n) !is null) return 2;
        return 0;
    }

    string _MlValueLockKindName(int kind) {
        if (kind == 1) return "Label.Value";
        if (kind == 2) return "Entry.Value";
        if (kind == 3) return "Visible";
        return "Unsupported";
    }

    string _MlBoolLockValue(bool value) {
        return value ? "1" : "0";
    }

    bool _MlParseBoolLockValue(const string &in raw, bool fallback = true) {
        string v = raw.Trim().ToLower();
        if (v == "1" || v == "true" || v == "yes" || v == "on" || v == "visible" || v == "show") return true;
        if (v == "0" || v == "false" || v == "no" || v == "off" || v == "hidden" || v == "hide") return false;
        return fallback;
    }

    string _MlValueLockReadNodeValue(CGameManialinkControl@ n, int kind) {
        if (n is null) return "";
        if (kind == 1) {
            auto lbl = cast<CGameManialinkLabel@>(n);
            if (lbl !is null) return lbl.Value;
        }
        if (kind == 2) {
            auto entry = cast<CGameManialinkEntry@>(n);
            if (entry !is null) return entry.Value;
        }
        if (kind == 3) {
            return _MlBoolLockValue(n.Visible);
        }
        return "";
    }

    bool _MlValueLockApplyNodeValue(CGameManialinkControl@ n, int kind, const string &in lockedValue) {
        if (n is null) return false;
        if (kind == 1) {
            auto lbl = cast<CGameManialinkLabel@>(n);
            if (lbl is null) return false;
            if (lbl.Value == lockedValue) return false;
            lbl.Value = lockedValue;
            return true;
        }
        if (kind == 2) {
            auto entry = cast<CGameManialinkEntry@>(n);
            if (entry is null) return false;
            if (entry.Value == lockedValue) return false;
            entry.SetText(lockedValue, true);
            return true;
        }
        if (kind == 3) {
            bool wantedVisible = _MlParseBoolLockValue(lockedValue, n.Visible);
            if (n.Visible == wantedVisible) return false;
            _SetMlVisibleSelf(n, wantedVisible);
            return true;
        }
        return false;
    }

    bool _MlResolveNodeByPath(CGameManialinkFrame@ root, const string &in path, CGameManialinkControl@ &out node) {
        @node = null;
        if (root is null) return false;
        CGameManialinkControl@ cur = root;
        string cleanPath = path.Trim();
        if (cleanPath.Length == 0) {
            @node = cur;
            return true;
        }

        auto parts = cleanPath.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;
            int idx = Text::ParseInt(part);
            if (idx < 0) return false;

            auto f = cast<CGameManialinkFrame@>(cur);
            if (f is null) return false;
            if (uint(idx) >= f.Controls.Length) return false;

            @cur = f.Controls[uint(idx)];
            if (cur is null) return false;
        }

        @node = cur;
        return true;
    }

    int _MlFindValueLockIx(int appKind, int layerIx, const string &in path, int valueKind) {
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null) continue;
            if (lock.appKind != appKind) continue;
            if (lock.layerIx != layerIx) continue;
            if (lock.valueKind != valueKind) continue;
            if (lock.path == path) return int(i);
        }
        return -1;
    }

    void _MlValueLocksLoad() {
        g_MlValueLocks.Resize(0);
        string raw = S_MlValueLocks;
        if (raw.Length == 0) return;

        auto lines = raw.Split("\n");
        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i];
            if (ln.EndsWith("\r")) ln = ln.SubStr(0, ln.Length - 1);
            ln = ln.Trim();
            if (ln.Length == 0) continue;

            auto parts = ln.Split("\t");
            if (parts.Length < 7) continue;

            MlValueLock@ lock = MlValueLock();
            lock.id = _MlNoteUnesc(parts[0]);
            lock.enabled = parts[1].Trim() != "0";
            lock.appKind = Text::ParseInt(parts[2].Trim());
            lock.layerIx = Text::ParseInt(parts[3].Trim());
            lock.path = _MlNoteUnesc(parts[4]).Trim();
            lock.valueKind = Text::ParseInt(parts[5].Trim());
            lock.lockedValue = _MlNoteUnesc(parts[6]);
            if (parts.Length >= 8) lock.label = _MlNoteUnesc(parts[7]);

            if (lock.appKind < 0 || lock.appKind > 2) continue;
            if (lock.layerIx < 0) continue;
            if (lock.valueKind < 1 || lock.valueKind > 3) continue;
            if (lock.id.Length == 0) {
                lock.id = Crypto::MD5(lock.appKind + "|" + lock.layerIx + "|" + lock.path + "|" + lock.valueKind);
            }

            if (_MlFindValueLockIx(lock.appKind, lock.layerIx, lock.path, lock.valueKind) >= 0) continue;
            g_MlValueLocks.InsertLast(lock);
        }
    }

    void _MlValueLocksSave() {
        array<string> lines;
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null) continue;
            if (lock.appKind < 0 || lock.appKind > 2) continue;
            if (lock.layerIx < 0) continue;
            if (lock.valueKind < 1 || lock.valueKind > 3) continue;
            string id = lock.id;
            if (id.Length == 0) {
                id = Crypto::MD5(lock.appKind + "|" + lock.layerIx + "|" + lock.path + "|" + lock.valueKind);
            }
            lines.InsertLast(
                _MlNoteEsc(id)
                + "\t" + (lock.enabled ? "1" : "0")
                + "\t" + lock.appKind
                + "\t" + lock.layerIx
                + "\t" + _MlNoteEsc(lock.path)
                + "\t" + lock.valueKind
                + "\t" + _MlNoteEsc(lock.lockedValue)
                + "\t" + _MlNoteEsc(lock.label)
            );
        }
        S_MlValueLocks = _JoinParts(lines, "\n");
    }

    void _MlValueLocksEnsureLoaded() {
        if (g_MlValueLocksLoaded) return;
        g_MlValueLocksLoaded = true;
        _MlValueLocksLoad();
    }

    string _MlValueLockDisplayLabel(MlValueLock@ lock) {
        if (lock is null) return "";
        string label = lock.label.Trim();
        if (label.Length == 0) {
            label = _MlAppNameByKind(lock.appKind) + " L[" + lock.layerIx + "] / " + lock.path;
            if (lock.path.Length == 0) label = _MlAppNameByKind(lock.appKind) + " L[" + lock.layerIx + "] / <root>";
        }
        label += " | " + _MlValueLockKindName(lock.valueKind);
        return label;
    }

    bool _MlAddOrUpdateValueLockKind(int appKind, int layerIx, const string &in path, int kind, const string &in lockValue, const string &in label = "") {
        if (kind < 1 || kind > 3) return false;
        if (appKind < 0 || appKind > 2 || layerIx < 0) return false;

        _MlValueLocksEnsureLoaded();
        string cleanPath = path.Trim();
        int existingIx = _MlFindValueLockIx(appKind, layerIx, cleanPath, kind);
        if (existingIx >= 0) {
            auto existing = g_MlValueLocks[uint(existingIx)];
            if (existing !is null) {
                existing.enabled = true;
                existing.lockedValue = lockValue;
                if (label.Trim().Length > 0) existing.label = label.Trim();
                _MlValueLocksSave();
                return true;
            }
        }

        MlValueLock@ lock = MlValueLock();
        lock.appKind = appKind;
        lock.layerIx = layerIx;
        lock.path = cleanPath;
        lock.valueKind = kind;
        lock.lockedValue = lockValue;
        lock.label = label.Trim();
        if (lock.label.Length == 0) {
            lock.label = _MlAppNameByKind(appKind) + " L[" + layerIx + "] / " + (cleanPath.Length > 0 ? cleanPath : "<root>");
        }
        lock.id = Crypto::MD5(lock.appKind + "|" + lock.layerIx + "|" + lock.path + "|" + lock.valueKind + "|" + lock.label);
        g_MlValueLocks.InsertLast(lock);
        _MlValueLocksSave();
        return true;
    }

    bool _MlAddOrUpdateValueLock(int appKind, int layerIx, const string &in path, CGameManialinkControl@ selectedNode, const string &in lockValue) {
        int kind = _MlValueLockKindForNode(selectedNode);
        if (kind == 0) return false;
        return _MlAddOrUpdateValueLockKind(appKind, layerIx, path, kind, lockValue);
    }

    bool _MlAddOrUpdateVisibilityLock(int appKind, int layerIx, const string &in path, bool visible) {
        return _MlAddOrUpdateValueLockKind(appKind, layerIx, path, 3, _MlBoolLockValue(visible));
    }

    bool _MlRemoveValueLock(int appKind, int layerIx, const string &in path, CGameManialinkControl@ selectedNode) {
        int kind = _MlValueLockKindForNode(selectedNode);
        if (kind == 0) return false;
        return _MlRemoveValueLockKind(appKind, layerIx, path, kind);
    }

    bool _MlRemoveValueLockKind(int appKind, int layerIx, const string &in path, int kind) {
        if (kind < 1 || kind > 3) return false;
        _MlValueLocksEnsureLoaded();
        int ix = _MlFindValueLockIx(appKind, layerIx, path.Trim(), kind);
        if (ix < 0) return false;
        g_MlValueLocks.RemoveAt(uint(ix));
        _MlValueLocksSave();
        return true;
    }

    bool _MlRemoveVisibilityLock(int appKind, int layerIx, const string &in path) {
        return _MlRemoveValueLockKind(appKind, layerIx, path, 3);
    }

    bool _MlSetValueLockEnabled(int appKind, int layerIx, const string &in path, int kind, bool enabled) {
        if (kind < 1 || kind > 3) return false;
        _MlValueLocksEnsureLoaded();
        int ix = _MlFindValueLockIx(appKind, layerIx, path.Trim(), kind);
        if (ix < 0) return false;
        auto lock = g_MlValueLocks[uint(ix)];
        if (lock is null) return false;
        if (lock.enabled == enabled) return true;
        lock.enabled = enabled;
        _MlValueLocksSave();
        return true;
    }

    bool _MlLayerHasValueLocks(int appKind, int layerIx) {
        _MlValueLocksEnsureLoaded();
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null) continue;
            if (lock.appKind == appKind && lock.layerIx == layerIx) return true;
        }
        return false;
    }

    bool _MlLayerAnyValueLockEnabled(int appKind, int layerIx) {
        _MlValueLocksEnsureLoaded();
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null) continue;
            if (lock.appKind != appKind || lock.layerIx != layerIx) continue;
            if (lock.enabled) return true;
        }
        return false;
    }

    int _MlSetLayerValueLocksEnabled(int appKind, int layerIx, bool enabled) {
        _MlValueLocksEnsureLoaded();
        int changed = 0;
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null) continue;
            if (lock.appKind != appKind || lock.layerIx != layerIx) continue;
            if (lock.enabled == enabled) continue;
            lock.enabled = enabled;
            changed++;
        }
        if (changed > 0) _MlValueLocksSave();
        return changed;
    }

    int _MlRemoveLayerValueLocks(int appKind, int layerIx) {
        _MlValueLocksEnsureLoaded();
        int removed = 0;
        for (int i = int(g_MlValueLocks.Length) - 1; i >= 0; --i) {
            auto lock = g_MlValueLocks[uint(i)];
            if (lock is null) continue;
            if (lock.appKind != appKind || lock.layerIx != layerIx) continue;
            g_MlValueLocks.RemoveAt(uint(i));
            removed++;
        }
        if (removed > 0) _MlValueLocksSave();
        return removed;
    }

    void _MlApplyValueLocks() {
        _MlValueLocksEnsureLoaded();
        int writes = 0;
        for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
            auto lock = g_MlValueLocks[i];
            if (lock is null || !lock.enabled) continue;

            auto root = _GetMlRootByLayerIx(lock.layerIx, lock.appKind);
            if (root is null) continue;

            CGameManialinkControl@ node = null;
            if (!_MlResolveNodeByPath(root, lock.path, node)) continue;
            if (_MlValueLockApplyNodeValue(node, lock.valueKind, lock.lockedValue)) writes++;
        }

        if (writes > 0) {
            g_MlValueLocksStatus = "Applied " + writes + " value lock write(s).";
        }
    }

}
}
