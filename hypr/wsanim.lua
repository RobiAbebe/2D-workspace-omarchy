-- Workspace Grid: direction-aware slide animation for every workspace switch.
-- Loaded from ~/.config/hypr/hyprland.lua (guarded) BEFORE Omarchy's default
-- keybindings, because binds capture hl.dsp.focus/hl.dsp.window.move when they
-- are created.
--
-- Any switch (gestures, Ctrl+Alt+Arrows, Super+N, Super+Tab, bar clicks,
-- hyprctl) slides the new workspace in from the edge of the grid it comes
-- from: right/left horizontally, up/down vertically (e.g. Super+4 from
-- workspace 1 is 1 -> 4, a vertical move, so it slides in from the bottom).
--
-- Hyprland reads the animation style when it starts a transition, so it is
-- enough to set the style in the moment a switch is dispatched. We wrap the
-- workspace dispatchers to compute the direction from the active workspace to
-- the target workspace right before dispatching.
--
-- Keep speed/curve in sync with ~/.config/hypr/looknfeel.lua.
-- Supports Omarchy 4.5+ per-monitor workspace blocks (10 slots per monitor).

-- Grid geometry, mirrored from bin/omarchy-workspace-grid (same env var).
local COLS = tonumber(os.getenv("OMARCHY_WS_COLS") or "") or 3
if COLS < 1 then COLS = 3 end
local SLOTS = 10

-- Slide style for a move from one workspace to another, based on the grid.
-- Returns nil when no direction can be determined (same workspace, selector
-- like "e+1"/"previous", special/named workspace) so callers fall back to the
-- neutral "slide", whose built-in direction already matches id-increasing
-- switches.
local function direction_for(from_id, to_id)
  if type(from_id) ~= "number" or type(to_id) ~= "number" then return nil end
  if from_id < 1 or to_id < 1 or from_id == to_id then return nil end

  local from_block = math.floor((from_id - 1) / SLOTS)
  local to_block = math.floor((to_id - 1) / SLOTS)
  if from_block ~= to_block then return nil end

  local from_slot = (from_id - 1) % SLOTS + 1
  local to_slot = (to_id - 1) % SLOTS + 1

  local dcol = ((to_slot - 1) % COLS) - ((from_slot - 1) % COLS)
  local drow = math.floor((to_slot - 1) / COLS) - math.floor((from_slot - 1) / COLS)

  if dcol == 0 then
    if drow == 0 then return nil end
    return drow > 0 and "slidevert bottom" or "slidevert top"
  end
  if drow == 0 then
    return dcol > 0 and "slide right" or "slide left"
  end
  -- Diagonal jump (e.g. 1 -> 6): follow the larger step, ties go horizontal.
  if math.abs(drow) > math.abs(dcol) then
    return drow > 0 and "slidevert bottom" or "slidevert top"
  end
  return dcol > 0 and "slide right" or "slide left"
end

local function apply_style(style)
  pcall(function()
    hl.curve("snapOut", { type = "bezier", points = { { 0.05, 0.8 }, { 0.18, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "snapOut", style = style })
  end)
end

local function target_id(workspace)
  if type(workspace) == "table" then workspace = workspace.id end
  return tonumber(workspace)
end

local function apply_direction(workspace)
  local ok, ws = pcall(hl.get_active_workspace)
  local from = ok and ws and tonumber(ws.id) or nil
  apply_style(direction_for(from, target_id(workspace)) or "slide")
end

-- Wrap a dispatcher builder so the direction is computed when the dispatcher
-- runs, not when it is built (config-load time for keybindings).
local function wrap(dispatcher_builder, workspace_key)
  return function(args)
    local workspace = type(args) == "table" and args[workspace_key] or nil
    if workspace == nil then return dispatcher_builder(args) end
    local dispatcher = dispatcher_builder(args)
    return function()
      apply_direction(workspace)
      hl.dispatch(dispatcher)
    end
  end
end

hl.dsp.focus = wrap(hl.dsp.focus, "workspace")

-- Moving a window switches to the target workspace too, unless follow=false
-- (then no switch happens and no direction must be set).
local original_move = hl.dsp.window.move
hl.dsp.window.move = function(args)
  if type(args) == "table" and args.workspace ~= nil and args.follow == false then
    return original_move(args)
  end
  return wrap(original_move, "workspace")(args)
end

-- Neutral slide after every switch: Hyprland has already read the direction
-- when it starts the animations (startAnimation runs before workspace.active
-- is emitted), so this never affects a running transition, but stale
-- directions cannot leak into switches we do not wrap (e.g. window rules).
hl.on("workspace.active", function()
  apply_style("slide")
end)
