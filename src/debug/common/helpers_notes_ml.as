namespace UiNav {
namespace Debug {

    class MlDebugNote {
        string id;
        bool enabled = true;
        string layerKey;
        string anchor;
        int condKind = 0;
        string condNeedle;
        string layerSelector;
        string text;
    }

    array<MlDebugNote@> g_MlDebugNotes;
    bool g_MlDebugNotesLoaded = false;
    string g_MlDebugNotesStatus = "";
    string g_MlNoteDraftText = "";
    int g_MlNoteDraftCondKind = 1;
    string g_MlNoteDraftNeedle = "";
    string g_MlNoteDraftLayerSelector = "";

    string _MlNotesPath() {
        string path = IO::FromStorageFolder("UiNavMlNotes.cfg");
        if (S_MlNotesPath != path) S_MlNotesPath = path;
        return path;
    }

    string _MlNoteEsc(const string &in raw) {
        string s = raw;
        s = s.Replace("%", "%25");
        s = s.Replace("\t", "%09");
        s = s.Replace("\r", "%0D");
        s = s.Replace("\n", "%0A");
        return s;
    }

    string _MlNoteUnesc(const string &in raw) {
        string s = raw;
        s = s.Replace("%09", "\t");
        s = s.Replace("%0D", "\r");
        s = s.Replace("%0A", "\n");
        s = s.Replace("%25", "%");
        return s;
    }

    string _MlNormalizeNoteText(const string &in raw) {
        if (raw.Length == 0) return raw;
        string lower = raw.ToLower();
        int gateIx = lower.IndexOf("\nwhen selector exists:\n");
        if (gateIx >= 0) {
            int condIx = lower.IndexOf("\nif ");
            if (condIx > gateIx) {
                string trimmed = raw.SubStr(0, gateIx).Trim();
                if (trimmed.Length > 0) return trimmed;
            }
        }
        return raw;
    }

    void _MlNotesEnsureLoaded() {
        if (g_MlDebugNotesLoaded) return;
        g_MlDebugNotesLoaded = true;
        _MlNotesLoad();
    }

    void _MlNotesLoad() {
        g_MlDebugNotes.Resize(0);
        string path = _MlNotesPath();
        if (!IO::FileExists(path)) return;

        IO::File f(path, IO::FileMode::Read);
        array<string>@ lines = f.ReadToEnd().Split("\n");
        f.Close();
        bool migrated = false;

        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i];
            if (ln.EndsWith("\r")) ln = ln.SubStr(0, ln.Length - 1);
            string trimmed = ln.Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith("#")) continue;

            array<string>@ parts = ln.Split("\t");
            if (parts.Length < 7) continue;

            MlDebugNote@ note = MlDebugNote();
            note.id = _MlNoteUnesc(parts[0]);
            note.enabled = parts[1].Trim() != "0";
            note.layerKey = _MlNoteUnesc(parts[2]);
            note.anchor = _MlNoteUnesc(parts[3]);
            note.condKind = Text::ParseInt(parts[4].Trim());
            if (note.condKind < 0) note.condKind = 0;
            note.condNeedle = _MlNoteUnesc(parts[5]);
            if (parts.Length >= 8) {
                note.layerSelector = _MlNoteUnesc(parts[6]);
                note.text = _MlNoteUnesc(parts[7]);
            } else {
                note.layerSelector = "";
                note.text = _MlNoteUnesc(parts[6]);
            }
            string normalizedText = _MlNormalizeNoteText(note.text);
            if (normalizedText != note.text) {
                note.text = normalizedText;
                migrated = true;
            }

            if (note.id.Length == 0) note.id = Crypto::MD5(note.layerKey + "|" + note.anchor + "|" + note.text + "|" + i);
            if (note.layerKey.Length == 0 || note.anchor.Length == 0) continue;
            g_MlDebugNotes.InsertLast(note);
        }
        if (migrated) _MlNotesSave();
    }

    void _MlNotesSave() {
        _MlNotesEnsureLoaded();
        string path = _MlNotesPath();
        string outText = "# UiNav ML notes v1\n";
        outText += "# id<TAB>enabled<TAB>layerKey<TAB>anchor<TAB>condKind<TAB>condNeedle<TAB>layerSelector<TAB>text\n";
        for (uint i = 0; i < g_MlDebugNotes.Length; ++i) {
            auto note = g_MlDebugNotes[i];
            if (note is null) continue;
            if (note.layerKey.Length == 0 || note.anchor.Length == 0) continue;
            string ln = _MlNoteEsc(note.id)
                + "\t" + (note.enabled ? "1" : "0")
                + "\t" + _MlNoteEsc(note.layerKey)
                + "\t" + _MlNoteEsc(note.anchor)
                + "\t" + note.condKind
                + "\t" + _MlNoteEsc(note.condNeedle)
                + "\t" + _MlNoteEsc(note.layerSelector)
                + "\t" + _MlNoteEsc(note.text);
            outText += ln + "\n";
        }
        _IO::File::WriteFile(path, outText, false);
        g_MlDebugNotesStatus = "Saved " + g_MlDebugNotes.Length + " note(s).";
    }

    string _MlNoteCondName(int kind) {
        switch (kind) {
            case 0: return "Always";
            case 1: return "Label.Value contains";
            case 2: return "Entry.Value contains";
            case 3: return "Node text contains";
            case 4: return "ControlId contains";
        }
        return "Unknown";
    }

    string _MlNoteCondValue(CGameManialinkControl@ n, int kind) {
        if (n is null) return "";
        if (kind == 1) {
            auto lbl = cast<CGameManialinkLabel@>(n);
            if (lbl is null) return "";
            return "" + lbl.Value;
        }
        if (kind == 2) {
            auto entry = cast<CGameManialinkEntry@>(n);
            if (entry is null) return "";
            return "" + entry.Value;
        }
        if (kind == 3) return UiNav::CleanUiFormatting(UiNav::ML::ReadText(n));
        if (kind == 4) return n.ControlId;
        return "";
    }

    bool _MlNoteIsActive(MlDebugNote@ note, CGameManialinkControl@ n, CGameManialinkFrame@ layerRoot) {
        if (note is null || n is null) return false;
        if (!note.enabled) return false;

        CGameManialinkControl@ condNode = n;
        string selectorGate = note.layerSelector.Trim();
        if (selectorGate.Length > 0) {
            if (layerRoot is null) return false;
            auto gated = UiNav::ML::ResolveSelector(selectorGate, layerRoot);
            if (gated is null) return false;
            if (note.condKind > 0) {
                @condNode = gated;
            }
        }

        if (note.condKind <= 0) return true;

        string needle = note.condNeedle.Trim().ToLower();
        if (note.condKind == 4 && needle.StartsWith("#")) {
            needle = needle.SubStr(1);
        }
        if (needle.Length == 0) return false;
        string hay = _MlNoteCondValue(condNode, note.condKind).ToLower();
        if (hay.Length == 0) return false;
        if (note.condKind == 4 && hay.StartsWith("#")) {
            hay = hay.SubStr(1);
        }
        return hay.Contains(needle);
    }

    string _MlNoteLayerKey(CGameUILayer@ layer, int appKind) {
        string key = UiNav::LayerTags::KeyForLayer(layer, -1);
        if (key.Length == 0) key = "ml:unknown";
        return _MlAppNameByKind(appKind) + "|" + key;
    }

}
}
