namespace UiNav {
namespace Debug {

    class ControlTreeDebugNote {
        string id;
        bool enabled = true;
        uint overlay = 16;
        int rootIx = -1;
        string relPath;
        int condKind = 0;
        string condNeedle;
        string text;
    }

    [Setting hidden name="UiNav debug ControlTree notes file path"]
    string S_ControlTreeNotesPath = IO::FromStorageFolder("UiNavControlTreeNotes.cfg");

    array<ControlTreeDebugNote@> g_ControlTreeDebugNotes;
    bool g_ControlTreeDebugNotesLoaded = false;
    string g_ControlTreeDebugNotesStatus = "";
    string g_ControlTreeNoteDraftText = "";
    int g_ControlTreeNoteDraftCondKind = 1;
    string g_ControlTreeNoteDraftNeedle = "";

    string _ControlTreeNotesPath() {
        string path = IO::FromStorageFolder("UiNavControlTreeNotes.cfg");
        if (S_ControlTreeNotesPath != path) S_ControlTreeNotesPath = path;
        return path;
    }

    void _ControlTreeNotesEnsureLoaded() {
        if (g_ControlTreeDebugNotesLoaded) return;
        g_ControlTreeDebugNotesLoaded = true;
        _ControlTreeNotesLoad();
    }

    void _ControlTreeNotesLoad() {
        g_ControlTreeDebugNotes.Resize(0);
        string path = _ControlTreeNotesPath();
        if (!IO::FileExists(path)) return;

        IO::File f(path, IO::FileMode::Read);
        array<string>@ lines = f.ReadToEnd().Split("\n");
        f.Close();

        for (uint i = 0; i < lines.Length; ++i) {
            string ln = lines[i];
            if (ln.EndsWith("\r")) ln = ln.SubStr(0, ln.Length - 1);
            string trimmed = ln.Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith("#")) continue;

            auto parts = ln.Split("\t");
            if (parts.Length < 8) continue;

            ControlTreeDebugNote@ note = ControlTreeDebugNote();
            note.id = _MlNoteUnesc(parts[0]);
            note.enabled = parts[1].Trim() != "0";
            note.overlay = uint(Math::Max(0, Text::ParseInt(parts[2].Trim())));
            note.rootIx = Text::ParseInt(parts[3].Trim());
            note.relPath = _MlNoteUnesc(parts[4]).Trim();
            note.condKind = Text::ParseInt(parts[5].Trim());
            if (note.condKind < 0) note.condKind = 0;
            note.condNeedle = _MlNoteUnesc(parts[6]);
            note.text = _MlNoteUnesc(parts[7]);

            if (note.id.Length == 0) {
                note.id = Crypto::MD5(note.overlay + "|" + note.rootIx + "|" + note.relPath + "|" + note.text + "|" + i);
            }
            if (note.rootIx < 0) continue;
            g_ControlTreeDebugNotes.InsertLast(note);
        }
    }

    void _ControlTreeNotesSave() {
        _ControlTreeNotesEnsureLoaded();
        string path = _ControlTreeNotesPath();
        string outText = "# UiNav ControlTree notes v1\n";
        outText += "# id<TAB>enabled<TAB>overlay<TAB>rootIx<TAB>relPath<TAB>condKind<TAB>condNeedle<TAB>text\n";
        for (uint i = 0; i < g_ControlTreeDebugNotes.Length; ++i) {
            auto note = g_ControlTreeDebugNotes[i];
            if (note is null) continue;
            if (note.rootIx < 0) continue;
            string ln = _MlNoteEsc(note.id)
                + "\t" + (note.enabled ? "1" : "0")
                + "\t" + note.overlay
                + "\t" + note.rootIx
                + "\t" + _MlNoteEsc(note.relPath)
                + "\t" + note.condKind
                + "\t" + _MlNoteEsc(note.condNeedle)
                + "\t" + _MlNoteEsc(note.text);
            outText += ln + "\n";
        }
        _IO::File::WriteFile(path, outText, false);
        g_ControlTreeDebugNotesStatus = "Saved " + g_ControlTreeDebugNotes.Length + " note(s).";
    }

    string _ControlTreeNoteCondName(int kind) {
        switch (kind) {
            case 0: return "Always";
            case 1: return "Node text contains";
            case 2: return "Id/Stack contains";
            case 3: return "Node type contains";
            case 4: return "Visible is";
        }
        return "Unknown";
    }

    string _ControlTreeNoteCondValue(CControlBase@ n, int kind) {
        if (n is null) return "";
        if (kind == 1) return CleanUiFormatting(ReadText(n));
        if (kind == 2) {
            string idName = n.IdName.Trim();
            string stack = n.StackText.Trim();
            if (idName.Length > 0 && stack.Length > 0) return idName + " " + stack;
            if (idName.Length > 0) return idName;
            return stack;
        }
        if (kind == 3) return NodeTypeName(n);
        if (kind == 4) return IsEffectivelyVisible(n) ? "true" : "false";
        return "";
    }

    bool _ControlTreeNoteMatchesSelection(ControlTreeDebugNote@ note, uint overlay, int rootIx, const string &in relPath) {
        if (note is null) return false;
        if (note.overlay != overlay) return false;
        if (note.rootIx != rootIx) return false;
        return note.relPath == relPath;
    }

    bool _ControlTreeNoteIsActive(ControlTreeDebugNote@ note, CControlBase@ n) {
        if (note is null || n is null) return false;
        if (!note.enabled) return false;
        if (note.condKind <= 0) return true;

        string hay = _ControlTreeNoteCondValue(n, note.condKind).ToLower();
        if (note.condKind == 4) {
            return _SearchBoolMatch(note.condNeedle, hay == "true");
        }

        string needle = note.condNeedle.Trim().ToLower();
        if (needle.Length == 0) return false;
        if (hay.Length == 0) return false;
        return hay.Contains(needle);
    }

    bool _ControlTreeGetActiveNotesTooltip(uint overlay, int rootIx, const string &in relPath, CControlBase@ n,
                                           string &out tooltip, int &out count) {
        _ControlTreeNotesEnsureLoaded();
        tooltip = "";
        count = 0;
        for (uint i = 0; i < g_ControlTreeDebugNotes.Length; ++i) {
            auto note = g_ControlTreeDebugNotes[i];
            if (!_ControlTreeNoteMatchesSelection(note, overlay, rootIx, relPath)) continue;
            if (!_ControlTreeNoteIsActive(note, n)) continue;
            string txt = note.text.Trim();
            if (txt.Length == 0) continue;
            if (tooltip.Length > 0) tooltip += "\n\n";
            tooltip += txt;
            count++;
        }
        return count > 0;
    }

}
}
