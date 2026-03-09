namespace UiNav {

    shared enum BackendKind {
        None = 0,
        ControlTree = 1,
        ML = 2
    }

    shared enum BackendPref {
        Unspecified = 0,
        PreferControlTree = 1,
        PreferML = 2
    }

    shared enum ManiaLinkSource {
        CurrentApp = 0,
        Playground = 1,
        Menu = 2,
        Editor = 3
    }

    shared enum ControlTreeSearchMode {
        Exact = 0,
        Smart = 1,
        HintsOnly = 2
    }

    shared enum OpStatus {
        Ok                 = 0,
        InvalidTarget      = 1,
        RequirementsFailed = 2,
        ResolveFailed      = 3,
        InvalidBackendRef  = 4,
        NotVisible         = 5,
        ActionFailed       = 6,
        TimedOut           = 7
    }

    shared class ManiaLinkReq {
        ManiaLinkSource source = ManiaLinkSource::CurrentApp;
        string pageNeedle;
        string rootControlId;

        bool mustBeVisible = true;
        bool mustHaveLocalPage = true;

        int layerIxHint = -1;
        array<int> layerIxHints;

        void AddLayerIxHint(int ix) {
            if (ix < 0) return;
            if (layerIxHint < 0) layerIxHint = ix;
            for (uint i = 0; i < layerIxHints.Length; ++i) {
                if (layerIxHints[i] == ix) return;
            }
            layerIxHints.InsertLast(ix);
        }

        void ClearLayerIxHints() {
            layerIxHint = -1;
            layerIxHints.Resize(0);
        }
    }

    shared class Requires {
        array<uint> overlaysAll;
        array<uint> overlaysAny;

        array<ManiaLinkReq@> layersAll;
        array<ManiaLinkReq@> layersAny;

        bool requireTargetVisible = true;

        bool strict = true;
    }

    shared class ControlTreeReq {
        uint overlay   = 16;
        uint rootIx    = 0;

        bool anyRoot   = false;
        uint maxRoots  = 24;

        ControlTreeSearchMode searchMode = ControlTreeSearchMode::Exact;
        string guardStartsWith;
    }

    shared class ControlTreeSpec {
        ControlTreeReq@ req = null;
        string selector;

        bool clickChildFallback = true;

        bool requireVisible = true;

        array<ControlTreeSpec@> alts;

        void AddAlt(ControlTreeSpec@ s) {
            if (s is null) return;
            alts.InsertLast(s);
        }
    }

    shared class ManiaLinkSpec {
        ManiaLinkReq@ req = null;
        string selector;

        bool clickChildFallback = true;
        bool requireVisible = true;

        array<ManiaLinkSpec@> alts;

        void AddAlt(ManiaLinkSpec@ s) {
            if (s is null) return;
            alts.InsertLast(s);
        }
    }

    shared class Target {
        string name;
        BackendPref pref = BackendPref::Unspecified;

        ControlTreeSpec@ controlTree;
        ManiaLinkSpec@  ml;
        Requires@ req;

        uint cacheInvalidationSerial = 1;

        void InvalidateCache() {
            cacheInvalidationSerial++;
            if (cacheInvalidationSerial == 0) cacheInvalidationSerial = 1;
        }
    }

    shared class NodeRef {
        BackendKind kind = BackendKind::None;
        string debug;

        bool visibilityChecked = false;
        bool visibilityOk = false;

        uint resolvedAtMs = 0;

        string selector;

        uint overlay = uint(-1);
        uint rootIx = uint(-1);
        CControlBase@ controlTree = null;

        ManiaLinkSource source = ManiaLinkSource::CurrentApp;
        CGameManiaApp@ maniaApp = null;
        CGameManialinkPage@ localPage = null;
        CGameUILayer@ layer = null;
        int layerIx = -1;
        CGameManialinkControl@ ml = null;

        bool IsControlTree() const {
            return kind == BackendKind::ControlTree;
        }

        bool IsManiaLink() const {
            return kind == BackendKind::ML;
        }

        bool HasSelector() const {
            return selector.Length > 0;
        }

        bool IsNull() const {
            if (kind == BackendKind::ControlTree) return controlTree is null;
            if (kind == BackendKind::ML)  return ml is null;
            return true;
        }
    }

    shared class OpResult {
        OpStatus status = OpStatus::ResolveFailed;
        BackendKind kind = BackendKind::None;
        string reason;
        string text;
        NodeRef@ ref = null;

        bool Ok() const {
            return status == OpStatus::Ok;
        }
    }

}
