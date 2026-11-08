-- Workspace Grid: 2D workspace navigation for Hyprland.
-- Loaded from ~/.config/hypr/hyprland.lua (guarded, see loader there).
--
-- Provides:
--   * touchpad gestures (3-finger swipe) for grid navigation
--   * Ctrl+Alt+Arrow to switch workspaces in the grid
--   * Super+Ctrl+Alt+Arrow to move the focused window to a neighboring workspace
--
-- The actual movement is delegated to the plugin-local grid engine so the bar
-- widget, gestures, and keys all share one script. The directional slide
-- animation for every switch comes from hypr/wsanim.lua (loaded early from
-- hyprland.lua).

-- Self-locate the plugin directory: Hyprland loads this file with dofile(),
-- so debug.getinfo is the reliable way to find our own path. The engine lives
-- next door under bin/.
local this_file = debug.getinfo(1, "S").source
local plugin_root = this_file:match("^@?(.-)/hypr/grid%.lua$")
local grid_script = (plugin_root or os.getenv("HOME")) .. "/bin/omarchy-workspace-grid"

local function grid_run(dir)
  return function()
    hl.dispatch(hl.dsp.exec_cmd(grid_script .. " " .. dir))
  end
end

-- Touchpad gestures (inverted: swipe LEFT advances to the next column, etc.).
-- Wrapped in pcall: gesture registration must never abort the keybindings below.
local gestures = {
  { fingers = 3, direction = "left",  action = grid_run("right") },
  { fingers = 3, direction = "right", action = grid_run("left") },
  { fingers = 3, direction = "up",    action = grid_run("down") },
  { fingers = 3, direction = "down",  action = grid_run("up") },
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
