namespace UiNav {
namespace Debug {

    int g_MlUnifiedSourceKind = -1;

    int _MlFirstAvailableSourceKind(bool hasPlayground, bool hasMenu, bool hasEditor) {
        if (hasPlayground) return 0;
        if (hasMenu) return 1;
        if (hasEditor) return 2;
        return -1;
    }

    void _EnsureMlUnifiedSourceKind(bool hasPlayground, bool hasMenu, bool hasEditor) {
        bool valid = (g_MlUnifiedSourceKind == 0 && hasPlayground)
            || (g_MlUnifiedSourceKind == 1 && hasMenu)
            || (g_MlUnifiedSourceKind == 2 && hasEditor);
        if (valid) return;
        g_MlUnifiedSourceKind = _MlFirstAvailableSourceKind(hasPlayground, hasMenu, hasEditor);
    }

    void _RenderMlUnifiedSourceTabs(bool hasPlayground, bool hasMenu, bool hasEditor) {
        _EnsureMlUnifiedSourceKind(hasPlayground, hasMenu, hasEditor);

        UI::BeginTabBar("##ml-source-tabs");
        if (hasPlayground) {
            if (UI::BeginTabItem("Playground")) {
                g_MlUnifiedSourceKind = 0;
                _RenderMlTreePane(0);
                UI::EndTabItem();
            }
        } else {
            UI::BeginDisabled();
            bool opened = UI::BeginTabItem("Playground");
            if (opened) UI::EndTabItem();
            UI::EndDisabled();
        }

        if (hasMenu) {
            if (UI::BeginTabItem("Menu")) {
                g_MlUnifiedSourceKind = 1;
                _RenderMlTreePane(1);
                UI::EndTabItem();
            }
        } else {
            UI::BeginDisabled();
            bool opened = UI::BeginTabItem("Menu");
            if (opened) UI::EndTabItem();
            UI::EndDisabled();
        }

        if (hasEditor) {
            if (UI::BeginTabItem("Editor")) {
                g_MlUnifiedSourceKind = 2;
                _RenderMlTreePane(2);
                UI::EndTabItem();
            }
        } else {
            UI::BeginDisabled();
            bool opened = UI::BeginTabItem("Editor");
            if (opened) UI::EndTabItem();
            UI::EndDisabled();
        }
        UI::EndTabBar();
    }

    void _RenderMlUnifiedPane(bool hasPlayground, bool hasMenu, bool hasEditor) {
        if (!hasPlayground && !hasMenu && !hasEditor) {
            UI::Text("No inspectable ManiaLink data is currently available.");
            return;
        }
        _RenderMlUnifiedSourceTabs(hasPlayground, hasMenu, hasEditor);
    }

    void _RenderMlTab() {
        _MlApplyValueLocks();

        bool hasPlayground = _MlHasInspectableData(0);
        bool hasMenu = _MlHasInspectableData(1);
        bool hasEditor = _MlHasInspectableData(2);
        _RenderMlUnifiedPane(hasPlayground, hasMenu, hasEditor);
    }

    void _RenderMlTreePane(int appKind) {
        g_MlActiveAppKind = appKind;
        g_MlSearch = UI::InputText("Search", g_MlSearch);
        UI::SameLine();
        if (UI::Button("Clear##ml-search")) g_MlSearch = "";
        UI::SameLine();
        S_MlSearchGlobal = UI::Checkbox("Global##ml-search-global", S_MlSearchGlobal);
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Global on: search full tree.\nGlobal off: search only currently visible rows.");
        }
        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        UI::Text("Layer");
        if (UI::IsItemHovered()) UI::SetTooltip("View layer index (-1 = all)");
        UI::SameLine();
        UI::SetNextItemWidth(110.0f);
        g_MlViewLayerIndex = UI::InputInt("##ml-view-layer-index", g_MlViewLayerIndex);
        if (UI::IsItemHovered()) UI::SetTooltip("View layer index (-1 = all)");
        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        bool liveLayerBox = UiNav::Builder::S_LiveLayerBoundsOverlayEnabled;
        liveLayerBox = UI::Checkbox("Live layer box##ml-live-layer-box", liveLayerBox);
        if (liveLayerBox != UiNav::Builder::S_LiveLayerBoundsOverlayEnabled) {
            UiNav::Builder::S_LiveLayerBoundsOverlayEnabled = liveLayerBox;
            if (liveLayerBox) UiNav::Builder::RefreshLiveLayerBoundsOverlay(true);
            else UiNav::Builder::DestroyLiveLayerBoundsOverlay();
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Draw bounds for selected ML layer/subtree in live UI.");
        }
        UI::Text("\\$888Search: words (AND), \"quoted text\", -exclude, id:, text:, class:, type:, path:, vis:true/false\\$z");
        UI::Text("\\$888Scope: " + (S_MlSearchGlobal ? "global (full tree)" : "visible only (open rows)") + "\\$z");
        if (g_MlViewLayerIndex < -1) g_MlViewLayerIndex = -1;

