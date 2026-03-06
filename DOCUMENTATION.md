# UiNav

UiNav is an Openplanet library/plugin for finding and interacting with Trackmania UI.
It has two backends:

- ManiaLink UI (ML): `CGameUILayer` -> `LocalPage` -> `MainFrame` -> `CGameManialinkControl`
- ControlTree UI: overlay control trees (`CDx11Viewport.Overlays` -> `CScene2d` -> `CControlBase`)

UiNav also ships in-game developer tooling (inspectors, selector, builder, browser, diagnostics) that helps you *discover* selectors/paths and then turn them into stable `UiNav::Target`s for automation.

## Using UiNav As A Dependency (Public API)

### Add the dependency

Add `UiNav` to your plugin's `info.toml`:

```toml
[script]
dependencies = ["UiNav"]
```

UiNav exports its API as dependency exports, so you can call `UiNav::...` directly.

### Public contract (what is safe to depend on)

UiNav intentionally keeps a strict public surface:

- Exported imports: `src/Exports/api.as`
- Shared types: `src/core/types.as` (declared `shared`)

Everything else under `src/core/*` (other than `types.as`) and all debug tooling under `src/debug/*` is internal and may change.

Note: `src/Exports/types.as` currently exists but is empty; types are provided via `shared_exports = ["src/core/types.as"]` in `info.toml`.

### Version gating

```angelscript
if (!UiNav::ApiVersionAtLeast(0, 1, 0)) {
    // Handle old/missing UiNav (or disable your feature).
}
```

## Core Types And Concepts

### Backend enums

- `BackendKind`: `None`, `ControlTree`, `ML`
- `BackendPref`: `Auto`, `PreferControlTree`, `PreferML`
- `OpStatus`: `Ok`, `InvalidTarget`, `RequirementsFailed`, `ResolveFailed`, `InvalidBackendRef`, `NotVisible`, `ActionFailed`, `TimedOut`

### `Target`

`UiNav::Target` describes *what* you want to find and *how* to act on it.
You typically allocate it once and keep reusing it.

Key fields:

- `name`: debug label (shows up in trace/diagnostics)
- `pref`: backend preference (`Auto` tries ML first if `ml` exists)
- `ml`: `ManiaLinkSpec@` (optional)
- `controlTree`: `ControlTreeSpec@` (optional)
- `req`: `Requires@` (optional preconditions)
- Caching:
  - `cacheNativePointers` (default `true`)
  - `cacheTtlMs` (default `200`)

If you're targeting volatile UI (scoreboards, dynamic lists), disable caching:

```angelscript
t.cacheNativePointers = false;
t.cacheTtlMs = 0;
```

### `NodeRef` and `OpResult`

- `UiNav::Resolve(Target@)` returns a `NodeRef@` (or `null`) that contains the resolved pointers + some metadata.
- Most convenience APIs return a simple `bool`/`string`.
- The `*Ex` variants return `UiNav::OpResult@` with structured failure info:
  - `status` (`OpStatus`)
  - `reason` (human-readable)
  - `kind` (backend used)
  - `ref` (`NodeRef@`) when available
  - `text` for `ReadTextEx`

In practice: use `*Ex` while developing/debugging and switch to the simple variants once stable.

### Requirements (`Requires`)

`UiNav::Requires` lets you define "only run when X is present":

- `overlaysAll` / `overlaysAny`: ControlTree overlays that must exist
- `layersAll` / `layersAny`: ManiaLink layers that must exist (as `ManiaLinkReq@`)
- `requireTargetVisible`: if `true`, actions fail with `NotVisible` when the resolved node is not visible
- `strict`: affects `Resolve(Target@)` behavior (strict requirements -> return `null` when unmet)

## Describing UI: ML vs ControlTree

### `ManiaLinkReq` (layer selection)

`UiNav::ManiaLinkReq` identifies a `CGameUILayer`:

- `mustBeVisible` (default `true`): require `layer.IsVisible`
- `mustHaveLocalPage` (default `true`): require `layer.LocalPage != null` and `LocalPage.MainFrame != null` for "active"
- `pageNeedle`: substring that must exist in `layer.ManialinkPage` or `ManialinkPageUtf8`
- `rootControlId`: require that the ML tree contains a node with this `ControlId`
- `layerIxHint`: optional index hint (faster/more stable when you already know the layer index)

