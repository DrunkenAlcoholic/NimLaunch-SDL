## parser.nim — helpers for reading `.desktop` files
## Mostly identical to NimLaunch, minus X11 dependencies.

import std/[os, strutils, streams, tables, options]
import ./state # DesktopApp

# ── Internal helpers ────────────────────────────────────────────────────

proc tokenize*(cmd: string): seq[string] =
  ## Shell-ish tokenizer for Exec= lines.
  ## Handles simple quotes, backslash escapes inside double-quotes,
  ## and whitespace splitting. Not a full shell parser.
  var cur = newStringOfCap(32)
  var i = 0
  var inQuote = '\0'
  var tokenStarted = false
  while i < cmd.len:
    let c = cmd[i]
    if inQuote == '\0':
      case c
      of ' ', '\t':
        if tokenStarted:
          result.add cur
          cur.setLen(0)
          tokenStarted = false
      of '"', '\'':
        inQuote = c
        tokenStarted = true
      of '\\':
        if i+1 < cmd.len:
          cur.add cmd[i+1]
          inc i
          tokenStarted = true
      else:
        cur.add c
        tokenStarted = true
    else:
      if c == inQuote:
        inQuote = '\0'
      elif c == '\\' and inQuote == '"' and i+1 < cmd.len:
        cur.add cmd[i+1]
        inc i
      else:
        cur.add c
        tokenStarted = true
    inc i
  if tokenStarted:
    result.add cur

proc expandExecToken(token, name, icon, desktopFile: string;
    args: var seq[string]): bool =
  ## Expand field codes in one token and append any resulting arguments.
  var expanded = newStringOfCap(token.len + name.len)
  var discardToken = false
  var hadFieldCode = false
  var i = 0
  while i < token.len:
    if token[i] != '%':
      expanded.add token[i]
      inc i
    elif i + 1 >= token.len:
      return false
    else:
      hadFieldCode = true
      case token[i + 1]
      of '%':
        expanded.add '%'
      of 'f', 'F', 'u', 'U':
        discardToken = true
      of 'i':
        if token != "%i":
          return false
        if icon.len > 0:
          args.add "--icon"
          args.add icon
        return true
      of 'c':
        expanded.add name
      of 'k':
        expanded.add desktopFile
      of 'd', 'D', 'n', 'N', 'v', 'm':
        discard
      else:
        return false
      inc i, 2
  if not discardToken and (expanded.len > 0 or not hadFieldCode):
    args.add expanded
  true

proc expandExecArgs*(exec: string; name = ""; icon = "";
    desktopFile = ""): tuple[args: seq[string]; valid: bool] =
  ## Expand Desktop Entry field codes into arguments without invoking a shell.
  result.valid = true
  let tokens: seq[string] = tokenize(exec)
  for token in tokens:
    if not expandExecToken(token, name, icon, desktopFile, result.args):
      result.args.setLen(0)
      result.valid = false
      return

proc stripFieldCodes*(s: string): string =
  ## Remove Desktop Entry field codes for command identity comparisons.
  let expanded = expandExecArgs(s)
  if expanded.valid:
    result = expanded.args.join(" ")

proc isEnvAssign(tok: string): bool =
  ## True if token is an environment assignment (e.g., FOO=bar).
  let eq = tok.find('=')
  eq > 0 and tok[0..eq-1].allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_'})

# ── Exec-line utilities ─────────────────────────────────────────────────

proc getBaseExec*(exec: string): string =
  ## Strip arguments/placeholders from Exec= and return a de-dup identifier.
  ## Examples:
  ##   "/usr/bin/kitty --single-instance"      → "kitty"
  ##   "code %F"                                → "code"
  ##   "env FOO=1 VAR=2 /opt/app/bin/foo %U"    → "foo"
  ##   "flatpak run com.app.Name"               → "com.app.Name"
  ##   "snap run app"                           → "app"
  ##   "sh -c 'prog --opt'"                     → "prog"
  let expanded = expandExecArgs(exec)
  if not expanded.valid:
    return ""
  var toks = expanded.args
  if toks.len == 0:
    return ""

  var idx = 0

  ## env VAR=... wrapper
  if toks[0] == "env":
    idx = 1
    while idx < toks.len and isEnvAssign(toks[idx]):
      inc idx
    if idx >= toks.len:
      return "env"

  ## sh|bash|zsh -c "…"
  if idx < toks.len and (toks[idx] in ["sh", "bash", "zsh"]) and idx+2 <= toks.len:
    var j = idx + 1
    while j < toks.len and toks[j] != "-c":
      inc j
    if j < toks.len and j+1 < toks.len:
      return getBaseExec(toks[j+1])

  ## flatpak/snap run <app-id>
  if idx+2 < toks.len and toks[idx] == "flatpak" and toks[idx+1] == "run":
    return toks[idx+2].extractFilename()
  if idx+2 < toks.len and toks[idx] == "snap" and toks[idx+1] == "run":
    return toks[idx+2].extractFilename()

  ## sudo/pkexec wrappers
  if idx < toks.len and (toks[idx] == "sudo" or toks[idx] == "pkexec"):
    inc idx
    if idx >= toks.len:
      return "sudo"
    return toks[idx].extractFilename()

  ## default: first non-wrapper token’s basename
  toks[idx].extractFilename()

# ── Locale helpers ──────────────────────────────────────────────────────

