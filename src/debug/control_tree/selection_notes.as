namespace UiNav {
namespace Debug {

    void _RenderControlTreeSelectionNotes(ControlTreeSelectionContext@ ctx) {
        if (ctx is null || ctx.sel is null) return;

        _ControlTreeNotesEnsureLoaded();

        UI::TextDisabled("Attach context notes and optional conditions for this selected ControlTree node.");
        UI::Text("Target key:");
        UI::BeginChild("##controlTree-note-target", vec2(0, 64), true);
        UI::TextWrapped("overlay=" + g_SelectedControlTreeOverlayAtSel + " root=" + g_SelectedControlTreeRootIx + " path="
            + (ctx.relPath.Length > 0 ? ctx.relPath : "<root>"));
        UI::TextWrapped("display=" + (ctx.dispPath.Length > 0 ? ctx.dispPath : "<empty>"));
        UI::EndChild();

        UI::Separator();
        UI::Text("Existing notes");

        string deleteId = "";
        bool changed = false;
        int shown = 0;
        for (uint i = 0; i < g_ControlTreeDebugNotes.Length; ++i) {
            auto note = g_ControlTreeDebugNotes[i];
            if (!_ControlTreeNoteMatchesSelection(note, g_SelectedControlTreeOverlayAtSel, g_SelectedControlTreeRootIx, ctx.relPath)) continue;
            shown++;

            UI::PushID("controlTree-note-" + note.id);

            bool en = note.enabled;
            en = UI::Checkbox("Enabled", en);
            if (en != note.enabled) {
                note.enabled = en;
                changed = true;
            }

            string txt = note.text;
            txt = UI::InputTextMultiline("Note text", txt, vec2(0, 70));
            if (txt != note.text) {
                note.text = txt;
                changed = true;
            }

            if (UI::BeginCombo("Condition", _ControlTreeNoteCondName(note.condKind))) {
                for (int kind = 0; kind <= 4; ++kind) {
                    bool selectedCond = note.condKind == kind;
                    if (UI::Selectable(_ControlTreeNoteCondName(kind), selectedCond)) {
                        note.condKind = kind;
                        changed = true;
                    }
                    if (selectedCond) UI::SetItemDefaultFocus();
                }
                UI::EndCombo();
            }

            string needle = note.condNeedle;
            needle = UI::InputText(note.condKind == 4 ? "Visible should be (true/false)" : "Contains", needle);
            if (needle != note.condNeedle) {
                note.condNeedle = needle;
                changed = true;
            }

            bool active = _ControlTreeNoteIsActive(note, ctx.sel);
            UI::Text("Active now: " + (active ? "true" : "false"));

            if (UI::Button("Delete note")) {
                deleteId = note.id;
            }

            UI::Separator();
            UI::PopID();
        }

        if (shown == 0) UI::Text("No notes on this node yet.");

        if (deleteId.Length > 0) {
            for (int i = int(g_ControlTreeDebugNotes.Length) - 1; i >= 0; --i) {
                auto note = g_ControlTreeDebugNotes[uint(i)];
                if (note is null || note.id != deleteId) continue;
                g_ControlTreeDebugNotes.RemoveAt(uint(i));
                changed = true;
                break;
            }
        }

        if (changed) _ControlTreeNotesSave();

        UI::Separator();
        UI::Text("Add note to selected node");
        g_ControlTreeNoteDraftText = UI::InputTextMultiline("New note text", g_ControlTreeNoteDraftText, vec2(0, 80));
        if (UI::BeginCombo("New condition", _ControlTreeNoteCondName(g_ControlTreeNoteDraftCondKind))) {
            for (int kind = 0; kind <= 4; ++kind) {
                bool selectedCond = g_ControlTreeNoteDraftCondKind == kind;
                if (UI::Selectable(_ControlTreeNoteCondName(kind), selectedCond)) {
                    g_ControlTreeNoteDraftCondKind = kind;
                }
                if (selectedCond) UI::SetItemDefaultFocus();
            }
            UI::EndCombo();
        }
        g_ControlTreeNoteDraftNeedle = UI::InputText(g_ControlTreeNoteDraftCondKind == 4 ? "New visible should be" : "New contains", g_ControlTreeNoteDraftNeedle);

        if (UI::Button("Add note")) {
            string noteText = g_ControlTreeNoteDraftText.Trim();
            if (noteText.Length == 0) {
                g_ControlTreeDebugNotesStatus = "Cannot add an empty note.";
            } else {
                ControlTreeDebugNote@ note = ControlTreeDebugNote();
                note.id = Crypto::MD5(g_SelectedControlTreeOverlayAtSel + "|" + g_SelectedControlTreeRootIx + "|" + ctx.relPath + "|" + noteText + "|" + Time::Now + "|" + g_ControlTreeDebugNotes.Length);
                note.enabled = true;
                note.overlay = g_SelectedControlTreeOverlayAtSel;
                note.rootIx = g_SelectedControlTreeRootIx;
                note.relPath = ctx.relPath;
                note.condKind = g_ControlTreeNoteDraftCondKind;
                note.condNeedle = g_ControlTreeNoteDraftNeedle;
                note.text = noteText;
                g_ControlTreeDebugNotes.InsertLast(note);
                _ControlTreeNotesSave();
                g_ControlTreeNoteDraftText = "";
            }
        }
        UI::SameLine();
        if (UI::Button("Reload notes from file")) {
            _ControlTreeNotesLoad();
            g_ControlTreeDebugNotesStatus = "Reloaded notes.";
        }

        UI::Text("Notes file: " + _ControlTreeNotesPath());
        if (g_ControlTreeDebugNotesStatus.Length > 0) {
            UI::Text(g_ControlTreeDebugNotesStatus);
        }
    }

}
}
