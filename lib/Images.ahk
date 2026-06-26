; ============================================================
;  Images.ahk
;  ImageSearch-based detection - parallel to Colors.ahk's pixel-
;  color layer, for graphical icons that don't render as one
;  reliable solid color (a fishing spot's animated ripple icon,
;  a highlighted bank marker icon, etc). No dependencies on any
;  other lib file.
; ============================================================

; Searches (x1,y1)-(x2,y2) for imageFile and writes the CENTER of
; the match into &centerX/&centerY (ImageSearch itself only gives
; you the upper-left corner, but the center is almost always what
; you actually want to click). imgW/imgH must match the actual
; pixel size of imageFile - AHK has no built-in way to query an
; arbitrary image file's dimensions, so they're passed in
; explicitly; keep them in sync if you swap in a differently-sized
; image. `options` is passed straight through to ImageSearch, e.g.
; "*Trans0x00FF00 *20" to ignore a solid background color with
; some shade tolerance. Returns true on a match, false (leaving
; centerX/centerY untouched) otherwise.
FindImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, options := "") {
    spec := options != "" ? options " " imageFile : imageFile
    if (!ImageSearch(&fx, &fy, x1, y1, x2, y2, spec))
        return false
    centerX := fx + imgW // 2
    centerY := fy + imgH // 2
    return true
}

; Plain presence check when you don't need the position back.
IsImagePresent(x1, y1, x2, y2, imageFile, options := "") {
    spec := options != "" ? options " " imageFile : imageFile
    return ImageSearch(&fx, &fy, x1, y1, x2, y2, spec) ? true : false
}

; Polls IsImagePresent(region) until it reads false (gone) for
; `confirmTicks` consecutive polls in a row, or gives up after
; timeoutMs. Returns true once confirmed gone, false on timeout.
; Same confirm-ticks debounce as Colors.ahk's WaitUntilNotOccupied /
; WaitForPixelColorChange, for the same reason - a single missed
; frame (e.g. a click animation briefly covering the icon)
; shouldn't be mistaken for "it's really gone".
WaitUntilImageGone(x1, y1, x2, y2, imageFile, timeoutMs, confirmTicks := 1, options := "", pollMs := 200) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!IsImagePresent(x1, y1, x2, y2, imageFile, options)) {
            streak += 1
            if (streak >= confirmTicks)
                return true
        } else {
            streak := 0
        }
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; The complement to WaitUntilImageGone: polls FindImageCenter
; (region) until it finds a match, writing the result into
; &centerX/&centerY, or gives up after timeoutMs. Returns true on a
; match, false (leaving centerX/centerY untouched) on timeout.
WaitForImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, options := "", pollMs := 200) {
    deadline := A_TickCount + timeoutMs
    loop {
        if (FindImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, options))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; Same as WaitForImageCenter, but the search region is derived from
; a known UI element's approximate position - a {x, y, w, h} map
; like the ones Grid.ahk returns (e.g. GetDepositAllButton()) -
; padded by `margin` pixels in every direction, rather than a wide
; area search. Useful for confirming a fixed-position UI element
; (a button, an icon) has actually appeared - e.g. waiting for the
; bank window to finish opening by waiting for its Deposit All
; button to render - instead of guessing how long that takes with a
; flat sleep.
WaitForImageNearButton(button, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, margin := 20, options := "", pollMs := 200) {
    x1 := button["x"] - button["w"] // 2 - margin
    y1 := button["y"] - button["h"] // 2 - margin
    x2 := button["x"] + button["w"] // 2 + margin
    y2 := button["y"] + button["h"] // 2 + margin
    return WaitForImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, options, pollMs)
}

; Tries each image in `images` (in order) against the same region/size/options,
; returning the first match's center plus which image matched (via
; &matchedImage). For a state that's represented by more than one reference
; image - e.g. a semi-transparent overlay icon photographed against two
; different backgrounds, so neither single image's tolerance alone safely
; covers the other - this lets a caller search for "any of these" as one
; logical match instead of repeating FindImageCenter calls inline.
FindAnyImageCenter(x1, y1, x2, y2, images, imgW, imgH, &centerX, &centerY, &matchedImage, options := "") {
    for img in images {
        if (FindImageCenter(x1, y1, x2, y2, img, imgW, imgH, &centerX, &centerY, options)) {
            matchedImage := img
            return true
        }
    }
    return false
}
