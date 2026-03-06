namespace UiNav {
namespace Debug {

    void _RenderMlSelectionNotes(MlSelectionContext@ ctx) {
        if (ctx is null) return;

        UI::TextDisabled("Attach context notes and optional conditions for this selected node.");
        CGameManiaApp@ noteApp = null;
        CGameUILayer@ noteLayer = null;
        CGameManialinkFrame@ noteRoot = null;
        bool haveCtx = _GetSelectedMlLayerContext(noteApp, noteLayer, noteRoot);
        if (!haveCtx) {
            UI::Text("Layer context unavailable for notes.");
            return;
        }

        string layerKey = _MlNoteLayerKey(noteLayer, g_SelectedMlAppKind);
        string anchor = _MlBuildAnchor(noteRoot, g_SelectedMlPath);

        UI::Text("Layer key:");
        UI::BeginChild("##ml-note-layerkey", vec2(0, 44), true);
        UI::TextWrapped(layerKey);
        UI::EndChild();

        UI::Text("Anchor:");
        UI::BeginChild("##ml-note-anchor", vec2(0, 44), true);
        UI::TextWrapped(anchor);
        UI::EndChild();

        _MlNotesEnsureLoaded();

        UI::Separator();
        UI::Text("Existing notes");
        string deleteId = "";
        bool changed = false;
        int shown = 0;
        for (uint i = 0; i < g_MlDebugNotes.Length; ++i) {
            auto note = g_MlDebugNotes[i];
            if (note is null) continue;
            if (note.layerKey != layerKey || note.anchor != anchor) continue;
            shown++;

            UI::PushID("ml-note-" + note.id);

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

            if (UI::BeginCombo("Condition", _MlNoteCondName(note.condKind))) {
                for (int kind = 0; kind <= 4; ++kind) {
                    bool selectedCond = note.condKind == kind;
                    if (UI::Selectable(_MlNoteCondName(kind), selectedCond)) {
                        note.condKind = kind;
                        changed = true;
                    }
                    if (selectedCond) UI::SetItemDefaultFocus();
                }
                UI::EndCombo();
            }

            string needle = note.condNeedle;
            needle = UI::InputText("Contains", needle);
            if (needle != note.condNeedle) {
                note.condNeedle = needle;
                changed = true;
            }

            string layerSelGate = note.layerSelector;
            layerSelGate = UI::InputText("Layer selector must exist", layerSelGate);
            if (layerSelGate != note.layerSelector) {
                note.layerSelector = layerSelGate;
                changed = true;
            }
            UI::TextWrapped("If this selector is set, condition checks run on that selector target.");

            if (UI::Button("Delete note")) {
                deleteId = note.id;
            }

            UI::Separator();
            UI::PopID();
        }

        if (shown == 0) UI::Text("No notes on this node yet.");

        if (deleteId.Length > 0) {
            for (int i = int(g_MlDebugNotes.Length) - 1; i >= 0; --i) {
                auto note = g_MlDebugNotes[uint(i)];
                if (note is null) continue;
                if (note.id != deleteId) continue;
                g_MlDebugNotes.RemoveAt(uint(i));
                changed = true;
                break;
            }
        }

        if (changed) {
            _MlNotesSave();
        }

        UI::Separator();
        UI::Text("Add note to selected node");
        g_MlNoteDraftText = UI::InputTextMultiline("New note text", g_MlNoteDraftText, vec2(0, 80));
        if (UI::BeginCombo("New condition", _MlNoteCondName(g_MlNoteDraftCondKind))) {
            for (int kind = 0; kind <= 4; ++kind) {
                bool selectedCond = g_MlNoteDraftCondKind == kind;
                if (UI::Selectable(_MlNoteCondName(kind), selectedCond)) {
                    g_MlNoteDraftCondKind = kind;
                }
                if (selectedCond) UI::SetItemDefaultFocus();
            }
            UI::EndCombo();
        }
        g_MlNoteDraftNeedle = UI::InputText("New contains", g_MlNoteDraftNeedle);
        g_MlNoteDraftLayerSelector = UI::InputText("New layer selector gate", g_MlNoteDraftLayerSelector);
        UI::TextWrapped("Layer selector gate is optional. Example: #frame-scorestable-layer. If set, condition checks run on that selector target.");

        if (UI::Button("Add note")) {
            string noteText = g_MlNoteDraftText.Trim();
            if (noteText.Length == 0) {
                g_MlDebugNotesStatus = "Cannot add an empty note.";
            } else {
                MlDebugNote@ nn = MlDebugNote();
                nn.id = _MlNewNoteId(layerKey, anchor, noteText);
                nn.enabled = true;
                nn.layerKey = layerKey;
                nn.anchor = anchor;
                nn.condKind = g_MlNoteDraftCondKind;
                nn.condNeedle = g_MlNoteDraftNeedle;
                nn.layerSelector = g_MlNoteDraftLayerSelector.Trim();
                nn.text = noteText;
                g_MlDebugNotes.InsertLast(nn);
                _MlNotesSave();
                g_MlNoteDraftText = "";
            }
        }
        UI::SameLine();
        if (UI::Button("Reload notes from file")) {
            _MlNotesLoad();
            g_MlDebugNotesStatus = "Reloaded notes.";
        }

        UI::Text("Notes file: " + _MlNotesPath());
        if (g_MlDebugNotesStatus.Length > 0) {
            UI::Text(g_MlDebugNotesStatus);
        }
    }

}
}