        if (!_MlSourceAvailable(appKind)) {
            _DiagBreadcrumb("ML pane: source unavailable (return)", "_RenderMlTreePane", /*forceWrite=*/true);
            UI::Text(_MlAppNameByKind(appKind) + " source not available.");
            return;
        }

        if (g_MlNodeFocusActive && g_MlNodeFocusAppKind == appKind) {
            string parentPath = _MlNodeFocusParentPathDisplay();
            UI::TextDisabled("Focused parent path:");
            UI::SameLine();
            UI::Text(parentPath.Length > 0 ? parentPath : "<none>");
            UI::SameLine();
            if (UI::Button("Clear node focus##ml-pane")) {
                _ClearMlNodeFocus();
                g_MlNodeFocusStatus = "Cleared node focus.";
            }
        }

        UI::Separator();

        float paneHeight = UI::GetContentRegionAvail().y - UI::GetFrameHeightWithSpacing() - 6.0f;
        paneHeight = Math::Floor(paneHeight);
        if (paneHeight < 1.0f) paneHeight = 1.0f;

        UI::BeginGroup();
        UI::Text("Tree");
        UI::SameLine();
        if (UI::Button("Collapse all##ml")) g_MlCollapseAll = true;
        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        UI::Text("Favorites");
        UI::SameLine();
        _RenderMlFavoritesSelector(appKind);
        bool mlTreeOpen = UI::BeginChild("##ml-tree", vec2(float(g_MlTreeWidth), paneHeight), true);
        if (mlTreeOpen) {
            _RenderMlLayersTree();
        }
        UI::EndChild();
        UI::EndGroup();
        if (g_MlCollapseAll) g_MlCollapseAll = false;

        UI::SameLine();
        g_MlTreeWidth = _DrawMlSplitter("##ml-splitter", g_MlTreeWidth, paneHeight);
        S_MlTreeWidth = g_MlTreeWidth;
        UI::SameLine();

        UI::BeginGroup();
        UI::Text("Selection");
        bool mlDetailsOpen = UI::BeginChild("##ml-details", vec2(0, paneHeight), true);
        if (mlDetailsOpen) {
            _RenderMlSelection();
        }
        UI::EndChild();
        UI::EndGroup();

        UI::Separator();
    }

    string _LayerTextColorCode(uint layerIx) {
        const string[] palette = {
            "\\$cef", // light cyan
            "\\$dcf", // light violet
            "\\$cfd", // light mint
            "\\$fdc", // light peach
            "\\$cdf", // light blue
            "\\$ecf", // light purple
            "\\$dfc", // light green
            "\\$fec"  // light sand
        };
        return palette[layerIx % palette.Length];
    }

    void _DrawLayerRowHighlight(bool selected, bool viewed) {
        if (!selected && !viewed) return;
        vec4 r = UI::GetItemRect();
        vec4 box = vec4(r.x - 2.0f, r.y - 1.0f, r.z + 2.0f, r.w + 1.0f);
        auto dl = UI::GetWindowDrawList();
        if (selected) {
            dl.AddRectFilled(box, vec4(0.28f, 0.62f, 1.0f, 0.11f));
            dl.AddRect(box, vec4(0.40f, 0.74f, 1.0f, 0.48f));
            return;
        }
        dl.AddRectFilled(box, vec4(0.28f, 0.62f, 1.0f, 0.06f));
        dl.AddRect(box, vec4(0.40f, 0.74f, 1.0f, 0.24f));
    }

