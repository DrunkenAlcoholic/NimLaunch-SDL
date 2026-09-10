## state.nim — core data definitions and runtime state
## Derived from NimLaunch X11 version, adapted to remove X11 types.

import std/tables
# ── Data structures ─────────────────────────────────────────────────────
type
  DmenuItem* = object
    label*: string
    labelLower*: string
    iconName*: string

  Rgb* = object
    r*, g*, b*: uint8

  ## A secondary action declared in a .desktop file.
  DesktopEntryAction* = object
    id*: string
    name*: string
    nameLower*: string
    exec*: string
    icon*: string
    hasIcon*: bool

  ## A single launchable application parsed from a `.desktop` file.
  DesktopApp* = object
    name*, nameLower*, exec*, desktopFile*: string
    desktopId*, workingDir*: string
    icon*: string
    hasIcon*: bool
    desktopActions*: seq[DesktopEntryAction]

  ## Payload cached to `~/.cache/nimlaunch/apps.json`.
  CacheData* = object
    formatVersion*: int
    environmentSignature*: string
    appDirs*: seq[string]
    dirMtimes*: seq[int64]
    dirSignatures*: seq[string]
    apps*: seq[DesktopApp]

  AppUsage* = object
    launchCount*: int
    lastLaunched*: int64

  ## Launcher configuration populated by initLauncherConfig.
  Config* = object
    # Window geometry ----------------------------------------------------
    winWidth*, winMaxHeight*: int
    opacity*: float          ## 0.1 - 1.0 window opacity (SDL window)
    lineHeight*, maxVisibleItems*: int
    centerWindow*: bool
    positionX*, positionY*: int
    verticalAlign*: string   ## "top" | "center" | "one-third"
    displayIndex*: int       ## display index for centered positioning

    # Colours as hex strings (resolved to SDL colours later) -------------
    bgColorHex*, fgColorHex*: string
    highlightBgColorHex*, highlightFgColorHex*: string
    borderColorHex*: string
    borderWidth*: int
    matchFgColorHex*: string ## color for matched letters (e.g. "#FF00FF")
    showIcons*: bool

    # Prompt / font / theme / terminal ----------------------------------
    prompt*, cursor*: string
    fontName*: string
    themeName*: string
    terminalExe*: string     ## preferred terminal program
    vimMode*: bool
    pollIntervalMs*: int

    # Resolved colours (set after theme application) --------------------
    bgColor*, fgColor*, highlightBgColor*, highlightFgColor*,
      borderColor*, matchFgColor*: Rgb

  PowerActionMode* = enum
    pamSpawn,   # execute via background shell
    pamTerminal # run inside configured terminal

  GroupQueryMode* = enum
    gqmFilter, # group query filters entries by label
    gqmPass    # group query passes through as {query}

  ShortcutMode* = enum
    smUrl,   # open base with URL-encoded query
    smShell, # run base as a shell command
    smFile   # treat base as a filesystem path

  ## User-configurable prefix shortcut.
  Shortcut* = object
    prefix*, label*, base*: string
    mode*: ShortcutMode
    group*: string # optional group label (e.g., "sys")
    runMode*: PowerActionMode = pamTerminal
    stayOpen*: bool = false

  ## What kind of thing the user can pick.
  ActionKind* = enum
    akApp,      # a real .desktop application
    akAppAction,# a .desktop secondary action (e.g. New Window)
    akDmenu,    # a generic stdin-provided entry
    akRun,      # a `:r` shell command
    akConfig,   # `:c` file under ~/.config
    akFile,     # `:s` file search (open with default app)
    akShortcut, # configurable shortcut (URL/shell/file)
    akTheme,    # `:t` Theme selector
    akPlaceholder

  ## A single selectable entry in the launcher.
  Action* = object
    kind*: ActionKind
    label*: string       # what gets drawn (e.g. "Firefox" or "Run: ls")
    exec*: string        # what actually gets executed or opened
    appData*: DesktopApp # optional for akApp; empty for other kinds
    iconName*: string
    desktopName*, desktopIcon*: string
    shortcutMode*: ShortcutMode = smUrl
    powerMode*: PowerActionMode = pamTerminal
    stayOpen*: bool = false

  ## Lightweight row metadata for rendering the results list.
  DisplayRow* = object
    text*: string
    iconName*: string

  VimCommandState* = object
    prefix*: string
    buffer*: string
    lastSearch*: string
    pendingG*: bool
    active*: bool
    savedInput*: string
    savedSelectedIndex*: int
    savedViewOffset*: int
    restorePending*: bool

  ## Theme definition (matchFgColorHex is explicit; no "auto" support).
  Theme* = object
    name*: string
    bgColorHex*: string
    fgColorHex*: string
    highlightBgColorHex*: string
    highlightFgColorHex*: string
    borderColorHex*: string
    matchFgColorHex*: string ## leave empty to inherit Config.matchFgColorHex

  AppContext* = object
    config*: Config
    allApps*: seq[DesktopApp]
    filteredApps*: seq[DisplayRow]
    inputText*: string
    lastInputChangeMs*: int64
    selectedIndex*: int
    viewOffset*: int
    shouldExit*: bool
    recentApps*: seq[string]
    appUsage*: Table[string, AppUsage]
    themeList*: seq[Theme]
    matchSpans*: seq[seq[(int, int)]]
    shortcuts*: seq[Shortcut]
    groupQueryModes*: Table[string, GroupQueryMode]
    configFilesLoaded*: bool
    configFilesCache*: seq[DesktopApp]
    vim*: VimCommandState
    themePreviewActive*: bool
    themePreviewBaseTheme*: string
    themePreviewCurrent*: string
    dmenuMode*: bool
    dmenuItems*: seq[DmenuItem]
    dmenuAccepted*: bool
    dmenuDryRunAccepted*: bool
    dmenuOutput*: string
    dmenuPrompt*: string
    listThemesMode*: bool
    dryRunMode*: bool
    verboseMode*: bool
    configOverridePath*: string
    actions*: seq[Action]

var ctx*: AppContext
ctx.configFilesLoaded = false
ctx.configFilesCache = @[]
ctx.themePreviewActive = false
ctx.dmenuMode = false
ctx.dmenuItems = @[]
ctx.dmenuAccepted = false
ctx.dmenuPrompt = ""
ctx.listThemesMode = false
ctx.dryRunMode = false
ctx.verboseMode = false
ctx.configOverridePath = ""

# ── Constants ───────────────────────────────────────────────────────────
const
  ## Hard-coded terminal fallback search order.
  fallbackTerms* = [
    "kitty", "alacritty", "wezterm", "foot",
    "gnome-terminal", "konsole", "xfce4-terminal", "xterm"
  ]
  maxRecent* = 10

import ./default_config
export default_config
