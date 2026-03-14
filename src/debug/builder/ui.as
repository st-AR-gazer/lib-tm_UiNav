namespace UiNav {
namespace Builder {

    void _SetBuilderParentChainTooltip() {
        string tooltip = "Draw bounds for every direct parent of the selected Builder node in preview.";
        int boundsIx = g_BoundsTargetNodeIx >= 0 ? g_BoundsTargetNodeIx : g_SelectedNodeIx;
        if (boundsIx >= 0) {
            int parentCount = _CountBuilderParentChain(g_Doc, boundsIx);
            tooltip += "\nCurrent chain: " + parentCount + " parent(s).";
            string overlapWarning = _DescribeBuilderParentChainOverlapWarnings(g_Doc, boundsIx);
            if (overlapWarning.Length > 0) {
                tooltip += "\n\nWarning:\n" + overlapWarning;
            }
        }
        UI::SetTooltip(tooltip);
    }

    string _AppKindLabel(int appKind) {
        if (appKind == 0) return "Playground";
        if (appKind == 1) return "Menu";
        return "Current";
    }

    string _FidelityLabel(int level) {
        if (level <= 0) return "Full";
        if (level == 1) return "Partial";
        return "Raw";
    }

    string _NodeTitle(const BuilderNode@ n, int ix) {
        if (n is null) return "<null>";
        string kind = n.kind.Length > 0 ? n.kind : n.tagName;
        string idPart = n.controlId.Length > 0 ? ("#" + n.controlId) : ("#" + n.uid);
        return "[" + tostring(ix) + "] " + kind + " " + idPart;
    }

    int _GetNodeIxByUid(const string &in uid) {
        if (g_Doc is null || uid.Length == 0) return -1;
        int ix = -1;
        if (!g_Doc.nodeByUid.Get(uid, ix)) return -1;
        return ix;
    }

    void _Mutated(const string &in status) {
        _UpdateDirtyState();
        _QueueAutoPreview();
        g_Status = status;
    }

    void _RefreshPreviewForBoundsOverlayToggle() {
        if (S_AutoLivePreview) _QueueAutoPreview();
        else _ApplyPreviewLayerInternal(false);
    }

    void _RefreshPreviewForBoundsTargetChange() {
        if (!S_PreviewSelectedBoundsOverlayEnabled && !S_PreviewSelectedParentBoundsOverlayEnabled) return;
        _RefreshPreviewForBoundsOverlayToggle();
    }

    void _RenderSelectorCaptureOverlay() {
        if (!g_SelectorArmed || g_SelectorWaitMouseRelease) return;

        int flags = UI::WindowFlags::NoTitleBar
            | UI::WindowFlags::NoResize
            | UI::WindowFlags::NoMove
            | UI::WindowFlags::NoScrollbar
            | UI::WindowFlags::NoScrollWithMouse
            | UI::WindowFlags::NoCollapse
            | UI::WindowFlags::NoSavedSettings;

        UI::SetNextWindowPos(0, 0, UI::Cond::Always);
        UI::SetNextWindowSize(int(Display::GetWidth()), int(Display::GetHeight()), UI::Cond::Always);
        UI::PushStyleColor(UI::Col::WindowBg, vec4(0.0f, 0.0f, 0.0f, 0.0f));
        UI::PushStyleColor(UI::Col::Border, vec4(0.0f, 0.0f, 0.0f, 0.0f));
        bool open = UI::Begin("##builder-selector-capture-overlay", flags);
        if (open) {
            UI::SetCursorPos(vec2());
            UI::InvisibleButton("##builder-selector-capture-btn", vec2(float(Display::GetWidth()), float(Display::GetHeight())));
            if (UI::IsItemHovered()) {
                UI::SetMouseCursor(UI::MouseCursor::Hand);
                UI::SetTooltip("Left-click to pick this UI area.\nRight-click to cancel picker.");
            }
            if (UI::IsItemClicked(UI::MouseButton::Left)) {
                SelectorPickNow();
                if (!S_SelectorStayArmed) SelectorDisarmPicker(true);
            } else if (UI::IsItemClicked(UI::MouseButton::Right)) {
                SelectorDisarmPicker();
            }
        }
        UI::End();
        UI::PopStyleColor(2);
    }

    string _EditStringField(const string &in label, const string &in field, const string &in status) {
        string v = UI::InputText(label, field);
        if (v != field) {
            _PushUndoSnapshot();
            _Mutated(status);
        }
        return v;
    }

    string _EditTextArea(const string &in label, const string &in field, const vec2 &in size, const string &in status) {
        string v = UI::InputTextMultiline(label, field, size);
        if (v != field) {
            _PushUndoSnapshot();
            _Mutated(status);
        }
        return v;
    }

    int _RootNodeCount(const BuilderDocument@ doc) {
        if (doc is null) return 0;
        int c = 0;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n !is null && n.parentIx < 0) c++;
        }
        return c;
    }

    float _EditFloatAsText(const string &in label, float target, const string &in status) {
        string cur = tostring(target);
        string next = UI::InputText(label, cur);
        if (next == cur) return target;
        _PushUndoSnapshot();
        float outV = _ParseFloat(next, target);
        _Mutated(status);
        return outV;
    }

    int _EditIntAsText(const string &in label, int target, const string &in status) {
        string cur = tostring(target);
        string next = UI::InputText(label, cur);
        if (next == cur) return target;
        _PushUndoSnapshot();
        int outV = _ParseInt(next, target);
        _Mutated(status);
        return outV;
    }

    vec2 _EditVec2AsText(const string &in label, const vec2 &in target, const string &in status) {
        string cur = _Vec2ToAttr(target);
        string next = UI::InputText(label, cur);
        if (next == cur) return target;
        _PushUndoSnapshot();
        vec2 outV = _ParseVec2(next, target);
        _Mutated(status);
        return outV;
    }

    float _ScreenWidthSliderMax() {
        float w = float(Display::GetWidth());
        if (w < 100.0f) w = 100.0f;
        if (w > 100000.0f) w = 100000.0f;
        return w;
    }

    vec2 _BuilderScreenHalfExtents() {
        float w = float(Display::GetWidth());
        float h = float(Display::GetHeight());
        if (w < 1.0f) w = 1600.0f;
        if (h < 1.0f) h = 900.0f;

        float aspect = w / h;
        if (aspect < 0.5f) aspect = 0.5f;
        if (aspect > 4.0f) aspect = 4.0f;
        return vec2(90.0f * aspect, 90.0f);
    }

    float _EditFloatSlider(const string &in label, float target, float minV, float maxV, const string &in status, const string &in fmt = "%.3f") {
        float next = UI::SliderFloat(label, target, minV, maxV, fmt);
        if (next == target) return target;
        _PushUndoSnapshot();
        _Mutated(status);
        return next;
    }

    vec2 _EditVec2Slider(const string &in label, const vec2 &in target, float minV, float maxV, const string &in status, const string &in fmt = "%.3f") {
        vec2 next = UI::SliderFloat2(label, target, minV, maxV, fmt);
        if (next.x == target.x && next.y == target.y) return target;
        _PushUndoSnapshot();
        _Mutated(status);
        return next;
    }

    void _RefreshBuilderStickyGuidesPreview() {
        if (S_AutoLivePreview) _QueueAutoPreview();
        else _ApplyPreviewLayerInternal(false);
    }

    vec2 _EditNodePosSlider(const string &in label, int nodeIx, const vec2 &in target, const string &in status, const string &in fmt = "%.3f") {
        vec2 screenHalf = _BuilderScreenHalfExtents();
        vec2 minPos = vec2(-_ScreenWidthSliderMax(), -_ScreenWidthSliderMax());
        vec2 maxPos = vec2(_ScreenWidthSliderMax(), _ScreenWidthSliderMax());
        bool hasClamp = _ComputeBuilderNodeLocalPosClamp(g_Doc, nodeIx, screenHalf, minPos, maxPos, S_BuilderStickySnapOffscreenMargin);

        float sliderMin = Math::Min(Math::Min(minPos.x, minPos.y), Math::Min(target.x, target.y));
        float sliderMax = Math::Max(Math::Max(maxPos.x, maxPos.y), Math::Max(target.x, target.y));
        vec2 next = UI::SliderFloat2(label, target, sliderMin, sliderMax, fmt);
        bool itemActive = UI::IsItemActive();
        if (next.x == target.x && next.y == target.y) {
            if (!itemActive && g_BuilderStickyGuides.active) {
                _ClearBuilderStickyGuides();
                _RefreshBuilderStickyGuidesPreview();
            }
            if (UI::IsItemHovered() && hasClamp) {
                UI::SetTooltip("Slider keeps bounds near-screen with sticky guides.\nX: " + minPos.x + " .. " + maxPos.x
                    + "\nY: " + minPos.y + " .. " + maxPos.y);
            }
            return target;
        }

        array<float> verticalGuides;
        array<float> horizontalGuides;
        if (hasClamp) {
            next = ResolveBuilderNodeSliderPos(
                g_Doc,
                nodeIx,
                next,
                screenHalf,
                S_BuilderStickySnapOffscreenMargin,
                S_BuilderStickySnapEnabled,
                S_BuilderStickySnapToScreen,
                S_BuilderStickySnapToNodes,
                S_BuilderStickySnapThreshold,
                verticalGuides,
                horizontalGuides
            );
        }

        if (S_BuilderStickySnapGuidesEnabled && (verticalGuides.Length > 0 || horizontalGuides.Length > 0)) {
            _SetBuilderStickyGuides(screenHalf, S_BuilderStickySnapOffscreenMargin, verticalGuides, horizontalGuides);
        } else {
            _ClearBuilderStickyGuides();
        }
        _PushUndoSnapshot();
        _Mutated(status);
        return next;
    }

    float _ApproxTextCharWidth() {
        return Math::Max(5.0f, UI::GetTextLineHeight() * 0.52f);
    }

    float _AutoColWidthFromChars(uint charCount, float minW = 32.0f, float maxW = 420.0f) {
        float w = float(charCount + 2) * _ApproxTextCharWidth() + 10.0f;
        if (w < minW) w = minW;
        if (maxW > 0.0f && w > maxW) w = maxW;
        return w;
    }

    bool g_BuilderSplitterDragging = false;
    float g_BuilderSplitterLastX = 0.0f;
    dictionary g_BuilderTreeOpen;
    bool g_BuilderCollapseAll = false;
    string g_BuilderTreeSearch = "";
    int g_EditTickerOverlayLastAppKind = -999999;
    int g_EditTickerOverlayLastLayerIx = -999999;

    void _SetBuilderTreeOpen(const string &in uiPath, bool open) {
        if (uiPath.Length == 0) return;
        g_BuilderTreeOpen.Set(uiPath, open);
    }

    bool _IsBuilderTreeOpen(const string &in uiPath) {
        if (uiPath.Length == 0) return false;
        bool open = false;
        if (g_BuilderTreeOpen.Exists(uiPath))
            g_BuilderTreeOpen.Get(uiPath, open);
        return open;
    }

    string _BuilderNodeColorCode(const string &in kind) {
        if (kind == "frame") return "\\$9fd";
        if (kind == "label") return "\\$bff";
        if (kind == "quad") return "\\$fcb";
        if (kind == "entry" || kind == "textedit") return "\\$fd8";
        if (kind == "generic" || kind == "raw_xml") return "\\$ddd";
        return "\\$ddd";
    }

    string _BuilderFidelityBadge(int level) {
        if (level <= 0) return "";
        if (level == 1) return " \\$ff0[Partial]\\$z";
        return " \\$f80[Raw]\\$z";
    }

    string _BuilderNodeLabel(const BuilderNode@ n, int ix) {
        if (n is null) return "<null>";
        string kind = n.kind.Length > 0 ? n.kind : n.tagName;
        string color = _BuilderNodeColorCode(kind);
        string label = color + kind + "\\$z";
        if (n.controlId.Length > 0) {
            label += " \\$aaa#" + n.controlId + "\\$z";
        }
        label += _BuilderFidelityBadge(n.fidelity.level);
        return label;
    }

    bool _BuilderNodeMatchesFilter(const BuilderNode@ n, int ix, const string &in filterLower) {
        if (n is null) return false;
        if (n.kind.ToLower().Contains(filterLower)) return true;
        if (n.tagName.ToLower().Contains(filterLower)) return true;
        if (n.controlId.ToLower().Contains(filterLower)) return true;
        if (n.uid.ToLower().Contains(filterLower)) return true;
        if (n.typed !is null && n.typed.text.ToLower().Contains(filterLower)) return true;
        return false;
    }

    bool _BuilderSubtreeMatchesFilter(int nodeIx, const string &in filterLower) {
        if (g_Doc is null || nodeIx < 0 || nodeIx >= int(g_Doc.nodes.Length)) return false;
        auto n = g_Doc.nodes[uint(nodeIx)];
        if (n is null) return false;
        if (_BuilderNodeMatchesFilter(n, nodeIx, filterLower)) return true;
        for (uint i = 0; i < n.childIx.Length; ++i) {
            if (_BuilderSubtreeMatchesFilter(n.childIx[i], filterLower)) return true;
        }
        return false;
    }

    int _DrawBuilderSplitter(const string &in id, int treeWidth, float height) {
        const float w = 6.0f;
        UI::PushStyleColor(UI::Col::Button, vec4(0.25f, 0.25f, 0.28f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.35f, 0.35f, 0.40f, 1.0f));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.45f, 0.45f, 0.50f, 1.0f));
        UI::Button(id, vec2(w, height));
        if (UI::IsItemHovered() || UI::IsItemActive()) {
            UI::SetMouseCursor(UI::MouseCursor::ResizeEW);
        }
        if (UI::IsItemActive()) {
            vec2 mp = UI::GetMousePos();
            if (!g_BuilderSplitterDragging) {
                g_BuilderSplitterDragging = true;
                g_BuilderSplitterLastX = mp.x;
            } else {
                float dx = mp.x - g_BuilderSplitterLastX;
                treeWidth += int(dx);
                g_BuilderSplitterLastX = mp.x;
            }
            if (treeWidth < 220) treeWidth = 220;
            if (treeWidth > 1100) treeWidth = 1100;
        } else {
            g_BuilderSplitterDragging = false;
        }
        UI::PopStyleColor(3);
        return treeWidth;
    }

    void _DrawBuilderRowHighlight(bool selected, bool boundsTarget = false) {
        if (!selected && !boundsTarget) return;
        vec4 r = UI::GetItemRect();
        vec4 box = vec4(r.x - 2.0f, r.y - 1.0f, r.z + 2.0f, r.w + 1.0f);
        auto dl = UI::GetWindowDrawList();
        if (selected) {
            dl.AddRectFilled(box, vec4(0.28f, 0.62f, 1.0f, 0.11f));
            dl.AddRect(box, vec4(0.40f, 0.74f, 1.0f, 0.48f));
        }
        if (boundsTarget) {
            dl.AddRect(box, vec4(1.0f, 0.85f, 0.2f, 0.70f));
        }
    }

    bool _ActionButton(const string &in label, bool enabled, const string &in tooltip = "") {
        if (!enabled) UI::BeginDisabled();
        bool pressed = UI::Button(label);
        if (!enabled) UI::EndDisabled();
        if (tooltip.Length > 0 && UI::IsItemHovered()) UI::SetTooltip(tooltip);
        return enabled && pressed;
    }

    bool _ActionMenuItem(const string &in label, bool enabled) {
        if (!enabled) UI::BeginDisabled();
        bool pressed = UI::MenuItem(label);
        if (!enabled) UI::EndDisabled();
        return enabled && pressed;
    }

    void _RenderNodeStructureActionsMenu(const BuilderNode@ n, int nodeIx) {
        if (n is null) return;

        bool canMoveToRoot = n.parentIx >= 0;
        bool canMoveOut = n.parentIx >= 0;
        bool canMoveUp = _CanMoveNodeSiblingOrderDelta(nodeIx, -1);
        bool canMoveDown = _CanMoveNodeSiblingOrderDelta(nodeIx, 1);

        UI::TextDisabled("Actions");
        if (_ActionMenuItem(Icons::LevelUp + " Move to root", canMoveToRoot)) {
            MoveNodeToRootAction(nodeIx);
        }
        if (_ActionMenuItem("Move to parent level", canMoveOut)) {
            MoveNodeOutOneLevel(nodeIx);
        }
        if (_ActionMenuItem("Move up in siblings", canMoveUp)) {
            MoveNodeSiblingOrder(nodeIx, -1);
        }
        if (_ActionMenuItem("Move down in siblings", canMoveDown)) {
            MoveNodeSiblingOrder(nodeIx, 1);
        }
    }

    void _RenderInspectorActionsTab(BuilderNode@ n, int nodeIx) {
        if (n is null) return;

        int parentIx = -1;
        int siblingPos = -1;
        int siblingCount = 0;
        bool hasSiblingContext = _GetNodeSiblingContext(nodeIx, parentIx, siblingPos, siblingCount);

        bool canMoveToRoot = n.parentIx >= 0;
        bool canMoveOut = n.parentIx >= 0;
        bool canMoveUp = _CanMoveNodeSiblingOrderDelta(nodeIx, -1);
        bool canMoveDown = _CanMoveNodeSiblingOrderDelta(nodeIx, 1);

        UI::TextDisabled("Explicit structure actions for the selected node.");
        UI::Separator();

        if (hasSiblingContext) {
            UI::TextDisabled("Parent: " + (parentIx >= 0 ? ("[" + parentIx + "]") : "root"));
            UI::TextDisabled("Sibling position: " + (siblingPos + 1) + " / " + siblingCount);
            if (parentIx >= 0) {
                auto parent = g_Doc.nodes[uint(parentIx)];
                int grandParentIx = parent is null ? -1 : parent.parentIx;
                UI::TextDisabled("Parent level target: " + (grandParentIx >= 0 ? ("[" + grandParentIx + "]") : "root"));
            }
        } else {
            UI::TextDisabled("Sibling context unavailable.");
        }

        UI::Separator();
        if (_ActionButton(Icons::LevelUp + " Move to root##builder-actions-root", canMoveToRoot,
                "Reparent this node to the document root.")) {
            MoveNodeToRootAction(nodeIx);
        }
        if (_ActionButton("Move to parent level##builder-actions-parent", canMoveOut,
                "Reparent this node to its parent's parent.")) {
            MoveNodeOutOneLevel(nodeIx);
        }
        if (_ActionButton("Move up in siblings##builder-actions-up", canMoveUp,
                "Move this node one slot earlier in its current sibling order.")) {
            MoveNodeSiblingOrder(nodeIx, -1);
        }
        if (_ActionButton("Move down in siblings##builder-actions-down", canMoveDown,
                "Move this node one slot later in its current sibling order.")) {
            MoveNodeSiblingOrder(nodeIx, 1);
        }

        UI::Separator();
        if (_ActionButton(Icons::TrashO + " Delete node##builder-actions-delete", true,
                "Delete this node and its subtree.")) {
            DeleteNode(nodeIx);
        }
    }

    void _RenderToolbar() {
        _EnsureDoc();

        if (UI::Button(Icons::FileO + " New##builder-new")) {
            _ResetDocument(_NewDocument());
            g_BaselineXml = ExportToXml(g_Doc);
            g_Doc.dirty = false;
            g_LastExportXml = g_BaselineXml;
            g_Status = "Created new Builder document.";
        }

        UI::SameLine();
        if (UI::Button(Icons::FolderOpenO + "##builder-import-popup")) {
            UI::OpenPopup("##builder-import-menu");
        }
        if (UI::BeginPopup("##builder-import-menu")) {
            UI::TextDisabled("Import Source");
            UI::Separator();
            if (UI::MenuItem("From XML text")) {
                ImportFromXmlText(g_ImportXmlInput, "import_xml", "Builder tab text input");
            }
            if (UI::MenuItem("From live layer (" + _AppKindLabel(g_ImportAppKind) + " L" + g_ImportLayerIx + ")")) {
                ImportFromLiveLayer(g_ImportAppKind, g_ImportLayerIx);
            }
            if (UI::MenuItem("Clone live tree (" + _AppKindLabel(g_ImportAppKind) + " L" + g_ImportLayerIx + ")")) {
                ImportFromLiveLayerTree(g_ImportAppKind, g_ImportLayerIx);
            }
            UI::EndPopup();
        }

        UI::SameLine();
        if (UI::Button(Icons::FloppyO + "##builder-export-popup")) {
            UI::OpenPopup("##builder-export-menu");
        }
        if (UI::BeginPopup("##builder-export-menu")) {
            UI::TextDisabled("Export");
            UI::Separator();
            if (UI::MenuItem("Copy XML to clipboard")) ExportToClipboard();
            if (UI::MenuItem("Write to file")) ExportToFilePath(S_ExportPath);
            UI::EndPopup();
        }

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();

        bool canUndo = g_UndoSnapshots.Length > 0;
        if (!canUndo) UI::BeginDisabled();
        if (UI::Button(Icons::Undo + "##builder-undo")) {
            if (!Undo()) g_Status = "Undo stack is empty.";
        }
        if (!canUndo) UI::EndDisabled();

        UI::SameLine();
        bool canRedo = g_RedoSnapshots.Length > 0;
        if (!canRedo) UI::BeginDisabled();
        if (UI::Button(Icons::Repeat + "##builder-redo")) {
            if (!Redo()) g_Status = "Redo stack is empty.";
        }
        if (!canRedo) UI::EndDisabled();

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();

        if (UI::Button(Icons::Play + " Preview##builder-preview-apply")) {
            ApplyPreviewLayer();
        }

        UI::SameLine();
        if (UI::Button(Icons::Stop + "##builder-preview-destroy")) {
            DestroyPreviewLayer();
        }

        UI::SameLine();
        if (S_AutoLivePreview) {
            UI::Text("\\$9fdAuto\\$z");
        }

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();

        if (UI::Button(Icons::Exchange + "##builder-diff")) {
            DiffAgainstOriginal();
        }

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        string dirtyMarker = g_Doc.dirty ? "\\$f80*\\$z " : "";
        UI::TextDisabled(dirtyMarker + g_Doc.name);
        if (g_Status.Length > 0) {
            UI::SameLine();
            UI::TextDisabled("- " + g_Status);
        }

        if (S_AutoLivePreview && g_AutoPreviewPending) {
            UI::SameLine();
            UI::TextDisabled("\\$ff0[preview pending]\\$z");
        }
    }

    void _RenderTreeRowRecursive(int nodeIx, int depth, const string &in uiPath) {
        if (g_Doc is null) return;
        if (nodeIx < 0 || nodeIx >= int(g_Doc.nodes.Length)) return;
        auto n = g_Doc.nodes[uint(nodeIx)];
        if (n is null) return;

        bool hasChildren = n.childIx.Length > 0;
        bool selected = g_SelectedNodeIx == nodeIx;

        UI::PushID("builder-tree-row-" + uiPath);

        bool visible = n.typed !is null ? n.typed.visible : true;
        bool prevVisible = visible;
        visible = UI::Checkbox("##builder-vis-" + uiPath, visible);
        if (visible != prevVisible && n.typed !is null) {
            _PushUndoSnapshot();
            n.typed.visible = visible;
            _Mutated("Toggled visibility.");
        }
        UI::SameLine();

        float indent = float(depth) * 12.0f;
        if (indent > 0.0f) {
            UI::Dummy(vec2(indent, 0.0f));
            UI::SameLine();
        }

        bool open = hasChildren && _IsBuilderTreeOpen(uiPath);
        if (hasChildren) {
            UI::PushFontSize(12.0f);
            UI::Text(open ? Icons::ChevronDown : Icons::ChevronRight);
            bool togHovered = UI::IsItemHovered();
            bool togPressed = togHovered && UI::IsMouseClicked(UI::MouseButton::Left);
            UI::PopFontSize();
            if (togHovered) {
                UI::SetMouseCursor(UI::MouseCursor::Hand);
            }
            if (togPressed) _SetBuilderTreeOpen(uiPath, !open);
        } else {
            UI::Dummy(vec2(10.0f, 12.0f));
        }
        UI::SameLine();

        string rowLabel = _BuilderNodeLabel(n, nodeIx);
        UI::Selectable(rowLabel + "##builder-tree-label-" + uiPath, false);

        bool isBoundsTarget = g_BoundsTargetNodeIx == nodeIx;
        _DrawBuilderRowHighlight(selected, isBoundsTarget);

        bool rowHovered = UI::IsItemHovered();
        if (rowHovered) {
            if (UI::IsMouseClicked(UI::MouseButton::Left)) {
                if (hasChildren) {
                    _SetBuilderTreeOpen(uiPath, !open);
                }
            }
            if (UI::IsMouseClicked(UI::MouseButton::Right)) {
                g_SelectedNodeIx = nodeIx;
                _RefreshPreviewForBoundsTargetChange();
                if (g_BuilderStickyGuides.active) {
                    _ClearBuilderStickyGuides();
                    _RefreshBuilderStickyGuidesPreview();
                }
            }
            if (UI::IsMouseClicked(UI::MouseButton::Middle)) {
                UI::OpenPopup("##builder-node-popup-" + uiPath);
            }
        }

        if (UI::BeginPopup("##builder-node-popup-" + uiPath)) {
            UI::Text(_BuilderNodeLabel(n, nodeIx));
            UI::Separator();

            if (hasChildren) {
                if (UI::MenuItem(Icons::ChevronDown + " Expand subtree")) _SetBuilderTreeOpen(uiPath, true);
                if (UI::MenuItem(Icons::ChevronRight + " Collapse subtree")) _SetBuilderTreeOpen(uiPath, false);
                UI::Separator();
            }

            bool isPinnedBoundsTarget = (g_BoundsTargetNodeIx == nodeIx);
            if (!isPinnedBoundsTarget) {
                if (UI::MenuItem(Icons::ThumbTack + " Pin bounds target")) {
                    g_BoundsTargetNodeIx = nodeIx;
                    _RefreshPreviewForBoundsTargetChange();
                }
            } else {
                if (UI::MenuItem(Icons::ThumbTack + " Unpin bounds target")) {
                    g_BoundsTargetNodeIx = -1;
                    _RefreshPreviewForBoundsTargetChange();
                }
            }
            UI::Separator();

            UI::TextDisabled("Add child...");
            if (UI::MenuItem("\\$9fd" + Icons::PlusSquareO + " Frame\\$z")) AddNode("frame", nodeIx);
            if (UI::MenuItem("\\$fcb" + Icons::PlusSquareO + " Quad\\$z")) AddNode("quad", nodeIx);
            if (UI::MenuItem("\\$bff" + Icons::PlusSquareO + " Label\\$z")) AddNode("label", nodeIx);
            if (UI::MenuItem("\\$fd8" + Icons::PlusSquareO + " Entry\\$z")) AddNode("entry", nodeIx);
            if (UI::MenuItem("\\$fd8" + Icons::PlusSquareO + " TextEdit\\$z")) AddNode("textedit", nodeIx);
            if (UI::MenuItem("\\$ddd" + Icons::PlusSquareO + " Generic\\$z")) AddNode("generic", nodeIx);
            UI::Separator();

            _RenderNodeStructureActionsMenu(n, nodeIx);
            UI::Separator();

            if (UI::MenuItem(Icons::TrashO + " Delete node")) DeleteNode(nodeIx);

            UI::EndPopup();
        }

        UI::PopID();

        if (!hasChildren || !open) return;
        for (uint i = 0; i < n.childIx.Length; ++i) {
            _RenderTreeRowRecursive(n.childIx[i], depth + 1, uiPath + "/" + i);
        }
    }

    void _RenderTreePane() {
        _EnsureDoc();

        UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 70.0f);
        g_BuilderTreeSearch = UI::InputText("##builder-tree-search", g_BuilderTreeSearch);
        UI::SameLine();
        if (UI::Button("Clear##builder-search")) g_BuilderTreeSearch = "";

        UI::Text("Tree");
        UI::SameLine();
        if (UI::Button(Icons::Compress + "##builder-collapse-all")) g_BuilderCollapseAll = true;
        UI::SameLine();
        UI::TextDisabled(tostring(_RootNodeCount(g_Doc)) + "R " + tostring(g_Doc.nodes.Length) + "N");

        UI::SameLine();
        if (UI::Button(Icons::Plus + "##builder-add-node")) {
            UI::OpenPopup("##builder-add-node-popup");
        }
        if (UI::BeginPopup("##builder-add-node-popup")) {
            int parentIx = g_SelectedNodeIx;
            string parentLabel = parentIx >= 0 ? ("child of [" + parentIx + "]") : "root";
            UI::TextDisabled("Add as " + parentLabel);
            UI::Separator();
            if (UI::MenuItem("\\$9fd" + Icons::PlusSquareO + " Frame\\$z")) AddNode("frame", parentIx);
            if (UI::MenuItem("\\$fcb" + Icons::PlusSquareO + " Quad\\$z")) AddNode("quad", parentIx);
            if (UI::MenuItem("\\$bff" + Icons::PlusSquareO + " Label\\$z")) AddNode("label", parentIx);
            if (UI::MenuItem("\\$fd8" + Icons::PlusSquareO + " Entry\\$z")) AddNode("entry", parentIx);
            if (UI::MenuItem("\\$fd8" + Icons::PlusSquareO + " TextEdit\\$z")) AddNode("textedit", parentIx);
            if (UI::MenuItem("\\$ddd" + Icons::PlusSquareO + " Generic\\$z")) AddNode("generic", parentIx);
            UI::EndPopup();
        }

        UI::SameLine();
        bool canDelete = g_SelectedNodeIx >= 0 && g_SelectedNodeIx < int(g_Doc.nodes.Length);
        if (!canDelete) UI::BeginDisabled();
        if (UI::Button(Icons::TrashO + "##builder-delete-selected")) {
            if (g_SelectedNodeIx >= 0) DeleteNode(g_SelectedNodeIx);
        }
        if (!canDelete) UI::EndDisabled();

        if (g_BuilderCollapseAll) {
            g_BuilderTreeOpen.DeleteAll();
            g_BuilderCollapseAll = false;
        }

        UI::Separator();

        if (UI::BeginChild("##builder-tree-list", vec2(0, 0), false)) {
            string filterLower = g_BuilderTreeSearch.Trim().ToLower();
            for (uint i = 0; i < g_Doc.nodes.Length; ++i) {
                auto n = g_Doc.nodes[i];
                if (n is null || n.parentIx >= 0) continue;

                if (filterLower.Length > 0) {
                    if (!_BuilderSubtreeMatchesFilter(int(i), filterLower)) continue;
                }

                _RenderTreeRowRecursive(int(i), 0, "R" + i);
            }

            UI::Dummy(vec2(0, UI::GetFrameHeightWithSpacing()));
        }
        UI::EndChild();
    }

    void _RenderInspectorPropertiesTab(BuilderNode@ n, int nodeIx) {
        if (n is null) return;

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Identity##builder-insp")) {
            n.tagName = _EditStringField("Tag name##builder-insp", n.tagName, "Updated tag name.");
            n.controlId = _EditStringField("Control id##builder-insp", n.controlId, "Updated control id.");

            string classText = _Join(n.classes, " ");
            string nextClasses = UI::InputText("Classes##builder-insp", classText);
            if (nextClasses != classText) {
                _PushUndoSnapshot();
                n.classes = _SplitSpaces(nextClasses);
                _Mutated("Updated classes.");
            }

            bool scriptEvents = n.scriptEvents;
            scriptEvents = UI::Checkbox("Script events##builder-insp", scriptEvents);
            if (scriptEvents != n.scriptEvents) {
                _PushUndoSnapshot();
                n.scriptEvents = scriptEvents;
                _Mutated("Updated script events.");
            }

            string eventId = "";
            n.rawAttrs.Get("scripteventid", eventId);
            string nextEventId = UI::InputText("Script event id##builder-insp", eventId);
            if (nextEventId != eventId) {
                _PushUndoSnapshot();
                if (nextEventId.Length == 0) n.rawAttrs.Delete("scripteventid");
                else n.rawAttrs.Set("scripteventid", nextEventId);
                _Mutated("Updated script event id.");
            }

            int newParentIx = UI::InputInt("Parent index (-1 = root)##builder-insp", n.parentIx);
            if (newParentIx != n.parentIx) {
                if (!MoveNode(g_SelectedNodeIx, newParentIx)) {
                    g_Status = "Move failed (invalid parent or cycle).";
                }
            }
        }

        if (n.typed is null) return;

        UI::SetNextItemOpen(true, UI::Cond::Appearing);
        if (UI::CollapsingHeader("Transform##builder-insp")) {
            float sw = _ScreenWidthSliderMax();
            n.typed.pos = _EditNodePosSlider("pos##builder-insp", nodeIx, n.typed.pos, "Updated pos.");
            n.typed.size = _EditVec2Slider("size##builder-insp", n.typed.size, 0.0f, sw, "Updated size.");
            n.typed.z = _EditFloatAsText("z##builder-insp", n.typed.z, "Updated z.");
            n.typed.scale = _EditFloatAsText("scale##builder-insp", n.typed.scale, "Updated scale.");
            n.typed.rot = _EditFloatSlider("rot##builder-insp", n.typed.rot, -sw, sw, "Updated rot.");

            bool vis = n.typed.visible;
            vis = UI::Checkbox("visible##builder-insp", vis);
            if (vis != n.typed.visible) {
                _PushUndoSnapshot();
                n.typed.visible = vis;
                _Mutated("Updated visible.");
            }

            n.typed.hAlign = _EditStringField("halign##builder-insp", n.typed.hAlign, "Updated halign.");
            n.typed.vAlign = _EditStringField("valign##builder-insp", n.typed.vAlign, "Updated valign.");
        }

        if (n.kind == "frame") {
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader("\\$9fdFrame\\$z##builder-insp-frame")) {
                bool clip = n.typed.clipActive;
                clip = UI::Checkbox("clip active##builder-insp-frame", clip);
                if (clip != n.typed.clipActive) {
                    _PushUndoSnapshot();
                    n.typed.clipActive = clip;
                    _Mutated("Updated clip active.");
                }
                vec2 prevClipPos = n.typed.clipPos;
                n.typed.clipPos = _EditVec2AsText("clip pos##builder-insp-frame", n.typed.clipPos, "Updated clip pos.");
                if (n.typed.clipPos.x != prevClipPos.x || n.typed.clipPos.y != prevClipPos.y) {
                    n.typed.clipPosExplicit = true;
                }
                vec2 prevClipSize = n.typed.clipSize;
                n.typed.clipSize = _EditVec2AsText("clip size##builder-insp-frame", n.typed.clipSize, "Updated clip size.");
                if (n.typed.clipSize.x != prevClipSize.x || n.typed.clipSize.y != prevClipSize.y) {
                    n.typed.clipSizeExplicit = true;
                }
            }
        } else if (n.kind == "quad") {
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader("\\$fcbQuad\\$z##builder-insp-quad")) {
                n.typed.image = _EditStringField("image##builder-insp-quad", n.typed.image, "Updated image.");
                n.typed.imageFocus = _EditStringField("imagefocus##builder-insp-quad", n.typed.imageFocus, "Updated image focus.");
                n.typed.alphaMask = _EditStringField("alphamask##builder-insp-quad", n.typed.alphaMask, "Updated alpha mask.");
                n.typed.style = _EditStringField("style##builder-insp-quad", n.typed.style, "Updated style.");
                n.typed.subStyle = _EditStringField("substyle##builder-insp-quad", n.typed.subStyle, "Updated substyle.");
                n.typed.bgColor = _EditStringField("bgcolor##builder-insp-quad", n.typed.bgColor, "Updated background color.");
                n.typed.bgColorFocus = _EditStringField("bgcolorfocus##builder-insp-quad", n.typed.bgColorFocus, "Updated focus background color.");
                n.typed.modulateColor = _EditStringField("modulatecolor##builder-insp-quad", n.typed.modulateColor, "Updated modulate color.");
                n.typed.colorize = _EditStringField("colorize##builder-insp-quad", n.typed.colorize, "Updated colorize.");
                n.typed.opacity = _EditFloatAsText("opacity##builder-insp-quad", n.typed.opacity, "Updated opacity.");
                n.typed.keepRatioMode = _EditIntAsText("keep ratio mode##builder-insp-quad", n.typed.keepRatioMode, "Updated keep ratio mode.");
                n.typed.blendMode = _EditIntAsText("blend mode##builder-insp-quad", n.typed.blendMode, "Updated blend mode.");
            }
        } else if (n.kind == "label") {
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader("\\$bffLabel\\$z##builder-insp-label")) {
                n.typed.text = _EditStringField("text##builder-insp-label", n.typed.text, "Updated text.");
                n.typed.textSize = _EditFloatAsText("text size##builder-insp-label", n.typed.textSize, "Updated text size.");
                n.typed.textFont = _EditStringField("text font##builder-insp-label", n.typed.textFont, "Updated text font.");
                n.typed.textPrefix = _EditStringField("text prefix##builder-insp-label", n.typed.textPrefix, "Updated text prefix.");
                n.typed.textColor = _EditStringField("text color##builder-insp-label", n.typed.textColor, "Updated text color.");
                n.typed.opacity = _EditFloatAsText("opacity##builder-insp-label", n.typed.opacity, "Updated opacity.");
                n.typed.maxLine = _EditIntAsText("max line##builder-insp-label", n.typed.maxLine, "Updated max line.");

                bool autoNewLine = n.typed.autoNewLine;
                autoNewLine = UI::Checkbox("auto newline##builder-insp-label", autoNewLine);
                if (autoNewLine != n.typed.autoNewLine) {
                    _PushUndoSnapshot();
                    n.typed.autoNewLine = autoNewLine;
                    _Mutated("Updated auto newline.");
                }
                n.typed.lineSpacing = _EditFloatAsText("line spacing##builder-insp-label", n.typed.lineSpacing, "Updated line spacing.");
                n.typed.italicSlope = _EditFloatAsText("italic slope##builder-insp-label", n.typed.italicSlope, "Updated italic slope.");

                bool appendEllipsis = n.typed.appendEllipsis;
                appendEllipsis = UI::Checkbox("append ellipsis##builder-insp-label", appendEllipsis);
                if (appendEllipsis != n.typed.appendEllipsis) {
                    _PushUndoSnapshot();
                    n.typed.appendEllipsis = appendEllipsis;
                    _Mutated("Updated append ellipsis.");
                }

                n.typed.style = _EditStringField("style##builder-insp-label", n.typed.style, "Updated style.");
                n.typed.subStyle = _EditStringField("substyle##builder-insp-label", n.typed.subStyle, "Updated substyle.");
            }
        } else if (n.kind == "entry" || n.kind == "textedit") {
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader("\\$fd8Entry/TextEdit\\$z##builder-insp-entry")) {
                n.typed.value = _EditStringField("value/default##builder-insp-entry", n.typed.value, "Updated value.");
                n.typed.textFormat = _EditIntAsText("text format##builder-insp-entry", n.typed.textFormat, "Updated text format.");
                n.typed.textSize = _EditFloatAsText("text size##builder-insp-entry", n.typed.textSize, "Updated text size.");
                n.typed.textColor = _EditStringField("text color##builder-insp-entry", n.typed.textColor, "Updated text color.");
                n.typed.opacity = _EditFloatAsText("opacity##builder-insp-entry", n.typed.opacity, "Updated opacity.");
                n.typed.maxLength = _EditIntAsText("max length##builder-insp-entry", n.typed.maxLength, "Updated max length.");
                n.typed.maxLine = _EditIntAsText("max line##builder-insp-entry", n.typed.maxLine, "Updated max line.");

                bool autoNewLine = n.typed.autoNewLine;
                autoNewLine = UI::Checkbox("auto newline##builder-insp-entry", autoNewLine);
                if (autoNewLine != n.typed.autoNewLine) {
                    _PushUndoSnapshot();
                    n.typed.autoNewLine = autoNewLine;
                    _Mutated("Updated auto newline.");
                }
                n.typed.lineSpacing = _EditFloatAsText("line spacing##builder-insp-entry", n.typed.lineSpacing, "Updated line spacing.");
            }
        }
    }

    void _RenderInspectorRawAttrsTab(BuilderNode@ n) {
        if (n is null) return;

        UI::Text("Raw Attributes");
        UI::TextDisabled("Attributes not mapped to typed properties. Preserved on export.");
        UI::Separator();

        array<string> keys = n.rawAttrs.GetKeys();
        keys.SortAsc();
        bool deleted = false;
        for (uint i = 0; i < keys.Length; ++i) {
            string k = keys[i];
            string oldV = "";
            n.rawAttrs.Get(k, oldV);

            UI::PushID("builder-raw-" + k + "-" + tostring(i));
            UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 80.0f);
            string newV = UI::InputText(k, oldV);
            if (newV != oldV) {
                _PushUndoSnapshot();
                n.rawAttrs.Set(k, newV);
                _Mutated("Updated raw attr: " + k);
            }
            UI::SameLine();
            if (UI::Button(Icons::TrashO + "##raw-remove")) {
                _PushUndoSnapshot();
                n.rawAttrs.Delete(k);
                _Mutated("Removed raw attr: " + k);
                deleted = true;
            }
            UI::PopID();
            if (deleted) break;
        }

        UI::Separator();
        UI::TextDisabled("Add new attribute:");
        g_RawAttrDraftKey = UI::InputText("Key##builder-raw-new", g_RawAttrDraftKey);
        g_RawAttrDraftValue = UI::InputText("Value##builder-raw-new", g_RawAttrDraftValue);
        if (UI::Button(Icons::Plus + " Add##builder-raw-add")) {
            string k = g_RawAttrDraftKey.Trim();
            if (k.Length == 0) {
                g_Status = "Raw attr key cannot be empty.";
            } else {
                _PushUndoSnapshot();
                n.rawAttrs.Set(k, g_RawAttrDraftValue);
                _Mutated("Added raw attr: " + k);
                g_RawAttrDraftKey = "";
                g_RawAttrDraftValue = "";
            }
        }
    }

    void _RenderInspectorComputedTab(BuilderNode@ n, int nodeIx) {
        if (UI::Button(Icons::Clipboard + " Copy Bounds Data##builder-insp-computed-copy")) {
            string payload = _BuildBuilderComputedMetricsText(n, nodeIx);
            if (payload.Length > 0) {
                IO::SetClipboard(payload);
                g_Status = "Copied computed bounds data.";
            }
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Copy the computed geometry/bounds data for this builder node.");

        UI::TextDisabled("Computed absolute metrics (read-only).");
        UI::Separator();

        auto abs = ComputeAbsMetrics(g_Doc, nodeIx);
        if (abs is null || !abs.ok) {
            UI::TextDisabled("Absolute transform unavailable (missing typed props in ancestry).");
            return;
        }
        UI::TextDisabled("Abs pos: " + _FmtVec2(abs.absPos));
        UI::TextDisabled("Abs scale: " + tostring(abs.absScale));
        UI::TextDisabled("Abs size: " + _FmtVec2(abs.absSize));
        UI::Separator();
        UI::TextDisabled("Bounds min: " + _FmtVec2(abs.boundsMin));
        UI::TextDisabled("Bounds max: " + _FmtVec2(abs.boundsMax));
        vec2 sz = abs.boundsMax - abs.boundsMin;
        vec2 center = (abs.boundsMin + abs.boundsMax) * 0.5f;
        UI::TextDisabled("Bounds size: " + _FmtVec2(sz));
        UI::TextDisabled("Bounds center: " + _FmtVec2(center));
        UI::Separator();
        UI::TextDisabled("Anchor: (" + abs.anchorX + ", " + abs.anchorY + ") from halign=" + n.typed.hAlign + " valign=" + n.typed.vAlign);
        if (abs.selfHidden || abs.hiddenByAncestor) {
            UI::TextDisabled("Visibility: " + (abs.selfHidden ? "self hidden" : "self visible")
                + " | " + (abs.hiddenByAncestor ? "ancestor hidden" : "ancestors visible"));
        }
        if (abs.underClipAncestor) {
            UI::TextDisabled("Under clip ancestors: " + abs.clipAncestorCount);
        }
    }

    string _BuildBuilderComputedMetricsText(const BuilderNode@ n, int nodeIx) {
        if (n is null) return "";

        array<string> lines;
        string kind = n.kind.Length > 0 ? n.kind : n.tagName;
        string title = kind;
        if (n.controlId.Length > 0) title += " #" + n.controlId;
        lines.InsertLast(title);

        auto abs = ComputeAbsMetrics(g_Doc, nodeIx);
        if (abs is null || !abs.ok) {
            lines.InsertLast("Absolute transform unavailable (missing typed props in ancestry).");
        } else {
            lines.InsertLast("Abs pos: " + _FmtVec2(abs.absPos));
            lines.InsertLast("Abs scale: " + abs.absScale);
            lines.InsertLast("Abs size: " + _FmtVec2(abs.absSize));
            lines.InsertLast("Bounds min: " + _FmtVec2(abs.boundsMin));
            lines.InsertLast("Bounds max: " + _FmtVec2(abs.boundsMax));
            vec2 sz = abs.boundsMax - abs.boundsMin;
            vec2 center = (abs.boundsMin + abs.boundsMax) * 0.5f;
            lines.InsertLast("Bounds size: " + _FmtVec2(sz));
            lines.InsertLast("Bounds center: " + _FmtVec2(center));
            lines.InsertLast("Anchor: (" + abs.anchorX + ", " + abs.anchorY + ") from halign=" + n.typed.hAlign + " valign=" + n.typed.vAlign);
            lines.InsertLast("Visibility: " + (abs.selfHidden ? "self hidden" : "self visible")
                + " | " + (abs.hiddenByAncestor ? "ancestor hidden" : "ancestors visible"));
            if (abs.underClipAncestor) lines.InsertLast("Under clip ancestors: " + abs.clipAncestorCount);
        }

        string outText = "";
        for (uint i = 0; i < lines.Length; ++i) outText += (i == 0 ? "" : "\n") + lines[i];
        return outText;
    }

    void _RenderBuilderSelectionSummaryContents(BuilderNode@ n, int nodeIx, const string &in idPrefix = "builder-summary") {
        if (n is null) return;

        string kind = n.kind.Length > 0 ? n.kind : n.tagName;
        string summaryTitle = _BuilderNodeColorCode(kind) + kind + "\\$z";
        if (n.controlId.Length > 0) summaryTitle += " \\$aaa#" + n.controlId + "\\$z";
        UI::Text(summaryTitle);
        UI::TextDisabled("[" + nodeIx + "] parent:" + (n.parentIx >= 0 ? tostring(n.parentIx) : "root")
            + " children:" + n.childIx.Length + " fidelity:" + _FidelityLabel(n.fidelity.level));
        UI::TextDisabled("Tag: " + n.tagName + " | Source: " + g_Doc.sourceKind
            + (g_Doc.sourceLabel.Length > 0 ? (" (" + g_Doc.sourceLabel + ")") : ""));
    }

    void _RenderInspectorPane() {
        _EnsureDoc();

        auto n = _GetSelectedNode();
        if (n is null) {
            UI::TextDisabled("No node selected.");
            UI::TextDisabled("Left-click container rows to open or close them.");
            UI::TextDisabled("Right-click a node to select it for Properties and Actions.");
            UI::TextDisabled("Middle-click opens the node context menu.");
            return;
        }

        _RenderBuilderSelectionSummaryContents(n, g_SelectedNodeIx, "builder-header-summary");
        UI::Separator();

        UI::BeginTabBar("##builder-inspector-tabs");

        if (UI::BeginTabItem("Properties##builder-insp")) {
            if (UI::BeginChild("##builder-insp-props-scroll", vec2(0, 0), false)) {
                UI::SetNextItemOpen(true, UI::Cond::Appearing);
                if (UI::CollapsingHeader("Node Summary##builder-insp-summary")) {
                    _RenderBuilderSelectionSummaryContents(n, g_SelectedNodeIx, "builder-tab-summary");
                    UI::Separator();
                }
                _RenderInspectorPropertiesTab(n, g_SelectedNodeIx);
            }
            UI::EndChild();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem("Actions##builder-insp")) {
            if (UI::BeginChild("##builder-insp-actions-scroll", vec2(0, 0), false)) {
                _RenderInspectorActionsTab(n, g_SelectedNodeIx);
            }
            UI::EndChild();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem("Raw Attrs##builder-insp")) {
            if (UI::BeginChild("##builder-insp-raw-scroll", vec2(0, 0), false)) {
                _RenderInspectorRawAttrsTab(n);
            }
            UI::EndChild();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem("Computed##builder-insp")) {
            if (UI::BeginChild("##builder-insp-comp-scroll", vec2(0, 0), false)) {
                _RenderInspectorComputedTab(n, g_SelectedNodeIx);
            }
            UI::EndChild();
            UI::EndTabItem();
        }

        UI::EndTabBar();
    }

    void _RenderEditView() {
        vec2 avail = UI::GetContentRegionAvail();
        float availX = avail.x;

        float treeW = float(S_TreeWidth);
        if (treeW < 220.0f) treeW = 220.0f;
        if (treeW > availX - 300.0f) treeW = Math::Max(220.0f, availX * 0.35f);
        S_TreeWidth = int(treeW);

        float tickerH = UI::GetTextLineHeightWithSpacing() + 4.0f;
        float paneHeight = UI::GetContentRegionAvail().y - tickerH - 4.0f;
        if (paneHeight < 1.0f) paneHeight = 1.0f;

        UI::BeginGroup();
        bool openTree = UI::BeginChild("##builder-pane-tree", vec2(treeW, paneHeight), true);
        if (openTree) _RenderTreePane();
        UI::EndChild();
        UI::EndGroup();

        UI::SameLine();
        S_TreeWidth = _DrawBuilderSplitter("##builder-splitter", S_TreeWidth, paneHeight);
        UI::SameLine();

        UI::BeginGroup();
        bool openInspector = UI::BeginChild("##builder-pane-inspector", vec2(0, paneHeight), true);
        if (openInspector) _RenderInspectorPane();
        UI::EndChild();
        UI::EndGroup();

        _RenderEditTickerBar();
    }

    void _RenderEditTickerBar() {
        _EnsureDoc();

        bool builderSelOverlay = S_PreviewSelectedBoundsOverlayEnabled;
        builderSelOverlay = UI::Checkbox("Builder selection box##builder-edit-selected-overlay", builderSelOverlay);
        if (builderSelOverlay != S_PreviewSelectedBoundsOverlayEnabled) {
            S_PreviewSelectedBoundsOverlayEnabled = builderSelOverlay;
            _RefreshPreviewForBoundsOverlayToggle();
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Draw bounds/anchor for the selected Builder node in preview.");
        }
        UI::SameLine();
        bool builderParentOverlay = S_PreviewSelectedParentBoundsOverlayEnabled;
        builderParentOverlay = UI::Checkbox("Parent chain##builder-edit-selected-parent-overlay", builderParentOverlay);
        if (builderParentOverlay != S_PreviewSelectedParentBoundsOverlayEnabled) {
            S_PreviewSelectedParentBoundsOverlayEnabled = builderParentOverlay;
            _RefreshPreviewForBoundsOverlayToggle();
        }
        if (UI::IsItemHovered()) {
            _SetBuilderParentChainTooltip();
        }
        UI::SameLine();
        bool stickySnap = S_BuilderStickySnapEnabled;
        stickySnap = UI::Checkbox("Sticky snap##builder-edit-sticky-snap", stickySnap);
        if (stickySnap != S_BuilderStickySnapEnabled) {
            S_BuilderStickySnapEnabled = stickySnap;
            if (!S_BuilderStickySnapEnabled && g_BuilderStickyGuides.active) {
                _ClearBuilderStickyGuides();
                _RefreshBuilderStickyGuidesPreview();
            }
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Snap position-slider moves to nearby screen and node guides.");
        }
        UI::SameLine();
        bool stickyGuides = S_BuilderStickySnapGuidesEnabled;
        stickyGuides = UI::Checkbox("Guides##builder-edit-sticky-guides", stickyGuides);
        if (stickyGuides != S_BuilderStickySnapGuidesEnabled) {
            S_BuilderStickySnapGuidesEnabled = stickyGuides;
            if (!S_BuilderStickySnapGuidesEnabled && g_BuilderStickyGuides.active) {
                _ClearBuilderStickyGuides();
                _RefreshBuilderStickyGuidesPreview();
            } else {
                _RefreshBuilderStickyGuidesPreview();
            }
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Show full-screen guide lines when sticky snap locks to an axis.");
        }
    }


    void _RenderPreviewView() {
        _EnsureDoc();

        if (UI::BeginChild("##builder-preview-scroll", vec2(0, 0), false)) {

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Play + " Preview Controls##bv-prev-ctrl")) {
                if (UI::Button(Icons::Play + " Apply##bv-apply")) ApplyPreviewLayer();
                UI::SameLine();
                if (UI::Button(Icons::Stop + " Destroy##bv-destroy")) DestroyPreviewLayer();
                UI::SameLine();
                if (UI::Button(Icons::Compress + " Force-fit##bv-fit")) {
                    g_PreviewForceFitOnce = true;
                    ApplyPreviewLayer();
                }
                UI::SameLine();
                if (UI::Button(Icons::Plus + " Origin##bv-origin")) AddDebugOriginMarker(true);

                UI::Separator();
                S_AutoLivePreview = UI::Checkbox("Auto live preview##bv-auto", S_AutoLivePreview);
                if (!S_AutoLivePreview) g_AutoPreviewPending = false;

                UI::SameLine();
                UI::SetNextItemWidth(100.0f);
                int debounceMs = int(S_AutoLivePreviewDebounceMs);
                debounceMs = UI::InputInt("Debounce##bv-auto", debounceMs);
                if (debounceMs < 0) debounceMs = 0;
                if (debounceMs > 2000) debounceMs = 2000;
                S_AutoLivePreviewDebounceMs = uint(debounceMs);

                S_PreviewLayerKey = UI::InputText("Layer key##bv-key", S_PreviewLayerKey);

                if (S_AutoLivePreview && g_AutoPreviewPending) {
                    UI::TextDisabled("\\$ff0[preview pending]\\$z");
                }
            }

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FolderOpenO + " Import From Live Layer##bv-import-live")) {
                int prevAppKind = g_ImportAppKind;
                if (UI::BeginCombo("App##bv-app", _AppKindLabel(g_ImportAppKind))) {
                    for (int kind = 0; kind <= 2; ++kind) {
                        bool sel = (g_ImportAppKind == kind);
                        if (UI::Selectable(_AppKindLabel(kind), sel)) g_ImportAppKind = kind;
                    }
                    UI::EndCombo();
                }
                UI::SameLine();
                UI::SetNextItemWidth(80.0f);
                int prevLayerIx = g_ImportLayerIx;
                g_ImportLayerIx = UI::InputInt("Layer##bv-lix", g_ImportLayerIx);
                if (S_LiveLayerBoundsOverlayEnabled) {
                    if (g_ImportAppKind != prevAppKind) {
                        RefreshLiveLayerBoundsOverlay(true);
                    } else if (g_ImportLayerIx != prevLayerIx) {
                        RefreshLiveLayerBoundsOverlay(false);
                    }
                }

                if (UI::Button(Icons::FolderOpenO + " Import##bv-imp")) {
                    ImportFromLiveLayer(g_ImportAppKind, g_ImportLayerIx);
                }
                UI::SameLine();
                if (UI::Button(Icons::FolderOpenO + " Clone##bv-clone")) {
                    ImportFromLiveLayerTree(g_ImportAppKind, g_ImportLayerIx);
                }
                UI::SameLine();
                S_CenterImportedLiveCopy = UI::Checkbox("Recenter##bv-recenter", S_CenterImportedLiveCopy);
            }

            string prevDiagIndicator = S_PreviewDiagnosticsEnabled
                ? "  \\$9fd" + Icons::Play + "\\$z"
                : "  \\$888" + Icons::Stop + "\\$z";
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Wrench + " Diagnostics & Overlays" + prevDiagIndicator + "##bv-diag")) {
                S_PreviewDiagnosticsEnabled = UI::Checkbox("Enabled##bv-diag-en", S_PreviewDiagnosticsEnabled);
                UI::SameLine();
                S_PreviewDiagnosticsPrintToLog = UI::Checkbox("Log##bv-diag-log", S_PreviewDiagnosticsPrintToLog);

                S_PreviewDebugOverlayEnabled = UI::Checkbox("Bounds overlay##bv-ov", S_PreviewDebugOverlayEnabled);
                UI::SameLine();
                bool prevSelBounds = S_PreviewSelectedBoundsOverlayEnabled;
                S_PreviewSelectedBoundsOverlayEnabled = UI::Checkbox("Selected bounds##bv-ov-selected", S_PreviewSelectedBoundsOverlayEnabled);
                if (S_PreviewSelectedBoundsOverlayEnabled != prevSelBounds) {
                    _RefreshPreviewForBoundsOverlayToggle();
                }
                UI::SameLine();
                bool prevParentBounds = S_PreviewSelectedParentBoundsOverlayEnabled;
                S_PreviewSelectedParentBoundsOverlayEnabled = UI::Checkbox("Parent chain##bv-ov-selected-parent", S_PreviewSelectedParentBoundsOverlayEnabled);
                if (S_PreviewSelectedParentBoundsOverlayEnabled != prevParentBounds) {
                    _RefreshPreviewForBoundsOverlayToggle();
                }
                if (UI::IsItemHovered()) {
                    _SetBuilderParentChainTooltip();
                }

                S_PreviewSanitizeInvalidTags = UI::Checkbox("Sanitize tags##bv-san", S_PreviewSanitizeInvalidTags);
                UI::SameLine();
                S_PreviewOmitGenericCommonAttrs = UI::Checkbox("Omit generic attrs##bv-san", S_PreviewOmitGenericCommonAttrs);

                if (S_PreviewSelectedBoundsOverlayEnabled) {
                    int boundsIx = g_BoundsTargetNodeIx >= 0 ? g_BoundsTargetNodeIx : g_SelectedNodeIx;
                    auto selAbs = ComputeAbsMetrics(g_Doc, boundsIx);
                    if (selAbs !is null && selAbs.ok) {
                        string pinLabel = g_BoundsTargetNodeIx >= 0 ? "\\$fd8" + Icons::ThumbTack + "\\$z " : "";
                        vec2 bSz = selAbs.boundsMax - selAbs.boundsMin;
                        UI::TextDisabled(pinLabel + "Bounds [" + boundsIx + "]: " + _FmtVec2(selAbs.boundsMin) + " .. " + _FmtVec2(selAbs.boundsMax) + "  size=" + _FmtVec2(bSz));
                        UI::TextDisabled("Anchor: pos=" + _FmtVec2(selAbs.absPos) + "  scale=" + selAbs.absScale);
                    } else {
                        UI::TextDisabled("No bounds target or missing typed props.");
                    }
                }

                if (UI::Button(Icons::Clipboard + " Copy Diag##bv-copy-diag")) {
                    if (g_LastPreviewDiagText.Length > 0) {
                        IO::SetClipboard(g_LastPreviewDiagText);
                        g_Status = "Copied preview diagnostics.";
                    } else {
                        g_Status = "No diagnostics text yet.";
                    }
                }
                UI::SameLine();
                if (UI::Button(Icons::Clipboard + " Copy Dump##bv-copy-dump")) CopyBuilderDumpToClipboard(true);

                if (g_LastPreviewAtMs > 0) {
                    UI::TextDisabled("t=" + g_LastPreviewAtMs + "ms  key=\"" + g_LastPreviewLayerKey + "\"  " + g_LastPreviewAppLabel + "  ix=" + g_LastPreviewLayerIx);
                } else {
                    UI::TextDisabled("No preview yet.");
                }

                float diagTextH = 140.0f;
                if (UI::BeginChild("##bv-diag-text", vec2(0, diagTextH), true)) {
                    if (g_LastPreviewDiagText.Length == 0) {
                        UI::TextDisabled("No preview diagnostics text.");
                    } else {
                        auto diagLines = g_LastPreviewDiagText.Split("\n");
                        for (uint dl = 0; dl < diagLines.Length; ++dl) {
                            UI::TextWrapped(diagLines[dl]);
                        }
                    }
                }
                UI::EndChild();
            }

            UI::SetNextItemOpen(false, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Exchange + " Live Layer Bounds##bv-live")) {
                UI::TextDisabled("Source: " + _AppKindLabel(g_ImportAppKind) + " | Layer ix: " + g_ImportLayerIx);

                if (UI::Button(Icons::Refresh + " Scan##bv-live-scan")) {
                    ScanLiveLayerBounds(g_ImportAppKind);
                    if (S_LiveLayerBoundsOverlayEnabled) RefreshLiveLayerBoundsOverlay(false);
                }
                UI::SameLine();
                if (UI::Button(Icons::Clipboard + " Copy##bv-live-copy")) {
                    IO::SetClipboard(LiveLayerBoundsTableText());
                    g_Status = "Copied live bounds table.";
                }
                if (g_LiveLayerBoundsStatus.Length > 0) UI::TextDisabled(g_LiveLayerBoundsStatus);

                float liveH = 200.0f;
                if (UI::BeginChild("##bv-live-bounds", vec2(0, liveH), true)) {
                    if (g_LiveLayerBoundsRows.Length == 0) {
                        UI::TextDisabled("No scan yet. Click '" + Icons::Refresh + " Scan'.");
                    } else {
                        uint ixChars = 2;
                        uint nodesChars = 5;
                        uint nameChars = 10;
                        uint vecChars = 8;
                        for (uint ri = 0; ri < g_LiveLayerBoundsRows.Length; ++ri) {
                            auto r = g_LiveLayerBoundsRows[ri];
                            if (r is null) continue;
                            string ixText = tostring(r.layerIx);
                            if (ixText.Length > ixChars) ixChars = ixText.Length;
                            string nodesText = tostring(r.nodes);
                            if (nodesText.Length > nodesChars) nodesChars = nodesText.Length;
                            string nm = r.manialinkName.Length > 0 ? r.manialinkName : (r.attachId.Length > 0 ? r.attachId : "<unnamed>");
                            if (nm.Length > nameChars) nameChars = nm.Length;
                            if (r.hasAll) {
                                string v1 = _FmtVec2(r.minAll);
                                string v2 = _FmtVec2(r.maxAll);
                                string v3 = _FmtVec2(r.maxAll - r.minAll);
                                string v4 = _FmtVec2((r.minAll + r.maxAll) * 0.5f);
                                if (v1.Length > vecChars) vecChars = v1.Length;
                                if (v2.Length > vecChars) vecChars = v2.Length;
                                if (v3.Length > vecChars) vecChars = v3.Length;
                                if (v4.Length > vecChars) vecChars = v4.Length;
                            }
                        }

                        float colIx = _AutoColWidthFromChars(ixChars + 2, 50.0f, 120.0f);
                        float colVis = _AutoColWidthFromChars(3, 38.0f, 64.0f);
                        float colNodes = _AutoColWidthFromChars(nodesChars + 1, 62.0f, 140.0f);
                        float colName = _AutoColWidthFromChars(nameChars + 1, 170.0f, 520.0f);
                        float colVec = _AutoColWidthFromChars(vecChars + 1, 110.0f, 260.0f);

                        int tblFlags = UI::TableFlags::RowBg | UI::TableFlags::BordersInnerV | UI::TableFlags::ScrollY | UI::TableFlags::ScrollX | UI::TableFlags::SizingFixedFit;
                        if (UI::BeginTable("##bv-live-tbl", 8, tblFlags)) {
                            UI::TableSetupColumn("Ix", UI::TableColumnFlags::WidthFixed, colIx);
                            UI::TableSetupColumn("Vis", UI::TableColumnFlags::WidthFixed, colVis);
                            UI::TableSetupColumn("Nodes", UI::TableColumnFlags::WidthFixed, colNodes);
                            UI::TableSetupColumn("Name/Attach", UI::TableColumnFlags::WidthFixed, colName);
                            UI::TableSetupColumn("Min", UI::TableColumnFlags::WidthFixed, colVec);
                            UI::TableSetupColumn("Max", UI::TableColumnFlags::WidthFixed, colVec);
                            UI::TableSetupColumn("Size", UI::TableColumnFlags::WidthFixed, colVec);
                            UI::TableSetupColumn("Center", UI::TableColumnFlags::WidthFixed, colVec);
                        UI::TableHeadersRow();

                        for (uint ri = 0; ri < g_LiveLayerBoundsRows.Length; ++ri) {
                            auto r = g_LiveLayerBoundsRows[ri];
                            if (r is null) continue;

                            vec2 bSz = r.hasAll ? (r.maxAll - r.minAll) : vec2();
                            vec2 bCenter = r.hasAll ? ((r.minAll + r.maxAll) * 0.5f) : vec2();
                            bool hl = (r.layerIx == g_ImportLayerIx);
                            string rc = hl ? "\\$bff" : "";
                            string rz = hl ? "\\$z" : "";

                            UI::TableNextRow();
                            UI::TableSetColumnIndex(0);
                            if (UI::Button((hl ? Icons::ChevronRight : Icons::Crosshairs) + "##bv-live-pick-" + ri)) {
                                g_ImportLayerIx = r.layerIx;
                                if (S_LiveLayerBoundsOverlayEnabled) RefreshLiveLayerBoundsOverlay(false);
                            }
                            UI::SameLine();
                            UI::Text(rc + (hl ? Icons::ChevronRight + " " : "  ") + tostring(r.layerIx) + rz);
                            UI::TableSetColumnIndex(1);
                            UI::Text(r.visible ? "\\$9fdY\\$z" : "\\$888N\\$z");
                            UI::TableSetColumnIndex(2);
                            UI::Text(tostring(r.nodes));
                            UI::TableSetColumnIndex(3);
                            string nm = r.manialinkName.Length > 0 ? r.manialinkName : (r.attachId.Length > 0 ? r.attachId : "\\$888<unnamed>\\$z");
                            UI::Text(rc + nm + rz);
                            UI::TableSetColumnIndex(4);
                            UI::Text(r.hasAll ? _FmtVec2(r.minAll) : "\\$888-\\$z");
                            UI::TableSetColumnIndex(5);
                            UI::Text(r.hasAll ? _FmtVec2(r.maxAll) : "\\$888-\\$z");
                            UI::TableSetColumnIndex(6);
                            UI::Text(r.hasAll ? _FmtVec2(bSz) : "\\$888-\\$z");
                            UI::TableSetColumnIndex(7);
                            UI::Text(r.hasAll ? _FmtVec2(bCenter) : "\\$888-\\$z");
                        }

                        UI::EndTable();
                    }
                    }
                }
                UI::EndChild();
            }

        }
        UI::EndChild();
    }

    void _RenderSelectorView() {
        if (UI::BeginChild("##builder-selector-scroll", vec2(0, 0), false)) {
            if (!g_SelectorArmed) {
                if (UI::Button(Icons::Crosshairs + " Arm Picker##bv-selector-arm")) {
                    SelectorArmPicker();
                }
            } else {
                if (UI::Button(Icons::Stop + " Stop Picker##bv-selector-stop")) {
                    SelectorDisarmPicker();
                }
                UI::SameLine();
                if (UI::Button(Icons::Crosshairs + " Pick Now##bv-selector-now")) {
                    SelectorPickNow();
                    if (!S_SelectorStayArmed) SelectorDisarmPicker(true);
                }
            }
            UI::SameLine();
            S_SelectorStayArmed = UI::Checkbox("Stay armed##bv-selector-stay", S_SelectorStayArmed);

            if (UI::BeginCombo("Source app##bv-selector-source", SelectorSourceLabel(S_SelectorSourceAppKind))) {
                bool selAll = S_SelectorSourceAppKind < 0;
                if (UI::Selectable("All", selAll)) S_SelectorSourceAppKind = -1;
                bool selCur = S_SelectorSourceAppKind == 2;
                if (UI::Selectable("Current", selCur)) S_SelectorSourceAppKind = 2;
                bool selMenu = S_SelectorSourceAppKind == 1;
                if (UI::Selectable("Menu", selMenu)) S_SelectorSourceAppKind = 1;
                bool selPg = S_SelectorSourceAppKind == 0;
                if (UI::Selectable("Playground", selPg)) S_SelectorSourceAppKind = 0;
                UI::EndCombo();
            }

            S_SelectorIncludeHidden = UI::Checkbox("Include hidden nodes##bv-selector-hidden", S_SelectorIncludeHidden);
            S_SelectorSyncMlSelection = UI::Checkbox("Sync ManiaLink UI selection##bv-selector-sync", S_SelectorSyncMlSelection);
            S_SelectorSyncControlTreeSelection = UI::Checkbox("Sync ControlTree selection##bv-selector-sync-ct", S_SelectorSyncControlTreeSelection);

            if (g_SelectorArmed) {
                UI::Text("\\$ff0" + Icons::Crosshairs + "\\$z Armed: left-click target element.");
            }
            if (g_SelectorStatus.Length > 0) {
                UI::TextDisabled(g_SelectorStatus);
            }

            if (g_SelectorArmed) {
                if (g_SelectorWaitMouseRelease) {
                    if (!UI::IsMouseDown(UI::MouseButton::Left)) g_SelectorWaitMouseRelease = false;
                }
            }

            UI::Separator();

            if (UI::Button(Icons::Clipboard + " Copy Hits##bv-selector-copy")) {
                IO::SetClipboard(SelectorHitsTableText());
                g_SelectorStatus = "Copied selector hits.";
            }
            UI::SameLine();
            UI::TextDisabled("Last pick: " + (g_SelectorLastPickAtMs > 0 ? tostring(g_SelectorLastPickAtMs) : "none"));

            float hitTableH = 230.0f;
            if (UI::BeginChild("##bv-selector-hits", vec2(0, hitTableH), true)) {
                if (g_SelectorHits.Length == 0) {
                    UI::TextDisabled("No hits yet. Arm picker and click a live UI element.");
                } else {
                    uint rankChars = 1;
                    uint appChars = 9;
                    uint typeChars = 4;
                    uint idChars = 4;
                    uint pathChars = 6;
                    uint sizeChars = 6;
                    for (uint i = 0; i < g_SelectorHits.Length; ++i) {
                        auto h = g_SelectorHits[i];
                        if (h is null) continue;
                        string rank = tostring(i + 1);
                        if (rank.Length > rankChars) rankChars = rank.Length;
                        string appLayer = _AppKindLabel(h.appKind) + " L" + h.layerIx;
                        if (appLayer.Length > appChars) appChars = appLayer.Length;
                        if (h.typeName.Length > typeChars) typeChars = h.typeName.Length;
                        string id = h.controlId.Length > 0 ? h.controlId : "<none>";
                        if (id.Length > idChars) idChars = id.Length;
                        string path = "/" + (h.path.Length > 0 ? h.path : "<root>");
                        if (path.Length > pathChars) pathChars = path.Length;
                        string size = _FmtVec2(h.absSize);
                        if (size.Length > sizeChars) sizeChars = size.Length;
                    }

                    float colBtn = 34.0f;
                    float colRank = _AutoColWidthFromChars(rankChars, 34.0f, 90.0f);
                    float colApp = _AutoColWidthFromChars(appChars, 92.0f, 220.0f);
                    float colType = _AutoColWidthFromChars(typeChars, 84.0f, 220.0f);
                    float colId = _AutoColWidthFromChars(idChars, 120.0f, 420.0f);
                    float colPath = _AutoColWidthFromChars(pathChars, 180.0f, 700.0f);
                    float colSize = _AutoColWidthFromChars(sizeChars, 98.0f, 220.0f);
                    float colVis = _AutoColWidthFromChars(3, 48.0f, 70.0f);

                    int tblFlags = UI::TableFlags::RowBg | UI::TableFlags::BordersInnerV | UI::TableFlags::ScrollY | UI::TableFlags::ScrollX | UI::TableFlags::SizingFixedFit;
                    if (UI::BeginTable("##bv-selector-hits-table", 8, tblFlags)) {
                    UI::TableSetupColumn("", UI::TableColumnFlags::WidthFixed, colBtn);
                    UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, colRank);
                    UI::TableSetupColumn("App/Layer", UI::TableColumnFlags::WidthFixed, colApp);
                    UI::TableSetupColumn("Type", UI::TableColumnFlags::WidthFixed, colType);
                    UI::TableSetupColumn("ID", UI::TableColumnFlags::WidthFixed, colId);
                    UI::TableSetupColumn("Path", UI::TableColumnFlags::WidthFixed, colPath);
                    UI::TableSetupColumn("Size", UI::TableColumnFlags::WidthFixed, colSize);
                    UI::TableSetupColumn("Vis", UI::TableColumnFlags::WidthFixed, colVis);
                    UI::TableHeadersRow();

                    for (uint i = 0; i < g_SelectorHits.Length; ++i) {
                        auto h = g_SelectorHits[i];
                        if (h is null) continue;
                        bool sel = int(i) == g_SelectorSelectedHitIx;

                        UI::TableNextRow();
                        UI::TableSetColumnIndex(0);
                        if (UI::Button((sel ? Icons::ChevronRight : Icons::Crosshairs) + "##bv-selector-pick-" + i, vec2(22, 0))) {
                            g_SelectorSelectedHitIx = int(i);
                            if (S_SelectorSyncMlSelection || S_SelectorSyncControlTreeSelection) {
                                SelectorSelectHit(g_SelectorSelectedHitIx, true);
                            }
                        }
                        UI::TableSetColumnIndex(1);
                        UI::Text(tostring(i + 1));
                        UI::TableSetColumnIndex(2);
                        UI::Text(_AppKindLabel(h.appKind) + " L" + h.layerIx);
                        UI::TableSetColumnIndex(3);
                        UI::Text(h.typeName);
                        UI::TableSetColumnIndex(4);
                        UI::Text(h.controlId.Length > 0 ? h.controlId : "\\$888<none>\\$z");
                        UI::TableSetColumnIndex(5);
                        UI::Text("/" + (h.path.Length > 0 ? h.path : "<root>"));
                        UI::TableSetColumnIndex(6);
                        UI::Text(_FmtVec2(h.absSize));
                        UI::TableSetColumnIndex(7);
                        UI::Text(h.visibleEffective ? "\\$9fdY\\$z" : "\\$f88N\\$z");
                    }

                    UI::EndTable();
                }
                }
            }
            UI::EndChild();

            if (g_SelectorSelectedHitIx >= 0 && g_SelectorSelectedHitIx < int(g_SelectorHits.Length)) {
                auto h = g_SelectorHits[uint(g_SelectorSelectedHitIx)];
                if (h !is null) {
                    UI::Separator();
                    UI::Text(SelectorHitSummary(h, g_SelectorSelectedHitIx + 1));

                    if (UI::Button(Icons::ChevronRight + " Sync Selected##bv-selector-sync-one")) {
                        SelectorSelectHit(g_SelectorSelectedHitIx, true);
                    }
                    UI::SameLine();
                    if (UI::Button(Icons::ShareSquareO + " Sync To ML##bv-selector-sync-ml-one")) {
                        bool ok = SelectorSyncHitToMlSelection(g_SelectorSelectedHitIx);
                        g_SelectorStatus = ok
                            ? "Synced selected hit to ManiaLink UI selection."
                            : "Could not sync selected hit to ManiaLink UI selection.";
                    }
                    UI::SameLine();
                    if (UI::Button(Icons::ShareSquareO + " Sync To CT##bv-selector-sync-ct-one")) {
                        bool ok = SelectorSyncHitToControlTreeSelection(g_SelectorSelectedHitIx);
                        g_SelectorStatus = ok
                            ? "Synced selected hit to ControlTree selection."
                            : "Could not sync selected hit to ControlTree selection.";
                    }
                    UI::SameLine();
                    if (UI::Button(Icons::Clipboard + " Copy Selected##bv-selector-copy-one")) {
                        IO::SetClipboard(SelectorHitSummary(h, g_SelectorSelectedHitIx + 1));
                        g_SelectorStatus = "Copied selected hit summary.";
                    }

                    UI::TextDisabled("Bounds: " + _FmtVec2(h.boundsMin) + " .. " + _FmtVec2(h.boundsMax));
                    UI::TextDisabled("Abs pos: " + _FmtVec2(h.absPos) + "  click: " + _FmtVec2(h.clickPoint) + "  z=" + h.zIndex);
                    UI::TextDisabled("Layer: vis=" + (h.layerVisible ? "1" : "0") + " attach=\"" + h.layerAttachId + "\" name=\"" + h.manialinkName + "\"");
                    UI::TextDisabled("Control: selfVis=" + (h.selfVisible ? "1" : "0") + " hiddenByAncestor=" + (h.hiddenByAncestor ? "1" : "0"));
                    if (h.classList.Length > 0) UI::TextDisabled("Classes: " + h.classList);
                    if (h.textPreview.Length > 0) UI::TextDisabled("Text: " + h.textPreview);
                }
            }
        }
        UI::EndChild();

        _RenderSelectorCaptureOverlay();
    }


    void _RenderIOView() {
        _EnsureDoc();

        if (UI::BeginChild("##builder-io-scroll", vec2(0, 0), false)) {

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FolderOpenO + " Import XML##bv-io-import")) {
                if (UI::Button(Icons::FolderOpenO + " Import From This Text##bv-io-imp")) {
                    ImportFromXmlText(g_ImportXmlInput, "import_xml", "Builder tab input");
                }

                float importH = Math::Max(120.0f, UI::GetContentRegionAvail().y * 0.3f);
                g_ImportXmlInput = UI::InputTextMultiline("##builder-import-xml", g_ImportXmlInput, vec2(0, importH));
            }

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FloppyO + " Export XML##bv-io-export")) {
                if (UI::Button(Icons::Refresh + " Refresh##bv-io-refresh")) {
                    g_LastExportXml = ExportToXml(g_Doc);
                    g_Status = "Refreshed export preview.";
                }
                UI::SameLine();
                if (UI::Button(Icons::Clipboard + " Copy##bv-io-copy")) ExportToClipboard();
                UI::SameLine();
                if (UI::Button(Icons::FloppyO + " Write##bv-io-write")) ExportToFilePath(S_ExportPath);

                S_ExportPath = UI::InputText("Export path##bv-io-path", S_ExportPath);

                if (g_LastExportXml.Length == 0) g_LastExportXml = ExportToXml(g_Doc);
                float exportH = Math::Max(120.0f, UI::GetContentRegionAvail().y * 0.5f);
                g_LastExportXml = UI::InputTextMultiline("##builder-export-xml", g_LastExportXml, vec2(0, exportH));
            }

            UI::SetNextItemOpen(false, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Exchange + " Diff##bv-io-diff")) {
                if (UI::Button(Icons::Exchange + " Compute Diff##bv-io-diff-btn")) DiffAgainstOriginal();

                if (g_LastDiff.Length == 0) {
                    UI::TextDisabled("No diff generated yet. Click 'Compute Diff'.");
                } else {
                    float diffH = Math::Max(100.0f, UI::GetContentRegionAvail().y - 4.0f);
                    if (UI::BeginChild("##bv-io-diff-text", vec2(0, diffH), true)) {
                        auto diffLines = g_LastDiff.Split("\n");
                        for (uint dli = 0; dli < diffLines.Length; ++dli) {
                            UI::TextWrapped(diffLines[dli]);
                        }
                    }
                    UI::EndChild();
                }
            }

        }
        UI::EndChild();
    }


    void _RenderCodeView() {
        _EnsureDoc();

        if (UI::BeginChild("##builder-code-scroll", vec2(0, 0), false)) {

            float halfH = Math::Max(120.0f, (UI::GetContentRegionAvail().y - 40.0f) * 0.5f);

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FileO + " Script##bv-code-script")) {
                if (g_Doc.scriptBlock is null) @g_Doc.scriptBlock = BuilderScriptBlock();
                g_Doc.scriptBlock.raw = _EditTextArea("##builder-script-block", g_Doc.scriptBlock.raw, vec2(0, halfH), "Updated script block.");
            }

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FileO + " Stylesheet##bv-code-style")) {
                if (g_Doc.stylesheetBlock is null) @g_Doc.stylesheetBlock = BuilderStylesheetBlock();
                g_Doc.stylesheetBlock.raw = _EditTextArea("##builder-stylesheet-block", g_Doc.stylesheetBlock.raw, vec2(0, halfH), "Updated stylesheet block.");
            }

        }
        UI::EndChild();
    }


    void _RenderSettingsView() {
        _EnsureDoc();

        if (UI::BeginChild("##builder-settings-scroll", vec2(0, 0), false)) {

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::FileO + " Document##bv-set-doc")) {
                g_Doc.name = _EditStringField("Document name##bv-set", g_Doc.name, "Updated document name.");
                int undoMax = UI::InputInt("Undo max snapshots##bv-set", S_UndoMax);
                if (undoMax != S_UndoMax) {
                    S_UndoMax = Math::Max(10, undoMax);
                }
                S_StripFrameClippingOnImport = UI::Checkbox("Strip frame clipping on import##bv-set-doc", S_StripFrameClippingOnImport);
                if (UI::IsItemHovered()) {
                    UI::SetTooltip("When importing/cloning live layers, disable frame clip windows so children can render outside parent bounds.");
                }
                if (UI::Button("Disable frame clipping in current document##bv-set-doc")) {
                    DisableAllFrameClipping(true, true);
                }
                UI::TextDisabled("Source: " + g_Doc.sourceKind + (g_Doc.sourceLabel.Length > 0 ? " (" + g_Doc.sourceLabel + ")" : ""));
            }

            UI::SetNextItemOpen(false, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Cog + " Layout##bv-set-layout")) {
                S_TreeWidth = UI::InputInt("Tree pane width##bv-set", S_TreeWidth);
                if (S_TreeWidth < 220) S_TreeWidth = 220;
                if (S_TreeWidth > 1100) S_TreeWidth = 1100;
            }

            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Crosshairs + " Sticky Snap##bv-set-snap")) {
                bool prevStickyEnabled = S_BuilderStickySnapEnabled;
                bool prevGuidesEnabled = S_BuilderStickySnapGuidesEnabled;
                S_BuilderStickySnapEnabled = UI::Checkbox("Enable sticky snap##bv-set-snap-enable", S_BuilderStickySnapEnabled);
                S_BuilderStickySnapToScreen = UI::Checkbox("Snap to screen guides##bv-set-snap-screen", S_BuilderStickySnapToScreen);
                S_BuilderStickySnapToNodes = UI::Checkbox("Snap to builder nodes##bv-set-snap-nodes", S_BuilderStickySnapToNodes);
                S_BuilderStickySnapGuidesEnabled = UI::Checkbox("Show snap guide lines##bv-set-snap-guides", S_BuilderStickySnapGuidesEnabled);
                S_BuilderStickySnapThreshold = UI::InputFloat("Snap threshold##bv-set-snap-thresh", S_BuilderStickySnapThreshold);
                if (S_BuilderStickySnapThreshold < 0.0f) S_BuilderStickySnapThreshold = 0.0f;
                if (S_BuilderStickySnapThreshold > 20.0f) S_BuilderStickySnapThreshold = 20.0f;
                S_BuilderStickySnapOffscreenMargin = UI::InputFloat("Offscreen margin##bv-set-snap-margin", S_BuilderStickySnapOffscreenMargin);
                if (S_BuilderStickySnapOffscreenMargin < 0.0f) S_BuilderStickySnapOffscreenMargin = 0.0f;
                if (S_BuilderStickySnapOffscreenMargin > 40.0f) S_BuilderStickySnapOffscreenMargin = 40.0f;
                if ((prevStickyEnabled != S_BuilderStickySnapEnabled || prevGuidesEnabled != S_BuilderStickySnapGuidesEnabled)
                    && (!S_BuilderStickySnapEnabled || !S_BuilderStickySnapGuidesEnabled)
                    && g_BuilderStickyGuides.active) {
                    _ClearBuilderStickyGuides();
                    _RefreshBuilderStickyGuidesPreview();
                }
                UI::TextDisabled("Applies to the position slider only. Manual text entry stays raw.");
            }

            int diagDocCount = int(g_Doc.diagnostics.Length);
            string diagDocLabel = diagDocCount > 0
                ? "  \\$fd8(" + diagDocCount + ")\\$z"
                : "  \\$888(0)\\$z";
            UI::SetNextItemOpen(true, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::ExclamationTriangle + " Document Diagnostics" + diagDocLabel + "##bv-set-diag")) {
                if (diagDocCount == 0) {
                    UI::TextDisabled("No document diagnostics.");
                } else {
                    for (uint di = 0; di < g_Doc.diagnostics.Length; ++di) {
                        auto d = g_Doc.diagnostics[di];
                        if (d is null) continue;

                        UI::PushID("bv-diag-" + tostring(di));

                        string sevColor = "\\$888";
                        string sevIcon = Icons::FileO;
                        if (d.severity == "error") { sevColor = "\\$f66"; sevIcon = Icons::ExclamationTriangle; }
                        else if (d.severity == "warn") { sevColor = "\\$fd8"; sevIcon = Icons::ExclamationTriangle; }

                        UI::Text(sevColor + sevIcon + " [" + d.severity.ToUpper() + "] " + d.code + "\\$z");
                        UI::TextDisabled(d.message);

                        if (d.nodeUid.Length > 0) {
                            UI::SameLine();
                            if (UI::Button(Icons::ChevronRight + " Go##bv-go")) {
                                int ix = _GetNodeIxByUid(d.nodeUid);
                                if (ix >= 0) {
                                    g_SelectedNodeIx = ix;
                                    g_Status = "Jumped to node.";
                                } else {
                                    g_Status = "Node not found.";
                                }
                            }
                        }

                        UI::Separator();
                        UI::PopID();
                    }
                }
            }

            UI::SetNextItemOpen(false, UI::Cond::Appearing);
            if (UI::CollapsingHeader(Icons::Wrench + " Self-Tests##bv-set-tests")) {
                if (UI::Button(Icons::Play + " Run##bv-set-run-tests")) RunAcceptanceSelfTests();
                UI::SameLine();
                UI::Text(g_TestStatus);
                UI::Separator();
                for (uint ti = 0; ti < g_TestLines.Length; ++ti) {
                    auto line = g_TestLines[ti];
                    if (line is null) continue;
                    string pf = line.ok ? "\\$9fd" + Icons::Play : "\\$f66" + Icons::ExclamationTriangle;
                    UI::Text(pf + "\\$z " + line.id + " \\$888- " + line.detail + "\\$z");
                }
            }

        }
        UI::EndChild();
    }

    void RenderSelectorSettingsUI() {
        _RenderSelectorView();
    }

    void RenderSettingsUI() {
        _EnsureDoc();
        TickAutoPreview();

        _RenderToolbar();
        UI::Separator();

        UI::BeginTabBar("##builder-main-tabs");

        if (UI::BeginTabItem(Icons::FileO + " Edit##builder-tab-edit")) {
            _RenderEditView();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem(Icons::Play + " Preview##builder-tab-preview")) {
            _RenderPreviewView();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem(Icons::Exchange + " I/O##builder-tab-io")) {
            _RenderIOView();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem(Icons::FileO + " Code##builder-tab-code")) {
            _RenderCodeView();
            UI::EndTabItem();
        }

        if (UI::BeginTabItem(Icons::Cog + " Settings##builder-tab-settings")) {
            _RenderSettingsView();
            UI::EndTabItem();
        }

        UI::EndTabBar();
    }

}
}