    string _MlFavoritePreviewLabel(int appKind) {
        if (g_MlViewLayerIndex < 0) return "All layers";
        _MlLayerFavoritesEnsureLoaded();
        int favIx = _MlFindLayerFavoriteIx(appKind, g_MlViewLayerIndex);
        if (favIx >= 0) return _MlFavoriteDisplayLabel(g_MlLayerFavorites[uint(favIx)], false);
        return "L[" + g_MlViewLayerIndex + "]";
    }

    void _RenderMlFavoritesSelector(int appKind) {
        _MlLayerFavoritesEnsureLoaded();
        string preview = _MlFavoritePreviewLabel(appKind);
        UI::SetNextItemWidth(250.0f);
        if (!UI::BeginCombo("##ml-favorites-selector", preview)) return;

        string curId = "";
        if (g_MlViewLayerIndex >= 0) {
            auto curLayer = _GetMlLayerByIx(appKind, g_MlViewLayerIndex);
            curId = _MlFavoriteLayerId(curLayer);
        }

        bool allSelected = g_MlViewLayerIndex < 0;
        if (UI::Selectable("All layers##ml-fav-all", allSelected)) g_MlViewLayerIndex = -1;
        UI::Separator();

        bool any = false;
        for (uint i = 0; i < g_MlLayerFavorites.Length; ++i) {
            auto fav = g_MlLayerFavorites[i];
            if (fav is null || fav.appKind != appKind) continue;
            any = true;
            string label = _MlFavoriteDisplayLabel(fav, false);
            bool selected = false;
            if (curId.Length > 0 && fav.layerId.Length > 0) {
                selected = (fav.layerId == curId);
            } else {
                selected = (g_MlViewLayerIndex == fav.layerIx);
            }
            if (UI::Selectable(label + "##ml-favorite-" + i, selected)) {
                int targetIx = fav.layerIx;
                if (fav.layerId.Length > 0) {
                    targetIx = _MlResolveFavoriteLayerIx(appKind, fav.layerId, fav.layerIx);
                    if (targetIx >= 0) fav.layerIx = targetIx;
                }
                if (targetIx >= 0) {
                    g_MlViewLayerIndex = targetIx;
                } else {
                    UI::ShowNotification("UiNav", "Favorite layer not found in " + _MlAppNameByKind(appKind) + ".", 6000);
                }
            }
        }
        if (!any) UI::TextDisabled("No favorites in this mode.");

        UI::EndCombo();
    }

