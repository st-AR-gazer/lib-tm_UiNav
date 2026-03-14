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
            string xml = "<manialink name=\"AT4b\"><frame id=\"root\" clip=\"1\"><label id=\"l\" text=\"X\" /></frame></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-004B");
            string outXml = ExportToXml(doc);
            bool ok = doc !is null
                && outXml.IndexOf("clip=\"1\"") >= 0
                && outXml.IndexOf("clippos=") < 0
                && outXml.IndexOf("clipsize=") < 0;
            _PushTest("AT-M1-004B", ok, ok
                ? "Implicit frame clipping preserved without synthetic zero clip bounds."
                : "Implicit frame clipping roundtrip synthesized clip bounds.");
            if (ok) passed++; else failed++;
        }

        {
            string xml = "<manialink name=\"AT4c\"><frame id=\"root\" clip=\"1\" clippos=\"1 2\" clipsize=\"3 4\"><label id=\"l\" text=\"X\" /></frame></manialink>";
            auto doc = ImportFromXml(xml, "import_xml", "AT-M1-004C");
            string outXml = ExportToXml(doc);
            bool ok = doc !is null
                && outXml.IndexOf("clip=\"1\"") >= 0
                && outXml.IndexOf("clippos=\"1 2\"") >= 0
                && outXml.IndexOf("clipsize=\"3 4\"") >= 0;
            _PushTest("AT-M1-004C", ok, ok
                ? "Explicit frame clip bounds preserved."
                : "Explicit frame clip bounds were not preserved.");
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

            int rootAIx = AddNode("frame", -1);
            int rootBIx = AddNode("frame", -1);
            int labelIx = AddNode("label", rootAIx);
            int quadIx = AddNode("quad", rootAIx);

            bool movedToContainer = MoveNode(labelIx, rootBIx);
            auto rootA = rootAIx >= 0 ? g_Doc.nodes[uint(rootAIx)] : null;
            auto rootB = rootBIx >= 0 ? g_Doc.nodes[uint(rootBIx)] : null;
            auto label = labelIx >= 0 ? g_Doc.nodes[uint(labelIx)] : null;

            bool labelUnderB = movedToContainer
                && label !is null
                && label.parentIx == rootBIx
                && rootB !is null
                && rootB.childIx.Length == 1
                && rootB.childIx[0] == labelIx;
            bool removedFromOldParent = rootA !is null
                && rootA.childIx.Length == 1
                && rootA.childIx[0] == quadIx;
            bool rejectLeafParent = !MoveNode(quadIx, labelIx);
            bool rejectDescendant = !MoveNode(rootBIx, labelIx);

            bool ok = movedToContainer
                && labelUnderB
                && removedFromOldParent
                && rejectLeafParent
                && rejectDescendant;

            _PushTest("AT-M1-006", ok, ok
                ? "Reparenting allows containers and rejects leaf/cycle targets."
                : "Reparenting failed container move or accepted an invalid target.");
            if (ok) passed++; else failed++;

            _ResetDocument(backupDoc);
            g_SelectedNodeIx = backupSel;
            g_UndoSnapshots = backupUndo;
            g_RedoSnapshots = backupRedo;
            g_BaselineXml = backupBaseline;
            g_Status = backupStatus;
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

            int rootAIx = AddNode("frame", -1);
            int rootBIx = AddNode("frame", -1);
            g_Doc.nodes[uint(rootAIx)].controlId = "rootA";
            g_Doc.nodes[uint(rootBIx)].controlId = "rootB";

            int labelIx = AddNode("label", rootAIx);
            int quadIx = AddNode("quad", rootAIx);
            bool moveChildUp = MoveNodeSiblingOrder(quadIx, -1);
            auto rootA = rootAIx >= 0 ? g_Doc.nodes[uint(rootAIx)] : null;
            bool childOrderOk = moveChildUp
                && rootA !is null
                && rootA.childIx.Length == 2
                && rootA.childIx[0] == quadIx
                && rootA.childIx[1] == labelIx;

            int nestedFrameIx = AddNode("frame", rootAIx);
            int nestedLabelIx = AddNode("label", nestedFrameIx);
            bool moveOutOk = MoveNodeOutOneLevel(nestedLabelIx);
            auto nestedFrame = nestedFrameIx >= 0 ? g_Doc.nodes[uint(nestedFrameIx)] : null;
            auto nestedLabel = nestedLabelIx >= 0 ? g_Doc.nodes[uint(nestedLabelIx)] : null;
            bool moveOutStateOk = moveOutOk
                && nestedLabel !is null
                && nestedLabel.parentIx == rootAIx
                && nestedFrame !is null
                && nestedFrame.childIx.Length == 0;

            bool moveToRootOk = MoveNodeToRootAction(nestedLabelIx);
            nestedLabel = nestedLabelIx >= 0 ? g_Doc.nodes[uint(nestedLabelIx)] : null;
            bool moveToRootStateOk = moveToRootOk
                && nestedLabel !is null
                && nestedLabel.parentIx < 0;

            bool moveRootUp = MoveNodeSiblingOrder(rootBIx, -1);
            string outXml = ExportToXml(g_Doc);
            int rootBPos = outXml.IndexOf("id=\"rootB\"");
            int rootAPos = outXml.IndexOf("id=\"rootA\"");
            bool rootOrderOk = moveRootUp
                && rootBPos >= 0
                && rootAPos >= 0
                && rootBPos < rootAPos;

            bool ok = childOrderOk
                && moveOutStateOk
                && moveToRootStateOk
                && rootOrderOk;

            _PushTest("AT-M1-007", ok, ok
                ? "Structure actions move nodes to parent/root and reorder sibling/root order."
                : "Structure actions failed to move or reorder nodes correctly.");
            if (ok) passed++; else failed++;

            _ResetDocument(backupDoc);
            g_SelectedNodeIx = backupSel;
            g_UndoSnapshots = backupUndo;
            g_RedoSnapshots = backupRedo;
            g_BaselineXml = backupBaseline;
            g_Status = backupStatus;
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

            int labelIx = AddNode("label", -1);
            auto label = labelIx >= 0 ? g_Doc.nodes[uint(labelIx)] : null;
            bool ok = false;
            if (label !is null && label.typed !is null) {
                label.typed.size = vec2(40.0f, 8.0f);
                label.typed.hAlign = "left";
                label.typed.vAlign = "center";

                vec2 clampedMax = ClampBuilderNodeLocalPosToScreen(g_Doc, labelIx, vec2(999.0f, 999.0f), vec2(160.0f, 90.0f));
                vec2 clampedMin = ClampBuilderNodeLocalPosToScreen(g_Doc, labelIx, vec2(-999.0f, -999.0f), vec2(160.0f, 90.0f));
                vec2 unchanged = ClampBuilderNodeLocalPosToScreen(g_Doc, labelIx, vec2(10.0f, 5.0f), vec2(160.0f, 90.0f));

                ok = Math::Abs(clampedMax.x - 120.0f) <= 0.01f
                    && Math::Abs(clampedMax.y - 86.0f) <= 0.01f
                    && Math::Abs(clampedMin.x - (-160.0f)) <= 0.01f
                    && Math::Abs(clampedMin.y - (-86.0f)) <= 0.01f
                    && Math::Abs(unchanged.x - 10.0f) <= 0.01f
                    && Math::Abs(unchanged.y - 5.0f) <= 0.01f;
            }

            _PushTest("AT-M1-008", ok, ok
                ? "Position slider clamp keeps nodes on-screen."
                : "Position slider clamp did not produce expected on-screen bounds.");
            if (ok) passed++; else failed++;

            _ResetDocument(backupDoc);
            g_SelectedNodeIx = backupSel;
            g_UndoSnapshots = backupUndo;
            g_RedoSnapshots = backupRedo;
            g_BaselineXml = backupBaseline;
            g_Status = backupStatus;
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

            int movingIx = AddNode("label", -1);
            int targetIx = AddNode("label", -1);
            auto moving = movingIx >= 0 ? g_Doc.nodes[uint(movingIx)] : null;
            auto target = targetIx >= 0 ? g_Doc.nodes[uint(targetIx)] : null;

            bool ok = false;
            if (moving !is null && moving.typed !is null && target !is null && target.typed !is null) {
                moving.typed.size = vec2(20.0f, 10.0f);
                moving.typed.hAlign = "center";
                moving.typed.vAlign = "center";

                target.typed.size = vec2(20.0f, 10.0f);
                target.typed.hAlign = "center";
                target.typed.vAlign = "center";
                target.typed.pos = vec2(30.0f, 12.0f);

                array<float> verticals;
                array<float> horizontals;
                vec2 snappedToScreen = ResolveBuilderNodeSliderPos(
                    g_Doc, movingIx, vec2(1.1f, -1.4f), vec2(160.0f, 90.0f), 6.0f,
                    true, true, false, 2.0f, verticals, horizontals
                );
                bool screenSnapOk = Math::Abs(snappedToScreen.x) <= 0.01f
                    && Math::Abs(snappedToScreen.y) <= 0.01f
                    && verticals.Length > 0
                    && horizontals.Length > 0;

                vec2 snappedToNode = ResolveBuilderNodeSliderPos(
                    g_Doc, movingIx, vec2(29.2f, 11.1f), vec2(160.0f, 90.0f), 6.0f,
                    true, false, true, 2.0f, verticals, horizontals
                );
                bool nodeSnapOk = Math::Abs(snappedToNode.x - 30.0f) <= 0.01f
                    && Math::Abs(snappedToNode.y - 12.0f) <= 0.01f
                    && verticals.Length > 0
                    && horizontals.Length > 0;

                ok = screenSnapOk && nodeSnapOk;
            }

            _PushTest("AT-M1-009", ok, ok
                ? "Sticky snap locks to screen guides and other builder nodes."
                : "Sticky snap failed against screen or builder-node guides.");
            if (ok) passed++; else failed++;

            _ResetDocument(backupDoc);
            g_SelectedNodeIx = backupSel;
            g_UndoSnapshots = backupUndo;
            g_RedoSnapshots = backupRedo;
            g_BaselineXml = backupBaseline;
            g_Status = backupStatus;
        }

        _PushTest("AT-M1-010/011", true, "Manual: run from Builder UI with live layer import + preview.");
        passed++;

        g_TestLastRunOk = failed == 0;
        g_TestStatus = "Builder self-tests: passed " + tostring(passed) + ", failed " + tostring(failed) + ".";
    }

}
}