proc localeChain(): seq[string] =
  ## Build locale preferences from the active message locale.
  let envs = [getEnv("LC_ALL"), getEnv("LC_MESSAGES"), getEnv("LANG")]
  var base = ""
  for e in envs:
    if e.len > 0:
      base = e
      break
  if base.len > 0:
    var locale = base
    let dot = locale.find('.')
    if dot >= 0:
      let modifierPos = locale.find('@', dot)
      if modifierPos >= 0:
        locale = locale[0 ..< dot] & locale[modifierPos .. ^1]
      else:
        locale = locale[0 ..< dot]
    if locale == "C" or locale == "POSIX":
      return
    let at = locale.find('@')
    let modifier = if at >= 0: locale[at + 1 .. ^1] else: ""
    let core = if at >= 0: locale[0 ..< at] else: locale
    let us = core.find('_')
    let language = if us >= 0: core[0 ..< us] else: core
    if core.len > 0:
      if modifier.len > 0:
        result.add core & "@" & modifier
      result.add core
    if us >= 0:
      if modifier.len > 0:
        result.add language & "@" & modifier
      result.add language

proc getBestValue*(entries: Table[string, string], baseKey: string): string =
  ## Return the most specific value for *baseKey* following .desktop rules.
  ## Order: locale preferences, then the unlocalized fallback.
  let prefs = localeChain()
  for loc in prefs:
    let k = baseKey & "[" & loc & "]"
    if entries.hasKey(k):
      return entries[k]
  if entries.hasKey(baseKey):
    return entries[baseKey]
  ""

proc splitDesktopList(value: string): seq[string] =
  for item in value.split(';'):
    let cleaned = item.strip()
    if cleaned.len > 0:
      result.add cleaned

# ── .desktop parser ─────────────────────────────────────────────────────

proc parseDesktopFile*(path: string): Option[DesktopApp] =
  ## Parse *path* and return `some(DesktopApp)` if launchable; otherwise `none`.
  ## Criteria:
  ##   • has Name & Exec
  ##   • NoDisplay=false
  ##   • Terminal=false
  let fs = newFileStream(path, fmRead)
  if fs.isNil:
    return none(DesktopApp)
  defer: fs.close()

  var currentSection = ""
  var kv = initTable[string, string]()
  var actionSections = initTable[string, Table[string, string]]()

  for raw in fs.lines:
    let line = raw.strip()
    if line.len == 0 or line.startsWith('#'):
      continue
    if line.startsWith('[') and line.endsWith(']'):
      currentSection = line[1 ..< line.len - 1].strip()
      continue
    let eq = line.find('=')
    if eq <= 0:
      continue
    let key = line[0 ..< eq].strip()
    if key.len == 0:
      continue
    let value =
      if eq + 1 < line.len: line[eq + 1 .. ^1].strip()
      else: ""
    if currentSection == "Desktop Entry":
      kv[key] = value
    elif currentSection.startsWith("Desktop Action "):
      let actionId = currentSection["Desktop Action ".len .. ^1].strip()
      if actionId.len > 0:
        if not actionSections.hasKey(actionId):
          actionSections[actionId] = initTable[string, string]()
        actionSections[actionId][key] = value

  let name = getBestValue(kv, "Name")
  let exec = kv.getOrDefault("Exec", "")
  let icon = kv.getOrDefault("Icon", "")
  let workingDir = kv.getOrDefault("Path", "")
  let entryType = kv.getOrDefault("Type", "Application")
  let noDisplay = kv.getOrDefault("NoDisplay", "false").toLowerAscii() == "true"
  let hidden = kv.getOrDefault("Hidden", "false").toLowerAscii() == "true"
  let terminalApp = kv.getOrDefault("Terminal", "false").toLowerAscii() == "true"
  let execExpansion = expandExecArgs(exec, name, icon, path)

  let tryExec = kv.getOrDefault("TryExec", "")
  var tryExecMissing = false
  if tryExec.len > 0:
    let absPath = findExe(tryExec)
    if absPath.len == 0:
      tryExecMissing = true

  let launchable =
    entryType == "Application" and name.len > 0 and exec.len > 0 and
    execExpansion.valid and not noDisplay and not hidden and not terminalApp and
    not tryExecMissing

  if launchable:
    var desktopActions: seq[DesktopEntryAction] = @[]
    let actionIds = splitDesktopList(kv.getOrDefault("Actions", ""))
    for actionId in actionIds:
      if not actionSections.hasKey(actionId):
        continue
      let section = actionSections[actionId]
      let actionName = getBestValue(section, "Name")
      let actionExec = section.getOrDefault("Exec", "")
      if actionName.len == 0 or actionExec.len == 0:
        continue
      let actionIcon = section.getOrDefault("Icon", "")
      let actionExpansion = expandExecArgs(actionExec, actionName, actionIcon, path)
      let actionNoDisplay = section.getOrDefault("NoDisplay", "false").toLowerAscii() == "true"
      if actionNoDisplay or not actionExpansion.valid:
        continue
      desktopActions.add DesktopEntryAction(
        id: actionId,
        name: actionName,
        nameLower: actionName.toLowerAscii(),
        exec: actionExec,
        icon: actionIcon,
        hasIcon: actionIcon.len > 0
      )

    some(DesktopApp(
      name: name,
      nameLower: name.toLowerAscii(),
      exec: exec,
      desktopFile: path,
      workingDir: workingDir,
      icon: icon,
      hasIcon: icon.len > 0,
      desktopActions: desktopActions
    ))
  else:
    none(DesktopApp)
