## apps_cache.nim — application discovery and cache management.

import std/[os, json, times, options, strutils, algorithm, hashes, sets, syncio]
import ./[state, parser, paths]

const CacheFormatVersion = 10

## Derive the desktop-file ID relative to its applications directory.
proc desktopFileId(baseDir, path: string): string =
  let relative = relativePath(path, baseDir)
  relative.replace(DirSep, '-').replace(AltSep, '-')

## Capture locale and executable search inputs used by desktop parsing.
proc parsingEnvironmentSignature(): string =
  [getEnv("LC_ALL"), getEnv("LC_MESSAGES"), getEnv("LANG"), getEnv("PATH")].join("\x1f")

## Describe TryExec availability for one desktop file.
proc tryExecState(path: string): string =
  var inDesktopEntry = false
  try:
    for raw in lines(path):
      let line = raw.strip()
      if line.startsWith('[') and line.endsWith(']'):
        inDesktopEntry = line == "[Desktop Entry]"
      elif inDesktopEntry and line.startsWith("TryExec="):
        let value = line["TryExec=".len..^1].strip()
        let resolved = findExe(value)
        if resolved.len == 0:
          return value & ":missing"
        let modified = getLastModificationTime(resolved).toUnix()
        return value & ":" & resolved & ":" & $modified
  except CatchableError:
    discard
  ""

proc desktopDirFingerprint(dir: string): tuple[newest: int64; signature: string] =
  ## Build a lightweight fingerprint for *.desktop files under *dir*.
  ## Includes newest mtime, file count, summed mtimes, and summed file sizes.
  if not dirExists(dir):
    return (0'i64, "0:0:0:0")
  var newest = 0'i64
  var count = 0'i64
  var sumMtime = 0'i64
  var sumSize = 0'i64
  var paths: seq[string] = @[]
  var tryExecStates: seq[string] = @[]
  for entry in walkDirDepth(dir, maxDepth = 3, yieldFilter = {pcFile}):
    if entry.endsWith(".desktop"):
      paths.add(entry)
      let state = tryExecState(entry)
      if state.len > 0:
        tryExecStates.add(state)
      try:
        let info = getFileInfo(entry)
        let m = times.toUnix(info.lastWriteTime)
        if m > newest: newest = m
        inc count
        sumMtime += m
        sumSize += info.size.int64
      except CatchableError:
        discard
  paths.sort()
  tryExecStates.sort()
  let pathHash = hash(paths)
  let tryExecHash = hash(tryExecStates)
  (newest, $count & ":" & $newest & ":" & $sumMtime & ":" & $sumSize &
      ":" & $pathHash & ":" & $tryExecHash)

proc loadApplications*() =
  ## Scan .desktop files with caching to ~/.cache/nimlaunch/apps.json.
  let appDirs = applicationDirs()
  let environmentSignature = parsingEnvironmentSignature()
  var dirMtimes: seq[int64] = @[]
  var dirSignatures: seq[string] = @[]
  for dir in appDirs:
    let fp = desktopDirFingerprint(dir)
    dirMtimes.add fp.newest
    dirSignatures.add fp.signature

  let cacheBase = cacheDir()
  let cacheFile = cacheBase / "apps.json"

  if fileExists(cacheFile):
    try:
      let node = parseJson(readFile(cacheFile))
      if node.kind == JObject and node.hasKey("formatVersion"):
        let c = to(node, CacheData)
        if c.formatVersion == CacheFormatVersion and
           c.environmentSignature == environmentSignature and
           c.appDirs == appDirs and c.dirMtimes == dirMtimes and
           c.dirSignatures == dirSignatures:
          ctx.allApps = c.apps
          ctx.filteredApps = @[]
          ctx.matchSpans = @[]
          return
      else:
        if ctx.verboseMode:
          stderr.writeLine "Cache invalid — rescanning …"
    except IOError, ValueError, OSError:
        let e = getCurrentException()
        if ctx.verboseMode:
          stderr.writeLine "Cache miss — rescanning (" & $e.name & ": " & e.msg & ")"

  var claimedIds = initHashSet[string]()
  var apps: seq[DesktopApp] = @[]
  for dir in appDirs:
    if not dirExists(dir): continue
    for path in walkDirDepth(dir, maxDepth = 3, yieldFilter = {pcFile}):
      if not path.endsWith(".desktop"): continue
      let desktopId = desktopFileId(dir, path)
      if desktopId in claimedIds:
        continue
      claimedIds.incl(desktopId)
      let opt = parseDesktopFile(path)
      if isSome(opt):
        var app = get(opt)
        app.desktopId = desktopId
        apps.add app

  ctx.allApps = apps
  ctx.allApps.sort(proc(a, b: DesktopApp): int = cmpIgnoreCase(a.name, b.name))
  ctx.filteredApps = @[]
  ctx.matchSpans = @[]
  try:
    createDir(cacheBase)
    writeFile(cacheFile, $ %CacheData(formatVersion: CacheFormatVersion,
                                      environmentSignature: environmentSignature,
                                      appDirs: appDirs,
                                      dirMtimes: dirMtimes,
                                      dirSignatures: dirSignatures,
                                      apps: ctx.allApps))
  except IOError, OSError:
    let e = getCurrentException()
    if ctx.verboseMode:
      stderr.writeLine "Warning: cache not saved (" & $e.name & ": " & e.msg & ")"
