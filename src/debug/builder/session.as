namespace UiNav {
namespace Builder {

    CGameManiaApp@ _GetAppByKind(int appKind) {
        if (appKind == 0) return UiNav::Layers::GetManiaAppPlayground();
        if (appKind == 1) return UiNav::Layers::GetManiaAppMenu();
        return UiNav::Layers::GetManiaApp();
    }

    CGameUILayer@ _GetLayerByKindIx(int appKind, int layerIx) {
        if (layerIx < 0) return null;
        auto app = _GetAppByKind(appKind);
        if (app is null) return null;
        auto layers = app.UILayers;
        if (layerIx < 0 || layerIx >= int(layers.Length)) return null;
        return layers[uint(layerIx)];
    }

    string _GetLayerXml(CGameUILayer@ layer) {
        if (layer is null) return "";
        string xml = "";
        try { xml = layer.ManialinkPageUtf8; } catch { xml = ""; }
        if (xml.Length == 0) {
            try { xml = "" + layer.ManialinkPage; } catch { xml = ""; }
        }
        return xml;
    }

    void _UpdateDirtyState() {
        _EnsureDoc();
        string nowXml = ExportToXml(g_Doc);
        g_Doc.dirty = nowXml != g_BaselineXml;
        g_LastExportXml = nowXml;
    }

    void _QueueAutoPreview() {
        if (!S_AutoLivePreview) return;
        g_AutoPreviewPending = true;
        g_AutoPreviewQueuedMs = Time::Now;
    }

    void TickAutoPreview() {
        if (!S_AutoLivePreview) return;
        if (!g_AutoPreviewPending) return;

        uint now = Time::Now;
        uint debounce = S_AutoLivePreviewDebounceMs;
        if (now - g_AutoPreviewQueuedMs < debounce) return;

        bool ok = _ApplyPreviewLayerInternal(false);
        if (ok) {
            g_AutoPreviewPending = false;
        } else {
            g_AutoPreviewQueuedMs = now;
        }
    }

    class _CenterBoundsState {
        bool has = false;
        vec2 minP = vec2();
        vec2 maxP = vec2();
    }

    void _CenterBoundsVisit(const BuilderDocument@ doc, int nodeIx, const vec2 &in parentPos, float parentScale, _CenterBoundsState@ st) {
        if (doc is null || st is null) return;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return;
        auto n = doc.nodes[uint(nodeIx)];
        if (n is null || n.typed is null) return;

        vec2 absPos = parentPos + n.typed.pos * parentScale;
        float absScale = parentScale * n.typed.scale;
        vec2 absSize = n.typed.size * absScale;

        float ax = 0.5f;
        float ay = 0.5f;
        {
            string h = n.typed.hAlign.Trim().ToLower();
            if (h == "left") ax = 0.0f;
            else if (h == "right") ax = 1.0f;
            else ax = 0.5f;

            string v = n.typed.vAlign.Trim().ToLower();
            if (v == "top") ay = 0.0f;
            else if (v == "bottom") ay = 1.0f;
            else if (v == "center" || v == "vcenter" || v == "center2" || v == "vcenter2") ay = 0.5f;
            else ay = 0.5f;
        }

        vec2 bMin = vec2(absPos.x - ax * absSize.x, absPos.y - (1.0f - ay) * absSize.y);
        vec2 bMax = vec2(absPos.x + (1.0f - ax) * absSize.x, absPos.y + ay * absSize.y);

        if (!st.has) {
            st.has = true;
            st.minP = bMin;
            st.maxP = bMax;
        } else {
            if (bMin.x < st.minP.x) st.minP.x = bMin.x;
            if (bMin.y < st.minP.y) st.minP.y = bMin.y;
            if (bMax.x > st.maxP.x) st.maxP.x = bMax.x;
            if (bMax.y > st.maxP.y) st.maxP.y = bMax.y;
        }

        for (uint i = 0; i < n.childIx.Length; ++i) {
            _CenterBoundsVisit(doc, n.childIx[i], absPos, absScale, st);
        }
    }

    bool _CenterDocumentRoots(BuilderDocument@ doc) {
        if (doc is null) return false;
        auto st = _CenterBoundsState();

        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null || n.parentIx >= 0) continue;
            _CenterBoundsVisit(doc, int(i), vec2(), 1.0f, st);
        }
        if (!st.has) return false;

        vec2 center = (st.minP + st.maxP) * 0.5f;
        vec2 delta = vec2(-center.x, -center.y);
        if (Math::Abs(delta.x) < 0.001f && Math::Abs(delta.y) < 0.001f) return true;

        bool movedAny = false;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null || n.parentIx >= 0 || n.typed is null) continue;
            n.typed.pos += delta;
            movedAny = true;
        }
        return movedAny;
    }

    class _PreviewBoundsState {
        bool hasAll = false;
        vec2 minAll = vec2();
        vec2 maxAll = vec2();

        bool hasVisible = false;
        vec2 minVisible = vec2();
        vec2 maxVisible = vec2();

        int nodesWithTyped = 0;
        int nodesHiddenSelf = 0;
        int nodesHiddenByAncestor = 0;
        int nodesUnderClipAncestor = 0;
        int clipActiveFrames = 0;
    }

    float _AnchorXFromHAlign(const string &in hAlign) {
        string h = hAlign.Trim().ToLower();
        if (h == "left") return 0.0f;
        if (h == "center" || h == "hcenter") return 0.5f;
        if (h == "right") return 1.0f;
        return 0.5f;
    }

    float _AnchorYFromVAlign(const string &in vAlign) {
        string v = vAlign.Trim().ToLower();
        if (v == "top") return 0.0f;
        if (v == "center" || v == "vcenter" || v == "center2" || v == "vcenter2") return 0.5f;
        if (v == "bottom") return 1.0f;
        return 0.5f;
    }

    class BuilderAbsMetrics {
        bool ok = false;

        vec2 absPos = vec2();
        float absScale = 1.0f;

        vec2 absSize = vec2();
        vec2 boundsMin = vec2();
        vec2 boundsMax = vec2();
        float anchorX = 0.5f;
        float anchorY = 0.5f;

        bool hiddenByAncestor = false;
        bool selfHidden = false;
        bool underClipAncestor = false;
        int clipAncestorCount = 0;
    }

    BuilderAbsMetrics@ ComputeAbsMetrics(const BuilderDocument@ doc, int nodeIx) {
        auto m = BuilderAbsMetrics();
        if (doc is null) return m;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return m;

        array<int> chain;
        int cur = nodeIx;
        int guard = 0;
        while (cur >= 0 && cur < int(doc.nodes.Length) && guard < 512) {
            guard++;
            chain.InsertLast(cur);
            auto n = doc.nodes[uint(cur)];
            if (n is null) break;
            cur = n.parentIx;
        }
        if (chain.Length == 0) return m;

        vec2 absPos = vec2();
        float parentScale = 1.0f;
        bool hiddenAncestor = false;
        int clipAnc = 0;

        for (int i = int(chain.Length) - 1; i >= 0; --i) {
            int ix = chain[uint(i)];
            auto n = doc.nodes[uint(ix)];
            if (n is null || n.typed is null) return m;

            bool isSelf = (i == 0);
            if (!isSelf) {
                if (!n.typed.visible) hiddenAncestor = true;
                if (n.kind == "frame" && n.typed.clipActive) clipAnc++;
            } else {
                if (!n.typed.visible) m.selfHidden = true;
            }

            absPos = absPos + n.typed.pos * parentScale;
            parentScale *= n.typed.scale;
        }

        auto self = doc.nodes[uint(nodeIx)];
        if (self is null || self.typed is null) return m;

        m.ok = true;
        m.absPos = absPos;
        m.absScale = parentScale;
        m.anchorX = _AnchorXFromHAlign(self.typed.hAlign);
        m.anchorY = _AnchorYFromVAlign(self.typed.vAlign);

        m.absSize = self.typed.size * m.absScale;
        m.boundsMin = vec2(absPos.x - m.anchorX * m.absSize.x, absPos.y - (1.0f - m.anchorY) * m.absSize.y);
        m.boundsMax = vec2(absPos.x + (1.0f - m.anchorX) * m.absSize.x, absPos.y + m.anchorY * m.absSize.y);

        m.hiddenByAncestor = hiddenAncestor;
        m.clipAncestorCount = clipAnc;
        m.underClipAncestor = clipAnc > 0;
        return m;
    }

    void _BoundsUpdateAll(_PreviewBoundsState@ st, const vec2 &in bMin, const vec2 &in bMax) {
        if (st is null) return;
        if (!st.hasAll) {
            st.hasAll = true;
            st.minAll = bMin;
            st.maxAll = bMax;
            return;
        }
        if (bMin.x < st.minAll.x) st.minAll.x = bMin.x;
        if (bMin.y < st.minAll.y) st.minAll.y = bMin.y;
        if (bMax.x > st.maxAll.x) st.maxAll.x = bMax.x;
        if (bMax.y > st.maxAll.y) st.maxAll.y = bMax.y;
    }

    void _BoundsUpdateVisible(_PreviewBoundsState@ st, const vec2 &in bMin, const vec2 &in bMax) {
        if (st is null) return;
        if (!st.hasVisible) {
            st.hasVisible = true;
            st.minVisible = bMin;
            st.maxVisible = bMax;
            return;
        }
        if (bMin.x < st.minVisible.x) st.minVisible.x = bMin.x;
        if (bMin.y < st.minVisible.y) st.minVisible.y = bMin.y;
        if (bMax.x > st.maxVisible.x) st.maxVisible.x = bMax.x;
        if (bMax.y > st.maxVisible.y) st.maxVisible.y = bMax.y;
    }

    void _PreviewBoundsVisit(const BuilderDocument@ doc, int nodeIx, const vec2 &in parentPos, float parentScale, bool hiddenAncestor, int clipDepth, _PreviewBoundsState@ st) {
        if (doc is null || st is null) return;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return;
        auto n = doc.nodes[uint(nodeIx)];
        if (n is null) return;

        bool selfHidden = false;
        bool hasTyped = n.typed !is null;
        if (hasTyped) {
            st.nodesWithTyped++;
            if (!n.typed.visible) {
                st.nodesHiddenSelf++;
                selfHidden = true;
            }
        }

        bool nowHiddenAncestor = hiddenAncestor || selfHidden;
        if (hiddenAncestor && !selfHidden) st.nodesHiddenByAncestor++;
        if (clipDepth > 0) st.nodesUnderClipAncestor++;

        vec2 absPos = parentPos;
        float absScale = parentScale;
        if (hasTyped) {
            absPos = parentPos + n.typed.pos * parentScale;
            absScale = parentScale * n.typed.scale;

            vec2 absSize = n.typed.size * absScale;
            float ax = _AnchorXFromHAlign(n.typed.hAlign);
            float ay = _AnchorYFromVAlign(n.typed.vAlign);
            vec2 bMin = vec2(absPos.x - ax * absSize.x, absPos.y - (1.0f - ay) * absSize.y);
            vec2 bMax = vec2(absPos.x + (1.0f - ax) * absSize.x, absPos.y + ay * absSize.y);
            _BoundsUpdateAll(st, bMin, bMax);
            if (!nowHiddenAncestor) {
                _BoundsUpdateVisible(st, bMin, bMax);
            }
        }

        bool isClipFrame = false;
        if (n.kind == "frame" && hasTyped && n.typed.clipActive) {
            st.clipActiveFrames++;
            isClipFrame = true;
        }
        int nextClipDepth = clipDepth + (isClipFrame ? 1 : 0);

        for (uint i = 0; i < n.childIx.Length; ++i) {
            _PreviewBoundsVisit(doc, n.childIx[i], absPos, absScale, nowHiddenAncestor, nextClipDepth, st);
        }
    }

    void _ComputePreviewBounds(const BuilderDocument@ doc, _PreviewBoundsState@ st) {
        if (doc is null || st is null) return;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null || n.parentIx >= 0) continue;
            _PreviewBoundsVisit(doc, int(i), vec2(), 1.0f, false, 0, st);
        }
    }

    bool _TryLocateLayerInApp(CGameManiaApp@ app, const string &in appLabel, CGameUILayer@ layer, string &out foundLabel, int &out foundIx) {
        if (app is null || layer is null) return false;
        auto layers = app.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            if (layers[i] is layer) {
                foundLabel = appLabel;
                foundIx = int(i);
                return true;
            }
        }
        return false;
    }

    void _LocateOwnedPreviewLayer(CGameUILayer@ layer, string &out appLabel, int &out layerIx) {
        appLabel = "<unknown>";
        layerIx = -1;
        if (layer is null) return;

        if (_TryLocateLayerInApp(UiNav::Layers::GetManiaApp(), "Current", layer, appLabel, layerIx)) return;
        if (_TryLocateLayerInApp(UiNav::Layers::GetManiaAppMenu(), "Menu", layer, appLabel, layerIx)) return;
        if (_TryLocateLayerInApp(UiNav::Layers::GetManiaAppPlayground(), "Playground", layer, appLabel, layerIx)) return;
    }

    int _AppKindFromLabel(const string &in labelRaw) {
        string l = labelRaw.Trim().ToLower();
        if (l == "playground") return 0;
        if (l == "menu") return 1;
        if (l == "current") return 2;
        return -1;
    }

    bool _ResolveLiveBoundsOverlayTarget(int &out appKind, int &out layerIx, string &out selectedPath, bool &out fromMlSelection) {
        selectedPath = "";
        fromMlSelection = false;

        if (UiNav::Debug::g_SelectedMlLayerIx >= 0) {
            appKind = UiNav::Debug::g_SelectedMlAppKind;
            layerIx = UiNav::Debug::g_SelectedMlLayerIx;
            selectedPath = UiNav::Debug::g_SelectedMlPath.Trim();
            fromMlSelection = true;
            return true;
        }

        int previewAppKind = _AppKindFromLabel(g_LastPreviewAppLabel);
        if (g_LastPreviewAtMs > 0 && previewAppKind >= 0 && g_LastPreviewLayerIx >= 0) {
            appKind = previewAppKind;
            layerIx = g_LastPreviewLayerIx;
            return true;
        }

        appKind = g_ImportAppKind;
        layerIx = g_ImportLayerIx;
        return layerIx >= 0;
    }

    string _FmtVec2(const vec2 &in v) {
        return "(" + v.x + ", " + v.y + ")";
    }

    void _BuildPreviewDiagText(const BuilderDocument@ doc, const string &in key, int xmlLen, CGameUILayer@ layer, const _PreviewBoundsState@ st, bool appliedForceFit, float forceFitScale, int sanitizedTags, int omittedGenericTyped, string &out text) {
        array<string> lines;
        if (doc is null) {
            lines.InsertLast("Preview: <no document>");
            text = lines[0];
            return;
        }

        string appLabel = "<unknown>";
        int layerIx = -1;
        _LocateOwnedPreviewLayer(layer, appLabel, layerIx);

        lines.InsertLast("Preview target: key=\"" + key + "\" app=" + appLabel + " layerIx=" + layerIx);
        lines.InsertLast("XML length: " + xmlLen + " chars");

        int roots = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) if (doc.nodes[i] !is null && doc.nodes[i].parentIx < 0) roots++;
        lines.InsertLast("Nodes: total=" + doc.nodes.Length + " roots=" + roots);

        if (st !is null && st.hasAll) {
            vec2 sz = st.maxAll - st.minAll;
            bool sane = Math::Abs(st.minAll.x) < 2000.0f && Math::Abs(st.maxAll.x) < 2000.0f
                && Math::Abs(st.minAll.y) < 2000.0f && Math::Abs(st.maxAll.y) < 2000.0f
                && sz.x < 4000.0f && sz.y < 4000.0f;
            lines.InsertLast("Bounds(all): min=" + _FmtVec2(st.minAll) + " max=" + _FmtVec2(st.maxAll) + " size=" + _FmtVec2(sz) + " sane=" + (sane ? "yes" : "NO"));
        } else {
            lines.InsertLast("Bounds(all): <none>");
        }

        if (st !is null && st.hasVisible) {
            vec2 sz = st.maxVisible - st.minVisible;
            lines.InsertLast("Bounds(visible): min=" + _FmtVec2(st.minVisible) + " max=" + _FmtVec2(st.maxVisible) + " size=" + _FmtVec2(sz));
        } else {
            lines.InsertLast("Bounds(visible): <none>");
        }

        if (st !is null) {
            lines.InsertLast("Hidden: self=" + st.nodesHiddenSelf + " byAncestor=" + st.nodesHiddenByAncestor);
            lines.InsertLast("Clipping: clipFrames=" + st.clipActiveFrames + " nodesUnderClipAncestor=" + st.nodesUnderClipAncestor);
        }

        if (appliedForceFit) {
            lines.InsertLast("Force-fit applied: scale=" + forceFitScale);
        }
        if (sanitizedTags > 0) lines.InsertLast("Preview sanitization: rewritten invalid tags=" + sanitizedTags);
        if (omittedGenericTyped > 0) lines.InsertLast("Preview sanitization: omitted typed props for generic nodes=" + omittedGenericTyped);

        int cFrame = 0, cQuad = 0, cLabel = 0, cEntry = 0, cTextEdit = 0, cGeneric = 0, cRaw = 0;
        int cTagControl = 0;
        dictionary tagCounts;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null) continue;
            string k = n.kind;
            if (k == "frame") cFrame++;
            else if (k == "quad") cQuad++;
            else if (k == "label") cLabel++;
            else if (k == "entry") cEntry++;
            else if (k == "textedit") cTextEdit++;
            else if (k == "raw_xml") cRaw++;
            else cGeneric++;

            string tag = n.tagName.Trim();
            if (tag.Length == 0) tag = n.kind;
            string tagLower = tag.ToLower();
            if (tagLower == "control") cTagControl++;
            int vv = 0;
            if (tagCounts.Get(tagLower, vv)) tagCounts.Set(tagLower, vv + 1);
            else tagCounts.Set(tagLower, 1);
        }
        lines.InsertLast("Kinds: frame=" + cFrame + " quad=" + cQuad + " label=" + cLabel + " entry=" + cEntry + " textedit=" + cTextEdit + " generic=" + cGeneric + " raw=" + cRaw);
        if (cTagControl > 0) lines.InsertLast("WARN: tag \"control\" count=" + cTagControl + " (likely invalid ML tag; can blank the whole page)");

        array<string> tags = tagCounts.GetKeys();
        array<int> counts;
        counts.Resize(tags.Length);
        for (uint i = 0; i < tags.Length; ++i) {
            int v = 0;
            tagCounts.Get(tags[i], v);
            counts[i] = v;
        }
        for (uint i = 0; i < tags.Length; ++i) {
            for (uint j = i + 1; j < tags.Length; ++j) {
                if (counts[j] > counts[i]) {
                    int tc = counts[i];
                    counts[i] = counts[j];
                    counts[j] = tc;
                    string ts = tags[i];
                    tags[i] = tags[j];
                    tags[j] = ts;
                }
            }
        }
        int topN = int(tags.Length);
        if (topN > 12) topN = 12;
        string top = "";
        for (int i = 0; i < topN; ++i) {
            if (i > 0) top += ", ";
            top += tags[uint(i)] + "=" + counts[uint(i)];
        }
        lines.InsertLast("Top tags: " + (top.Length > 0 ? top : "<none>") + " (unique=" + tags.Length + ")");

        lines.InsertLast("Root nodes:");
        int shown = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null || n.parentIx >= 0) continue;
            string idPart = n.controlId.Length > 0 ? n.controlId : n.uid;
            string tag = n.tagName.Trim();
            if (tag.Length == 0) tag = n.kind;
            string line = "  [" + i + "] <" + tag + "> kind=" + n.kind + " id=" + idPart;
            if (n.typed is null) {
                line += " <no typed props>";
                lines.InsertLast(line);
                shown++;
                continue;
            }
            line += " pos=" + _FmtVec2(n.typed.pos)
                + " size=" + _FmtVec2(n.typed.size)
                + " scale=" + n.typed.scale
                + " rot=" + n.typed.rot
                + " z=" + n.typed.z
                + " visible=" + (n.typed.visible ? "1" : "0");
            if (n.kind == "frame") {
                line += " clip=" + (n.typed.clipActive ? "1" : "0");
                if (n.typed.clipActive) {
                    line += " clipPos=" + _FmtVec2(n.typed.clipPos) + " clipSize=" + _FmtVec2(n.typed.clipSize);
                }
            } else if (n.kind == "quad" || n.kind == "label" || n.kind == "entry" || n.kind == "textedit") {
                line += " opacity=" + n.typed.opacity;
            }
            lines.InsertLast(line);
            shown++;
            if (shown >= 24) {
                lines.InsertLast("  ... (truncated)");
                break;
            }
        }

        text = "";
        for (uint i = 0; i < lines.Length; ++i) {
            if (i > 0) text += "\n";
            text += lines[i];
        }
    }

    class _LiveBoundsState {
        bool hasAll = false;
        vec2 minAll = vec2();
        vec2 maxAll = vec2();

        bool hasVisible = false;
        vec2 minVisible = vec2();
        vec2 maxVisible = vec2();

        int nodes = 0;
        int clipActiveFrames = 0;
        int hiddenSelf = 0;
        int hiddenByAncestor = 0;
        int underClipAncestor = 0;
    }

    float _AnchorXFromLiveAlign(CGameManialinkControl::EAlignHorizontal a) {
        int v = int(a);
        if (v == 0) return 0.0f;
        if (v == 2) return 1.0f;
        return 0.5f;
    }

    float _AnchorYFromLiveAlign(CGameManialinkControl::EAlignVertical a) {
        int v = int(a);
        if (v == 0) return 0.0f;
        if (v == 2) return 1.0f;
        return 0.5f;
    }

    void _LiveBoundsUpdateAll(_LiveBoundsState@ st, const vec2 &in bMin, const vec2 &in bMax) {
        if (st is null) return;
        if (!st.hasAll) {
            st.hasAll = true;
            st.minAll = bMin;
            st.maxAll = bMax;
            return;
        }
        if (bMin.x < st.minAll.x) st.minAll.x = bMin.x;
        if (bMin.y < st.minAll.y) st.minAll.y = bMin.y;
        if (bMax.x > st.maxAll.x) st.maxAll.x = bMax.x;
        if (bMax.y > st.maxAll.y) st.maxAll.y = bMax.y;
    }

    void _LiveBoundsUpdateVisible(_LiveBoundsState@ st, const vec2 &in bMin, const vec2 &in bMax) {
        if (st is null) return;
        if (!st.hasVisible) {
            st.hasVisible = true;
            st.minVisible = bMin;
            st.maxVisible = bMax;
            return;
        }
        if (bMin.x < st.minVisible.x) st.minVisible.x = bMin.x;
        if (bMin.y < st.minVisible.y) st.minVisible.y = bMin.y;
        if (bMax.x > st.maxVisible.x) st.maxVisible.x = bMax.x;
        if (bMax.y > st.maxVisible.y) st.maxVisible.y = bMax.y;
    }

    void _LiveBoundsVisit(CGameManialinkControl@ n, bool hiddenAncestor, int clipDepth, _LiveBoundsState@ st) {
        if (n is null || st is null) return;
        st.nodes++;

        bool selfVisible = true;
        try { selfVisible = n.Visible; } catch { selfVisible = true; }
        bool selfHidden = !selfVisible;
        bool nowHidden = hiddenAncestor || selfHidden;
        if (selfHidden) st.hiddenSelf++;
        if (hiddenAncestor && !selfHidden) st.hiddenByAncestor++;
        if (clipDepth > 0) st.underClipAncestor++;

        bool ok = true;
        vec2 absPos = vec2();
        vec2 size = vec2();
        float absScale = 1.0f;
        CGameManialinkControl::EAlignHorizontal ha = CGameManialinkControl::EAlignHorizontal(1);
        CGameManialinkControl::EAlignVertical va = CGameManialinkControl::EAlignVertical(1);
        try { absPos = n.AbsolutePosition_V3; } catch { ok = false; }
        try { size = n.Size; } catch { ok = false; }
        try { absScale = n.AbsoluteScale; } catch { absScale = 1.0f; }
        try { ha = n.HorizontalAlign; } catch { ha = CGameManialinkControl::EAlignHorizontal(1); }
        try { va = n.VerticalAlign; } catch { va = CGameManialinkControl::EAlignVertical(1); }

        if (ok) {
            float ax = _AnchorXFromLiveAlign(ha);
            float ay = _AnchorYFromLiveAlign(va);
            vec2 absSize = size * absScale;
            vec2 bMin = vec2(absPos.x - ax * absSize.x, absPos.y - (1.0f - ay) * absSize.y);
            vec2 bMax = vec2(absPos.x + (1.0f - ax) * absSize.x, absPos.y + ay * absSize.y);
            _LiveBoundsUpdateAll(st, bMin, bMax);
            if (!nowHidden) _LiveBoundsUpdateVisible(st, bMin, bMax);
        }

        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null) return;

        bool clipActive = false;
        try { clipActive = f.ClipWindowActive; } catch { clipActive = false; }
        int nextClipDepth = clipDepth + (clipActive ? 1 : 0);
        if (clipActive) st.clipActiveFrames++;

        try {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                _LiveBoundsVisit(ch, nowHidden, nextClipDepth, st);
            }
        } catch {
            return;
        }
    }

    string _SelectorAppKindLabel(int appKind) {
        if (appKind == 0) return "Playground";
        if (appKind == 1) return "Menu";
        if (appKind == 2) return "Current";
        return "<unknown>";
    }

    string SelectorSourceLabel(int appKind) {
        if (appKind < 0) return "All";
        return _SelectorAppKindLabel(appKind);
    }

    string _SelectorAppPrefixByKind(int appKind) {
        if (appKind == 0) return "P";
        if (appKind == 1) return "M";
        return "C";
    }

    string _SelectorMlPrefixByDebugKind(int debugAppKind) {
        if (debugAppKind == 1) return "M";
        if (debugAppKind == 2) return "E";
        return "P";
    }

    int _SelectorMapBuilderAppKindToDebugMlKind(int builderAppKind) {
        if (builderAppKind == 0 || builderAppKind == 1) return builderAppKind;
        if (builderAppKind != 2) return UiNav::Debug::g_MlActiveAppKind;

        auto cur = _GetAppByKind(2);
        auto menu = _GetAppByKind(1);
        auto pg = _GetAppByKind(0);
        if (cur !is null && menu !is null && cur is menu) return 1;
        if (cur !is null && pg !is null && cur is pg) return 0;
        return UiNav::Debug::g_MlActiveAppKind;
    }

    void SelectorArmPicker() {
        g_SelectorArmed = true;
        g_SelectorWaitMouseRelease = true;
        g_SelectorArmedAtMs = Time::Now;
        g_SelectorStatus = "Selector armed. Left-click a target UI element.";
    }

    void SelectorDisarmPicker(bool keepStatus = false) {
        g_SelectorArmed = false;
        g_SelectorWaitMouseRelease = false;
        if (!keepStatus) g_SelectorStatus = "Selector stopped.";
    }

    bool _SelectorPointInRect(const vec2 &in p, const vec2 &in minP, const vec2 &in maxP) {
        return p.x >= minP.x && p.x <= maxP.x && p.y >= minP.y && p.y <= maxP.y;
    }

    string _SelectorClasses(CGameManialinkControl@ n) {
        if (n is null) return "";
        string outS = "";
        try {
            auto classes = n.ControlClasses;
            for (uint i = 0; i < classes.Length; ++i) {
                string c = classes[i].Trim();
                if (c.Length == 0) continue;
                if (outS.Length > 0) outS += " ";
                outS += c;
            }
        } catch {
            outS = outS.Trim();
        }
        return outS;
    }

    string _SelectorTextPreview(CGameManialinkControl@ n, uint maxLen = 120) {
        if (n is null) return "";
        string t = "";
        try { t = UiNav::CleanUiFormatting(UiNav::ML::ReadText(n)); } catch { t = ""; }
        t = t.Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");
        int maxLenI = int(maxLen);
        if (maxLenI < 8) maxLenI = 8;
        if (int(t.Length) > maxLenI) t = t.SubStr(0, maxLenI - 3) + "...";
        return t;
    }

    void _SelectorVisit(CGameManialinkControl@ n, int appKind, int layerIx, bool layerVisible,
                        const string &in layerAttachId, const string &in manialinkName,
                        const string &in path, int depth, bool hiddenAncestor,
                        const vec2 &in clickPoint, bool includeHidden,
                        array<SelectorHitRow@> &inout hits) {
        if (n is null) return;

        bool selfVisible = true;
        try { selfVisible = n.Visible; } catch { selfVisible = true; }
        bool hiddenNow = hiddenAncestor || !selfVisible;

        bool ok = true;
        vec2 absPos = vec2();
        vec2 size = vec2();
        float absScale = 1.0f;
        float z = 0.0f;
        CGameManialinkControl::EAlignHorizontal ha = CGameManialinkControl::EAlignHorizontal(1);
        CGameManialinkControl::EAlignVertical va = CGameManialinkControl::EAlignVertical(1);

        try { absPos = n.AbsolutePosition_V3; } catch { ok = false; }
        try { size = n.Size; } catch { ok = false; }
        try { absScale = n.AbsoluteScale; } catch { absScale = 1.0f; }
        try { z = n.ZIndex; } catch { z = 0.0f; }
        try { ha = n.HorizontalAlign; } catch { ha = CGameManialinkControl::EAlignHorizontal(1); }
        try { va = n.VerticalAlign; } catch { va = CGameManialinkControl::EAlignVertical(1); }

        if (ok) {
            float ax = _AnchorXFromLiveAlign(ha);
            float ay = _AnchorYFromLiveAlign(va);
            vec2 absSize = size * absScale;
            vec2 bMin = vec2(absPos.x - ax * absSize.x, absPos.y - (1.0f - ay) * absSize.y);
            vec2 bMax = vec2(absPos.x + (1.0f - ax) * absSize.x, absPos.y + ay * absSize.y);

            bool isHit = _SelectorPointInRect(clickPoint, bMin, bMax);
            if (isHit && (includeHidden || !hiddenNow)) {
                auto row = SelectorHitRow();
                row.appKind = appKind;
                row.layerIx = layerIx;
                row.layerVisible = layerVisible;
                row.layerAttachId = layerAttachId;
                row.manialinkName = manialinkName;
                row.path = path;
                row.uiPath = _SelectorAppPrefixByKind(appKind) + "/L" + layerIx + (path.Length > 0 ? ("/" + path) : "");
                row.depth = depth;
                row.typeName = UiNav::ML::TypeName(n);
                try { row.controlId = n.ControlId; } catch { row.controlId = ""; }
                row.classList = _SelectorClasses(n);
                row.textPreview = _SelectorTextPreview(n);
                row.selfVisible = selfVisible;
                row.hiddenByAncestor = hiddenAncestor;
                row.visibleEffective = row.layerVisible && row.selfVisible && !row.hiddenByAncestor;
                row.zIndex = z;
                row.clickPoint = clickPoint;
                row.absPos = absPos;
                row.absSize = absSize;
                row.boundsMin = bMin;
                row.boundsMax = bMax;
                row.area = Math::Abs(absSize.x * absSize.y);
                hits.InsertLast(row);
            }
        }

        auto f = cast<CGameManialinkFrame@>(n);
        if (f is null) return;

        try {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                string childPath = path.Length > 0 ? (path + "/" + i) : tostring(i);
                _SelectorVisit(ch, appKind, layerIx, layerVisible, layerAttachId, manialinkName, childPath,
                    depth + 1, hiddenNow, clickPoint, includeHidden, hits);
            }
        } catch {
            return;
        }
    }

    void _SelectorPushUniqueApp(array<CGameManiaApp@> &inout apps, array<int> &inout kinds, int appKind) {
        auto app = _GetAppByKind(appKind);
        if (app is null) return;
        for (uint i = 0; i < apps.Length; ++i) {
            if (apps[i] is app) return;
        }
        apps.InsertLast(app);
        kinds.InsertLast(appKind);
    }

    int _SelectorAppRank(int appKind) {
        if (appKind == 2) return 3;
        if (appKind == 1) return 2;
        return 1;
    }

    bool _SelectorHitComesBefore(const SelectorHitRow@ a, const SelectorHitRow@ b) {
        if (a is null) return false;
        if (b is null) return true;

        bool aVisible = a.visibleEffective;
        bool bVisible = b.visibleEffective;
        if (aVisible != bVisible) return aVisible;

        int ar = _SelectorAppRank(a.appKind);
        int br = _SelectorAppRank(b.appKind);
        if (ar != br) return ar > br;

        if (a.layerIx != b.layerIx) return a.layerIx > b.layerIx;

        float zDelta = a.zIndex - b.zIndex;
        if (Math::Abs(zDelta) > 0.001f) return zDelta > 0.0f;

        if (a.depth != b.depth) return a.depth > b.depth;

        float areaDelta = a.area - b.area;
        if (Math::Abs(areaDelta) > 0.001f) return areaDelta < 0.0f;

        return a.path.Length > b.path.Length;
    }

    void _SelectorSortHits(array<SelectorHitRow@> &inout hits) {
        for (uint i = 0; i < hits.Length; ++i) {
            for (uint j = i + 1; j < hits.Length; ++j) {
                if (_SelectorHitComesBefore(hits[j], hits[i])) {
                    auto tmp = hits[i];
                    @hits[i] = hits[j];
                    @hits[j] = tmp;
                }
            }
        }
    }

    bool _SelectorBuildPathFromFocused(CGameManialinkFrame@ root, CGameManialinkControl@ focus, string &out path, int &out depth, bool &out hiddenByAncestor) {
        path = "";
        depth = 0;
        hiddenByAncestor = false;
        if (root is null || focus is null) return false;
        if (focus is root) return true;

        array<int> revPath;
        CGameManialinkControl@ cur = focus;
        int guard = 0;
        while (cur !is null && !(cur is root) && guard < 512) {
            guard++;
            auto parent = cur.Parent;
            if (parent is null) return false;

            bool parentVisible = true;
            try { parentVisible = parent.Visible; } catch { parentVisible = true; }
            if (!parentVisible) hiddenByAncestor = true;

            int found = -1;
            try {
                for (uint i = 0; i < parent.Controls.Length; ++i) {
                    if (parent.Controls[i] is cur) {
                        found = int(i);
                        break;
                    }
                }
            } catch {
                return false;
            }
            if (found < 0) return false;

            revPath.InsertLast(found);
            @cur = cast<CGameManialinkControl@>(parent);
            depth++;
        }
        if (!(cur is root)) return false;

        for (int i = int(revPath.Length) - 1; i >= 0; --i) {
            if (path.Length > 0) path += "/";
            path += tostring(revPath[uint(i)]);
        }
        return true;
    }

    bool SelectorSelectHit(int hitIx, bool syncMlSelection = false) {
        if (hitIx < 0 || hitIx >= int(g_SelectorHits.Length)) return false;
        g_SelectorSelectedHitIx = hitIx;
        if (syncMlSelection) return SelectorSyncHitToMlSelection(hitIx);
        return true;
    }

    bool SelectorPickNow() {
        g_SelectorHits.Resize(0);
        g_SelectorSelectedHitIx = -1;
        g_SelectorLastPickAtMs = Time::Now;

        array<CGameManiaApp@> apps;
        array<int> kinds;
        if (S_SelectorSourceAppKind >= 0 && S_SelectorSourceAppKind <= 2) {
            _SelectorPushUniqueApp(apps, kinds, S_SelectorSourceAppKind);
        } else {
            _SelectorPushUniqueApp(apps, kinds, 2);
            _SelectorPushUniqueApp(apps, kinds, 1);
            _SelectorPushUniqueApp(apps, kinds, 0);
        }

        if (apps.Length == 0) {
            g_SelectorStatus = "Selector pick failed: no UI app context available.";
            return false;
        }

        for (uint ai = 0; ai < apps.Length; ++ai) {
            auto app = apps[ai];
            int appKind = kinds[ai];
            if (app is null) continue;

            vec2 clickPoint = vec2();
            bool okMouse = true;
            try { clickPoint.x = app.MouseX; } catch { okMouse = false; }
            try { clickPoint.y = app.MouseY; } catch { okMouse = false; }
            if (!okMouse) continue;

            auto layers = app.UILayers;
            for (uint li = 0; li < layers.Length; ++li) {
                auto layer = layers[li];
                if (layer is null) continue;

                bool layerVisible = true;
                try { layerVisible = layer.IsVisible; } catch { layerVisible = true; }
                if (!S_SelectorIncludeHidden && !layerVisible) continue;

                auto page = layer.LocalPage;
                if (page is null || page.MainFrame is null) continue;

                CGameManialinkControl@ focused = null;
                try { @focused = page.FocusedControl; } catch { @focused = null; }
                if (focused is null) continue;

                bool selfVisible = true;
                try { selfVisible = focused.Visible; } catch { selfVisible = true; }
                if (!S_SelectorIncludeHidden && (!layerVisible || !selfVisible)) continue;

                string path = "";
                int depth = 0;
                bool hiddenByAncestor = false;
                if (!_SelectorBuildPathFromFocused(page.MainFrame, focused, path, depth, hiddenByAncestor)) continue;
                if (!S_SelectorIncludeHidden && hiddenByAncestor) continue;

                auto row = SelectorHitRow();
                row.appKind = appKind;
                row.layerIx = int(li);
                row.layerVisible = layerVisible;
                try { row.layerAttachId = layer.AttachId; } catch { row.layerAttachId = ""; }
                row.manialinkName = UiNav::Layers::_ExtractManialinkName(_GetLayerXml(layer));
                row.path = path;
                row.uiPath = _SelectorAppPrefixByKind(appKind) + "/L" + row.layerIx + (path.Length > 0 ? ("/" + path) : "");
                row.depth = depth;
                row.typeName = UiNav::ML::TypeName(focused);
                try { row.controlId = focused.ControlId; } catch { row.controlId = ""; }
                row.classList = _SelectorClasses(focused);
                row.textPreview = "";
                row.selfVisible = selfVisible;
                row.hiddenByAncestor = hiddenByAncestor;
                row.visibleEffective = row.layerVisible && row.selfVisible && !row.hiddenByAncestor;
                row.clickPoint = clickPoint;

                try { row.zIndex = focused.ZIndex; } catch { row.zIndex = 0.0f; }
                bool gotGeom = true;
                vec2 absPos = vec2();
                vec2 size = vec2();
                float absScale = 1.0f;
                CGameManialinkControl::EAlignHorizontal ha = CGameManialinkControl::EAlignHorizontal(1);
                CGameManialinkControl::EAlignVertical va = CGameManialinkControl::EAlignVertical(1);
                try { absPos = focused.AbsolutePosition_V3; } catch { gotGeom = false; }
                try { size = focused.Size; } catch { gotGeom = false; }
                try { absScale = focused.AbsoluteScale; } catch { absScale = 1.0f; }
                try { ha = focused.HorizontalAlign; } catch { ha = CGameManialinkControl::EAlignHorizontal(1); }
                try { va = focused.VerticalAlign; } catch { va = CGameManialinkControl::EAlignVertical(1); }
                if (gotGeom) {
                    row.absPos = absPos;
                    row.absSize = size * absScale;
                    float ax = _AnchorXFromLiveAlign(ha);
                    float ay = _AnchorYFromLiveAlign(va);
                    row.boundsMin = vec2(absPos.x - ax * row.absSize.x, absPos.y - (1.0f - ay) * row.absSize.y);
                    row.boundsMax = vec2(absPos.x + (1.0f - ax) * row.absSize.x, absPos.y + ay * row.absSize.y);
                    row.area = Math::Abs(row.absSize.x * row.absSize.y);
                }

                g_SelectorHits.InsertLast(row);
            }
        }

        _SelectorSortHits(g_SelectorHits);
        if (g_SelectorHits.Length == 0) {
            g_SelectorStatus = "No focused UI control found from this click.";
            return false;
        }

        g_SelectorSelectedHitIx = 0;
        auto top = g_SelectorHits[0];
        g_SelectorStatus = "Captured " + g_SelectorHits.Length + " focused element(s). Top: "
            + _SelectorAppKindLabel(top.appKind) + " L" + top.layerIx
            + (top.path.Length > 0 ? ("/" + top.path) : "/<root>");

        if (S_SelectorSyncMlSelection) {
            SelectorSyncHitToMlSelection(0);
        }
        return true;
    }

    bool SelectorSyncHitToMlSelection(int hitIx) {
        if (hitIx < 0 || hitIx >= int(g_SelectorHits.Length)) return false;
        auto row = g_SelectorHits[uint(hitIx)];
        if (row is null) return false;

        int mlAppKind = _SelectorMapBuilderAppKindToDebugMlKind(row.appKind);
        UiNav::Debug::g_MlActiveAppKind = mlAppKind;
        @UiNav::Debug::g_SelectedMlNode = null;
        UiNav::Debug::_ClearMlNodeFocus();
        UiNav::Debug::g_SelectedMlAppKind = mlAppKind;
        UiNav::Debug::g_SelectedMlLayerIx = row.layerIx;
        UiNav::Debug::g_SelectedMlPath = row.path;
        UiNav::Debug::g_SelectedMlUiPath = _SelectorMlPrefixByDebugKind(mlAppKind)
            + "/L" + row.layerIx + (row.path.Length > 0 ? ("/" + row.path) : "");
        string layerUiPath = _SelectorMlPrefixByDebugKind(mlAppKind) + "/L" + row.layerIx;
        UiNav::Debug::g_MlViewLayerIndex = row.layerIx;
        UiNav::Debug::g_MlFlatDirty = true;
        UiNav::Debug::g_MlNodeFocusActive = true;
        UiNav::Debug::g_MlNodeFocusAppKind = mlAppKind;
        UiNav::Debug::g_MlNodeFocusLayerIx = row.layerIx;
        UiNav::Debug::g_MlNodeFocusPath = row.path;
        UiNav::Debug::g_MlNodeFocusUiPath = UiNav::Debug::g_SelectedMlUiPath;
        UiNav::Debug::_SetMlTreeOpen(layerUiPath, false);
        UiNav::Debug::_SetMlTreeOpen(UiNav::Debug::g_SelectedMlUiPath, false);
        UiNav::Debug::g_MlNodeFocusStatus = "Selector synced selection and focused path.";

        if (S_LiveLayerBoundsOverlayEnabled) {
            RefreshLiveLayerBoundsOverlay(false, /*quiet=*/true);
        }
        return true;
    }

    string SelectorHitSummary(const SelectorHitRow@ row, int rank = -1) {
        if (row is null) return "<null>";
        string pfx = rank >= 0 ? ("#" + rank + " ") : "";
        string idPart = row.controlId.Length > 0 ? ("#" + row.controlId) : "<no-id>";
        string pathPart = row.path.Length > 0 ? row.path : "<root>";
        vec2 sz = row.boundsMax - row.boundsMin;
        return pfx + _SelectorAppKindLabel(row.appKind) + " L" + row.layerIx + " /" + pathPart
            + " " + row.typeName + " " + idPart
            + " bounds=" + _FmtVec2(row.boundsMin) + ".." + _FmtVec2(row.boundsMax)
            + " size=" + _FmtVec2(sz);
    }

    string SelectorHitsTableText() {
        string outS = "";
        outS += "=== UiNav Builder Selector Hits ===\n";
        outS += "t_ms=" + g_SelectorLastPickAtMs + " hits=" + g_SelectorHits.Length + "\n";
        for (uint i = 0; i < g_SelectorHits.Length; ++i) {
            auto row = g_SelectorHits[i];
            if (row is null) continue;
            outS += SelectorHitSummary(row, int(i + 1)) + "\n";
        }
        return outS;
    }

    bool _ResolveLiveNodeByPath(CGameManialinkFrame@ root, const string &in pathRaw, CGameManialinkControl@ &out node,
                                bool &out hiddenAncestor, int &out clipDepth) {
        @node = null;
        hiddenAncestor = false;
        clipDepth = 0;
        if (root is null) return false;

        CGameManialinkControl@ cur = cast<CGameManialinkControl@>(root);
        string path = pathRaw.Trim();
        if (path.Length == 0) {
            @node = cur;
            return true;
        }

        auto parts = path.Split("/");
        for (uint i = 0; i < parts.Length; ++i) {
            string part = parts[i].Trim();
            if (part.Length == 0) continue;

            int idx = Text::ParseInt(part);
            if (idx < 0) return false;

            bool vis = true;
            try { vis = cur.Visible; } catch { vis = true; }
            if (!vis) hiddenAncestor = true;

            auto f = cast<CGameManialinkFrame@>(cur);
            if (f is null) return false;

            bool clipActive = false;
            try { clipActive = f.ClipWindowActive; } catch { clipActive = false; }
            if (clipActive) clipDepth++;

            if (uint(idx) >= f.Controls.Length) return false;
            @cur = f.Controls[uint(idx)];
            if (cur is null) return false;
        }

        @node = cur;
        return true;
    }

    bool _ScanLiveLayerBoundsRow(CGameUILayer@ layer, int appKind, int layerIx, LiveLayerBoundsRow@ &out row) {
        @row = null;
        if (layer is null || layerIx < 0) return false;

        auto outRow = LiveLayerBoundsRow();
        outRow.appKind = appKind;
        outRow.layerIx = layerIx;
        try { outRow.visible = layer.IsVisible; } catch { outRow.visible = false; }
        try { outRow.attachId = layer.AttachId; } catch { outRow.attachId = ""; }

        string xml = _GetLayerXml(layer);
        outRow.manialinkName = UiNav::Layers::_ExtractManialinkName(xml);

        if (layer.LocalPage is null || layer.LocalPage.MainFrame is null) {
            outRow.note = "No LocalPage/MainFrame.";
            @row = outRow;
            return true;
        }

        auto st = _LiveBoundsState();
        _LiveBoundsVisit(layer.LocalPage.MainFrame, /*hiddenAncestor=*/false, /*clipDepth=*/0, st);

        outRow.nodes = st.nodes;
        outRow.clipActiveFrames = st.clipActiveFrames;
        outRow.hiddenSelf = st.hiddenSelf;
        outRow.hiddenByAncestor = st.hiddenByAncestor;
        outRow.underClipAncestor = st.underClipAncestor;

        outRow.hasAll = st.hasAll;
        if (st.hasAll) {
            outRow.minAll = st.minAll;
            outRow.maxAll = st.maxAll;
        }

        outRow.hasVisible = st.hasVisible;
        if (st.hasVisible) {
            outRow.minVisible = st.minVisible;
            outRow.maxVisible = st.maxVisible;
        }

        @row = outRow;
        return true;
    }

    bool _ScanLiveLayerBoundsPathRow(CGameUILayer@ layer, int appKind, int layerIx, const string &in path, LiveLayerBoundsRow@ &out row) {
        @row = null;
        if (layer is null || layerIx < 0) return false;

        auto outRow = LiveLayerBoundsRow();
        outRow.appKind = appKind;
        outRow.layerIx = layerIx;
        try { outRow.visible = layer.IsVisible; } catch { outRow.visible = false; }
        try { outRow.attachId = layer.AttachId; } catch { outRow.attachId = ""; }

        string xml = _GetLayerXml(layer);
        outRow.manialinkName = UiNav::Layers::_ExtractManialinkName(xml);

        if (layer.LocalPage is null || layer.LocalPage.MainFrame is null) {
            outRow.note = "No LocalPage/MainFrame.";
            @row = outRow;
            return true;
        }

        CGameManialinkControl@ start = null;
        bool hiddenAncestor = false;
        int clipDepth = 0;
        if (!_ResolveLiveNodeByPath(layer.LocalPage.MainFrame, path, start, hiddenAncestor, clipDepth) || start is null) {
            outRow.note = "Selection path unavailable: " + path;
            @row = outRow;
            return true;
        }

        auto st = _LiveBoundsState();
        _LiveBoundsVisit(start, hiddenAncestor, clipDepth, st);

        outRow.nodes = st.nodes;
        outRow.clipActiveFrames = st.clipActiveFrames;
        outRow.hiddenSelf = st.hiddenSelf;
        outRow.hiddenByAncestor = st.hiddenByAncestor;
        outRow.underClipAncestor = st.underClipAncestor;

        outRow.hasAll = st.hasAll;
        if (st.hasAll) {
            outRow.minAll = st.minAll;
            outRow.maxAll = st.maxAll;
        }

        outRow.hasVisible = st.hasVisible;
        if (st.hasVisible) {
            outRow.minVisible = st.minVisible;
            outRow.maxVisible = st.maxVisible;
        }

        outRow.visible = outRow.visible && st.hasVisible;
        outRow.note = "path=" + (path.Length > 0 ? path : "<root>");

        @row = outRow;
        return true;
    }

    bool ScanLiveLayerBounds(int appKind) {
        g_LiveLayerBoundsRows.Resize(0);
        g_LiveLayerBoundsStatus = "";
        g_LiveLayerBoundsAtMs = Time::Now;
        g_LiveLayerBoundsAppKind = appKind;

        auto app = _GetAppByKind(appKind);
        if (app is null) {
            g_LiveLayerBoundsStatus = "Scan failed: app is null for appKind=" + appKind + ".";
            return false;
        }

        auto layers = app.UILayers;
        for (uint i = 0; i < layers.Length; ++i) {
            auto layer = layers[i];
            if (layer is null) continue;
            LiveLayerBoundsRow@ row = null;
            if (!_ScanLiveLayerBoundsRow(layer, appKind, int(i), row) || row is null) continue;
            g_LiveLayerBoundsRows.InsertLast(row);
        }

        g_LiveLayerBoundsStatus = "Scanned " + g_LiveLayerBoundsRows.Length + " layer(s) for appKind=" + appKind + ".";
        return true;
    }

    string LiveLayerBoundsTableText() {
        string outS = "";
        outS += "=== UiNav Live Layer Bounds ===\n";
        outS += "t_ms=" + Time::Now + "\n";
        outS += "appKind=" + g_LiveLayerBoundsAppKind + " layers=" + g_LiveLayerBoundsRows.Length + "\n";
        for (uint i = 0; i < g_LiveLayerBoundsRows.Length; ++i) {
            auto r = g_LiveLayerBoundsRows[i];
            if (r is null) continue;
            string name = r.manialinkName.Length > 0 ? r.manialinkName : "<no manialink name>";
            vec2 sz = r.hasAll ? (r.maxAll - r.minAll) : vec2();
            outS += "L[" + r.layerIx + "] vis=" + (r.visible ? "1" : "0")
                + " attachId=\"" + r.attachId + "\""
                + " name=\"" + name + "\""
                + " nodes=" + r.nodes
                + " boundsHas=" + (r.hasAll ? "1" : "0");
            if (r.hasAll) outS += " min=" + _FmtVec2(r.minAll) + " max=" + _FmtVec2(r.maxAll) + " size=" + _FmtVec2(sz);
            if (r.note.Length > 0) outS += " note=\"" + r.note + "\"";
            outS += "\n";
        }
        return outS;
    }

    string _LiveBoundsOverlayKey() {
        return "UiNav_BuilderLiveBoundsOverlay";
    }

    void _AppendLiveLayerBoundsOverlayNodes(BuilderDocument@ doc, const LiveLayerBoundsRow@ selectedRow, int selectedLayerIx, const string &in selectedPath = "") {
        if (doc is null) return;

        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_live_bounds_origin_h", vec2(0, 0), vec2(20, 0.5f), "fff", 0.65f, 12000.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_live_bounds_origin_v", vec2(0, 0), vec2(0.5f, 20), "fff", 0.65f, 12000.0f));
        doc.nodes.InsertLast(_MakeOverlayLabel("__uinav_live_bounds_origin_lbl", vec2(0, -10), vec2(70, 6), "LIVE BOUNDS", "fff", 1.5f, 12001.0f));

        if (selectedLayerIx < 0) {
            _RebuildNodeIndex(doc);
            return;
        }

        if (selectedRow !is null && selectedRow.hasAll) {
            vec2 minP = selectedRow.minAll;
            vec2 maxP = selectedRow.maxAll;
            vec2 center = (minP + maxP) * 0.5f;
            vec2 size = maxP - minP;
            if (size.x >= 0.001f && size.y >= 0.001f) {
                string color = selectedRow.visible ? "ff0" : "f6a";
                float fillOpacity = 0.09f;
                float lineOpacity = 0.88f;
                float t = 0.95f;
                float zBase = 11900.0f;

                string uidPrefix = "__uinav_live_bounds_l" + selectedLayerIx + "_";
                doc.nodes.InsertLast(_MakeOverlayQuad(uidPrefix + "fill", center, size, color, fillOpacity, zBase));
                doc.nodes.InsertLast(_MakeOverlayQuad(uidPrefix + "top", vec2(center.x, maxP.y), vec2(size.x, t), color, lineOpacity, zBase + 0.1f));
                doc.nodes.InsertLast(_MakeOverlayQuad(uidPrefix + "bot", vec2(center.x, minP.y), vec2(size.x, t), color, lineOpacity, zBase + 0.1f));
                doc.nodes.InsertLast(_MakeOverlayQuad(uidPrefix + "l", vec2(minP.x, center.y), vec2(t, size.y), color, lineOpacity, zBase + 0.1f));
                doc.nodes.InsertLast(_MakeOverlayQuad(uidPrefix + "r", vec2(maxP.x, center.y), vec2(t, size.y), color, lineOpacity, zBase + 0.1f));

                string visMark = selectedRow.visible ? "V" : "H";
                string pathSuffix = selectedPath.Length > 0 ? (" /" + selectedPath) : "";
                string lbl = "L[" + selectedLayerIx + "]" + pathSuffix + " " + visMark + " n=" + selectedRow.nodes;
                doc.nodes.InsertLast(_MakeOverlayLabel(uidPrefix + "lbl", vec2(center.x, maxP.y + 6.0f), vec2(260, 6), lbl, color, 1.6f, zBase + 0.2f));
            }
        }

        _RebuildNodeIndex(doc);
    }

    bool RefreshLiveLayerBoundsOverlay(bool rescan = false, bool quiet = false) {
        if (!S_LiveLayerBoundsOverlayEnabled) return false;

        int targetAppKind = g_ImportAppKind;
        int targetLayerIx = g_ImportLayerIx;
        string targetPath = "";
        bool targetFromMlSelection = false;
        bool hasTarget = _ResolveLiveBoundsOverlayTarget(targetAppKind, targetLayerIx, targetPath, targetFromMlSelection);
        CGameManiaApp@ overlayApp = null;
        if (hasTarget) @overlayApp = _GetAppByKind(targetAppKind);
        else @overlayApp = UiNav::Layers::GetManiaApp();
        if (overlayApp is null) @overlayApp = UiNav::Layers::GetManiaAppMenu();
        if (overlayApp is null) @overlayApp = UiNav::Layers::GetManiaAppPlayground();
        if (overlayApp is null) {
            if (!quiet) g_Status = "Live bounds overlay failed: no target app context.";
            return false;
        }

        LiveLayerBoundsRow@ targetRow = null;
        if (hasTarget) {
            auto layer = _GetLayerByKindIx(targetAppKind, targetLayerIx);
            bool okScan = false;
            if (layer !is null) {
                if (targetFromMlSelection && targetPath.Length > 0)
                    okScan = _ScanLiveLayerBoundsPathRow(layer, targetAppKind, targetLayerIx, targetPath, targetRow);
                else
                    okScan = _ScanLiveLayerBoundsRow(layer, targetAppKind, targetLayerIx, targetRow);
            }
            if (!okScan || targetRow is null) {
                if (!quiet) g_Status = "Live bounds overlay failed: target layer unavailable.";
                return false;
            }
        }

        auto doc = _NewDocument();
        doc.name = "UiNav_BuilderLiveBoundsOverlay";
        _AppendLiveLayerBoundsOverlayNodes(doc, targetRow, hasTarget ? targetLayerIx : -1, targetFromMlSelection ? targetPath : "");

        string xml = ExportToXml(doc);
        if (xml.Length == 0) {
            g_Status = "Live bounds overlay failed: generated XML is empty.";
            return false;
        }

        string key = _LiveBoundsOverlayKey();
        auto layer = UiNav::Layers::EnsureAtApp(key, xml, overlayApp, true);
        if (layer is null) {
            g_Status = "Live bounds overlay failed: could not create/update overlay layer.";
            return false;
        }

        if (!quiet) {
            string targetText = "no target";
            if (hasTarget) {
                targetText = "target L[" + targetLayerIx + "] app=" + targetAppKind;
                if (targetFromMlSelection && targetPath.Length > 0) targetText += " path=" + targetPath;
            }
            g_Status = "Live bounds overlay updated (" + targetText + ").";
        }
        return true;
    }

    bool DestroyLiveLayerBoundsOverlay() {
        string key = _LiveBoundsOverlayKey();
        bool ok = UiNav::Layers::Destroy(key);
        g_Status = ok
            ? "Destroyed live bounds overlay."
            : "Live bounds overlay not found.";
        return ok;
    }

    string _DbgIndent(int depth) {
        if (depth <= 0) return "";
        string outS = "";
        for (int i = 0; i < depth; ++i) outS += "  ";
        return outS;
    }

    string _DbgTrunc(const string &in s, int maxLen = 240) {
        if (maxLen < 8) maxLen = 8;
        if (s.Length <= maxLen) return s;
        return s.SubStr(0, maxLen - 3) + "...";
    }

    void _DbgAppend(array<string> &inout lines, const string &in s) {
        lines.InsertLast(s);
    }

    string DumpBuilderDocumentToText(const BuilderDocument@ doc, bool includeExportXml = true) {
        array<string> lines;
        _DbgAppend(lines, "=== UiNav Builder Debug Dump ===");
        _DbgAppend(lines, "t_ms=" + Time::Now);

        if (doc is null) {
            _DbgAppend(lines, "<null doc>");
            string outS = "";
            for (uint i = 0; i < lines.Length; ++i) outS += (i == 0 ? "" : "\n") + lines[i];
            return outS;
        }

        int roots = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) if (doc.nodes[i] !is null && doc.nodes[i].parentIx < 0) roots++;

        _DbgAppend(lines, "doc.format=" + doc.format);
        _DbgAppend(lines, "doc.version=" + doc.version);
        _DbgAppend(lines, "doc.name=" + doc.name);
        _DbgAppend(lines, "doc.sourceKind=" + doc.sourceKind);
        _DbgAppend(lines, "doc.sourceLabel=" + doc.sourceLabel);
        _DbgAppend(lines, "doc.nodes=" + doc.nodes.Length + " roots=" + roots);
        _DbgAppend(lines, "doc.diagnostics=" + doc.diagnostics.Length);
        _DbgAppend(lines, "selectedNodeIx=" + g_SelectedNodeIx);
        _DbgAppend(lines, "baselineXmlLen=" + g_BaselineXml.Length);

        _DbgAppend(lines, "");
        _DbgAppend(lines, "Last preview:");
        _DbgAppend(lines, "  atMs=" + g_LastPreviewAtMs);
        _DbgAppend(lines, "  key=" + g_LastPreviewLayerKey);
        _DbgAppend(lines, "  app=" + g_LastPreviewAppLabel + " layerIx=" + g_LastPreviewLayerIx);
        _DbgAppend(lines, "  xmlLen=" + g_LastPreviewXmlLen);
        _DbgAppend(lines, "  boundsHas=" + (g_LastPreviewBoundsHas ? "1" : "0"));
        if (g_LastPreviewBoundsHas) {
            _DbgAppend(lines, "  boundsMin=" + _FmtVec2(g_LastPreviewBoundsMin));
            _DbgAppend(lines, "  boundsMax=" + _FmtVec2(g_LastPreviewBoundsMax));
        }

        if (g_LastPreviewDiagText.Length > 0) {
            _DbgAppend(lines, "");
            _DbgAppend(lines, "Last preview diag text:");
            auto diagLines = g_LastPreviewDiagText.Split("\n");
            for (uint i = 0; i < diagLines.Length; ++i) {
                _DbgAppend(lines, "  " + diagLines[i]);
            }
        }

        if (doc.diagnostics.Length > 0) {
            _DbgAppend(lines, "");
            _DbgAppend(lines, "Document diagnostics:");
            for (uint i = 0; i < doc.diagnostics.Length; ++i) {
                auto d = doc.diagnostics[i];
                if (d is null) continue;
                _DbgAppend(lines, "  [" + d.severity + "] " + d.code + (d.nodeUid.Length > 0 ? (" node=" + d.nodeUid) : ""));
                _DbgAppend(lines, "    " + d.message);
            }
        }

        _DbgAppend(lines, "");
        _DbgAppend(lines, "Nodes:");
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null) continue;
            string hdr = "[" + i + "] uid=" + n.uid
                + " kind=" + n.kind
                + " tag=" + n.tagName
                + " id=" + (n.controlId.Length > 0 ? n.controlId : "<none>")
                + " parent=" + n.parentIx
                + " children=" + n.childIx.Length
                + " fidelity=" + n.fidelity.level;
            _DbgAppend(lines, hdr);

            if (n.classes.Length > 0) {
                string cls = "";
                for (uint c = 0; c < n.classes.Length; ++c) cls += (c == 0 ? "" : " ") + n.classes[c];
                _DbgAppend(lines, "  classes=" + cls);
            }
            if (n.scriptEvents) _DbgAppend(lines, "  scriptevents=1");

            if (n.typed is null) {
                _DbgAppend(lines, "  typed=<null>");
            } else {
                _DbgAppend(lines, "  typed.pos=" + _FmtVec2(n.typed.pos) + " size=" + _FmtVec2(n.typed.size)
                    + " z=" + n.typed.z + " scale=" + n.typed.scale + " rot=" + n.typed.rot
                    + " visible=" + (n.typed.visible ? "1" : "0")
                    + " halign=" + n.typed.hAlign + " valign=" + n.typed.vAlign);

                if (n.kind == "frame") {
                    _DbgAppend(lines, "  frame.clipActive=" + (n.typed.clipActive ? "1" : "0")
                        + " clipPos=" + _FmtVec2(n.typed.clipPos) + " clipSize=" + _FmtVec2(n.typed.clipSize));
                } else if (n.kind == "quad") {
                    _DbgAppend(lines, "  quad.opacity=" + n.typed.opacity
                        + " bgcolor=" + n.typed.bgColor
                        + " style=" + n.typed.style
                        + " substyle=" + n.typed.subStyle);
                    if (n.typed.image.Length > 0) _DbgAppend(lines, "  quad.image=" + _DbgTrunc(n.typed.image));
                    if (n.typed.imageFocus.Length > 0) _DbgAppend(lines, "  quad.imageFocus=" + _DbgTrunc(n.typed.imageFocus));
                } else if (n.kind == "label") {
                    _DbgAppend(lines, "  label.opacity=" + n.typed.opacity
                        + " textSize=" + n.typed.textSize
                        + " textColor=" + n.typed.textColor
                        + " style=" + n.typed.style
                        + " substyle=" + n.typed.subStyle);
                    if (n.typed.text.Length > 0) _DbgAppend(lines, "  label.text=" + n.typed.text);
                    if (n.typed.textPrefix.Length > 0) _DbgAppend(lines, "  label.textPrefix=" + n.typed.textPrefix);
                } else if (n.kind == "entry" || n.kind == "textedit") {
                    _DbgAppend(lines, "  input.opacity=" + n.typed.opacity
                        + " textSize=" + n.typed.textSize
                        + " textColor=" + n.typed.textColor
                        + " maxLen=" + n.typed.maxLength
                        + " maxLine=" + n.typed.maxLine);
                    if (n.typed.value.Length > 0) _DbgAppend(lines, "  input.value=" + n.typed.value);
                }
            }

            array<string> rawKeys = n.rawAttrs.GetKeys();
            if (rawKeys.Length > 0) {
                rawKeys.SortAsc();
                _DbgAppend(lines, "  rawAttrs=" + rawKeys.Length);
                for (uint r = 0; r < rawKeys.Length; ++r) {
                    string v = "";
                    n.rawAttrs.Get(rawKeys[r], v);
                    _DbgAppend(lines, "    " + rawKeys[r] + "=\"" + v + "\"");
                }
            }

            if (n.fidelity.reasons.Length > 0) {
                string rs = "";
                for (uint r = 0; r < n.fidelity.reasons.Length; ++r) rs += (r == 0 ? "" : ", ") + n.fidelity.reasons[r];
                _DbgAppend(lines, "  fidelity.reasons=" + rs);
            }
        }

        if (doc.stylesheetBlock !is null && doc.stylesheetBlock.raw.Length > 0) {
            _DbgAppend(lines, "");
            _DbgAppend(lines, "Stylesheet block (" + doc.stylesheetBlock.raw.Length + " chars):");
            auto sheetLines = doc.stylesheetBlock.raw.Split("\n");
            for (uint i = 0; i < sheetLines.Length; ++i) _DbgAppend(lines, "  " + sheetLines[i]);
        }

        if (doc.scriptBlock !is null && doc.scriptBlock.raw.Length > 0) {
            _DbgAppend(lines, "");
            _DbgAppend(lines, "Script block (" + doc.scriptBlock.raw.Length + " chars):");
            auto scriptLines = doc.scriptBlock.raw.Split("\n");
            for (uint i = 0; i < scriptLines.Length; ++i) _DbgAppend(lines, "  " + scriptLines[i]);
        }

        if (includeExportXml) {
            string xml = ExportToXml(doc);
            _DbgAppend(lines, "");
            _DbgAppend(lines, "Export XML (" + xml.Length + " chars):");
            _DbgAppend(lines, xml);
        }

        string outS = "";
        for (uint i = 0; i < lines.Length; ++i) outS += (i == 0 ? "" : "\n") + lines[i];
        return outS;
    }

    bool CopyBuilderDumpToClipboard(bool includeExportXml = true) {
        _EnsureDoc();
        string dump = DumpBuilderDocumentToText(g_Doc, includeExportXml);
        IO::SetClipboard(dump);
        g_Status = "Copied Builder dump to clipboard (" + dump.Length + " chars).";
        return true;
    }

    BuilderNode@ _MakeOverlayQuad(const string &in uid, const vec2 &in pos, const vec2 &in size, const string &in color, float opacity, float z) {
        auto n = BuilderNode();
        n.uid = uid;
        n.kind = "quad";
        n.tagName = "quad";
        n.parentIx = -1;
        @n.typed = BuilderTypedProps();
        n.typed.pos = pos;
        n.typed.size = size;
        n.typed.z = z;
        n.typed.opacity = opacity;
        n.typed.bgColor = color;
        n.typed.hAlign = "center";
        n.typed.vAlign = "center";
        return n;
    }

    BuilderNode@ _MakeOverlayLabel(const string &in uid, const vec2 &in pos, const vec2 &in size, const string &in textV, const string &in color, float textSize, float z) {
        auto n = BuilderNode();
        n.uid = uid;
        n.kind = "label";
        n.tagName = "label";
        n.parentIx = -1;
        @n.typed = BuilderTypedProps();
        n.typed.pos = pos;
        n.typed.size = size;
        n.typed.z = z;
        n.typed.text = textV;
        n.typed.textColor = color;
        n.typed.textSize = textSize;
        n.typed.hAlign = "center";
        n.typed.vAlign = "center";
        n.typed.opacity = 1.0f;
        return n;
    }

    void _AppendPreviewOverlayNodes(BuilderDocument@ doc, const _PreviewBoundsState@ st) {
        if (doc is null) return;

        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_origin_h", vec2(0, 0), vec2(24, 0.7f), "f00", 0.85f, 10000.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_origin_v", vec2(0, 0), vec2(0.7f, 24), "f00", 0.85f, 10000.0f));
        doc.nodes.InsertLast(_MakeOverlayLabel("__uinav_dbg_origin_lbl", vec2(0, -12), vec2(60, 6), "ORIGIN (0,0)", "f44", 2.0f, 10001.0f));

        if (st is null || !st.hasAll) return;
        vec2 minP = st.minAll;
        vec2 maxP = st.maxAll;
        vec2 center = (minP + maxP) * 0.5f;
        vec2 size = maxP - minP;
        if (size.x < 0.001f || size.y < 0.001f) return;

        float t = 0.6f;
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_bounds_fill", center, size, "0f0", 0.08f, 9990.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_bounds_top", vec2(center.x, maxP.y), vec2(size.x, t), "0f0", 0.70f, 9991.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_bounds_bot", vec2(center.x, minP.y), vec2(size.x, t), "0f0", 0.70f, 9991.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_bounds_l", vec2(minP.x, center.y), vec2(t, size.y), "0f0", 0.70f, 9991.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_bounds_r", vec2(maxP.x, center.y), vec2(t, size.y), "0f0", 0.70f, 9991.0f));
        doc.nodes.InsertLast(_MakeOverlayLabel("__uinav_dbg_bounds_lbl", vec2(center.x, center.y + 6.0f), vec2(180, 6),
            "BOUNDS " + _FmtVec2(minP) + " .. " + _FmtVec2(maxP), "0f0", 1.6f, 9992.0f));
    }

    void _AppendPreviewSelectedOverlayNodes(BuilderDocument@ doc, const BuilderAbsMetrics@ sel) {
        if (doc is null || sel is null || !sel.ok) return;

        vec2 minP = sel.boundsMin;
        vec2 maxP = sel.boundsMax;
        vec2 center = (minP + maxP) * 0.5f;
        vec2 size = maxP - minP;
        if (size.x < 0.001f || size.y < 0.001f) return;

        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_anchor_h", sel.absPos, vec2(18, 0.6f), "ff0", 0.92f, 10002.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_anchor_v", sel.absPos, vec2(0.6f, 18), "ff0", 0.92f, 10002.0f));

        float t = 0.6f;
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_fill", center, size, "ff0", 0.06f, 9993.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_top", vec2(center.x, maxP.y), vec2(size.x, t), "ff0", 0.80f, 9994.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_bot", vec2(center.x, minP.y), vec2(size.x, t), "ff0", 0.80f, 9994.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_l", vec2(minP.x, center.y), vec2(t, size.y), "ff0", 0.80f, 9994.0f));
        doc.nodes.InsertLast(_MakeOverlayQuad("__uinav_dbg_sel_r", vec2(maxP.x, center.y), vec2(t, size.y), "ff0", 0.80f, 9994.0f));

        vec2 sz = maxP - minP;
        string lbl = "SELECTED bounds " + _FmtVec2(minP) + " .. " + _FmtVec2(maxP)
            + " size=" + _FmtVec2(sz)
            + " absPos=" + _FmtVec2(sel.absPos)
            + " absScale=" + sel.absScale;
        doc.nodes.InsertLast(_MakeOverlayLabel("__uinav_dbg_sel_lbl", vec2(center.x, maxP.y + 6.0f), vec2(260, 6), lbl, "ff0", 1.5f, 10003.0f));
    }

    void _ClearRedo() {
        g_RedoSnapshots.Resize(0);
    }

    void _PushUndoSnapshot() {
        _EnsureDoc();
        g_UndoSnapshots.InsertLast(_CloneDocument(g_Doc));
        int maxKeep = S_UndoMax;
        if (maxKeep < 10) maxKeep = 10;
        while (int(g_UndoSnapshots.Length) > maxKeep) {
            g_UndoSnapshots.RemoveAt(0);
        }
        _ClearRedo();
    }

    bool Undo() {
        _EnsureDoc();
        if (g_UndoSnapshots.Length == 0) return false;
        g_RedoSnapshots.InsertLast(_CloneDocument(g_Doc));
        @g_Doc = g_UndoSnapshots[g_UndoSnapshots.Length - 1];
        g_UndoSnapshots.RemoveAt(g_UndoSnapshots.Length - 1);
        _RebuildNodeIndex(g_Doc);
        if (g_SelectedNodeIx >= int(g_Doc.nodes.Length)) g_SelectedNodeIx = -1;
        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = "Undo applied.";
        return true;
    }

    bool Redo() {
        _EnsureDoc();
        if (g_RedoSnapshots.Length == 0) return false;
        g_UndoSnapshots.InsertLast(_CloneDocument(g_Doc));
        @g_Doc = g_RedoSnapshots[g_RedoSnapshots.Length - 1];
        g_RedoSnapshots.RemoveAt(g_RedoSnapshots.Length - 1);
        _RebuildNodeIndex(g_Doc);
        if (g_SelectedNodeIx >= int(g_Doc.nodes.Length)) g_SelectedNodeIx = -1;
        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = "Redo applied.";
        return true;
    }

    bool _NodeCanContainChildren(const BuilderNode@ n) {
        if (n is null) return false;
        return n.kind == "frame"
            || n.kind == "generic"
            || n.kind == "raw_xml";
    }

    int _CountRootNodes(const BuilderDocument@ doc) {
        if (doc is null) return 0;
        int c = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n !is null && n.parentIx < 0) c++;
        }
        return c;
    }

    void _InitAuthoringDefaults(BuilderNode@ n, int siblingCount = 0) {
        if (n is null || n.typed is null) return;

        float dx = float(siblingCount % 8) * 6.0f;
        float dy = float(siblingCount % 8) * -4.0f;
        n.typed.pos = vec2(dx, dy);

        if (n.kind == "frame") {
            n.typed.size = vec2(160.0f, 90.0f);
            n.typed.z = 0.0f;
            return;
        }
        if (n.kind == "quad") {
            n.typed.size = vec2(36.0f, 20.0f);
            n.typed.bgColor = "09f";
            n.typed.opacity = 1.0f;
            n.typed.z = 4.0f;
            return;
        }
        if (n.kind == "label") {
            n.typed.size = vec2(40.0f, 8.0f);
            n.typed.text = "New Label";
            n.typed.textColor = "fff";
            n.typed.textSize = 2.0f;
            n.typed.z = 6.0f;
            return;
        }
        if (n.kind == "entry" || n.kind == "textedit") {
            n.typed.size = vec2(50.0f, 8.0f);
            n.typed.value = "Type here";
            n.typed.textColor = "fff";
            n.typed.textSize = 1.5f;
            n.typed.z = 6.0f;
            return;
        }
    }

    float _ComputeAbsScaleAtIx(int nodeIx) {
        if (g_Doc is null) return 1.0f;
        float s = 1.0f;
        int cur = nodeIx;
        int guard = 0;
        while (cur >= 0 && cur < int(g_Doc.nodes.Length) && guard < 512) {
            guard++;
            auto n = g_Doc.nodes[uint(cur)];
            if (n is null || n.typed is null) break;
            s *= n.typed.scale;
            cur = n.parentIx;
        }
        return s;
    }

    int AddNode(const string &in kindRaw, int parentIx = -1) {
        _EnsureDoc();
        string kind = kindRaw.Trim().ToLower();
        if (kind.Length == 0) kind = "frame";
        if (!_IsKnownKind(kind)) kind = "generic";

        if (parentIx < -1 || parentIx >= int(g_Doc.nodes.Length)) parentIx = -1;
        if (parentIx >= 0) {
            auto maybeParent = g_Doc.nodes[uint(parentIx)];
            if (!_NodeCanContainChildren(maybeParent)) {
                parentIx = maybeParent is null ? -1 : maybeParent.parentIx;
            }
        }

        _PushUndoSnapshot();

        if (parentIx < 0 && g_Doc.nodes.Length == 0 && kind != "frame") {
            auto root = _NewNode("frame", -1);
            root.tagName = "frame";
            _InitAuthoringDefaults(root, 0);
            g_Doc.nodes.InsertLast(root);
            parentIx = int(g_Doc.nodes.Length) - 1;
        }

        int siblingCount = 0;
        if (parentIx >= 0 && parentIx < int(g_Doc.nodes.Length)) {
            auto p = g_Doc.nodes[uint(parentIx)];
            if (p !is null) siblingCount = int(p.childIx.Length);
        } else {
            siblingCount = _CountRootNodes(g_Doc);
        }

        auto n = _NewNode(kind, parentIx);
        n.tagName = kind;
        _InitAuthoringDefaults(n, siblingCount);

        if (parentIx >= 0 && n.typed !is null) {
            float parentAbsScale = _ComputeAbsScaleAtIx(parentIx);
            if (Math::Abs(parentAbsScale) > 0.0001f && Math::Abs(parentAbsScale - 1.0f) > 0.0001f) {
                n.typed.pos /= parentAbsScale;
                n.typed.size /= parentAbsScale;
                if (n.kind == "label" || n.kind == "entry" || n.kind == "textedit") {
                    n.typed.textSize /= parentAbsScale;
                }
            }
        }

        int ix = int(g_Doc.nodes.Length);
        g_Doc.nodes.InsertLast(n);
        if (parentIx >= 0) {
            auto p = g_Doc.nodes[uint(parentIx)];
            if (p !is null) p.childIx.InsertLast(ix);
        }

        _RebuildNodeIndex(g_Doc);
        g_SelectedNodeIx = ix;
        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = "Added node: " + kind + ".";
        return ix;
    }

    void _MarkDeleteRecursive(int nodeIx, array<bool> &inout marks) {
        if (nodeIx < 0 || nodeIx >= int(marks.Length)) return;
        if (marks[uint(nodeIx)]) return;
        marks[uint(nodeIx)] = true;

        if (g_Doc is null) return;
        if (nodeIx >= int(g_Doc.nodes.Length)) return;
        auto n = g_Doc.nodes[uint(nodeIx)];
        if (n is null) return;
        for (uint i = 0; i < n.childIx.Length; ++i) {
            _MarkDeleteRecursive(n.childIx[i], marks);
        }
    }

    bool DeleteNode(int nodeIx) {
        _EnsureDoc();
        if (nodeIx < 0 || nodeIx >= int(g_Doc.nodes.Length)) return false;

        _PushUndoSnapshot();

        array<bool> marks;
        marks.Resize(g_Doc.nodes.Length);
        for (uint i = 0; i < marks.Length; ++i) marks[i] = false;
        _MarkDeleteRecursive(nodeIx, marks);

        array<int> remap;
        remap.Resize(g_Doc.nodes.Length);
        for (uint i = 0; i < remap.Length; ++i) remap[i] = -1;

        array<BuilderNode@> newNodes;
        for (uint i = 0; i < g_Doc.nodes.Length; ++i) {
            if (marks[i]) continue;
            remap[i] = int(newNodes.Length);
            newNodes.InsertLast(_CloneNode(g_Doc.nodes[i]));
        }

        for (uint i = 0; i < newNodes.Length; ++i) {
            auto n = newNodes[i];
            if (n is null) continue;
            if (n.parentIx >= 0) n.parentIx = remap[uint(n.parentIx)];

            array<int> children;
            for (uint c = 0; c < n.childIx.Length; ++c) {
                int oldIx = n.childIx[c];
                if (oldIx < 0 || oldIx >= int(remap.Length)) continue;
                int mapped = remap[uint(oldIx)];
                if (mapped >= 0) children.InsertLast(mapped);
            }
            n.childIx = children;
        }

        g_Doc.nodes = newNodes;
        _RebuildNodeIndex(g_Doc);

        if (nodeIx >= 0 && nodeIx < int(remap.Length)) {
            int mappedSel = remap[uint(nodeIx)];
            g_SelectedNodeIx = mappedSel >= 0 ? mappedSel : -1;
        } else {
            g_SelectedNodeIx = -1;
        }

        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = "Deleted node/subtree.";
        return true;
    }

    bool _IsAncestor(int nodeIx, int maybeAncestor) {
        if (nodeIx < 0 || maybeAncestor < 0) return false;
        if (nodeIx >= int(g_Doc.nodes.Length) || maybeAncestor >= int(g_Doc.nodes.Length)) return false;
        int cur = nodeIx;
        while (cur >= 0 && cur < int(g_Doc.nodes.Length)) {
            if (cur == maybeAncestor) return true;
            auto n = g_Doc.nodes[uint(cur)];
            if (n is null) break;
            cur = n.parentIx;
        }
        return false;
    }

    bool MoveNode(int nodeIx, int newParentIx) {
        _EnsureDoc();
        if (nodeIx < 0 || nodeIx >= int(g_Doc.nodes.Length)) return false;
        if (newParentIx >= int(g_Doc.nodes.Length)) return false;
        if (newParentIx == nodeIx) return false;
        if (newParentIx >= 0 && _IsAncestor(newParentIx, nodeIx)) return false;

        auto node = g_Doc.nodes[uint(nodeIx)];
        if (node is null) return false;
        int oldParent = node.parentIx;
        if (oldParent == newParentIx) return true;

        _PushUndoSnapshot();

        if (oldParent >= 0 && oldParent < int(g_Doc.nodes.Length)) {
            auto p = g_Doc.nodes[uint(oldParent)];
            if (p !is null) {
                for (uint i = 0; i < p.childIx.Length; ++i) {
                    if (p.childIx[i] == nodeIx) {
                        p.childIx.RemoveAt(i);
                        break;
                    }
                }
            }
        }

        node.parentIx = newParentIx;
        if (newParentIx >= 0) {
            auto p2 = g_Doc.nodes[uint(newParentIx)];
            if (p2 !is null) p2.childIx.InsertLast(nodeIx);
        }

        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = "Moved node.";
        return true;
    }

    int _SetFrameClipActiveInDoc(BuilderDocument@ doc, bool active) {
        if (doc is null) return 0;
        int changed = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null || n.typed is null) continue;
            if (n.kind != "frame") continue;
            if (n.typed.clipActive == active) continue;
            n.typed.clipActive = active;
            changed++;
        }
        return changed;
    }

    int DisableAllFrameClipping(bool pushUndo = true, bool applyPreviewNow = true) {
        _EnsureDoc();

        int activeCount = 0;
        for (uint i = 0; i < g_Doc.nodes.Length; ++i) {
            auto n = g_Doc.nodes[i];
            if (n is null || n.typed is null) continue;
            if (n.kind != "frame") continue;
            if (n.typed.clipActive) activeCount++;
        }
        if (activeCount <= 0) {
            g_Status = "No active frame clipping found.";
            return 0;
        }

        if (pushUndo) _PushUndoSnapshot();
        int changed = _SetFrameClipActiveInDoc(g_Doc, false);

        _UpdateDirtyState();
        _QueueAutoPreview();
        if (applyPreviewNow && !S_AutoLivePreview) _ApplyPreviewLayerInternal(false);

        g_Status = "Disabled frame clipping on " + changed + " frame(s).";
        return changed;
    }

    bool ImportFromXmlText(const string &in xmlText, const string &in sourceKind = "import_xml", const string &in sourceLabel = "", bool centerAfterImport = false) {
        string txt = xmlText.Trim();
        if (txt.Length == 0) {
            g_Status = "Import failed: XML is empty.";
            return false;
        }

        auto doc = ImportFromXml(xmlText, sourceKind, sourceLabel);
        if (doc is null) {
            g_Status = "Import failed: parser returned null document.";
            return false;
        }

        _ResetDocument(doc);
        int strippedClip = 0;
        if (S_StripFrameClippingOnImport) strippedClip = _SetFrameClipActiveInDoc(g_Doc, false);
        bool centered = false;
        if (centerAfterImport) centered = _CenterDocumentRoots(g_Doc);
        g_BaselineXml = ExportToXml(g_Doc);
        g_Doc.dirty = false;
        g_LastExportXml = g_BaselineXml;
        _QueueAutoPreview();
        g_Status = "Imported XML: " + g_Doc.nodes.Length + " nodes.";
        if (strippedClip > 0) g_Status += " Stripped clipping on " + strippedClip + " frame(s).";
        if (centerAfterImport) {
            g_Status += centered
                ? " Centered copy at screen center."
                : " Centering skipped.";
        }
        return true;
    }

    bool ImportFromLiveLayer(int appKind, int layerIx) {
        auto layer = _GetLayerByKindIx(appKind, layerIx);
        if (layer is null) {
            g_Status = "Import failed: layer not found (app_kind=" + appKind + ", layer_ix=" + layerIx + ").";
            return false;
        }

        string xml = _GetLayerXml(layer);
        if (xml.Length == 0) {
            g_Status = "Import failed: layer XML is empty.";
            return false;
        }

        string label = "app=" + appKind + " layer=" + layerIx;
        return ImportFromXmlText(xml, "import_live_layer", label, S_CenterImportedLiveCopy);
    }

    string _AlignHToXml(CGameManialinkControl::EAlignHorizontal a) {
        int v = int(a);
        if (v == 0) return "left";
        if (v == 1) return "center";
        if (v == 2) return "right";
        return "";
    }

    string _AlignVToXml(CGameManialinkControl::EAlignVertical a) {
        int v = int(a);
        if (v == 0) return "top";
        if (v == 1) return "center";
        if (v == 2) return "bottom";
        if (v == 4) return "center2";
        return "";
    }

    int _ClampByte(float v) {
        if (v < 0.0f) v = 0.0f;
        if (v > 1.0f) v = 1.0f;
        return int(v * 255.0f + 0.5f);
    }

    string _Vec3ToHexRgb(const vec3 &in v) {
        int r = _ClampByte(v.x);
        int g = _ClampByte(v.y);
        int b = _ClampByte(v.z);
        return Text::Format("%02x", r) + Text::Format("%02x", g) + Text::Format("%02x", b);
    }

    string _WStr(const wstring &in v) {
        return string(v);
    }

    class _LiveTreeCloneState {
        int maxNodes = 6000;
        int maxDepth = 256;
        int nodes = 0;
        bool truncated = false;
    }

    void _CloneLiveCommonProps(BuilderNode@ outNode, CGameManialinkControl@ inNode) {
        if (outNode is null || inNode is null || outNode.typed is null) return;

        outNode.controlId = inNode.ControlId;
        outNode.typed.pos = inNode.RelativePosition_V3;
        outNode.typed.size = inNode.Size;
        outNode.typed.z = inNode.ZIndex;
        outNode.typed.scale = inNode.RelativeScale;
        outNode.typed.rot = inNode.RelativeRotation;
        outNode.typed.visible = inNode.Visible;
        outNode.typed.hAlign = _AlignHToXml(inNode.HorizontalAlign);
        outNode.typed.vAlign = _AlignVToXml(inNode.VerticalAlign);

        auto classes = inNode.ControlClasses;
        for (uint i = 0; i < classes.Length; ++i) {
            outNode.classes.InsertLast(classes[i]);
        }
    }

    string _TagFromLiveControl(CGameManialinkControl@ n, string &out kind) {
        kind = "generic";
        if (n is null) return "control";

        if (cast<CGameManialinkFrame@>(n) !is null) { kind = "frame"; return "frame"; }
        if (cast<CGameManialinkQuad@>(n) !is null) { kind = "quad"; return "quad"; }
        if (cast<CGameManialinkLabel@>(n) !is null) { kind = "label"; return "label"; }
        if (cast<CGameManialinkTextEdit@>(n) !is null) { kind = "textedit"; return "textedit"; }
        if (cast<CGameManialinkEntry@>(n) !is null) { kind = "entry"; return "entry"; }

        if (cast<CGameManialinkGauge@>(n) !is null) return "gauge";
        if (cast<CGameManialinkGraph@>(n) !is null) return "graph";
        if (cast<CGameManialinkMiniMap@>(n) !is null) return "minimap";
        if (cast<CGameManialinkPlayerList@>(n) !is null) return "playerlist";
        if (cast<CGameManialinkMediaPlayer@>(n) !is null) return "mediaplayer";
        if (cast<CGameManialinkArrow@>(n) !is null) return "arrow";
        if (cast<CGameManialinkSlider@>(n) !is null) return "slider";
        if (cast<CGameManialinkTimeLine@>(n) !is null) return "timeline";
        if (cast<CGameManialinkCamera@>(n) !is null) return "camera";
        if (cast<CGameManialinkColorChooser@>(n) !is null) return "colorchooser";

        return "control";
    }

    int _AppendLiveTreeNode(BuilderDocument@ doc, CGameManialinkControl@ live, int parentIx, int depth, _LiveTreeCloneState@ st) {
        if (doc is null || st is null) return -1;
        if (live is null) return -1;
        if (st.nodes >= st.maxNodes || depth > st.maxDepth) {
            st.truncated = true;
            return -1;
        }
        st.nodes++;

        string kind;
        string tag = _TagFromLiveControl(live, kind);
        auto node = _NewNode(kind, parentIx);
        node.tagName = tag;

        _CloneLiveCommonProps(node, live);
        node.fidelity.level = 1;
        node.fidelity.reasons.InsertLast("live_tree_clone");

        if (kind == "frame") {
            auto f = cast<CGameManialinkFrame@>(live);
            if (f !is null) {
                node.typed.clipActive = f.ClipWindowActive;
                node.typed.clipPos = f.ClipWindowRelativePosition;
                node.typed.clipSize = f.ClipWindowSize;
            }
        } else if (kind == "quad") {
            auto q = cast<CGameManialinkQuad@>(live);
            if (q !is null) {
                node.typed.image = q.ImageUrl;
                node.typed.imageFocus = q.ImageUrlFocus;
                node.typed.alphaMask = q.AlphaMaskUrl;
                node.typed.style = q.Style;
                node.typed.subStyle = q.Substyle;
                node.typed.bgColor = _Vec3ToHexRgb(q.BgColor);
                node.typed.bgColorFocus = _Vec3ToHexRgb(q.BgColorFocus);
                node.typed.modulateColor = _Vec3ToHexRgb(q.ModulateColor);
                node.typed.colorize = _Vec3ToHexRgb(q.Colorize);
                node.typed.opacity = q.Opacity;
                node.typed.keepRatioMode = int(q.KeepRatio);
                node.typed.blendMode = int(q.Blend);
            }
        } else if (kind == "label") {
            auto l = cast<CGameManialinkLabel@>(live);
            if (l !is null) {
                node.typed.text = _WStr(l.Value);
                node.typed.textSize = l.TextSizeReal;
                node.typed.textFont = _WStr(l.TextFont);
                node.typed.textPrefix = _WStr(l.TextPrefix);
                node.typed.textColor = _Vec3ToHexRgb(l.TextColor);
                node.typed.opacity = l.Opacity;
                node.typed.maxLine = l.MaxLine;
                node.typed.autoNewLine = l.AutoNewLine;
                node.typed.lineSpacing = l.LineSpacing;
                node.typed.italicSlope = l.ItalicSlope;
                node.typed.appendEllipsis = l.AppendEllipsis;
                node.typed.style = l.Style;
                node.typed.subStyle = l.Substyle;
            }
        } else if (kind == "entry") {
            auto e = cast<CGameManialinkEntry@>(live);
            if (e !is null) {
                node.typed.value = _WStr(e.Value);
                node.typed.textFormat = int(e.TextFormat);
                node.typed.textSize = e.TextSizeReal;
                node.typed.textColor = _Vec3ToHexRgb(e.TextColor);
                node.typed.opacity = e.Opacity;
                node.typed.maxLength = e.MaxLength;
                node.typed.maxLine = e.MaxLine;
                node.typed.autoNewLine = e.AutoNewLine;
            }
        } else if (kind == "textedit") {
            auto t = cast<CGameManialinkTextEdit@>(live);
            if (t !is null) {
                node.typed.value = _WStr(t.Value);
                node.typed.textFormat = int(t.TextFormat);
                node.typed.textSize = t.TextSizeReal;
                node.typed.textColor = _Vec3ToHexRgb(t.TextColor);
                node.typed.opacity = t.Opacity;
                node.typed.maxLine = t.MaxLine;
                node.typed.autoNewLine = t.AutoNewLine;
                node.typed.lineSpacing = t.LineSpacing;
            }
        } else {
            node.fidelity.level = 2;
            node.fidelity.reasons.InsertLast("unsupported_kind_live_tree");
        }

        int ix = int(doc.nodes.Length);
        doc.nodes.InsertLast(node);
        if (parentIx >= 0 && parentIx < int(doc.nodes.Length)) {
            auto parent = doc.nodes[uint(parentIx)];
            if (parent !is null) parent.childIx.InsertLast(ix);
        }
        doc.nodeByUid.Set(node.uid, ix);

        auto f = cast<CGameManialinkFrame@>(live);
        if (f !is null) {
            for (uint i = 0; i < f.Controls.Length; ++i) {
                auto ch = f.Controls[i];
                if (ch is null) continue;
                _AppendLiveTreeNode(doc, ch, ix, depth + 1, st);
            }
        }

        return ix;
    }

    bool ImportFromLiveLayerTree(int appKind, int layerIx) {
        auto layer = _GetLayerByKindIx(appKind, layerIx);
        if (layer is null) {
            g_Status = "Clone failed: layer not found (app_kind=" + appKind + ", layer_ix=" + layerIx + ").";
            return false;
        }
        if (layer.LocalPage is null || layer.LocalPage.MainFrame is null) {
            g_Status = "Clone failed: layer has no LocalPage/MainFrame.";
            return false;
        }

        auto doc = _NewDocument();
        doc.sourceKind = "import_live_tree";
        doc.sourceLabel = "app=" + appKind + " layer=" + layerIx;

        auto st = _LiveTreeCloneState();
        _AppendLiveTreeNode(doc, layer.LocalPage.MainFrame, -1, 0, st);
        if (st.truncated) {
            _AddDiag(doc, "clone.truncated", "warn", "Live tree clone truncated at node/depth budget.");
        }

        _ResetDocument(doc);
        int strippedClip = 0;
        if (S_StripFrameClippingOnImport) strippedClip = _SetFrameClipActiveInDoc(g_Doc, false);
        bool centered = false;
        if (S_CenterImportedLiveCopy) centered = _CenterDocumentRoots(g_Doc);
        g_BaselineXml = ExportToXml(g_Doc);
        g_Doc.dirty = false;
        g_LastExportXml = g_BaselineXml;
        _QueueAutoPreview();
        g_Status = "Cloned live tree: " + g_Doc.nodes.Length + " nodes."
            + (strippedClip > 0 ? (" Stripped clipping on " + strippedClip + " frame(s).") : "")
            + (S_CenterImportedLiveCopy ? (centered ? " Centered." : " Centering skipped.") : "");
        return true;
    }

    bool AddDebugOriginMarker(bool applyPreviewNow = true) {
        _EnsureDoc();
        _PushUndoSnapshot();

        auto q = _NewNode("quad", -1);
        q.tagName = "quad";
        q.controlId = "UiNav_DbgOriginQuad";
        q.typed.pos = vec2(0, 0);
        q.typed.size = vec2(6.0f, 6.0f);
        q.typed.hAlign = "center";
        q.typed.vAlign = "center";
        q.typed.bgColor = "f00";
        q.typed.opacity = 1.0f;
        q.typed.z = 10000.0f;
        g_Doc.nodes.InsertLast(q);

        auto l = _NewNode("label", -1);
        l.tagName = "label";
        l.controlId = "UiNav_DbgOriginLabel";
        l.typed.pos = vec2(0, -10.0f);
        l.typed.size = vec2(80.0f, 6.0f);
        l.typed.hAlign = "center";
        l.typed.vAlign = "center";
        l.typed.text = "ORIGIN";
        l.typed.textColor = "f66";
        l.typed.textSize = 2.2f;
        l.typed.opacity = 1.0f;
        l.typed.z = 10001.0f;
        g_Doc.nodes.InsertLast(l);

        _RebuildNodeIndex(g_Doc);
        _UpdateDirtyState();
        _QueueAutoPreview();
        if (applyPreviewNow) _ApplyPreviewLayerInternal(false);
        g_Status = "Added origin marker.";
        return true;
    }

    bool ExportToClipboard() {
        _EnsureDoc();
        string xml = ExportToXml(g_Doc);
        if (xml.Length == 0) {
            g_Status = "Export failed: generated XML is empty.";
            return false;
        }
        g_LastExportXml = xml;
        IO::SetClipboard(xml);
        g_Status = "Exported XML to clipboard (" + xml.Length + " chars).";
        return true;
    }

    bool ExportToFilePath(const string &in pathRaw) {
        _EnsureDoc();
        string path = pathRaw.Trim();
        if (path.Length == 0) {
            g_Status = "Export failed: file path is empty.";
            return false;
        }

        string xml = ExportToXml(g_Doc);
        if (xml.Length == 0) {
            g_Status = "Export failed: generated XML is empty.";
            return false;
        }

        string folder = Path::GetDirectoryName(path);
        if (folder.Length > 0 && !IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        _IO::File::WriteFile(path, xml, false);
        g_LastExportXml = xml;
        g_Status = "Exported XML to: " + path;
        return true;
    }

    bool _ApplyPreviewLayerInternal(bool writeSuccessStatus = true) {
        _EnsureDoc();
        string key = S_PreviewLayerKey.Trim();
        if (key.Length == 0) key = "UiNav_BuilderPreview";

        bool wantClone = S_PreviewDebugOverlayEnabled
            || S_PreviewSelectedBoundsOverlayEnabled
            || S_PreviewSanitizeInvalidTags
            || S_PreviewOmitGenericCommonAttrs
            || g_PreviewForceFitOnce;

        BuilderDocument@ previewDoc = g_Doc;
        BuilderDocument@ tmp = null;
        if (wantClone) {
            @tmp = _CloneDocument(g_Doc);
            @previewDoc = tmp;
        }

        int sanitizedTags = 0;
        if (tmp !is null && S_PreviewSanitizeInvalidTags) {
            for (uint i = 0; i < tmp.nodes.Length; ++i) {
                auto n = tmp.nodes[i];
                if (n is null) continue;
                string tagLower = n.tagName.Trim().ToLower();
                if (tagLower.Length == 0 || tagLower == "control") {
                    n.tagName = "frame";
                    sanitizedTags++;
                }
            }
        }

        bool appliedForceFit = false;
        float forceFitScale = 1.0f;
        if (tmp !is null && g_PreviewForceFitOnce) {
            g_PreviewForceFitOnce = false;

            auto stPre = _PreviewBoundsState();
            _ComputePreviewBounds(tmp, stPre);
            if (stPre.hasAll) {
                vec2 sz = stPre.maxAll - stPre.minAll;
                float targetW = Math::Max(1.0f, S_PreviewForceFitHalfW * 2.0f);
                float targetH = Math::Max(1.0f, S_PreviewForceFitHalfH * 2.0f);

                float s = 1.0f;
                if (sz.x > 0.001f) s = Math::Min(s, targetW / sz.x);
                if (sz.y > 0.001f) s = Math::Min(s, targetH / sz.y);
                s *= S_PreviewForceFitMargin;
                if (s < 0.001f) s = 0.001f;
                if (s > 50.0f) s = 50.0f;

                vec2 center = (stPre.minAll + stPre.maxAll) * 0.5f;
                for (uint i = 0; i < tmp.nodes.Length; ++i) {
                    auto n = tmp.nodes[i];
                    if (n is null || n.parentIx >= 0 || n.typed is null) continue;
                    n.typed.pos = (n.typed.pos - center) * s;
                    n.typed.scale *= s;
                }
                appliedForceFit = true;
                forceFitScale = s;
            }
        }

        int omittedGenericTyped = 0;
        if (tmp !is null && S_PreviewOmitGenericCommonAttrs) {
            for (uint i = 0; i < tmp.nodes.Length; ++i) {
                auto n = tmp.nodes[i];
                if (n is null) continue;
                if (n.kind == "generic" && n.typed !is null) {
                    @n.typed = null;
                    omittedGenericTyped++;
                }
            }
        }

        auto boundsSt = _PreviewBoundsState();
        bool wantDiag = S_PreviewDiagnosticsEnabled || S_PreviewDebugOverlayEnabled || appliedForceFit || sanitizedTags > 0 || omittedGenericTyped > 0;
        if (wantDiag) {
            _ComputePreviewBounds(previewDoc, boundsSt);
        }

        BuilderAbsMetrics@ selAbs = null;
        if (tmp !is null && S_PreviewSelectedBoundsOverlayEnabled && g_SelectedNodeIx >= 0) {
            @selAbs = ComputeAbsMetrics(previewDoc, g_SelectedNodeIx);
        }

        if (tmp !is null && S_PreviewDebugOverlayEnabled) _AppendPreviewOverlayNodes(tmp, boundsSt);
        if (tmp !is null && S_PreviewSelectedBoundsOverlayEnabled && selAbs !is null && selAbs.ok) _AppendPreviewSelectedOverlayNodes(tmp, selAbs);

        string xml = ExportToXml(previewDoc);
        if (xml.Length == 0) {
            g_Status = "Preview failed: generated XML is empty.";
            return false;
        }

        auto layer = UiNav::Layers::Ensure(key, xml, true);
        if (layer is null) {
            g_Status = "Preview failed: UiNav::Layers::Ensure returned null.";
            return false;
        }

        uint nowMs = Time::Now;
        g_LastPreviewAtMs = nowMs;
        g_LastPreviewLayerKey = key;
        g_LastPreviewXmlLen = xml.Length;
        _LocateOwnedPreviewLayer(layer, g_LastPreviewAppLabel, g_LastPreviewLayerIx);

        if (wantDiag) {
            string diagText = "";
            _BuildPreviewDiagText(previewDoc, key, xml.Length, layer, boundsSt, appliedForceFit, forceFitScale, sanitizedTags, omittedGenericTyped, diagText);
            g_LastPreviewDiagText = diagText;
            g_LastPreviewBoundsHas = boundsSt.hasAll;
            if (boundsSt.hasAll) {
                g_LastPreviewBoundsMin = boundsSt.minAll;
                g_LastPreviewBoundsMax = boundsSt.maxAll;
            }
            if (S_PreviewDiagnosticsPrintToLog && diagText.Length > 0) {
                print("[UiNav.Builder] Preview diagnostics:\n" + diagText);
            }
        } else {
            g_LastPreviewDiagText = "";
            g_LastPreviewBoundsHas = false;
        }

        g_LastExportXml = xml;
        if (writeSuccessStatus) g_Status = "Preview applied to layer key: " + key;
        g_AutoPreviewPending = false;

        if (S_LiveLayerBoundsOverlayEnabled) {
            RefreshLiveLayerBoundsOverlay(true, /*quiet=*/true);
        }
        return true;
    }

    bool ApplyPreviewLayer() {
        return _ApplyPreviewLayerInternal(true);
    }

    bool DestroyPreviewLayer() {
        string key = S_PreviewLayerKey.Trim();
        if (key.Length == 0) key = "UiNav_BuilderPreview";
        bool ok = UiNav::Layers::Destroy(key);
        g_Status = ok
            ? ("Destroyed preview layer: " + key)
            : ("Preview layer not found or could not be destroyed: " + key);
        return ok;
    }

    void DiffAgainstOriginal() {
        _EnsureDoc();
        string current = ExportToXml(g_Doc);
        g_LastExportXml = current;
        _ComputeDiffSummary(g_Doc.originalXml, current, g_LastDiff);
        g_Status = "Diff generated.";
    }

}
}
