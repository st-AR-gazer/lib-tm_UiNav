namespace UiNav {
namespace Metrics {

    const uint kLatencyWindow = 256;

    class LatencyBucket {
        array<uint> samples;
        uint nextIx = 0;
        uint count = 0;
        double totalMs = 0.0;
        uint maxMs = 0;
        uint lastMs = 0;
    }

    dictionary g_Latency;

    LatencyBucket@ _Get(const string &in name, bool createIfMissing = false) {
        if (name.Length == 0) return null;
        LatencyBucket@ b;
        if (g_Latency.Get(name, @b) && b !is null) return b;
        if (!createIfMissing) return null;
        @b = LatencyBucket();
        g_Latency.Set(name, @b);
        return b;
    }

    void Record(const string &in name, uint elapsedMs) {
        auto b = _Get(name, true);
        if (b is null) return;

        b.count++;
        b.totalMs += elapsedMs;
        b.lastMs = elapsedMs;
        if (elapsedMs > b.maxMs) b.maxMs = elapsedMs;

        if (b.samples.Length < kLatencyWindow) {
            b.samples.InsertLast(elapsedMs);
            if (b.samples.Length == kLatencyWindow) b.nextIx = 0;
            return;
        }

        b.samples[b.nextIx] = elapsedMs;
        b.nextIx = (b.nextIx + 1) % kLatencyWindow;
    }

    uint Count(const string &in name) {
        auto b = _Get(name, false);
        if (b is null) return 0;
        return b.count;
    }

    float AvgMs(const string &in name) {
        auto b = _Get(name, false);
        if (b is null || b.count == 0) return 0.0f;
        return float(b.totalMs / double(b.count));
    }

    uint MaxMs(const string &in name) {
        auto b = _Get(name, false);
        if (b is null) return 0;
        return b.maxMs;
    }

    uint LastMs(const string &in name) {
        auto b = _Get(name, false);
        if (b is null) return 0;
        return b.lastMs;
    }

    uint _PercentileMs(const string &in name, float pct) {
        auto b = _Get(name, false);
        if (b is null || b.samples.Length == 0) return 0;
        if (pct <= 0.0f) pct = 0.0f;
        if (pct >= 1.0f) pct = 1.0f;

        array<uint> s = b.samples;
        s.SortAsc();
        int idx = int(Math::Floor((s.Length - 1) * pct + 0.5f));
        if (idx < 0) idx = 0;
        if (idx >= int(s.Length)) idx = int(s.Length) - 1;
        return s[uint(idx)];
    }

    uint P50Ms(const string &in name) { return _PercentileMs(name, 0.50f); }
    uint P95Ms(const string &in name) { return _PercentileMs(name, 0.95f); }

    void Reset() {
        g_Latency.DeleteAll();
    }

}
}
