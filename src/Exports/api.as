// UiNav Public API (imports)
// --------------------------
//
// This file is exported to dependent plugins. It declares imported functions that are
// implemented by the UiNav plugin module ("UiNav").
//
// Public rule: dependent plugins should only rely on items declared here + shared types
// from `src/core/types.as`.
//
// Everything else in UiNav's source tree is considered internal and may change.

namespace UiNav {
    import uint ApiVersionMajor() from "UiNav";
    import uint ApiVersionMinor() from "UiNav";
    import uint ApiVersionPatch() from "UiNav";
    import string ApiVersionString() from "UiNav";
    import bool ApiVersionAtLeast(uint major, uint minor = 0, uint patch = 0) from "UiNav";

    import NodeRef@ Resolve(Target@ t) from "UiNav";
    import bool IsReady(Target@ t) from "UiNav";
    import OpResult@ IsReadyEx(Target@ t) from "UiNav";
    import bool WaitForTarget(Target@ t, int timeoutMs = 4000, int pollMs = 33) from "UiNav";
    import OpResult@ WaitForTargetEx(Target@ t, int timeoutMs = 4000, int pollMs = 33) from "UiNav";

    import bool Click(Target@ t) from "UiNav";
    import OpResult@ ClickEx(Target@ t) from "UiNav";
    import bool SetText(Target@ t, const string &in text) from "UiNav";
    import OpResult@ SetTextEx(Target@ t, const string &in text) from "UiNav";
    import string ReadText(Target@ t) from "UiNav";
    import OpResult@ ReadTextEx(Target@ t) from "UiNav";
    import void PrepareTarget(Target@ t) from "UiNav";
    import void InvalidateTargetPlan(Target@ t) from "UiNav";

    import bool ValidateML(NodeRef@ r) from "UiNav";

    import bool IsEffectivelyVisible(CControlBase@ n) from "UiNav";
    import string CleanUiFormatting(const string &in s) from "UiNav";

    import uint ContextEpoch() from "UiNav";
    import uint ContextEpochBumps() from "UiNav";
    import bool RefreshContext() from "UiNav";
    import void InvalidateAllCaches(const string &in reason = "manual") from "UiNav";

    import uint CacheLayerFrameMemoHits() from "UiNav";
    import uint CacheLayerFrameMemoMisses() from "UiNav";
    import uint CacheLayerFrameMemoNegativeHits() from "UiNav";
    import uint CacheLayerReqHintHits() from "UiNav";
    import uint CacheLayerReqHintMisses() from "UiNav";

    import uint CacheSelectorTokenHits() from "UiNav";
    import uint CacheSelectorTokenMisses() from "UiNav";
    import uint CacheSelectorTokenEvictions() from "UiNav";
    import uint CacheSelectorTokenSize() from "UiNav";
    import float CacheSelectorTokenHitRate() from "UiNav";
    import uint CacheTargetPlanHits() from "UiNav";
    import uint CacheTargetPlanMisses() from "UiNav";
    import uint CacheTargetPlanRebuilds() from "UiNav";
    import void ResetCacheMetrics() from "UiNav";

    import uint LatencySampleCount(const string &in metricName) from "UiNav";
    import float LatencyAvgMs(const string &in metricName) from "UiNav";
    import uint LatencyP50Ms(const string &in metricName) from "UiNav";
    import uint LatencyP95Ms(const string &in metricName) from "UiNav";
    import uint LatencyMaxMs(const string &in metricName) from "UiNav";
    import uint LatencyLastMs(const string &in metricName) from "UiNav";
    import void ResetLatencyMetrics() from "UiNav";
}

namespace UiNav { namespace Layers {
    import CGameUILayer@ FindLayer(const ManiaLinkReq@ req) from "UiNav";
    import CGameUILayer@ FindLayer(const ManiaLinkReq@ req, int &out layerIx) from "UiNav";
    import bool LayerLooksActiveBestEffort(CGameUILayer@ layer) from "UiNav";
} }

namespace UiNav { namespace ML {
    import CGameManialinkFrame@ GetRootFrame(CGameUILayer@ layer) from "UiNav";
    import CGameManialinkControl@ ResolveSelector(const string &in selector, CGameManialinkControl@ start) from "UiNav";
    import CGameManialinkControl@ FindFirstById(CGameManialinkControl@ root, const string &in id) from "UiNav";

    import bool IsVisible(CGameManialinkControl@ n) from "UiNav";
    import string ReadText(CGameManialinkControl@ n) from "UiNav";
    import bool SetText(CGameManialinkControl@ n, const string &in text) from "UiNav";

    import bool Show(CGameManialinkControl@ n) from "UiNav";
    import bool Hide(CGameManialinkControl@ n) from "UiNav";

    import Json::Value@ SnapshotStyleNode(CGameManialinkControl@ n, bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false) from "UiNav";
    import Json::Value@ NewStylePack() from "UiNav";
    import int StylePackEntryCount(const Json::Value@ pack) from "UiNav";
    import bool StylePackAddEntry(Json::Value@ pack, CGameManialinkControl@ n, const string &in selector = "", bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false, const string &in name = "") from "UiNav";
    import bool StylePackAddEntryBySelector(Json::Value@ pack, CGameManialinkControl@ root, const string &in selector, bool includeChildren = false, int maxDepth = 1, bool includeTextValues = false, const string &in name = "") from "UiNav";
    import int StylePackApply(CGameManialinkControl@ root, const Json::Value@ pack, bool applyChildren = false) from "UiNav";
    import string StylePackToJson(const Json::Value@ pack) from "UiNav";
    import Json::Value@ StylePackFromJson(const string &in jsonText) from "UiNav";
    import bool SaveStylePackToFile(const Json::Value@ pack, const string &in path) from "UiNav";
    import Json::Value@ LoadStylePackFromFile(const string &in path) from "UiNav";
} }
