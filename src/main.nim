import std/[os, strutils, syncio]
import sdl3
import ./[state, app_core, gui, utils, settings, search, input, apps_cache, theme_session]

const Version = "0.11.5"

# Print the command-line synopsis and available options.
proc printUsage() =
  echo """Usage: nimlaunch [options]

Options:
  -c, --config PATH  Use an alternate configuration file
  -p, --prompt TEXT  Override the prompt in --dmenu mode
      --dmenu         Select an item read from standard input
      --dry-run       Print the selected raw action without executing it
      --list-themes   Print configured theme names and exit
      --verbose       Print runtime metrics on shutdown
  -v, --version       Print the version and exit
  -h, --help          Show this help text and exit"""

# Parse command-line options into the shared startup context.
proc configureStartupMode() =
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    if arg == "--version" or arg == "-v":
      echo "NimLaunch v", Version
      quit 0
    elif arg == "--help" or arg == "-h":
      printUsage()
      quit 0
    elif arg == "--list-themes":
      ctx.listThemesMode = true
    elif arg == "--dry-run":
      ctx.dryRunMode = true
    elif arg == "--verbose":
      ctx.verboseMode = true
    elif arg == "--dmenu":
      ctx.dmenuMode = true
    elif arg == "--prompt" or arg == "-p":
      if i < paramCount():
        ctx.dmenuPrompt = paramStr(i + 1)
        inc i
      else:
        quit "Error: --prompt requires a text argument."
    elif arg == "--config" or arg == "-c":
      if i < paramCount():
        ctx.configOverridePath = paramStr(i + 1)
        inc i
      else:
        quit "Error: --config requires a path argument."
    else:
      quit "Error: unknown option '" & arg & "'. Use --help for usage."
    inc i

  if ctx.dmenuPrompt.len > 0 and not ctx.dmenuMode:
    quit "Error: --prompt can only be used with --dmenu."

# Read non-empty dmenu entries and extract optional Rofi icon metadata.
proc loadDmenuInput() =
  let raw = stdin.readAll()
  ctx.dmenuItems.setLen(0)
  for line in raw.splitLines():
    var item = line
    if item.len > 0 and item[^1] == '\r':
      item.setLen(item.len - 1)
    if item.len > 0:
      var label = item
      var iconName = ""
      let nullPos = item.find('\0')
      if nullPos != -1:
        label = item[0 ..< nullPos]
        let remainder = item[nullPos + 1 .. ^1]
        let prefix = "icon\x1f"
        if remainder.startsWith(prefix):
          iconName = remainder[prefix.len .. ^1]
      ctx.dmenuItems.add DmenuItem(label: label, labelLower: label.toLowerAscii(), iconName: iconName)

proc processSearchDebounce(): bool =
  ## Debounce wake-up: if we're in s: search, rebuild after idle.
  let (cmd, rest, _, _) = parseCommand(ctx.inputText)
  if cmd != ckSearch:
    return false
  let now = gui.nowMs()
  let sinceEdit = now - ctx.lastInputChangeMs
  if rest.len >= 2 and sinceEdit >= SearchDebounceMs and
     lastSearchBuildMs < ctx.lastInputChangeMs:
    lastSearchBuildMs = now
    buildActions()
    return true
  false

proc main*() =
  let startupTimeMs = gui.nowMs()
  configureStartupMode()

  if not ctx.dmenuMode and not ensureSingleInstance():
    echo "NimLaunch is already running."
    quit 0
  initLauncherConfig()
  if ctx.dmenuPrompt.len > 0:
    ctx.config.prompt = ctx.dmenuPrompt

  if ctx.listThemesMode:
    for th in ctx.themeList:
      echo th.name
    quit 0
  if ctx.dmenuMode:
    loadDmenuInput()
  else:
    loadApplications()
    loadRecent()
    loadUsage()
    startSearchWorker()
  buildActions()

  resetVimState()

  gui.initGui()
  updateParsedColors(ctx.config)
  gui.updateGuiColors()
  gui.redrawWindow()

  var ev: Event
  var focus: FocusState
  focus.startMs = gui.nowMs()
  focus.lastGainMs = focus.startMs

  while not ctx.shouldExit:
    while pollEvent(ev):
      case ev.`type`
      of EVENT_QUIT:
        ctx.shouldExit = true
      of EVENT_WINDOW_SHOWN, EVENT_WINDOW_HIDDEN, EVENT_WINDOW_EXPOSED,
          EVENT_WINDOW_MOVED, EVENT_WINDOW_RESIZED, EVENT_WINDOW_PIXEL_SIZE_CHANGED,
          EVENT_WINDOW_MINIMIZED, EVENT_WINDOW_FOCUS_GAINED, EVENT_WINDOW_FOCUS_LOST,
          EVENT_WINDOW_DISPLAY_CHANGED, EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
        if handleWindowEvent(ev, focus):
          gui.redrawWindow()
      of EVENT_KEY_DOWN:
        if handleKeyDown(ev, focus):
          gui.redrawWindow()
      of EVENT_TEXT_INPUT:
        if handleTextInput(ev, focus):
          gui.redrawWindow()
      of EVENT_TEXT_EDITING:
        if handleTextEditing(ev):
          gui.redrawWindow()
      of EVENT_TEXT_EDITING_CANDIDATES:
        if handleTextEditingCandidates(ev):
          gui.redrawWindow()
      of EVENT_USER:
        gui.redrawWindow()
      else:
        discard

    if ctx.shouldExit: break

    if processSearchDebounce():
      gui.redrawWindow()
      continue

    if pollSearchUpdates():
      gui.redrawWindow()
      continue

    if gui.needsTimedRedraw():
      gui.redrawWindow()

    delay(ctx.config.pollIntervalMs.uint32)

  if ctx.themePreviewActive:
    endThemePreviewSession(false)

  stopSearchWorker()

  if ctx.verboseMode:
    let uptimeMs = gui.nowMs() - startupTimeMs
    stderr.writeLine "NimLaunch shutting down."
    stderr.writeLine "  Uptime: " & $uptimeMs & " ms"
    stderr.writeLine "  Apps parsed: " & $ctx.allApps.len
    stderr.writeLine "  Icons cached: " & $getIconCacheSize()

  gui.shutdownGui()
  if ctx.dmenuMode:
    if ctx.dmenuAccepted:
      if not ctx.dmenuDryRunAccepted:
        stdout.write(ctx.dmenuOutput & "\n")
      quit 0
    quit 1

when isMainModule:
  main()
