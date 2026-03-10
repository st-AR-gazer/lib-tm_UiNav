namespace UiNav {
namespace Debug {

    void _RenderTreeRowBudgetOverride(const string &in idSuffix) {
        int budget = S_DebugTreeRowBudget;
        UI::SetNextItemWidth(120.0f);
        budget = UI::InputInt("Max rows##tree-row-budget-" + idSuffix, budget);
        if (budget < 0) budget = 0;
        if (budget != S_DebugTreeRowBudget) S_DebugTreeRowBudget = budget;
        UI::SameLine();
        UI::TextDisabled("0 = unlimited");
    }

    void _SelectControlTreeLayerRoot(uint overlay, int rootIx) {
        if (rootIx < 0) return;
        CControlBase@ root = null;
        if (!_ResolveControlTreeNodeByPath(overlay, rootIx, "", root) || root is null) return;
        string rootUi = "O" + overlay + "/root[" + rootIx + "]";
        string rootDisplay = "overlay[" + overlay + "]/root[" + rootIx + "]";
        _SelectControlTree(root, "", rootDisplay, rootUi, rootIx, overlay);
    }

    void _RenderControlTreeInspectorPane() {
        float paneHeight = UI::GetContentRegionAvail().y - UI::GetFrameHeightWithSpacing() - 6.0f;
        paneHeight = Math::Floor(paneHeight);
        if (paneHeight < 1.0f) paneHeight = 1.0f;

        UI::BeginGroup();
        UI::Text("Tree");
        UI::SameLine();
        if (UI::Button("Collapse all##controlTree")) g_ControlTreeCollapseAll = true;
        bool controlTreeTreeOpen = UI::BeginChild("##controlTree-tree", vec2(float(g_ControlTreeTreeWidth), paneHeight), true);
        if (controlTreeTreeOpen) {
            _RenderControlTreeTree();
        }
        UI::EndChild();
        UI::EndGroup();
        if (g_ControlTreeCollapseAll) g_ControlTreeCollapseAll = false;

        UI::SameLine();
        g_ControlTreeTreeWidth = _DrawControlTreeSplitter("##controlTree-splitter", g_ControlTreeTreeWidth, paneHeight);
        S_ControlTreeTreeWidth = g_ControlTreeTreeWidth;
        UI::SameLine();

        UI::BeginGroup();
        UI::Text("Selection");
        bool controlTreeDetailsOpen = UI::BeginChild("##controlTree-details", vec2(0, paneHeight), true);
        if (controlTreeDetailsOpen) {
            _RenderControlTreeSelection();
        }
        UI::EndChild();
        UI::EndGroup();
    }

    void _RenderControlTreeTab() {
        UI::SetNextItemWidth(440.0f);
        g_ControlTreeSearch = UI::InputText("Search", g_ControlTreeSearch);
        UI::SameLine();
        if (UI::Button("Clear##controlTree-search")) g_ControlTreeSearch = "";
        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        UI::Text("Overlay");
        if (UI::IsItemHovered()) UI::SetTooltip("Overlay index (-1 = all overlays)");
        UI::SameLine();
        UI::SetNextItemWidth(110.0f);
        g_ControlTreeOverlay = UI::InputInt("##controlTree-overlay-index", g_ControlTreeOverlay);
        if (UI::IsItemHovered()) UI::SetTooltip("Overlay index (-1 = all overlays)");
        UI::SameLine();
        S_ControlTreeHideEmptyRoots = UI::Checkbox("Hide empty roots##controlTree-hide-empty", S_ControlTreeHideEmptyRoots);
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Hide plain top-level Frame roots that have no children and no identifying text.");
        }
        UI::SameLine();
        S_ControlTreeHideDuplicateAnonymousRoots = UI::Checkbox("Hide duplicate roots##controlTree-hide-dup", S_ControlTreeHideDuplicateAnonymousRoots);
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Hide duplicate anonymous top-level Frame roots and keep only the first matching subtree.");
        }
        if (g_ControlTreeOverlay < -1) g_ControlTreeOverlay = -1;
        uint overlayCount = 0;
        if (_TryGetControlTreeOverlayCount(overlayCount) && overlayCount > 0
            && g_ControlTreeOverlay >= int(overlayCount)) {
            g_ControlTreeOverlay = int(overlayCount - 1);
        }
        UI::Text("\\$888Search: words (AND), \"quoted text\", -exclude, id: (IdName), text:, type:, path:, vis:true/false\\$z");

        if (g_ControlTreeNodeFocusActive) {
            string parentPath = _ControlTreeNodeFocusParentPathDisplay();
            UI::TextDisabled("Focused parent path:");
            UI::SameLine();
            UI::Text(parentPath.Length > 0 ? parentPath : "<none>");
            UI::SameLine();
            if (UI::Button("Clear node focus##controlTree-pane")) {
                _ClearControlTreeNodeFocus();
                g_ControlTreeSelectionStatus = "Cleared node focus.";
            }
        }

        UI::Separator();

        _RenderControlTreeInspectorPane();
    }

    bool _TryGetControlTreeOverlayCount(uint &out count) {
        count = 0;
        CGameCtnApp@ app = GetApp();
        if (app is null || app.Viewport is null) return false;
        auto vp = cast<CDx11Viewport>(app.Viewport);
        if (vp is null) return false;
        count = vp.Overlays.Length;
        return true;
    }

    string _ControlTreeOverlayRootsCacheKey(uint overlay) {
        return "ov=" + overlay
            + "|hide=" + (S_ControlTreeHideEmptyRoots ? "1" : "0")
            + "|dup=" + (S_ControlTreeHideDuplicateAnonymousRoots ? "1" : "0");
    }

    ControlTreeOverlayRootsCacheEntry@ _GetControlTreeOverlayRootsCache(uint overlay, uint mobilsLen) {
        string key = _ControlTreeOverlayRootsCacheKey(overlay);
        uint epoch = UiNav::ContextEpoch();

        ControlTreeOverlayRootsCacheEntry@ e;
        bool ok = g_ControlTreeOverlayRootsCache.Get(key, @e) && e !is null;
        if (ok && e.epoch == epoch && e.mobilsLen == mobilsLen) return e;

        @e = ControlTreeOverlayRootsCacheEntry();
        e.epoch = epoch;
        e.mobilsLen = mobilsLen;
        g_ControlTreeOverlayRootsCache.Set(key, @e);
        return e;
    }

    bool _ShouldDisplayControlTreeOverlayRoot(CControlBase@ root) {
        if (root is null) return false;
        if (!S_ControlTreeHideEmptyRoots) return true;
        if (_ChildrenLen(root) > 0) return true;
        if (root.IdName.Trim().Length > 0) return true;
        if (root.StackText.Trim().Length > 0) return true;
        if (cast<CControlLabel>(root) !is null) return true;
        if (cast<CControlEntry>(root) !is null) return true;
        if (cast<CControlButton>(root) !is null) return true;
        if (cast<CControlQuad>(root) !is null) return true;
        if (cast<CControlGrid>(root) !is null) return true;
        if (cast<CControlListCard>(root) !is null) return true;
        return false;
    }

    string _ShortControlTreeRootSigText(const string &in raw, uint maxLen = 24) {
        string t = CleanUiFormatting(raw).Trim();
        int maxLenInt = int(maxLen);
        if (int(t.Length) > maxLenInt) t = t.SubStr(0, maxLenInt) + "...";
        return t;
    }

    bool _IsControlTreeAnonymousFrameRoot(CControlBase@ root) {
        if (root is null) return false;
        if (cast<CControlFrameStyled>(root) is null && cast<CControlFrame>(root) is null) return false;
        if (root.IdName.Trim().Length > 0) return false;
        if (CleanUiFormatting(root.StackText).Trim().Length > 0) return false;
        if (CleanUiFormatting(ReadText(root)).Trim().Length > 0) return false;
        return true;
    }

    class _ControlTreeRootSignatureState {
        uint budget = 0;
        string sig = "";
    }

    void _AppendControlTreeRootSignature(CControlBase@ n, _ControlTreeRootSignatureState@ st, uint depth, uint maxDepth) {
        if (st is null) return;
        if (st.budget == 0) {
            st.sig += "...";
            return;
        }
        if (n is null) {
            st.sig += "<null>";
            return;
        }

        st.budget--;

        string type = NodeTypeName(n);
        string idName = _ShortControlTreeRootSigText(n.IdName, 18);
        string stack = _ShortControlTreeRootSigText(n.StackText, 24);
        string text = _ShortControlTreeRootSigText(ReadText(n), 24);
        uint childCount = _ChildrenLen(n);

        st.sig += type + "(" + (IsEffectivelyVisible(n) ? "1" : "0") + ":" + childCount;
        if (idName.Length > 0) st.sig += "#" + idName;
        if (stack.Length > 0) st.sig += "$" + stack;
        if (text.Length > 0) st.sig += "\"" + text + "\"";

        if (depth >= maxDepth || childCount == 0) {
            st.sig += ")";
            return;
        }

        st.sig += "[";
        uint childLimit = childCount;
        if (childLimit > 6) childLimit = 6;
        for (uint i = 0; i < childLimit; ++i) {
            if (i > 0) st.sig += ",";
            _AppendControlTreeRootSignature(_ChildAt(n, i), st, depth + 1, maxDepth);
        }
        if (childCount > childLimit) st.sig += ",+" + (childCount - childLimit);
        st.sig += "])";
    }

    string _ControlTreeAnonymousRootSignature(CControlBase@ root) {
        if (!S_ControlTreeHideDuplicateAnonymousRoots) return "";
        if (!_IsControlTreeAnonymousFrameRoot(root)) return "";

        _ControlTreeRootSignatureState@ st = _ControlTreeRootSignatureState();
        st.budget = 48;
        _AppendControlTreeRootSignature(root, st, 0, 4);
        return st.sig;
    }

    bool _TryMarkControlTreeAnonymousRootSignature(CControlBase@ root, dictionary@ seenSigs, bool &out duplicate) {
        duplicate = false;
        if (seenSigs is null) return false;

        string sig = _ControlTreeAnonymousRootSignature(root);
        if (sig.Length == 0) return false;
        if (seenSigs.Exists(sig)) {
            duplicate = true;
            return true;
        }

        seenSigs.Set(sig, true);
        return true;
    }

    void _AdvanceControlTreeOverlayRootsCache(CScene2d@ scene, uint overlay, uint maxMobilsToScan) {
        if (scene is null) return;
        uint mobilsLen = scene.Mobils.Length;
        auto e = _GetControlTreeOverlayRootsCache(overlay, mobilsLen);
        if (e is null || e.complete) return;

        uint budget = maxMobilsToScan;
        if (budget == 0) budget = mobilsLen;

        uint scanned = 0;
        while (e.scanIx < mobilsLen && scanned < budget) {
            auto root = _RootFromMobil(scene, e.scanIx);
            if (!_ShouldDisplayControlTreeOverlayRoot(root)) {
                e.hiddenNoiseRoots++;
            } else {
                bool duplicate = false;
                _TryMarkControlTreeAnonymousRootSignature(root, @e.anonRootSignatures, duplicate);
                if (duplicate) {
                    e.hiddenDuplicateRoots++;
                } else {
                    e.rootIxs.InsertLast(int(e.scanIx));
                }
            }
            e.scanIx++;
            scanned++;
        }
        if (e.scanIx >= mobilsLen) e.complete = true;
    }

    int _FindFirstDisplayableControlTreeRootIx(CScene2d@ scene, uint overlay) {
        if (scene is null) return -1;
        uint mobilsLen = scene.Mobils.Length;
        auto e = _GetControlTreeOverlayRootsCache(overlay, mobilsLen);
        if (e !is null && e.rootIxs.Length > 0) return e.rootIxs[0];

        dictionary seenSigs;
        for (uint i = 0; i < mobilsLen; ++i) {
            auto root = _RootFromMobil(scene, i);
            if (!_ShouldDisplayControlTreeOverlayRoot(root)) continue;
            bool duplicate = false;
            _TryMarkControlTreeAnonymousRootSignature(root, @seenSigs, duplicate);
            if (duplicate) continue;
            return int(i);
        }
        return -1;
    }

    void _RenderControlTreeNode(CControlBase@ n, const string &in relPath, const string &in displayPath, const string &in uiPath,
                                int depth, int rootIx, uint overlay, const string &in filter, const array<_SearchTerm@> &in searchTerms) {
        if (g_ControlTreeRowsTruncated) return;
        if (n is null) return;
        if (filter.Length > 0 && !_ControlTreeSubtreeMatchesCached(n, uiPath, displayPath, filter, searchTerms)) return;

        g_ControlTreeRowsRendered++;
        if (S_DebugTreeRowBudget > 0 && g_ControlTreeRowsRendered > S_DebugTreeRowBudget) {
            g_ControlTreeRowsTruncated = true;
            return;
        }
        bool hasChildren = _ChildrenLen(n) > 0;

        UI::PushID("controlTree-node-row-" + uiPath);

        bool selectPressed = false;
        bool nodPressed = false;
        _DrawStackedTreeActionButtons("controlTree-node-" + uiPath, selectPressed, nodPressed);
        if (selectPressed) _SelectControlTree(n, relPath, displayPath, uiPath, rootIx, overlay);
        if (nodPressed) _OpenNodExplorer(n);
        UI::SameLine();

        bool visible = IsEffectivelyVisible(n);
        bool prevVisible = visible;
        visible = UI::Checkbox("##controlTree-node-vis-" + uiPath, visible);
        if (visible != prevVisible) _SetControlTreeVisibleSelf(n, visible);
        UI::SameLine();

        float indent = float(depth) * 12.0f;
        if (indent > 0.0f) {
            UI::Dummy(vec2(indent, 0.0f));
            UI::SameLine();
        }

        bool open = hasChildren && _IsControlTreeTreeOpen(uiPath);
        if (_DrawTreeToggleButton("controlTree-node-exp-" + uiPath, open, hasChildren)) {
            _SetControlTreeTreeOpen(uiPath, !open);
        }
        UI::SameLine();

        string rowLabel = _ControlTreeLabel(n, uiPath);
        bool selected = (g_SelectedControlTreeUiPath == uiPath);
        UI::Selectable(rowLabel + "##controlTree-node-label-" + uiPath, false);
        _DrawLayerRowHighlight(selected, false);
        bool rowHovered = UI::IsItemHovered();
        bool rowOpenRequested = false;
        bool rowSelectRequested = false;
        _TreeRowMouseActions(rowHovered, hasChildren, rowOpenRequested, rowSelectRequested);
        if (rowOpenRequested) {
            _SetControlTreeTreeOpen(uiPath, !open);
        }
        if (rowSelectRequested) _SelectControlTree(n, relPath, displayPath, uiPath, rootIx, overlay);

        string nodePopupId = "##controlTree-node-popup-" + uiPath;
        if (rowHovered && UI::IsMouseClicked(UI::MouseButton::Middle)) {
            UI::OpenPopup(nodePopupId);
        }
        if (UI::BeginPopup(nodePopupId)) {
            UI::Text(_ControlTreeLabel(n, uiPath));
            UI::Separator();

            if (UI::MenuItem("Select node")) _SelectControlTree(n, relPath, displayPath, uiPath, rootIx, overlay);
            if (UI::MenuItem("Focus this overlay")) g_ControlTreeOverlay = int(overlay);
            if (UI::MenuItem("Show all overlays")) g_ControlTreeOverlay = -1;
            if (hasChildren && UI::MenuItem("Open node tree")) _SetControlTreeTreeOpen(uiPath, true);
            if (UI::MenuItem("Open NOD")) _OpenNodExplorer(n);

            UI::Separator();
            if (UI::MenuItem("Show selected")) _SetControlTreeVisibleSelf(n, true);
            if (UI::MenuItem("Hide selected")) _SetControlTreeVisibleSelf(n, false);

            UI::Separator();
            if (relPath.Length > 0 && UI::MenuItem("Copy relative path")) IO::SetClipboard(relPath);
            if (displayPath.Length > 0 && UI::MenuItem("Copy display path")) IO::SetClipboard(displayPath);

            UI::EndPopup();
        }

        UI::PopID();

        if (!hasChildren || !_IsControlTreeTreeOpen(uiPath)) return;
        uint len = _ChildrenLen(n);
        for (uint i = 0; i < len; ++i) {
            if (g_ControlTreeRowsTruncated) break;
            auto ch = _ChildAt(n, i);
            if (ch is null) continue;
            string childRel = (relPath.Length == 0) ? ("" + i) : (relPath + "/" + i);
            string childDisplay = displayPath + "/" + i;
            string childUi = uiPath + "/" + i;
            _RenderControlTreeNode(ch, childRel, childDisplay, childUi, depth + 1, rootIx, overlay, filter, searchTerms);
        }
    }

    void _RenderControlTreeOverlayTree(uint overlay, const string &in filter, const array<_SearchTerm@> &in searchTerms) {
        CScene2d@ scene;
        if (!_GetScene2d(overlay, scene) || scene is null) return;

        uint rootsLen = scene.Mobils.Length;
        if (rootsLen == 0) return;

        auto rootsCache = _GetControlTreeOverlayRootsCache(overlay, rootsLen);
        bool hasRoots = true;
        bool rootCountExact = false;
        uint rootCount = 0;
        uint hiddenNoiseCount = 0;
        uint hiddenDuplicateCount = 0;

        string overlayUi = "O" + overlay;
        if (filter.Length > 0) {
            hasRoots = false;
            bool overlayHasMatch = false;
            dictionary seenSigs;
            for (uint i = 0; i < rootsLen; ++i) {
                auto root = _RootFromMobil(scene, i);
                if (root is null) continue;
                if (!_ShouldDisplayControlTreeOverlayRoot(root)) {
                    hiddenNoiseCount++;
                    continue;
                }
                bool duplicate = false;
                _TryMarkControlTreeAnonymousRootSignature(root, @seenSigs, duplicate);
                if (duplicate) {
                    hiddenDuplicateCount++;
                    continue;
                }
                hasRoots = true;
                rootCount++;
                string rootPath = "root[" + i + "]";
                string rootUi = overlayUi + "/" + rootPath;
                string rootDisplay = "overlay[" + overlay + "]/" + rootPath;
                if (_ControlTreeSubtreeMatchesCached(root, rootUi, rootDisplay, filter, searchTerms)) {
                    overlayHasMatch = true;
                }
            }
            if (!overlayHasMatch) return;
            rootCountExact = true;
        } else if (_IsControlTreeTreeOpen(overlayUi)) {
            _AdvanceControlTreeOverlayRootsCache(scene, overlay, S_ControlTreeOverlayRootScanBudget);
            if (rootsCache !is null) {
                rootCount = rootsCache.rootIxs.Length;
                hiddenNoiseCount = rootsCache.hiddenNoiseRoots;
                hiddenDuplicateCount = rootsCache.hiddenDuplicateRoots;
                rootCountExact = rootsCache.complete;
                if (rootsCache.complete) hasRoots = rootsCache.rootIxs.Length > 0;
            }
        }

        g_ControlTreeRowsRendered++;
        if (S_DebugTreeRowBudget > 0 && g_ControlTreeRowsRendered > S_DebugTreeRowBudget) {
            g_ControlTreeRowsTruncated = true;
            return;
        }

        UI::PushID("controlTree-overlay-row-" + overlayUi);

        _DrawStackedTreeActionButtonsSpacer();
        UI::SameLine();
        bool overlayVisibleKnown = false;
        bool overlayVisible = false;
        if (g_SelectedControlTreeOverlayAtSel == overlay && g_SelectedControlTreeRootIx >= 0) {
            CControlBase@ selectedRoot = null;
            if (_ResolveControlTreeNodeByPath(overlay, g_SelectedControlTreeRootIx, "", selectedRoot) && selectedRoot !is null) {
                overlayVisible = IsEffectivelyVisible(selectedRoot);
                overlayVisibleKnown = true;
            }
        }
        UI::BeginDisabled();
        UI::Checkbox("##controlTree-overlay-vis-" + overlayUi, overlayVisible);
        UI::EndDisabled();
        if (UI::IsItemHovered()) {
            if (overlayVisibleKnown) {
                UI::SetTooltip("Overlay visibility indicator (selected root only). Toggle roots/nodes directly.");
            } else {
                UI::SetTooltip("Overlay-wide visibility aggregation is skipped for performance. Select a root/node to inspect visibility.");
            }
        }
        UI::SameLine();

        bool open = _IsControlTreeTreeOpen(overlayUi);
        if (_DrawTreeToggleButton("controlTree-overlay-exp-" + overlayUi, open, hasRoots)) {
            _SetControlTreeTreeOpen(overlayUi, !open);
        }
        UI::SameLine();

        bool hasPartialCounts = filter.Length == 0
            && rootsCache !is null
            && _IsControlTreeTreeOpen(overlayUi)
            && !rootsCache.complete
            && (rootCount > 0 || hiddenNoiseCount > 0 || hiddenDuplicateCount > 0);
        string approxSuffix = hasPartialCounts ? "+" : "";

        string overlayMeta = "mobils: " + rootsLen;
        if (rootCountExact || hasPartialCounts) overlayMeta += ", shown: " + rootCount + approxSuffix;
        if (hiddenNoiseCount > 0) overlayMeta += ", hidden empty: " + hiddenNoiseCount + approxSuffix;
        if (hiddenDuplicateCount > 0) overlayMeta += ", hidden dup: " + hiddenDuplicateCount + approxSuffix;
        string overlayLabel = _LayerTextColorCode(overlay)
            + "Overlay[" + overlay + "] \\$999(" + overlayMeta + ")\\$z";
        bool viewed = (g_ControlTreeOverlay >= 0 && g_ControlTreeOverlay == int(overlay));
        UI::Selectable(overlayLabel + "##controlTree-overlay-label-" + overlayUi, false);
        _DrawLayerRowHighlight(false, viewed);
        bool rowHovered = UI::IsItemHovered();
        bool rowOpenRequested = false;
        bool rowSelectRequested = false;
        _TreeRowMouseActions(rowHovered, hasRoots, rowOpenRequested, rowSelectRequested);
        if (rowOpenRequested) {
            _SetControlTreeTreeOpen(overlayUi, !open);
        }
        if (rowSelectRequested) {
            int firstRootIx = _FindFirstDisplayableControlTreeRootIx(scene, overlay);
            if (firstRootIx >= 0) _SelectControlTreeLayerRoot(overlay, firstRootIx);
        }

        string overlayPopupId = "##controlTree-overlay-popup-" + overlayUi;
        if (rowHovered && UI::IsMouseClicked(UI::MouseButton::Middle)) {
            UI::OpenPopup(overlayPopupId);
        }
        if (UI::BeginPopup(overlayPopupId)) {
            string popupLabel = "Overlay[" + overlay + "] | mobils: " + rootsLen;
            if (rootCountExact || hasPartialCounts) popupLabel += " | shown: " + rootCount + approxSuffix;
            if (hiddenNoiseCount > 0) popupLabel += " | hidden empty: " + hiddenNoiseCount + approxSuffix;
            if (hiddenDuplicateCount > 0) popupLabel += " | hidden dup: " + hiddenDuplicateCount + approxSuffix;
            UI::Text(popupLabel);
            UI::Separator();
            if (UI::MenuItem("Focus this overlay")) g_ControlTreeOverlay = int(overlay);
            if (UI::MenuItem("Show all overlays")) g_ControlTreeOverlay = -1;
            if (UI::MenuItem("Open overlay tree")) _SetControlTreeTreeOpen(overlayUi, true);

            UI::Separator();
            if (UI::MenuItem("Show overlay roots")) {
                for (uint i = 0; i < rootsLen; ++i) {
                    auto root = _RootFromMobil(scene, i);
                    if (root is null) continue;
                    _SetControlTreeVisibleSelf(root, true);
                }
            }
            if (UI::MenuItem("Hide overlay roots")) {
                for (uint i = 0; i < rootsLen; ++i) {
                    auto root = _RootFromMobil(scene, i);
                    if (root is null) continue;
                    _SetControlTreeVisibleSelf(root, false);
                }
            }

            UI::EndPopup();
        }

        UI::PopID();

        if (!_IsControlTreeTreeOpen(overlayUi)) return;
        if (filter.Length == 0) {
            _AdvanceControlTreeOverlayRootsCache(scene, overlay, S_ControlTreeOverlayRootScanBudget);
            if (rootsCache !is null) {
                for (uint i = 0; i < rootsCache.rootIxs.Length; ++i) {
                    if (g_ControlTreeRowsTruncated) break;
                    int rootIx = rootsCache.rootIxs[i];
                    if (rootIx < 0) continue;
                    auto root = _RootFromMobil(scene, uint(rootIx));
                    if (root is null) continue;
                    string rootPath = "root[" + rootIx + "]";
                    string rootUi = overlayUi + "/" + rootPath;
                    string rootDisplay = "overlay[" + overlay + "]/" + rootPath;
                    _RenderControlTreeNode(root, "", rootDisplay, rootUi, 1, rootIx, overlay, filter, searchTerms);
                }
                if (!rootsCache.complete && !g_ControlTreeRowsTruncated) {
                    UI::TextDisabled("Scanning overlay roots...");
                }
            }
            return;
        }
        dictionary seenSigs;
        for (uint i = 0; i < rootsLen; ++i) {
            if (g_ControlTreeRowsTruncated) break;
            auto root = _RootFromMobil(scene, i);
            if (root is null) continue;
            if (!_ShouldDisplayControlTreeOverlayRoot(root)) continue;
            bool duplicate = false;
            _TryMarkControlTreeAnonymousRootSignature(root, @seenSigs, duplicate);
            if (duplicate) continue;
            string rootPath = "root[" + i + "]";
            string rootUi = overlayUi + "/" + rootPath;
            string rootDisplay = "overlay[" + overlay + "]/" + rootPath;
            _RenderControlTreeNode(root, "", rootDisplay, rootUi, 1, int(i), overlay, filter, searchTerms);
        }
    }

    void _RenderControlTreeTree() {
        string filter = g_ControlTreeSearch.Trim();
        array<_SearchTerm@> searchTerms = _SearchParseTerms(filter);
        _ControlTreeSearchTick(filter);

        if (g_ControlTreeCollapseAll) {
            g_ControlTreeTreeOpen.DeleteAll();
            g_ControlTreeCollapseAll = false;
        }

        g_ControlTreeRowsRendered = 0;
        g_ControlTreeRowsTruncated = false;

        if (g_ControlTreeNodeFocusActive) {
            CControlBase@ focusNode = null;
            bool ok = _ResolveControlTreeNodeByPath(
                g_ControlTreeNodeFocusOverlay,
                g_ControlTreeNodeFocusRootIx,
                g_ControlTreeNodeFocusPath,
                focusNode
            );
            if (!ok || focusNode is null) {
                UI::Text("\\$f80Focused node is no longer available. Clear node focus to continue.\\$z");
                return;
            }

            string focusUi = g_ControlTreeNodeFocusUiPath;
            if (focusUi.Length == 0) {
                focusUi = "O" + g_ControlTreeNodeFocusOverlay + "/root[" + g_ControlTreeNodeFocusRootIx + "]";
                if (g_ControlTreeNodeFocusPath.Length > 0) focusUi += "/" + g_ControlTreeNodeFocusPath;
            }
            string focusDisplay = _ControlTreePathDisplay(g_ControlTreeNodeFocusOverlay, g_ControlTreeNodeFocusRootIx, g_ControlTreeNodeFocusPath);
            _SetControlTreeTreeOpen(focusUi, true);
            _RenderControlTreeNode(
                focusNode,
                g_ControlTreeNodeFocusPath,
                focusDisplay,
                focusUi,
                0,
                g_ControlTreeNodeFocusRootIx,
                g_ControlTreeNodeFocusOverlay,
                filter,
                searchTerms
            );
            if (g_ControlTreeRowsRendered == 0) UI::Text("No matching controls.");
            else if (g_ControlTreeRowsTruncated) {
                UI::Text("\\$f80Tree rows truncated at budget " + S_DebugTreeRowBudget + ". Refine search or open fewer branches.\\$z");
                _RenderTreeRowBudgetOverride("controlTree-focus");
            }
            UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
            return;
        }

        uint overlayCount = 0;
        if (!_TryGetControlTreeOverlayCount(overlayCount) || overlayCount == 0) {
            UI::Text("No overlays available.");
            return;
        }

        uint startOverlay = 0;
        uint endOverlay = overlayCount;
        if (g_ControlTreeOverlay >= 0) {
            if (uint(g_ControlTreeOverlay) >= overlayCount) {
                UI::Text("Overlay index out of range.");
                return;
            }
            startOverlay = uint(g_ControlTreeOverlay);
            endOverlay = startOverlay + 1;
        }

        for (uint ov = startOverlay; ov < endOverlay; ++ov) {
            if (g_ControlTreeRowsTruncated) break;
            _RenderControlTreeOverlayTree(ov, filter, searchTerms);
        }

        if (g_ControlTreeRowsRendered == 0) UI::Text("No matching controls.");
        else if (g_ControlTreeRowsTruncated) {
            UI::Text("\\$f80Tree rows truncated at budget " + S_DebugTreeRowBudget + ". Refine search or open fewer branches.\\$z");
            _RenderTreeRowBudgetOverride("controlTree");
        }

        UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
    }

}
}
