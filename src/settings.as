[Setting hidden name="Enabled"]
bool S_Enabled = true;

[Setting hidden name="Show/hide with game UI"]
bool S_HideWithGame = true;

[Setting hidden name="Show/hide with Openplanet UI"]
bool S_HideWithOP = false;

[Setting hidden name="Show dev tabs"]
bool S_ShowUiNavDev = false;

bool _RenderUiNavDevTabGate(const string &in tabName) {
    if (S_ShowUiNavDev) return true;
    UI::Text("This tab is only available in dev mode.");
    UI::TextDisabled("Enable \"Show dev tabs\" in the General tab to use " + tabName + ".");
    return false;
}

[SettingsTab name="General" icon="Wrench" order="1"]
void RenderUiNavGeneralSettingsTab() {
    UiNav::Debug::RenderGeneralSettingsUI();
}

[SettingsTab name="Selector" icon="Wrench" order="2"]
void RenderUiNavSelectorSettingsTab() {
    if (!_RenderUiNavDevTabGate("Selector")) return;
    UiNav::Builder::RenderSelectorSettingsUI();
}

[SettingsTab name="ManiaLink UI" icon="Wrench" order="3"]
void RenderUiNavManiaLinkSettingsTab() {
    if (!_RenderUiNavDevTabGate("ManiaLink UI")) return;
    UiNav::Debug::RenderManiaLinkUiSettingsUI();
}

[SettingsTab name="ControlTree UI" icon="Wrench" order="4"]
void RenderUiNavControlTreeUiSettingsTab() {
    if (!_RenderUiNavDevTabGate("ControlTree UI")) return;
    UiNav::Debug::RenderControlTreeUiSettingsUI();
}

[SettingsTab name="ManiaLink Builder" icon="Wrench" order="5"]
void RenderUiNavManiaLinkBuilderSettingsTab() {
    if (!_RenderUiNavDevTabGate("ManiaLink Builder")) return;
    UiNav::Builder::RenderSettingsUI();
}

[SettingsTab name="ManiaLink Browser" icon="Wrench" order="6"]
void RenderUiNavManiaLinkBrowserSettingsTab() {
    if (!_RenderUiNavDevTabGate("ManiaLink Browser")) return;
    UiNav::Debug::RenderManiaLinkBrowserSettingsUI();
}

[SettingsTab name="Diagnostics" icon="Wrench" order="7"]
void RenderUiNavDiagnosticsSettingsTab() {
    if (!_RenderUiNavDevTabGate("Diagnostics")) return;
    UiNav::Debug::RenderDiagnosticsSettingsUI();
}
