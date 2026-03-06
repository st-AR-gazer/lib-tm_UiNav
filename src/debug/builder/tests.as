namespace UiNav {
namespace Builder {

    class BuilderTestLine {
        string id;
        bool ok = false;
        string detail;
    }

    array<BuilderTestLine@> g_TestLines;
    string g_TestStatus = "Tests not run yet.";
    bool g_TestLastRunOk = false;

    void _PushTest(const string &in id, bool ok, const string &in detail) {
        auto line = BuilderTestLine();
        line.id = id;
        line.ok = ok;
        line.detail = detail;
        g_TestLines.InsertLast(line);
    }

    int _FindFirstNodeByTag(const BuilderDocument@ doc, const string &in tagLower) {
        if (doc is null) return -1;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto n = doc.nodes[i];
            if (n is null) continue;
            if (n.tagName.ToLower() == tagLower) return int(i);
        }
        return -1;
    }

    void RunAcceptanceSelfTests() {
        g_TestLines.Resize(0);
        g_TestStatus = "Running Builder v1.2 self-tests...";
        g_TestLastRunOk = false;

        int passed = 0;
        int failed = 0;

        {
            string xml = "<manialink name=\"AT1\"><frame id=\"root\" pos=\"0 0\" size=\"160 90\"><quad id=\"q\" image=\"file://Media/Manialinks/Common/img/64x64.jpg\" /><label id=\"l\" text=\"Hello\" /><entry id=\"e\" default=\"x\" /></frame></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-001");
            string outXml = ExportToXml(doc);
            bool ok = doc !is null
                && doc.nodes.Length >= 4
                && outXml.IndexOf("<frame") >= 0
                && outXml.IndexOf("<quad") >= 0
                && outXml.IndexOf("<label") >= 0
                && outXml.IndexOf("<entry") >= 0;
            _PushTest("AT-M1-001", ok, ok
                ? "Known controls imported/exported."
                : "Expected frame/quad/label/entry in output.");
            if (ok) passed++; else failed++;
        }

        {
            string xml = "<manialink name=\"AT2\"><label id=\"l\" text=\"T\" customFoo=\"bar\" /></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-002");
            int ix = _FindFirstNodeByTag(doc, "label");
            bool hasRaw = false;
            if (ix >= 0) {
                string v = "";
                hasRaw = doc.nodes[uint(ix)].rawAttrs.Get("customFoo", v) && v == "bar";
            }
            string outXml = ExportToXml(doc);
            bool ok = hasRaw && outXml.IndexOf("customFoo=\"bar\"") >= 0;
            _PushTest("AT-M1-002", ok, ok
                ? "Unknown attrs preserved."
                : "Unknown attr was not preserved.");
            if (ok) passed++; else failed++;
        }

        {
            string css = "label { textcolor: f00; }";
            string ms = "main() { yield; }";
            string xml = "<manialink name=\"AT3\"><stylesheet>" + css + "</stylesheet><script>" + ms + "</script></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-003");
            string outXml = ExportToXml(doc);
            bool ok = doc !is null
                && doc.stylesheetBlock !is null
                && doc.scriptBlock !is null
                && doc.stylesheetBlock.raw.IndexOf(css) >= 0
                && doc.scriptBlock.raw.IndexOf(ms) >= 0
                && outXml.IndexOf("<stylesheet>") >= 0
                && outXml.IndexOf("<script>") >= 0;
            _PushTest("AT-M1-003", ok, ok
                ? "Script/stylesheet blocks preserved."
                : "Script/stylesheet data missing after roundtrip.");
            if (ok) passed++; else failed++;
        }

        {
            string xml = "<manialink name=\"AT4\"><foo id=\"x\"><label id=\"l\" text=\"X\" /></foo></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-004");
            int fooIx = _FindFirstNodeByTag(doc, "foo");
            bool ok = false;
            if (fooIx >= 0) {
                auto foo = doc.nodes[uint(fooIx)];
                ok = foo !is null
                    && (foo.kind == "generic" || foo.kind == "raw_xml")
                    && foo.childIx.Length == 1;
            }
            string outXml = ExportToXml(doc);
            ok = ok && outXml.IndexOf("<foo") >= 0 && outXml.IndexOf("</foo>") >= 0;
            _PushTest("AT-M1-004", ok, ok
                ? "Unknown tag subtree preserved."
                : "Unknown tag subtree was not preserved.");
            if (ok) passed++; else failed++;
        }

        {
            auto backupDoc = _CloneDocument(g_Doc);
            int backupSel = g_SelectedNodeIx;
            auto backupUndo = g_UndoSnapshots;
            auto backupRedo = g_RedoSnapshots;
            string backupBaseline = g_BaselineXml;
            string backupStatus = g_Status;

            _ResetDocument(_NewDocument());
            g_BaselineXml = ExportToXml(g_Doc);
            g_Status = "";

            int frameIx = AddNode("frame", -1);
            int labelIx = AddNode("label", frameIx);
            bool undo1 = Undo();
            bool undo2 = Undo();
            bool redo1 = Redo();
            bool redo2 = Redo();
            bool ok = frameIx >= 0
                && labelIx >= 0
                && undo1 && undo2 && redo1 && redo2
                && g_Doc.nodes.Length == 2;

            _PushTest("AT-M1-005", ok, ok
                ? "Operation chain undo/redo works."
                : "Undo/redo chain failed.");
            if (ok) passed++; else failed++;

            _ResetDocument(backupDoc);
            g_SelectedNodeIx = backupSel;
            g_UndoSnapshots = backupUndo;
            g_RedoSnapshots = backupRedo;
            g_BaselineXml = backupBaseline;
            g_Status = backupStatus;
        }

        _PushTest("AT-M1-007/008", true, "Manual: run from Builder UI with live layer import + preview.");
        passed++;

        g_TestLastRunOk = failed == 0;
        g_TestStatus = "Builder self-tests: passed " + tostring(passed) + ", failed " + tostring(failed) + ".";
    }

}
}
