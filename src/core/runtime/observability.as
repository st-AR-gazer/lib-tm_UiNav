namespace UiNav {

    const uint kApiVersionMajor = 0;
    const uint kApiVersionMinor = 1;
    const uint kApiVersionPatch = 0;

    class _CacheMetricsBaseline {
        uint layerFrameMemoHits = 0;
        uint layerFrameMemoMisses = 0;
        uint layerFrameMemoNegativeHits = 0;
        uint layerReqHintHits = 0;
        uint layerReqHintMisses = 0;
        uint selectorTokenHits = 0;
        uint selectorTokenMisses = 0;
        uint selectorTokenEvictions = 0;
        uint targetPlanHits = 0;
        uint targetPlanMisses = 0;
        uint targetPlanRebuilds = 0;
    }

    dictionary g_CacheMetricBaselines;

    uint ApiVersionMajor() { return kApiVersionMajor; }
    uint ApiVersionMinor() { return kApiVersionMinor; }
    uint ApiVersionPatch() { return kApiVersionPatch; }

    string ApiVersionString() {
        return tostring(kApiVersionMajor) + "." + tostring(kApiVersionMinor) + "." + tostring(kApiVersionPatch);
    }

    bool ApiVersionAtLeast(uint major, uint minor = 0, uint patch = 0) {
        if (kApiVersionMajor != major) return kApiVersionMajor > major;
        if (kApiVersionMinor != minor) return kApiVersionMinor > minor;
        return kApiVersionPatch >= patch;
    }

    string _CurrentObservabilityScope() {
        return UiNav::Layers::_CurrentCallerScope();
    }

    _CacheMetricsBaseline@ _GetCacheMetricsBaseline(const string &in scopeId, bool createIfMissing = false) {
        if (scopeId.Length == 0) return null;
        _CacheMetricsBaseline@ baseline;
        if (g_CacheMetricBaselines.Get(scopeId, @baseline) && baseline !is null) return baseline;
        if (!createIfMissing) return null;
        @baseline = _CacheMetricsBaseline();
        g_CacheMetricBaselines.Set(scopeId, @baseline);
        return baseline;
    }

    void _CaptureCacheMetricsBaseline(_CacheMetricsBaseline@ baseline) {
        if (baseline is null) return;
        baseline.layerFrameMemoHits = UiNav::Layers::LayerReqFrameMemoHits();
        baseline.layerFrameMemoMisses = UiNav::Layers::LayerReqFrameMemoMisses();
        baseline.layerFrameMemoNegativeHits = UiNav::Layers::LayerReqFrameMemoNegativeHits();
        baseline.layerReqHintHits = UiNav::Layers::LayerReqCacheHits();
        baseline.layerReqHintMisses = UiNav::Layers::LayerReqCacheMisses();
        baseline.selectorTokenHits = UiNav::ML::SelectorCacheHits();
        baseline.selectorTokenMisses = UiNav::ML::SelectorCacheMisses();
        baseline.selectorTokenEvictions = UiNav::ML::SelectorCacheEvictions();
        baseline.targetPlanHits = UiNav::TargetPlanCacheHits();
        baseline.targetPlanMisses = UiNav::TargetPlanCacheMisses();
        baseline.targetPlanRebuilds = UiNav::TargetPlanCacheRebuilds();
    }

    uint _CounterDelta(uint current, uint baseline) {
        if (current >= baseline) return current - baseline;
        return current;
    }

    uint ContextEpoch() {
        return UiNav::Context::Epoch();
    }

    uint ContextEpochBumps() {
        return UiNav::Context::EpochBumps();
    }

    bool RefreshContext() {
        return UiNav::Context::Refresh(true);
    }

    void InvalidateTargetCaches(const string &in reason = "manual") {
        string scopeId = _CurrentObservabilityScope();
        UiNav::InvalidateTargetStatesForScope(scopeId, "cache invalidated: " + reason);
    }

    void InvalidateAllCaches(const string &in reason = "manual") {
        InvalidateTargetCaches(reason);
    }

    uint CacheLayerFrameMemoHits() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::Layers::LayerReqFrameMemoHits(), baseline is null ? 0 : baseline.layerFrameMemoHits);
    }
    uint CacheLayerFrameMemoMisses() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::Layers::LayerReqFrameMemoMisses(), baseline is null ? 0 : baseline.layerFrameMemoMisses);
    }
    uint CacheLayerFrameMemoNegativeHits() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::Layers::LayerReqFrameMemoNegativeHits(), baseline is null ? 0 : baseline.layerFrameMemoNegativeHits);
    }
    uint CacheLayerReqHintHits() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::Layers::LayerReqCacheHits(), baseline is null ? 0 : baseline.layerReqHintHits);
    }
    uint CacheLayerReqHintMisses() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::Layers::LayerReqCacheMisses(), baseline is null ? 0 : baseline.layerReqHintMisses);
    }

    uint CacheSelectorTokenHits() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::ML::SelectorCacheHits(), baseline is null ? 0 : baseline.selectorTokenHits);
    }
    uint CacheSelectorTokenMisses() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::ML::SelectorCacheMisses(), baseline is null ? 0 : baseline.selectorTokenMisses);
    }
    uint CacheSelectorTokenEvictions() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::ML::SelectorCacheEvictions(), baseline is null ? 0 : baseline.selectorTokenEvictions);
    }
    uint SharedCacheSelectorTokenSize() { return UiNav::ML::SelectorCacheSize(); }

    uint CacheSelectorTokenSize() { return SharedCacheSelectorTokenSize(); }
    float CacheSelectorTokenHitRate() {
        uint hits = CacheSelectorTokenHits();
        uint misses = CacheSelectorTokenMisses();
        uint total = hits + misses;
        if (total == 0) return 0.0f;
        return float(hits) / float(total);
    }

    uint CacheTargetPlanHits() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::TargetPlanCacheHits(), baseline is null ? 0 : baseline.targetPlanHits);
    }
    uint CacheTargetPlanMisses() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::TargetPlanCacheMisses(), baseline is null ? 0 : baseline.targetPlanMisses);
    }
    uint CacheTargetPlanRebuilds() {
        auto baseline = _GetCacheMetricsBaseline(_CurrentObservabilityScope(), false);
        return _CounterDelta(UiNav::TargetPlanCacheRebuilds(), baseline is null ? 0 : baseline.targetPlanRebuilds);
    }

    uint LatencySampleCount(const string &in metricName) { return UiNav::Metrics::Count(metricName); }
    float LatencyAvgMs(const string &in metricName) { return UiNav::Metrics::AvgMs(metricName); }
    uint LatencyP50Ms(const string &in metricName) { return UiNav::Metrics::P50Ms(metricName); }
    uint LatencyP95Ms(const string &in metricName) { return UiNav::Metrics::P95Ms(metricName); }
    uint LatencyMaxMs(const string &in metricName) { return UiNav::Metrics::MaxMs(metricName); }
    uint LatencyLastMs(const string &in metricName) { return UiNav::Metrics::LastMs(metricName); }

    void ResetLatencyMetrics() {
        UiNav::Metrics::Reset();
    }

    void ResetCacheMetricBaselines() {
        string scopeId = _CurrentObservabilityScope();
        auto baseline = _GetCacheMetricsBaseline(scopeId, true);
        _CaptureCacheMetricsBaseline(baseline);
    }

    void ResetCacheMetrics() {
        ResetCacheMetricBaselines();
    }

}
