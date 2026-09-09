# DEVELOPMENT.md — Workspace Grid plugin

Developer guide for contributors working on this plugin.

## What this plugin is

A **bar widget** for the Omarchy desktop shell that replaces the built-in
`omarchy.workspaces` with a 2D grid of workspaces (`3 × 2` by default, filling
row-major), shows the most recently focused app icon per workspace, and adds
arrow-key + touchpad navigation that reuses the same grid math.

It has three cooperating parts:

| Part | Path | Role |
|------|------|------|
| Bar widget | `Grid.qml` | Rendering + clicking (focus / move window) |
| Hyprland config | `hypr/grid.lua` | Keybindings + touchpad gestures |
| Navigation engine | `bin/omarchy-workspace-grid` | Grid math shared by bar binds/gestures |

## Architecture notes (read before editing)

- **Clone lifecycle.** `manifest.json` declares
  `omarchy.clonedFrom: "omarchy.workspaces"`. Omarchy's registry swaps the
  plugin into the built-in workspace slot on `enable` and restores
  `omarchy.workspaces` on `disable`. Do not manually edit the plugin entry out
  of `shell.json` while testing clones — use `omarchy plugin enable|disable`.
- **Grid math lives in one place.** `bin/omarchy-workspace-grid` computes the
  destination workspace from the active one (`row = (current-1) / COLS`,
  `col = (current-1) % COLS`). `grid.lua` and the widget must agree on the
  row-major ordering (1 2 3 / 4 5 6). If you change `columns`/`rows` defaults
  or ordering, update **all three** places.
- **Self-locating paths.** `grid.lua` finds its own directory via
  `debug.getinfo(1, "S").source` so the plugin works from any install path.
  Keep that; do not hardcode `~/.local/bin` or the plugin id into engine paths.
- **Binds must never be blocked.** Gesture registration in `grid.lua` is
  wrapped in `pcall` deliberately — a Hyprland error there must not abort the
  `o.bind()` calls that follow. Preserve that ordering and the pcalls.
- **No `os.setenv` in `grid.lua`.** Setting process env inside Hyprland's Lua
  config silently breaks every subsequent `o.bind()` registration with no
  error message. Do not reintroduce it.
- **No `_G`-guard memoization.** Hyprland re-runs this file on every
  `hyprctl reload`, and `_G` persists across reloads. A
  `if _G.omarchy_workspace_grid_loaded then return end` guard would prevent
  re-registration after a reload. If idempotence is ever needed, do it in the
  shell plugin (bar config), not in the Lua.
- **Cell sizing caps to the bar.** `Grid.qml` caps `cellSize` so the whole grid
  always fits `barSize`; `gridSize` is only an upper bound on width. If you
  add content to a cell, keep it inside `cellSize`.
- **Icon index is a fast shell script.** `bin/omarchy-icon-index` builds a
  `class → file://icon` JSON map from live `hyprctl clients` output; the same
  output also feeds a per-window `[{w,c,f}]` map (`"windows"` key) used by the
  cells as their authoritative class source (see above). The script reads
  `hyprctl` once and pipes the snapshot through `jq` for both sections.
  Resolution order: curated alias (`aliased_name`) → `StartupWMClass=…` desktop
  entry
  (`Icon=`; matched case-insensitively, so `Cursor` matches window class
  `cursor`) → browser-PWA domain (e.g. `chrome-youtube.com__-Default`)
  matched against desktop ids/names, with a curated web-app map for common
  PWA domains (Telegram, WhatsApp, YouTube; `pwa_alias`) → direct
  class-as-icon-name. Icon files. Icon files
  are found by probing every theme's `scalable/apps`, `SIZE/apps` and flat
  pixmaps paths (single-pass, ~120ms) — never by scanning whole trees, which
  degrades to seconds. Missing icons fall back to `application-x-executable`
  so tiles are never blank.
