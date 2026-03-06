# UiNav

UiNav is an Openplanet library/plugin for finding and interacting with Trackmania UI.
It supports:
- **ManiaLink UI (ML / UILayers)** for layer/page-based UI work.
- **ControlTree UI (control-tree overlays)** for overlay tree/path-based UI work.

## Public API

Dependent plugins should only rely on:
- `src/Exports/api.as` (public function imports)
- `src/core/types.as` (shared types like `Target`, `ManiaLinkReq`, `ManiaLinkSpec`, `ControlTreeReq`, `ControlTreeSpec`, `NodeRef`)

Everything else in `src/` is considered internal implementation detail.

`UiNav::ML` exports include both single-node snapshot helpers and multi-element **style pack** helpers
for capturing/reusing styling across menus/layers (`NewStylePack`, `StylePackAddEntry*`, `StylePackApply`, save/load JSON).

## Debug tooling

UiNav includes its own inspector/debug tooling and dump request pump.
Most of it is gated behind `Show dev tabs` (UiNav settings -> `General`).

Dev tabs:
- `Selector` (click-to-pick elements by bounds)
- `ManiaLink UI` (ML inspector + code/selector generator)
- `ControlTree UI` (overlay inspector + code/selector generator)
- `ManiaLink Builder` (authoring + live-layer import + preview overlays)
- `ManiaLink Browser` (asset/url discovery + previews, incl DDS)
- `Diagnostics` (breadcrumbs, trace ring buffer, request pump policy)

## Docs

See `DOCUMENTATION.md` for usage, examples, and selector syntax.