### `ManiaLinkSpec` (node selection inside a layer)

`UiNav::ManiaLinkSpec` selects a node inside the chosen layer:

- `req`: `ManiaLinkReq@` (`layer` remains supported as a legacy alias)
- `selector`: ML selector string (see syntax below)
- `requireVisible` (default `true`): require `n.Visible`
- `clickChildFallback` (default `true`): if the resolved node isn't directly clickable, try clickable immediate children
- `alts`: alternate selectors (use `AddAlt`)

### `ControlTreeReq` (root search)

`UiNav::ControlTreeReq` defines how to discover candidate roots:

- `overlay` (default: `16` in spec; optional in `req`)
- `anyRoot`: scan multiple roots (`scene.Mobils`) instead of only `Mobils[0]`
- `maxRoots`: limit any-root scan (default 24)
- `smart`: do deeper candidate exploration when wildcards are present
- `hintsOnly`: reject wildcard steps without hints
- `guardStartsWith`: prioritize subtrees whose label text starts with this prefix
- `overlay` / `anyRoot` / `maxRoots` defaults are intentionally mirrored into `ControlTreeSpec` for convenience.

### `ControlTreeSpec` (node selection)

`UiNav::ControlTreeSpec` defines how to select a control inside the chosen root:

- `selector`: selector/path syntax (see below); `path` remains supported as a legacy alias
- `idName`: match by `CControlBase.IdName` (recursive fallback when the selector is unstable)
- `requireVisible`: require resolved control is visible
- `clickChildFallback`: same fallback behavior as ML selectors
- `alts`: alternate specs when the primary path is brittle

`ControlTreeSpec` can either set root search fields directly (`overlay`, `anyRoot`, ...) or reference a `ControlTreeReq@` via `spec.req`.

## Typical Usage Pattern (Public API)

Workflow:

