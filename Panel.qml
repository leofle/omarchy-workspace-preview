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
  property var captureStamps: ({})
  property string shotSource: ""
  property bool pendingRefresh: false
  property bool layoutPollPending: false
  property string lastLayoutFingerprint: ""
  property int windowBorderSize: 2
  property color windowBorderColor: Color.accent
  readonly property int frameWidth: Math.max(1, root.windowBorderSize)

  readonly property string home: Quickshell.env("HOME")
  readonly property string previewDir: Model.previewDirectory(root.home)
  readonly property string wallpaperUrl: Model.wallpaperUrl(root.home)
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

  function layoutFingerprint(clientsText) {
    var clients
    try { clients = JSON.parse(clientsText || "[]") } catch (e) { return "" }
    if (!clients || !clients.length) return "empty"
    var parts = []
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (!c || c.mapped === false || c.hidden === true) continue
      var ws = c.workspace && c.workspace.id !== undefined ? c.workspace.id : "?"
      var at = c.at || [0, 0]
      var size = c.size || [0, 0]
      parts.push([c.address || "", ws, at[0], at[1], size[0], size[1], c.class || "", c.floating ? 1 : 0, c.fullscreen || 0].join(","))
    }
    parts.sort()
    return parts.join("|")
  }

  function pollLayout() {
    if (layoutProc.running) {
      root.layoutPollPending = true
      return
    }
    layoutProc.running = false
    layoutProc.running = true
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
    root.captureWorkspace(root.currentWorkspaceId())
  }

  function shotUrl(workspaceId) {
    var url = Model.previewUrl(root.previewDir, workspaceId)
    var stamp = root.captureStamps[workspaceId] || 0
    url += "?t=" + stamp + "-" + Date.now()
    return url
  }

  function setShot(workspaceId) {
    var next = (workspaceId > 0 && root.workspaceOccupied(workspaceId))
      ? root.shotUrl(workspaceId)
      : root.wallpaperUrl
    if (root.shotSource === next) {
      root.shotSource = ""
      Qt.callLater(function() { if (!root.shotSource) root.shotSource = next })
      return
    }
    root.shotSource = next
  }

  function markCaptured(id) {
    var next = {}
    for (var key in root.captureStamps) next[key] = root.captureStamps[key]
    next[id] = Date.now()
    root.captureStamps = next
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

  function captureWorkspace(id, force) {
    if (id <= 0) return
    if (!force && !root.onFocusedOutput()) return
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
    if (root.opened) root.refreshWindowBorder()
    else root.scheduleRefresh()
  }

  Component.onCompleted: {
    root.lastFocusId = root.currentWorkspaceId()
    root.setShot(root.selectedWorkspaceId)
    root.pollLayout()
    root.refreshWindowBorder()
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
    onTriggered: root.captureWorkspace(root.currentWorkspaceId())
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

  Timer {
    interval: 120
    running: true
    repeat: true
    onTriggered: root.pollLayout()
  }

  Process {
    id: borderOptProc
    command: ["sh", "-c", "hyprctl -j getoption general:border_size; printf '\\n'; hyprctl -j getoption general:col.active_border"]
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
    id: layoutProc
    command: ["hyprctl", "-j", "clients"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = root.layoutFingerprint(text)
        if (!next || next === root.lastLayoutFingerprint) return
        root.lastLayoutFingerprint = next
        root.scheduleRefresh()
      }
    }
    onExited: {
      layoutProc.running = false
      if (!root.layoutPollPending) return
      root.layoutPollPending = false
      Qt.callLater(root.pollLayout)
    }
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
      root.markCaptured(capturedId)
      if (root.selectedWorkspaceId === capturedId) root.setShot(capturedId)
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
