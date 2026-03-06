namespace UiNav {

    const uint kApiVersionMajor = 1;
    const uint kApiVersionMinor = 0;
    const uint kApiVersionPatch = 0;

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

    uint ContextEpoch() {
        return UiNav::Context::Epoch();
    }

    uint ContextEpochBumps() {
        return UiNav::Context::EpochBumps();
    }

    bool RefreshContext() {
        return UiNav::Context::Refresh(true);
    }

    void InvalidateAllCaches(const string &in reason = "manual") {
        UiNav::Context::InvalidateAll(reason);
    }

    uint CacheLayerFrameMemoHits() { return UiNav::Layers::LayerReqFrameMemoHits(); }
    uint CacheLayerFrameMemoMisses() { return UiNav::Layers::LayerReqFrameMemoMisses(); }
    uint CacheLayerFrameMemoNegativeHits() { return UiNav::Layers::LayerReqFrameMemoNegativeHits(); }
    uint CacheLayerReqHintHits() { return UiNav::Layers::LayerReqCacheHits(); }
    uint CacheLayerReqHintMisses() { return UiNav::Layers::LayerReqCacheMisses(); }

    uint CacheSelectorTokenHits() { return UiNav::ML::SelectorCacheHits(); }
    uint CacheSelectorTokenMisses() { return UiNav::ML::SelectorCacheMisses(); }
    uint CacheSelectorTokenEvictions() { return UiNav::ML::SelectorCacheEvictions(); }
    uint CacheSelectorTokenSize() { return UiNav::ML::SelectorCacheSize(); }
    float CacheSelectorTokenHitRate() { return UiNav::ML::SelectorCacheHitRate(); }

    uint CacheTargetPlanHits() { return UiNav::TargetPlanCacheHits(); }
    uint CacheTargetPlanMisses() { return UiNav::TargetPlanCacheMisses(); }
    uint CacheTargetPlanRebuilds() { return UiNav::TargetPlanCacheRebuilds(); }

    uint LatencySampleCount(const string &in metricName) { return UiNav::Metrics::Count(metricName); }
    float LatencyAvgMs(const string &in metricName) { return UiNav::Metrics::AvgMs(metricName); }
    uint LatencyP50Ms(const string &in metricName) { return UiNav::Metrics::P50Ms(metricName); }
    uint LatencyP95Ms(const string &in metricName) { return UiNav::Metrics::P95Ms(metricName); }
    uint LatencyMaxMs(const string &in metricName) { return UiNav::Metrics::MaxMs(metricName); }
    uint LatencyLastMs(const string &in metricName) { return UiNav::Metrics::LastMs(metricName); }

    void ResetLatencyMetrics() {
        UiNav::Metrics::Reset();
    }

    void ResetCacheMetrics() {
        UiNav::Layers::ResetCacheStats();
        UiNav::ML::ResetSelectorCacheStats();
        UiNav::ResetTargetPlanCacheStats();
    }

}