    void _RenderMlNodeTree(CGameManialinkControl@ n, const string &in path, const string &in uiPath, int depth, int layerIx,
                           const string &in filter, const array<_SearchTerm@> &in searchTerms) {
        if (g_MlRowsTruncated) return;
        if (n is null) return;
        if (filter.Length > 0) {
            bool matches = false;
            if (S_MlSearchGlobal) {
                matches = _MlSubtreeMatchesCached(n, uiPath, filter, searchTerms);
            } else {
                bool allowChildren = _IsMlTreeOpen(uiPath);
                matches = _MlSubtreeMatchesVisibleCached(n, uiPath, filter, searchTerms, allowChildren);
            }
            if (!matches) return;
        }

        g_MlRowsRendered++;
        if (S_DebugTreeRowBudget > 0 && g_MlRowsRendered > S_DebugTreeRowBudget) {
            g_MlRowsTruncated = true;
            return;
        }
        auto frame = cast<CGameManialinkFrame@>(n);
        bool hasChildren = frame !is null && frame.Controls.Length > 0;

        UI::PushID("ml-node-row-" + uiPath);

        bool selectPressed = false;
        bool nodPressed = false;
        _DrawStackedTreeActionButtons("ml-node-" + uiPath, selectPressed, nodPressed);
        if (selectPressed) _SelectMl(n, path, uiPath, layerIx);
        if (nodPressed) _OpenNodExplorer(n);
        UI::SameLine();

        bool visible = n.Visible;
        bool prevVisible = visible;
        visible = UI::Checkbox("##ml-node-vis-" + uiPath, visible);
        if (visible != prevVisible) _SetMlVisibleSelf(n, visible);
        UI::SameLine();

        float indent = float(depth) * 12.0f;
        if (indent > 0.0f) {
            UI::Dummy(vec2(indent, 0.0f));
            UI::SameLine();
        }

        bool open = hasChildren && _IsMlTreeOpen(uiPath);
        if (_DrawTreeToggleButton("ml-node-exp-" + uiPath, open, hasChildren)) {
            _SetMlTreeOpen(uiPath, !open);
        }
        UI::SameLine();

        string rowLabel = _MlLabel(n, uiPath);
        bool selected = (g_SelectedMlUiPath == uiPath);
        UI::Selectable(rowLabel + "##ml-node-label-" + uiPath, false);
        _DrawLayerRowHighlight(selected, false);
        bool rowHovered = UI::IsItemHovered();
        bool rowOpenRequested = false;
        bool rowSelectRequested = false;
        _TreeRowMouseActions(rowHovered, hasChildren, rowOpenRequested, rowSelectRequested);
        if (rowOpenRequested) {
            _SetMlTreeOpen(uiPath, !open);
        }
        if (rowSelectRequested) _SelectMl(n, path, uiPath, layerIx);

        string nodePopupId = "##ml-node-popup-" + uiPath;
        if (rowHovered && UI::IsMouseClicked(UI::MouseButton::Middle)) {
            UI::OpenPopup(nodePopupId);
        }
        if (UI::BeginPopup(nodePopupId)) {
            UI::Text(_MlLabel(n, uiPath));
            UI::Separator();

            if (UI::MenuItem("Select node")) _SelectMl(n, path, uiPath, layerIx);
            if (UI::MenuItem("Focus this layer")) g_MlViewLayerIndex = layerIx;
            if (UI::MenuItem("Show all layers")) g_MlViewLayerIndex = -1;
            if (hasChildren && UI::MenuItem("Open node tree")) _SetMlTreeOpen(uiPath, true);

            _MlValueLocksEnsureLoaded();
            UI::Separator();

            int visLockIx = _MlFindValueLockIx(g_MlActiveAppKind, layerIx, path, 3);
            bool currentVisible = n.Visible;
            if (visLockIx >= 0) {
                auto visLock = g_MlValueLocks[uint(visLockIx)];
                bool visEnabled = visLock !is null && visLock.enabled;
                bool lockedVisible = visLock is null ? currentVisible : _MlParseBoolLockValue(visLock.lockedValue, currentVisible);

                string visToggle = visEnabled ? "Disable visibility lock" : "Enable visibility lock";
                if (UI::MenuItem(visToggle)) {
                    _MlSetValueLockEnabled(g_MlActiveAppKind, layerIx, path, 3, !visEnabled);
                    g_MlValueLocksStatus = visEnabled ? "Disabled visibility lock." : "Enabled visibility lock.";
                }

                string visSet = lockedVisible ? "Set lock to hidden" : "Set lock to visible";
                if (UI::MenuItem(visSet)) {
                    _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, path, !lockedVisible);
                    g_MlValueLocksStatus = !lockedVisible ? "Visibility lock set to visible." : "Visibility lock set to hidden.";
                }

                if (UI::MenuItem("Remove visibility lock")) {
                    _MlRemoveVisibilityLock(g_MlActiveAppKind, layerIx, path);
                    g_MlValueLocksStatus = "Removed visibility lock.";
                }
            } else {
                if (UI::MenuItem("Lock visibility: visible")) {
                    _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, path, true);
                    g_MlValueLocksStatus = "Added visibility lock (visible).";
                }
                if (UI::MenuItem("Lock visibility: hidden")) {
                    _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, path, false);
                    g_MlValueLocksStatus = "Added visibility lock (hidden).";
                }
            }

            UI::Separator();
            int lockKind = _MlValueLockKindForNode(n);
            if (lockKind > 0) {
                int existingIx = _MlFindValueLockIx(g_MlActiveAppKind, layerIx, path, lockKind);
                if (existingIx >= 0) {
                    auto lock = g_MlValueLocks[uint(existingIx)];
                    if (lock !is null) {
                        string toggleText = lock.enabled ? "Disable value lock" : "Enable value lock";
                        if (UI::MenuItem(toggleText)) {
                            lock.enabled = !lock.enabled;
                            _MlValueLocksSave();
                            g_MlValueLocksStatus = lock.enabled ? "Enabled value lock." : "Disabled value lock.";
                        }
                    }
                    if (UI::MenuItem("Update lock from current value")) {
                        string currentVal = _MlValueLockReadNodeValue(n, lockKind);
                        bool ok = _MlAddOrUpdateValueLock(g_MlActiveAppKind, layerIx, path, n, currentVal);
                        g_MlValueLocksStatus = ok ? "Updated value lock." : "Could not update value lock.";
                    }
                    if (UI::MenuItem("Remove value lock")) {
                        bool removed = _MlRemoveValueLock(g_MlActiveAppKind, layerIx, path, n);
                        g_MlValueLocksStatus = removed ? "Removed value lock." : "No value lock to remove.";
                    }
                } else {
                    if (UI::MenuItem("Lock this value")) {
                        string currentVal = _MlValueLockReadNodeValue(n, lockKind);
                        bool ok = _MlAddOrUpdateValueLock(g_MlActiveAppKind, layerIx, path, n, currentVal);
                        g_MlValueLocksStatus = ok ? "Added value lock." : "Could not lock this value.";
                    }
                }
            } else {
                UI::TextDisabled("No lockable Value on this node.");
            }

            UI::EndPopup();
        }

        UI::PopID();

        if (!hasChildren || !_IsMlTreeOpen(uiPath)) return;
        for (uint i = 0; i < frame.Controls.Length; ++i) {
            if (g_MlRowsTruncated) break;
            auto ch = frame.Controls[i];
            if (ch is null) continue;
            string childPath = (path.Length == 0) ? ("" + i) : (path + "/" + i);
            string childUi = uiPath + "/" + i;
            _RenderMlNodeTree(ch, childPath, childUi, depth + 1, layerIx, filter, searchTerms);
        }
    }

    void _RenderMlLayerTree(CGameUILayer@ layer, int layerIx, const string &in layerUiPath,
                            const string &in filter, const array<_SearchTerm@> &in searchTerms) {
        if (g_MlRowsTruncated) return;
        if (layer is null) return;
        auto root = (layer.LocalPage !is null) ? layer.LocalPage.MainFrame : null;
        if (filter.Length > 0) {
            if (root is null) return;
            bool matches = false;
            if (S_MlSearchGlobal) {
                matches = _MlSubtreeMatchesCached(root, layerUiPath, filter, searchTerms);
            } else {
                bool allowChildren = _IsMlTreeOpen(layerUiPath);
                matches = _MlSubtreeMatchesVisibleCached(root, layerUiPath, filter, searchTerms, allowChildren);
            }
            if (!matches) return;
        }

        g_MlRowsRendered++;
        if (S_DebugTreeRowBudget > 0 && g_MlRowsRendered > S_DebugTreeRowBudget) {
            g_MlRowsTruncated = true;
            return;
        }
        string layerName = _CachedMlLayerName(layer, g_MlActiveAppKind, layerIx);
        string layerLabel = "Layer[" + layerIx + "]";
        if (layerName.Length > 0) layerLabel += " " + layerName;
        string tag = "";

        auto rootFrame = cast<CGameManialinkFrame@>(root);
        bool hasChildren = rootFrame !is null && rootFrame.Controls.Length > 0;

        UI::PushID("ml-layer-row-" + layerUiPath);

        bool selectPressed = false;
        bool nodPressed = false;
        if (root !is null) _DrawStackedTreeActionButtons("ml-layer-" + layerUiPath, selectPressed, nodPressed);
        else _DrawStackedTreeActionButtonsSpacer();
        if (selectPressed && root !is null) _SelectMl(root, "", layerUiPath, layerIx);
        if (nodPressed && root !is null) _OpenNodExplorer(root);
        UI::SameLine();

        bool visible = layer.IsVisible;
        bool prevVisible = visible;
        visible = UI::Checkbox("##ml-layer-vis-" + layerUiPath, visible);
        if (visible != prevVisible) layer.IsVisible = visible;
        UI::SameLine();

        bool open = hasChildren && _IsMlTreeOpen(layerUiPath);
        if (_DrawTreeToggleButton("ml-layer-exp-" + layerUiPath, open, hasChildren)) {
            _SetMlTreeOpen(layerUiPath, !open);
        }
        UI::SameLine();

        string rowLabel = _LayerTextColorCode(layerIx) + layerLabel + "\\$z";
        bool selected = (g_SelectedMlUiPath == layerUiPath);
        bool viewed = (g_MlViewLayerIndex >= 0 && g_MlViewLayerIndex == layerIx);
        UI::Selectable(rowLabel + "##ml-layer-label-" + layerUiPath, false);
        _DrawLayerRowHighlight(selected, viewed);
        bool rowHovered = UI::IsItemHovered();
        if (selected || viewed || rowHovered) {
            tag = UiNav::LayerTags::GetTagForLayer(layer, layerIx);
        }
        bool rowOpenRequested = false;
        bool rowSelectRequested = false;
        _TreeRowMouseActions(rowHovered, hasChildren, rowOpenRequested, rowSelectRequested);
        if (rowOpenRequested) {
            _SetMlTreeOpen(layerUiPath, !open);
        }
        if (rowSelectRequested && root !is null) _SelectMl(root, "", layerUiPath, layerIx);

        string layerPopupId = "##ml-layer-popup-" + layerUiPath;
        if (rowHovered && UI::IsMouseClicked(UI::MouseButton::Middle)) {
            UI::OpenPopup(layerPopupId);
        }
        if (UI::BeginPopup(layerPopupId)) {
            string popupLayerName = _CachedMlLayerName(layer, g_MlActiveAppKind, layerIx);
            string popupLabel = "Layer[" + layerIx + "]";
            if (popupLayerName.Length > 0) popupLabel += " " + popupLayerName;
            UI::Text(popupLabel);
            UI::Separator();

            if (UI::MenuItem("Focus this layer")) g_MlViewLayerIndex = layerIx;
            if (UI::MenuItem("Show all layers")) g_MlViewLayerIndex = -1;
            if (UI::MenuItem("Open layer tree")) _SetMlTreeOpen(layerUiPath, true);
            if (root !is null && UI::MenuItem("Select layer")) _SelectMl(root, "", layerUiPath, layerIx);
            if (UI::MenuItem("Copy layer to Builder")) {
                string builderStatus = "";
                _MlImportLayerToBuilder(g_MlActiveAppKind, layerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }
            if (UI::MenuItem("Copy layer to Builder + ORIGIN marker")) {
                string builderStatus = "";
                _MlImportLayerToBuilderWithOrigin(g_MlActiveAppKind, layerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }
            if (UI::MenuItem("Copy layer to Builder (force-fit once)")) {
                string builderStatus = "";
                _MlImportLayerToBuilderForceFitOnce(g_MlActiveAppKind, layerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }

            bool isFavorite = _MlIsLayerFavorite(g_MlActiveAppKind, layerIx);
            if (isFavorite) {
                if (UI::MenuItem("Remove favorite")) {
                    _MlRemoveLayerFavorite(g_MlActiveAppKind, layerIx);
                }
            } else {
                if (UI::MenuItem("Favorite this layer")) {
                    _MlAddLayerFavorite(g_MlActiveAppKind, layerIx, popupLayerName);
                }
            }

            if (root !is null) {
                UI::Separator();
                int layerVisLockIx = _MlFindValueLockIx(g_MlActiveAppKind, layerIx, "", 3);
                if (layerVisLockIx >= 0) {
                    auto visLock = g_MlValueLocks[uint(layerVisLockIx)];
                    bool visEnabled = visLock !is null && visLock.enabled;
                    bool lockedVisible = visLock is null ? root.Visible : _MlParseBoolLockValue(visLock.lockedValue, root.Visible);

                    string visToggle = visEnabled ? "Disable layer visibility lock" : "Enable layer visibility lock";
                    if (UI::MenuItem(visToggle)) {
                        _MlSetValueLockEnabled(g_MlActiveAppKind, layerIx, "", 3, !visEnabled);
                        g_MlValueLocksStatus = visEnabled ? "Disabled layer visibility lock." : "Enabled layer visibility lock.";
                    }

                    string visSet = lockedVisible ? "Set layer lock to hidden" : "Set layer lock to visible";
                    if (UI::MenuItem(visSet)) {
                        _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, "", !lockedVisible);
                        g_MlValueLocksStatus = !lockedVisible ? "Layer visibility lock set to visible." : "Layer visibility lock set to hidden.";
                    }

                    if (UI::MenuItem("Remove layer visibility lock")) {
                        _MlRemoveVisibilityLock(g_MlActiveAppKind, layerIx, "");
                        g_MlValueLocksStatus = "Removed layer visibility lock.";
                    }
                } else {
                    if (UI::MenuItem("Lock layer visibility: visible")) {
                        _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, "", true);
                        g_MlValueLocksStatus = "Added layer visibility lock (visible).";
                    }
                    if (UI::MenuItem("Lock layer visibility: hidden")) {
                        _MlAddOrUpdateVisibilityLock(g_MlActiveAppKind, layerIx, "", false);
                        g_MlValueLocksStatus = "Added layer visibility lock (hidden).";
                    }
                }
            }

            bool hasLayerLocks = _MlLayerHasValueLocks(g_MlActiveAppKind, layerIx);
            if (hasLayerLocks) {
                bool anyLayerLocksEnabled = _MlLayerAnyValueLockEnabled(g_MlActiveAppKind, layerIx);
                string toggleLabel = anyLayerLocksEnabled ? "Disable value locks (layer)" : "Enable value locks (layer)";
                if (UI::MenuItem(toggleLabel)) {
                    int changed = _MlSetLayerValueLocksEnabled(g_MlActiveAppKind, layerIx, !anyLayerLocksEnabled);
                    if (changed > 0) {
                        g_MlValueLocksStatus = (anyLayerLocksEnabled ? "Disabled " : "Enabled ") + changed + " layer value lock(s).";
                    }
                }
                if (UI::MenuItem("Clear value locks (layer)")) {
                    int removed = _MlRemoveLayerValueLocks(g_MlActiveAppKind, layerIx);
                    g_MlValueLocksStatus = (removed > 0)
                        ? ("Removed " + removed + " layer value lock(s).")
                        : "No layer value locks to clear.";
                }
            }
            UI::EndPopup();
        }

        if (tag.Length > 0) {
            UI::SameLine();
            UI::Text("\\$fb0" + Icons::ExclamationTriangle + "\\$z");
            if (UI::IsItemHovered()) UI::SetTooltip(tag);
        }
        if (root !is null && selected) {
            string layerKey = _MlNoteLayerKey(layer, g_MlActiveAppKind);
            string rootAnchor = _MlNoteAnchorToken(root, -1);
            _MlRenderNoteIndicator(layerKey, rootAnchor, root, root);
        }

        UI::PopID();

        if (!hasChildren || !_IsMlTreeOpen(layerUiPath)) return;
        for (uint j = 0; j < rootFrame.Controls.Length; ++j) {
            if (g_MlRowsTruncated) break;
            auto ch = rootFrame.Controls[j];
            if (ch is null) continue;
            string childPath = "" + j;
            string childUi = layerUiPath + "/" + j;
            _RenderMlNodeTree(ch, childPath, childUi, 1, layerIx, filter, searchTerms);
        }
    }

    void _MlPrepareLayersTreeRender(string &out filter, array<_SearchTerm@> &out searchTerms) {
        filter = g_MlSearch.Trim();
        searchTerms = _SearchParseTerms(filter);
        string searchKey = filter + "|scope=" + (S_MlSearchGlobal ? "global" : "visible");
        if (!S_MlSearchGlobal) searchKey += "|open=" + g_MlTreeOpenEpoch;
        _MlSearchTick(searchKey);

        if (g_MlCollapseAll) {
            g_MlTreeOpen.DeleteAll();
            g_MlCollapseAll = false;
            g_MlTreeOpenEpoch++;
        }

        g_MlRowsRendered = 0;
        g_MlRowsTruncated = false;
    }

    int _RenderMlLayersTreeForApp(int appKind, const string &in filter, const array<_SearchTerm@> &in searchTerms) {
        uint layersLen = _GetMlLayerCount(appKind);
        if (layersLen == 0) return 0;
        string appPrefix = _MlAppPrefixByKind(appKind);

        uint startIx = 0;
        uint endIx = layersLen;
        if (g_MlViewLayerIndex >= 0 && g_MlViewLayerIndex < int(layersLen)) {
            startIx = uint(g_MlViewLayerIndex);
            endIx = startIx + 1;
        }

        int rowsBefore = g_MlRowsRendered;
        int prevActiveAppKind = g_MlActiveAppKind;
        g_MlActiveAppKind = appKind;
        for (uint i = startIx; i < endIx; ++i) {
            if (g_MlRowsTruncated) break;
            auto layer = _GetMlLayerByIx(appKind, int(i));
            if (layer is null) continue;
            string layerUiPath = appPrefix + "/L" + i;
            _RenderMlLayerTree(layer, int(i), layerUiPath, filter, searchTerms);
        }
        g_MlActiveAppKind = prevActiveAppKind;

        return g_MlRowsRendered - rowsBefore;
    }

    void _RenderMlLayersTree() {
        string filter;
        array<_SearchTerm@> searchTerms;
        _MlPrepareLayersTreeRender(filter, searchTerms);

        if (g_MlNodeFocusActive && g_MlNodeFocusAppKind == g_MlActiveAppKind) {
            CGameManialinkFrame@ focusRoot = null;
            CGameManialinkControl@ focusNode = null;
            bool ok = _ResolveMlNodeByPath(g_MlNodeFocusAppKind, g_MlNodeFocusLayerIx, g_MlNodeFocusPath, focusRoot, focusNode);
            if (!ok || focusNode is null) {
                UI::Text("\\$f80Focused node is no longer available. Clear node focus to continue.\\$z");
                return;
            }

            string focusUi = g_MlNodeFocusUiPath;
            if (focusUi.Length == 0) {
                focusUi = _MlAppPrefixByKind(g_MlNodeFocusAppKind) + "/L" + g_MlNodeFocusLayerIx;
                if (g_MlNodeFocusPath.Length > 0) focusUi += "/" + g_MlNodeFocusPath;
            }
            _SetMlTreeOpen(focusUi, true);
            _RenderMlNodeTree(focusNode, g_MlNodeFocusPath, focusUi, 0, g_MlNodeFocusLayerIx, filter, searchTerms);
            if (g_MlRowsRendered == 0) UI::Text("No matching controls.");
            else if (g_MlRowsTruncated) {
                UI::Text("\\$f80Tree rows truncated at budget " + S_DebugTreeRowBudget + ". Refine search or open fewer branches.\\$z");
            }
            UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
            return;
        }

        uint layersLen = _GetMlLayerCount(g_MlActiveAppKind);
        int added = _RenderMlLayersTreeForApp(g_MlActiveAppKind, filter, searchTerms);
        if (layersLen == 0) {
            UI::Text("No UILayers available.");
        } else if (added == 0) {
            UI::Text("No matching controls.");
        } else if (g_MlRowsTruncated) {
            UI::Text("\\$f80Tree rows truncated at budget " + S_DebugTreeRowBudget + ". Refine search or open fewer branches.\\$z");
        }

        UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
    }

}
}
