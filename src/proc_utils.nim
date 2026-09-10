## proc_utils.nim — process spawning, terminal selection, and file-opening helpers.

import std/[os, osproc, strutils, syncio]
import ./[state, parser]

proc whichExists*(name: string): bool =
  ## True if an executable can be found in $PATH (or is a path that exists).
  if name.len == 0: return false
  if name.contains('/'): return fileExists(name)
  findExe(name).len > 0

proc tryStart(candidates: seq[(string, seq[string])]): bool =
  ## Attempt to start each (exe, args) pair; return true on first success.
  for (exe, args) in candidates:
    if exe.len == 0: continue
    try:
      discard startProcess(exe, args = args, options = {poDaemon,
          poParentStreams})
      return true
    except CatchableError:
      discard
  false

proc openPathWithDefault*(path: string): bool =
  ## Open a file with the system default handler; fall back to common editors.
  let absPath = absolutePath(path)
  if not fileExists(absPath): return false

  ## Preferred system openers
  if tryStart(@[(findExe("xdg-open"), @[absPath]),
               (findExe("gio"), @["open", absPath])]):
    return true

  ## Respect user editor preference
  var envCandidates: seq[(string, seq[string])] = @[]
  for envName in ["VISUAL", "EDITOR"]:
    let ed = getEnv(envName)
    if ed.len == 0:
      continue
    let tokens = tokenize(ed)
    if tokens.len == 0:
      continue
    let head = tokens[0]
    var exePath: string
    if head.contains('/'):
      try:
        exePath = expandFilename(head)
      except OSError:
        continue
      if not fileExists(exePath):
        exePath = ""
    else:
      exePath = findExe(head)
    if exePath.len == 0:
      continue
    var args: seq[string] = @[]
    if tokens.len > 1:
      args = tokens[1 ..< tokens.len]
    args.add absPath
    envCandidates.add((exePath, args))
  if tryStart(envCandidates):
    return true

  ## Fallback shortlist
  var fallbackCandidates: seq[(string, seq[string])] = @[]
  for ed in ["gedit", "kate", "mousepad", "code", "nano", "vi"]:
    let exe = findExe(ed)
    if exe.len > 0:
      fallbackCandidates.add((exe, @[absPath]))
  if tryStart(fallbackCandidates):
    return true

  false

proc openPathWithFallback*(path: string): bool =
  ## Open files or directories, falling back to xdg-open when needed.
  let resolved = path.expandTilde()
  if openPathWithDefault(resolved): return true
  if dirExists(resolved) or fileExists(resolved):
    try:
      discard startProcess("/usr/bin/env", args = @["xdg-open", resolved],
          options = {poDaemon})
      return true
    except CatchableError:
      stderr.writeLine "openPathWithFallback failed: " & resolved
  false

proc chooseTerminal*(): string =
  ## Pick a terminal emulator: prefer ctx.config.terminalExe, then $TERMINAL, then fallbacks.
  if ctx.config.terminalExe.len > 0:
    let tokens = tokenize(ctx.config.terminalExe)
    if tokens.len > 0 and whichExists(tokens[0]):
      return ctx.config.terminalExe
  let envTerm = getEnv("TERMINAL")
  if envTerm.len > 0:
    let tokens = tokenize(envTerm)
    if tokens.len > 0 and whichExists(tokens[0]):
      return envTerm
  for t in fallbackTerms:
    if whichExists(t):
      return t
  "" # headless

proc hasHoldFlagLocal*(args: seq[string]): bool =
  ## Detect common "keep window open" flags passed to terminals.
  for a in args:
    case a
    of "--hold", "-hold", "--keep-open", "--wait", "--noclose",
       "--stay-open", "--keep", "--keepalive":
      return true
    else:
      discard
  false

proc appendShellArgs*(argv: var seq[string]; shExe: string; shArgs: seq[string]) =
  ## Append shell executable and its arguments to `argv`.
  argv.add shExe
  for a in shArgs: argv.add a

proc buildTerminalArgs*(base: string; termArgs: seq[string]; shExe: string;
                       shArgs: seq[string]): seq[string] =
  ## Normalize command-line to launch a shell inside major terminals.
  var argv = termArgs
  case base
  of "gnome-terminal", "kgx":
    argv.add "--"
  of "wezterm":
    argv = @["start"] & argv
  else:
    argv.add "-e"
  appendShellArgs(argv, shExe, shArgs)
  argv

proc buildShellCommand*(cmd, shExe: string; hold = false):
    tuple[fullCmd: string; shArgs: seq[string]] =
  ## Run user's command in a group, and add a robust hold prompt when needed.
  ## Grouping prevents suffix binding to pipelines/conditionals.
  let suffix = if hold: "" else:
    "\nprintf '\\n[Press Enter to close]\\n'\nread -r _"
  let fullCmd = "{\n" & cmd & "\n}" & suffix
  let shArgs = if shExe.endsWith("bash"): @["-lc", fullCmd] else: @["-c", fullCmd]
  (fullCmd, shArgs)

proc runCommand*(cmd: string): bool =
  ## Run `cmd` in the user's terminal. Fails gracefully if no terminal is found.
  let bash = findExe("bash")
  let shExe = if bash.len > 0: bash else: "/bin/sh"

  var parts = tokenize(chooseTerminal())
  if parts.len == 0:
    stderr.writeLine "runCommand failed: No terminal emulator configured or found."
    return false

  let exe = parts[0]
  let exePath = findExe(exe)
  if exePath.len == 0:
    stderr.writeLine "runCommand failed: Terminal emulator '" & exe & "' not found."
    return false

  var termArgs = if parts.len > 1: parts[1..^1] else: @[]
  let base = exe.extractFilename()
  let hold = hasHoldFlagLocal(termArgs)
  let (_, shArgs) = buildShellCommand(cmd, shExe, hold)
  let argv = buildTerminalArgs(base, termArgs, shExe, shArgs)
  try:
    discard startProcess(exePath, args = argv,
                         options = {poDaemon, poParentStreams})
    true
  except CatchableError as e:
    stderr.writeLine "runCommand failed: " & cmd & " (" & $e.name & "): " & e.msg
    false

proc spawnShellCommand*(cmd: string): bool =
  ## Execute *cmd* via /bin/sh in the background; return success.
  try:
    discard startProcess("/bin/sh", args = ["-c", cmd],
                         options = {poDaemon, poParentStreams})
    true
  except CatchableError as e:
    stderr.writeLine "spawnShellCommand failed: " & cmd & " (" & $e.name & "): " & e.msg
    false

proc spawnProcess*(exe: string; args: openArray[string]; workingDir = ""): bool =
  ## Execute *exe* directly without a shell in the background; return success.
  if workingDir.len > 0 and not dirExists(workingDir):
    stderr.writeLine "spawnProcess failed: working directory not found: " & workingDir
    return false
  try:
    discard startProcess(exe, args = args,
                         workingDir = workingDir,
                         options = {poDaemon, poParentStreams, poUsePath})
    true
  except CatchableError as e:
    stderr.writeLine "spawnProcess failed: " & exe & " (" & $e.name & "): " & e.msg
    false

proc openUrl*(url: string): bool =
  ## Open *url* via xdg-open (no shell involved). Log failures for diagnosis.
  try:
    discard startProcess("/usr/bin/env", args = @["xdg-open", url],
                         options = {poDaemon, poParentStreams})
    true
  except CatchableError as e:
    stderr.writeLine "openUrl failed: " & url & " (" & $e.name & "): " & e.msg
    false