- **Instant refresh.** `Grid.qml` listens to `Hyprland.rawEvent`: window
  open/close/move triggers a debounced (200ms) icon-index rerun; focus /
  workspace / fullscreen changes just bump `iconRevision` to re-pick the
  most-recently-focused window without re-running the script. After a debounce
  fires, a staggered timer re-bumps `iconRevision` at 400ms intervals (4
  times) so a toplevel that is identified a beat late (fresh app, newly
  created empty workspace) still pops its icon in ~1s instead of on the 3s
  safety-net timer. The cache is also populated once at startup via
  `Component.onCompleted` (not on the first 3s tick) so occupied cells show
  icons immediately. A `requestIconRefresh` + `iconDirty` pair ensures a
  refresh that arrives while the process is already running is not dropped.
- **Cell bindings depend on `iconRevision`.** `focusedWindows` and
  `windowClasses` are IIFEs that read `root.iconRevision` so they re-evaluate
  on every refresh.
- **Class source is hyprctl, not Quickshell toplevels.** In this Quickshell
  build, `Toplevel.class`/`initialClass`/`lastIpcObject` stay empty for windows
  that open **after** the shell started (only pre-start toplevels carry a
  payload). Cells therefore read their per-workspace classes from a live
  `hyprctl` window map (`winCache`, shape
  `[{w, c, f}]` = workspace/class/focusHistoryID) emitted by
  `bin/omarchy-icon-index` as the `"windows"` key of its JSON. `winClassesFor`
  picks the two most-recently-focused classes per workspace. The Quickshell
  toplevel path remains only as a startup fallback. This is what makes a
  freshly opened app (e.g. on a brand-new empty workspace) appear in its cell
  within ~0.5s.
- **Active indicator is an accent pill, never a circle.** The focused cell
  gets a soft accent pill (`Color.accent` at 0.32 fill / 0.55 border). Empty
  workspaces always render their workspace **number** (dimmed unless
  focused); there is deliberately no `●` glyph — it read as a "white circle
  on an empty workspace" and was removed. The `WidgetButton` keeps
  `useActiveColor: false` so the default `activeColor` (`bar.urgent`, red)
  never shows.

## Conventions

- Keep `manifest.json` and `README.md` in sync:
  - every `barWidget.defaults` key must exist in `schema` with matching type;
  - every schema entry should be reflected in the README settings table;
  - bump `version` (`X.Y.Z`) on any behavior change.
- Manifest is validated as JSON: run
  `omarchy plugin validate <plugin-dir>` after editing.
- QML/style: mirror existing Omarchy shell widgets (`BarWidget`,
  `WidgetButton`, `Style.space*()`, `root.setting(...)` for config). Reuse
  `root.bar.run(...)` for hyprctl dispatches. Injected props are `bar`,
  `moduleName`, `settings`.
- Shell scripting: `set -euo pipefail`, use `jq`, keep `hyprctl dispatch
  "hl.dsp.focus({ workspace = \"N\" })"` form used elsewhere in omarchy.

## Testing checklist (run after any change)

1. `omarchy plugin validate <plugin-dir>` — manifest OK.
2. Restart the shell: `omarchy restart shell`; check `journalctl --user -u
   omarchy-shell` for QML errors.
3. Confirm binds registered:
   `hyprctl binds -j | jq '[.[] | select(.description | startswith("Grid:"))]'`
   → expect 8 (4 focus + 4 move). Verify `hyprctl configerrors` is empty.
4. Grid math (from a known workspace): `OMARCHY_WS_DRYRUN=1
   <plugin-dir>/bin/omarchy-workspace-grid <direction>` and compare against the
   visual layout (row-major).
5. Clone cycle: `omarchy plugin disable com.robi.workspace-grid` → `shell.json`
   left layout regains `omarchy.workspaces`; `enable` → regains the grid.

## Context values

- Username: `robi`; plugin lives at
  `~/.config/omarchy/plugins/com.robi.workspace-grid/`.
- Reference widget: `/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml`
  (the built-in this plugin clones); shared UI:
  `/usr/share/omarchy/shell/Ui/WidgetButton.qml` and `BarWidget.qml`.
- Omarchy plugin registry semantics live in
  `/usr/share/omarchy/shell/services/PluginRegistry.qml` (clone/restore logic).
- Never write secrets to the repo; the plugin must stay self-contained
  (no dependency on files outside its directory).