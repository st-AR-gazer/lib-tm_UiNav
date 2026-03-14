namespace UiNav {
namespace Builder {

    [Setting hidden name="UiNav Builder v1.2 preview layer key"]
    string S_PreviewLayerKey = "UiNav_BuilderPreview";

    [Setting hidden name="UiNav Builder v1.2 export path"]
    string S_ExportPath = IO::FromStorageFolder("Exports/ManiaLinks/Builder/uinav_builder_v1_2_export.xml");

    [Setting hidden name="UiNav Builder v1.2 tree width"]
    int S_TreeWidth = 360;

    [Setting hidden name="UiNav Builder v1.2 undo max snapshots"]
    int S_UndoMax = 120;

    [Setting hidden name="UiNav Builder v1.2 center imported live copy"]
    bool S_CenterImportedLiveCopy = false;

    [Setting hidden name="UiNav Builder v1.2 strip frame clipping on import"]
    bool S_StripFrameClippingOnImport = true;

    [Setting hidden name="UiNav Builder v1.2 auto live preview"]
    bool S_AutoLivePreview = true;

    [Setting hidden name="UiNav Builder v1.2 auto live preview debounce ms"]
    uint S_AutoLivePreviewDebounceMs = 120;


    [Setting hidden name="UiNav Builder v1.2 preview diagnostics enabled"]
    bool S_PreviewDiagnosticsEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 preview diagnostics print to log"]
    bool S_PreviewDiagnosticsPrintToLog = false;

    [Setting hidden name="UiNav Builder v1.2 preview debug overlay enabled"]
    bool S_PreviewDebugOverlayEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 preview selected node overlay enabled"]
    bool S_PreviewSelectedBoundsOverlayEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 preview selected parent overlay enabled"]
    bool S_PreviewSelectedParentBoundsOverlayEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 live bounds overlay enabled"]
    bool S_LiveLayerBoundsOverlayEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 live bounds overlay parent chain enabled"]
    bool S_LiveLayerBoundsOverlayParentChainEnabled = false;

    [Setting hidden name="UiNav Builder v1.2 preview sanitize invalid tags"]
    bool S_PreviewSanitizeInvalidTags = false;

    [Setting hidden name="UiNav Builder v1.2 preview omit generic common attrs"]
    bool S_PreviewOmitGenericCommonAttrs = false;

    [Setting hidden name="UiNav Builder v1.2 preview force-fit half width"]
    float S_PreviewForceFitHalfW = 150.0f;

    [Setting hidden name="UiNav Builder v1.2 preview force-fit half height"]
    float S_PreviewForceFitHalfH = 85.0f;

    [Setting hidden name="UiNav Builder v1.2 preview force-fit margin"]
    float S_PreviewForceFitMargin = 0.92f;

    [Setting hidden name="UiNav Builder v1.2 sticky snap enabled"]
    bool S_BuilderStickySnapEnabled = true;

    [Setting hidden name="UiNav Builder v1.2 sticky snap to screen"]
    bool S_BuilderStickySnapToScreen = true;

    [Setting hidden name="UiNav Builder v1.2 sticky snap to builder nodes"]
    bool S_BuilderStickySnapToNodes = true;

    [Setting hidden name="UiNav Builder v1.2 sticky snap guides enabled"]
    bool S_BuilderStickySnapGuidesEnabled = true;

    [Setting hidden name="UiNav Builder v1.2 sticky snap threshold"]
    float S_BuilderStickySnapThreshold = 2.0f;

    [Setting hidden name="UiNav Builder v1.2 sticky snap offscreen margin"]
    float S_BuilderStickySnapOffscreenMargin = 6.0f;

    [Setting hidden name="UiNav Builder v1.2 selector source app kind"]
    int S_SelectorSourceAppKind = -1; // -1 = all, 0 = playground, 1 = menu, 2 = current

    [Setting hidden name="UiNav Builder v1.2 selector include hidden"]
    bool S_SelectorIncludeHidden = false;

    [Setting hidden name="UiNav Builder v1.2 selector sync ML selection"]
    bool S_SelectorSyncMlSelection = true;

    [Setting hidden name="UiNav Builder v1.2 selector sync ControlTree selection"]
    bool S_SelectorSyncControlTreeSelection = true;

    [Setting hidden name="UiNav Builder v1.2 selector stay armed"]
    bool S_SelectorStayArmed = false;

    BuilderDocument@ g_Doc = null;
    int g_SelectedNodeIx = -1;
    int g_BoundsTargetNodeIx = -1;
    array<BuilderDocument@> g_UndoSnapshots;
    array<BuilderDocument@> g_RedoSnapshots;

    string g_Status = "";
    string g_ImportXmlInput = "";
    string g_LastExportXml = "";
    string g_LastDiff = "";
    int g_ImportAppKind = 1; // 0 = playground, 1 = menu, 2 = current
    int g_ImportLayerIx = -1;

    string g_RawAttrDraftKey = "";
    string g_RawAttrDraftValue = "";
    string g_ClassDraft = "";

    uint g_NextUid = 1;
    string g_BaselineXml = "";
    bool g_AutoPreviewPending = false;
    uint g_AutoPreviewQueuedMs = 0;

    bool g_PreviewForceFitOnce = false;

    uint g_LastPreviewAtMs = 0;
    string g_LastPreviewLayerKey = "";
    string g_LastPreviewAppLabel = "";
    int g_LastPreviewLayerIx = -1;
    int g_LastPreviewXmlLen = 0;
    bool g_LastPreviewBoundsHas = false;
    vec2 g_LastPreviewBoundsMin = vec2();
    vec2 g_LastPreviewBoundsMax = vec2();
    string g_LastPreviewDiagText = "";

    class BuilderStickyGuideState {
        bool active = false;
        vec2 screenHalfExtents = vec2(160.0f, 90.0f);
        float offscreenMargin = 0.0f;
        array<float> verticals;
        array<float> horizontals;
    }
    BuilderStickyGuideState g_BuilderStickyGuides;

    class LiveLayerBoundsRow {
        int appKind = -1;
        int layerIx = -1;
        bool visible = false;
        string attachId;
        string manialinkName;

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

        string note;
    }
    array<LiveLayerBoundsRow@> g_LiveLayerBoundsRows;
    uint g_LiveLayerBoundsAtMs = 0;
    int g_LiveLayerBoundsAppKind = -1;
    string g_LiveLayerBoundsStatus = "";

    class SelectorHitRow {
        int appKind = -1;
        int layerIx = -1;
        bool layerVisible = false;
        string layerAttachId;
        string manialinkName;

        string path;
        string uiPath;
        int depth = 0;

        string typeName;
        string controlId;
        string classList;
        string textPreview;

        bool selfVisible = true;
        bool hiddenByAncestor = false;
        bool visibleEffective = true;

        float zIndex = 0.0f;
        vec2 clickPoint = vec2();
        vec2 absPos = vec2();
        vec2 absSize = vec2();
        vec2 boundsMin = vec2();
        vec2 boundsMax = vec2();
        float area = 0.0f;
    }
    array<SelectorHitRow@> g_SelectorHits;
    int g_SelectorSelectedHitIx = -1;
    bool g_SelectorArmed = false;
    bool g_SelectorWaitMouseRelease = false;
    uint g_SelectorArmedAtMs = 0;
    uint g_SelectorLastPickAtMs = 0;
    string g_SelectorStatus = "";

    BuilderTypedProps@ _NewTypedProps() {
        return BuilderTypedProps();
    }

    BuilderNode@ _NewNode(const string &in kind, int parentIx = -1) {
        auto n = BuilderNode();
        n.uid = "n" + (g_NextUid++);
        n.kind = kind;
        n.tagName = kind;
        n.parentIx = parentIx;
        @n.typed = _NewTypedProps();
        return n;
    }

    BuilderDocument@ _NewDocument() {
        auto d = BuilderDocument();
        @d.scriptBlock = BuilderScriptBlock();
        @d.stylesheetBlock = BuilderStylesheetBlock();
        return d;
    }

    void _RebuildNodeIndex(BuilderDocument@ doc) {
        if (doc is null) return;
        doc.nodeByUid.DeleteAll();
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null) continue;
            doc.nodeByUid.Set(n.uid, int(i));
        }
    }

    BuilderTypedProps@ _CloneTypedProps(const BuilderTypedProps@ src) {
        if (src is null) return _NewTypedProps();
        auto outV = BuilderTypedProps();
        outV.size = src.size;
        outV.pos = src.pos;
        outV.z = src.z;
        outV.scale = src.scale;
        outV.rot = src.rot;
        outV.visible = src.visible;
        outV.hAlign = src.hAlign;
        outV.vAlign = src.vAlign;

        outV.clipActive = src.clipActive;
        outV.clipPos = src.clipPos;
        outV.clipSize = src.clipSize;
        outV.clipPosExplicit = src.clipPosExplicit;
        outV.clipSizeExplicit = src.clipSizeExplicit;

        outV.image = src.image;
        outV.imageFocus = src.imageFocus;
        outV.alphaMask = src.alphaMask;
        outV.style = src.style;
        outV.subStyle = src.subStyle;
        outV.bgColor = src.bgColor;
        outV.bgColorFocus = src.bgColorFocus;
        outV.modulateColor = src.modulateColor;
        outV.colorize = src.colorize;
        outV.opacity = src.opacity;
        outV.keepRatioMode = src.keepRatioMode;
        outV.blendMode = src.blendMode;

        outV.text = src.text;
        outV.textSize = src.textSize;
        outV.textFont = src.textFont;
        outV.textPrefix = src.textPrefix;
        outV.textColor = src.textColor;
        outV.maxLine = src.maxLine;
        outV.autoNewLine = src.autoNewLine;
        outV.lineSpacing = src.lineSpacing;
        outV.italicSlope = src.italicSlope;
        outV.appendEllipsis = src.appendEllipsis;

        outV.value = src.value;
        outV.textFormat = src.textFormat;
        outV.maxLength = src.maxLength;
        return outV;
    }

    BuilderNode@ _CloneNode(const BuilderNode@ src) {
        if (src is null) return null;
        auto n = BuilderNode();
        n.uid = src.uid;
        n.kind = src.kind;
        n.controlId = src.controlId;
        n.tagName = src.tagName;
        n.parentIx = src.parentIx;
        n.childIx = src.childIx;
        @n.typed = _CloneTypedProps(src.typed);
        n.classes = src.classes;
        n.scriptEvents = src.scriptEvents;
        n.fidelity.level = src.fidelity.level;
        n.fidelity.reasons = src.fidelity.reasons;
        n.span.start = src.span.start;
        n.span.end = src.span.end;

        array<string> keys = src.rawAttrs.GetKeys();
        for (uint i = 0; i < keys.Length; ++i) {
            string v = "";
            src.rawAttrs.Get(keys[i], v);
            n.rawAttrs.Set(keys[i], v);
        }
        return n;
    }

    BuilderDocument@ _CloneDocument(const BuilderDocument@ src) {
        if (src is null) return _NewDocument();
        auto d = BuilderDocument();
        d.format = src.format;
        d.schemaVersion = src.schemaVersion;
        d.name = src.name;
        d.sourceKind = src.sourceKind;
        d.sourceLabel = src.sourceLabel;
        d.rootIx = src.rootIx;
        d.originalXml = src.originalXml;
        d.dirty = src.dirty;

        @d.scriptBlock = BuilderScriptBlock();
        if (src.scriptBlock !is null) d.scriptBlock.raw = src.scriptBlock.raw;

        @d.stylesheetBlock = BuilderStylesheetBlock();
        if (src.stylesheetBlock !is null) d.stylesheetBlock.raw = src.stylesheetBlock.raw;

        for (uint i = 0; i < src.nodes.Length; ++i) {
            d.nodes.InsertLast(_CloneNode(src.nodes[i]));
        }

        for (uint i = 0; i < src.diagnostics.Length; ++i) {
            auto inD = src.diagnostics[i];
            if (inD is null) continue;
            auto outD = BuilderDiagnostic();
            outD.code = inD.code;
            outD.severity = inD.severity;
            outD.message = inD.message;
            outD.nodeUid = inD.nodeUid;
            d.diagnostics.InsertLast(outD);
        }

        _RebuildNodeIndex(d);
        return d;
    }

    void _EnsureDoc() {
        if (g_Doc is null) {
            @g_Doc = _NewDocument();
            g_BaselineXml = "";
        }
    }

    void _ResetDocument(BuilderDocument@ doc) {
        if (doc is null) @doc = _NewDocument();
        @g_Doc = doc;
        g_SelectedNodeIx = -1;
        g_UndoSnapshots.Resize(0);
        g_RedoSnapshots.Resize(0);
        g_LastDiff = "";
        g_LastExportXml = "";
        g_BuilderStickyGuides.active = false;
        g_BuilderStickyGuides.verticals.Resize(0);
        g_BuilderStickyGuides.horizontals.Resize(0);
        _RebuildNodeIndex(g_Doc);
    }

    BuilderNode@ _GetSelectedNode() {
        _EnsureDoc();
        if (g_SelectedNodeIx < 0 || g_SelectedNodeIx >= int(g_Doc.nodes.Length)) return null;
        return g_Doc.nodes[uint(g_SelectedNodeIx)];
    }

    bool _IsKnownKind(const string &in kindLower) {
        return kindLower == "frame"
            || kindLower == "quad"
            || kindLower == "label"
            || kindLower == "entry"
            || kindLower == "textedit";
    }

}
}
