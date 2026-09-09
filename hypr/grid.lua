-- Workspace Grid: 2D workspace navigation for Hyprland.
-- Loaded from ~/.config/hypr/hyprland.lua (guarded, see loader below).
--
-- Provides:
--   * touchpad gestures (3-finger swipe) for grid navigation
--   * Ctrl+Alt+Arrow to switch workspaces in the grid
--   * Super+Ctrl+Alt+Arrow to move the focused window to a neighboring workspace
--
-- The actual movement is delegated to the plugin-local grid engine so the bar
-- widget, gestures, and keys all share one script.

-- Self-locate the plugin directory: Hyprland loads this file with dofile(),
-- so debug.getinfo is the reliable way to find our own path. The engine lives
-- next door under bin/.
local this_file = debug.getinfo(1, "S").source
local plugin_root = this_file:match("^@?(.-)/hypr/grid%.lua$")
local grid_script = (plugin_root or os.getenv("HOME")) .. "/bin/omarchy-workspace-grid"

-- Set the workspace-switch animation the gesture uses (snappy crossfade, no
-- sideways slide). Keep this in sync with ~/.config/hypr/looknfeel.lua.
local function ensure_workspace_animation()
  pcall(function()
    hl.curve("snapOut", { type = "bezier", points = { { 0.05, 0.8 }, { 0.18, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "snapOut", style = "fade" })
  end)
end

local function grid_gesture(dir)
  ensure_workspace_animation()
  hl.dispatch(hl.dsp.exec_cmd(grid_script .. " " .. dir))
end

-- Touchpad gestures (inverted: swipe LEFT advances to the next column, etc.).
-- Wrapped in pcall: gesture registration must never abort the keybindings below.
local gestures = {
  { fingers = 3, direction = "left",  action = function() grid_gesture("right") end },
  { fingers = 3, direction = "right", action = function() grid_gesture("left") end },
  { fingers = 3, direction = "up",    action = function() grid_gesture("down") end },
  { fingers = 3, direction = "down",  action = function() grid_gesture("up") end },
}
for _, g in ipairs(gestures) do
  pcall(function() hl.gesture(g) end)
end

-- Arrow-key workspace switching.
o.bind("CTRL + ALT + LEFT", "Grid: workspace left", grid_script .. " left")
o.bind("CTRL + ALT + RIGHT", "Grid: workspace right", grid_script .. " right")
o.bind("CTRL + ALT + UP", "Grid: workspace above", grid_script .. " up")
o.bind("CTRL + ALT + DOWN", "Grid: workspace below", grid_script .. " down")

-- Arrow-key window moves.
o.bind("SUPER + CTRL + ALT + LEFT", "Grid: move window left", grid_script .. " move left")
o.bind("SUPER + CTRL + ALT + RIGHT", "Grid: move window right", grid_script .. " move right")
o.bind("SUPER + CTRL + ALT + UP", "Grid: move window above", grid_script .. " move up")
o.bind("SUPER + CTRL + ALT + DOWN", "Grid: move window below", grid_script .. " move down")