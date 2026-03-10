namespace UiNav {

    class _TargetPlan {
        ManiaLinkSpec@ mlRef = null;
        string mlSelectorRaw = "";
        string mlSelectorTrim = "";
        array<UiNav::ML::_Tok@>@ mlToks = null;
        bool mlToksReady = false;

        Requires@ reqRef = null;
        array<ManiaLinkReq@> reqAllRefs;
        array<string> reqAllCacheKeys;
        array<string> reqAllFrameKeys;
        array<ManiaLinkReq@> reqAnyRefs;
        array<string> reqAnyCacheKeys;
        array<string> reqAnyFrameKeys;
    }

    class _TargetState {
        string scopeId = "";
        uint seenInvalidationSerial = 1;
        uint lastTouchedMs = 0;

        _TargetPlan@ plan = null;

        uint lastResolveMs = 0;
        uint cacheEpoch = 0;
        BackendKind lastKind = BackendKind::None;
        string lastDebug = "";

        CControlBase@ cachedControlTree = null;
        uint cachedControlTreeRootIx = uint(-1);
        CGameManialinkControl@ cachedMl = null;
        CGameUILayer@ cachedLayer = null;
        int cachedLayerIx = -1;
        CGameManiaApp@ cachedManiaApp = null;
        CGameManialinkPage@ cachedLocalPage = null;
        string cachedMlSelector = "";
        string cachedTargetConfigKey = "";
    }

    array<Target@> g_TargetStateHandles;
    array<_TargetState@> g_TargetStateValues;
    const uint kTargetStateMax = 512;
    const uint kTargetPointerCacheTtlMs = 200;

    uint g_TargetPlanHits = 0;
    uint g_TargetPlanMisses = 0;
    uint g_TargetPlanRebuilds = 0;

    void _ClearResolvedCache(_TargetState@ st, const string &in debug = "") {
        if (st is null) return;

        st.lastResolveMs = 0;
        st.cacheEpoch = 0;
        st.lastKind = BackendKind::None;
        if (debug.Length > 0) st.lastDebug = debug;

        @st.cachedControlTree = null;
        st.cachedControlTreeRootIx = uint(-1);
        @st.cachedMl = null;
        @st.cachedLayer = null;
        st.cachedLayerIx = -1;
        @st.cachedManiaApp = null;
        @st.cachedLocalPage = null;
        st.cachedMlSelector = "";
        st.cachedTargetConfigKey = "";
    }

    string _ConfigBool(bool v) {
        return v ? "1" : "0";
    }

    string _ConfigString(const string &in v) {
        return "[" + tostring(v.Length) + "]" + v;
    }

    string _ConfigUIntArray(const array<uint> &in values) {
        string key = tostring(values.Length) + ":";
        for (uint i = 0; i < values.Length; ++i) {
            if (i > 0) key += ",";
            key += tostring(values[i]);
        }
        return key;
    }

    string _ConfigManiaLinkReq(const ManiaLinkReq@ req) {
        if (req is null) return "<null>";
        return UiNav::Layers::_LayerReqFrameMemoKey(req);
    }

    string _ConfigRequires(Requires@ req) {
        if (req is null) return "<null>";

        string key = "strict=" + _ConfigBool(req.strict)
            + "|targetVisible=" + _ConfigBool(req.requireTargetVisible)
            + "|overlaysAll=" + _ConfigUIntArray(req.overlaysAll)
            + "|overlaysAny=" + _ConfigUIntArray(req.overlaysAny)
            + "|layersAll=" + tostring(req.layersAll.Length)
            + "|layersAny=" + tostring(req.layersAny.Length);

        for (uint i = 0; i < req.layersAll.Length; ++i) {
            key += "|all[" + tostring(i) + "]=" + _ConfigManiaLinkReq(req.layersAll[i]);
        }
        for (uint i = 0; i < req.layersAny.Length; ++i) {
            key += "|any[" + tostring(i) + "]=" + _ConfigManiaLinkReq(req.layersAny[i]);
        }
        return key;
    }

    string _ConfigControlTreeReq(ControlTreeReq@ req) {
        if (req is null) return "<null>";
        return "ov=" + tostring(req.overlay)
            + "|root=" + tostring(req.rootIx)
            + "|any=" + _ConfigBool(req.anyRoot)
            + "|maxRoots=" + tostring(req.maxRoots)
            + "|mode=" + tostring(int(req.searchMode))
            + "|guard=" + _ConfigString(req.guardStartsWith);
    }

    string _ConfigControlTreeSpec(ControlTreeSpec@ spec, uint depth = 0) {
        if (spec is null) return "<null>";
        if (depth >= 4) return "<depth>";

        string key = "req=" + _ConfigControlTreeReq(spec.req)
            + "|selector=" + _ConfigString(spec.selector.Trim())
            + "|childFallback=" + _ConfigBool(spec.clickChildFallback)
            + "|visible=" + _ConfigBool(spec.requireVisible)
            + "|alts=" + tostring(spec.alts.Length);
        for (uint i = 0; i < spec.alts.Length; ++i) {
            key += "|alt[" + tostring(i) + "]=" + _ConfigControlTreeSpec(spec.alts[i], depth + 1);
        }
        return key;
    }

    string _ConfigManiaLinkSpec(ManiaLinkSpec@ spec, uint depth = 0) {
        if (spec is null) return "<null>";
        if (depth >= 4) return "<depth>";

        string key = "req=" + _ConfigManiaLinkReq(spec.req)
            + "|selector=" + _ConfigString(spec.selector.Trim())
            + "|childFallback=" + _ConfigBool(spec.clickChildFallback)
            + "|visible=" + _ConfigBool(spec.requireVisible)
            + "|alts=" + tostring(spec.alts.Length);
        for (uint i = 0; i < spec.alts.Length; ++i) {
            key += "|alt[" + tostring(i) + "]=" + _ConfigManiaLinkSpec(spec.alts[i], depth + 1);
        }
        return key;
    }

    string _TargetConfigKey(Target@ t) {
        if (t is null) return "<null>";
        return "pref=" + tostring(int(t.pref))
            + "|ct=" + _ConfigControlTreeSpec(t.controlTree)
            + "|ml=" + _ConfigManiaLinkSpec(t.ml)
            + "|req=" + _ConfigRequires(t.req);
    }

    _TargetState@ _FindTargetState(Target@ t, int &out ix) {
        ix = -1;
        if (t is null) return null;

        for (uint i = 0; i < g_TargetStateHandles.Length; ++i) {
            if (g_TargetStateHandles[i] is t) {
                ix = int(i);
                return g_TargetStateValues[i];
            }
        }
        return null;
    }

    void _SyncTargetInvalidation(Target@ t, _TargetState@ st) {
        if (t is null || st is null) return;
        uint serial = t.cacheInvalidationSerial == 0 ? 1 : t.cacheInvalidationSerial;
        if (st.seenInvalidationSerial == serial) return;
        _ClearResolvedCache(st, "cache invalidated");
        st.seenInvalidationSerial = serial;
    }

    _TargetState@ _GetTargetState(Target@ t, bool createIfMissing = true) {
        if (t is null) return null;

        int ix = -1;
        auto st = _FindTargetState(t, ix);
        if (st !is null) {
            st.lastTouchedMs = Time::Now;
            _SyncTargetInvalidation(t, st);
            return st;
        }

        if (!createIfMissing) return null;

        if (g_TargetStateHandles.Length >= kTargetStateMax && g_TargetStateHandles.Length > 0) {
            uint oldestIx = 0;
            uint oldestAt = g_TargetStateValues[0] is null ? 0 : g_TargetStateValues[0].lastTouchedMs;
            for (uint i = 1; i < g_TargetStateValues.Length; ++i) {
                uint at = g_TargetStateValues[i] is null ? 0 : g_TargetStateValues[i].lastTouchedMs;
                if (at < oldestAt) {
                    oldestAt = at;
                    oldestIx = i;
                }
            }
            g_TargetStateHandles.RemoveAt(oldestIx);
            g_TargetStateValues.RemoveAt(oldestIx);
        }

        @st = _TargetState();
        st.scopeId = UiNav::Layers::_CurrentCallerScope();
        st.seenInvalidationSerial = t.cacheInvalidationSerial == 0 ? 1 : t.cacheInvalidationSerial;
        st.lastTouchedMs = Time::Now;
        g_TargetStateHandles.InsertLast(t);
        g_TargetStateValues.InsertLast(st);
        return st;
    }

    bool _LayerReqRefsMatch(const array<ManiaLinkReq@> &in cachedRefs, const array<string> &in cachedFrameKeys, const array<ManiaLinkReq@> &in refsNow) {
        if (cachedRefs.Length != refsNow.Length) return false;
        if (cachedFrameKeys.Length != refsNow.Length) return false;
        for (uint i = 0; i < refsNow.Length; ++i) {
            if (cachedRefs[i] !is refsNow[i]) return false;
            if (cachedFrameKeys[i] != UiNav::Layers::_LayerReqFrameMemoKey(refsNow[i])) return false;
        }
        return true;
    }

    void _BuildLayerReqKeyCache(const array<ManiaLinkReq@> &in refsNow, array<ManiaLinkReq@> &out refsOut, array<string> &out cacheKeysOut, array<string> &out frameKeysOut) {
        refsOut.Resize(0);
        cacheKeysOut.Resize(0);
        frameKeysOut.Resize(0);

        for (uint i = 0; i < refsNow.Length; ++i) {
            auto req = refsNow[i];
            refsOut.InsertLast(req);
            cacheKeysOut.InsertLast(UiNav::Layers::_LayerReqKey(req));
            frameKeysOut.InsertLast(UiNav::Layers::_LayerReqFrameMemoKey(req));
        }
    }

    _TargetPlan@ _GetTargetPlan(Target@ t, _TargetState@ st = null) {
        if (t is null) return null;
        if (st is null) @st = _GetTargetState(t);
        if (st is null) return null;

        if (st.plan !is null) {
            g_TargetPlanHits++;
            return st.plan;
        }

        g_TargetPlanMisses++;
        @st.plan = _TargetPlan();
        return st.plan;
    }

    void _RefreshTargetPlan(Target@ t, _TargetPlan@ plan) {
        if (t is null || plan is null) return;

        bool rebuilt = false;

        bool mlChanged = (plan.mlRef !is t.ml);
        if (!mlChanged && t.ml !is null) {
            mlChanged = plan.mlSelectorRaw != _ManiaLinkSpecSelector(t.ml);
        }

        if (mlChanged) {
            rebuilt = true;
            @plan.mlRef = t.ml;
            plan.mlSelectorRaw = (t.ml is null) ? "" : _ManiaLinkSpecSelector(t.ml);
            plan.mlSelectorTrim = plan.mlSelectorRaw.Trim();
            @plan.mlToks = null;
            plan.mlToksReady = false;
            if (plan.mlSelectorTrim.Length > 0) {
                @plan.mlToks = UiNav::ML::_GetTokChainCached(plan.mlSelectorTrim);
                plan.mlToksReady = plan.mlToks !is null;
            }
        }

        bool reqChanged = (plan.reqRef !is t.req);
        if (!reqChanged && t.req !is null) {
            if (!_LayerReqRefsMatch(plan.reqAllRefs, plan.reqAllFrameKeys, t.req.layersAll)) reqChanged = true;
            else if (!_LayerReqRefsMatch(plan.reqAnyRefs, plan.reqAnyFrameKeys, t.req.layersAny)) reqChanged = true;
        }

        if (reqChanged) {
            rebuilt = true;
            @plan.reqRef = t.req;
            if (t.req is null) {
                plan.reqAllRefs.Resize(0);
                plan.reqAllCacheKeys.Resize(0);
                plan.reqAllFrameKeys.Resize(0);
                plan.reqAnyRefs.Resize(0);
                plan.reqAnyCacheKeys.Resize(0);
                plan.reqAnyFrameKeys.Resize(0);
            } else {
                _BuildLayerReqKeyCache(t.req.layersAll, plan.reqAllRefs, plan.reqAllCacheKeys, plan.reqAllFrameKeys);
                _BuildLayerReqKeyCache(t.req.layersAny, plan.reqAnyRefs, plan.reqAnyCacheKeys, plan.reqAnyFrameKeys);
            }
        }

        if (rebuilt) g_TargetPlanRebuilds++;
    }

    _TargetPlan@ _EnsureTargetPlan(Target@ t, _TargetState@ st = null) {
        if (st is null) @st = _GetTargetState(t);
        auto plan = _GetTargetPlan(t, st);
        _RefreshTargetPlan(t, plan);
        return plan;
    }

    void PrepareTarget(Target@ t) {
        auto st = _GetTargetState(t);
        _EnsureTargetPlan(t, st);
    }

    void InvalidateTargetPlan(Target@ t) {
        if (t is null) return;
        t.InvalidateCache();
        auto st = _GetTargetState(t, false);
        if (st is null) return;
        @st.plan = null;
        _ClearResolvedCache(st, "target plan invalidated");
        st.seenInvalidationSerial = t.cacheInvalidationSerial == 0 ? 1 : t.cacheInvalidationSerial;
    }

    uint TargetPlanCacheHits() { return g_TargetPlanHits; }
    uint TargetPlanCacheMisses() { return g_TargetPlanMisses; }
    uint TargetPlanCacheRebuilds() { return g_TargetPlanRebuilds; }

    void ResetTargetPlanCacheStats() {
        g_TargetPlanHits = 0;
        g_TargetPlanMisses = 0;
        g_TargetPlanRebuilds = 0;
    }

    void InvalidateTargetStatesForScope(const string &in scopeIdRaw, const string &in debug = "cache invalidated") {
        string scopeId = scopeIdRaw.Trim();
        if (scopeId.Length == 0) return;

        for (uint i = 0; i < g_TargetStateValues.Length; ++i) {
            auto st = g_TargetStateValues[i];
            if (st is null || st.scopeId != scopeId) continue;
            @st.plan = null;
            _ClearResolvedCache(st, debug);
        }
    }

    bool _CheckOverlaysAll(const array<uint> &in overlays) {
        for (uint i = 0; i < overlays.Length; ++i) {
            if (!OverlayAvailable(overlays[i])) return false;
        }
        return true;
    }

    bool _CheckOverlaysAny(const array<uint> &in overlays) {
        if (overlays.Length == 0) return true;
        for (uint i = 0; i < overlays.Length; ++i) {
            if (OverlayAvailable(overlays[i])) return true;
        }
        return false;
    }

    bool _CheckLayersAll(const array<ManiaLinkReq@> &in layers, array<string>@ cacheKeys = null, array<string>@ frameKeys = null) {
        int layerIx = -1;
        for (uint i = 0; i < layers.Length; ++i) {
            string cacheKey = "";
            if (cacheKeys !is null && i < cacheKeys.Length) cacheKey = cacheKeys[i];
            string frameKey = "";
            if (frameKeys !is null && i < frameKeys.Length) frameKey = frameKeys[i];
            if (UiNav::Layers::FindLayer(layers[i], layerIx, cacheKey, frameKey) is null) return false;
        }
        return true;
    }

    bool _CheckLayersAny(const array<ManiaLinkReq@> &in layers, array<string>@ cacheKeys = null, array<string>@ frameKeys = null) {
        if (layers.Length == 0) return true;
        int layerIx = -1;
        for (uint i = 0; i < layers.Length; ++i) {
            string cacheKey = "";
            if (cacheKeys !is null && i < cacheKeys.Length) cacheKey = cacheKeys[i];
            string frameKey = "";
            if (frameKeys !is null && i < frameKeys.Length) frameKey = frameKeys[i];
            if (UiNav::Layers::FindLayer(layers[i], layerIx, cacheKey, frameKey) !is null) return true;
        }
        return false;
    }

    bool CheckRequirements(Target@ t, _TargetPlan@ plan = null) {
        uint startedAt = Time::Now;
        bool ok = true;

        if (t is null) {
            ok = false;
        } else if (t.req !is null) {
            if (!_CheckOverlaysAll(t.req.overlaysAll)) ok = false;
            else if (!_CheckOverlaysAny(t.req.overlaysAny)) ok = false;
            else {
                array<string>@ allCache = null;
                array<string>@ allFrame = null;
                array<string>@ anyCache = null;
                array<string>@ anyFrame = null;
                if (plan !is null && plan.reqRef is t.req) {
                    @allCache = plan.reqAllCacheKeys;
                    @allFrame = plan.reqAllFrameKeys;
                    @anyCache = plan.reqAnyCacheKeys;
                    @anyFrame = plan.reqAnyFrameKeys;
                }

                if (!_CheckLayersAll(t.req.layersAll, allCache, allFrame)) ok = false;
                else if (!_CheckLayersAny(t.req.layersAny, anyCache, anyFrame)) ok = false;
            }
        }

        UiNav::Metrics::Record("check_requirements", Time::Now - startedAt);
        return ok;
    }

    bool _CheckReqVisible(Target@ t, NodeRef@ r) {
        if (t is null || r is null) return false;
        if (t.req is null || !t.req.requireTargetVisible) return true;

        if (r.visibilityChecked) return r.visibilityOk;
        if (r.kind == BackendKind::ControlTree) return IsEffectivelyVisible(r.controlTree);
        if (r.kind == BackendKind::ML) return UiNav::ML::IsEffectivelyVisible(r.ml);
        return false;
    }

    ControlTreeReq@ _ControlTreeSpecReq(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        if (s is null) return fallback;
        if (s.req !is null) return s.req;
        return fallback;
    }

    string _ControlTreeSpecSelector(ControlTreeSpec@ s) {
        if (s is null) return "";
        return s.selector.Trim();
    }

    uint _ControlTreeSpecOverlay(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        if (req is null) return 16;
        return req.overlay;
    }

    uint _ControlTreeSpecRootIx(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        if (req is null) return 0;
        return req.rootIx;
    }

    bool _ControlTreeSpecAnyRoot(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        return req !is null && req.anyRoot;
    }

    uint _ControlTreeSpecMaxRoots(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        if (req is null) return 24;
        return req.maxRoots;
    }

    ControlTreeSearchMode _ControlTreeSpecSearchMode(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        if (req is null) return ControlTreeSearchMode::Exact;
        return req.searchMode;
    }

    string _ControlTreeSpecGuardStartsWith(ControlTreeSpec@ s, ControlTreeReq@ fallback = null) {
        auto req = _ControlTreeSpecReq(s, fallback);
        if (req is null) return "";
        return req.guardStartsWith;
    }

    string _ControlTreeSpecDebugSelector(ControlTreeSpec@ s) {
        return _ControlTreeSpecSelector(s);
    }

    CControlBase@ _ResolveControlTreeSpec(ControlTreeSpec@ s, ControlTreeReq@ fallback, uint &out matchedRootIx) {
        matchedRootIx = uint(-1);
        if (s is null) return null;

        string selector = _ControlTreeSpecSelector(s);
        if (selector.Length == 0) return null;

        uint overlay = _ControlTreeSpecOverlay(s, fallback);
        auto mode = _ControlTreeSpecSearchMode(s, fallback);
        string guard = _ControlTreeSpecGuardStartsWith(s, fallback);

        if (_ControlTreeSpecAnyRoot(s, fallback)) {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene) || scene is null) return null;

            uint rootsLen = scene.Mobils.Length;
            if (rootsLen == 0) return null;

            uint maxRoots = Math::Min(_ControlTreeSpecMaxRoots(s, fallback), rootsLen);
            if (maxRoots == 0) return null;

            uint preferred = _ControlTreeSpecRootIx(s, fallback);
            if (preferred < maxRoots) {
                auto root = _RootFromMobil(scene, preferred);
                auto found = UiNav::CT::ResolveSelector(selector, root, mode, guard);
                if (found !is null) {
                    matchedRootIx = preferred;
                    return found;
                }
            }

            for (uint r = 0; r < maxRoots; ++r) {
                if (r == preferred) continue;
                auto root = _RootFromMobil(scene, r);
                auto found = UiNav::CT::ResolveSelector(selector, root, mode, guard);
                if (found !is null) {
                    matchedRootIx = r;
                    return found;
                }
            }

            return null;
        }

        uint rootIx = _ControlTreeSpecRootIx(s, fallback);
        CControlBase@ root = null;
        if (rootIx == 0) {
            @root = RootAtOverlay(overlay);
        } else {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene) || scene is null) return null;
            if (rootIx >= scene.Mobils.Length) return null;
            @root = _RootFromMobil(scene, rootIx);
        }
        if (root is null) return null;

        auto found = UiNav::CT::ResolveSelector(selector, root, mode, guard);
        if (found is null) return null;
        matchedRootIx = rootIx;
        return found;
    }

    ManiaLinkReq@ _ManiaLinkSpecReq(ManiaLinkSpec@ s, ManiaLinkReq@ fallback = null) {
        if (s is null) return fallback;
        if (s.req !is null) return s.req;
        return fallback;
    }

    string _ManiaLinkSpecSelector(ManiaLinkSpec@ s) {
        if (s is null) return "";
        return s.selector.Trim();
    }

    bool _ResolveMlSource(const ManiaLinkReq@ req, ManiaLinkSource &out source, CGameManiaApp@ &out app) {
        ManiaLinkSource requested = (req is null) ? ManiaLinkSource::CurrentApp : req.source;
        return UiNav::Layers::_ResolveLayerSource(requested, source, app);
    }

    NodeRef@ ResolveControlTree(Target@ t, _TargetState@ st = null) {
        if (t is null || t.controlTree is null) return null;
        if (st is null) @st = _GetTargetState(t);
        if (st is null) return null;

        string targetConfigKey = _TargetConfigKey(t);
        if (st.cachedTargetConfigKey.Length > 0 && st.cachedTargetConfigKey != targetConfigKey) {
            _ClearResolvedCache(st, "target config changed");
        }

        if (st.cachedControlTree !is null && st.cacheEpoch == UiNav::Context::Epoch() && (Time::Now - st.lastResolveMs) <= kTargetPointerCacheTtlMs) {
            if (t.controlTree.requireVisible && !IsEffectivelyVisible(st.cachedControlTree)) {
                @st.cachedControlTree = null;
                st.cachedControlTreeRootIx = uint(-1);
                st.cacheEpoch = 0;
            } else {
                auto r = NodeRef();
                r.kind = BackendKind::ControlTree;
                r.selector = _ControlTreeSpecDebugSelector(t.controlTree);
                r.overlay = _ControlTreeSpecOverlay(t.controlTree, null);
                r.rootIx = st.cachedControlTreeRootIx;
                @r.controlTree = st.cachedControlTree;
                r.debug = "cached controlTree";
                r.visibilityChecked = t.controlTree.requireVisible;
                r.visibilityOk = t.controlTree.requireVisible;
                r.resolvedAtMs = st.lastResolveMs;
                return r;
            }
        }

        array<ControlTreeSpec@> tries;
        tries.InsertLast(t.controlTree);
        for (uint i = 0; i < t.controlTree.alts.Length; ++i) tries.InsertLast(t.controlTree.alts[i]);

        auto primaryReq = _ControlTreeSpecReq(t.controlTree, null);
        for (uint i = 0; i < tries.Length; ++i) {
            auto s = tries[i];
            if (s is null) continue;
            uint matchedRootIx = uint(-1);
            auto n = _ResolveControlTreeSpec(s, primaryReq, matchedRootIx);
            if (n is null) continue;

            if (s.requireVisible && !IsEffectivelyVisible(n)) continue;

            st.lastResolveMs = Time::Now;
            @st.cachedControlTree = n;
            st.cachedControlTreeRootIx = matchedRootIx;
            st.cacheEpoch = UiNav::Context::Epoch();
            st.lastKind = BackendKind::ControlTree;
            st.cachedTargetConfigKey = targetConfigKey;

            auto r = NodeRef();
            r.kind = BackendKind::ControlTree;
            r.selector = _ControlTreeSpecDebugSelector(s);
            r.overlay = _ControlTreeSpecOverlay(s, primaryReq);
            r.rootIx = matchedRootIx;
            @r.controlTree = n;
            r.debug = "controlTree resolved";
            r.visibilityChecked = s.requireVisible;
            r.visibilityOk = s.requireVisible;
            r.resolvedAtMs = st.lastResolveMs;
            return r;
        }

        return null;
    }

    NodeRef@ ResolveML(Target@ t, _TargetPlan@ plan = null, _TargetState@ st = null) {
        if (t is null || t.ml is null) return null;
        if (st is null) @st = _GetTargetState(t);
        if (st is null) return null;

        string targetConfigKey = _TargetConfigKey(t);
        if (st.cachedTargetConfigKey.Length > 0 && st.cachedTargetConfigKey != targetConfigKey) {
            _ClearResolvedCache(st, "target config changed");
        }

        if (st.cachedMl !is null && st.cachedLayer !is null && st.cacheEpoch == UiNav::Context::Epoch() && (Time::Now - st.lastResolveMs) <= kTargetPointerCacheTtlMs) {
            auto req = _ManiaLinkSpecReq(t.ml, null);
            ManiaLinkSource resolvedSource = ManiaLinkSource::CurrentApp;
            CGameManiaApp@ app = null;
            bool ok = false;
            if (_ResolveMlSource(req, resolvedSource, app)) {
                int ix = st.cachedLayerIx;
                uint layersLen = UiNav::Layers::_LayerCountForSource(resolvedSource, app);
                if (ix >= 0 && ix < int(layersLen)) {
                    auto layer = UiNav::Layers::_LayerAtSource(resolvedSource, app, uint(ix));
                    if (layer !is null && layer is st.cachedLayer) {
                        if (st.cachedLocalPage !is null && layer.LocalPage is st.cachedLocalPage && app is st.cachedManiaApp) {
                            ok = true;
                        }
                        if (resolvedSource == ManiaLinkSource::Editor && st.cachedManiaApp is null && layer.LocalPage is st.cachedLocalPage) {
                            ok = true;
                        }
                    }
                }
            }

            if (ok) {
                bool visReq = (t.ml !is null) ? t.ml.requireVisible : false;
                if (visReq && !UiNav::ML::IsEffectivelyVisible(st.cachedMl)) {
                    ok = false;
                }
            }

            if (ok) {
                auto r = NodeRef();
                r.kind = BackendKind::ML;
                r.source = resolvedSource;
                @r.maniaApp = st.cachedManiaApp;
                @r.localPage = st.cachedLocalPage;
                @r.layer = st.cachedLayer;
                r.layerIx = st.cachedLayerIx;
                r.selector = (st.cachedMlSelector.Length > 0) ? st.cachedMlSelector : _ManiaLinkSpecSelector(t.ml);
                @r.ml = st.cachedMl;
                r.debug = "cached ml (validated)";
                r.visibilityChecked = (t.ml !is null) ? t.ml.requireVisible : false;
                r.visibilityOk = r.visibilityChecked;
                r.resolvedAtMs = st.lastResolveMs;
                return r;
            }

            @st.cachedMl = null;
            @st.cachedLayer = null;
            st.cachedLayerIx = -1;
            @st.cachedManiaApp = null;
            @st.cachedLocalPage = null;
            st.cachedMlSelector = "";
            st.cacheEpoch = 0;
        }

        array<ManiaLinkSpec@> tries;
        tries.InsertLast(t.ml);
        for (uint i = 0; i < t.ml.alts.Length; ++i) tries.InsertLast(t.ml.alts[i]);

        auto primaryReq = _ManiaLinkSpecReq(t.ml, null);
        for (uint i = 0; i < tries.Length; ++i) {
            auto s = tries[i];
            auto req = _ManiaLinkSpecReq(s, primaryReq);
            if (s is null || req is null) continue;

            int layerIx = -1;
            auto layer = UiNav::Layers::FindLayer(req, layerIx);
            if (layer is null) continue;

            auto page = layer.LocalPage;
            if (page is null) continue;

            auto root = page.MainFrame;
            if (root is null) continue;

            CGameManialinkControl@ node = null;
            string resolvedSelector = _ManiaLinkSpecSelector(s);
            bool usePrepared = (i == 0 && plan !is null && plan.mlRef is s && plan.mlToksReady && plan.mlToks !is null);
            if (usePrepared) {
                @node = UiNav::ML::ResolveSelectorPrepared(plan.mlToks, root);
                if (plan.mlSelectorTrim.Length > 0) resolvedSelector = plan.mlSelectorTrim;
            } else {
                @node = UiNav::ML::ResolveSelector(resolvedSelector, root);
            }
            if (node is null) continue;

            if (layer.LocalPage !is page) continue;

            if (s.requireVisible && !UiNav::ML::IsEffectivelyVisible(node)) continue;

            ManiaLinkSource resolvedSource = ManiaLinkSource::CurrentApp;
            CGameManiaApp@ appNow = null;
            if (!_ResolveMlSource(req, resolvedSource, appNow)) continue;

            st.lastResolveMs = Time::Now;
            @st.cachedLayer = layer;
            st.cachedLayerIx = layerIx;
            @st.cachedMl = node;
            @st.cachedManiaApp = appNow;
            @st.cachedLocalPage = page;
            st.cachedMlSelector = resolvedSelector;
            st.cacheEpoch = UiNav::Context::Epoch();
            st.lastKind = BackendKind::ML;
            st.cachedTargetConfigKey = targetConfigKey;

            auto r = NodeRef();
            r.kind = BackendKind::ML;
            r.source = resolvedSource;
            @r.maniaApp = appNow;
            @r.localPage = page;
            @r.layer = layer;
            r.layerIx = layerIx;
            r.selector = resolvedSelector;
            @r.ml = node;
            r.debug = "ml resolved";
            r.visibilityChecked = s.requireVisible;
            r.visibilityOk = s.requireVisible;
            r.resolvedAtMs = st.lastResolveMs;
            return r;
        }

        return null;
    }

    NodeRef@ _ResolveInternal(Target@ t, bool checkRequirements = true, _TargetPlan@ plan = null) {
        if (t is null) return null;
        uint startedAt = Time::Now;
        auto st = _GetTargetState(t);
        if (st is null) return null;

        if (plan is null) {
            @plan = _EnsureTargetPlan(t, st);
        }

        UiNav::Context::Refresh();
        uint epochNow = UiNav::Context::Epoch();
        if (st.cacheEpoch != 0 && st.cacheEpoch != epochNow) {
            _ClearResolvedCache(st, "cache invalidated");
        }

        UiNav::Trace::Ev("Resolve.begin", t);

        if (checkRequirements && t.req !is null) {
            bool reqOk = CheckRequirements(t, plan);
            if (!reqOk) {
                _ClearResolvedCache(st, "requirements failed");
                if (t.req.strict) {
                    UiNav::Metrics::Record("resolve", Time::Now - startedAt);
                    return null;
                }
            }
        }

        NodeRef@ r = null;
        bool hasCt = t.controlTree !is null;
        bool hasMl = t.ml !is null;

        if (hasCt && hasMl && t.pref == BackendPref::Unspecified) {
            st.lastDebug = "backend preference required when both ml and controlTree are configured";
            UiNav::Trace::Ev("Resolve.fail", t, null, st.lastDebug);
            UiNav::Metrics::Record("resolve", Time::Now - startedAt);
            return null;
        }

        if (!hasCt && !hasMl) {
            st.lastDebug = "resolve failed";
            UiNav::Trace::Ev("Resolve.fail", t, null, st.lastDebug);
            UiNav::Metrics::Record("resolve", Time::Now - startedAt);
            return null;
        }

        if (hasCt && !hasMl) {
            @r = ResolveControlTree(t, st);
        } else if (hasMl && !hasCt) {
            @r = ResolveML(t, plan, st);
        } else if (t.pref == BackendPref::PreferControlTree) {
            @r = ResolveControlTree(t, st);
            if (r is null) @r = ResolveML(t, plan, st);
        } else {
            @r = ResolveML(t, plan, st);
            if (r is null) @r = ResolveControlTree(t, st);
        }

        if (r is null) st.lastDebug = "resolve failed";
        else st.lastDebug = r.debug;

        if (r is null) UiNav::Trace::Ev("Resolve.fail", t, null, st.lastDebug);
        else UiNav::Trace::Ev("Resolve.ok", t, r);
        UiNav::Metrics::Record("resolve", Time::Now - startedAt);
        return r;
    }

    NodeRef@ Resolve(Target@ t) {
        return _ResolveInternal(t, true, null);
    }

    

    string _OpStatusName(OpStatus s) {
        if (s == OpStatus::Ok) return "Ok";
        if (s == OpStatus::InvalidTarget) return "InvalidTarget";
        if (s == OpStatus::RequirementsFailed) return "RequirementsFailed";
        if (s == OpStatus::ResolveFailed) return "ResolveFailed";
        if (s == OpStatus::InvalidBackendRef) return "InvalidBackendRef";
        if (s == OpStatus::NotVisible) return "NotVisible";
        if (s == OpStatus::ActionFailed) return "ActionFailed";
        if (s == OpStatus::TimedOut) return "TimedOut";
        return "Unknown";
    }

    OpResult@ _MakeOpResult(OpStatus status, NodeRef@ r = null, const string &in reason = "", const string &in text = "") {
        OpResult@ res = OpResult();
        res.status = status;
        res.kind = (r is null) ? BackendKind::None : r.kind;
        res.reason = reason;
        res.text = text;
        @res.ref = r;
        return res;
    }

    OpResult@ _DoneOp(const string &in metricName, uint startedAt, OpResult@ res) {
        UiNav::Metrics::Record(metricName, Time::Now - startedAt);
        return res;
    }

    OpResult@ _ResolveForOp(Target@ t, const string &in opName) {
        if (t is null) {
            auto res = _MakeOpResult(OpStatus::InvalidTarget, null, "target is null");
            UiNav::Trace::Ev(opName + ".fail", null, null, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return res;
        }

        auto st = _GetTargetState(t);
        auto plan = _EnsureTargetPlan(t, st);

        if (t.req !is null) {
            if (!CheckRequirements(t, plan)) {
                auto res = _MakeOpResult(OpStatus::RequirementsFailed, null, "requirements failed");
                UiNav::Trace::Ev(opName + ".fail", t, null, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
                return res;
            }
        }

        NodeRef@ r = _ResolveInternal(t, false, plan);
        if (r is null || r.IsNull()) {
            auto res = _MakeOpResult(OpStatus::ResolveFailed, r, "resolve failed");
            UiNav::Trace::Ev(opName + ".fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return res;
        }

        if (r.kind == BackendKind::ML) {
            if (!UiNav::ML::ValidateRef(r)) {
                auto res = _MakeOpResult(OpStatus::InvalidBackendRef, r, "ValidateRef failed");
                UiNav::Trace::Ev(opName + ".fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
                return res;
            }
        }

        if (!_CheckReqVisible(t, r)) {
            auto res = _MakeOpResult(OpStatus::NotVisible, r, "target not visible");
            UiNav::Trace::Ev(opName + ".fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return res;
        }

        return _MakeOpResult(OpStatus::Ok, r);
    }

    OpResult@ IsReadyEx(Target@ t) {
        uint startedAt = Time::Now;
        auto res = _ResolveForOp(t, "IsReady");
        if (res.Ok() && t !is null) {
            UiNav::Trace::Ev("IsReady.ok", t, res.ref);
        }
        return _DoneOp("is_ready", startedAt, res);
    }

    bool IsReady(Target@ t) {
        return IsReadyEx(t).Ok();
    }

    OpResult@ ClickEx(Target@ t) {
        uint startedAt = Time::Now;
        if (t !is null) UiNav::Trace::Ev("Click.begin", t);

        auto base = _ResolveForOp(t, "Click");
        if (!base.Ok()) return _DoneOp("click", startedAt, base);

        auto r = base.ref;
        bool ok = false;

        if (r.kind == BackendKind::ControlTree) {
            bool childFallback = (t.controlTree !is null) ? t.controlTree.clickChildFallback : true;
            ok = ClickControlNode(r.controlTree, childFallback);
        } else if (r.kind == BackendKind::ML) {
            bool childFallback = (t.ml !is null) ? t.ml.clickChildFallback : true;
            ok = UiNav::ML::Click(r.ml, childFallback);
        } else {
            auto res = _MakeOpResult(OpStatus::InvalidBackendRef, r, "unsupported backend");
            UiNav::Trace::Ev("Click.fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return _DoneOp("click", startedAt, res);
        }

        if (!ok) {
            auto res = _MakeOpResult(OpStatus::ActionFailed, r, "action failed");
            UiNav::Trace::Ev("Click.fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return _DoneOp("click", startedAt, res);
        }

        UiNav::Trace::Ev("Click.ok", t, r);
        return _DoneOp("click", startedAt, _MakeOpResult(OpStatus::Ok, r));
    }

    bool Click(Target@ t) {
        return ClickEx(t).Ok();
    }

    OpResult@ SetTextEx(Target@ t, const string &in text) {
        uint startedAt = Time::Now;
        if (t !is null) UiNav::Trace::Ev("SetText.begin", t);

        auto base = _ResolveForOp(t, "SetText");
        if (!base.Ok()) return _DoneOp("set_text", startedAt, base);

        auto r = base.ref;
        bool ok = false;

        if (r.kind == BackendKind::ControlTree) {
            ok = SetTextControlNode(r.controlTree, text);
        } else if (r.kind == BackendKind::ML) {
            ok = UiNav::ML::SetText(r.ml, text);
        } else {
            auto res = _MakeOpResult(OpStatus::InvalidBackendRef, r, "unsupported backend");
            UiNav::Trace::Ev("SetText.fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return _DoneOp("set_text", startedAt, res);
        }

        if (!ok) {
            auto res = _MakeOpResult(OpStatus::ActionFailed, r, "action failed");
            UiNav::Trace::Ev("SetText.fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
            return _DoneOp("set_text", startedAt, res);
        }

        UiNav::Trace::Ev("SetText.ok", t, r);
        return _DoneOp("set_text", startedAt, _MakeOpResult(OpStatus::Ok, r));
    }

    bool SetText(Target@ t, const string &in text) {
        return SetTextEx(t, text).Ok();
    }

    OpResult@ ReadTextEx(Target@ t) {
        uint startedAt = Time::Now;
        if (t !is null) UiNav::Trace::Ev("ReadText.begin", t);

        auto base = _ResolveForOp(t, "ReadText");
        if (!base.Ok()) return _DoneOp("read_text", startedAt, base);

        auto r = base.ref;
        if (r.kind == BackendKind::ControlTree) {
            string v = UiNav::ReadText(r.controlTree);
            UiNav::Trace::Ev("ReadText.ok", t, r, "len=" + v.Length);
            return _DoneOp("read_text", startedAt, _MakeOpResult(OpStatus::Ok, r, "", v));
        }
        if (r.kind == BackendKind::ML) {
            string v = UiNav::ML::ReadText(r.ml);
            UiNav::Trace::Ev("ReadText.ok", t, r, "len=" + v.Length);
            return _DoneOp("read_text", startedAt, _MakeOpResult(OpStatus::Ok, r, "", v));
        }

        auto res = _MakeOpResult(OpStatus::InvalidBackendRef, r, "unsupported backend");
        UiNav::Trace::Ev("ReadText.fail", t, r, "status=" + _OpStatusName(res.status) + " reason=" + res.reason);
        return _DoneOp("read_text", startedAt, res);
    }

    string ReadText(Target@ t) {
        auto res = ReadTextEx(t);
        if (!res.Ok()) return "";
        return res.text;
    }

    bool _ValidateMLRef(NodeRef@ r) {
        if (r is null) return false;
        if (r.kind != BackendKind::ML) return true;
        if (r.layer is null || r.ml is null) return false;
        if (r.localPage is null) return false;

        CGameManiaApp@ app = null;
        ManiaLinkSource resolvedSource = r.source;
        if (!UiNav::Layers::_ResolveLayerSource(r.source, resolvedSource, app)) return false;

        uint layersLen = UiNav::Layers::_LayerCountForSource(resolvedSource, app);
        for (uint i = 0; i < layersLen; ++i) {
            auto layer = UiNav::Layers::_LayerAtSource(resolvedSource, app, i);
            if (layer is r.layer) {
                if (resolvedSource != ManiaLinkSource::Editor && app !is r.maniaApp) return false;
                if (resolvedSource == ManiaLinkSource::Editor && r.maniaApp !is null) return false;
                return layer.LocalPage is r.localPage;
            }
        }

        return false;
    }

    bool _ControlTreeContainsNode(CControlBase@ root, CControlBase@ target, uint maxNodes = 120000) {
        if (root is null || target is null) return false;

        array<CControlBase@> q;
        q.InsertLast(root);

        uint head = 0;
        uint visited = 0;
        while (head < q.Length && visited < maxNodes) {
            auto cur = q[head++];
            if (cur is null) continue;
            visited++;

            if (cur is target) return true;

            uint len = _ChildrenLen(cur);
            for (uint i = 0; i < len; ++i) {
                auto ch = _ChildAt(cur, i);
                if (ch !is null) q.InsertLast(ch);
            }
        }

        return false;
    }

    bool _ValidateControlTreeRef(NodeRef@ r) {
        if (r is null) return false;
        if (r.kind != BackendKind::ControlTree) return true;
        if (r.controlTree is null) return false;
        if (r.overlay == uint(-1) || r.rootIx == uint(-1)) return false;

        CControlBase@ root = null;
        CScene2d@ scene;
        if (_GetScene2d(r.overlay, scene) && scene !is null && r.rootIx < scene.Mobils.Length) {
            @root = _RootFromMobil(scene, r.rootIx);
        }
        if (root is null && r.rootIx == 0) {
            @root = RootAtOverlay(r.overlay);
        }
        if (root is null) return false;

        return _ControlTreeContainsNode(root, r.controlTree);
    }

    bool ValidateRef(NodeRef@ r) {
        if (r is null) return false;
        if (r.kind == BackendKind::ML) return _ValidateMLRef(r);
        if (r.kind == BackendKind::ControlTree) return _ValidateControlTreeRef(r);
        return false;
    }

}

namespace UiNav {
namespace CT {

    bool ValidateRef(NodeRef@ r) {
        return UiNav::_ValidateControlTreeRef(r);
    }

}
}

namespace UiNav {
namespace ML {

    bool ValidateRef(NodeRef@ r) {
        return UiNav::_ValidateMLRef(r);
    }

}
}
