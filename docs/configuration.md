# Configuration

NimLaunch reads its configuration from
`${XDG_CONFIG_HOME:-~/.config}/nimlaunch/nimlaunch.toml`. If the file does not
exist, NimLaunch generates one on the first run from the embedded default
template. If it contains invalid TOML, NimLaunch prints a parse error and uses
built-in defaults for that session.

Application metadata is cached under
`${XDG_CACHE_HOME:-~/.cache}/nimlaunch`. Desktop entries are discovered using
`XDG_DATA_HOME` and `XDG_DATA_DIRS`, with their standard defaults.

## Layout

The generated configuration is split into the following sections:

- `[window]`
- `[font]`
- `[input]`
- `[terminal]`
- `[border]`
- `[icons]`
- `[[groups]]`
- `[[shortcuts]]`
- `[[themes]]`
- `[theme]`

## Window

```toml
[window]
width = 500
opacity = 1.0
max_visible_items = 10
center = true
position_x = 20
position_y = 500
vertical_align = "one-third"
display = 0
pollIntervalMs = 10
```

- **`width`**: Launcher width in pixels, clamped to 200–4000.
- **`opacity`**: Float between `0.1` and `1.0`. Note that some compositors may ignore this setting.
- **`max_visible_items`**: Number of rows before scrolling begins; values below 1 become 1.

The window and row height automatically expand to fit the selected font and icons. On a
small display, NimLaunch reduces the number of visible rows while keeping every row fully
selectable.

- **`center`**: If `true`, NimLaunch ignores `position_x` and centers the window.
- **`position_x`**, **`position_y`**: Used only when `center` is `false`.
- **`vertical_align`**: Used only when centered. Valid values are `top`, `center`, and `one-third`.
- **`display`**: Monitor index used when centered; negative values become 0.
- **`pollIntervalMs`**: Sleep duration in milliseconds per event loop, clamped to 1–1000. A higher value lowers CPU usage but decreases responsiveness (default: 10).

## Font

```toml
[font]
fontname = "Dejavu:size=16"
```

This uses a fontconfig-style string. Use an installed font family and size.

Examples:
- `fontname = "Noto Sans:size=14"`
- `fontname = "JetBrains Mono:size=15"`

## Input

```toml
[input]
prompt = "> "
cursor = "_"
vim_mode = false
```

- **`prompt`**: Prefix shown before the active query.
- **`cursor`**: Cursor glyph shown after the query.
- **`vim_mode`**: Enables Vim-style movement and command handling.

## Terminal

```toml
[terminal]
program = "gnome-terminal"
```

Specifies the terminal emulator used by `:r` and `!` commands. Set this to your preferred terminal (e.g., `kitty`, `foot`, or `gnome-terminal`).

## Border

```toml
[border]
width = 2
```

Specifies the border width in pixels. It is clamped to 0–64 and reduced further
when necessary to fit the window. Set it to `0` to disable the border.

## Icons

```toml
[icons]
enabled = true
```

NimLaunch resolves icons from standard desktop and icon-theme locations, loading PNG and SVG icons through `SDL3_image`.

## Themes

Theme structure, selection, persistence, and custom theme examples are detailed in [Themes](themes.md).

## Generated Defaults

The embedded template used for first-run generation is located in [`src/default_config.nim`](../src/default_config.nim). This template serves as the reference for the generated configuration, default groups, default shortcuts, and bundled themes.

The checked-in [example config](../examples/nimlaunch.toml) provides a richer public sample built from the same format.

## Related Documentation

- [Themes](themes.md)
- [Groups and Shortcuts](groups-and-shortcuts.md)
- [Dmenu Mode](dmenu.md)

## Advanced: Start Menu Mode

NimLaunch can be repurposed as a corner-pinned Start Menu for your panel (e.g., Waybar, Polybar, or KDE Panel).

Create a dedicated configuration file (e.g., `~/.config/nimlaunch/startmenu.toml`) and disable centering:

```toml
[window]
center = false
position_x = 15
position_y = 45  # Adjust based on your panel height and screen resolution
```

**Wayland Users:** By design, Wayland compositors forbid standard applications from dictating their absolute window positions. If your compositor ignores the coordinates and continues to center the window, you can force NimLaunch to run through XWayland (which allows absolute positioning) by prefixing the launch command:

```bash
SDL_VIDEODRIVER=x11 nimlaunch --config ~/.config/nimlaunch/startmenu.toml
```
