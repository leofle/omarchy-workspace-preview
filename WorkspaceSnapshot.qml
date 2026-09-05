import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import "Model.js" as Model

Item {
  id: root
  required property int workspaceId
  required property int revision
  required property string wallpaper
  clip: true

  readonly property var workspace: {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === root.workspaceId) return values[i]
    return null
  }
  readonly property var monitor: root.workspace ? root.workspace.monitor : null
  readonly property var geometry: Model.monitorGeometry(root.monitor ? root.monitor.lastIpcObject : null)

  Image {
    anchors.fill: parent
    source: root.wallpaper
    fillMode: Image.PreserveAspectCrop
    sourceSize: Qt.size(root.width * 2, root.height * 2)
    asynchronous: true
  }

  Repeater {
    model: root.workspace ? root.workspace.toplevels : null
    delegate: Item {
      id: windowItem
      required property var modelData
      readonly property var ipc: modelData.lastIpcObject || {}
      readonly property var placement: Model.windowPlacement(ipc, root.geometry, root.width, root.height)
      x: placement.x
      y: placement.y
      width: placement.width
      height: placement.height
      z: ipc.fullscreen ? 2 : (ipc.floating ? 1 : 0)
      visible: ipc.mapped !== false && ipc.hidden !== true
      clip: true

      Rectangle { anchors.fill: parent; color: "#202020" }
      ScreencopyView {
        id: capture
        anchors.fill: parent
        captureSource: windowItem.visible ? windowItem.modelData.wayland : null
        live: false
        paintCursor: false
        // Changing the source starts a snapshot; revisiting the same workspace
        // must explicitly request another frame from the compositor.
        Connections {
          target: root
          function onRevisionChanged() {
            if (capture.hasContent) capture.captureFrame()
          }
        }
      }
    }
  }
}
