; ============================================================
; v7 Lib\Find.ahk - detection primitives
;
; Colors are ALWAYS an array at script level (standard #1):
; FindAnyFilledBlock/IsAnyColorAt are the list-order multi-color
; primitives; AcquireClosestInBox breaks ties by proximity to a
; reference point; FindFilledBlock/IsColorAt are the one-color engine
; underneath, not called from script config directly.
;
; No delays here - detection only (delays are an action concept).
; ============================================================

; ---------- fast native block search ----------

; Builds (and caches) the solid-color bitmap ImageSearch matches
; against. One native search for a full solid block: decoys/specks cost
; nothing, whole-screen runs at a constant ~100-200ms (v6-confirmed;
; the old per-candidate verify loop cost ~3s with 42 decoys on screen).
SolidBlockBitmap(color, w, h) {
    static cache := Map()
    key := color "_" w "x" h
    if (cache.Has(key))
        return cache[key]

    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    memDC := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdc, "int", w, "int", h, "ptr")
    oldBmp := DllCall("SelectObject", "ptr", memDC, "ptr", hbm, "ptr")

    ; GDI COLORREF is 0x00BBGGRR - swap R and B from the 0xRRGGBB value
    bgr := ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
    brush := DllCall("CreateSolidBrush", "uint", bgr, "ptr")
    rect := Buffer(16, 0)
    NumPut("int", 0, "int", 0, "int", w, "int", h, rect)
    DllCall("FillRect", "ptr", memDC, "ptr", rect, "ptr", brush)

    DllCall("DeleteObject", "ptr", brush)
    DllCall("SelectObject", "ptr", memDC, "ptr", oldBmp, "ptr")
    DllCall("DeleteDC", "ptr", memDC)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)

    cache[key] := hbm
    return hbm
}

