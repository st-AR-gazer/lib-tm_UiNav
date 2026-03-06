namespace UiNav {
namespace Debug {

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

        bool hasRoots = false;
        uint rootCount = 0;
        uint rootsLen = scene.Mobils.Length;
        for (uint i = 0; i < rootsLen; ++i) {
            if (_RootFromMobil(scene, i) !is null) {
                hasRoots = true;
                rootCount++;
            }
        }
        if (!hasRoots) return;

        string overlayUi = "O" + overlay;
        if (filter.Length > 0) {
            bool overlayHasMatch = false;
            for (uint i = 0; i < rootsLen; ++i) {
                auto root = _RootFromMobil(scene, i);
                if (root is null) continue;
                string rootPath = "root[" + i + "]";
                string rootUi = overlayUi + "/" + rootPath;
                string rootDisplay = "overlay[" + overlay + "]/" + rootPath;
                if (_ControlTreeSubtreeMatchesCached(root, rootUi, rootDisplay, filter, searchTerms)) {
                    overlayHasMatch = true;
                    break;
                }
            }
            if (!overlayHasMatch) return;
        }

        g_ControlTreeRowsRendered++;
        if (S_DebugTreeRowBudget > 0 && g_ControlTreeRowsRendered > S_DebugTreeRowBudget) {
            g_ControlTreeRowsTruncated = true;
            return;
        }

        UI::PushID("controlTree-overlay-row-" + overlayUi);

        _DrawStackedTreeActionButtonsSpacer();
        UI::SameLine();
        bool overlayVisibleAny = false;
        for (uint i = 0; i < rootsLen; ++i) {
            auto root = _RootFromMobil(scene, i);
            if (root is null) continue;
            bool v = IsEffectivelyVisible(root);
            if (v) overlayVisibleAny = true;
        }
        bool overlayVisible = overlayVisibleAny;
        UI::BeginDisabled();
        UI::Checkbox("##controlTree-overlay-vis-" + overlayUi, overlayVisible);
        UI::EndDisabled();
        if (UI::IsItemHovered()) UI::SetTooltip("Overlay visibility indicator (read-only). Toggle roots/nodes directly.");
        UI::SameLine();

        bool open = _IsControlTreeTreeOpen(overlayUi);
        if (_DrawTreeToggleButton("controlTree-overlay-exp-" + overlayUi, open, hasRoots)) {
            _SetControlTreeTreeOpen(overlayUi, !open);
        }
        UI::SameLine();

        string overlayLabel = _LayerTextColorCode(overlay)
            + "Overlay[" + overlay + "] \\$999(mobils: " + rootsLen + ", roots: " + rootCount + ")\\$z";
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
            for (uint i = 0; i < rootsLen; ++i) {
                auto root = _RootFromMobil(scene, i);
                if (root is null) continue;
                _SelectControlTreeLayerRoot(overlay, int(i));
                break;
            }
        }

        string overlayPopupId = "##controlTree-overlay-popup-" + overlayUi;
        if (rowHovered && UI::IsMouseClicked(UI::MouseButton::Middle)) {
            UI::OpenPopup(overlayPopupId);
        }
        if (UI::BeginPopup(overlayPopupId)) {
            UI::Text("Overlay[" + overlay + "] | mobils: " + rootsLen + " | roots: " + rootCount);
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
        for (uint i = 0; i < rootsLen; ++i) {
            if (g_ControlTreeRowsTruncated) break;
            auto root = _RootFromMobil(scene, i);
            if (root is null) continue;
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
        }

        UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
    }

}
}
