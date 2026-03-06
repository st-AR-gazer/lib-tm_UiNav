namespace UiNav {
namespace Context {

    uint g_Epoch = 1;
    uint g_EpochBumps = 0;
    uint g_LastRefreshAtMs = 0;
    bool g_HasSnapshot = false;

    CGameManiaApp@ g_LastApp = null;
    array<CGameUILayer@> g_LastLayers;
    array<CGameManialinkPage@> g_LastPages;

    uint Epoch() { return g_Epoch; }
    uint EpochBumps() { return g_EpochBumps; }

    void _StoreSnapshot(CGameManiaApp@ app) {
        @g_LastApp = app;
        g_LastLayers.Resize(0);
        g_LastPages.Resize(0);

        if (app is null) return;

        auto layers = app.UILayers;
        g_LastLayers.Resize(layers.Length);
        g_LastPages.Resize(layers.Length);
        for (uint i = 0; i < layers.Length; ++i) {
            auto layer = layers[i];
            @g_LastLayers[i] = layer;
            @g_LastPages[i] = (layer !is null) ? layer.LocalPage : null;
        }
    }

    bool _SnapshotDiffers(CGameManiaApp@ app) {
        if ((app is null) != (g_LastApp is null)) return true;
        if (app !is g_LastApp) return true;
        if (app is null) return false;

        auto layers = app.UILayers;
        if (layers.Length != g_LastLayers.Length) return true;

        for (uint i = 0; i < layers.Length; ++i) {
            auto layer = layers[i];
            if (layer !is g_LastLayers[i]) return true;

            auto page = (layer !is null) ? layer.LocalPage : null;
            if (page !is g_LastPages[i]) return true;
        }

        return false;
    }

    void _BumpEpoch(const string &in reason) {
        g_Epoch++;
        g_EpochBumps++;
        UiNav::Layers::OnContextEpochChanged();
        UiNav::Trace::Add("Context.bump epoch=" + g_Epoch + " reason=" + reason);
    }

    bool Refresh(bool force = false) {
        uint now = Time::Now;
        if (!force) {
            if (g_LastRefreshAtMs == now) return false;
            g_LastRefreshAtMs = now;
        } else {
            g_LastRefreshAtMs = now;
        }

        auto app = UiNav::Layers::GetManiaApp();
        if (!g_HasSnapshot) {
            _StoreSnapshot(app);
            g_HasSnapshot = true;
            return false;
        }

        bool changed = _SnapshotDiffers(app);
        if (!changed) return false;

        _BumpEpoch("auto");
        _StoreSnapshot(app);
        return true;
    }

    void InvalidateAll(const string &in reason = "manual") {
        _BumpEpoch(reason);
        _StoreSnapshot(UiNav::Layers::GetManiaApp());
        g_HasSnapshot = true;
    }

}
}
