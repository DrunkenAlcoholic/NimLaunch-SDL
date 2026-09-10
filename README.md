# NimLaunch (SDL3)

The lightning fast original X11 only version is available here:

https://github.com/Vyrnexis/NimLaunch-X11

NimLaunch is a keyboard-first launcher for Wayland and X11 built on SDL3. It
covers three main workflows:

- application launching from `.desktop` entries
- configurable command/url/file shortcuts
- generic stdin-driven selection through `--dmenu`

It uses SDL3 for native Wayland/X11 support with GPU-backed compositing and
loads PNG/SVG icons through the SDL3 stack.

![NimLaunch screenshot](screenshots/NimLaunch-SDL2.gif)

## Features
- **Typo-tolerant fuzzy matching:** Allocation-conscious application search with substring and transposition matching.
- **Asynchronous Icon Engine:** A background worker decodes PNG/SVG desktop icons without disk I/O on the main UI thread.
- **Application State Caching:** Parsed `.desktop` entries are cached as JSON to avoid unnecessary rescans at startup.
- Prefix commands: `:t`, `:c`, `:s`, `:r`, `!`, and custom groups.
- Desktop entry actions for apps that expose secondary launch actions.
- Vim mode (optional): `j/k` navigation, `/ : !` command bar, `gg/G`, `:q`, etc.
- Themes with live preview, status/toast messages, and clock overlay.
- `--dmenu` mode for scripts, and other stdin-driven workflows (with native `rofi`-style `\0icon\x1f` support).
- Window opacity setting (0.1–1.0)

## Documentation
- [Configuration Guide](docs/configuration.md)
- [Themes](docs/themes.md)
- [Groups and Shortcuts](docs/groups-and-shortcuts.md)
- [Dmenu Mode](docs/dmenu.md)

