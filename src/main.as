class UiNav_UnloadCleanup {
    ~UiNav_UnloadCleanup() {
        UiNav::Layers::OnPluginUnload();
        UiNav::Layers::DestroyAllOwnedGlobal();
    }
}
UiNav_UnloadCleanup g_UiNav_UnloadCleanup;

void Main() {
    while (true) {
        UiNav::Layers::TickOwnedRestore();
        UiNav::Dump::TickRequestPump();
        yield();
    }
}
