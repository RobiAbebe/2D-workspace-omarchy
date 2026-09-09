import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "com.robi.workspace-grid"

  readonly property int columns: Math.max(1, root.setting("columns", 3) || 3)
  readonly property int rows: Math.max(1, root.setting("rows", 2) || 2)
  readonly property int gridSize: Math.max(6, root.setting("gridSize", 20) || 20)
  readonly property bool clampEdges: root.setting("clampEdges", true) !== false
  readonly property bool showIcons: root.setting("showIcons", true) !== false
  readonly property bool alwaysShowNumbers: root.setting("alwaysShowNumbers", false) === true

  readonly property int slotCount: root.vertical ? root.rows : root.columns * root.rows

  // Cell size capped so the whole grid fits the bar height.
  readonly property real cellSize: root.vertical ? root.gridSize : Math.max(
    6, Math.min(root.gridSize, Math.floor((root.barSize - Style.spaceReal(1) * (root.rows - 1)) / root.rows)))

  // Window class -> "file://" icon path, refreshed by bin/omarchy-icon-index.
  property var iconCache: ({})
  // Live window map [{w:workspace, c:class, f:focusHistoryID}] from the same
  // script. Quickshell's Toplevel.lastIpcObject stays empty for windows that
  // open after the shell started, so hyprctl is the reliable class source.
  property var winCache: []
  property string indexRaw: ""
  property int iconRevision: 0
  property bool iconDirty: false

  function workspaceById(id) {
    var values = Hyprland.workspaces ? (Hyprland.workspaces.values || []) : []
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // Most recently focused classes on a workspace, from the live hyprctl window
  // map (lowest focusHistoryID first, capped at 2, deduplicated by class).
  function winClassesFor(workspaceId) {
    var wins = root.winCache || []
    var pick = []
    for (var i = 0; i < wins.length; i++) {
      if (wins[i].w === workspaceId) pick.push(wins[i])
    }
    pick.sort(function(a, b) { return a.f - b.f })
    var out = []
    var seen = {}
    for (var j = 0; j < pick.length && out.length < 2; j++) {
      var c = String(pick[j].c || "").trim()
      if (c.length > 0 && !seen[c]) { seen[c] = true; out.push(c) }
    }
    return out
  }

  // Quickshell-based fallback: resolves classes from the Toplevel payloads,
  // which are populated for windows that were open when the shell started.
  function workspaceFocusedWindows(workspace) {
    if (workspace === null || workspace === undefined) return []
    if (workspace.toplevels === null || workspace.toplevels === undefined) return []
    var values = workspace.toplevels.values || []
    var metas = []
    for (var i = 0; i < values.length; i++) {
      var meta = values[i].lastIpcObject || {}
      metas.push({ focus: Number(meta.focusHistoryID), meta: meta })
    }
    metas.sort(function(a, b) { return a.focus - b.focus })
    var out = []
    for (var j = 0; j < Math.min(2, metas.length); j++) out.push(metas[j].meta)
    return out
  }

  // Class of a window (last IPC payload preferred over convenience props,
  // mirroring the classic widget).
  function classFor(meta) {
    return String(meta.class || meta.initialClass || "").trim()
  }

  function iconFor(kind) {
    return String(root.iconCache[kind] || "")
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function moveWindowTo(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.window.move({ workspace = \"" + id + "\" })"))
  }

  property bool pendingRefresh: false
  property int refreshDelay: 200

  // Request a refresh; if one is already in flight the next run picks this up
  // (iconDirty) so no window-open event is dropped.
  function requestIconRefresh(delay) {
    if (delay >= 0) {
      root.refreshDelay = delay
      root.pendingRefresh = true
      return
    }
    if (iconIndexProc && iconIndexProc.running) {
      root.iconDirty = true
      return
    }
    iconIndexProc.running = true
  }

  // Refresh the icon index on window events (near-instant) and on a slow timer
  // as a safety net so newly opened apps pick up an icon shortly after launch.
  Process {
    id: iconIndexProc
    command: ["bash", "-c", Qt.resolvedUrl("bin/omarchy-icon-index").toString().replace("file://", "")]
    stdout: SplitParser {
      onRead: function(line) { root.indexRaw += line }
    }
    onStarted: root.indexRaw = ""
    onExited: {
      try {
        var parsed = JSON.parse(root.indexRaw)
        root.iconCache = parsed.icons || {}
        root.winCache = parsed.windows || []
      } catch (e) { /* keep previous */ }
      root.indexRaw = ""
      root.iconRevision++ // re-evaluate cells so newly opened apps appear
      if (root.iconDirty) {
        root.iconDirty = false
        if (iconIndexProc && !iconIndexProc.running) iconIndexProc.running = true
      }
    }
  }

  // Debounced trigger for window open/close events: waits a beat so Quickshell
  // has identified the toplevel before the cells re-read its lastIpcObject on
  // the iconRevision bump. Driven by pendingRefresh (no id references inside
  // functions, which could be undefined while the widget tree is still being
  // built on startup).
  Timer {
    id: instantRefresh
    interval: root.refreshDelay
    repeat: false
    running: root.pendingRefresh
    onTriggered: {
      root.pendingRefresh = false
      root.requestIconRefresh(-1)
      // A brand-new toplevel can take a few hundred ms to be fully identified
      // (class, lastIpcObject) after its openwindow event, so keep re-picking
      // for a moment instead of waiting for the slow safety net.
      root.staggerLeft = 4
    }
  }

  // Staggered iconRevision bumps shortly after a window opens/departs, so a
  // late-identifying workspace/toplevel still pops its icon in ~1s instead of
  // at the next 3s timer tick.
  property int staggerLeft: 0
  Timer {
    id: stagger
    interval: 400
    repeat: true
    running: root.staggerLeft > 0
    onTriggered: {
      root.iconRevision++
      root.staggerLeft--
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
        case "openwindow":
        case "closewindow":
        case "movewindow":
          // New/removed windows may add a new icon to the cache.
          root.requestIconRefresh(200)
          break
        case "workspace":
        case "activewindow":
        case "fullscreen":
          // The class->icon mapping is unchanged; just nudge the cells to
          // re-pick the most-recently-focused window.
          root.iconRevision++
          break
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.requestIconRefresh(-1)
  }

  // Populate the icon cache immediately at startup (not on the first 3s tick)
  // so every occupied cell shows its icon from the moment the shell appears.
  Component.onCompleted: root.requestIconRefresh(-1)

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.columns
    rows: root.rows
    columnSpacing: root.vertical ? 0 : Style.space(0.25)
    rowSpacing: root.vertical ? Style.space(0.5) : Style.space(0.15)

    Repeater {
      model: root.slotCount

      Item {
        id: cell
        required property int index

        readonly property int workspaceId: index + 1
        // Quickshell's Hyprland.workspaces model has no change notification, so
        // re-resolve the workspace object on every iconRevision bump (catches
        // workspaces created after the shell started).
        readonly property var workspace: (function() {
          var rev = root.iconRevision
          return root.workspaceById(workspaceId) || null
        })()
        // Depends on iconRevision so cells re-evaluate on every icon-index
        // refresh: a window that was just opened may not have its IPC payload
        // ready in time for the workspace-toplevels notification, so re-dig
        // on a slow tick to pick it up.
        readonly property var focusedWindows: (function() {
          var rev = root.iconRevision
          if (!workspace) return []
          try { return root.workspaceFocusedWindows(workspace) } catch (e) { return [] }
        })()
        readonly property var windowClasses: (function() {
          var rev = root.iconRevision
          if (!root.showIcons) return []
          // Primary source: live hyprctl window map (catches every window,
          // including ones that open after the shell started).
          var live = []
          try { live = root.winClassesFor(workspaceId) } catch (e) {}
          if (live && live.length > 0) return live
          // Fallback: Quickshell Toplevel payloads (populated at startup).
          if (!workspace) return []
          var classes = focusedWindows
          if (!classes || classes.length === 0) return []
          var out = []
          for (var i = 0; i < classes.length; i++) {
            var c = root.classFor(classes[i] || {})
            if (c && c.length > 0) out.push(c)
          }
          return out
        })()
        readonly property bool occupied: windowClasses.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === workspaceId

        Layout.row: root.vertical ? index : Math.floor(index / root.columns)
        Layout.column: root.vertical ? 0 : index % root.columns
        Layout.preferredWidth: root.vertical ? root.barSize : root.cellSize
        Layout.preferredHeight: root.vertical ? root.barSize : root.cellSize

        // Active-workspace indicator: a soft accent pill behind the cell,
        // mirroring the classic omarchy.workspaces widget.
        Rectangle {
          anchors.fill: parent
          visible: cell.focused
          radius: Math.min(4, parent.height / 2)
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.32)
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
          border.width: 1
        }

        // KDE-style app-icon indicator for the windows on this workspace.
        Row {
          anchors.centerIn: parent
          spacing: Style.spaceReal(1)
          visible: cell.windowClasses.length > 0

          Repeater {
            model: cell.windowClasses

            Rectangle {
                required property string modelData
                readonly property int tile: Math.max(7, Math.floor(root.cellSize / 3))

              width: tile
              height: tile
              radius: 2
              color: cell.focused ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.12)

              Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: root.iconFor(modelData)
                sourceSize.width: 16
                sourceSize.height: 16
              }
            }
          }
        }

        WidgetButton {
          anchors.fill: parent

          text: cell.occupied && !root.alwaysShowNumbers ? "" : (workspaceId === 10 ? "0" : String(workspaceId))
          active: cell.focused
          useActiveColor: false
          opacity: cell.occupied || cell.focused ? 1 : 0.4
          horizontalMargin: 3
          verticalPadding: 2
          fontSize: Math.min(Style.font.body, root.cellSize - 2)
          tooltipText: "Workspace " + workspaceId
          onPressed: function(buttonState) {
            if (buttonState === Qt.RightButton) root.moveWindowTo(cell.workspaceId)
            else root.focusWorkspace(cell.workspaceId)
          }
        }
      }
    }
  }
}