## Install
Grab a compiled binary from the [releases page](https://github.com/Vyrnexis/NimLaunch/releases).

**Arch Linux (AUR)**
You can install NimLaunch from the Arch User Repository using `yay` or `paru`:
```bash
# For the pre-built binary
yay -S nimlaunch-bin
# OR
paru -S nimlaunch-bin
```

## Build
> [!NOTE]
> Runtime/build deps: `nim >= 2.0`, `sdl3`, `sdl3_ttf`, `sdl3_image`, plus a font
> (default `ttf-dejavu`).
>
> Nim package note: the Nim SDL3 and `parsetoml` sources are vendored in
> `packages/`, so Nimble does not need to download those wrappers separately.
>
> Optional helpers:
> - `fd` and/or `locate` for faster `:s` file search

### Arch Linux
```bash
sudo pacman -S sdl3 sdl3_ttf sdl3_image ttf-dejavu --needed
```

### Ubuntu releases with SDL3 development packages (including 25.10)
```bash
sudo apt install libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev fonts-dejavu-core
```

### OpenSUSE
```bash
# Tumbleweed / Slowroll package names:
sudo zypper install SDL3-devel SDL3_ttf-devel SDL3_image-devel dejavu-fonts
```
If you are on Leap and a name differs, run `zypper search sdl3`
to find the matching package variant.

### Solus
```bash
sudo eopkg it sdl3-devel sdl3-ttf-devel sdl3-image-devel
```

### Build from source
```bash
git clone https://github.com/Vyrnexis/NimLaunch.git
cd NimLaunch
```

```bash
nimble build          # default release build -> ./bin/nimlaunch
nimble test           # run all automated test suites
nimble -y nimDebug    # debug build -> ./bin/nimlaunch
nimble -y nimRelease  # release build for current CPU (fastest on this machine) -> ./bin/nimlaunch
nimble -y nimGeneric  # portable + smaller release build (generic x86_64 baseline) -> ./bin/nimlaunch
```

For a more portable release build (via Zig/clang), use:

```bash
nimble -y zigDebug    # debug build -> ./bin/nimlaunch
nimble -y zigRelease  # release build for current CPU via Zig/clang -> ./bin/nimlaunch
nimble -y zigGeneric  # portable + smaller Zig/clang release build (generic x86_64 baseline) -> ./bin/nimlaunch
```

The native tasks require a C compiler. The Zig tasks additionally require
`zig` on `PATH`; the included `zigcc` wrapper is selected automatically.

Use `nimble c` from project root if you need custom compiler flags:

```bash
nimble c -d:release -d:lto --opt:speed --mm:orc --threads:on -o:./bin/nimlaunch src/nimlaunch.nim
```

```bash
./bin/nimlaunch
```

Place the binary (`nimlaunch`) somewhere on your `PATH` (e.g., `~/.local/bin`) and
bind a hotkey to launch it. The TOML config is auto-generated on first run.

## Wayland/X11
Runs natively on both via SDL3 (no XWayland required on Wayland). Borderless
window like the original. GPU compositing handles fills/icons/text blits; SDL_ttf
still rasterizes glyphs in software.

## Troubleshooting
- Build fails with `cannot open .../src/nimlaunch.nim`: build from project root,
  and use `nimble build`, `nimble c ...`, or the provided Nimble tasks.
- Build fails with `cannot open file: sdl3` or `parsetoml`: make sure you are
  building from project root so `config.nims` can add the vendored `packages/`
  paths.
- `nimble nimGeneric` or `nimble zigGeneric` is unknown: update to the current
  `.nimble` file.
- `:s` search feels slow: install `fd` and/or `locate` so search avoids the
  slower `$HOME` fallback walk.
- Icons are missing for SVG apps: ensure your `SDL3_image` build includes SVG
  support. This project now loads SVG icons through `SDL3_image` directly.
- `--dmenu` looks empty: make sure you are piping newline-separated input into
  it, for example `printf "one\\ntwo\\n" | nimlaunch --dmenu`.
- Text looks wrong or too small: set `[font].fontname` to an installed font and
  size (e.g., `"Dejavu:size=16"`). Row and window height adjust automatically;
  the visible row count is reduced only when the display is too small.
- Wayland/Niri black padding or delayed repaint: use a debug build with
  `-d:nimlaunchWindowDebug` to log window events and redraw timing.
- Theme changes do not persist: verify the NimLaunch configuration file
  is writable.

## Command Line Flags
- `--config`, `-c`: Override the default config file path (e.g. `./nimlaunch --config /path/to/alt.toml`). Auto-generates a clean config if the file doesn't exist.
- `--version`, `-v`: Print the current NimLaunch version and exit.
- `--list-themes`: Print all available themes and exit.
- `--verbose`: Dump internal metrics (uptime, cache sizes, parsing stats) to standard error upon closing.
- `--dmenu`: Turns NimLaunch into a generic selector for stdin-provided items.
- `--prompt`, `-p`: Override the prompt when using `--dmenu`.
- `--dry-run`: Prints the selected raw action without running it. Desktop-entry field codes are not expanded.
- `--help`, `-h`: Print command-line usage and exit.


## Quick Reference
Core controls:

| Trigger | Context | Effect |
| ------- | ------- | ------ |
| Type text | Normal | Fuzzy-search applications; top hit updates instantly |
| Enter | Normal or command bar | Launch the highlighted entry immediately |
| Esc | Command bar | Close the bar, keep the narrowed results selected |
| Esc | Normal | Exit NimLaunch |
| ↑ / ↓ / PgUp / PgDn / Home / End | Any | Navigate the results list |
| `/` | Normal | Toggle the command bar (restores previous `/` search) |
| `:` / `!` | Normal | Open the bar primed for a prefix or `!` command |
| Ctrl+U | Command bar | Clear the current query |
| Ctrl+H / Backspace | Command bar | Delete one character (closes the bar when empty) |
| Ctrl+V | Any | Paste text from clipboard |

### Built-in prefixes

| Prefix | Example | Description |
| ------ | ------- | ----------- |
| *none* | `fire` | Regular app search; rankings favour prefixes, recent launches, and persistent usage |
| `:t` | `:t nord` | Browse themes; Up/Down preview, Enter to keep selection |
| `:s` | `:s notes` | Search files (`fd` → `locate` → bounded `$HOME` walk) |
| `:c` | `:c sway` | Match files inside the XDG configuration directory and open with the default handler |
| `:r` | `:r htop` | Run a shell command inside your preferred terminal |
| `:q`, `:quit` | `:q` | Exit NimLaunch immediately from the command bar |
| `!` | `!htop` | Shorthand for `:r` without the colon |
| `:<group>` | `:sys lock` | Run grouped shortcuts (for example a `sys` group for session/power actions) |

## Configuration
Config path: `${XDG_CONFIG_HOME:-~/.config}/nimlaunch/nimlaunch.toml`
(auto-generated on first run).

We provide an `examples/` directory containing showcase integrations:
- `examples/nimlaunch.toml` - A larger sample configuration with calculator snippets, window switchers, grouped actions, and more.
- `examples/scripts/` - Bash scripts demonstrating `--dmenu` and native Rofi icon injection.

For the full config layout, field descriptions, theme handling, and generated
default behavior, see [Configuration Guide](docs/configuration.md).

## More Detail
- Shortcut and group configuration: [Groups and Shortcuts](docs/groups-and-shortcuts.md)
- Theme definition and persistence: [Themes](docs/themes.md)
- `--dmenu` wrappers and patterns: [Dmenu Mode](docs/dmenu.md)
