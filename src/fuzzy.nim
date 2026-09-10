## fuzzy.nim — fuzzy matching, typo tolerance, and highlight helpers.

import std/[strutils, times, tables, unicode]
import ./state

proc recentBoost*(key: string): int =
  ## Small score bonus for recently used apps (first is strongest).
  let idx = ctx.recentApps.find(key)
  if idx >= 0: return max(0, 200 - idx * 40)
  0

proc usageBoost*(key: string): int =
  ## Small persistent score layer based on launch frequency and recency.
  let stats = ctx.appUsage.getOrDefault(key)
  if stats.launchCount <= 0 and stats.lastLaunched <= 0:
    return 0
  let frequency = min(stats.launchCount, 20) * 30
  let ageSeconds = max(0'i64, epochTime().int64 - stats.lastLaunched)
  let recency =
    if ageSeconds < 3_600: 320
    elif ageSeconds < 86_400: 220
    elif ageSeconds < 604_800: 120
    elif ageSeconds < 2_592_000: 40
    else: 0
  frequency + recency

proc subseqPositions*(q, t: string): seq[int] =
  ## Return UTF-8 byte offsets for a case-insensitive rune subsequence.
  if q.len == 0: return @[]
  let queryRunes = q.toRunes()
  var queryIndex = 0
  var byteOffset = 0
  for rune in t.runes:
    if queryIndex < queryRunes.len and
        rune.toLower() == queryRunes[queryIndex].toLower():
      result.add byteOffset
      inc queryIndex
      if queryIndex == queryRunes.len:
        return
    byteOffset += rune.size
  result.setLen(0)

proc subseqSpans*(q, t: string): seq[(int, int)] =
  ## Convert rune positions to valid UTF-8 byte spans for highlighting.
  for p in subseqPositions(q, t):
    result.add (p, runeAt(t, p).size)

proc isWordBoundary*(lt: string; idx: int): bool =
  ## Basic token boundary check for nicer scoring.
  if idx <= 0: return true
  var previous = idx - 1
  while previous > 0 and (ord(lt[previous]) and 0xC0) == 0x80:
    dec previous
  let rune = runeAt(lt, previous)
  rune in [Rune(' '), Rune('-'), Rune('_'), Rune('.'), Rune('/')]

proc withinOneEdit(a, b: openArray[Rune]): bool =
  ## Return true when two rune sequences differ by at most one edit.
  let m = a.len; let n = b.len
  if abs(m - n) > 1: return false
  var i = 0; var j = 0; var edits = 0
  while i < m and j < n:
    if a[i] == b[j]: inc i; inc j
    else:
      inc edits; if edits > 1: return false
      if m == n: inc i; inc j
      elif m < n: inc j
      else: inc i
  edits += (m - i) + (n - j)
  edits <= 1

proc withinOneTransposition(a, b: openArray[Rune]): bool =
  ## Return true when rune sequences differ by one adjacent swap.
  if a.len != b.len or a.len < 2: return false
  var k = 0
  while k < a.len and a[k] == b[k]: inc k
  if k >= a.len - 1: return false
  if not (a[k] == b[k+1] and a[k+1] == b[k]): return false
  let tailStart = k + 2
  if tailStart < a.len:
    for i in tailStart ..< a.len:
      if a[i] != b[i]: return false
  return true

proc scoreMatch*(q, lq, t, lt, fullPath, home: string): int =
  ## Heuristic score for matching q against t (higher is better).
  ## Typo-friendly: 1 edit (ins/del/sub) or one adjacent transposition.
  if q.len == 0: return -1_000_000
  let normalizedQuery = unicode.toLower(q)
  let normalizedText = unicode.toLower(t)
  let queryRunes = normalizedQuery.toRunes()
  let textRunes = normalizedText.toRunes()
  let pos = normalizedText.find(normalizedQuery)

  var s = -1_000_000
  if pos >= 0:
    s = 1000
    if pos == 0: s += 200
    if isWordBoundary(normalizedText, pos): s += 80
    s += max(0, 60 - (t.len - q.len))

  if t == q: s += 9000
  elif normalizedText == normalizedQuery: s += 8600
  elif normalizedText.startsWith(normalizedQuery): s += 8200
  elif pos >= 0: s += 7800
  else:
    var typoHit = false

    ## Whole-string typo tolerance (1 edit or adjacent swap).
    if queryRunes.len > 0 and
        (withinOneEdit(queryRunes, textRunes) or
         withinOneTransposition(queryRunes, textRunes)):
      typoHit = true
      s = max(s, 7600)

    ## Substring typo tolerance to catch near-start matches.
    if not typoHit and queryRunes.len > 0:
      let sizes = [max(1, queryRunes.len - 1), queryRunes.len,
          queryRunes.len + 1]
      for L in sizes:
        if L > textRunes.len: continue
        var start = 0
        let maxStart = textRunes.len - L
        while start <= maxStart:
          let candidate = textRunes[start..<start + L]
          if withinOneEdit(queryRunes, candidate) or
              withinOneTransposition(queryRunes, candidate):
            typoHit = true
            var base = 7700
            if start == 0: base = 7950
            s = max(s, base - min(120, start))
            break
          inc start
        if typoHit: break

  if fullPath.startsWith(home & "/"):
    if normalizedText == normalizedQuery: s += 600
    elif normalizedText.startsWith(normalizedQuery): s += 400
  s
