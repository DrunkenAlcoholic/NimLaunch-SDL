import std/[assertions, os, osproc, strutils, unicode]
import sdl3
import ../src/[state, layout, parser, fuzzy, app_core, input, proc_utils, utils,
    settings, apps_cache, search, gui]

block font_drives_layout:
  for fontHeight in [12, 16, 24, 32, 48, 64]:
    let input = LayoutInput(
      canvasHeight: 2000,
      requestedRows: 10,
      configuredLineHeight: 22,
      fontLineHeight: fontHeight,
      overlayLineHeight: max(10, fontHeight - 2),
      iconMinimum: 18,
      textPadding: 4,
      outerMargin: 10,
      rowGap: 6,
      commandExtraHeight: 6,
      commandBottomGap: 4,
      vimMode: false,
      showIcons: true)
    let computed = computeLayout(input)
    doAssert computed.rowHeight >= fontHeight + 4
    doAssert computed.visibleRows == 10
    doAssert computed.desiredHeight >= computed.contentTop + 10 * computed.rowHeight

block small_canvas_reduces_visible_rows:
  let computed = computeLayout(LayoutInput(
    canvasHeight: 180,
    requestedRows: 20,
    configuredLineHeight: 22,
    fontLineHeight: 32,
    overlayLineHeight: 30,
    iconMinimum: 18,
    textPadding: 4,
    outerMargin: 10,
    rowGap: 6,
    commandExtraHeight: 6,
    commandBottomGap: 4,
    vimMode: false,
    showIcons: true))
  doAssert computed.visibleRows < 20
  doAssert computed.contentTop + computed.visibleRows * computed.rowHeight <=
      computed.contentBottom

block empty_quoted_argument_is_preserved:
  doAssert tokenize("program \"\" tail") == @["program", "", "tail"]
  doAssert expandExecArgs("program \"\" tail").args == @["program", "", "tail"]
  doAssert expandExecArgs("program %f tail").args == @["program", "tail"]

block unicode_highlights_are_valid:
  let text = "Café 東京"
  let spans = subseqSpans("é東", text)
  doAssert spans.len == 2
  for (start, length) in spans:
    doAssert validateUtf8(text[start..<start + length]) == -1
  doAssert scoreMatch("É", "", "é", "", "", "") > -1_000_000

block unicode_path_shortening_is_valid:
  let shortened = shortenPath("/tmp/東京/📄-résumé.txt", 12)
  doAssert shortened.runeLen <= 12
  doAssert validateUtf8(shortened) == -1

block vim_backspace_does_not_drop_later_text:
  ctx.config.vimMode = true
  ctx.vim.active = true
  ctx.vim.buffer = "ab"
  doAssert handleVimCommandKey(SDLK_BACKSPACE, false)
  var event: Event
  event.text.text = "c"
  var focus: FocusState
  doAssert handleTextInput(event, focus)
  doAssert ctx.vim.buffer == "ac"

block same_name_apps_keep_distinct_identity:
  ctx.config = Config(maxVisibleItems: 10, lineHeight: 22)
  ctx.inputText = ""
  ctx.allApps = @[
    DesktopApp(name: "Editor", nameLower: "editor", exec: "one",
        desktopId: "one.desktop"),
    DesktopApp(name: "Editor", nameLower: "editor", exec: "two",
        desktopId: "two.desktop")]
  ctx.recentApps = @["one.desktop"]
  buildActions()
  doAssert ctx.actions.len == 2
  doAssert appIdentity(ctx.actions[0].appData) == "one.desktop"
  doAssert appIdentity(ctx.actions[1].appData) == "two.desktop"

block shell_wrapper_accepts_trailing_syntax:
  for command in ["true;", "true &", "printf ok | cat", "true # final comment"]:
    let generated = buildShellCommand(command, "/bin/sh", hold = true).fullCmd
    let process = startProcess("/bin/sh", args = @["-n", "-c", generated])
    doAssert process.waitForExit() == 0
    process.close()

block theme_writer_preserves_comments_and_single_table:
  let path = getTempDir() / "nimlaunch-theme-save.toml"
  defer:
    if fileExists(path):
      removeFile(path)
  writeFile(path, "[theme] # selected\n\"last_chosen\" = \"Old\" # keep\n" &
      "[[themes]]\nname = \"Example\"\n")
  ctx.config.themeName = "New"
  doAssert saveLastTheme(path)
  let saved = readFile(path)
  doAssert saved.count("[theme]") == 1
  doAssert saved.contains("last_chosen = \"New\" # keep")
  doAssert saved.contains("[[themes]]\nname = \"Example\"")

block malformed_theme_file_is_not_overwritten:
  let path = getTempDir() / "nimlaunch-theme-invalid.toml"
  defer:
    if fileExists(path):
      removeFile(path)
  let original = "[theme\nlast_chosen = \"Old\"\n"
  writeFile(path, original)
  ctx.config.themeName = "New"
  doAssert not saveLastTheme(path)
  doAssert readFile(path) == original

block expired_status_requests_clear_redraw:
  gui.statusText = "done"
  gui.statusUntilMs = 0
  doAssert gui.needsTimedRedraw()
  doAssert gui.statusText.len == 0

