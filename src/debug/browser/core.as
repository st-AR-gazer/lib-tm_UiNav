namespace UiNav {
namespace Debug {

    void _MlBrowserFavoritesLoad() {
        g_MlBrowserFavorites.Resize(0);
        string raw = S_MlBrowserFavorites;
        if (raw.Length == 0) return;

        auto lines = raw.Split("\n");
        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i];
            if (ln.EndsWith("\r")) ln = ln.SubStr(0, ln.Length - 1);
            ln = _MlNoteUnesc(ln.Trim());
            if (ln.Length == 0) continue;
            bool dupe = false;
            for (uint j = 0; j < g_MlBrowserFavorites.Length; ++j) {
                if (g_MlBrowserFavorites[j] == ln) {
                    dupe = true;
                    break;
                }
            }
            if (!dupe) g_MlBrowserFavorites.InsertLast(ln);
        }
    }

    void _MlBrowserFavoritesSave() {
        array<string> lines;
        for (uint i = 0; i < g_MlBrowserFavorites.Length; ++i) {
            string u = g_MlBrowserFavorites[i].Trim();
            if (u.Length == 0) continue;
            lines.InsertLast(_MlNoteEsc(u));
        }
        S_MlBrowserFavorites = _JoinParts(lines, "\n");
    }

    void _MlBrowserFavoritesEnsureLoaded() {
        if (g_MlBrowserFavoritesLoaded) return;
        g_MlBrowserFavoritesLoaded = true;
        _MlBrowserFavoritesLoad();
    }

    int _MlBrowserFavoriteIx(const string &in rawUrl) {
        _MlBrowserFavoritesEnsureLoaded();
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return -1;
        for (uint i = 0; i < g_MlBrowserFavorites.Length; ++i) {
            if (g_MlBrowserFavorites[i] == url) return int(i);
        }
        return -1;
    }

    bool _MlBrowserIsFavorite(const string &in rawUrl) {
        return _MlBrowserFavoriteIx(rawUrl) >= 0;
    }

    void _MlBrowserToggleFavorite(const string &in rawUrl) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return;
        int ix = _MlBrowserFavoriteIx(url);
        if (ix >= 0) {
            g_MlBrowserFavorites.RemoveAt(uint(ix));
            _MlBrowserFavoritesSave();
            g_MlBrowserStatus = "Removed favorite: " + url;
            return;
        }
        g_MlBrowserFavorites.InsertLast(url);
        _MlBrowserFavoritesSave();
        g_MlBrowserStatus = "Added favorite: " + url;
    }

    string _MlBrowserFavoriteLabel(const string &in rawUrl) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return "(empty)";
        if (url.StartsWith("file://")) url = url.SubStr(7);
        int slash = url.LastIndexOf("/");
        if (slash >= 0 && slash + 1 < int(url.Length)) return url.SubStr(slash + 1);
        return url;
    }

    void _MlBrowserLog(const string &in msg) {
        if (!S_MlBrowserVerboseLogs) return;
        log(msg, LogLevel::Custom, -1, "UiNav::Browser", "BROWSER", "\\$7cf");
    }

    void _MlBrowserWarn(const string &in msg) {
        if (!S_MlBrowserVerboseLogs) return;
        log(msg, LogLevel::Warning, -1, "UiNav::Browser");
    }

    string _MlBrowserNormalizeUrl(const string &in rawUrl) {
        string url = rawUrl.Trim();
        if (url.Length == 0) return "";
        url = url.Replace("\\", "/");
        if (url.StartsWith("file://")) return url;
        if (url.StartsWith("Media/")) return "file://" + url;
        return url;
    }

    bool _MlBrowserHasAllowedExt(const string &in pathLower) {
        return pathLower.EndsWith(".dds")
            || pathLower.EndsWith(".png")
            || pathLower.EndsWith(".jpg")
            || pathLower.EndsWith(".jpeg")
            || pathLower.EndsWith(".webp")
            || pathLower.EndsWith(".bmp")
            || pathLower.EndsWith(".tga")
            || pathLower.EndsWith(".svg");
    }

    void _MlBrowserAddEntry(dictionary &inout seen, const string &in rawUrl, const string &in source, const string &in kind) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return;
        string key = url.ToLower();
        bool exists = false;
        if (seen.Get(key, exists)) return;
        seen.Set(key, true);

        auto e = MlBrowserEntry();
        e.url = url;
        e.source = source;
        e.kind = kind;
        g_MlBrowserEntries.InsertLast(e);
    }

    void _MlBrowserExtractXmlAttrUrls(const string &in xml, const string &in attr, const string &in source, dictionary &inout seen) {
        if (xml.Length == 0 || attr.Length == 0) return;
        string needle = attr + "=\"";
        int scan = 0;
        while (scan >= 0 && scan < int(xml.Length)) {
            int idx = _IndexOfFrom(xml, needle, scan);
            if (idx < 0) break;
            int start = idx + int(needle.Length);
            int end = _IndexOfFrom(xml, "\"", start);
            if (end < 0 || end <= start) break;
            string value = xml.SubStr(start, end - start).Trim();
            if (value.Length > 0) _MlBrowserAddEntry(seen, value, source, attr);
            scan = end + 1;
        }
    }

    int _MlBrowserCollectFromLayerXml(dictionary &inout seen) {
        int addedBefore = int(g_MlBrowserEntries.Length);
        const int kTimeBudgetMs = 120;
        const int kMaxCharsPerLayer = 350000;
        uint startMs = Time::Now;
        bool timeBudgetHit = false;
        bool xmlCapped = false;

        for (int appKind = 0; appKind <= 2; ++appKind) {
            uint len = _GetMlLayerCount(appKind);
            for (uint i = 0; i < len; ++i) {
                if (int(Time::Now - startMs) > kTimeBudgetMs) {
                    timeBudgetHit = true;
                    break;
                }
                auto layer = _GetMlLayerByIx(appKind, int(i));
                if (layer is null) continue;
                string xml = "";
                try { xml = layer.ManialinkPageUtf8; } catch { xml = ""; }
                if (xml.Length == 0) {
                    try { xml = "" + layer.ManialinkPage; } catch { xml = ""; }
                }
                if (xml.Length == 0) continue;
                if (xml.Length > uint(kMaxCharsPerLayer)) {
                    xml = xml.SubStr(0, kMaxCharsPerLayer);
                    xmlCapped = true;
                }

                string source = _MlAppNameByKind(appKind) + " L[" + i + "]";
                _MlBrowserExtractXmlAttrUrls(xml, "image", source, seen);
                _MlBrowserExtractXmlAttrUrls(xml, "imagefocus", source, seen);
                _MlBrowserExtractXmlAttrUrls(xml, "alphamask", source, seen);
            }
            if (timeBudgetHit) break;
        }

        if (timeBudgetHit || xmlCapped) {
            string suffix = "";
            if (timeBudgetHit) suffix += " live scan budget hit";
            if (xmlCapped) {
                if (suffix.Length > 0) suffix += ";";
                suffix += " XML clipped per layer";
            }
            if (suffix.Length > 0) g_MlBrowserStatus = suffix + ".";
        }

        return int(g_MlBrowserEntries.Length) - addedBefore;
    }

    string _MlBrowserFsPathToUrl(const string &in fsPath) {
        string p = fsPath.Replace("\\", "/");
        string lower = p.ToLower();
        int mediaIx = lower.IndexOf("media/manialinks/");
        if (mediaIx >= 0) {
            string tail = p.SubStr(mediaIx + 17);
            return "file://Media/Manialinks/" + tail;
        }
        return "file://" + p;
    }

    int _MlBrowserCollectFromFilesystem(const string &in rootPath, bool recursive, int maxFiles, dictionary &inout seen) {
        string root = rootPath.Trim();
        if (root.Length == 0 || !IO::FolderExists(root)) return 0;
        if (maxFiles < 1) maxFiles = 1;

        array<string>@ files = IO::IndexFolder(root, recursive);
        if (files is null || files.Length == 0) return 0;

        int addedBefore = int(g_MlBrowserEntries.Length);
        int scanned = 0;
        for (uint i = 0; i < files.Length; ++i) {
            if (scanned >= maxFiles) break;
            string path = files[i];
            string lower = path.ToLower();
            if (!_MlBrowserHasAllowedExt(lower)) continue;
            scanned++;
            _MlBrowserAddEntry(seen, _MlBrowserFsPathToUrl(path), "Filesystem", "file");
        }
        return int(g_MlBrowserEntries.Length) - addedBefore;
    }

    bool _MlBrowserFidsScanShouldStop(MlBrowserFidsScanState@ state) {
        if (state is null) return true;
        if (state.remaining <= 0) {
            state.capped = true;
            return true;
        }
        if (state.timeBudgetMs > 0 && (Time::Now - state.startedAtMs) > state.timeBudgetMs) {
            state.timedOut = true;
            return true;
        }
        return false;
    }

    string _MlBrowserFidsFolderName(CSystemFidsFolder@ folder) {
        if (folder is null) return "";
        string name = "";
        try { name = string(folder.DirName); } catch { name = ""; }
        if (name.Length == 0) {
            try { name = string(folder.FullDirName); } catch { name = ""; }
        }
        name = _MlBrowserCollapseSlashes(name.Replace("\\", "/").Trim());
        while (name.EndsWith("/")) name = name.SubStr(0, name.Length - 1);
        int slash = name.LastIndexOf("/");
        if (slash >= 0 && slash + 1 < int(name.Length)) name = name.SubStr(slash + 1);
        return name.Trim();
    }

    void _MlBrowserCollectFidsNadeoFolderRec(
        CSystemFidsFolder@ folder,
        const string &in relPrefix,
        const string &in source,
        dictionary &inout seen,
        MlBrowserFidsScanState@ state
    ) {
        if (folder is null || _MlBrowserFidsScanShouldStop(state)) return;

        uint leafLen = 0;
        try { leafLen = folder.Leaves.Length; } catch { leafLen = 0; }
        for (uint i = 0; i < leafLen; ++i) {
            if (_MlBrowserFidsScanShouldStop(state)) return;
            CSystemFidFile@ leaf = null;
            try { @leaf = folder.Leaves[i]; } catch { @leaf = null; }
            if (leaf is null) continue;

            string fileName = "";
            try { fileName = string(leaf.FileName); } catch { fileName = ""; }
            if (fileName.Length == 0) continue;
            string lower = fileName.ToLower();
            if (!_MlBrowserHasAllowedExt(lower)) continue;

            string rel = relPrefix.Length > 0 ? relPrefix + "/" + fileName : fileName;
            rel = _MlBrowserCollapseSlashes(rel);
            while (rel.StartsWith("/")) rel = rel.SubStr(1);
            if (rel.Length == 0) continue;

            _MlBrowserAddEntry(seen, "file://Media/Manialinks/Nadeo/" + rel, source, "fid-tree");
            state.remaining--;
        }

        uint treeLen = 0;
        try { treeLen = folder.Trees.Length; } catch { treeLen = 0; }
        for (uint i = 0; i < treeLen; ++i) {
            if (_MlBrowserFidsScanShouldStop(state)) return;
            CSystemFidsFolder@ child = null;
            try { @child = folder.Trees[i]; } catch { @child = null; }
            if (child is null) continue;

            string childName = _MlBrowserFidsFolderName(child);
            if (childName.Length == 0) continue;
            string childRel = relPrefix.Length > 0 ? relPrefix + "/" + childName : childName;
            childRel = _MlBrowserCollapseSlashes(childRel);
            _MlBrowserCollectFidsNadeoFolderRec(child, childRel, source, seen, state);
        }
    }

    bool _MlBrowserCollectNadeoFidsRoot(
        CSystemFidsFolder@ root,
        const string &in source,
        dictionary &inout seen,
        MlBrowserFidsScanState@ state
    ) {
        if (root is null || state is null) return false;
        try { Fids::UpdateTree(root, true); } catch { _MlBrowserLog("Fids::UpdateTree failed for source: " + source); }
        _MlBrowserCollectFidsNadeoFolderRec(root, "", source, seen, state);
        return true;
    }

    int _MlBrowserCollectFromNadeoFidsTree(dictionary &inout seen, string &out note) {
        note = "";
        int addedBefore = int(g_MlBrowserEntries.Length);

        MlBrowserFidsScanState@ state = MlBrowserFidsScanState();
        state.remaining = S_MlBrowserMaxNadeoFidsFiles;
        if (state.remaining < 1) state.remaining = 1;
        state.timeBudgetMs = 650;
        state.startedAtMs = Time::Now;

        bool gotAnyRoot = false;
        {
            CSystemFidsFolder@ root = null;
            try { @root = Fids::GetFakeFolder("Titles/Trackmania/Media/Manialinks/Nadeo"); } catch { @root = null; }
            gotAnyRoot = _MlBrowserCollectNadeoFidsRoot(root, "Fids Fake: Titles/Trackmania/Media/Manialinks/Nadeo", seen, state) || gotAnyRoot;
        }
        {
            CSystemFidsFolder@ root = null;
            try { @root = Fids::GetGameFolder("Media/Manialinks/Nadeo"); } catch { @root = null; }
            gotAnyRoot = _MlBrowserCollectNadeoFidsRoot(root, "Fids Game: Media/Manialinks/Nadeo", seen, state) || gotAnyRoot;
        }
        {
            CSystemFidsFolder@ root = null;
            try { @root = Fids::GetResourceFolder("Media/Manialinks/Nadeo"); } catch { @root = null; }
            gotAnyRoot = _MlBrowserCollectNadeoFidsRoot(root, "Fids Resource: Media/Manialinks/Nadeo", seen, state) || gotAnyRoot;
        }
        {
            CSystemFidsFolder@ root = null;
            try { @root = Fids::GetProgramDataFolder("Media/Manialinks/Nadeo"); } catch { @root = null; }
            gotAnyRoot = _MlBrowserCollectNadeoFidsRoot(root, "Fids ProgramData: Media/Manialinks/Nadeo", seen, state) || gotAnyRoot;
        }
        {
            CSystemFidsFolder@ root = null;
            try { @root = Fids::GetUserFolder("Media/Manialinks/Nadeo"); } catch { @root = null; }
            gotAnyRoot = _MlBrowserCollectNadeoFidsRoot(root, "Fids User: Media/Manialinks/Nadeo", seen, state) || gotAnyRoot;
        }

        if (!gotAnyRoot) note = "No Fids roots found for Media/Manialinks/Nadeo.";
        else if (state.capped) note = "Nadeo Fids scan hit max files cap (" + S_MlBrowserMaxNadeoFidsFiles + ").";
        else if (state.timedOut) note = "Nadeo Fids scan hit time budget; click Refresh again or narrow scope.";

        return int(g_MlBrowserEntries.Length) - addedBefore;
    }

    void _MlBrowserRefresh() {
        g_MlBrowserEntries.Resize(0);
        g_MlBrowserStatus = "";
        dictionary seen;

        int addedLive = 0;
        int addedFs = 0;
        int addedNadeoFids = 0;
        string fidsNote = "";

        if (S_MlBrowserIncludeLiveLayers) addedLive = _MlBrowserCollectFromLayerXml(seen);
        if (S_MlBrowserIncludeNadeoFidsTree) addedNadeoFids = _MlBrowserCollectFromNadeoFidsTree(seen, fidsNote);
        if (S_MlBrowserIncludeFilesystem) addedFs = _MlBrowserCollectFromFilesystem(S_MlBrowserAssetsRoot, S_MlBrowserRecursive, S_MlBrowserMaxFiles, seen);

        g_MlBrowserLastRefreshMs = Time::Now;
        string suffix = g_MlBrowserStatus;
        if (fidsNote.Length > 0) {
            if (suffix.Length > 0) suffix += " ";
            suffix += fidsNote;
        }
        g_MlBrowserStatus = "Loaded " + g_MlBrowserEntries.Length + " URLs (live=" + addedLive + ", fids=" + addedNadeoFids + ", fs=" + addedFs + ").";
        if (suffix.Length > 0) g_MlBrowserStatus += " " + suffix;
        _MlBrowserInvalidateTreeCache();
        _MlBrowserResetPreview();
    }

    bool _MlBrowserEntryMatches(const MlBrowserEntry@ e, const string &in filterLower) {
        if (e is null) return false;
        if (filterLower.Length == 0) return true;
        return e.url.ToLower().IndexOf(filterLower) >= 0
            || e.source.ToLower().IndexOf(filterLower) >= 0
            || e.kind.ToLower().IndexOf(filterLower) >= 0;
    }

    bool _MlBrowserTryGetNadeoRelPath(const string &in rawUrl, string &out relPath) {
        relPath = "";
        string url = _MlBrowserNormalizeUrl(rawUrl);
        const string kPrefixA = "file://Media/Manialinks/Nadeo/";
        if (!url.StartsWith(kPrefixA)) return false;
        relPath = url.SubStr(kPrefixA.Length);

        relPath = _MlBrowserCollapseSlashes(relPath.Trim());
        while (relPath.StartsWith("/")) relPath = relPath.SubStr(1);
        while (relPath.EndsWith("/")) relPath = relPath.SubStr(0, relPath.Length - 1);
        return relPath.Length > 0;
    }

    void _MlBrowserSplitRelPath(const string &in relPath, array<string> &out parts) {
        parts.Resize(0);
        int start = 0;
        int len = int(relPath.Length);
        for (int i = 0; i <= len; ++i) {
            bool atSep = i == len || relPath.SubStr(i, 1) == "/";
            if (!atSep) continue;
            if (i > start) parts.InsertLast(relPath.SubStr(start, i - start));
            start = i + 1;
        }
    }

    bool _MlBrowserTreeComesBefore(const MlBrowserTreeNode@ a, const MlBrowserTreeNode@ b) {
        if (a is null) return false;
        if (b is null) return true;
        if (a.isFile != b.isFile) return !a.isFile;
        string an = a.name.ToLower();
        string bn = b.name.ToLower();
        if (an == bn) return a.name < b.name;
        return an < bn;
    }

    MlBrowserTreeNode@ _MlBrowserTreeGetOrCreateChild(MlBrowserTreeNode@ parent, const string &in name, bool isFile, const string &in key) {
        if (parent is null) return null;
        for (uint i = 0; i < parent.children.Length; ++i) {
            auto c = parent.children[i];
            if (c is null) continue;
            if (c.name == name && c.isFile == isFile) return c;
        }

        if (g_MlBrowserBuildNodeCount >= g_MlBrowserBuildMaxNodes) {
            g_MlBrowserBuildTruncated = true;
            return null;
        }

        auto node = MlBrowserTreeNode();
        node.name = name;
        node.key = key;
        node.isFile = isFile;

        uint insertIx = parent.children.Length;
        for (uint i = 0; i < parent.children.Length; ++i) {
            if (_MlBrowserTreeComesBefore(node, parent.children[i])) {
                insertIx = i;
                break;
            }
        }
        parent.children.InsertAt(insertIx, node);
        g_MlBrowserBuildNodeCount++;
        return node;
    }

    MlBrowserTreeNode@ _MlBrowserBuildNadeoTree(const string &in filterLower, int &out shownFiles, int &out totalFiles, bool &out truncated) {
        shownFiles = 0;
        totalFiles = 0;
        truncated = false;
        const uint kBuildBudgetMs = 40;
        uint startedAt = Time::Now;
        g_MlBrowserBuildMaxNodes = 35000;
        g_MlBrowserBuildNodeCount = 1;
        g_MlBrowserBuildTruncated = false;
        auto root = MlBrowserTreeNode();
        root.name = "Nadeo";
        root.key = "Nadeo";
        root.isFile = false;

        for (uint i = 0; i < g_MlBrowserEntries.Length; ++i) {
            if (Time::Now - startedAt > kBuildBudgetMs) {
                truncated = true;
                break;
            }
            auto e = g_MlBrowserEntries[i];
            if (e is null) continue;
            string relPath = "";
            if (!_MlBrowserTryGetNadeoRelPath(e.url, relPath)) continue;
            totalFiles++;
            if (!_MlBrowserEntryMatches(e, filterLower)) continue;
            shownFiles++;

            array<string> parts;
            _MlBrowserSplitRelPath(relPath, parts);
            if (parts.Length == 0) continue;

            MlBrowserTreeNode@ cur = root;
            string keyAcc = "";
            for (uint p = 0; p < parts.Length; ++p) {
                if (keyAcc.Length > 0) keyAcc += "/";
                keyAcc += parts[p];
                bool isLeaf = p + 1 >= parts.Length;
                auto child = _MlBrowserTreeGetOrCreateChild(cur, parts[p], isLeaf, keyAcc);
                if (child is null) break;
                if (isLeaf) @child.entry = e;
                @cur = child;
            }
            if (g_MlBrowserBuildTruncated) {
                truncated = true;
                break;
            }
        }
        if (g_MlBrowserBuildTruncated) truncated = true;

        return root;
    }

    void _MlBrowserInvalidateTreeCache() {
        @g_MlBrowserTreeCacheRoot = null;
        g_MlBrowserTreeCacheFilter = "";
        g_MlBrowserTreeCacheEntryCount = 0;
        g_MlBrowserTreeCacheShownFiles = 0;
        g_MlBrowserTreeCacheTotalFiles = 0;
        g_MlBrowserTreeCacheTruncated = false;
        g_MlBrowserTreeCacheDirty = true;
    }

    void _MlBrowserEnsureTreeCache(const string &in filterLower) {
        bool needsRebuild = g_MlBrowserTreeCacheDirty
            || g_MlBrowserTreeCacheRoot is null
            || g_MlBrowserTreeCacheFilter != filterLower
            || g_MlBrowserTreeCacheEntryCount != g_MlBrowserEntries.Length;
        if (!needsRebuild) return;

        uint now = Time::Now;
        if (g_MlBrowserTreeCacheRoot !is null && (now - g_MlBrowserTreeLastBuildMs) < 120 && g_MlBrowserTreeCacheFilter != filterLower) {
            return;
        }

        bool truncated = false;
        int shown = 0;
        int total = 0;
        auto root = _MlBrowserBuildNadeoTree(filterLower, shown, total, truncated);
        @g_MlBrowserTreeCacheRoot = root;
        g_MlBrowserTreeCacheFilter = filterLower;
        g_MlBrowserTreeCacheEntryCount = g_MlBrowserEntries.Length;
        g_MlBrowserTreeCacheShownFiles = shown;
        g_MlBrowserTreeCacheTotalFiles = total;
        g_MlBrowserTreeCacheTruncated = truncated;
        g_MlBrowserTreeCacheDirty = false;
        g_MlBrowserTreeLastBuildMs = now;
    }

    void _MlBrowserRenderTreeNode(MlBrowserTreeNode@ node) {
        if (node is null) return;
        UI::PushID("ml-browser-tree-" + node.key);
        if (node.isFile) {
            bool isSel = node.entry !is null && g_MlBrowserSelectedUrl == node.entry.url;
            bool isFav = node.entry !is null && _MlBrowserIsFavorite(node.entry.url);

            string ext = _MlBrowserFileExtension(node.name);
            string color = _MlBrowserFileColorCode(ext);
            string icon = _MlBrowserFileIcon(ext);
            string favStar = isFav ? " \\$ff6" + Icons::Star + "\\$z" : "";
            string label = color + icon + "\\$z " + node.name + favStar;

            if (UI::Selectable(label + "##ml-browser-file", isSel) && node.entry !is null) _MlBrowserSelectUrl(node.entry.url);

            if (isSel) {
                vec4 r = UI::GetItemRect();
                vec4 box = vec4(r.x - 2.0f, r.y - 1.0f, r.z + 2.0f, r.w + 1.0f);
                auto dl = UI::GetWindowDrawList();
                dl.AddRectFilled(box, vec4(0.28f, 0.62f, 1.0f, 0.11f));
                dl.AddRect(box, vec4(0.40f, 0.74f, 1.0f, 0.48f));
            }

            if (UI::IsItemHovered() && node.entry !is null) {
                UI::SetTooltip("Source: " + node.entry.source + "\nKind: " + node.entry.kind
                    + (ext.Length > 0 ? "\nType: " + ext.ToUpper() : "")
                    + "\n" + node.entry.url);
            }
            UI::PopID();
            return;
        }

        int fileCount = 0;
        int folderCount = 0;
        for (uint c = 0; c < node.children.Length; ++c) {
            if (node.children[c] !is null) {
                if (node.children[c].isFile) fileCount++;
                else folderCount++;
            }
        }
        string folderLabel = "\\$cef" + Icons::FolderO + "\\$z " + node.name;
        if (fileCount > 0 || folderCount > 0) {
            folderLabel += " \\$888(" + (fileCount > 0 ? tostring(fileCount) + "f" : "")
                + (fileCount > 0 && folderCount > 0 ? " " : "")
                + (folderCount > 0 ? tostring(folderCount) + "d" : "") + ")\\$z";
        }

        bool open = UI::TreeNode(folderLabel);
        if (open) {
            for (uint i = 0; i < node.children.Length; ++i) {
                _MlBrowserRenderTreeNode(node.children[i]);
            }
            UI::TreePop();
        }
        UI::PopID();
    }

    bool _MlBrowserTryGetSelectedPreviewTextureSize(vec2 &out texSize) {
        texSize = vec2();
        string url = _MlBrowserNormalizeUrl(g_MlBrowserSelectedUrl);
        if (url.Length == 0) return false;
        _MlBrowserEnsurePreviewLoaded();
        if (g_MlBrowserPreviewTextureUrl != url || g_MlBrowserPreviewTexture is null) return false;
        return _MlBrowserTextureHasValidSize(g_MlBrowserPreviewTexture, texSize);
    }

    void _MlBrowserResetPreview() {
        @g_MlBrowserPreviewTexture = null;
        g_MlBrowserPreviewTextureUrl = "";
        g_MlBrowserPreviewError = "";
        g_MlBrowserLoadPreviewRequested = false;
        g_MlBrowserPreviewLoadStartedMs = 0;
        g_MlBrowserPreviewLastAttemptMs = 0;
    }

    void _MlBrowserQueueDdsConversion(const string &in url, const string &in stagedRawPath) {
        string u = _MlBrowserNormalizeUrl(url);
        string raw = stagedRawPath.Trim();
        if (u.Length == 0 || raw.Length == 0) return;
        if (!raw.ToLower().EndsWith(".dds")) return;

        string converted = "";
        if (g_MlBrowserConvertedPathCache.Get(u, converted) && converted.Length > 0 && IO::FileExists(converted)) return;

        if (g_MlBrowserConvertJobRunning) {
            if (g_MlBrowserConvertJobStartedMs > 0 && int(Time::Now - g_MlBrowserConvertJobStartedMs) > 15000) {
                _MlBrowserWarn("DDS conversion worker looked stale; resetting queue state.");
                g_MlBrowserConvertJobRunning = false;
                g_MlBrowserConvertJobUrl = "";
                g_MlBrowserConvertJobRawPath = "";
                g_MlBrowserConvertQueuedUrl = "";
                g_MlBrowserConvertQueuedRawPath = "";
                g_MlBrowserConvertJobStartedMs = 0;
            }
        }

        if (g_MlBrowserConvertJobRunning) {
            if (g_MlBrowserConvertJobUrl == u && g_MlBrowserConvertJobRawPath == raw) return;
            g_MlBrowserConvertQueuedUrl = u;
            g_MlBrowserConvertQueuedRawPath = raw;
            return;
        }

        g_MlBrowserConvertJobRunning = true;
        g_MlBrowserConvertJobStartedMs = Time::Now;
        g_MlBrowserConvertJobUrl = u;
        g_MlBrowserConvertJobRawPath = raw;
        startnew(_MlBrowserRunDdsConversionWorker);
    }

    void _MlBrowserRunDdsConversionWorker() {
        while (g_MlBrowserConvertJobRunning) {
            string url = g_MlBrowserConvertJobUrl;
            string rawPath = g_MlBrowserConvertJobRawPath;
            string outPath = "";
            string err = "";
            bool ok = false;
            try {
                ok = _MlBrowserConvertStagedDdsToLoadable(rawPath, outPath, err);
            } catch {
                err = "DDS conversion worker exception: " + getExceptionInfo();
                ok = false;
            }
            if (ok && outPath.Length > 0 && IO::FileExists(outPath)) {
                g_MlBrowserConvertedPathCache.Set(url, outPath);
                g_MlBrowserConvertedErrorCache.Delete(url);
                _MlBrowserLog("DDS conversion ready: " + outPath);
            } else {
                if (err.Length == 0) err = "Unknown DDS conversion failure.";
                g_MlBrowserConvertedErrorCache.Set(url, err);
                _MlBrowserWarn("DDS conversion failed: " + err + " | " + url);
            }

            g_MlBrowserConvertJobRunning = false;
            g_MlBrowserConvertJobUrl = "";
            g_MlBrowserConvertJobRawPath = "";
            g_MlBrowserConvertJobStartedMs = 0;

            string nextUrl = g_MlBrowserConvertQueuedUrl;
            string nextRaw = g_MlBrowserConvertQueuedRawPath;
            g_MlBrowserConvertQueuedUrl = "";
            g_MlBrowserConvertQueuedRawPath = "";
            if (nextUrl.Length > 0 && nextRaw.Length > 0) {
                g_MlBrowserConvertJobRunning = true;
                g_MlBrowserConvertJobStartedMs = Time::Now;
                g_MlBrowserConvertJobUrl = nextUrl;
                g_MlBrowserConvertJobRawPath = nextRaw;
                yield();
                continue;
            }
            break;
        }
    }

    void _MlBrowserAddLoadCandidate(array<string> &inout outPaths, const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length == 0) return;
        for (uint i = 0; i < outPaths.Length; ++i) {
            if (outPaths[i] == p) return;
        }
        outPaths.InsertLast(p);
    }

    string _MlBrowserExtFromPath(const string &in rawPath) {
        string path = rawPath.Trim().ToLower();
        int slash = path.LastIndexOf("/");
        int dot = path.LastIndexOf(".");
        if (dot >= 0 && dot > slash) return path.SubStr(dot);
        return ".dds";
    }

    string _MlBrowserStorageRoot() {
        return IO::FromStorageFolder("Media/Manialinks");
    }

    bool _MlBrowserIsAbsolutePath(const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length < 1) return false;
        if (p.StartsWith("/") || p.StartsWith("\\")) return true;
        if (p.Length >= 3 && p.SubStr(1, 1) == ":" && (p.SubStr(2, 1) == "/" || p.SubStr(2, 1) == "\\")) return true;
        return false;
    }

    string _MlBrowserOpenplanetRoot() {
        string storageRoot = IO::FromStorageFolder("").Replace("\\", "/");
        while (storageRoot.EndsWith("/")) storageRoot = storageRoot.SubStr(0, storageRoot.Length - 1);
        if (storageRoot.Length == 0) return "";
        string pluginStorage = Path::GetDirectoryName(storageRoot).Replace("\\", "/");
        if (pluginStorage.Length == 0) return "";
        string opRoot = Path::GetDirectoryName(pluginStorage).Replace("\\", "/");
        return opRoot;
    }

    string _MlBrowserBaseName(const string &in rawPath) {
        string p = rawPath.Replace("\\", "/");
        int slash = p.LastIndexOf("/");
        if (slash < 0 || slash + 1 >= int(p.Length)) return p;
        return p.SubStr(slash + 1);
    }

    void _MlBrowserAddRelativeCandidates(array<string> &inout outPaths, const string &in relPath) {
        string rel = relPath.Trim().Replace("\\", "/");
        if (rel.Length == 0) return;
        _MlBrowserAddUniquePath(outPaths, rel);
        _MlBrowserAddUniquePath(outPaths, IO::FromAppFolder(rel));
        _MlBrowserAddUniquePath(outPaths, IO::FromUserGameFolder(rel));

        string opRoot = _MlBrowserOpenplanetRoot();
        if (opRoot.Length > 0) {
            _MlBrowserAddUniquePath(outPaths, opRoot + "/" + rel);
            string leaf = _MlBrowserBaseName(rel);
            if (leaf.Length > 0) _MlBrowserAddUniquePath(outPaths, opRoot + "/" + leaf);
        }
    }

    void _MlBrowserAddCandidateAnyPath(array<string> &inout outPaths, const string &in rawPath) {
        string p = rawPath.Trim().Replace("\\", "/");
        if (p.Length == 0) return;
        if (_MlBrowserIsAbsolutePath(p)) {
            _MlBrowserAddUniquePath(outPaths, p);
            return;
        }
        _MlBrowserAddRelativeCandidates(outPaths, p);
    }

    string _MlBrowserNormalizeExtractKey(const string &in rawKey, const string &in url) {
        string key = _MlBrowserCollapseSlashes(rawKey.Trim().Replace("\\", "/"));
        while (key.StartsWith("/")) key = key.SubStr(1);
        if (key.StartsWith("GameData/")) key = key.SubStr(9);
        if (key.StartsWith("Media/")) key = "Titles/Trackmania/" + key;
        if (!_MlBrowserPathHasExt(key)) key += _MlBrowserExtFromPath(url);
        return key;
    }

    void _MlBrowserBuildExtractPathAttempts(const string &in fidKey, const string &in url, array<string> &out relAttempts, array<string> &out absAttempts) {
        relAttempts.Resize(0);
        absAttempts.Resize(0);

        string canonical = _MlBrowserNormalizeExtractKey(fidKey, url);
        if (canonical.Length > 0) {
            _MlBrowserAddUniquePath(relAttempts, "Extract/" + canonical);
            const string kTitlePrefix = "Titles/Trackmania/";
            if (canonical.StartsWith(kTitlePrefix)) {
                _MlBrowserAddUniquePath(relAttempts, "Extract/" + canonical.SubStr(kTitlePrefix.Length));
            }
        }

        string relFromUrl = _MlBrowserStorageRelPathForUrl(url);
        if (relFromUrl.Length > 0) {
            if (!_MlBrowserPathHasExt(relFromUrl)) relFromUrl += _MlBrowserExtFromPath(url);
            _MlBrowserAddUniquePath(relAttempts, "Extract/Titles/Trackmania/Media/Manialinks/" + relFromUrl);
        }

        string leaf = _MlBrowserBaseName(fidKey);
        if (leaf.Length > 0) _MlBrowserAddUniquePath(relAttempts, "Extract/" + leaf);

        for (uint i = 0; i < relAttempts.Length; ++i) {
            _MlBrowserAddUniquePath(absAttempts, IO::FromDataFolder(relAttempts[i]));
        }
    }

    void _MlBrowserAddExtractPathCandidates(array<string> &inout srcCandidates, const string &in fidKey, const string &in url) {
        array<string> relAttempts;
        array<string> absAttempts;
        _MlBrowserBuildExtractPathAttempts(fidKey, url, relAttempts, absAttempts);
        for (uint i = 0; i < absAttempts.Length; ++i) {
            _MlBrowserAddUniquePath(srcCandidates, absAttempts[i]);
        }
    }

    string _MlBrowserCollapseSlashes(const string &in rawPath) {
        string p = rawPath.Replace("\\", "/");
        while (p.IndexOf("//") >= 0) p = p.Replace("//", "/");
        return p;
    }

    bool _MlBrowserPathHasExt(const string &in rawPath) {
        string p = rawPath.Trim();
        int slash = p.LastIndexOf("/");
        int dot = p.LastIndexOf(".");
        return dot >= 0 && dot > slash;
    }

    string _MlBrowserStorageRelPathForUrl(const string &in rawUrl) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        string p = url;
        if (p.StartsWith("file://")) p = p.SubStr(7);
        p = _MlBrowserCollapseSlashes(p.Trim());
        while (p.StartsWith("/")) p = p.SubStr(1);
        if (p.StartsWith("Media/Manialinks/")) p = p.SubStr(17);
        if (p.Length == 0) p = "_unknown/" + Crypto::MD5(url);
        return p;
    }

    string _MlBrowserStoragePathForUrl(const string &in rawUrl, const string &in extHintPath = "") {
        string rel = _MlBrowserStorageRelPathForUrl(rawUrl);
        if (!_MlBrowserPathHasExt(rel)) {
            string ext = _MlBrowserExtFromPath(extHintPath.Length > 0 ? extHintPath : rawUrl);
            rel += ext;
        }
        return _MlBrowserStorageRoot() + "/" + rel;
    }

    string _MlBrowserDecodedBmpCachePath(const string &in key) {
        string hash = Crypto::MD5(key);
        return _MlBrowserStorageRoot() + "/_decoded/" + hash + ".bmp";
    }

    bool _MlBrowserWriteBufferToFile(const string &in outPath, MemoryBuffer@ buffer) {
        if (buffer is null || buffer.GetSize() == 0) return false;
        string path = outPath.Trim();
        if (path.Length == 0) return false;
        try {
            string folder = Path::GetDirectoryName(path);
            if (folder.Length > 0 && !IO::FolderExists(folder)) IO::CreateFolder(folder, true);
            IO::File f;
            f.Open(path, IO::FileMode::Write);
            f.Write(buffer);
            f.Close();
            return IO::FileExists(path) && IO::FileSize(path) > 0;
        } catch {
            return false;
        }
    }

    string _MlBrowserStageFileForPreview(const string &in sourcePath, const string &in url) {
        string src = sourcePath.Trim();
        if (src.Length == 0) return "";
        if (!IO::FileExists(src)) return "";
        string dst = _MlBrowserStoragePathForUrl(url, src);
        try {
            string folder = Path::GetDirectoryName(dst);
            if (folder.Length > 0 && !IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        } catch {
            _MlBrowserWarn("Could not ensure staging folder for: " + dst);
        }
        bool sameSize = false;
        try {
            if (IO::FileExists(dst)) sameSize = IO::FileSize(dst) == IO::FileSize(src);
        } catch {
            sameSize = false;
        }
        if (sameSize) return dst;
        try {
            if (IO::FileExists(dst)) IO::Delete(dst);
            IO::Copy(src, dst);
        } catch {
            _MlBrowserWarn("Could not stage image into storage: " + src + " -> " + dst);
        }
        if (IO::FileExists(dst)) return dst;
        return "";
    }

    bool _MlBrowserTrySetResolvedPath(const string &in candidate, const string &in url, string &out diskPath) {
        string c = candidate.Trim();
        if (c.Length == 0) return false;
        if (!IO::FileExists(c)) return false;
        string stagedPath = _MlBrowserStageFileForPreview(c, url);
        if (stagedPath.Length == 0) return false;
        g_MlBrowserResolvedPathCache.Set(url, stagedPath);
        diskPath = stagedPath;
        _MlBrowserLog("Resolved internal URL to file: " + diskPath);
        return true;
    }

    void _MlBrowserAddUniquePath(array<string> &inout paths, const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length == 0) return;
        for (uint i = 0; i < paths.Length; ++i) {
            if (paths[i] == p) return;
        }
        paths.InsertLast(p);
    }

    void _MlBrowserAddFidKeyVariants(array<string> &inout keys, const string &in rawPath) {
        string p = rawPath.Trim().Replace("\\", "/");
        while (p.StartsWith("/")) p = p.SubStr(1);
        if (p.Length == 0) return;

        _MlBrowserAddUniquePath(keys, p);
        _MlBrowserAddUniquePath(keys, p.Replace("/", "\\"));

        if (!p.StartsWith("GameData/")) {
            string gd = "GameData/" + p;
            _MlBrowserAddUniquePath(keys, gd);
            _MlBrowserAddUniquePath(keys, gd.Replace("/", "\\"));
        } else if (p.Length > 9) {
            string noGd = p.SubStr(9);
            _MlBrowserAddUniquePath(keys, noGd);
            _MlBrowserAddUniquePath(keys, noGd.Replace("/", "\\"));
        }
    }

    bool _MlBrowserTryExtractFidToDisk(CSystemFidFile@ fid, const string &in fidKey, const string &in url, string &out diskPath) {
        if (fid is null) return false;
        bool extracted = false;
        try { extracted = Fids::Extract(fid, false); } catch { extracted = false; }
        _MlBrowserLog("Fids::Extract(" + fidKey + ", false) => " + (extracted ? "true" : "false"));
        if (!extracted) return false;

        string full = "";
        try { full = Fids::GetFullPath(fid); } catch { full = ""; }
        full = full.Trim().Replace("\\", "/");
        if (_MlBrowserTrySetResolvedPath(full, url, diskPath)) return true;

        if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder(fidKey), url, diskPath)) return true;
        if (!fidKey.StartsWith("GameData/")) {
            if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder("GameData/" + fidKey), url, diskPath)) return true;
        }
        if (_MlBrowserTrySetResolvedPath(IO::FromUserGameFolder(fidKey), url, diskPath)) return true;

        return false;
    }

    bool _MlBrowserTryResolveFromFid(CSystemFidFile@ fid, const string &in fidKey, const string &in url, string &out diskPath) {
        if (fid is null) return false;

        string full = "";
        try { full = Fids::GetFullPath(fid); } catch { full = ""; }
        full = full.Trim().Replace("\\", "/");
        if (_MlBrowserTrySetResolvedPath(full, url, diskPath)) return true;

        bool exists = false;
        try { exists = fid.OSCheckIfExists(); } catch { exists = false; }
        _MlBrowserLog("Fid OSCheckIfExists(" + fidKey + ") => " + (exists ? "true" : "false"));

        if (_MlBrowserTryExtractFidToDisk(fid, fidKey, url, diskPath)) return true;

        if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder(fidKey), url, diskPath)) return true;
        if (!fidKey.StartsWith("GameData/")) {
            if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder("GameData/" + fidKey), url, diskPath)) return true;
        }
        if (_MlBrowserTrySetResolvedPath(IO::FromUserGameFolder(fidKey), url, diskPath)) return true;

        return false;
    }

    bool _MlBrowserTryResolveViaFidKeys(const array<string> &in fidKeys, const string &in url, string &out diskPath) {
        for (uint k = 0; k < fidKeys.Length; ++k) {
            string key = fidKeys[k];
            _MlBrowserLog("Trying fid key: " + key);

            CSystemFidFile@ gameFid = null;
            CSystemFidFile@ resourceFid = null;
            CSystemFidFile@ userFid = null;
            try { @gameFid = Fids::GetGame(key); } catch { @gameFid = null; }
            try { @resourceFid = Fids::GetResource(key); } catch { @resourceFid = null; }
            try { @userFid = Fids::GetUser(key); } catch { @userFid = null; }

            if (gameFid !is null) {
                _MlBrowserLog("  found fid on Game drive");
                if (_MlBrowserTryResolveFromFid(gameFid, key, url, diskPath)) return true;
            }
            if (resourceFid !is null) {
                _MlBrowserLog("  found fid on Resource drive");
                if (_MlBrowserTryResolveFromFid(resourceFid, key, url, diskPath)) return true;
            }
            if (userFid !is null) {
                _MlBrowserLog("  found fid on User drive");
                if (_MlBrowserTryResolveFromFid(userFid, key, url, diskPath)) return true;
            }
        }
        return false;
    }

    bool _MlBrowserTryResolveInternalToDisk(const string &in rawUrl, string &out diskPath) {
        diskPath = "";
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return false;

        string cached = "";
        if (g_MlBrowserResolvedPathCache.Get(url, cached)) {
            if (cached.Length > 0 && IO::FileExists(cached)) {
                diskPath = cached;
                _MlBrowserLog("Using cached resolved file: " + diskPath);
                return true;
            }
        }

        string path = url;
        if (path.StartsWith("file://")) path = path.SubStr(7);
        path = path.Trim().Replace("\\", "/");
        if (path.Length == 0) return false;

        if (_MlBrowserTrySetResolvedPath(path, url, diskPath)) return true;
        if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder(path), url, diskPath)) return true;
        if (_MlBrowserTrySetResolvedPath(IO::FromAppFolder("GameData/" + path), url, diskPath)) return true;
        if (_MlBrowserTrySetResolvedPath(IO::FromUserGameFolder(path), url, diskPath)) return true;

        if (S_MlBrowserUseFidsResolution) {
            array<string> fidKeys;
            _MlBrowserAddFidKeyVariants(fidKeys, path);
            if (_MlBrowserTryResolveViaFidKeys(fidKeys, url, diskPath)) return true;
        } else {
            _MlBrowserLog("Fids resolution disabled; skipping Fids drive lookup.");
        }

        _MlBrowserWarn("Failed to resolve URL to disk path: " + url);
        g_MlBrowserResolvedPathCache.Set(url, "");
        return false;
    }

    bool _MlBrowserTryLoadTextureFromBuffer(const string &in filePath, UI::Texture@ &out texture) {
        @texture = null;
        string path = filePath.Trim();
        if (path.Length == 0 || !IO::FileExists(path)) return false;
        try {
            IO::File f;
            f.Open(path, IO::FileMode::Read);
            uint64 size = f.Size();
            const uint64 kMaxBufferLoadBytes = 32 * 1024 * 1024;
            if (size == 0 || size > kMaxBufferLoadBytes) {
                f.Close();
                if (size > kMaxBufferLoadBytes) {
                    _MlBrowserWarn("Skipping buffer load for large file (" + size + " bytes): " + path);
                }
                return false;
            }
            MemoryBuffer@ buf = f.Read(size);
            f.Close();
            if (buf is null || buf.GetSize() == 0) return false;
            @texture = UI::LoadTexture(buf);
            if (texture !is null) _MlBrowserLog("Loaded texture from memory buffer: " + path);
            else _MlBrowserWarn("UI::LoadTexture(buffer) returned null for: " + path + " (size=" + size + ")");
            return texture !is null;
        } catch {
            _MlBrowserWarn("Exception in buffer texture load for: " + path + " | " + getExceptionInfo());
            @texture = null;
            return false;
        }
    }

    bool _MlBrowserTextureHasValidSize(UI::Texture@ tex, vec2 &out size) {
        size = vec2();
        if (tex is null) return false;
        try { size = tex.GetSize(); } catch { size = vec2(); }
        if (size.x <= 1.0f || size.y <= 1.0f) return false;
        if (size.x > 65536.0f || size.y > 65536.0f) return false;
        return true;
    }

    bool _MlBrowserTryLoadTextureViaDdsDecoder(const string &in filePath, UI::Texture@ &out texture, string &out errorDetails) {
        @texture = null;
        errorDetails = "";
        string path = filePath.Trim();
        if (path.Length == 0 || !IO::FileExists(path)) return false;

        bool maybeDds = path.ToLower().EndsWith(".dds");
        if (!maybeDds) {
            try { maybeDds = IMG::IsDds(path); } catch { maybeDds = false; }
        }
        if (!maybeDds) return false;

        try {
            _MlBrowserLog("Trying DDS decode fallback: " + path);
            IMG::_lastTextureLoadError = "";
            auto dds = IMG::LoadDdsContainer(path);
            if (dds is null || dds.Images.Length == 0) {
                errorDetails = "DDS parse failed: " + IMG::_lastTextureLoadError;
                _MlBrowserWarn(errorDetails + " | " + path);
                return false;
            }
            auto decoded = dds.Images[0].DecompressSize(1024, 1024);
            if (decoded is null) {
                errorDetails = "DDS decode failed: " + IMG::_lastTextureLoadError;
                _MlBrowserWarn(errorDetails + " | " + path);
                return false;
            }
            MemoryBuffer@ bmp = decoded.ToBitmap();
            if (bmp !is null && bmp.GetSize() > 0) {
                string bmpPath = _MlBrowserDecodedBmpCachePath(path);
                if (_MlBrowserWriteBufferToFile(bmpPath, bmp)) {
                    _MlBrowserLog("Wrote decoded DDS BMP cache: " + bmpPath);
                    try {
                        @texture = UI::LoadTexture(bmpPath);
                        if (texture !is null) {
                            _MlBrowserLog("Loaded DDS preview from cached BMP file: " + bmpPath);
                            return true;
                        }
                        _MlBrowserWarn("UI::LoadTexture(path) returned null for decoded BMP: " + bmpPath);
                    } catch {
                        _MlBrowserWarn("Exception loading decoded BMP file texture: " + bmpPath + " | " + getExceptionInfo());
                    }
                }

                try {
                    @texture = UI::LoadTexture(bmp);
                    if (texture !is null) {
                        _MlBrowserLog("Loaded DDS preview directly from decoded BMP buffer.");
                        return true;
                    }
                    _MlBrowserWarn("UI::LoadTexture(decoded BMP buffer) returned null: " + path);
                } catch {
                    _MlBrowserWarn("Exception loading decoded BMP buffer: " + path + " | " + getExceptionInfo());
                }
            }

            @texture = decoded.ToTexture();
            if (texture !is null) {
                _MlBrowserLog("Loaded DDS preview via RawImage::ToTexture fallback.");
                return true;
            }
            errorDetails = "DDS decode produced no loadable texture: " + IMG::_lastTextureLoadError;
            _MlBrowserWarn(errorDetails + " | " + path);
            return false;
        } catch {
            errorDetails = "DDS exception: " + getExceptionInfo();
            _MlBrowserWarn(errorDetails + " | " + path);
            @texture = null;
            return false;
        }
    }

    bool _MlBrowserIsMediaManialinksUrl(const string &in rawUrl) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return false;
        return url.StartsWith("file://Media/Manialinks/");
    }

    string _MlBrowserStorageBmpPathForRaw(const string &in rawPath) {
        string p = rawPath.Trim();
        if (p.Length > 4 && p.ToLower().EndsWith(".dds")) return p.SubStr(0, p.Length - 4) + ".bmp";
        return p + ".bmp";
    }

    bool _MlBrowserIsValidFid(CSystemFidFile@ fid) {
        if (fid is null) return false;
        try { return string(fid.TimeWrite) != "?"; } catch { _MlBrowserLog("Fid.TimeWrite unavailable; falling back to ByteSize."); }
        try { return fid.ByteSize > 0; } catch { return true; }
        return true;
    }

    string _MlBrowserFidDebugMeta(CSystemFidFile@ fid) {
        if (fid is null) return "fid=null";
        string tw = "?";
        uint size = 0;
        string fn = "";
        try { tw = string(fid.TimeWrite); } catch { tw = "?"; }
        try { size = fid.ByteSize; } catch { size = 0; }
        try { fn = string(fid.FileName); } catch { fn = ""; }
        return "TimeWrite=" + tw + ", ByteSize=" + size + ", FileName=" + fn;
    }

    bool _MlBrowserCanUseFidExtract() {
        bool canExtract = false;
        try { canExtract = OpenplanetHasFullPermissions(); } catch { canExtract = false; }
        return canExtract;
    }

    string _MlBrowserDataExtractRelPathForUrl(const string &in url) {
        string rel = _MlBrowserStorageRelPathForUrl(url);
        if (!_MlBrowserPathHasExt(rel)) rel += _MlBrowserExtFromPath(url);
        return "Extract/Titles/Trackmania/Media/Manialinks/" + rel;
    }

    void _MlBrowserAddFidSourceCandidates(array<string> &inout srcCandidates, CSystemFidFile@ fid, const string &in fidKey) {
        if (fid is null) return;

        string full = "";
        try { full = Fids::GetFullPath(fid); } catch { full = ""; }
        if (full.Length > 0) _MlBrowserAddCandidateAnyPath(srcCandidates, full);

        string fullFileName = "";
        try { fullFileName = string(fid.FullFileName); } catch { fullFileName = ""; }
        fullFileName = fullFileName.Replace("\\", "/").Trim();
        if (fullFileName.StartsWith("file://")) fullFileName = fullFileName.SubStr(7);
        if (fullFileName.Length > 0) _MlBrowserAddCandidateAnyPath(srcCandidates, fullFileName);

        string fileName = "";
        try { fileName = string(fid.FileName); } catch { fileName = ""; }
        fileName = fileName.Replace("\\", "/").Trim();
        if (fileName.StartsWith("file://")) fileName = fileName.SubStr(7);
        if (fileName.Length > 0) {
            _MlBrowserAddCandidateAnyPath(srcCandidates, fileName);
            _MlBrowserAddCandidateAnyPath(srcCandidates, "GameData/" + fileName);
        }

        _MlBrowserAddCandidateAnyPath(srcCandidates, fidKey);
        if (!fidKey.StartsWith("GameData/")) _MlBrowserAddCandidateAnyPath(srcCandidates, "GameData/" + fidKey);
    }

    bool _MlBrowserTryStageFromFid(CSystemFidFile@ fid, const string &in fidKey, const string &in url, string &out stagedRawPath) {
        stagedRawPath = "";
        if (fid is null) return false;
        array<string> srcCandidates;
        _MlBrowserAddFidSourceCandidates(srcCandidates, fid, fidKey);
        _MlBrowserAddExtractPathCandidates(srcCandidates, fidKey, url);

        array<string> relExtractAttempts;
        array<string> absExtractAttempts;
        _MlBrowserBuildExtractPathAttempts(fidKey, url, relExtractAttempts, absExtractAttempts);
        for (uint i = 0; i < relExtractAttempts.Length; ++i) {
            string relExtract = relExtractAttempts[i];
            string absExtract = i < absExtractAttempts.Length ? absExtractAttempts[i] : IO::FromDataFolder(relExtract);
            bool copiedRel = false;
            try {
                string outFolder = Path::GetDirectoryName(absExtract);
                if (outFolder.Length > 0 && !IO::FolderExists(outFolder)) IO::CreateFolder(outFolder, true);
                fid.CopyToFileRelative(relExtract, false);
                copiedRel = IO::FileExists(absExtract) && IO::FileSize(absExtract) > 0;
            } catch {
                copiedRel = false;
            }
            _MlBrowserLog("fid.CopyToFileRelative(" + relExtract + ") => " + (copiedRel ? "true" : "false"));
            if (!copiedRel) continue;

            string staged = _MlBrowserStageFileForPreview(absExtract, url);
            if (staged.Length > 0 && IO::FileExists(staged)) {
                stagedRawPath = staged;
                _MlBrowserLog("Staged media URL to storage via CopyToFileRelative: " + stagedRawPath);
                return true;
            }
            _MlBrowserAddUniquePath(srcCandidates, absExtract);
        }

        bool extracted = false;
        bool validFid = _MlBrowserIsValidFid(fid);
        if (!validFid) {
            _MlBrowserLog("Skipping Fids::Extract on invalid fid: " + fidKey + " | " + _MlBrowserFidDebugMeta(fid));
        } else if (!_MlBrowserCanUseFidExtract()) {
            _MlBrowserLog("Skipping Fids::Extract (OpenplanetHasFullPermissions=false): " + fidKey);
        } else {
            try { extracted = Fids::Extract(fid, false); } catch { extracted = false; }
            _MlBrowserLog("Fids::Extract(" + fidKey + ", false) => " + (extracted ? "true" : "false"));
        }
        if (extracted) {
            _MlBrowserAddFidSourceCandidates(srcCandidates, fid, fidKey);
            _MlBrowserAddExtractPathCandidates(srcCandidates, fidKey, url);
        }

        for (uint i = 0; i < srcCandidates.Length; ++i) {
            string src = srcCandidates[i];
            if (src.Length == 0 || !IO::FileExists(src)) continue;
            string staged = _MlBrowserStageFileForPreview(src, url);
            if (staged.Length == 0 || !IO::FileExists(staged)) continue;
            stagedRawPath = staged;
            _MlBrowserLog("Staged media URL to storage: " + stagedRawPath);
            return true;
        }
        if (extracted) {
            _MlBrowserWarn("Extract succeeded but no readable source candidate was found: " + fidKey);
            if (S_MlBrowserVerboseLogs) {
                uint maxDump = Math::Min(srcCandidates.Length, 12);
                for (uint i = 0; i < maxDump; ++i) {
                    string src = srcCandidates[i];
                    bool exists = src.Length > 0 && IO::FileExists(src);
                    _MlBrowserLog("  post-extract candidate[" + i + "] exists=" + (exists ? "true" : "false") + " :: " + src);
                }
            }
        }
        return false;
    }

    bool _MlBrowserTryStageMediaWithGetFlow(const string &in key, const string &in url, string &out stagedRawPath) {
        stagedRawPath = "";
        string path = key.Trim().Replace("\\", "/");
        while (path.StartsWith("/")) path = path.SubStr(1);
        if (path.Length == 0) return false;

        array<string> gameKeys;
        if (!path.StartsWith("GameData/")) gameKeys.InsertLast("GameData/" + path);
        gameKeys.InsertLast(path);

        for (uint i = 0; i < gameKeys.Length; ++i) {
            string gameKey = gameKeys[i];
            CSystemFidFile@ fid = null;
            try { @fid = Fids::GetGame(gameKey); } catch { @fid = null; }
            if (fid is null) {
                _MlBrowserLog("GetGame miss: " + gameKey);
                continue;
            }
            _MlBrowserLog("GetGame hit: " + gameKey + " | valid=" + (_MlBrowserIsValidFid(fid) ? "true" : "false") + " | " + _MlBrowserFidDebugMeta(fid));
            if (_MlBrowserTryStageFromFid(fid, gameKey, url, stagedRawPath)) return true;
        }

        {
            array<string> fakeKeys;
            if (!path.StartsWith("Titles/Trackmania/")) fakeKeys.InsertLast("Titles/Trackmania/" + path);
            fakeKeys.InsertLast(path);
            for (uint i = 0; i < fakeKeys.Length; ++i) {
                string fakeKey = fakeKeys[i];
                CSystemFidFile@ fid = null;
                try { @fid = Fids::GetFake(fakeKey); } catch { @fid = null; }
                if (fid is null) {
                    _MlBrowserLog("GetFake miss: " + fakeKey);
                    continue;
                }
                _MlBrowserLog("GetFake hit: " + fakeKey + " | valid=" + (_MlBrowserIsValidFid(fid) ? "true" : "false") + " | " + _MlBrowserFidDebugMeta(fid));
                if (_MlBrowserTryStageFromFid(fid, fakeKey, url, stagedRawPath)) return true;
            }
        }

        {
            CSystemFidFile@ fid = null;
            try { @fid = Fids::GetProgramData(path); } catch { @fid = null; }
            if (fid !is null) {
                _MlBrowserLog("GetProgramData hit: " + path + " | valid=" + (_MlBrowserIsValidFid(fid) ? "true" : "false") + " | " + _MlBrowserFidDebugMeta(fid));
                if (_MlBrowserTryStageFromFid(fid, path, url, stagedRawPath)) return true;
            } else {
                _MlBrowserLog("GetProgramData miss: " + path);
            }
        }

        {
            CSystemFidFile@ fid = null;
            try { @fid = Fids::GetResource(path); } catch { @fid = null; }
            if (fid !is null) {
                _MlBrowserLog("GetResource hit: " + path + " | valid=" + (_MlBrowserIsValidFid(fid) ? "true" : "false") + " | " + _MlBrowserFidDebugMeta(fid));
                if (_MlBrowserTryStageFromFid(fid, path, url, stagedRawPath)) return true;
            } else {
                _MlBrowserLog("GetResource miss: " + path);
            }
        }

        {
            CSystemFidFile@ fid = null;
            try { @fid = Fids::GetUser(path); } catch { @fid = null; }
            if (fid !is null) {
                _MlBrowserLog("GetUser hit: " + path + " | valid=" + (_MlBrowserIsValidFid(fid) ? "true" : "false") + " | " + _MlBrowserFidDebugMeta(fid));
                if (_MlBrowserTryStageFromFid(fid, path, url, stagedRawPath)) return true;
            } else {
                _MlBrowserLog("GetUser miss: " + path);
            }
        }

        return false;
    }

    bool _MlBrowserExtractMediaUrlToStorageRaw(const string &in rawUrl, string &out stagedRawPath, string &out errorDetails) {
        stagedRawPath = "";
        errorDetails = "";
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (!_MlBrowserIsMediaManialinksUrl(url)) {
            errorDetails = "URL is not under file://Media/Manialinks/";
            return false;
        }

        string rel = _MlBrowserStorageRelPathForUrl(url);
        string mediaKey = "Media/Manialinks/" + rel;
        string alreadyStaged = _MlBrowserStoragePathForUrl(url, mediaKey);
        if (IO::FileExists(alreadyStaged)) {
            stagedRawPath = alreadyStaged;
            return true;
        }

        array<string> fidKeys = {mediaKey};

        for (uint k = 0; k < fidKeys.Length; ++k) {
            string key = fidKeys[k];
            _MlBrowserLog("Trying media fid key: " + key);
            if (_MlBrowserTryStageMediaWithGetFlow(key, url, stagedRawPath)) return true;
        }

        errorDetails = "Failed to extract Media/Manialinks fid to storage path.";
        if (!_MlBrowserCanUseFidExtract()) errorDetails += " Openplanet full permissions are required for Fids::Extract.";
        return false;
    }

    MemoryBuffer@ _MlBrowserRawImageToBmpBuffer(IMG::RawImage@ raw, string &out errorDetails) {
        errorDetails = "";
        if (raw is null) {
            errorDetails = "Decoded image was null.";
            return null;
        }

        int srcW = raw.Width;
        int srcH = raw.Height;
        if (srcW <= 0 || srcH <= 0) {
            errorDetails = "Decoded image has invalid dimensions.";
            return null;
        }

        int expectedBytes = srcW * srcH * 4;
        if (expectedBytes <= 0 || raw.Data.Length < expectedBytes) {
            errorDetails = "Decoded image buffer is invalid.";
            return null;
        }

        int dstW = srcW;
        int dstH = srcH;
        const int kMaxPreviewDim = 1024;
        if (srcW > kMaxPreviewDim || srcH > kMaxPreviewDim) {
            float sx = float(kMaxPreviewDim) / float(srcW);
            float sy = float(kMaxPreviewDim) / float(srcH);
            float scale = Math::Min(sx, sy);
            dstW = Math::Max(1, int(Math::Round(float(srcW) * scale)));
            dstH = Math::Max(1, int(Math::Round(float(srcH) * scale)));
            _MlBrowserLog("Downscaling decoded DDS preview " + srcW + "x" + srcH + " -> " + dstW + "x" + dstH);
        }

        MemoryBuffer@ target = MemoryBuffer();

        target.Write("BM");
        uint bmpBytes = uint(14 + 40 + 2 + dstW * dstH * 4);
        target.Write(bmpBytes);
        target.Write(uint(0));
        target.Write(14 + 40 + 2);

        target.Write(uint(40));
        target.Write(dstW);
        target.Write(-dstH);
        target.Write(uint16(1));
        target.Write(uint16(32));
        target.Write(uint(0));
        target.Write(uint(dstW * dstH * 4));
        target.Write(0);
        target.Write(0);
        target.Write(uint(0));
        target.Write(uint(0));
        target.Write(uint16(0));

        const int kYieldEveryRows = 16;

        if (dstW == srcW && dstH == srcH) {
            for (int y = 0; y < dstH; ++y) {
                int rowBase = y * srcW * 4;
                for (int x = 0; x < dstW; ++x) {
                    int si = rowBase + x * 4;
                    target.Write(raw.Data[si + 2]);
                    target.Write(raw.Data[si + 1]);
                    target.Write(raw.Data[si + 0]);
                    target.Write(raw.Data[si + 3]);
                }
                if ((y & (kYieldEveryRows - 1)) == (kYieldEveryRows - 1)) yield();
            }
        } else {
            for (int y = 0; y < dstH; ++y) {
                int sy = (y * srcH) / dstH;
                int srcRow = sy * srcW * 4;
                for (int x = 0; x < dstW; ++x) {
                    int sxPx = (x * srcW) / dstW;
                    int si = srcRow + sxPx * 4;
                    target.Write(raw.Data[si + 2]);
                    target.Write(raw.Data[si + 1]);
                    target.Write(raw.Data[si + 0]);
                    target.Write(raw.Data[si + 3]);
                }
                if ((y & (kYieldEveryRows - 1)) == (kYieldEveryRows - 1)) yield();
            }
        }

        return target;
    }

    bool _MlBrowserConvertStagedDdsToLoadable(const string &in stagedRawPath, string &out loadPath, string &out errorDetails) {
        loadPath = stagedRawPath.Trim();
        errorDetails = "";
        if (loadPath.Length == 0 || !IO::FileExists(loadPath)) {
            errorDetails = "Staged raw path missing.";
            return false;
        }
        if (!loadPath.ToLower().EndsWith(".dds")) return true;

        uint64 ddsSize = 0;
        try { ddsSize = IO::FileSize(loadPath); } catch { ddsSize = 0; }
        if (ddsSize == 0) {
            errorDetails = "DDS file is empty.";
            return false;
        }
        const uint64 kMaxDecodeSize = 96 * 1024 * 1024;
        if (ddsSize > kMaxDecodeSize) {
            errorDetails = "DDS file too large to decode safely (" + ddsSize + " bytes).";
            return false;
        }

        bool isDds = false;
        try { isDds = IMG::IsDds(loadPath); } catch { isDds = false; }
        if (!isDds) {
            errorDetails = "Staged file is not recognized as DDS.";
            return false;
        }

        string bmpPath = _MlBrowserStorageBmpPathForRaw(loadPath);
        if (IO::FileExists(bmpPath) && IO::FileSize(bmpPath) > 0) {
            loadPath = bmpPath;
            return true;
        }

        try {
            IMG::_lastTextureLoadError = "";
            auto dds = IMG::LoadDdsContainer(loadPath);
            if (dds is null || dds.Images.Length == 0) {
                errorDetails = "DDS parse failed: " + IMG::_lastTextureLoadError;
                return false;
            }

            auto decoded = dds.Images[0].DecompressSize(1024, 1024);
            if (decoded is null) {
                errorDetails = "DDS decode failed: " + IMG::_lastTextureLoadError;
                return false;
            }

            auto bmp = _MlBrowserRawImageToBmpBuffer(decoded, errorDetails);
            if (bmp is null || bmp.GetSize() == 0) {
                if (errorDetails.Length == 0) errorDetails = "DDS decode produced empty bitmap.";
                return false;
            }

            if (!_MlBrowserWriteBufferToFile(bmpPath, bmp)) {
                errorDetails = "Failed to write decoded BMP to storage.";
                return false;
            }
        } catch {
            errorDetails = "DDS conversion exception: " + getExceptionInfo();
            return false;
        }

        loadPath = bmpPath;
        _MlBrowserLog("Decoded DDS and wrote loadable preview: " + loadPath);
        return true;
    }

    bool _MlBrowserPrepareStoragePreviewPath(const string &in rawUrl, string &out previewPath, string &out errorDetails) {
        previewPath = "";
        errorDetails = "";
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) {
            errorDetails = "Empty URL.";
            return false;
        }

        string stagedRaw = "";
        if (_MlBrowserIsMediaManialinksUrl(url)) {
            if (!_MlBrowserExtractMediaUrlToStorageRaw(url, stagedRaw, errorDetails)) return false;
        } else {
            string path = url.StartsWith("file://") ? url.SubStr(7) : url;
            string staged = _MlBrowserStageFileForPreview(path, url);
            if (staged.Length == 0) {
                errorDetails = "Could not stage non-media URL into storage.";
                return false;
            }
            stagedRaw = staged;
        }

        if (!stagedRaw.ToLower().EndsWith(".dds")) {
            previewPath = stagedRaw;
            return true;
        }

        string convertedPath = "";
        if (g_MlBrowserConvertedPathCache.Get(url, convertedPath) && convertedPath.Length > 0 && IO::FileExists(convertedPath)) {
            previewPath = convertedPath;
            return true;
        }

        previewPath = stagedRaw;
        return true;
    }

    void _MlBrowserBuildLoadCandidates(const string &in rawUrl, array<string> &inout outPaths) {
        outPaths.Resize(0);
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return;
        string previewPath = "";
        string prepErr = "";
        if (_MlBrowserPrepareStoragePreviewPath(url, previewPath, prepErr) && previewPath.Length > 0) {
            _MlBrowserAddLoadCandidate(outPaths, previewPath);
        } else {
            string fallback = _MlBrowserStoragePathForUrl(url, url);
            _MlBrowserAddLoadCandidate(outPaths, fallback);
            if (prepErr.Length > 0) _MlBrowserWarn(prepErr + " | " + url);
        }

        _MlBrowserLog("Load candidates for " + url + ": " + outPaths.Length);
        if (S_MlBrowserVerboseLogs) {
            for (uint i = 0; i < outPaths.Length; ++i) {
                _MlBrowserLog("  candidate[" + i + "] = " + outPaths[i]);
            }
        }
    }

    void _MlBrowserEnsurePreviewLoaded() {
        if (!g_MlBrowserLoadPreviewRequested) return;
        string url = g_MlBrowserSelectedUrl.Trim();
        if (url.Length == 0) {
            _MlBrowserResetPreview();
            return;
        }
        if (g_MlBrowserPreviewTextureUrl == url && g_MlBrowserPreviewTexture !is null) {
            vec2 texSize = vec2();
            if (_MlBrowserTextureHasValidSize(g_MlBrowserPreviewTexture, texSize)) return;
            if (g_MlBrowserPreviewLoadStartedMs > 0 && int(Time::Now - g_MlBrowserPreviewLoadStartedMs) < 1500) return;
        }
        if (g_MlBrowserPreviewTextureUrl == url && g_MlBrowserPreviewError.Length > 0) {
            string convertedPath = "";
            bool hasNewConverted = g_MlBrowserConvertedPathCache.Get(url, convertedPath) && convertedPath.Length > 0 && IO::FileExists(convertedPath);
            if (!hasNewConverted) {
                string convertErr = "";
                if (g_MlBrowserConvertedErrorCache.Get(url, convertErr) && convertErr.Length > 0) {
                    g_MlBrowserPreviewError = "Could not load this image as a UI texture. DDS conversion failed: " + convertErr;
                }
                return;
            }
        }
        if (g_MlBrowserPreviewTextureUrl == url) {
            if (g_MlBrowserPreviewLastAttemptMs > 0 && int(Time::Now - g_MlBrowserPreviewLastAttemptMs) < 250) return;
            if (g_MlBrowserConvertJobRunning && g_MlBrowserConvertJobUrl == url) {
                if (g_MlBrowserPreviewLastAttemptMs > 0 && int(Time::Now - g_MlBrowserPreviewLastAttemptMs) < 750) return;
            }
        }

        @g_MlBrowserPreviewTexture = null;
        g_MlBrowserPreviewTextureUrl = url;
        g_MlBrowserPreviewError = "";
        g_MlBrowserPreviewLastAttemptMs = Time::Now;
        g_MlBrowserPreviewLoadStartedMs = g_MlBrowserPreviewLastAttemptMs;

        array<string> candidates;
        _MlBrowserBuildLoadCandidates(url, candidates);
        bool queuedDdsConversion = false;
        UI::Texture@ pendingTexture = null;
        string pendingTextureSource = "";
        for (uint i = 0; i < candidates.Length; ++i) {
            string candidate = candidates[i];
            try {
                auto tex = UI::LoadTexture(candidate);
                if (tex !is null) {
                    vec2 texSize = vec2();
                    if (_MlBrowserTextureHasValidSize(tex, texSize)) {
                        _MlBrowserLog("Loaded texture from path candidate: " + candidate + " (" + texSize.x + "x" + texSize.y + ")");
                        @g_MlBrowserPreviewTexture = tex;
                        return;
                    }
                    if (pendingTexture is null) {
                        @pendingTexture = tex;
                        pendingTextureSource = candidate;
                    }
                    _MlBrowserWarn("Loaded path texture had invalid size: " + candidate);
                }
                _MlBrowserWarn("UI::LoadTexture(path) returned null for candidate: " + candidate);
            } catch {
                _MlBrowserWarn("Exception in UI::LoadTexture(path) for candidate: " + candidate + " | " + getExceptionInfo());
            }

            UI::Texture@ texFromBuf = null;
            if (_MlBrowserTryLoadTextureFromBuffer(candidate, texFromBuf) && texFromBuf !is null) {
                vec2 texSize = vec2();
                if (_MlBrowserTextureHasValidSize(texFromBuf, texSize)) {
                    _MlBrowserLog("Using buffer-loaded texture: " + candidate + " (" + texSize.x + "x" + texSize.y + ")");
                    @g_MlBrowserPreviewTexture = texFromBuf;
                    return;
                }
                if (pendingTexture is null) {
                    @pendingTexture = texFromBuf;
                    pendingTextureSource = candidate + " (buffer)";
                }
                _MlBrowserWarn("Loaded buffer texture had invalid size: " + candidate);
            }

            if (candidate.ToLower().EndsWith(".dds")) {
                _MlBrowserQueueDdsConversion(url, candidate);
                queuedDdsConversion = true;
            }
        }

        if (queuedDdsConversion) {
            string convertErr = "";
            if (g_MlBrowserConvertedErrorCache.Get(url, convertErr) && convertErr.Length > 0) {
                g_MlBrowserPreviewError = "Could not load this image as a UI texture. DDS conversion failed: " + convertErr;
            } else {
                g_MlBrowserPreviewError = "Preparing DDS preview fallback...";
            }
            return;
        }

        if (pendingTexture !is null) {
            @g_MlBrowserPreviewTexture = pendingTexture;
            g_MlBrowserPreviewError = "Texture loaded but reported invalid size (best effort).";
            _MlBrowserWarn("Using pending-size texture: " + pendingTextureSource);
            return;
        }

        g_MlBrowserPreviewError = "Could not load this image as a UI texture.";
        _MlBrowserWarn("All preview load methods failed for URL: " + url);
    }

    void _MlBrowserSelectUrl(const string &in url) {
        string normalized = _MlBrowserNormalizeUrl(url);
        if (g_MlBrowserSelectedUrl == normalized) return;
        g_MlBrowserSelectedUrl = normalized;
        @g_MlBrowserPreviewTexture = null;
        g_MlBrowserPreviewTextureUrl = "";
        g_MlBrowserPreviewError = "";
        g_MlBrowserLoadPreviewRequested = S_MlBrowserAutoPreview;
        g_MlBrowserPreviewLoadStartedMs = 0;
        g_MlBrowserPreviewLastAttemptMs = 0;
    }

    MlBrowserEntry@ _MlBrowserGetSelectedEntry() {
        string selected = g_MlBrowserSelectedUrl;
        if (selected.Length == 0) return null;
        for (uint i = 0; i < g_MlBrowserEntries.Length; ++i) {
            auto e = g_MlBrowserEntries[i];
            if (e is null) continue;
            if (e.url == selected) return e;
        }
        return null;
    }

    string _MlBrowserPreviewLoadingFrame() {
        uint frame = (Time::Now / 120) % 4;
        if (frame == 0) return "|";
        if (frame == 1) return "/";
        if (frame == 2) return "-";
        return "\\";
    }

    bool _MlBrowserIsPreviewLoading(const string &in rawUrl) {
        if (!g_MlBrowserLoadPreviewRequested) return false;
        string url = _MlBrowserNormalizeUrl(rawUrl);
        if (url.Length == 0) return false;
        if (g_MlBrowserConvertJobRunning && g_MlBrowserConvertJobUrl == url) return true;
        if (g_MlBrowserPreviewTextureUrl != url) return false;
        if (g_MlBrowserPreviewTexture is null) return true;

        vec2 texSize = vec2();
        if (!_MlBrowserTextureHasValidSize(g_MlBrowserPreviewTexture, texSize)) return true;
        return false;
    }

    void _MlBrowserRenderPreviewLoadingUi(const string &in rawUrl) {
        string url = _MlBrowserNormalizeUrl(rawUrl);
        int elapsedSec = 0;
        if (g_MlBrowserPreviewLoadStartedMs > 0) {
            elapsedSec = int(Time::Now - g_MlBrowserPreviewLoadStartedMs) / 1000;
        }
        string msg = "Loading preview " + _MlBrowserPreviewLoadingFrame();
        if (g_MlBrowserConvertJobRunning && g_MlBrowserConvertJobUrl == url) msg += " (DDS decode)";
        if (elapsedSec > 0) msg += " " + elapsedSec + "s";
        UI::Text("\\$ff0" + msg + "\\$z");
        UI::TextDisabled("Large assets can take a few seconds to stage/decode.");
    }

    

}
}