1. Build a `Target` (once).
2. `PrepareTarget(target)` (recommended if you'll reuse it).
3. `WaitForTarget(target)` or `IsReadyEx(target)` before acting.
4. Act: `Click`, `ReadText`, `SetText`.

Example: read text from a label in a specific ML layer:

```angelscript
UiNav::ManiaLinkReq@ req = UiNav::ManiaLinkReq("PauseMenu", "SomeUniqueNeedleInThePage");

UiNav::ManiaLinkSpec@ ml = UiNav::ManiaLinkSpec();
@ml.req = req;
ml.selector = "#SomeLabelId";
ml.requireVisible = true;

UiNav::Target@ t = UiNav::Target();
t.name = "Pause label";
@t.ml = ml;
t.pref = UiNav::BackendPref::PreferML;

UiNav::PrepareTarget(t);
if (UiNav::WaitForTarget(t, 2000, 33)) {
    string txt = UiNav::ReadText(t);
}
```

Example: click a ControlTree node with mixed selector syntax:

```angelscript
UiNav::ControlTreeReq@ req = UiNav::ControlTreeReq();
req.overlay = 16;
req.anyRoot = true;
req.maxRoots = 24;

UiNav::ControlTreeSpec@ ct = UiNav::ControlTreeSpec();
@ct.req = req;
ct.selector = "overlay[16]/root[0]/#InterfaceRoot/#FrameSystem/#FrameSound/#ButtonMusicVolume";
ct.requireVisible = true;

UiNav::Target@ t = UiNav::Target();
t.name = "Music volume";
@t.controlTree = ct;
t.pref = UiNav::BackendPref::PreferControlTree;

if (UiNav::WaitForTarget(t, 2000, 33)) {
    UiNav::Click(t);
}
```

### Alternates (`alts`)

Both `ManiaLinkSpec` and `ControlTreeSpec` support alternates:

```angelscript
UiNav::ManiaLinkReq@ req = UiNav::ManiaLinkReq("PauseMenu", "SomeUniqueNeedleInThePage");

UiNav::ManiaLinkSpec@ ml = UiNav::ManiaLinkSpec();
@ml.req = req;
ml.selector = "#MainLayout/#ButtonOk";

UiNav::ManiaLinkSpec@ alt = UiNav::ManiaLinkSpec();
@alt.req = req;
alt.selector = "#AltLayout/#ButtonOk";
ml.AddAlt(alt);
```

## Selector Syntax (ML)

ML selectors are `/`-separated paths resolved against a `CGameManialinkControl@` root.
Each segment can select a direct child, or (with `**`) a descendant.

Segment forms:

- `#id` or `id`: match `ControlId`
- `.class`: match by `ControlClasses` entry
- `N`: numeric index (0-based) in the children list
- `*` or empty: wildcard match
- `**` prefix: search descendants (BFS) instead of direct children
- `:n` suffix: pick nth match at that step (0-based, default `0`)

Examples:

```text
#Race_ScoresTable/**.text-bold:0
**#frame-scorestable-layer/0/2
.my-class:1
```

Practical tips:

- Prefer ids when possible.
- Use classes only when ids are missing; many nodes share classes.
- Use `:n` when a step matches multiple nodes.
- Use numeric-only paths only as a last resort; indexes drift as UI changes.

## Selector Syntax (ControlTree)

ControlTree selectors live in `ControlTreeSpec.selector` (`path` is still accepted as a legacy alias).
UiNav supports two styles, and will auto-pick the correct resolver:

### 1) Pure index paths (fast)

Use `/`-separated indices (0-based). Wildcards are allowed.

- `1/0/3` selects child 1, then 0, then 3.
- `*` selects "some child". By default it picks the first child unless you provide hints.

Wildcard hints (choose a specific child index at that wildcard step):

- `*<4>`
- `*<4,7>` or `*<4|7>`
- `*[4,7]` or `*{4,7}`

Examples:

```text
0/1/5
0/*<2>/3
0/*<2|5>/3
```

### 2) Mixed paths (id + index + overlay/root hints)

Mixed paths use `/` separators and allow:

- `overlay[16]` and `root[0]` tokens (usually at the front)
- integer indices
- wildcards (`*` with optional hints)
- IdName tokens:
  - `id:SomeIdName`
  - `#SomeIdName`
  - `SomeIdName` (bare token)

IdName tokens match a direct child by `CControlBase.IdName` (and a token can also match the current node).

Examples:

```text
overlay[16]/root[0]/#InterfaceRoot/#FrameSystem/2/*<0>/#ButtonMusicVolume
root[3]/id:InterfaceRoot/0/*<2>/FrameSound
```

### Search modes (`ControlTreeReq` flags)

- `anyRoot=true`: scan multiple roots instead of only `Mobils[0]`.
- `maxRoots`: limits `anyRoot` scanning.
- `smart=true`: when wildcards exist, tries more candidates at wildcard steps.
- `guardStartsWith`: used with `smart` to prioritize subtrees containing label text with a given prefix.
- `hintsOnly=true`: wildcard steps require hints (fail fast if a wildcard has no hints).

If selectors are too unstable, prefer `ControlTreeSpec.idName` (recursive IdName search) for a first pass, then refine to a selector once you can.

## ML Style Packs (Exported)

UiNav exposes a small "style pack" helper set under `UiNav::ML` for capturing and reapplying style-related properties across nodes/layers.
This is useful when:

- You want to reuse a UI theme across multiple screens.
- You want to snapshot and reapply layout changes during development.

Core functions:

- `SnapshotStyleNode(node, includeChildren=false, maxDepth=1, includeTextValues=false)`
- `NewStylePack()`
- `StylePackAddEntry(pack, node, selector="...", ...)`
- `StylePackAddEntryBySelector(pack, root, selector, ...)`
- `StylePackApply(root, pack, applyChildren=false)`
- `SaveStylePackToFile(pack, path)` / `LoadStylePackFromFile(path)`

Example:

```angelscript
// Capture style from a node and apply it later somewhere else.
UiNav::ManiaLinkReq@ layerReq = UiNav::ManiaLinkReq("SomeLayer", "needle");
auto layer = UiNav::Layers::FindLayer(layerReq);
auto root = UiNav::ML::GetRootFrame(layer);

Json::Value@ pack = UiNav::ML::NewStylePack();
UiNav::ML::StylePackAddEntryBySelector(pack, root, "#MyWidget", /*includeChildren=*/true, /*maxDepth=*/3);
UiNav::ML::SaveStylePackToFile(pack, "Exports/ManiaLinks/my_style_pack.json");

// ...
Json::Value@ loaded = UiNav::ML::LoadStylePackFromFile("Exports/ManiaLinks/my_style_pack.json");
UiNav::ML::StylePackApply(root, loaded, /*applyChildren=*/true);
```

Notes:

- Style packs rely on selectors (or an index path) to find destination nodes; use `StylePackAddEntryBySelector` unless you know what you're doing.
- Applying snapshots modifies node properties; treat it like "live patching UI".

## Observability And Caches (Exported)

UiNav exposes cache and latency metrics to help debug "it sometimes works" behavior:

- Context: `ContextEpoch`, `ContextEpochBumps`, `RefreshContext`, `InvalidateAllCaches`
- Cache counters: `CacheLayer*`, `CacheSelectorToken*`, `CacheTargetPlan*`, `ResetCacheMetrics`
- Latency metrics: `Latency*` by name, `ResetLatencyMetrics`

Common metric names: `resolve`, `is_ready`, `wait_for_target`, `click`, `read_text`, `set_text`, `check_requirements`.

## In-Game Developer Tooling (UiNav Plugin)

UiNav includes a dev-focused settings UI.

### Enable dev tabs

Open the UiNav settings and enable `Show dev tabs` in the `General` tab.

Unlocked tabs:

- `Selector`
- `ManiaLink UI`
- `ControlTree UI`
- `ManiaLink Builder`
- `ManiaLink Browser`
- `Diagnostics`

### Common mouse behavior (tree views)

Most tree views follow the same controls:

- Left click: expand/collapse rows
- Right click: select row
- Middle click: context menu

### General

- `Show dev tabs`: enables the dev tooling tabs
- `Destroy all UiNav layers`: removes UiNav-owned layers (useful if a debug overlay got stuck)

### Selector (click-to-pick by bounds)

Selector answers: "What UI element did I click?"

Workflow:

1. Open the `Selector` tab.
2. Click `Arm Picker`.
3. Left-click your target element in the game viewport (click outside the Openplanet UI window).
4. Inspect the hit list (overlapping controls are shown as multiple hits).
5. Optional: click `Sync Selected To ML` to jump to the same element in the `ManiaLink UI` inspector.

Toggles:

- `Source app`: restrict to `Playground`, `Menu`, `Current`, or `All`
- `Include hidden nodes`: include nodes hidden by their own visibility or an ancestor
- `Sync ManiaLink UI selection`: auto-sync top hit to the ML inspector after picking

### ManiaLink UI (ML inspector)

The ML inspector is a live view of `CGameUILayer` and their `MainFrame` trees.

Features:

- Source tabs: `Playground`, `Menu`, `Editor` (when available)
- Search/filter (supports `id:`, `text:`, `class:`, `type:`, `path:`, `vis:true/false`, quoted phrases, `-exclude`)
- Layer focus (`Layer` input: `-1` = all)
- Per-node visibility toggle
- Favorites (quick jump to layers)
- Context menus (middle click) for actions and exports
- Selection pane with tabs:
  - `Overview`: key properties (ids, text, type, pos/size, visibility, etc)
  - `Selectors`: id/class/index selectors and a recommended UiNav selector
  - `Code`: generates a `UiNav::Target` snippet for the current selection
  - `Actions`: show/hide, click, set text (best-effort)
  - `Export`: dump layer page XML, dump subtree, etc
  - `Notes`: per-node notes + value locks (dev-only)

Live bounds overlay integration:

- `Live layer box`: draws bounds for the currently selected ML layer or selected subtree path in live UI.

### ControlTree UI (ControlTree inspector)

The ControlTree inspector shows overlay control trees (`CControlBase`).

Features:

- Overlay filter (`Overlay` input: `-1` = all overlays)
- Search/filter (`id:` matches `IdName`; also supports `text:`, `type:`, `path:`, `vis:true/false`)
- Per-node visibility toggle
- Context menus (middle click) with:
  - selection/focus actions
  - show/hide node
  - copy relative path / display path
- Selection pane tabs mirror the ML inspector (`Overview`, `Selectors`, `Code`, `Actions`, `Export`, `Notes`)

### ManiaLink Builder

Builder is an in-plugin ManiaLink authoring tool that can also clone/import live UI layers for editing.

Common workflows:

- Create/edit from scratch:
  - `New` -> build a tree of `frame`/`quad`/`label`/`entry` nodes
  - use `Preview` to apply to a UiNav-owned layer for iteration
- Import a live layer:
  - In `ManiaLink UI`, middle-click a layer row -> `Copy layer to Builder`
  - Edit in Builder (`Edit` tab), then preview/export
- Import from XML:
  - `I/O` tab -> paste XML -> import

Builder tabs:

- `Edit`: tree + properties editor (right click selects; middle click opens node menu)
- `Preview`: apply live preview + debug overlays (bounds/origin/selected bounds)
- `I/O`: import/export XML, diff against baseline, write to file
- `Code`: helper exports (builder-specific)
- `Settings`: behavior toggles (auto-preview, strip clipping on import, diagnostics, self-tests)

If a frame's clipping hides children that overflow their parent, enable `Strip frame clipping on import` in Builder settings and re-import the live layer.

### ManiaLink Browser

ManiaLink Browser helps you find image URLs referenced by UI and preview them.

Features:

- `Refresh` scans:
  - live ML layer XML (`image=...`, `imagefocus=...`, etc.)
  - optional filesystem root
  - optional Nadeo Fids tree (game assets)
- Search/filter + favorites
- Preview loader with optional "resolve via Fids" and auto-preview on selection
- DDS support (dev-oriented) for previews

### Diagnostics

Diagnostics provides runtime tooling:

- Crash breadcrumbs (writes last-known step to a file)
- Trace ring buffer (in-memory trace events; dump/copy/clear)
- Step logging (Openplanet log; optional verbose mode)
- Dump request pump policy (`Disabled`, `Dev-only`, `Always`)

## Dump Request Pump (Automation)

UiNav runs a file-based "dump request pump" in `Main()`.
It is intended for development tooling.

When enabled, it polls:

- Requests: `IO::FromStorageFolder("opdev/uinav/requests")`
- Responses: `IO::FromStorageFolder("opdev/uinav/responses")`

Each request is a `.json` file. UiNav processes one request per poll interval and writes a response JSON to the responses folder.

Request shape (fields can be top-level or inside `data`):

```json
{
  "request_id": "example-1",
  "action": "dump_ui",
  "include_ml": true,
  "include_control_tree": true,
  "include_layer_pages": false,
  "app_kind": 2,
  "layer_ix": -1,
  "overlay": 16,
  "max_depth": 6,
  "max_nodes": 3500,
  "max_elapsed_ms": 250,
  "write_file": true,
  "output_path": "Diagnostics/ui_dump.txt"
}
```

## Troubleshooting

### Target never resolves

- Make your `ManiaLinkReq` specific: use `pageNeedle` and/or `rootControlId`.
- Use `IsReadyEx` / `WaitForTargetEx` and inspect `OpResult.status` + `OpResult.reason`.
- Use the in-game inspectors to generate selectors and code snippets.

### It works sometimes then stops

Common causes: page rebuilds, stale pointers, or a plan cached against old UI.

- Disable caching (`cacheNativePointers=false`, `cacheTtlMs=0`)
- Call `UiNav::InvalidateTargetPlan(t)` if you mutate a target or after major UI transitions
- Prefer `*Ex` calls while stabilizing selectors

### Hard crash when touching nodes

Almost always stale native handles:

- Keep handle usage short-lived.
- Validate ML refs before touching `NodeRef.ml`:

```angelscript
UiNav::NodeRef@ r = UiNav::Resolve(t);
if (r !is null && r.kind == UiNav::BackendKind::ML && UiNav::ValidateML(r)) {
    // Use r.ml briefly here.
}
```