block dmenu_dry_run_records_success:
  ctx.dryRunMode = true
  ctx.dmenuMode = true
  ctx.dmenuAccepted = false
  ctx.dmenuDryRunAccepted = false
  ctx.shouldExit = false
  performAction(Action(kind: akDmenu, exec: "selected"))
  doAssert ctx.shouldExit
  doAssert ctx.dmenuAccepted
  doAssert ctx.dmenuDryRunAccepted
  ctx.dryRunMode = false
  ctx.dmenuMode = false

block desktop_id_precedence_honours_hidden_override:
  let root = getTempDir() / "nimlaunch-desktop-precedence"
  let userData = root / "user"
  let systemData = root / "system"
  let cacheData = root / "cache"
  createDir(userData / "applications")
  createDir(systemData / "applications")
  defer:
    if dirExists(root):
      removeDir(root)
  let oldDataHome = getEnv("XDG_DATA_HOME")
  let oldDataDirs = getEnv("XDG_DATA_DIRS")
  let oldCacheHome = getEnv("XDG_CACHE_HOME")
  let oldLocale = getEnv("LC_ALL")
  defer:
    putEnv("XDG_DATA_HOME", oldDataHome)
    putEnv("XDG_DATA_DIRS", oldDataDirs)
    putEnv("XDG_CACHE_HOME", oldCacheHome)
    putEnv("LC_ALL", oldLocale)
  putEnv("XDG_DATA_HOME", userData)
  putEnv("XDG_DATA_DIRS", systemData)
  putEnv("XDG_CACHE_HOME", cacheData)
  putEnv("LC_ALL", "C")
  writeFile(systemData / "applications/example.desktop",
      "[Desktop Entry]\nName=System\nExec=system-app\n")
  writeFile(userData / "applications/example.desktop",
      "[Desktop Entry]\nName=Hidden\nExec=user-app\nHidden=true\n")
  loadApplications()
  doAssert ctx.allApps.len == 0
  writeFile(userData / "applications/example.desktop",
      "[Desktop Entry]\nName=User\nName[fr]=Utilisateur\n" &
      "Exec=user-app\nPath=/tmp\n")
  loadApplications()
  doAssert ctx.allApps.len == 1
  doAssert ctx.allApps[0].desktopId == "example.desktop"
  doAssert ctx.allApps[0].exec == "user-app"
  doAssert ctx.allApps[0].workingDir == "/tmp"
  putEnv("LC_ALL", "fr_FR.UTF-8")
  loadApplications()
  doAssert ctx.allApps[0].name == "Utilisateur"

block try_exec_changes_invalidate_application_cache:
  let root = getTempDir() / "nimlaunch-tryexec-cache"
  let userData = root / "user"
  let systemData = root / "system"
  let cacheData = root / "cache"
  let executable = root / "available-command"
  createDir(userData / "applications")
  createDir(systemData / "applications")
  defer:
    if dirExists(root):
      removeDir(root)
  let oldDataHome = getEnv("XDG_DATA_HOME")
  let oldDataDirs = getEnv("XDG_DATA_DIRS")
  let oldCacheHome = getEnv("XDG_CACHE_HOME")
  defer:
    putEnv("XDG_DATA_HOME", oldDataHome)
    putEnv("XDG_DATA_DIRS", oldDataDirs)
    putEnv("XDG_CACHE_HOME", oldCacheHome)
  putEnv("XDG_DATA_HOME", userData)
  putEnv("XDG_DATA_DIRS", systemData)
  putEnv("XDG_CACHE_HOME", cacheData)
  writeFile(executable, "#!/bin/sh\nexit 0\n")
  setFilePermissions(executable, {fpUserRead, fpUserWrite, fpUserExec})
  writeFile(userData / "applications/tryexec.desktop",
      "[Desktop Entry]\nName=Conditional\nExec=conditional\nTryExec=" &
      executable & "\n")
  loadApplications()
  doAssert ctx.allApps.len == 1
  removeFile(executable)
  loadApplications()
  doAssert ctx.allApps.len == 0

block desktop_working_directory_reaches_spawn:
  let root = getTempDir() / "nimlaunch-working-directory"
  let output = root / "pwd.txt"
  createDir(root)
  defer:
    if dirExists(root):
      removeDir(root)
  doAssert spawnProcess("/bin/sh", ["-c", "pwd > \"$1\"", "sh", output], root)
  for _ in 0..<200:
    if fileExists(output):
      break
    sleep(10)
  doAssert fileExists(output)
  doAssert readFile(output).strip() == root

block background_search_returns_without_blocking_request:
  let root = getTempDir() / "nimlaunch-search-worker"
  createDir(root)
  defer:
    stopSearchWorker()
    if dirExists(root):
      removeDir(root)
  let oldHome = getEnv("HOME")
  defer: putEnv("HOME", oldHome)
  putEnv("HOME", root)
  startSearchWorker()
  let generation = requestFileSearch("nothing-matches-this-query")
  doAssert generation > 0
  var response: SearchResponse
  var received = false
  for _ in 0..<500:
    if pollFileSearch(response):
      received = true
      break
    sleep(10)
  doAssert received
  doAssert response.generation == generation
  doAssert response.query == "nothing-matches-this-query"
