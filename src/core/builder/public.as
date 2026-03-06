namespace UiNav {
namespace Builder {

    int _FirstRootIx(const BuilderDocument@ doc) {
        if (doc is null) return -1;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto node = doc.nodes[i];
            if (node !is null && node.parentIx < 0) return int(i);
        }
        return -1;
    }

    void _FinalizeDocument(BuilderDocument@ doc) {
        if (doc is null) return;
        if (doc.scriptBlock is null) @doc.scriptBlock = BuilderScriptBlock();
        if (doc.stylesheetBlock is null) @doc.stylesheetBlock = BuilderStylesheetBlock();
        _RebuildNodeIndex(doc);
        if (doc.rootIx < 0 || doc.rootIx >= int(doc.nodes.Length)) {
            doc.rootIx = _FirstRootIx(doc);
        } else {
            auto root = doc.nodes[uint(doc.rootIx)];
            if (root is null || root.parentIx >= 0) doc.rootIx = _FirstRootIx(doc);
        }
    }

    string _NormalizePublicKind(const string &in kindRaw) {
        string kind = kindRaw.Trim().ToLower();
        if (kind.Length == 0) return "frame";
        if (_IsKnownKind(kind)) return kind;
        return "generic";
    }

    void _EnsureNodeDefaults(BuilderNode@ node) {
        if (node is null) return;
        if (node.typed is null) @node.typed = _NewTypedProps();

        string rawTag = node.tagName.Trim();
        string kind = _NormalizePublicKind(node.kind);
        if (kind == "generic" && rawTag.Length > 0 && rawTag.ToLower() != "generic") {
            node.kind = "generic";
        } else {
            node.kind = kind;
        }

        if (node.kind != "generic") {
            node.tagName = node.kind;
        } else if (rawTag.Length == 0) {
            node.tagName = "frame";
        }

        if (node.uid.Length == 0) {
            node.uid = "n" + (g_NextUid++);
        }
    }

    bool _DocUidExists(const BuilderDocument@ doc, const string &in uid) {
        if (doc is null || uid.Length == 0) return false;
        int dummy = -1;
        return doc.nodeByUid.Get(uid, dummy);
    }

    int _SiblingCount(const BuilderDocument@ doc, int parentIx) {
        if (doc is null) return 0;
        if (parentIx < 0) return _CountRootNodes(doc);
        if (parentIx >= int(doc.nodes.Length)) return 0;
        auto parent = doc.nodes[uint(parentIx)];
        if (parent is null) return 0;
        return int(parent.childIx.Length);
    }

    BuilderDocument@ NewDocument() {
        auto doc = _NewDocument();
        _FinalizeDocument(doc);
        return doc;
    }

    BuilderDocument@ CloneDocument(const BuilderDocument@ src) {
        auto doc = _CloneDocument(src);
        _FinalizeDocument(doc);
        return doc;
    }

    BuilderNode@ NewNode(const string &in kind = "frame") {
        string normalizedKind = _NormalizePublicKind(kind);
        auto node = _NewNode(normalizedKind);
        if (normalizedKind == "generic") {
            string rawTag = kind.Trim().ToLower();
            node.tagName = rawTag.Length == 0 ? "frame" : rawTag;
        } else {
            node.tagName = normalizedKind;
        }
        _EnsureNodeDefaults(node);
        _InitAuthoringDefaults(node, 0);
        return node;
    }

    BuilderDocument@ ImportXml(const string &in xmlText, const string &in sourceKind = "import_xml", const string &in sourceLabel = "") {
        auto doc = ImportFromXml(xmlText, sourceKind, sourceLabel);
        _FinalizeDocument(doc);
        return doc;
    }

    string ExportXml(const BuilderDocument@ doc) {
        return ExportToXml(doc);
    }

    int AppendRoot(BuilderDocument@ doc, BuilderNode@ node) {
        return AppendChild(doc, -1, node);
    }

    int AppendChild(BuilderDocument@ doc, int parentIx, BuilderNode@ node) {
        if (doc is null || node is null) return -1;

        _FinalizeDocument(doc);
        if (parentIx >= int(doc.nodes.Length)) return -1;

        if (parentIx >= 0) {
            auto parent = doc.nodes[uint(parentIx)];
            if (!_NodeCanContainChildren(parent)) return -1;
        }

        _EnsureNodeDefaults(node);
        if (_DocUidExists(doc, node.uid)) node.uid = "n" + (g_NextUid++);

        node.parentIx = parentIx;
        node.childIx.Resize(0);

        int ix = int(doc.nodes.Length);
        doc.nodes.InsertLast(node);
        if (parentIx >= 0) {
            auto parent = doc.nodes[uint(parentIx)];
            if (parent !is null) parent.childIx.InsertLast(ix);
        }

        doc.nodeByUid.Set(node.uid, ix);
        if (parentIx < 0 && doc.rootIx < 0) doc.rootIx = ix;
        doc.dirty = true;
        return ix;
    }

    void _MarkDeleteRecursiveDoc(const BuilderDocument@ doc, int nodeIx, array<bool> &inout marks) {
        if (doc is null) return;
        if (nodeIx < 0 || nodeIx >= int(marks.Length)) return;
        if (marks[uint(nodeIx)]) return;
        marks[uint(nodeIx)] = true;

        auto node = doc.nodes[uint(nodeIx)];
        if (node is null) return;
        for (uint i = 0; i < node.childIx.Length; ++i) {
            _MarkDeleteRecursiveDoc(doc, node.childIx[i], marks);
        }
    }

    bool DeleteNode(BuilderDocument@ doc, int nodeIx) {
        if (doc is null) return false;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return false;

        array<bool> marks;
        marks.Resize(doc.nodes.Length);
        for (uint i = 0; i < marks.Length; ++i) marks[i] = false;
        _MarkDeleteRecursiveDoc(doc, nodeIx, marks);

        array<int> remap;
        remap.Resize(doc.nodes.Length);
        for (uint i = 0; i < remap.Length; ++i) remap[i] = -1;

        array<BuilderNode@> newNodes;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            if (marks[i]) continue;
            remap[i] = int(newNodes.Length);
            newNodes.InsertLast(_CloneNode(doc.nodes[i]));
        }

        for (uint i = 0; i < newNodes.Length; ++i) {
            auto node = newNodes[i];
            if (node is null) continue;
            if (node.parentIx >= 0) node.parentIx = remap[uint(node.parentIx)];

            array<int> children;
            for (uint c = 0; c < node.childIx.Length; ++c) {
                int oldIx = node.childIx[c];
                if (oldIx < 0 || oldIx >= int(remap.Length)) continue;
                int mapped = remap[uint(oldIx)];
                if (mapped >= 0) children.InsertLast(mapped);
            }
            node.childIx = children;
        }

        doc.nodes = newNodes;
        doc.dirty = true;
        _FinalizeDocument(doc);
        return true;
    }

    bool _IsAncestorDoc(const BuilderDocument@ doc, int nodeIx, int maybeAncestor) {
        if (doc is null) return false;
        if (nodeIx < 0 || maybeAncestor < 0) return false;
        if (nodeIx >= int(doc.nodes.Length) || maybeAncestor >= int(doc.nodes.Length)) return false;

        int cur = nodeIx;
        while (cur >= 0 && cur < int(doc.nodes.Length)) {
            if (cur == maybeAncestor) return true;
            auto node = doc.nodes[uint(cur)];
            if (node is null) break;
            cur = node.parentIx;
        }
        return false;
    }

    bool MoveNode(BuilderDocument@ doc, int nodeIx, int newParentIx) {
        if (doc is null) return false;
        if (nodeIx < 0 || nodeIx >= int(doc.nodes.Length)) return false;
        if (newParentIx >= int(doc.nodes.Length)) return false;
        if (newParentIx == nodeIx) return false;
        if (newParentIx >= 0 && _IsAncestorDoc(doc, newParentIx, nodeIx)) return false;

        auto node = doc.nodes[uint(nodeIx)];
        if (node is null) return false;
        int oldParent = node.parentIx;
        if (oldParent == newParentIx) return true;

        if (newParentIx >= 0) {
            auto parent = doc.nodes[uint(newParentIx)];
            if (!_NodeCanContainChildren(parent)) return false;
        }

        if (oldParent >= 0) {
            auto oldNode = doc.nodes[uint(oldParent)];
            if (oldNode !is null) {
                for (uint i = 0; i < oldNode.childIx.Length; ++i) {
                    if (oldNode.childIx[i] == nodeIx) {
                        oldNode.childIx.RemoveAt(i);
                        break;
                    }
                }
            }
        }

        node.parentIx = newParentIx;
        if (newParentIx >= 0) {
            auto newParent = doc.nodes[uint(newParentIx)];
            if (newParent !is null) newParent.childIx.InsertLast(nodeIx);
        }

        doc.dirty = true;
        _FinalizeDocument(doc);
        return true;
    }

    int FindFirstById(const BuilderDocument@ doc, const string &in controlId) {
        if (doc is null || controlId.Length == 0) return -1;
        for (uint i = 0; i < doc.nodes.Length; ++i) {
            auto node = doc.nodes[i];
            if (node !is null && node.controlId == controlId) return int(i);
        }
        return -1;
    }

    bool _NodeHasClass(const BuilderNode@ node, const string &in cls) {
        if (node is null || cls.Length == 0) return false;
        for (uint i = 0; i < node.classes.Length; ++i) {
            if (node.classes[i] == cls) return true;
        }
        return false;
    }

    bool _MatchSelectorTok(const BuilderNode@ node, UiNav::ML::_Tok@ tok) {
        if (node is null || tok is null) return false;
        if (tok.isAny) return true;
        if (tok.isId) return node.controlId == tok.id;
        if (tok.isClass) return _NodeHasClass(node, tok.cls);
        return false;
    }

    int _PickNthMatchAmongChildren(const BuilderDocument@ doc, int parentIx, UiNav::ML::_Tok@ tok) {
        if (doc is null || tok is null) return -1;
        if (parentIx < 0 || parentIx >= int(doc.nodes.Length)) return -1;

        auto parent = doc.nodes[uint(parentIx)];
        if (parent is null) return -1;

        if (tok.isIndex) {
            if (tok.index < 0) return -1;
            uint ix = uint(tok.index);
            if (ix >= parent.childIx.Length) return -1;
            return parent.childIx[ix];
        }

        int wantNth = tok.nth;
        int found = 0;
        for (uint i = 0; i < parent.childIx.Length; ++i) {
            int childIx = parent.childIx[i];
            if (childIx < 0 || childIx >= int(doc.nodes.Length)) continue;
            auto child = doc.nodes[uint(childIx)];
            if (_MatchSelectorTok(child, tok)) {
                if (found == wantNth) return childIx;
                found++;
            }
        }
        return -1;
    }

    int _PickNthMatchDescendant(const BuilderDocument@ doc, int rootIx, UiNav::ML::_Tok@ tok) {
        if (doc is null || tok is null) return -1;
        if (rootIx < 0 || rootIx >= int(doc.nodes.Length)) return -1;

        array<int> q;
        q.InsertLast(rootIx);

        int wantNth = tok.nth;
        int found = 0;
        uint head = 0;
        while (head < q.Length) {
            int curIx = q[head++];
            if (curIx < 0 || curIx >= int(doc.nodes.Length)) continue;
            auto cur = doc.nodes[uint(curIx)];
            if (cur is null) continue;

            if (!tok.isIndex && _MatchSelectorTok(cur, tok)) {
                if (found == wantNth) return curIx;
                found++;
            }

            for (uint i = 0; i < cur.childIx.Length; ++i) {
                q.InsertLast(cur.childIx[i]);
            }
        }

        return -1;
    }

    int ResolveSelector(const BuilderDocument@ doc, const string &in selector, int startIx = -1) {
        if (doc is null) return -1;
        string sel = selector.Trim();
        if (sel.Length == 0) return -1;

        auto toks = UiNav::ML::_GetTokChainCached(sel);
        if (toks is null || toks.Length == 0) return -1;

        int curIx = startIx;
        if (curIx < 0) curIx = doc.rootIx >= 0 ? doc.rootIx : _FirstRootIx(doc);
        if (curIx < 0 || curIx >= int(doc.nodes.Length)) return -1;

        for (uint i = 0; i < toks.Length; ++i) {
            auto tok = toks[i];
            if (tok is null) return -1;
            curIx = tok.descendant
                ? _PickNthMatchDescendant(doc, curIx, tok)
                : _PickNthMatchAmongChildren(doc, curIx, tok);
            if (curIx < 0) return -1;
        }

        return curIx;
    }

    int StripFrameClipping(BuilderDocument@ doc) {
        if (doc is null) return 0;
        int changed = _SetFrameClipActiveInDoc(doc, false);
        if (changed > 0) doc.dirty = true;
        return changed;
    }

    bool CenterRoots(BuilderDocument@ doc) {
        if (doc is null) return false;
        bool changed = _CenterDocumentRoots(doc);
        if (changed) doc.dirty = true;
        return changed;
    }

    BuilderDocument@ CloneLiveLayer(const ManiaLinkReq@ req, bool stripFrameClipping = true, bool centerRoots = false) {
        if (req is null) return null;

        int layerIx = -1;
        auto layer = UiNav::Layers::FindLayer(req, layerIx);
        if (layer is null || layer.LocalPage is null || layer.LocalPage.MainFrame is null) return null;

        auto doc = _NewDocument();
        doc.sourceKind = "import_live_tree";
        doc.sourceLabel = "source=" + tostring(int(req.source)) + " layer=" + layerIx;
        doc.originalXml = _GetLayerXml(layer);

        auto st = _LiveTreeCloneState();
        _AppendLiveTreeNode(doc, layer.LocalPage.MainFrame, -1, 0, st);
        if (st.truncated) {
            _AddDiag(doc, "clone.truncated", "warn", "Live tree clone truncated at node/depth budget.");
        }

        _FinalizeDocument(doc);
        if (stripFrameClipping) _SetFrameClipActiveInDoc(doc, false);
        if (centerRoots) _CenterDocumentRoots(doc);
        doc.dirty = false;
        return doc;
    }

    CGameUILayer@ MountOwned(const string &in key, const BuilderDocument@ doc, ManiaLinkSource source = ManiaLinkSource::CurrentApp, bool visible = true) {
        if (doc is null) return null;
        string xml = ExportXml(doc);
        if (xml.Length == 0) return null;
        return UiNav::Layers::EnsureOwned(key, xml, source, visible);
    }

}
}
