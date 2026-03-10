namespace UiNav {
namespace Builder {

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
    }

}
}
