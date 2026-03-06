namespace UiNav {
namespace Debug {

    string _MlFavoriteLayerId(CGameUILayer@ layer) {
        if (layer is null) return "";
        string key = "ml:";

        if (layer.LocalPage !is null && layer.LocalPage.MainFrame !is null) {
            string id = layer.LocalPage.MainFrame.ControlId.Trim();
            if (id.Length > 0) key += "id=" + id + "|";
        }

        string attach = layer.AttachId.Trim();
        if (attach.Length > 0) key += "attach=" + attach + "|";

        string name = _ExtractMlNameFromLayer(layer).Trim();
        if (name.Length > 0) key += "name=" + name + "|";

        if (key.EndsWith("|")) key = key.SubStr(0, key.Length - 1);
        if (key != "ml:") return key;
        return "";
    }

    string _MlFavoriteKey(int appKind, const string &in layerId) {
        return appKind + ":" + layerId;
    }

    int _MlFindLayerFavoriteIxById(int appKind, const string &in layerId) {
        if (layerId.Length == 0) return -1;
        for (uint i = 0; i < g_MlLayerFavorites.Length; ++i) {
            auto fav = g_MlLayerFavorites[i];
            if (fav is null) continue;
            if (fav.appKind != appKind) continue;
            if (fav.layerId == layerId) return int(i);
        }
        return -1;
    }

    int _MlFindLayerFavoriteIxByLayerIx(int appKind, int layerIx) {
        if (layerIx < 0) return -1;
        for (uint i = 0; i < g_MlLayerFavorites.Length; ++i) {
            auto fav = g_MlLayerFavorites[i];
            if (fav is null) continue;
            if (fav.appKind != appKind) continue;
            if (fav.layerId.Length > 0) continue;
            if (fav.layerIx == layerIx) return int(i);
        }
        return -1;
    }

    int _MlFindLayerFavoriteIx(int appKind, int layerIx) {
        auto layer = _GetMlLayerByIx(appKind, layerIx);
        string layerId = _MlFavoriteLayerId(layer);
        int ix = -1;
        if (layerId.Length > 0) ix = _MlFindLayerFavoriteIxById(appKind, layerId);
        if (ix < 0) ix = _MlFindLayerFavoriteIxByLayerIx(appKind, layerIx);
        return ix;
    }

    int _MlResolveFavoriteLayerIx(int appKind, const string &in layerId, int hintIx = -1) {
        if (layerId.Length == 0) return hintIx;

        if (hintIx >= 0) {
            auto layerHint = _GetMlLayerByIx(appKind, hintIx);
            if (layerHint !is null && _MlFavoriteLayerId(layerHint) == layerId) return hintIx;
        }

        uint len = _GetMlLayerCount(appKind);
        for (uint i = 0; i < len; ++i) {
            auto layer = _GetMlLayerByIx(appKind, int(i));
            if (layer is null) continue;
            if (_MlFavoriteLayerId(layer) == layerId) return int(i);
        }
        return -1;
    }

    void _MlLayerFavoritesLoad() {
        g_MlLayerFavorites.Resize(0);
        string raw = S_MlFavoriteLayers;
        if (raw.Length == 0) return;

        auto lines = raw.Split("\n");
        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i];
            if (ln.EndsWith("\r")) ln = ln.SubStr(0, ln.Length - 1);
            ln = ln.Trim();
            if (ln.Length == 0) continue;

            auto parts = ln.Split("\t");
            if (parts.Length < 2) continue;
            int appKind = Text::ParseInt(parts[0].Trim());
            if (appKind < 0 || appKind > 2) continue;

            string p1 = parts[1].Trim();
            MlLayerFavorite@ fav = MlLayerFavorite();
            fav.appKind = appKind;

            if (_MlLooksLikeInt(p1)) {
                int layerIx = Text::ParseInt(p1);
                if (layerIx < 0) continue;
                fav.layerIx = layerIx;
                if (parts.Length >= 3) fav.label = _MlNoteUnesc(parts[2]);

                auto layer = _GetMlLayerByIx(appKind, layerIx);
                fav.layerId = _MlFavoriteLayerId(layer);

                if (fav.layerId.Length > 0) {
                    if (_MlFindLayerFavoriteIxById(appKind, fav.layerId) >= 0) continue;
                } else {
                    if (_MlFindLayerFavoriteIxByLayerIx(appKind, layerIx) >= 0) continue;
                }

                g_MlLayerFavorites.InsertLast(fav);
                continue;
            }

            fav.layerId = _MlNoteUnesc(p1).Trim();
            if (fav.layerId.Length == 0) continue;
            if (parts.Length >= 3) fav.label = _MlNoteUnesc(parts[2]);
            if (parts.Length >= 4 && _MlLooksLikeInt(parts[3])) fav.layerIx = Text::ParseInt(parts[3].Trim());

            if (_MlFindLayerFavoriteIxById(appKind, fav.layerId) >= 0) continue;
            g_MlLayerFavorites.InsertLast(fav);
        }
    }

    void _MlLayerFavoritesSave() {
        array<string> lines;
        for (uint i = 0; i < g_MlLayerFavorites.Length; ++i) {
            auto fav = g_MlLayerFavorites[i];
            if (fav is null) continue;
            if (fav.appKind < 0 || fav.appKind > 2) continue;

            if (fav.layerId.Trim().Length > 0) {
                lines.InsertLast(
                    fav.appKind
                    + "\t" + _MlNoteEsc(fav.layerId.Trim())
                    + "\t" + _MlNoteEsc(fav.label)
                    + "\t" + fav.layerIx
                );
                continue;
            }

            if (fav.layerIx < 0) continue;
            lines.InsertLast(fav.appKind + "\t" + fav.layerIx + "\t" + _MlNoteEsc(fav.label));
        }
        S_MlFavoriteLayers = _JoinParts(lines, "\n");
    }

    void _MlLayerFavoritesEnsureLoaded() {
        if (g_MlLayerFavoritesLoaded) return;
        g_MlLayerFavoritesLoaded = true;
        _MlLayerFavoritesLoad();
    }

    bool _MlIsLayerFavorite(int appKind, int layerIx) {
        _MlLayerFavoritesEnsureLoaded();
        return _MlFindLayerFavoriteIx(appKind, layerIx) >= 0;
    }

    string _MlFavoriteDisplayLabel(MlLayerFavorite@ fav, bool includeAppName = true) {
        if (fav is null) return "";

        string name = fav.label.Trim();
        if (name.Length == 0) {
            auto layer = _GetMlLayerByIx(fav.appKind, fav.layerIx);
            name = _CachedMlLayerName(layer, fav.appKind, fav.layerIx);
        }

        string outLabel = "L[" + fav.layerIx + "]";
        if (name.Length > 0) outLabel += " " + name;
        if (includeAppName) outLabel = _MlAppNameByKind(fav.appKind) + " - " + outLabel;
        return outLabel;
    }

    void _MlAddLayerFavorite(int appKind, int layerIx, const string &in label = "") {
        if (appKind < 0 || appKind > 2 || layerIx < 0) return;
        _MlLayerFavoritesEnsureLoaded();

        auto layer = _GetMlLayerByIx(appKind, layerIx);
        string layerId = _MlFavoriteLayerId(layer);
        if (layerId.Trim().Length == 0) return;
        string labelTrim = label.Trim();

        int ix = _MlFindLayerFavoriteIxById(appKind, layerId);
        if (ix >= 0) {
            auto fav = g_MlLayerFavorites[uint(ix)];
            if (fav !is null) {
                fav.layerIx = layerIx;
                if (labelTrim.Length > 0) fav.label = labelTrim;
            }
            _MlLayerFavoritesSave();
            return;
        }

        int legacyIx = _MlFindLayerFavoriteIxByLayerIx(appKind, layerIx);
        if (legacyIx >= 0) {
            auto fav = g_MlLayerFavorites[uint(legacyIx)];
            if (fav !is null) {
                fav.layerId = layerId;
                if (labelTrim.Length > 0) fav.label = labelTrim;
            }
            _MlLayerFavoritesSave();
            return;
        }

        MlLayerFavorite@ fav = MlLayerFavorite();
        fav.appKind = appKind;
        fav.layerId = layerId;
        fav.layerIx = layerIx;
        fav.label = labelTrim;
        g_MlLayerFavorites.InsertLast(fav);
        _MlLayerFavoritesSave();
    }

    bool _MlRemoveLayerFavorite(int appKind, int layerIx) {
        _MlLayerFavoritesEnsureLoaded();
        if (appKind < 0 || appKind > 2 || layerIx < 0) return false;

        auto layer = _GetMlLayerByIx(appKind, layerIx);
        string layerId = _MlFavoriteLayerId(layer);

        int ix = -1;
        if (layerId.Length > 0) ix = _MlFindLayerFavoriteIxById(appKind, layerId);
        if (ix < 0) ix = _MlFindLayerFavoriteIxByLayerIx(appKind, layerIx);
        if (ix < 0) return false;

        g_MlLayerFavorites.RemoveAt(uint(ix));
        _MlLayerFavoritesSave();
        return true;
    }

}
}
