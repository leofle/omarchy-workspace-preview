function workspaceLabel(id) {
  return id === 10 ? "0" : String(id)
}

function previewDirectory(home) {
  return String(home || "") + "/.cache/omarchy/workspace-previews"
}

function previewPath(dir, workspaceId) {
  return String(dir || "") + "/ws-" + String(workspaceId) + ".jpg"
}

function previewUrl(dir, workspaceId) {
  return "file://" + previewPath(dir, workspaceId)
}

function wallpaperPath(home) {
  return String(home || "") + "/.local/state/omarchy/current/background"
}

function wallpaperUrl(home) {
  return "file://" + wallpaperPath(home)
}

function sameIdList(left, right) {
  if (!left || !right || left.length !== right.length) return false
  for (var i = 0; i < left.length; i++) {
    if (left[i] !== right[i]) return false
  }
  return true
}

function monitorGeometry(ipc) {
  ipc = ipc || {}
  var scale = Number(ipc.scale) > 0 ? Number(ipc.scale) : 1
  var rotated = Number(ipc.transform || 0) % 2 !== 0
  return {
    x: Number(ipc.x || 0), y: Number(ipc.y || 0),
    width: Math.max(1, Number((rotated ? ipc.height : ipc.width) || 1920) / scale),
    height: Math.max(1, Number((rotated ? ipc.width : ipc.height) || 1080) / scale)
  }
}

function windowPlacement(ipc, monitor, width, height) {
  var at = ipc.at || [monitor.x, monitor.y]
  var size = ipc.size || [monitor.width, monitor.height]
  return {
    x: (at[0] - monitor.x) * width / monitor.width,
    y: (at[1] - monitor.y) * height / monitor.height,
    width: Math.max(1, size[0] * width / monitor.width),
    height: Math.max(1, size[1] * height / monitor.height)
  }
}
