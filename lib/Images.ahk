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

; Local channel-tolerance color check, kept private to this file rather
; than reusing Colors.ahk's ColorClose, so Images.ahk stays dependency-free
; (see file header).
ColorWithinTolerance(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
    return Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol
}

; Checks whether the four rim points (top/bottom/left/right, each
; `ringRadius` px from (cx,cy)) all match `markerColor` within `tolerance`.
RingMarkerMatchesAt(cx, cy, ringRadius, markerColor, tolerance) {
    points := [[cx, cy - ringRadius], [cx, cy + ringRadius], [cx - ringRadius, cy], [cx + ringRadius, cy]]
    for p in points {
        if (!ColorWithinTolerance(PixelGetColor(p[1], p[2], "RGB"), markerColor, tolerance))
            return false
    }
    return true
}

; A single PixelSearch hit on `markerColor` could be any one of a real
; ring's four rim points (top/bottom/left/right), so this tries all four
; hypotheses for where the ring's center would be and checks whether the
; OTHER three expected rim points also match. Returns true and writes the
; center into &centerX/&centerY on the first hypothesis that fully agrees.
RingMarkerCenterFromCandidate(fx, fy, ringRadius, markerColor, tolerance, &centerX, &centerY) {
    hyp := [[fx, fy + ringRadius], [fx, fy - ringRadius], [fx + ringRadius, fy], [fx - ringRadius, fy]]
    for h in hyp {
        if (RingMarkerMatchesAt(h[1], h[2], ringRadius, markerColor, tolerance)) {
            centerX := h[1]
            centerY := h[2]
            return true
        }
    }
    return false
}

; Searches (x1,y1)-(x2,y2) for a circle's rim, identified not by a full
; image match but by four small marker points (2x2px in practice, but the
; exact size doesn't matter here - only their COLOR does) at the top-mid,
; bottom-mid, left-mid, and right-mid positions of a `ringRadius`-px circle.
; This exists for graphics where the INTERIOR isn't reliably matchable (e.g.
; a mining spot's animated depletion-timer overlay covers the disc's middle
; but not its rim) - by only ever checking the rim, whatever happens inside
; is irrelevant. Returns true and writes the circle's center into
; &centerX/&centerY on a match, false otherwise.
;
; PixelSearch only ever returns the FIRST matching pixel in scan order
; (top-to-bottom, left-to-right), and a single matching pixel elsewhere on
; screen that ISN'T really one of a ring's four points (a false hit) is
; expected sometimes - so on a hit that doesn't verify, this resumes
; searching exactly where that hit left off (the rest of its row, then
; every full row below) rather than re-scanning from the top or giving up.
FindRingMarkerCenter(x1, y1, x2, y2, ringRadius, markerColor, tolerance, &centerX, &centerY) {
    curY1 := y1
    curX1 := x1
    rowOnly := false   ; true while resuming mid-row after a false hit
    loop {
        if (rowOnly)
            found := PixelSearch(&fx, &fy, curX1, curY1, x2, curY1, markerColor, tolerance)
        else
            found := PixelSearch(&fx, &fy, x1, curY1, x2, y2, markerColor, tolerance)

        if (!found) {
            if (rowOnly) {
                ; Nothing left in this row - fall through to full rows below.
                rowOnly := false
                curY1 += 1
                if (curY1 > y2)
                    return false
                continue
            }
            return false
        }

        if (RingMarkerCenterFromCandidate(fx, fy, ringRadius, markerColor, tolerance, &centerX, &centerY))
            return true

        ; False hit - resume right after it: same row first, then below.
        curX1 := fx + 1
        curY1 := fy
        rowOnly := true
        if (curX1 > x2) {
            rowOnly := false
            curY1 := fy + 1
            if (curY1 > y2)
                return false
        }
    }
}
