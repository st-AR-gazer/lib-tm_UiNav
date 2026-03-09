namespace UiNav {
namespace Debug {

    bool _MlImportLayerToBuilder(int appKind, int layerIx, string &out status) {
        status = "";
        if (layerIx < 0) {
            status = "Copy to Builder failed: invalid layer index.";
            return false;
        }

        auto layer = _GetMlLayerByIx(appKind, layerIx);
        if (layer is null) {
            status = "Copy to Builder failed: layer is no longer available.";
            return false;
        }

        bool ok = UiNav::Builder::ImportFromLiveLayerTree(appKind, layerIx);
        if (!ok) {
            ok = UiNav::Builder::ImportFromLiveLayer(appKind, layerIx);
        }
        if (!ok) {
            status = "Copy to Builder failed: " + UiNav::Builder::g_Status;
            return false;
        }

        UiNav::Builder::g_ImportAppKind = appKind;
        UiNav::Builder::g_ImportLayerIx = layerIx;
        status = "Copied layer L[" + layerIx + "] to Builder.";
        return true;
    }

    bool _MlImportLayerToBuilderWithOrigin(int appKind, int layerIx, string &out status) {
        status = "";
        bool ok = _MlImportLayerToBuilder(appKind, layerIx, status);
        if (!ok) return false;

        UiNav::Builder::AddDebugOriginMarker(true);
        status = "Copied layer L[" + layerIx + "] to Builder + ORIGIN marker.";
        return true;
    }

    bool _MlImportLayerToBuilderForceFitOnce(int appKind, int layerIx, string &out status) {
        status = "";
        UiNav::Builder::g_PreviewForceFitOnce = true;
        bool ok = _MlImportLayerToBuilder(appKind, layerIx, status);
        if (!ok) return false;

        UiNav::Builder::ApplyPreviewLayer();
        status = "Copied layer L[" + layerIx + "] to Builder (force-fit once).";
        return true;
    }

    bool _MlDeleteLayerBySelection(string &out status) {
        status = "";
        int appKind = g_SelectedMlAppKind;
        int layerIx = g_SelectedMlLayerIx;
        if (layerIx < 0) {
            status = "Delete failed: no selected layer.";
            return false;
        }

        auto layer = _GetMlLayerByIx(appKind, layerIx);
        if (layer is null) {
            status = "Delete failed: selected layer is no longer available.";
            return false;
        }

        string layerName = _CachedMlLayerName(layer, appKind, layerIx);
        bool removed = false;

        if (layerName.StartsWith("UiNav_")) {
            removed = UiNav::Layers::Destroy(layerName);
        }

        if (!removed) {
            if (appKind == 2) {
                auto editor = _GetMlEditorCommon();
                if (editor is null || editor.PluginMapType is null || editor.PluginMapType.UIManager is null) {
                    status = "Delete failed: editor UI manager unavailable.";
                    return false;
                }
                try {
                    editor.PluginMapType.UIManager.UILayerDestroy(layer);
                    removed = true;
                } catch {
                    removed = false;
                }
            } else {
                auto app = _GetMlManiaAppByKind(appKind);
                if (app is null) {
                    status = "Delete failed: ManiaApp source unavailable.";
                    return false;
                }
                try {
                    app.UILayerDestroy(layer);
                    removed = true;
                } catch {
                    removed = false;
                }
            }
        }

        if (!removed) {
            status = "Delete failed: could not destroy selected layer.";
            return false;
        }

        int removedLocks = _MlRemoveLayerValueLocks(appKind, layerIx);
        _MlRemoveLayerFavorite(appKind, layerIx);

        if (g_MlNodeFocusActive && g_MlNodeFocusAppKind == appKind && g_MlNodeFocusLayerIx == layerIx) {
            _ClearMlNodeFocus();
            g_MlNodeFocusStatus = "Cleared node focus (deleted focused layer).";
        }
        if (g_MlViewLayerIndex == layerIx) g_MlViewLayerIndex = -1;
        _ClearMlSelection();

        status = "Deleted layer L[" + layerIx + "]"
            + (layerName.Length > 0 ? (" " + layerName) : "")
            + (removedLocks > 0 ? (" and removed " + removedLocks + " layer lock(s).") : ".");
        return true;
    }

    void _RenderMlSelectionActions(MlSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        UI::TextDisabled("Live visibility toggles and value/visibility locks.");
        if (UI::Button("Show selected")) _SetMlVisibleSelf(ctx.sel, true);
        UI::SameLine();
        if (UI::Button("Hide selected")) _SetMlVisibleSelf(ctx.sel, false);
        bool layerSelected = g_SelectedMlLayerIx >= 0 && g_SelectedMlPath.Length == 0;
        if (layerSelected) {
            UI::SameLine();
            if (UI::Button("Delete this layer##ml-actions-delete-layer")) {
                string deleteStatus = "";
                _MlDeleteLayerBySelection(deleteStatus);
                g_MlValueLocksStatus = deleteStatus;
            }
            if (UI::IsItemHovered()) {
                UI::SetTooltip("Destroys the currently selected ManiaLink layer.");
            }

            UI::SameLine();
            if (UI::Button("Copy layer to Builder##ml-actions-copy-layer-builder")) {
                string builderStatus = "";
                _MlImportLayerToBuilder(g_SelectedMlAppKind, g_SelectedMlLayerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }
            if (UI::IsItemHovered()) {
                UI::SetTooltip("Imports the selected live layer into the ManiaLink Builder tab.");
            }

            if (UI::Button("Copy layer to Builder + ORIGIN marker##ml-actions-copy-layer-builder-origin")) {
                string builderStatus = "";
                _MlImportLayerToBuilderWithOrigin(g_SelectedMlAppKind, g_SelectedMlLayerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }
            if (UI::IsItemHovered()) {
                UI::SetTooltip("Imports to Builder and injects a known-visible ORIGIN marker into the Builder document.");
            }
            UI::SameLine();
            if (UI::Button("Copy layer to Builder (force-fit once)##ml-actions-copy-layer-builder-fit")) {
                string builderStatus = "";
                _MlImportLayerToBuilderForceFitOnce(g_SelectedMlAppKind, g_SelectedMlLayerIx, builderStatus);
                g_MlValueLocksStatus = builderStatus;
            }
            if (UI::IsItemHovered()) {
                UI::SetTooltip("Imports to Builder and force-fits the preview output into a safe on-screen region (preview-only).");
            }
        }
        if (UI::Button("Focus selected node")) {
            bool ok = _FocusSelectedMlNode();
            g_MlNodeFocusStatus = ok ? "Focused selected node." : "Could not focus selected node.";
        }
        UI::SameLine();
        if (UI::Button("Clear node focus##ml")) {
            _ClearMlNodeFocus();
            g_MlNodeFocusStatus = "Cleared node focus.";
        }
        if (g_MlNodeFocusStatus.Length > 0) UI::Text(g_MlNodeFocusStatus);

        UI::Separator();
        UI::Text("Live overlay");
        bool liveLayerBox = UiNav::Builder::S_LiveLayerBoundsOverlayEnabled;
        liveLayerBox = UI::Checkbox("Live layer box##ml-actions-live-layer-box", liveLayerBox);
        if (liveLayerBox != UiNav::Builder::S_LiveLayerBoundsOverlayEnabled) {
            UiNav::Builder::S_LiveLayerBoundsOverlayEnabled = liveLayerBox;
            if (liveLayerBox) UiNav::Builder::RefreshLiveLayerBoundsOverlay(true);
            else UiNav::Builder::DestroyLiveLayerBoundsOverlay();
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Draw bounds for the selected ML layer or subtree in the live UI.");
        }
        UI::SameLine();
        bool liveParentBox = UiNav::Builder::S_LiveLayerBoundsOverlayParentChainEnabled;
        liveParentBox = UI::Checkbox("Parent chain##ml-actions-live-layer-parent", liveParentBox);
        if (liveParentBox != UiNav::Builder::S_LiveLayerBoundsOverlayParentChainEnabled) {
            UiNav::Builder::S_LiveLayerBoundsOverlayParentChainEnabled = liveParentBox;
            if (UiNav::Builder::S_LiveLayerBoundsOverlayEnabled) UiNav::Builder::RefreshLiveLayerBoundsOverlay(true);
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Also draw bounds for each direct parent path of the selected ML node in the live UI.");
        }
        if (UiNav::Builder::S_LiveLayerBoundsOverlayEnabled) {
            UI::SameLine();
            if (UI::Button("Refresh##ml-actions-live-layer-box")) {
                UiNav::Builder::RefreshLiveLayerBoundsOverlay(true);
            }
        }

        UI::Separator();
        UI::Text("Lock selected value");
        _MlValueLocksEnsureLoaded();

        int lockKind = _MlValueLockKindForNode(ctx.sel);
        if (lockKind <= 0) {
            UI::TextDisabled("Selected node does not expose a lockable Value (Label/Entry).");
        } else {
            string currentVal = _MlValueLockReadNodeValue(ctx.sel, lockKind);
            string lockKey = g_SelectedMlAppKind + "|" + g_SelectedMlLayerIx + "|" + g_SelectedMlPath + "|" + lockKind;
            if (lockKey != g_MlValueLockDraftKey) {
                g_MlValueLockDraftKey = lockKey;
                int existingIx = _MlFindValueLockIx(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, lockKind);
                if (existingIx >= 0) {
                    auto existing = g_MlValueLocks[uint(existingIx)];
                    g_MlValueLockDraft = (existing is null) ? currentVal : existing.lockedValue;
                } else {
                    g_MlValueLockDraft = currentVal;
                }
            }

            UI::Text("Type: " + _MlValueLockKindName(lockKind));
            UI::Text("Current: " + currentVal);
            g_MlValueLockDraft = UI::InputText("Locked value", g_MlValueLockDraft);

            int existingIx = _MlFindValueLockIx(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, lockKind);
            bool hasExisting = existingIx >= 0;
            string lockBtn = hasExisting ? "Update lock" : "Lock value";
            if (UI::Button(lockBtn + "##ml-lock-selected")) {
                bool ok = _MlAddOrUpdateValueLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, ctx.sel, g_MlValueLockDraft);
                g_MlValueLocksStatus = ok ? (hasExisting ? "Updated value lock." : "Added value lock.") : "Could not lock selected value.";
            }
            UI::SameLine();
            if (UI::Button("Unlock selected##ml-lock-selected")) {
                bool removed = _MlRemoveValueLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, ctx.sel);
                g_MlValueLocksStatus = removed ? "Removed value lock." : "No value lock for selected node.";
                g_MlValueLockDraft = currentVal;
            }
        }

        UI::Separator();
        UI::Text("Lock selected visibility");
        bool currentVisible = ctx.sel.Visible;
        int visIx = _MlFindValueLockIx(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, 3);
        bool hasVisLock = visIx >= 0;
        bool visEnabled = false;
        bool lockedVisible = currentVisible;
        if (hasVisLock) {
            auto visLock = g_MlValueLocks[uint(visIx)];
            visEnabled = visLock !is null && visLock.enabled;
            if (visLock !is null) lockedVisible = _MlParseBoolLockValue(visLock.lockedValue, currentVisible);
        }
        UI::Text("Current: " + (currentVisible ? "visible" : "hidden"));
        if (hasVisLock) {
            UI::Text("Locked: " + (lockedVisible ? "visible" : "hidden") + " (" + (visEnabled ? "enabled" : "disabled") + ")");
            if (UI::Button("Set lock visible##ml-vis-lock")) {
                _MlAddOrUpdateVisibilityLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, true);
                g_MlValueLocksStatus = "Visibility lock set to visible.";
            }
            UI::SameLine();
            if (UI::Button("Set lock hidden##ml-vis-lock")) {
                _MlAddOrUpdateVisibilityLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, false);
                g_MlValueLocksStatus = "Visibility lock set to hidden.";
            }
            UI::SameLine();
            string toggleBtn = visEnabled ? "Disable lock##ml-vis-lock" : "Enable lock##ml-vis-lock";
            if (UI::Button(toggleBtn)) {
                _MlSetValueLockEnabled(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, 3, !visEnabled);
                g_MlValueLocksStatus = visEnabled ? "Disabled visibility lock." : "Enabled visibility lock.";
            }
            UI::SameLine();
            if (UI::Button("Unlock visibility##ml-vis-lock")) {
                _MlRemoveVisibilityLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath);
                g_MlValueLocksStatus = "Removed visibility lock.";
            }
        } else {
            if (UI::Button("Lock visible##ml-vis-lock")) {
                _MlAddOrUpdateVisibilityLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, true);
                g_MlValueLocksStatus = "Added visibility lock (visible).";
            }
            UI::SameLine();
            if (UI::Button("Lock hidden##ml-vis-lock")) {
                _MlAddOrUpdateVisibilityLock(g_SelectedMlAppKind, g_SelectedMlLayerIx, g_SelectedMlPath, false);
                g_MlValueLocksStatus = "Added visibility lock (hidden).";
            }
        }

        UI::Text("Active locks: " + g_MlValueLocks.Length);
        if (g_MlValueLocksStatus.Length > 0) UI::Text(g_MlValueLocksStatus);
        bool locksDirty = false;
        int removeLockIx = -1;
        float locksListH = 140.0f;
        if (UI::BeginChild("##ml-value-locks-list", vec2(0, locksListH), true)) {
            for (uint i = 0; i < g_MlValueLocks.Length; ++i) {
                auto lock = g_MlValueLocks[i];
                if (lock is null) continue;

                UI::PushID("ml-value-lock-" + i);
                bool enabled = lock.enabled;
                enabled = UI::Checkbox("##enabled", enabled);
                if (enabled != lock.enabled) {
                    lock.enabled = enabled;
                    locksDirty = true;
                }
                UI::SameLine();
                UI::Text(_MlValueLockDisplayLabel(lock));
                UI::SameLine();
                if (UI::Button("X")) removeLockIx = int(i);
                UI::PopID();
            }
        }
        UI::EndChild();
        if (locksDirty) _MlValueLocksSave();
        if (removeLockIx >= 0 && removeLockIx < int(g_MlValueLocks.Length)) {
            g_MlValueLocks.RemoveAt(uint(removeLockIx));
            _MlValueLocksSave();
            g_MlValueLocksStatus = "Removed value lock.";
        }
        if (g_MlValueLocks.Length > 0 && UI::Button("Clear all value locks")) {
            g_MlValueLocks.Resize(0);
            _MlValueLocksSave();
            g_MlValueLocksStatus = "Cleared all value locks.";
        }
    }

}
}
