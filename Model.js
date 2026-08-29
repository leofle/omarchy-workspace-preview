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