; True if a solid `color` block of reqW x reqH (scaled by verifyPercent,
; 100 = strict) exists in the region; &cx/&cy get the match center.
FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy, verifyPercent := 100) {
    t0 := A_TickCount
    bmpW := Max(1, reqW * verifyPercent // 100)
    bmpH := Max(1, reqH * verifyPercent // 100)
    hbm := SolidBlockBitmap(color, bmpW, bmpH)

    if (!ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" tol " HBITMAP:*" hbm)) {
        LogLine("FindFilledBlock: not found (" bmpW "x" bmpH " " HexColor(color) " tol=" tol ", " (A_TickCount - t0) " ms)")
        return false
    }
    cx := fx + bmpW // 2
    cy := fy + bmpH // 2
    LogLine("FindFilledBlock: found at " cx "," cy " (" bmpW "x" bmpH " " HexColor(color) " tol=" tol ", " (A_TickCount - t0) " ms)")
    return true
}

; ---------- color helpers ----------

HexColor(c) {
    return Format("0x{:06X}", c)
}

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
}

; ---------- region math ----------

; [x1,y1,x2,y2] box around a corner-measured area, padded by marginPx
; (default 0 per standard #18 - raise only after live drift shows up).
RegionAround(cornerX, cornerY, w, h, marginPx := 0) {
    x1 := Max(0, cornerX - marginPx)
    y1 := Max(0, cornerY - marginPx)
    return [x1, y1, cornerX + w + marginPx, cornerY + h + marginPx]
}

; Whole physical screen as [x1,y1,x2,y2].
ScreenRegion() {
    return [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
}

; GameZoneRegion() split into 4 equal rectangles around CHAR_X/CHAR_Y
; (the fixed player-center calibration, NOT a recomputed geometric
; midpoint - guarantees the split always passes through the character's
; own point even if GAME_ZONE_* is ever re-measured asymmetrically;
; currently the two happen to coincide exactly: (0+2499)//2,(45+1380)//2
; = 1249,712 = CHAR_X,CHAR_Y).
GameZoneQuadrant(which) {
    zone := GameZoneRegion()
    switch which {
        case "top-left":
            return [zone[1], zone[2], CHAR_X, CHAR_Y]
        case "top-right":
            return [CHAR_X, zone[2], zone[3], CHAR_Y]
        case "bottom-left":
            return [zone[1], CHAR_Y, CHAR_X, zone[4]]
        case "bottom-right":
            return [CHAR_X, CHAR_Y, zone[3], zone[4]]
        default:
            throw ValueError("GameZoneQuadrant: unknown quadrant '" which "'")
    }
}

; One-flag region builder (standard #22): mode "full" = GameZoneRegion(),
; "area" = rough box bigger than the target, "fixed" = exact box the
; target's own size, "quadrant" = one quarter of the game zone (opts.quadrant:
; "top-left" | "top-right" | "bottom-left" | "bottom-right", see
; GameZoneQuadrant). Caller pattern - ONE object literal per mode,
; alternates commented out (never separate conditionally-read globals;
; AHK's unassigned-variable check is whole-file, see standard #22):
;   MARKER_ZONE := {mode: "full"}
;   ; MARKER_ZONE := {mode: "area", x: .., y: .., w: .., h: .., marginPx: 0}
;   ; MARKER_ZONE := {mode: "fixed", x: .., y: .., w: .., h: .., marginPx: 0}
;   ; MARKER_ZONE := {mode: "quadrant", quadrant: "top-right"}
SearchZone(opts) {
    if (opts.mode = "full")
        return GameZoneRegion()
    if (opts.mode = "quadrant")
        return GameZoneQuadrant(opts.quadrant)
    return RegionAround(opts.x, opts.y, opts.w, opts.h, Opt(opts, "marginPx", 0))
}

; ---------- multi-color search ----------

; Closest match to refX/refY across ALL colors (equal priority, squared
; distance) - the per-stage core of expanding-ring acquire (M4).
AcquireClosestInBox(x1, y1, x2, y2, colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor) {
    found := false
    bestDist := 0
    for color in colors {
        if (FindFilledBlock(x1, y1, x2, y2, color, tol, blockW, blockH, &cx, &cy, verifyPercent)) {
            dist := (cx - refX) ** 2 + (cy - refY) ** 2
            if (!found || dist < bestDist) {
                found := true
                bestDist := dist
                tx := cx, ty := cy, foundColor := color
            }
        }
    }
    return found
}

; First match in list order (no reference point, no proximity concept).
FindAnyFilledBlock(x1, y1, x2, y2, colors, tol, blockW, blockH, &cx, &cy, &foundColor, verifyPercent := 100) {
    for color in colors {
        if (FindFilledBlock(x1, y1, x2, y2, color, tol, blockW, blockH, &mx, &my, verifyPercent)) {
            cx := mx, cy := my, foundColor := color
            return true
        }
    }
    return false
}

; Single-pixel "any of these colors" check.
IsAnyColorAt(x, y, colors, tol, &foundColor) {
    for color in colors {
        if (IsColorAt(x, y, color, tol)) {
            foundColor := color
            return true
        }
    }
    return false
}

; ---------- fixed screen calibration (this setup, measured once) ----------

; Game viewport (excludes chat/minimap chrome/taskbar) - clamp in-game
; target searches to this. Bank/inventory UI coords are separate,
; measured directly on screen.
GAME_ZONE_X1 := 0
GAME_ZONE_Y1 := 45
GAME_ZONE_X2 := 2499
GAME_ZONE_Y2 := 1380

GameZoneRegion() {
    return [GAME_ZONE_X1, GAME_ZONE_Y1, GAME_ZONE_X2, GAME_ZONE_Y2]
}

; Character's on-screen center (fixed camera/zoom) - the reference point
; ring acquires expand from.
CHAR_X := 1249
CHAR_Y := 712

; Default expanding-ring paddings (each ring extends this far from
; CHAR_X/Y on every side), small then large, before region-wide fallback.
ACQUIRE_PADDING_SMALL := 64
ACQUIRE_PADDING_LARGE := 128

; Deposit-all PNG buttons - genuinely fixed positions, so they live
; here. ONLY fixed PNG button positions belong in Lib; bank/deposit-box
; color MARKERS vary per location and stay per-script config (standard
; #17). TWO separate real buttons/captures coexist (2026-07-23) -
; BANK_DEPOSIT_IMAGE_* (deposit-bank.png, micro 24) and
; DEPOSIT_BOX_IMAGE_* (deposit-box.png, woodcutting) - pick whichever
; matches the bank interface a given bot actually sees.
BANK_DEPOSIT_IMAGE_X := 1327
BANK_DEPOSIT_IMAGE_Y := 963
BANK_DEPOSIT_IMAGE_W := 72
BANK_DEPOSIT_IMAGE_H := 72

DEPOSIT_BOX_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-box.png"
DEPOSIT_BOX_IMAGE_X := 721
DEPOSIT_BOX_IMAGE_Y := 765
DEPOSIT_BOX_IMAGE_W := 80
DEPOSIT_BOX_IMAGE_H := 72

; Regions derived purely from the fixed constants above are themselves
; fixed - precomputed once here (marginPx 0, standard #17) so no bot
; has to rebuild the identical SearchZone/RegionAround call.
BANK_DEPOSIT_IMAGE_REGION := RegionAround(BANK_DEPOSIT_IMAGE_X, BANK_DEPOSIT_IMAGE_Y, BANK_DEPOSIT_IMAGE_W, BANK_DEPOSIT_IMAGE_H, 0)
DEPOSIT_BOX_IMAGE_REGION := RegionAround(DEPOSIT_BOX_IMAGE_X, DEPOSIT_BOX_IMAGE_Y, DEPOSIT_BOX_IMAGE_W, DEPOSIT_BOX_IMAGE_H, 0)

; ---------- state-indicator watcher ----------

; Watches point (x,y) for any of `colors` to reach targetState
; ("present"/"absent"). &alreadyTrue reports whether the state already
; held at the very first sample (vs a transition witnessed during the
; wait) - a caller watching for "enemy died" needs that distinction.
WatchIndicator(x, y, colors, tol, targetState, timeoutMs, pollMs?, &alreadyTrue := false) {
    if (!IsSet(pollMs))
        pollMs := POLL_MS_DEFAULT

    checkState() {
        return IsAnyColorAt(x, y, colors, tol, &fc)
    }

    startPresent := checkState()
    startMatches := (targetState = "present") ? startPresent : !startPresent
    alreadyTrue := startMatches
    if (startMatches) {
        LogLine("WatchIndicator: already " targetState " at start (" x "," y ")")
        return true
    }

    Matches() {
        present := checkState()
        return (targetState = "present") ? present : !present
    }

    return WaitUntil(Matches, timeoutMs, pollMs)
}

; ---------- waypoint arrival (exact-position block check, M6) ----------

; Confirms a block whose CENTER lands within posTolPx of the expected
; point - "did we arrive", not "is this color anywhere". Search box =
; block + marginPx (default 0, standard #18; raise marginPx AND posTolPx
; together if arrival drift shows up live). &fx/&fy/&foundColor only
; meaningful on true.
BlockAtPoint(expectedCx, expectedCy, colors, tol, blockW, blockH, posTolPx, &fx, &fy, &foundColor, marginPx := 0, verifyPercent := 100) {
    box := RegionAround(expectedCx - blockW // 2, expectedCy - blockH // 2, blockW, blockH, marginPx)
    found := FindAnyFilledBlock(box[1], box[2], box[3], box[4], colors, tol, blockW, blockH, &mx, &my, &fc, verifyPercent)
    if (!found)
        return false

    if (Abs(mx - expectedCx) > posTolPx || Abs(my - expectedCy) > posTolPx)
        return false

    fx := mx, fy := my, foundColor := fc
    return true
}

; ---------- image search (M2) ----------

; "*tol *TransColor path" pattern string; transColor "" omits *Trans.
ImagePattern(path, tol, transColor := "") {
    pattern := "*" tol
    if (transColor != "")
        pattern .= " *Trans" transColor
    return pattern " " path
}

; Searches for the image at path (w/h = its real pixel size, used for
; center math); &cx/&cy get the match center. Single image only - a
; different asset has its own w/h, so no path array (unlike colors).
FindImage(x1, y1, x2, y2, path, w, h, tol, transColor, &cx, &cy) {
    t0 := A_TickCount
    try {
        found := ImageSearch(&fx, &fy, x1, y1, x2, y2, ImagePattern(path, tol, transColor))
    } catch as exc {
        LogLine("FindImage: ERROR " exc.Message)
        return false
    }
    if (!found) {
        LogLine("FindImage: not found (" path ", " (A_TickCount - t0) " ms)")
        return false
    }
    cx := fx + w // 2
    cy := fy + h // 2
    LogLine("FindImage: found at " cx "," cy " (" path ", " (A_TickCount - t0) " ms)")
    return true
}

; Poll wrappers over FindImage. &cx/&cy report the found center
; (WaitForImage only).
WaitForImage(x1, y1, x2, y2, path, w, h, tol, transColor, timeoutMs, pollMs, &cx, &cy) {
    fx := 0, fy := 0
    Visible() {
        found := FindImage(x1, y1, x2, y2, path, w, h, tol, transColor, &mx, &my)
        if (found)
            fx := mx, fy := my
        return found
    }
    result := WaitUntil(Visible, timeoutMs, pollMs)
    cx := fx, cy := fy
    return result
}

WaitForImageGone(x1, y1, x2, y2, path, w, h, tol, transColor, timeoutMs, pollMs) {
    Gone() {
        return !FindImage(x1, y1, x2, y2, path, w, h, tol, transColor, &mx, &my)
    }
    return WaitUntil(Gone, timeoutMs, pollMs)
}

; ---------- watch-box (snapshot + change detection) ----------

; Strided sampling (~targetSamples points regardless of box size; v6
; measured exhaustive at ~6s vs ~350ms strided). Snapshot bundles the
; stride so HasChanged re-samples the exact same points.
TakeSnapshot(x, y, w, h, targetSamples := 50) {
    scale := Sqrt(w * h / targetSamples)
    strideX := Max(1, Round(scale))
    strideY := Max(1, Round(scale))

    colors := []
    yy := 0
    while (yy < h) {
        xx := 0
        while (xx < w) {
            colors.Push(PixelGetColor(x + xx, y + yy))
            xx += strideX
        }
        yy += strideY
    }
    return {colors: colors, w: w, h: h, strideX: strideX, strideY: strideY}
}

; True if any sampled point now differs from the snapshot baseline.
HasChanged(snapshot, x, y, tol) {
    idx := 1
    yy := 0
    while (yy < snapshot.h) {
        xx := 0
        while (xx < snapshot.w) {
            current := PixelGetColor(x + xx, y + yy)
            if (!ColorClose(current, snapshot.colors[idx], tol))
                return true
            idx += 1
            xx += snapshot.strideX
        }
        yy += snapshot.strideY
    }
    return false
}
