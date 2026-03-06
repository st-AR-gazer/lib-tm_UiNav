class UiNav_UnloadCleanup {
    ~UiNav_UnloadCleanup() {
        UiNav::Layers::DestroyAllOwned();
    }
}
UiNav_UnloadCleanup g_UiNav_UnloadCleanup;

void Main() {
    while (true) {
        // Service UiNav dump requests from OpDevCompanion while UiNav is active.
        UiNav::Dump::TickRequestPump();
        yield();
    }
}
