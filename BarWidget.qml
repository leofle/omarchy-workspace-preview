import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.bubblepaxi.workspace-preview"

  property int hoveredWorkspaceId: -1
  property var displayedIds: [1, 2, 3, 4, 5]

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function syncDisplayedIds() {
    var ids = root.workspaceIds()
    if (!Model.sameIdList(ids, root.displayedIds)) root.displayedIds = ids
  }

  function workspaceLabel(id) {
    return Model.workspaceLabel(id)
  }

  function currentWorkspaceId() {
    if (Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id > 0)
      return Hyprland.focusedWorkspace.id
    return 1
  }

  function focusWorkspace(id) {
    if (panelLoader.item) panelLoader.item.close()
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function open() {
    ensurePanel()
    var id = root.hoveredWorkspaceId > 0 ? root.hoveredWorkspaceId : root.currentWorkspaceId()
    if (panelLoader.item) panelLoader.item.openForWorkspace(id, root)
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.opened) close()
    else open()
  }

  function setPreviewWorkspace(id) {
    if (id <= 0) return
    hoveredWorkspaceId = id
    ensurePanel()
    previewCloseTimer.stop()
    if (panelLoader.item) panelLoader.item.cancelClose()
    if (panelLoader.item && panelLoader.item.opened) {
      panelLoader.item.showWorkspace(id, root)
      return
    }
    if (!previewOpenTimer.running) previewOpenTimer.start()
  }

  function stripLeft() {
    hoveredWorkspaceId = -1
    previewOpenTimer.stop()
    previewCloseTimer.restart()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  function ensurePanel() {
    if (!panelLoader.active) panelLoader.active = true
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  implicitWidth: root.vertical ? root.barSize : grid.implicitWidth + trailingGap
  implicitHeight: root.vertical ? grid.implicitHeight : root.barSize

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  onBarChanged: injectPanel()
  Component.onCompleted: root.syncDisplayedIds()

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.syncDisplayedIds() }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Timer {
    id: previewOpenTimer
    interval: 20
    repeat: false
    onTriggered: {
      if (root.hoveredWorkspaceId <= 0) return
      if (panelLoader.item) panelLoader.item.openForWorkspace(root.hoveredWorkspaceId, root)
    }
  }

  Timer {
    id: previewCloseTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (root.hoveredWorkspaceId > 0) return
      if (panelLoader.item) panelLoader.item.scheduleClose()
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { if (panelLoader.item && panelLoader.item.captureCurrentWorkspace) panelLoader.item.captureCurrentWorkspace() }
  }

  HoverHandler {
    onHoveredChanged: {
      if (hovered) previewCloseTimer.stop()
      else root.stripLeft()
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.displayedIds.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.displayedIds

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : root.workspaceLabel(modelData)
        opacity: occupied || focused ? 1 : 0.55
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        tooltipText: ""
        onPressed: function(buttonCode) {
          if (buttonCode === Qt.LeftButton) root.focusWorkspace(modelData)
        }

        HoverHandler {
          onHoveredChanged: {
            if (hovered) root.setPreviewWorkspace(modelData)
          }
        }
      }
    }
  }
}
