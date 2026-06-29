; ============================================================
; Images.ahk - v3 REDESIGNED
;
; ImageSearch-based detection - parallel to Colors.ahk's pixel-color
; layer, for graphical icons that don't render as one reliable solid
; color (fishing spot ripple, bank deposit button, etc).
;
; v3 changes: wait functions take ctx (first param) instead of
; optional runningVarGetter closure. confirmTicks defaults to 3.
;
; Depends on: Context.ahk (CtxIsRunning)
; ============================================================

#Requires AutoHotkey v2.0

#Include Context.ahk

; Searches (x1,y1)-(x2,y2) for imageFile and writes the CENTER of the match
; into &centerX/&centerY (ImageSearch itself only gives the upper-left corner).
; imgW/imgH must match the actual pixel size of imageFile - AHK has no built-in
; way to query image dimensions, so they're passed explicitly.
; Returns true on a match, false (leaving centerX/centerY untouched) otherwise.
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

; Polls IsImagePresent until it reads false (gone) for `confirmTicks` consecutive
; polls, or gives up after timeoutMs. Returns true once confirmed gone, false on timeout.
;
; v3: ctx is required (first param), confirmTicks defaults to 3.
WaitUntilImageGone(ctx, x1, y1, x2, y2, imageFile, timeoutMs, confirmTicks := 3, options := "", pollMs := 200) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!CtxIsRunning(ctx))
            return false
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

; Polls FindImageCenter until it finds a match, writing the result into
; &centerX/&centerY, or gives up after timeoutMs. Returns true on a match,
; false (leaving centerX/centerY untouched) on timeout.
;
; v3: ctx is required (first param).
WaitForImageCenter(ctx, x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, options := "", pollMs := 200) {
    deadline := A_TickCount + timeoutMs
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (FindImageCenter(x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, options))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; Same as WaitForImageCenter, but the search region is derived from a known UI
; element's position (a {x, y, w, h} map) padded by `margin` pixels, instead of
; a wide-area search. Useful for confirming a fixed-position UI element (button,
; icon) has appeared - e.g. waiting for the bank's Deposit All button - instead
; of guessing how long that takes.
;
; v3: ctx is required (first param).
WaitForImageNearButton(ctx, button, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, margin := 20, options := "", pollMs := 200) {
    x1 := button["x"] - button["w"] // 2 - margin
    y1 := button["y"] - button["h"] // 2 - margin
    x2 := button["x"] + button["w"] // 2 + margin
    y2 := button["y"] + button["h"] // 2 + margin
    return WaitForImageCenter(ctx, x1, y1, x2, y2, imageFile, imgW, imgH, &centerX, &centerY, timeoutMs, options, pollMs)
}

; Tries each image in `images` (in order) against the same region/size/options,
; returning the first match's center plus which image matched (via &matchedImage).
; For a state represented by multiple reference images - e.g. a semi-transparent
; overlay whose rendered shade drifts - this lets a caller search for "any of these"
; as one logical match instead of repeating FindImageCenter calls inline.
FindAnyImageCenter(x1, y1, x2, y2, images, imgW, imgH, &centerX, &centerY, &matchedImage, options := "") {
    for img in images {
        if (FindImageCenter(x1, y1, x2, y2, img, imgW, imgH, &centerX, &centerY, options)) {
            matchedImage := img
            return true
        }
    }
    return false
}
