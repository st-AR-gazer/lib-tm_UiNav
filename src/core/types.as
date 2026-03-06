namespace UiNav {

    shared enum BackendKind {
        None = 0,
        ControlTree = 1,
        ML = 2
    }

    shared enum BackendPref {
        Auto = 0,
        PreferControlTree = 1,
        PreferML = 2
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
        string name;
        string pageNeedle;
        string rootControlId;

        bool mustBeVisible = true;
        bool mustHaveLocalPage = true;

        int layerIxHint = -1;

        ManiaLinkReq() {}
        ManiaLinkReq(const string &in name_, const string &in needle_="") {
            name = name_;
            pageNeedle = needle_;
        }
    }

    shared class LayerReq : ManiaLinkReq {
        LayerReq() { super(); }
        LayerReq(const string &in name_, const string &in needle_="") { super(name_, needle_); }
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
        uint overlay   = 0;

        bool anyRoot   = false;
        uint maxRoots  = 24;

        bool smart     = false;
        bool hintsOnly = false;
        string guardStartsWith;
    }

    shared class CtlReq : ControlTreeReq {}

    shared class ControlTreeSpec {
        ControlTreeReq@ req = null;

        uint overlay = 16;
        string path;
        string selector;
        string idName;

        bool anyRoot   = false;
        uint maxRoots  = 24;

        bool smart     = false;
        bool hintsOnly = false;
        string guardStartsWith;

        bool clickChildFallback = true;

        bool requireVisible = true;

        array<ControlTreeSpec@> alts;

        void AddAlt(ControlTreeSpec@ s) {
            if (s is null) return;
            alts.InsertLast(s);
        }
    }

    shared class CtlSpec : ControlTreeSpec {}

    shared class ManiaLinkSpec {
        ManiaLinkReq@ layer;
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

    shared class MlSpec : ManiaLinkSpec {}

    shared class Target {
        string name;
        BackendPref pref = BackendPref::Auto;

        ControlTreeSpec@ controlTree;
        ManiaLinkSpec@  ml;
        Requires@ req;

        bool cacheNativePointers = true;

        uint cacheTtlMs = 200;
        uint lastResolveMs = 0;
        uint cacheEpoch = 0;

        uint planUid = 0;

        BackendKind lastKind = BackendKind::None;
        string lastDebug = "";

        CControlBase@ cachedControlTree = null;
        CGameManialinkControl@ cachedMl = null;
        CGameUILayer@ cachedLayer = null;
        int cachedLayerIx = -1;
        CGameManiaApp@ cachedManiaApp = null;
        CGameManialinkPage@ cachedLocalPage = null;
        string cachedMlSelector = "";

        void InvalidateCache() {
            lastResolveMs = 0;
            cacheEpoch = 0;
            lastKind = BackendKind::None;
            lastDebug = "cache invalidated";

            @cachedControlTree = null;
            @cachedMl = null;
            @cachedLayer = null;
            cachedLayerIx = -1;
            @cachedManiaApp = null;
            @cachedLocalPage = null;
            cachedMlSelector = "";
        }
    }

    shared class NodeRef {
        BackendKind kind = BackendKind::None;
        string debug;

        bool visibilityChecked = false;
        bool visibilityOk = false;

        uint resolvedAtMs = 0;

        uint overlay = uint(-1);
        string path;
        CControlBase@ controlTree = null;

        CGameManiaApp@ maniaApp = null;
        CGameManialinkPage@ localPage = null;
        CGameUILayer@ layer = null;
        string selector;
        CGameManialinkControl@ ml = null;

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
