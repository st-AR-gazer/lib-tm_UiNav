namespace UiNav {
namespace Debug {

    string _MlBrowserFileExtension(const string &in name) {
        int dot = -1;
        for (int i = int(name.Length) - 1; i >= 0; --i) {
            if (name.SubStr(i, 1) == ".") { dot = i; break; }
        }
        if (dot < 0) return "";
        return name.SubStr(dot + 1).ToLower();
    }

    string _MlBrowserFileColorCode(const string &in ext) {
        if (ext == "dds") return "\\$fcb";  // pink
        if (ext == "png") return "\\$9fd";  // cyan
        if (ext == "jpg" || ext == "jpeg") return "\\$bff"; // light blue
        if (ext == "tga") return "\\$fd8";  // orange
        if (ext == "webp") return "\\$dfc"; // mint
        if (ext == "bmp") return "\\$fdc";  // peach
        return "\\$ddd"; // gray
    }

    string _MlBrowserFileIcon(const string &in ext) {
        if (ext == "dds" || ext == "png" || ext == "jpg" || ext == "jpeg"
            || ext == "tga" || ext == "webp" || ext == "bmp")
            return Icons::FileImageO;
        return Icons::FileO;
    }

    string _MlBrowserShortTileLabel(const string &in rawLabel, uint maxChars = 22) {
        string label = rawLabel.Trim();
        int maxCharsInt = int(maxChars);
        if (int(label.Length) > maxCharsInt && maxCharsInt > 3) {
            label = label.SubStr(0, maxCharsInt - 3) + "...";
        }
        return label;
    }

    void _MlBrowserRenderFolderGridTile(const MlBrowserEntry@ entry, int index, float tileW, float tileH) {
        if (entry is null) return;

        UI::PushID("ml-browser-folder-tile-" + index);
        bool activateRequested = false;
        bool tileHovered = false;
        bool tileOpen = UI::BeginChild(
            "##ml-browser-folder-tile",
            vec2(tileW, tileH),
            true,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (tileOpen) {
            float thumbH = Math::Max(72.0f, tileH - 34.0f);
            bool thumbOpen = UI::BeginChild(
                "##ml-browser-folder-thumb",
                vec2(0, thumbH),
                true,
                UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
            );
            if (thumbOpen) {
                UI::Texture@ tex = null;
                string err = "";
                bool loading = false;
                bool hasTex = _MlBrowserTryGetThumbTexture(entry.url, tex, err, loading);
                if (hasTex && tex !is null) {
                    vec2 texSize = vec2();
                    if (_MlBrowserTextureHasValidSize(tex, texSize)) {
                        float availW = Math::Max(32.0f, UI::GetContentRegionAvail().x);
                        float availH = Math::Max(32.0f, UI::GetContentRegionAvail().y);
                        float drawW = availW;
                        float drawH = drawW * (texSize.y / texSize.x);
                        if (drawH > availH && drawH > 0.0f) {
                            float scale = availH / drawH;
                            drawH = availH;
                            drawW *= scale;
                        }
                        if (drawW > availW && drawW > 0.0f) {
                            float scale = availW / drawW;
                            drawW = availW;
                            drawH *= scale;
                        }
                        float padX = Math::Max(0.0f, (availW - drawW) * 0.5f);
                        float padY = Math::Max(0.0f, (availH - drawH) * 0.5f);
                        if (padY > 0.0f) UI::Dummy(vec2(0.0f, padY));
                        if (padX > 0.0f) {
                            UI::Dummy(vec2(padX, 0.0f));
                            UI::SameLine();
                        }
                        UI::ImageWithBg(tex, vec2(drawW, drawH), vec2(0, 0), vec2(1, 1), vec4(0.20f, 0.20f, 0.20f, 1.0f), vec4(1, 1, 1, 1));
                    } else {
                        UI::TextDisabled("No preview");
                    }
                } else if (loading) {
                    string loadLine1 = "";
                    string loadLine2 = "";
                    if (_MlBrowserGetLoadingInfo(entry.url, loadLine1, loadLine2)) {
                        UI::TextDisabled(loadLine1);
                        if (loadLine2.Length > 0) UI::TextDisabled(loadLine2);
                    } else {
                        UI::TextDisabled("Loading preview " + _MlBrowserPreviewLoadingFrame());
                    }
                } else {
                    UI::TextDisabled(err.Length > 0 ? err : "No preview");
                }
            }
            UI::EndChild();
            bool thumbHovered = UI::IsItemHovered();
            if (thumbHovered && UI::IsMouseClicked(UI::MouseButton::Left)) activateRequested = true;
            tileHovered = tileHovered || thumbHovered;

            string ext = _MlBrowserFileExtension(entry.url);
            string label = _MlBrowserShortTileLabel(_MlBrowserEntryLabel(entry));
            UI::Text(_MlBrowserFileColorCode(ext) + _MlBrowserFileIcon(ext) + "\\$z " + label);
            bool labelHovered = UI::IsItemHovered();
            if (labelHovered && UI::IsMouseClicked(UI::MouseButton::Left)) activateRequested = true;
            tileHovered = tileHovered || labelHovered;
        }
        UI::EndChild();
        if (tileHovered) {
            UI::SetTooltip(entry.url);
            UI::SetMouseCursor(UI::MouseCursor::Hand);
        }
        if (activateRequested) _MlBrowserSelectUrl(entry.url);
        UI::PopID();
    }

    bool _MlBrowserRenderFolderPreviewPane() {
        if (g_MlBrowserSelectedFolderKey.Length == 0) return false;

        string folderName = g_MlBrowserSelectedFolderName.Length > 0 ? g_MlBrowserSelectedFolderName : g_MlBrowserSelectedFolderKey;
        UI::Text("\\$cef" + Icons::FolderOpenO + "\\$z " + folderName);
        if (UI::IsItemHovered()) UI::SetTooltip(g_MlBrowserSelectedFolderKey);
        UI::SameLine();
        UI::BeginDisabled(!_MlBrowserCanGoBack());
        if (UI::Button(Icons::ArrowLeft + " Back##ml-browser-folder-back")) {
            _MlBrowserGoBack();
            UI::EndDisabled();
            return true;
        }
        UI::EndDisabled();
        if (UI::IsItemHovered()) UI::SetTooltip("Return to the previous browser view");
        UI::SameLine();
        if (UI::Button(Icons::Times + " Clear folder##ml-browser-folder-clear")) {
            _MlBrowserClearFolderSelection();
            return true;
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Return to single-file preview mode");
        UI::Separator();

        array<MlBrowserEntry@> entries;
        _MlBrowserCollectEntriesForFolderKey(g_MlBrowserSelectedFolderKey, entries);
        if (entries.Length == 0) {
            UI::TextDisabled("No image files found under this folder.");
            return true;
        }

        UI::TextDisabled(Icons::FileImageO + " " + entries.Length + " files");
        float availW = Math::Max(180.0f, UI::GetContentRegionAvail().x);
        float spacing = 8.0f;
        float minTileW = 180.0f;
        int cols = Math::Max(1, int(Math::Floor((availW + spacing) / (minTileW + spacing))));
        float tileW = Math::Floor((availW - spacing * (cols - 1)) / cols);
        if (tileW < 144.0f) tileW = 144.0f;
        float tileH = tileW + 34.0f;
        float rowH = tileH + spacing;

        bool gridOpen = UI::BeginChild("##ml-browser-folder-grid", vec2(0, 0), false);
        if (gridOpen) {
            int totalRows = int(Math::Ceil(float(entries.Length) / float(cols)));
            float scrollY = UI::GetScrollY();
            float viewH = Math::Max(1.0f, UI::GetWindowSize().y);
            int firstRow = Math::Max(0, int(Math::Floor(scrollY / Math::Max(1.0f, rowH))) - 1);
            int visibleRows = Math::Max(1, int(Math::Ceil(viewH / Math::Max(1.0f, rowH))) + 2);
            int lastRow = Math::Min(totalRows, firstRow + visibleRows);

            if (firstRow > 0) UI::Dummy(vec2(0, firstRow * rowH));
            for (int row = firstRow; row < lastRow; ++row) {
                int startIx = row * cols;
                int endIx = Math::Min(int(entries.Length), startIx + cols);
                for (int i = startIx; i < endIx; ++i) {
                    if (i > startIx) UI::SameLine();
                    _MlBrowserRenderFolderGridTile(entries[uint(i)], i, tileW, tileH);
                }
            }
            if (lastRow < totalRows) {
                UI::Dummy(vec2(0, (totalRows - lastRow) * rowH));
            }
        }
        UI::EndChild();
        return true;
    }

    void _MlBrowserRenderPreviewPane() {
        if (_MlBrowserRenderFolderPreviewPane()) return;
        if (g_MlBrowserSelectedUrl.Length == 0) {
            UI::TextDisabled("Select an image URL to preview it.");
            UI::TextDisabled("Browse the tree on the left, or use search to filter.");
            return;
        }

        string urlLabel = g_MlBrowserSelectedUrl;
        if (urlLabel.Length > 160) urlLabel = urlLabel.SubStr(0, 157) + "...";
        UI::TextWrapped(urlLabel);
        if (UI::IsItemHovered()) UI::SetTooltip(g_MlBrowserSelectedUrl);

        UI::BeginDisabled(!_MlBrowserCanGoBack());
        if (UI::Button(Icons::ArrowLeft + " Back##ml-browser-back")) {
            _MlBrowserGoBack();
            UI::EndDisabled();
            return;
        }
        UI::EndDisabled();
        if (UI::IsItemHovered()) UI::SetTooltip("Return to the previous browser view");

        UI::SameLine();
        if (UI::Button(Icons::Clipboard + " Copy##ml-browser-copy")) IO::SetClipboard(g_MlBrowserSelectedUrl);
        if (UI::IsItemHovered()) UI::SetTooltip("Copy URL to clipboard");

        UI::SameLine();
        if (UI::Button(Icons::Play + " Load##ml-browser-load")) {
            @g_MlBrowserPreviewTexture = null;
            g_MlBrowserPreviewTextureUrl = "";
            g_MlBrowserPreviewError = "";
            g_MlBrowserLoadPreviewRequested = true;
            g_MlBrowserPreviewLoadStartedMs = 0;
            g_MlBrowserPreviewLastAttemptMs = 0;
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Load texture preview");

        UI::SameLine();
        if (UI::Button(Icons::Times + "##ml-browser-clear")) {
            @g_MlBrowserPreviewTexture = null;
            g_MlBrowserPreviewTextureUrl = "";
            g_MlBrowserPreviewError = "";
            g_MlBrowserLoadPreviewRequested = false;
            g_MlBrowserPreviewLoadStartedMs = 0;
            g_MlBrowserPreviewLastAttemptMs = 0;
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Clear preview");

        UI::SameLine();
        bool isFav = _MlBrowserIsFavorite(g_MlBrowserSelectedUrl);
        string favLabel = isFav ? "\\$ff6" + Icons::Star + "\\$z" : Icons::StarO;
        if (UI::Button(favLabel + "##ml-browser-fav")) {
            _MlBrowserToggleFavorite(g_MlBrowserSelectedUrl);
        }
        if (UI::IsItemHovered()) UI::SetTooltip(isFav ? "Remove from favorites" : "Add to favorites");

        auto selectedEntry = _MlBrowserGetSelectedEntry();
        if (selectedEntry !is null) {
            string ext = _MlBrowserFileExtension(selectedEntry.url);
            string extColor = _MlBrowserFileColorCode(ext);
            UI::TextDisabled("Source: " + selectedEntry.source
                + " | Kind: " + selectedEntry.kind
                + (ext.Length > 0 ? " | Type: " : ""));
            if (ext.Length > 0) {
                UI::SameLine();
                UI::Text(extColor + ext.ToUpper() + "\\$z");
            }
        }
        UI::Separator();

        _MlBrowserEnsurePreviewLoaded();
        bool isLoading = _MlBrowserIsPreviewLoading(g_MlBrowserSelectedUrl);
        if (g_MlBrowserPreviewTexture is null) {
            if (!g_MlBrowserLoadPreviewRequested) {
                UI::TextDisabled("Preview not loaded. Click '" + Icons::Play + " Load' or enable auto-preview.");
                return;
            }
            if (isLoading) _MlBrowserRenderPreviewLoadingUi(g_MlBrowserSelectedUrl);
            if (g_MlBrowserPreviewError.Length > 0) UI::Text("\\$f66" + Icons::ExclamationTriangle + " " + g_MlBrowserPreviewError + "\\$z");
            return;
        }

        vec2 avail = UI::GetContentRegionAvail();
        float availW = Math::Max(64.0f, avail.x);
        float availH = Math::Max(64.0f, avail.y);
        float drawW = availW;
        float drawH = availW;
        vec2 texSize = vec2();
        if (!_MlBrowserTextureHasValidSize(g_MlBrowserPreviewTexture, texSize)) {
            if (isLoading) _MlBrowserRenderPreviewLoadingUi(g_MlBrowserSelectedUrl);
            else UI::TextDisabled("Texture size unavailable.");
            if (g_MlBrowserPreviewError.Length > 0) UI::Text("\\$f66" + g_MlBrowserPreviewError + "\\$z");
            return;
        }
        drawH = drawW * (texSize.y / texSize.x);
        UI::TextDisabled(Icons::FileImageO + " " + int(texSize.x) + " x " + int(texSize.y) + " px");
        if (drawH > availH && drawH > 0.0f) {
            float scale = availH / drawH;
            drawH = availH;
            drawW *= scale;
        }
        if (drawW > availW && drawW > 0.0f) {
            float scale = availW / drawW;
            drawW = availW;
            drawH *= scale;
        }
        drawW = Math::Max(64.0f, drawW);
        drawH = Math::Max(64.0f, drawH);
        UI::ImageWithBg(g_MlBrowserPreviewTexture, vec2(drawW, drawH), vec2(0, 0), vec2(1, 1), vec4(0.20f, 0.20f, 0.20f, 1.0f), vec4(1, 1, 1, 1));
    }

    void _RenderMlBrowserTab() {
        S_MlBrowserAllowFidExtract = true;
        S_MlBrowserUseDdsDecoder = true;

        if (UI::Button(Icons::Refresh + " Refresh##ml-browser")) _MlBrowserRefresh();
        if (UI::IsItemHovered()) UI::SetTooltip("Scan live pages and assets for image URLs");

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();

        bool srcLive = S_MlBrowserIncludeLiveLayers;
        bool srcFs = S_MlBrowserIncludeFilesystem;
        bool srcFids = S_MlBrowserIncludeNadeoFidsTree;
        bool srcFidsRes = S_MlBrowserUseFidsResolution;
        bool autoPreview = S_MlBrowserAutoPreview;

        srcLive = UI::Checkbox("Live##ml-browser-src", srcLive);
        if (UI::IsItemHovered()) UI::SetTooltip("Include live ManiaLink layer URLs");
        S_MlBrowserIncludeLiveLayers = srcLive;

        UI::SameLine();
        srcFs = UI::Checkbox("FS##ml-browser-src", srcFs);
        if (UI::IsItemHovered()) UI::SetTooltip("Include filesystem assets");
        S_MlBrowserIncludeFilesystem = srcFs;

        UI::SameLine();
        srcFids = UI::Checkbox("Fids##ml-browser-src", srcFids);
        if (UI::IsItemHovered()) UI::SetTooltip("Include Nadeo Fids tree (game assets)");
        S_MlBrowserIncludeNadeoFidsTree = srcFids;

        UI::SameLine();
        srcFidsRes = UI::Checkbox("Resolve##ml-browser-src", srcFidsRes);
        if (UI::IsItemHovered()) UI::SetTooltip("Use Fids resolution for preview loading");
        S_MlBrowserUseFidsResolution = srcFidsRes;

        UI::SameLine();
        UI::TextDisabled("|");
        UI::SameLine();
        autoPreview = UI::Checkbox("Auto##ml-browser-auto", autoPreview);
        if (UI::IsItemHovered()) UI::SetTooltip("Auto-load preview when selecting a file");
        S_MlBrowserAutoPreview = autoPreview;

        UI::SameLine();
        if (UI::Button(Icons::Cog + "##ml-browser-settings")) {
            UI::OpenPopup("##ml-browser-settings-popup");
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Advanced settings");
        if (UI::BeginPopup("##ml-browser-settings-popup")) {
            UI::TextDisabled("Filesystem Scan");
            UI::Separator();
            UI::SetNextItemWidth(300.0f);
            S_MlBrowserAssetsRoot = UI::InputText("Assets root##ml-browser-set", S_MlBrowserAssetsRoot);
            S_MlBrowserRecursive = UI::Checkbox("Recursive scan##ml-browser-set", S_MlBrowserRecursive);

            int maxFiles = S_MlBrowserMaxFiles;
            UI::SetNextItemWidth(150.0f);
            maxFiles = UI::InputInt("Max files##ml-browser-set", maxFiles);
            if (maxFiles < 1) maxFiles = 1;
            if (maxFiles > 50000) maxFiles = 50000;
            S_MlBrowserMaxFiles = maxFiles;

            UI::Separator();
            UI::TextDisabled("Nadeo Fids");
            UI::Separator();
            int maxFidsFiles = S_MlBrowserMaxNadeoFidsFiles;
            UI::SetNextItemWidth(150.0f);
            maxFidsFiles = UI::InputInt("Max Fids files##ml-browser-set", maxFidsFiles);
            if (maxFidsFiles < 1) maxFidsFiles = 1;
            if (maxFidsFiles > 200000) maxFidsFiles = 200000;
            S_MlBrowserMaxNadeoFidsFiles = maxFidsFiles;

            UI::EndPopup();
        }

        UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 280.0f);
        g_MlBrowserSearch = UI::InputText("##ml-browser-search", g_MlBrowserSearch);
        if (UI::IsItemHovered()) UI::SetTooltip("Filter URLs by name, path, or extension");
        UI::SameLine();
        if (UI::Button(Icons::Times + "##ml-browser-clear-search")) g_MlBrowserSearch = "";
        if (UI::IsItemHovered()) UI::SetTooltip("Clear search");

        UI::SameLine();
        _MlBrowserFavoritesEnsureLoaded();
        UI::SetNextItemWidth(220.0f);
        string favPreview = Icons::StarO + " Favorites (" + g_MlBrowserFavorites.Length + ")";
        if (_MlBrowserIsFavorite(g_MlBrowserSelectedUrl)) {
            favPreview = "\\$ff6" + Icons::Star + "\\$z " + _MlBrowserFavoriteLabel(g_MlBrowserSelectedUrl);
        }
        if (UI::BeginCombo("##ml-browser-favorites", favPreview)) {
            if (g_MlBrowserFavorites.Length == 0) {
                UI::TextDisabled("No favorites yet.");
                UI::TextDisabled("Select a file and click the star to add it.");
            } else {
                for (uint i = 0; i < g_MlBrowserFavorites.Length; ++i) {
                    string fav = g_MlBrowserFavorites[i];
                    bool isSelected = fav == g_MlBrowserSelectedUrl;
                    string label = "\\$ff6" + Icons::Star + "\\$z " + _MlBrowserFavoriteLabel(fav) + "##ml-browser-favorite-" + i;
                    if (UI::Selectable(label, isSelected)) _MlBrowserSelectUrl(fav);
                    if (UI::IsItemHovered()) UI::SetTooltip(fav);
                }
            }
            UI::EndCombo();
        }

        if (g_MlBrowserEntries.Length == 0 && g_MlBrowserLastRefreshMs == 0) {
            UI::TextDisabled("Click '" + Icons::Refresh + " Refresh' to scan live pages and assets.");
        }
        if (g_MlBrowserStatus.Length > 0) UI::TextDisabled(g_MlBrowserStatus);
        UI::Separator();

        string filter = g_MlBrowserSearch.Trim().ToLower();
        float paneHeight = UI::GetContentRegionAvail().y - 2.0f;
        paneHeight = Math::Floor(paneHeight);
        if (paneHeight < 1.0f) paneHeight = 1.0f;
        float availWidth = UI::GetContentRegionAvail().x;
        int minPreviewWidth = 260;
        int listMax = int(availWidth) - minPreviewWidth - 6;
        if (listMax < 260) listMax = 260;
        int listWidth = S_MlBrowserListWidth;
        if (listWidth < 260) listWidth = 260;
        if (listWidth > listMax) listWidth = listMax;
        S_MlBrowserListWidth = listWidth;

        UI::BeginGroup();
        bool listOpen = UI::BeginChild("##ml-browser-list", vec2(float(listWidth), paneHeight), true);
        if (listOpen) {
            _MlBrowserEnsureTreeCache(filter);
            _MlBrowserResetVisibleUrls();
            auto root = g_MlBrowserTreeCacheRoot;

            if (root !is null && root.children.Length > 0) {
                for (uint i = 0; i < root.children.Length; ++i) {
                    _MlBrowserRenderTreeNode(root.children[i]);
                }
            } else {
                if (g_MlBrowserTreeCacheTotalFiles == 0) UI::TextDisabled("No URLs found. Click Refresh to scan.");
                else UI::TextDisabled("No entries match the current filter.");
            }
            _MlBrowserHandleListKeyboardNavigation();
            UI::Separator();
            UI::TextDisabled(Icons::FileImageO + " " + g_MlBrowserTreeCacheShownFiles + " / " + g_MlBrowserTreeCacheTotalFiles);
            if (g_MlBrowserTreeCacheTruncated) {
                UI::Text("\\$fa0" + Icons::ExclamationTriangle + " Tree capped; refine filter to narrow results.\\$z");
            }
        }
        UI::EndChild();
        UI::EndGroup();

        UI::SameLine();
        S_MlBrowserListWidth = _DrawMlBrowserSplitter("##ml-browser-splitter", S_MlBrowserListWidth, paneHeight);
        if (S_MlBrowserListWidth < 260) S_MlBrowserListWidth = 260;
        if (S_MlBrowserListWidth > listMax) S_MlBrowserListWidth = listMax;
        UI::SameLine();

        UI::BeginGroup();
        bool previewOpen = UI::BeginChild(
            "##ml-browser-preview",
            vec2(0, paneHeight),
            true,
            UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoScrollWithMouse
        );
        if (previewOpen) _MlBrowserRenderPreviewPane();
        UI::EndChild();
        UI::EndGroup();
    }

}
}
