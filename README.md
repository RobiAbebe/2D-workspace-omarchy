# Workspace Grid

A 2D grid workspace switcher for the Omarchy bar. The grid replaces the
built-in `omarchy.workspaces` widget while the plugin is enabled; disabling the
plugin automatically restores `omarchy.workspaces` in the same bar slot.

Workspaces fill the grid **row-major** (left to right, row by row):

```
1  2  3
4  5  6
```

---

## Features

### Bar widget (`Grid.qml`)

- **Grid layout** — `columns` × `rows` cells; workspaces fill left to right,
  then wrap to the next row (configurable, defaults 3 × 2).
- **Click to focus** — left-click a workspace to switch to it.
- **Right-click to move** — right-click a workspace to move the focused window
  there.
- **App icons** — each occupied workspace shows the icon of its most recently
  focused window (up to two). Icons refresh instantly when windows open, close
  or move (and on focus changes) via `bin/omarchy-icon-index`, which resolves
  the window `class` against desktop entries — `StartupWMClass` (case-
  insensitive), browser-PWA domain (Chromium/Edge web apps), curated aliases —
  then themed icon names, then a generic application icon so tiles are never
  blank.
- **Active-workspace pill** — the focused cell is highlighted with a soft
  accent pill (accent colour at low opacity, 1px border).
- **Numbers** — empty workspaces always show their number; workspace 10
  renders as `0`. Numbers hide when icons are shown (unless
  `alwaysShowNumbers`). There is no active-circle glyph.
- **Workspace tooltip** — hovering any cell shows `Workspace N`.
- **Vertical bar support** — on a left/right bar the grid becomes a single
  column of `rows` workspaces.
- **Auto-sized cells** — cell width caps to `gridSize` and height is computed
  so the whole grid always fits the bar height.

### Keyboard & touchpad (`hypr/grid.lua`, optional)

- **Ctrl+Alt+Arrows** — switch to the neighboring workspace in the given grid
  direction.
- **Super+Ctrl+Alt+Arrows** — move the focused window to the neighboring
  workspace.
- **Three-finger touchpad swipe** — navigate the grid (swipe direction is
  inverted: swiping left moves right in the grid, etc.).
- **Workspace fade animation** — the gesture triggers a smooth crossfade (no
  sideways slide) between workspaces; speed/curve are mirrored from
  `~/.config/hypr/looknfeel.lua`.

### Lifecycle

- **Clone of `omarchy.workspaces`** — enabling the plugin swaps it into the
  built-in workspace slot; disabling removes it and restores
  `omarchy.workspaces` in the exact same position.
- **Self-contained** — the navigation engine lives inside the plugin
  (`bin/`), so the plugin works wherever it is installed.

---

## Installation

```sh
omarchy plugin add <this-repo-url>
omarchy plugin enable com.robi.workspace-grid
```

Enabling the plugin puts the grid in the bar. For arrow-key navigation and
touchpad gestures, Hyprland must also load the plugin config. Add a guarded
include at the end of `~/.config/hypr/hyprland.lua`:

```lua
-- Workspace Grid: touchpad gestures + arrow-key 2D navigation.
local grid_plugin_root = (os.getenv("HOME") or "")
  .. "/.config/omarchy/plugins/com.robi.workspace-grid/hypr"
local grid_plugin_file = grid_plugin_root .. "/grid.lua"
local f = io.open(grid_plugin_file, "r")
if f then f:close(); dofile(grid_plugin_file) end
```

---

## Disabling

Disable from the omarchy menu / shell settings, or:

```sh
omarchy plugin disable com.robi.workspace-grid
```

The plugin is removed from the bar layout and `omarchy.workspaces` is restored
in its place. Re-enabling swaps the grid back in.

---

## Customization

Settings are set from the plugin's settings form or the `shell.json` bar entry:

| Setting             | Type    | Default | Meaning                                        |
|---------------------|---------|---------|------------------------------------------------|
| `columns`           | integer | 3       | Grid columns (workspaces fill left→right)      |
| `rows`              | integer | 2       | Grid rows                                      |
| `gridSize`          | integer | 20      | Cell width in px (height caps to fit bar)      |
| `clampEdges`        | boolean | true    | Stop at grid edges instead of wrapping         |
| `showIcons`         | boolean | true    | Show the focused app's icon on occupied cells  |
| `alwaysShowNumbers` | boolean | false   | Keep the number visible even with an icon      |

### Engine environment variables (`bin/omarchy-workspace-grid`)

| Variable            | Default | Meaning                                           |
|---------------------|---------|---------------------------------------------------|
| `OMARCHY_WS_COLS`   | 3       | Grid columns used for navigation math             |
| `OMARCHY_WS_ROWS`   | 2       | Grid rows used for navigation math                |
| `OMARCHY_WS_CLAMP`  | 1       | `0` wraps around grid edges instead of clamping   |
| `OMARCHY_WS_DRYRUN` | 0       | `1` prints `current -> next` instead of acting    |

---

## Layout

```
com.robi.workspace-grid/
├── manifest.json            # Plugin manifest (id, kinds, settings schema,
│                            #   and omarchy.clonedFrom: "omarchy.workspaces")
├── Grid.qml                 # The bar widget
├── README.md                # This file
├── DEVELOPMENT.md           # Developer guide for contributors
├── LICENSE                  # MIT
├── bin/
│   └── omarchy-workspace-grid   # Shared grid navigation engine (bash)
└── hypr/
    └── grid.lua             # Hyprland keybindings + touchpad gestures
                             #   (optional include from hyprland.lua)
```

## License

[MIT](LICENSE)