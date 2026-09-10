## Pure layout calculations shared by the SDL renderer and regression tests.

type
  LayoutInput* = object
    canvasHeight*: int
    requestedRows*: int
    configuredLineHeight*: int
    fontLineHeight*: int
    overlayLineHeight*: int
    iconMinimum*: int
    textPadding*: int
    outerMargin*: int
    rowGap*: int
    commandExtraHeight*: int
    commandBottomGap*: int
    vimMode*: bool
    showIcons*: bool

  LayoutResult* = object
    rowHeight*: int
    contentTop*: int
    contentBottom*: int
    visibleRows*: int
    desiredHeight*: int

## Return a row height that contains text, padding, and an optional icon.
proc effectiveRowHeight*(input: LayoutInput): int =
  let textHeight = max(1, input.fontLineHeight) + max(0, input.textPadding)
  let iconHeight = if input.showIcons: max(1, input.iconMinimum) else: 1
  max(max(1, input.configuredLineHeight), max(textHeight, iconHeight))

## Calculate vertical space reserved above and below result rows.
proc layoutChrome(input: LayoutInput; rowHeight: int): tuple[top, bottom: int] =
  let margin = max(0, input.outerMargin)
  let gap = max(0, input.rowGap)
  let overlayHeight = max(1, input.overlayLineHeight)
  if input.vimMode:
    result.top = margin + overlayHeight * 2 + gap
    result.bottom = margin + rowHeight + max(0, input.commandExtraHeight) +
        max(0, input.commandBottomGap)
  else:
    result.top = margin + rowHeight + gap
    result.bottom = margin + overlayHeight + gap

## Derive row bounds, visible capacity, and the ideal canvas height.
proc computeLayout*(input: LayoutInput): LayoutResult =
  result.rowHeight = effectiveRowHeight(input)
  let chrome = layoutChrome(input, result.rowHeight)
  result.contentTop = chrome.top
  result.contentBottom = max(result.contentTop,
      max(1, input.canvasHeight) - chrome.bottom)
  let available = max(0, result.contentBottom - result.contentTop)
  result.visibleRows = min(max(1, input.requestedRows),
      max(1, available div result.rowHeight))
  result.desiredHeight = chrome.top + chrome.bottom +
      max(1, input.requestedRows) * result.rowHeight
