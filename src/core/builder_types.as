namespace UiNav {
namespace Builder {

    shared enum BuilderNodeKind {
        Frame = 0,
        Quad = 1,
        Label = 2,
        Entry = 3,
        TextEdit = 4,
        Generic = 5,
        RawXml = 6,
        Unknown = 7
    }

    shared enum BuilderDiagnosticSeverity {
        Info = 0,
        Warn = 1,
        Error = 2,
        Unknown = 3
    }

    shared enum BuilderSourceKind {
        NewDoc = 0,
        ImportXml = 1,
        ImportJson = 2,
        ImportJsonFile = 3,
        ImportLiveLayer = 4,
        ImportLiveTree = 5,
        Unknown = 6
    }

    shared class BuilderSourceSpan {
        int start = -1;
        int end = -1;
    }

    shared class BuilderFidelity {
        int level = 0; // 0 = full, 1 = partial, 2 = raw_only
        array<string> reasons;
    }

    shared class BuilderDiagnostic {
        string code;
        string severity; // info|warn|error
        string message;
        string nodeUid;

        BuilderDiagnosticSeverity SeverityEnum() const {
            string sev = severity.ToLower();
            if (sev == "info") return BuilderDiagnosticSeverity::Info;
            if (sev == "warn") return BuilderDiagnosticSeverity::Warn;
            if (sev == "error") return BuilderDiagnosticSeverity::Error;
            return BuilderDiagnosticSeverity::Unknown;
        }
    }

    shared class BuilderScriptBlock {
        string raw;
    }

    shared class BuilderStylesheetBlock {
        string raw;
    }

    shared class BuilderTypedProps {
        vec2 size = vec2(80.0f, 8.0f);
        vec2 pos = vec2(0.0f, 0.0f);
        float z = 0.0f;
        float scale = 1.0f;
        float rot = 0.0f;
        bool visible = true;
        string hAlign = "left";
        string vAlign = "center";

        bool clipActive = false;
        vec2 clipPos = vec2();
        vec2 clipSize = vec2();
        bool clipPosExplicit = false;
        bool clipSizeExplicit = false;

        string image;
        string imageFocus;
        string alphaMask;
        string style;
        string subStyle;
        string bgColor;
        string bgColorFocus;
        string modulateColor;
        string colorize;
        float opacity = 1.0f;
        int keepRatioMode = 0;
        int blendMode = 0;

        string text;
        float textSize = 1.0f;
        string textFont;
        string textPrefix;
        string textColor = "fff";
        int maxLine = 0;
        bool autoNewLine = false;
        float lineSpacing = 0.0f;
        float italicSlope = 0.0f;
        bool appendEllipsis = false;

        string value;
        int textFormat = 0;
        int maxLength = 0;
    }

    shared class BuilderNode {
        string uid;
        string kind; // frame|quad|label|entry|textedit|generic|raw_xml
        string controlId;
        string tagName;
        int parentIx = -1;
        array<int> childIx;
        BuilderTypedProps@ typed;
        dictionary rawAttrs;
        array<string> classes;
        bool scriptEvents = false;
        BuilderFidelity fidelity;
        BuilderSourceSpan span;

        BuilderNodeKind KindEnum() const {
            string k = kind.ToLower();
            if (k == "frame") return BuilderNodeKind::Frame;
            if (k == "quad") return BuilderNodeKind::Quad;
            if (k == "label") return BuilderNodeKind::Label;
            if (k == "entry") return BuilderNodeKind::Entry;
            if (k == "textedit") return BuilderNodeKind::TextEdit;
            if (k == "generic") return BuilderNodeKind::Generic;
            if (k == "raw_xml") return BuilderNodeKind::RawXml;
            return BuilderNodeKind::Unknown;
        }

        void SetKind(BuilderNodeKind value) {
            if (value == BuilderNodeKind::Frame) {
                kind = "frame";
                tagName = "frame";
            } else if (value == BuilderNodeKind::Quad) {
                kind = "quad";
                tagName = "quad";
            } else if (value == BuilderNodeKind::Label) {
                kind = "label";
                tagName = "label";
            } else if (value == BuilderNodeKind::Entry) {
                kind = "entry";
                tagName = "entry";
            } else if (value == BuilderNodeKind::TextEdit) {
                kind = "textedit";
                tagName = "textedit";
            } else if (value == BuilderNodeKind::RawXml) {
                kind = "raw_xml";
                tagName = "raw_xml";
            } else {
                kind = "generic";
                if (tagName.Trim().Length == 0 || tagName.ToLower() == "generic") {
                    tagName = "frame";
                }
            }
        }
    }

    shared class BuilderDocument {
        string format = "uinav_builder_doc";
        string schemaVersion = "1.2";
        string name = "UiNav_Builder";
        string sourceKind = "new"; // new|import_xml|import_live_layer|import_live_tree
        string sourceLabel;
        int rootIx = -1;
        array<BuilderNode@> nodes;
        dictionary nodeByUid;
        array<BuilderDiagnostic@> diagnostics;
        BuilderScriptBlock@ scriptBlock;
        BuilderStylesheetBlock@ stylesheetBlock;
        string originalXml;
        bool dirty = false;

        BuilderSourceKind SourceKindEnum() const {
            string kind = sourceKind.ToLower();
            if (kind == "new") return BuilderSourceKind::NewDoc;
            if (kind == "import_xml") return BuilderSourceKind::ImportXml;
            if (kind == "import_json") return BuilderSourceKind::ImportJson;
            if (kind == "import_json_file") return BuilderSourceKind::ImportJsonFile;
            if (kind == "import_live_layer") return BuilderSourceKind::ImportLiveLayer;
            if (kind == "import_live_tree") return BuilderSourceKind::ImportLiveTree;
            return BuilderSourceKind::Unknown;
        }

        int RootCount() const {
            int count = 0;
            for (uint i = 0; i < nodes.Length; ++i) {
                auto node = nodes[i];
                if (node !is null && node.parentIx < 0) count++;
            }
            return count;
        }

        int RootNodeIx(int ordinal) const {
            if (ordinal < 0) return -1;
            int seen = 0;
            for (uint i = 0; i < nodes.Length; ++i) {
                auto node = nodes[i];
                if (node is null || node.parentIx >= 0) continue;
                if (seen == ordinal) return int(i);
                seen++;
            }
            return -1;
        }

        bool HasMultipleRoots() const {
            return RootCount() > 1;
        }

        bool SetPrimaryRoot(int nodeIx) {
            if (nodeIx < 0 || nodeIx >= int(nodes.Length)) return false;
            auto node = nodes[uint(nodeIx)];
            if (node is null || node.parentIx >= 0) return false;
            rootIx = nodeIx;
            return true;
        }
    }

}
}
