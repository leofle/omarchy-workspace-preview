import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.bubblepaxi.workspace-preview"
  ipcTarget: "io.github.bubblepaxi.workspace-preview"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int selectedWorkspaceId: 1
  property bool captureQueued: false
  property int lastFocusId: -1
  property int capturingId: -1
  property string shotSource: ""
  property bool pendingRefresh: false
  property string lastLayoutFingerprint: ""
  property int jpegReadId: -1
  property int windowBorderSize: 2
  property color windowBorderColor: Color.accent
  readonly property int frameWidth: Math.max(1, root.windowBorderSize)

  readonly property string home: Quickshell.env("HOME")
  readonly property string previewDir: Model.previewDirectory(root.home)
  readonly property string wallpaperUrl: Model.wallpaperUrl(root.home)
  readonly property string helperScript: String(Qt.resolvedUrl("preview-helper.py")).replace(/^file:\/\//, "")
  readonly property string captureScript: String(Qt.resolvedUrl("capture-workspace-preview.sh")).replace(/^file:\/\//, "")
  readonly property int focusId: Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
  readonly property var barWindow: root.hostWidget && root.hostWidget.QsWindow ? root.hostWidget.QsWindow.window : null
  readonly property var previewScreen: root.barWindow ? root.barWindow.screen : null
  readonly property real monitorWidth: root.previewScreen && root.previewScreen.width > 0
    ? root.previewScreen.width
    : (Hyprland.focusedMonitor && Hyprland.focusedMonitor.width > 0 ? Hyprland.focusedMonitor.width : 1920)
  readonly property real monitorHeight: root.previewScreen && root.previewScreen.height > 0
    ? root.previewScreen.height
    : (Hyprland.focusedMonitor && Hyprland.focusedMonitor.height > 0 ? Hyprland.focusedMonitor.height : 1080)
  readonly property int previewWidth: {
    var maxW = 320
    var scale = Math.min(0.14, maxW / Math.max(1, root.monitorWidth))
    return Math.max(200, Math.round(root.monitorWidth * scale))
  }
  readonly property int previewHeight: Math.max(112, Math.round(root.previewWidth * root.monitorHeight / Math.max(1, root.monitorWidth)))

  function currentWorkspaceId() {
    if (root.focusId > 0) return root.focusId
    return 1
  }

  function onFocusedOutput() {
    if (!root.previewScreen) return true
    var mapped = Hyprland.monitorFor(root.previewScreen)
    if (!mapped || !Hyprland.focusedMonitor) return true
    return mapped.name === Hyprland.focusedMonitor.name
  }

  function isLayoutEvent(name) {
    name = String(name || "")
    if (!name) return false
    if (name === "windowtitle" || name === "windowtitlev2") return false
    if (name === "activewindow" || name === "activewindowv2") return false
    if (name === "urgent" || name === "screencast" || name === "screencastv2") return false
    if (name === "activelayout") return false
    return name === "openwindow"
      || name === "closewindow"
      || name.indexOf("movewindow") === 0
      || name.indexOf("swapwindow") === 0
      || name.indexOf("fullscreen") === 0
      || name === "changefloatingmode"
      || name.indexOf("workspace") === 0
      || name.indexOf("focusedmon") === 0
      || name.indexOf("group") !== -1
      || name === "pin"
      || name.indexOf("minimize") !== -1
      || name === "configreloaded"
  }

  function layoutFingerprint() {
    var toplevels
    try { toplevels = Hyprland.toplevels.values } catch (e) { return "" }
    if (!toplevels || !toplevels.length) return "empty"
    var parts = []
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      if (!t) continue
      var ipc = t.lastIpcObject || {}
      if (ipc.mapped === false || ipc.hidden === true) continue
      var ws = t.workspace && t.workspace.id !== undefined ? t.workspace.id : "?"
      var at = ipc.at || [0, 0]
      var size = ipc.size || [0, 0]
      parts.push([t.address || "", ws, at[0], at[1], size[0], size[1], ipc["class"] || "", ipc.floating ? 1 : 0, ipc.fullscreen || 0].join(","))
    }
    parts.sort()
    return parts.join("|")
  }

  function pollGeometry() {
    if (root.opened || root.overlayOnScreen()) return
    var next = root.layoutFingerprint()
    if (next && next !== root.lastLayoutFingerprint) {
      root.lastLayoutFingerprint = next
      root.scheduleRefresh()
    }
    Hyprland.refreshToplevels()
  }

  function scheduleRefresh() {
    windowCaptureTimer.restart()
  }

  function parseHyprlandColor(raw) {
    var s = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (!s) return ""
    var parts = s.split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (part.match(/deg$/)) continue
      if (part.match(/^[0-9A-Fa-f]{8}$/)) return "#" + part.substring(2)
      if (part.charAt(0) === "#" && part.length >= 7) return part.substring(0, 7)
      var rgba = part.match(/^rgba\(([0-9A-Fa-f]{6})/i)
      if (rgba) return "#" + rgba[1]
      var rgb = part.match(/^rgb\(([0-9A-Fa-f]{6})\)/i)
      if (rgb) return "#" + rgb[1]
    }
    return ""
  }

  function refreshWindowBorder() {
    if (borderOptProc.running) return
    borderOptProc.running = false
    borderOptProc.command = ["python3", root.helperScript, "run", "1000", "16384", "--", "sh", "-c", "hyprctl -j getoption general:border_size; printf '\\n'; hyprctl -j getoption general:col.active_border"]
    borderOptProc.running = true
  }

  function workspaceOccupied(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws && ws.id === id) return ws.toplevels.values.length > 0
    }
    return false
  }

  function showWorkspace(workspaceId, anchor) {
    if (workspaceId <= 0) return
    if (anchor) root.anchorItem = anchor
    root.selectedWorkspaceId = workspaceId
    root.setShot(workspaceId)
  }

  function setShot(workspaceId) {
    if (!(workspaceId > 0 && root.workspaceOccupied(workspaceId))) {
      root.shotSource = root.wallpaperUrl
      return
    }
    root.loadValidatedShot(workspaceId)
  }

  function loadValidatedShot(workspaceId) {
    root.jpegReadId = workspaceId
    jpegReadProc.running = false
    jpegReadProc.command = ["python3", root.helperScript, "read", Model.previewPath(root.previewDir, workspaceId)]
    jpegReadProc.running = true
  }

  function openForWorkspace(workspaceId, anchor) {
    closeTimer.stop()
    root.showWorkspace(workspaceId, anchor)
    root.controller.show()
  }

  function openFromHotkey() {
    openForWorkspace(root.selectedWorkspaceId > 0 ? root.selectedWorkspaceId : root.currentWorkspaceId(), root.anchorItem)
  }

  function close() {
    closeTimer.stop()
    root.controller.hide()
  }

  function scheduleClose() {
    if (panel.containsMouse) return
    closeTimer.restart()
  }

  function cancelClose() {
    closeTimer.stop()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function overlayOnScreen() {
    return panel.visible
  }

  function abortCapture() {
    stallTimer.stop()
    if (captureProc.running) captureProc.running = false
    root.captureQueued = false
    root.capturingId = -1
  }

  function captureWorkspace(id, force) {
    if (id <= 0) return
    if (!force && !root.onFocusedOutput()) return
    if (root.overlayOnScreen()) return
    if (root.captureQueued || captureProc.running) {
      root.pendingRefresh = true
      return
    }
    root.pendingRefresh = false
    root.captureQueued = true
    root.capturingId = id
    stallTimer.restart()
    captureProc.running = false
    captureProc.command = [root.captureScript, String(id), Model.previewPath(root.previewDir, id)]
    captureProc.running = true
  }

  function captureCurrentWorkspace() {
    root.captureWorkspace(root.currentWorkspaceId(), true)
  }

  onFocusIdChanged: {
    if (root.focusId <= 0) return
    if (root.focusId === root.lastFocusId) return
    root.lastFocusId = root.focusId
    root.scheduleRefresh()
  }

  onOpenedChanged: {
    if (root.opened) {
      root.refreshWindowBorder()
      root.abortCapture()
      return
    }
    root.scheduleRefresh()
  }

  Component.onCompleted: {
    root.lastFocusId = root.currentWorkspaceId()
    root.setShot(root.selectedWorkspaceId)
    root.scheduleRefresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "configreloaded") root.refreshWindowBorder()
      if (!root.isLayoutEvent(event.name)) return
      root.scheduleRefresh()
    }
  }

  Timer {
    id: geometryPollTimer
    interval: 400
    running: !root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollGeometry()
  }

  Timer {
    id: closeTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (panel.containsMouse) return
      root.close()
    }
  }

  Timer {
    id: windowCaptureTimer
    interval: 420
    repeat: false
    onTriggered: {
      if (root.overlayOnScreen()) return
      root.captureWorkspace(root.currentWorkspaceId())
    }
  }

  Timer {
    id: stallTimer
    interval: 2000
    repeat: false
    onTriggered: {
      captureProc.running = false
      root.captureQueued = false
      root.capturingId = -1
      root.scheduleRefresh()
    }
  }

  Process {
    id: jpegReadProc
    command: ["python3", "-c", "raise SystemExit(1)"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var requestedId = root.jpegReadId
        var b64 = String(text || "").replace(/\s+/g, "")
        if (requestedId !== root.selectedWorkspaceId) return
        if (!b64) {
          root.shotSource = root.wallpaperUrl
          return
        }
        root.shotSource = "data:image/jpeg;base64," + b64
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      if (root.jpegReadId !== root.selectedWorkspaceId) return
      root.shotSource = root.wallpaperUrl
    }
  }

  Process {
    id: borderOptProc
    command: ["python3", "-c", "raise SystemExit(1)"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var blobs = String(text || "").match(/\{[\s\S]*?\}/g) || []
        for (var i = 0; i < blobs.length; i++) {
          var data
          try { data = JSON.parse(blobs[i]) } catch (e) { continue }
          if (!data) continue
          if (data.int !== undefined && String(data.option || "").indexOf("border_size") !== -1) {
            var size = Number(data.int)
            if (isFinite(size) && size >= 0) root.windowBorderSize = Math.round(size)
          }
          var raw = data.gradient || data.custom || data.str || ""
          var parsed = root.parseHyprlandColor(raw)
          if (parsed) root.windowBorderColor = parsed
        }
      }
    }
    onExited: borderOptProc.running = false
  }

  Process {
    id: captureProc
    command: ["/bin/sh", "-c", "true"]
    running: false
    onExited: function(exitCode) {
      var capturedId = root.capturingId
      stallTimer.stop()
      root.captureQueued = false
      root.capturingId = -1
      if (exitCode !== 0 || capturedId <= 0) {
        if (root.pendingRefresh) Qt.callLater(function() { root.captureWorkspace(root.currentWorkspaceId()) })
        return
      }
      if (root.selectedWorkspaceId === capturedId && !root.overlayOnScreen())
        root.loadValidatedShot(capturedId)
      if (root.pendingRefresh) Qt.callLater(function() { root.captureWorkspace(root.currentWorkspaceId()) })
    }
  }

  PopupCard {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    triggerMode: "hover"
    centerOnBar: false
    padding: 0
    margin: 6
    borderSpec: Border.none()
    contentWidth: root.previewWidth
    contentHeight: root.previewHeight

    Rectangle {
      anchors.fill: parent
      color: root.windowBorderColor

      Rectangle {
        anchors.fill: parent
        anchors.margins: root.frameWidth
        color: Color.background

        Image {
          id: shot
          anchors.fill: parent
          source: root.shotSource
          sourceSize.width: Math.max(1, root.previewWidth * 2)
          sourceSize.height: Math.max(1, root.previewHeight * 2)
          fillMode: Image.PreserveAspectFit
          smooth: true
          asynchronous: false
          cache: false
          onStatusChanged: {
            if (status !== Image.Error) return
            if (root.shotSource === root.wallpaperUrl) return
            Qt.callLater(function() {
              if (shot.status === Image.Error) root.shotSource = root.wallpaperUrl
            })
          }
        }
      }
    }
  }
}
