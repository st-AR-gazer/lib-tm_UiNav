namespace UiNav {
namespace Debug {

    class MlBrowserTreeNode {
        string name;
        string key;
        bool isFile = false;
        MlBrowserEntry@ entry = null;
        array<MlBrowserTreeNode@> children;
    }

    class MlBrowserFidsScanState {
        int remaining = 0;
        bool timedOut = false;
        bool capped = false;
        uint startedAtMs = 0;
        uint timeBudgetMs = 0;
    }

    dictionary g_MlBrowserConvertedPathCache;
    dictionary g_MlBrowserConvertedErrorCache;
    bool g_MlBrowserConvertJobRunning = false;
    string g_MlBrowserConvertJobUrl = "";
    string g_MlBrowserConvertJobRawPath = "";
    string g_MlBrowserConvertQueuedUrl = "";
    string g_MlBrowserConvertQueuedRawPath = "";
    uint g_MlBrowserConvertJobStartedMs = 0;
    uint g_MlBrowserPreviewLoadStartedMs = 0;
    uint g_MlBrowserPreviewLastAttemptMs = 0;

    MlBrowserTreeNode@ g_MlBrowserTreeCacheRoot = null;
    string g_MlBrowserTreeCacheFilter = "";
    uint g_MlBrowserTreeCacheEntryCount = 0;
    int g_MlBrowserTreeCacheShownFiles = 0;
    int g_MlBrowserTreeCacheTotalFiles = 0;
    bool g_MlBrowserTreeCacheTruncated = false;
    bool g_MlBrowserTreeCacheDirty = true;
    uint g_MlBrowserTreeLastBuildMs = 0;
    bool g_MlBrowserBuildTruncated = false;
    int g_MlBrowserBuildNodeCount = 0;
    int g_MlBrowserBuildMaxNodes = 35000;

    const int ML_BROWSER_QUAD_APPLY_IMAGE_ONLY = 0;
    const int ML_BROWSER_QUAD_APPLY_FIT_WIDTH_BY_HEIGHT = 1;
    const int ML_BROWSER_QUAD_APPLY_FIT_HEIGHT_BY_WIDTH = 2;

}
}
