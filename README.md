# Workspace Preview

Hover a workspace number in the Omarchy bar to preview that desktop as a thumbnail. The same panel can be summoned from a shortcut.

## Install

```sh
omarchy plugin add https://github.com/leofle/omarchy-workspace-preview.git --enable
```

This plugin is a drop-in replacement for the built-in workspace numbers. After install, move it onto the bar and disable `omarchy.workspaces` if both appear:

```sh
omarchy bar move io.github.bubblepaxi.workspace-preview --section left
omarchy plugin disable omarchy.workspaces
```

## Usage

- Hover a workspace number to open its thumbnail.
- Click a number or a preview card to focus that workspace.
- Previews refresh when you leave a workspace or when windows move.

Summon or hide the panel from a keybinding:

```sh
omarchy-shell shell summon io.github.bubblepaxi.workspace-preview '{}'
omarchy-shell shell hide io.github.bubblepaxi.workspace-preview
```

Example Hyprland binding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + TAB", "Workspace Preview", "omarchy-shell shell summon io.github.bubblepaxi.workspace-preview '{}'")
```

## Dependencies

These are already present on a normal Omarchy install:

- Hyprland (`hyprctl`)
- `grim` to capture the focused monitor
- `jq` to choose that monitor

Thumbnails are written to `~/.cache/omarchy/workspace-previews/`. The plugin does not use `sudo` or `pkexec`, does not install packages, and does not change files outside its cache directory.

## Remove

```sh
omarchy plugin remove io.github.bubblepaxi.workspace-preview
```

If you disabled the built-in workspace widget, turn it back on:

```sh
omarchy plugin enable omarchy.workspaces
```

Cached thumbnails are left in `~/.cache/omarchy/workspace-previews/` and can be deleted by hand.

## License

[MIT](LICENSE)
