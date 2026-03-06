namespace UiNav {

    class _TargetPlan {
        uint uid = 0;

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

    dictionary g_TargetPlans;
    array<uint> g_TargetPlanOrder;
    const uint kTargetPlanMax = 512;
    uint g_TargetPlanNextUid = 1;
    uint g_TargetPlanHits = 0;
    uint g_TargetPlanMisses = 0;
    uint g_TargetPlanRebuilds = 0;

    void _ClearDisabledCaches(Target@ t) {
        if (t is null) return;
        if (t.cacheNativePointers && t.cacheTtlMs > 0) return;

        @t.cachedControlTree = null;
        @t.cachedMl = null;
        @t.cachedLayer = null;
        t.cachedLayerIx = -1;
        @t.cachedManiaApp = null;
        @t.cachedLocalPage = null;
        t.cachedMlSelector = "";
        t.cacheEpoch = 0;
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

    _TargetPlan@ _GetTargetPlan(Target@ t) {
        if (t is null) return null;

        if (t.planUid == 0) {
            t.planUid = g_TargetPlanNextUid++;
            if (g_TargetPlanNextUid == 0) g_TargetPlanNextUid = 1;
        }

        string key = tostring(t.planUid);
        _TargetPlan@ plan;
        if (g_TargetPlans.Get(key, @plan) && plan !is null) {
            g_TargetPlanHits++;
            return plan;
        }

        g_TargetPlanMisses++;
        @plan = _TargetPlan();
        plan.uid = t.planUid;
        g_TargetPlans.Set(key, @plan);
        g_TargetPlanOrder.InsertLast(t.planUid);

        if (g_TargetPlanOrder.Length > kTargetPlanMax) {
            uint oldUid = g_TargetPlanOrder[0];
            g_TargetPlanOrder.RemoveAt(0);
            g_TargetPlans.Delete(tostring(oldUid));
        }

        return plan;
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

    _TargetPlan@ _EnsureTargetPlan(Target@ t) {
        auto plan = _GetTargetPlan(t);
        _RefreshTargetPlan(t, plan);
        return plan;
    }

    void PrepareTarget(Target@ t) {
        _EnsureTargetPlan(t);
    }

    void InvalidateTargetPlan(Target@ t) {
        if (t is null || t.planUid == 0) return;
        uint uid = t.planUid;
        string key = tostring(uid);
        g_TargetPlans.Delete(key);
        for (uint i = 0; i < g_TargetPlanOrder.Length; ++i) {
            if (g_TargetPlanOrder[i] == uid) {
                g_TargetPlanOrder.RemoveAt(i);
                break;
            }
        }
        t.planUid = 0;
    }

    uint TargetPlanCacheHits() { return g_TargetPlanHits; }
    uint TargetPlanCacheMisses() { return g_TargetPlanMisses; }
    uint TargetPlanCacheRebuilds() { return g_TargetPlanRebuilds; }

    void ResetTargetPlanCacheStats() {
        g_TargetPlanHits = 0;
        g_TargetPlanMisses = 0;
        g_TargetPlanRebuilds = 0;
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
        if (r.kind == BackendKind::ML) return UiNav::ML::IsVisible(r.ml);
        return false;
    }

    bool _ControlTreeTokenIsInt(const string &in raw) {
        string s = raw.Trim();
        if (s.Length == 0) return false;
        int start = 0;
        if (s.StartsWith("-")) {
            if (s.Length == 1) return false;
            start = 1;
        }
        for (int i = start; i < int(s.Length); ++i) {
            string ch = s.SubStr(i, 1);
            if (ch < "0" || ch > "9") return false;
        }
        return true;
    }

    bool _ControlTreeTryParseBracketIntToken(const string &in rawToken, const string &in prefixLower, int &out value) {
        value = -1;
        string tok = rawToken.Trim().ToLower();
        if (!tok.StartsWith(prefixLower)) return false;
        int closeIx = tok.LastIndexOf("]");
        if (closeIx <= int(prefixLower.Length)) return false;
        string inner = tok.SubStr(int(prefixLower.Length), closeIx - int(prefixLower.Length)).Trim();
        if (!_ControlTreeTokenIsInt(inner)) return false;
        value = Text::ParseInt(inner);
        return value >= 0;
    }

    bool _ControlTreeHasLegacySeparator(const string &in rawPath) {
        return rawPath.IndexOf(">") >= 0;
    }

    void _ControlTreeSplitPathTokens(const string &in rawPath, array<string> &out outTokens) {
        outTokens.Resize(0);
        string path = rawPath.Trim();
        if (path.Length == 0) return;
        if (_ControlTreeHasLegacySeparator(path)) return;
        auto rawParts = path.Split("/");
        for (uint i = 0; i < rawParts.Length; ++i) {
            string t = rawParts[i].Trim();
            if (t.Length == 0) continue;
            outTokens.InsertLast(t);
        }
    }

    string _ControlTreeExtractIdToken(const string &in rawToken) {
        string tok = rawToken.Trim();
        if (tok.Length == 0) return "";

        int dummy = -1;
        if (_ControlTreeTryParseBracketIntToken(tok, "overlay[", dummy)) return "";
        if (_ControlTreeTryParseBracketIntToken(tok, "root[", dummy)) return "";
        if (_ControlTreeTokenIsInt(tok)) return "";
        if (tok.SubStr(0, 1) == "*") return "";

        string lower = tok.ToLower();
        if (lower.StartsWith("id:")) return tok.SubStr(3).Trim();
        if (tok.StartsWith("#")) return tok.SubStr(1).Trim();
        return tok;
    }

    bool _ControlTreePathNeedsMixedResolver(const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length == 0) return false;
        if (_ControlTreeHasLegacySeparator(p) || p.IndexOf("#") >= 0) return true;

        array<string> tokens;
        _ControlTreeSplitPathTokens(p, tokens);
        for (uint i = 0; i < tokens.Length; ++i) {
            string tok = tokens[i];
            if (tok.Length == 0) continue;
            if (tok.SubStr(0, 1) == "*") continue;
            if (_ControlTreeTokenIsInt(tok)) continue;

            int dummy = -1;
            if (_ControlTreeTryParseBracketIntToken(tok, "overlay[", dummy)) return true;
            if (_ControlTreeTryParseBracketIntToken(tok, "root[", dummy)) return true;
            if (tok.ToLower().StartsWith("id:")) return true;
            return true;
        }
        return false;
    }

    CControlBase@ _FindControlTreeDirectChildByIdName(CControlBase@ cur, const string &in wantLower) {
        if (cur is null || wantLower.Length == 0) return null;
        uint len = _ChildrenLen(cur);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(cur, i);
            if (ch is null) continue;
            string idName = ch.IdName.Trim();
            if (idName.Length > 0 && idName.ToLower() == wantLower) return ch;
        }
        return null;
    }

    CControlBase@ _ResolveControlTreeMixedPathFromRoot(CControlBase@ root, const array<string> &in tokens, uint startIx = 0) {
        if (root is null) return null;
        CControlBase@ cur = root;
        for (uint i = startIx; i < tokens.Length; ++i) {
            string tok = tokens[i].Trim();
            if (tok.Length == 0) continue;

            int dummy = -1;
            if (_ControlTreeTryParseBracketIntToken(tok, "overlay[", dummy)) continue;
            if (_ControlTreeTryParseBracketIntToken(tok, "root[", dummy)) continue;

            string idTok = _ControlTreeExtractIdToken(tok);
            if (idTok.Length > 0) {
                string wantLower = idTok.ToLower();
                string curId = cur.IdName.Trim().ToLower();
                if (curId.Length > 0 && curId == wantLower) continue;
                auto byId = _FindControlTreeDirectChildByIdName(cur, wantLower);
                if (byId is null) return null;
                @cur = byId;
                continue;
            }

            if (tok.SubStr(0, 1) == "*") {
                uint lenW = _ChildrenLen(cur);
                if (lenW == 0) return null;

                array<int> hints;
                _ParseWildcardHintsToken(tok, hints);
                if (hints.Length > 0) {
                    bool advanced = false;
                    for (uint h = 0; h < hints.Length; ++h) {
                        int hi = hints[h];
                        if (hi < 0) continue;
                        uint uhi = uint(hi);
                        if (uhi >= lenW) continue;
                        auto cand = _ChildAt(cur, uhi);
                        if (cand is null) continue;
                        @cur = cand;
                        advanced = true;
                        break;
                    }
                    if (!advanced) return null;
                } else {
                    auto cand0 = _ChildAt(cur, 0);
                    if (cand0 is null) return null;
                    @cur = cand0;
                }
                continue;
            }

            if (!_ControlTreeTokenIsInt(tok)) return null;

            int idx = Text::ParseInt(tok);
            if (idx < 0) return null;
            uint uidx = uint(idx);
            uint len = _ChildrenLen(cur);
            if (uidx >= len) return null;
            auto ch = _ChildAt(cur, uidx);
            if (ch is null) return null;
            @cur = ch;
        }
        return cur;
    }

    string _ControlTreeSpecSelector(ControlTreeSpec@ s) {
        if (s is null) return "";
        string selector = s.selector.Trim();
        if (selector.Length > 0) return selector;
        return s.path.Trim();
    }

    uint _ControlTreeSpecOverlay(ControlTreeSpec@ s) {
        if (s is null) return 16;
        if (s.req !is null) return s.req.overlay;
        return s.overlay;
    }

    bool _ControlTreeSpecAnyRoot(ControlTreeSpec@ s) {
        if (s is null) return false;
        if (s.req !is null) return s.req.anyRoot;
        return s.anyRoot;
    }

    uint _ControlTreeSpecMaxRoots(ControlTreeSpec@ s) {
        if (s is null) return 24;
        if (s.req !is null) return s.req.maxRoots;
        return s.maxRoots;
    }

    bool _ControlTreeSpecHintsOnly(ControlTreeSpec@ s) {
        if (s is null) return false;
        if (s.req !is null) return s.req.hintsOnly;
        return s.hintsOnly;
    }

    bool _ControlTreeSpecSmart(ControlTreeSpec@ s) {
        if (s is null) return false;
        if (s.req !is null) return s.req.smart;
        return s.smart;
    }

    string _ControlTreeSpecGuardStartsWith(ControlTreeSpec@ s) {
        if (s is null) return "";
        if (s.req !is null) return s.req.guardStartsWith;
        return s.guardStartsWith;
    }

    CControlBase@ _ResolveControlTreeMixedPath(ControlTreeSpec@ s, const string &in rawPath) {
        if (s is null) return null;

        array<string> tokens;
        _ControlTreeSplitPathTokens(rawPath, tokens);
        if (tokens.Length == 0) return null;

        uint startIx = 0;
        int rootHint = -1;
        int overlayHint = -1;
        while (startIx < tokens.Length) {
            int parsed = -1;
            if (_ControlTreeTryParseBracketIntToken(tokens[startIx], "overlay[", parsed)) {
                overlayHint = parsed;
                startIx++;
                continue;
            }
            if (_ControlTreeTryParseBracketIntToken(tokens[startIx], "root[", parsed)) {
                rootHint = parsed;
                startIx++;
                continue;
            }
            break;
        }

        uint overlay = _ControlTreeSpecOverlay(s);
        if (overlayHint >= 0) overlay = uint(overlayHint);

        if (rootHint >= 0) {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene) || scene is null) return null;
            if (uint(rootHint) >= scene.Mobils.Length) return null;
            auto root = _RootFromMobil(scene, uint(rootHint));
            if (root is null) return null;
            return _ResolveControlTreeMixedPathFromRoot(root, tokens, startIx);
        }

        if (_ControlTreeSpecAnyRoot(s)) {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene) || scene is null) return null;
            uint roots = Math::Min(_ControlTreeSpecMaxRoots(s), scene.Mobils.Length);
            for (uint r = 0; r < roots; ++r) {
                auto root = _RootFromMobil(scene, r);
                if (root is null) continue;
                auto found = _ResolveControlTreeMixedPathFromRoot(root, tokens, startIx);
                if (found !is null) return found;
            }
            return null;
        }

        CControlFrame@ root = RootAtOverlay(overlay);
        if (root is null) return null;
        return _ResolveControlTreeMixedPathFromRoot(root, tokens, startIx);
    }

    CControlBase@ _FindControlTreeByIdNameRec(CControlBase@ cur, const string &in wantLower, uint depth = 0, uint maxDepth = 256) {
        if (cur is null) return null;
        if (depth > maxDepth) return null;

        string idName = cur.IdName.Trim();
        if (idName.Length > 0 && idName.ToLower() == wantLower) return cur;

        uint len = _ChildrenLen(cur);
        for (uint i = 0; i < len; ++i) {
            auto ch = _ChildAt(cur, i);
            if (ch is null) continue;
            auto found = _FindControlTreeByIdNameRec(ch, wantLower, depth + 1, maxDepth);
            if (found !is null) return found;
        }
        return null;
    }

    CControlBase@ _ResolveControlTreeByIdName(ControlTreeSpec@ s) {
        if (s is null) return null;
        string want = s.idName.Trim().ToLower();
        if (want.Length == 0) return null;

        uint overlay = _ControlTreeSpecOverlay(s);
        if (_ControlTreeSpecAnyRoot(s)) {
            CScene2d@ scene;
            if (!_GetScene2d(overlay, scene)) return null;
            uint roots = Math::Min(_ControlTreeSpecMaxRoots(s), scene.Mobils.Length);
            for (uint r = 0; r < roots; ++r) {
                CControlFrame@ root = _RootFromMobil(scene, r);
                if (root is null) continue;
                auto found = _FindControlTreeByIdNameRec(root, want);
                if (found !is null) return found;
            }
            return null;
        }

        CControlFrame@ root = RootAtOverlay(overlay);
        if (root is null) return null;
        return _FindControlTreeByIdNameRec(root, want);
    }

    string _ControlTreeSpecDebugSelector(ControlTreeSpec@ s) {
        if (s is null) return "";
        string selector = _ControlTreeSpecSelector(s);
        if (selector.Length > 0) return selector;
        if (s.idName.Length > 0) return "id:" + s.idName;
        return "";
    }

    CControlBase@ _ResolveControlTreeSpec(ControlTreeSpec@ s) {
        if (s is null) return null;
        uint overlay = _ControlTreeSpecOverlay(s);

        string path = _ControlTreeSpecSelector(s);
        if (_ControlTreeHasLegacySeparator(path)) return null;
        if (path.Length > 0) {
            bool mixedSyntax = _ControlTreePathNeedsMixedResolver(path);
            if (mixedSyntax) {
                auto mixed = _ResolveControlTreeMixedPath(s, path);
                if (mixed !is null) return mixed;
                return _ResolveControlTreeByIdName(s);
            }

            if (_ControlTreeSpecAnyRoot(s)) {
                if (SpecHasWildcard(path)) {
                    if (_ControlTreeSpecHintsOnly(s)) return ResolvePathHintsOnlyAnyRoot(path, overlay);
                    return ResolvePathAnyRoot(path, overlay, _ControlTreeSpecMaxRoots(s));
                }
                return ResolvePathExactAnyRoot(path, overlay);
            }

            if (_ControlTreeSpecHintsOnly(s)) {
                return ResolvePathHintsOnly(path, overlay);
            }

            if (_ControlTreeSpecSmart(s)) {
                string guard = _ControlTreeSpecGuardStartsWith(s);
                if (guard.Length > 0) {
                    return ResolvePathSmartGuarded(path, guard, overlay);
                }
                return ResolvePathSmart(path, overlay);
            }

            auto resolved = ResolvePath(path, overlay);
            if (resolved !is null) return resolved;
        }

        return _ResolveControlTreeByIdName(s);
    }

    ManiaLinkReq@ _ManiaLinkSpecReq(ManiaLinkSpec@ s) {
        if (s is null) return null;
        if (s.req !is null) return s.req;
        return s.layer;
    }

    string _ManiaLinkSpecSelector(ManiaLinkSpec@ s) {
        if (s is null) return "";
        return s.selector.Trim();
    }

    NodeRef@ ResolveControlTree(Target@ t) {
        if (t is null || t.controlTree is null) return null;

        if (t.cacheNativePointers && t.cacheTtlMs > 0 && t.cachedControlTree !is null && t.cacheEpoch == UiNav::Context::Epoch() && (Time::Now - t.lastResolveMs) <= t.cacheTtlMs) {
            if (t.controlTree.requireVisible && !IsEffectivelyVisible(t.cachedControlTree)) {
                @t.cachedControlTree = null;
                t.cacheEpoch = 0;
            } else {
                auto r = NodeRef();
                r.kind = BackendKind::ControlTree;
                r.overlay = _ControlTreeSpecOverlay(t.controlTree);
                r.path = _ControlTreeSpecDebugSelector(t.controlTree);
                @r.controlTree = t.cachedControlTree;
                r.debug = "cached controlTree";
                r.visibilityChecked = t.controlTree.requireVisible;
                r.visibilityOk = t.controlTree.requireVisible;
                r.resolvedAtMs = t.lastResolveMs;
                return r;
            }
        }

        array<ControlTreeSpec@> tries;
        tries.InsertLast(t.controlTree);
        for (uint i = 0; i < t.controlTree.alts.Length; ++i) tries.InsertLast(t.controlTree.alts[i]);

        for (uint i = 0; i < tries.Length; ++i) {
            auto s = tries[i];
            auto n = _ResolveControlTreeSpec(s);
            if (n is null) continue;

            if (s.requireVisible && !IsEffectivelyVisible(n)) continue;

            t.lastResolveMs = Time::Now;
            if (t.cacheNativePointers && t.cacheTtlMs > 0) {
                @t.cachedControlTree = n;
                t.cacheEpoch = UiNav::Context::Epoch();
            } else {
                @t.cachedControlTree = null;
                t.cacheEpoch = 0;
            }
            t.lastKind = BackendKind::ControlTree;

            auto r = NodeRef();
            r.kind = BackendKind::ControlTree;
            r.overlay = _ControlTreeSpecOverlay(s);
            r.path = _ControlTreeSpecDebugSelector(s);
            @r.controlTree = n;
            r.debug = "controlTree resolved";
            r.visibilityChecked = s.requireVisible;
            r.visibilityOk = s.requireVisible;
            r.resolvedAtMs = t.lastResolveMs;
            return r;
        }

        return null;
    }

    NodeRef@ ResolveML(Target@ t, _TargetPlan@ plan = null) {
        if (t is null || t.ml is null) return null;

        if (t.cacheNativePointers && t.cacheTtlMs > 0 && t.cachedMl !is null && t.cachedLayer !is null && t.cacheEpoch == UiNav::Context::Epoch() && (Time::Now - t.lastResolveMs) <= t.cacheTtlMs) {
            auto app = UiNav::Layers::GetManiaApp();
            bool ok = false;
            if (app !is null && app is t.cachedManiaApp) {
                auto layers = app.UILayers;
                int ix = t.cachedLayerIx;
                if (ix >= 0 && ix < int(layers.Length) && layers[uint(ix)] is t.cachedLayer) {
                    if (t.cachedLocalPage !is null && layers[uint(ix)].LocalPage is t.cachedLocalPage) {
                        ok = true;
                    }
                }
            }

            if (ok) {
                bool visReq = (t.ml !is null) ? t.ml.requireVisible : false;
                if (visReq && !UiNav::ML::IsVisible(t.cachedMl)) {
                    ok = false;
                }
            }

            if (ok) {
                auto r = NodeRef();
                r.kind = BackendKind::ML;
                @r.maniaApp = t.cachedManiaApp;
                @r.localPage = t.cachedLocalPage;
                @r.layer = t.cachedLayer;
                r.selector = (t.cachedMlSelector.Length > 0) ? t.cachedMlSelector : _ManiaLinkSpecSelector(t.ml);
                @r.ml = t.cachedMl;
                r.debug = "cached ml (validated)";
                r.visibilityChecked = (t.ml !is null) ? t.ml.requireVisible : false;
                r.visibilityOk = r.visibilityChecked;
                r.resolvedAtMs = t.lastResolveMs;
                return r;
            }

            @t.cachedMl = null;
            @t.cachedLayer = null;
            t.cachedLayerIx = -1;
            @t.cachedManiaApp = null;
            @t.cachedLocalPage = null;
            t.cachedMlSelector = "";
            t.cacheEpoch = 0;
        }

        array<ManiaLinkSpec@> tries;
        tries.InsertLast(t.ml);
        for (uint i = 0; i < t.ml.alts.Length; ++i) tries.InsertLast(t.ml.alts[i]);

        for (uint i = 0; i < tries.Length; ++i) {
            auto s = tries[i];
            auto req = _ManiaLinkSpecReq(s);
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

            if (s.requireVisible && !UiNav::ML::IsVisible(node)) continue;

            t.lastResolveMs = Time::Now;
            auto appNow = UiNav::Layers::GetManiaApp();
            if (t.cacheNativePointers && t.cacheTtlMs > 0) {
                @t.cachedLayer = layer;
                t.cachedLayerIx = layerIx;
                @t.cachedMl = node;
                @t.cachedManiaApp = appNow;
                @t.cachedLocalPage = page;
                t.cachedMlSelector = resolvedSelector;
                t.cacheEpoch = UiNav::Context::Epoch();
            } else {
                @t.cachedLayer = null;
                t.cachedLayerIx = -1;
                @t.cachedMl = null;
                @t.cachedManiaApp = null;
                @t.cachedLocalPage = null;
                t.cachedMlSelector = "";
                t.cacheEpoch = 0;
            }
            t.lastKind = BackendKind::ML;

            auto r = NodeRef();
            r.kind = BackendKind::ML;
            @r.maniaApp = appNow;
            @r.localPage = page;
            @r.layer = layer;
            r.selector = resolvedSelector;
            @r.ml = node;
            r.debug = "ml resolved";
            r.visibilityChecked = s.requireVisible;
            r.visibilityOk = s.requireVisible;
            r.resolvedAtMs = t.lastResolveMs;
            return r;
        }

        return null;
    }

    NodeRef@ _ResolveInternal(Target@ t, bool checkRequirements = true, _TargetPlan@ plan = null) {
        if (t is null) return null;
        uint startedAt = Time::Now;

        if (plan is null) {
            @plan = _EnsureTargetPlan(t);
        }

        UiNav::Context::Refresh();
        uint epochNow = UiNav::Context::Epoch();
        if (t.cacheEpoch != 0 && t.cacheEpoch != epochNow) {
            t.InvalidateCache();
        }

        _ClearDisabledCaches(t);
        UiNav::Trace::Ev("Resolve.begin", t);

        if (checkRequirements && t.req !is null) {
            bool reqOk = CheckRequirements(t, plan);
            if (!reqOk) {
                t.InvalidateCache();
                t.lastDebug = "requirements failed";
                if (t.req.strict) {
                    UiNav::Metrics::Record("resolve", Time::Now - startedAt);
                    return null;
                }
            }
        }

        NodeRef@ r = null;

        if (t.pref == BackendPref::PreferControlTree) {
            @r = ResolveControlTree(t);
            if (r is null) @r = ResolveML(t, plan);
        } else if (t.pref == BackendPref::PreferML) {
            @r = ResolveML(t, plan);
            if (r is null) @r = ResolveControlTree(t);
        } else {
            if (t.ml !is null) {
                @r = ResolveML(t, plan);
                if (r is null) @r = ResolveControlTree(t);
            } else {
                @r = ResolveControlTree(t);
            }
        }

        if (r is null) t.lastDebug = "resolve failed";
        else t.lastDebug = r.debug;

        if (r is null) UiNav::Trace::Ev("Resolve.fail", t, null, t.lastDebug);
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

        auto plan = _EnsureTargetPlan(t);

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
            if (!ValidateML(r)) {
                auto res = _MakeOpResult(OpStatus::InvalidBackendRef, r, "ValidateML failed");
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

    bool ValidateML(NodeRef@ r) {
        if (r is null) return false;
        if (r.kind != BackendKind::ML) return true;
        if (r.layer is null || r.ml is null) return false;

        if (r.maniaApp is null || r.localPage is null) return false;

        auto app = UiNav::Layers::GetManiaApp();
        if (app is null) return false;
        if (app !is r.maniaApp) return false;

        auto layers = app.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            if (layers[i] is r.layer) {
                return layers[i].LocalPage is r.localPage;
            }
        }

        return false;
    }

}
