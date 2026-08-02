; ============================================================
; v8 Lib\Find.ahk - detection primitives
;
; Search/detection internals are ported VERBATIM from v7\Lib\Find.ahk
; (proven live) - notably FindFilledBlock's verifyPercent semantics
; (it SCALES THE SEARCHED BITMAP to verifyPercent of the block size,
; it is not an ImageSearch option) and the "*tol HBITMAP:*handle"
; pattern string. Do not "simplify" these - they are the exact
; strings/math confirmed working in v6/v7.
;
; v8 changes vs v7:
; - RegionAround clamps ALL FOUR edges to the screen (v7 clamped
;   only x1/y1) - an unclamped box near a screen edge handed
;   ImageSearch an invalid region.
; - SearchZone has only "full" and "area" modes (v7's "quadrant" and
;   "fixed" dropped per user decision - "fixed" was identical to
;   "area" anyway).
; - NEW unified target-spec dispatch: FindTarget/WaitForTarget/
;   WaitForTargetGone take ONE spec object - {colors,tol,w,h[,
;   verifyPercent]} for a block, {path,tol,transColor,w,h} for an
;   image - the presence of `colors` vs `path` selects the branch.
;   These are also the readiness-indicator primitives the fail-safe
;   engine (Run.ahk) uses for `done` closures.
; - Colors are ALWAYS an array at script level (v7 standard #1);
;   FindFilledBlock/IsColorAt are the one-color engine underneath,
;   not called from script config directly.
; - No delays here - detection only (delays are an action concept).
; ============================================================

; ---------- fast native block search ----------

; Builds (and caches) the solid-color bitmap ImageSearch matches
; against. One native search for a full solid block: decoys/specks
; cost nothing, whole-screen runs at a constant ~100-200ms.
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

; ---------- region math ----------

; [x1,y1,x2,y2] box around a corner-measured area, padded by marginPx,
; clamped to the physical screen on all four edges (v8 fix - v7 only
; clamped x1/y1).
RegionAround(cornerX, cornerY, w, h, marginPx := 0) {
    x1 := Max(0, cornerX - marginPx)
    y1 := Max(0, cornerY - marginPx)
    x2 := Min(A_ScreenWidth - 1, cornerX + w + marginPx)
    y2 := Min(A_ScreenHeight - 1, cornerY + h + marginPx)
    return [x1, y1, x2, y2]
}

; Whole physical screen as [x1,y1,x2,y2].
ScreenRegion() {
    return [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
}

; One-flag region builder: mode "full" = GameZoneRegion(), "area" =
; box around a corner point (RegionAround). Caller pattern - ONE
; object literal per mode, alternates commented out:
;   MARKER_ZONE := {mode: "full"}
;   ; MARKER_ZONE := {mode: "area", x: .., y: .., w: .., h: .., marginPx: 0}
SearchZone(opts) {
    if (opts.mode = "full")
        return GameZoneRegion()
    if (opts.mode = "area")
        return RegionAround(opts.x, opts.y, opts.w, opts.h, Opt(opts, "marginPx", 0))
    throw ValueError("SearchZone: unknown mode '" opts.mode "'")
}

; ---------- multi-color search ----------

; Closest match to refX/refY across ALL colors (equal priority,
; squared distance) - the per-stage core of expanding-ring acquire.
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

; ---------- fixed screen calibration (this setup, measured once) ----------

; Game viewport (excludes chat/minimap chrome/taskbar) - clamp
; in-game target searches to this. Bank/inventory UI coords are
; separate, measured directly on screen.
GAME_ZONE_X1 := 0
GAME_ZONE_Y1 := 45
GAME_ZONE_X2 := 2499
GAME_ZONE_Y2 := 1380

GameZoneRegion() {
    return [GAME_ZONE_X1, GAME_ZONE_Y1, GAME_ZONE_X2, GAME_ZONE_Y2]
}

; Character's on-screen center (fixed camera/zoom) - the reference
; point ring acquires expand from.
CHAR_X := 1249
CHAR_Y := 712

; Deposit-all PNG buttons - genuinely fixed positions, so they live
; here. TWO separate real buttons/captures coexist -
; BANK_DEPOSIT_IMAGE_* (deposit-bank.png) and DEPOSIT_BOX_IMAGE_*
; (deposit-box.png) - pick whichever matches the bank interface a
; given bot actually sees. Paths are Lib constants in v8 (v7 only
; hoisted one of the two - that asymmetry is gone).
BANK_DEPOSIT_IMAGE_PATH := IMAGES_DIR "\deposit-bank.png"
BANK_DEPOSIT_IMAGE_X := 1327
BANK_DEPOSIT_IMAGE_Y := 963
BANK_DEPOSIT_IMAGE_W := 72
BANK_DEPOSIT_IMAGE_H := 72

DEPOSIT_BOX_IMAGE_PATH := IMAGES_DIR "\deposit-box.png"
DEPOSIT_BOX_IMAGE_X := 721
DEPOSIT_BOX_IMAGE_Y := 765
DEPOSIT_BOX_IMAGE_W := 80
DEPOSIT_BOX_IMAGE_H := 72

; Regions derived purely from the fixed constants above are
; themselves fixed - precomputed once here so no bot has to rebuild
; the identical RegionAround call.
BANK_DEPOSIT_IMAGE_REGION := RegionAround(BANK_DEPOSIT_IMAGE_X, BANK_DEPOSIT_IMAGE_Y, BANK_DEPOSIT_IMAGE_W, BANK_DEPOSIT_IMAGE_H, 0)
DEPOSIT_BOX_IMAGE_REGION := RegionAround(DEPOSIT_BOX_IMAGE_X, DEPOSIT_BOX_IMAGE_Y, DEPOSIT_BOX_IMAGE_W, DEPOSIT_BOX_IMAGE_H, 0)

; ---------- image search ----------

; "*tol *TransColor path" pattern string; transColor "" omits *Trans.
; transColor is passed through as-is (e.g. "0x00FF00") - do NOT strip
; the 0x prefix, ImageSearch needs it to parse the value as a color.
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

; ---------- unified target-spec dispatch (v8-only) ----------

; Block spec {colors,tol,w,h[,verifyPercent]} or image spec
; {path,tol,transColor,w,h} - the presence of `colors` vs `path`
; selects the branch. Defaults normalized in one place: tol 5,
; transColor "", verifyPercent 100.
FindTarget(region, spec, &cx, &cy, &foundColor := 0) {
    if (spec.HasOwnProp("colors"))
        return FindAnyFilledBlock(region[1], region[2], region[3], region[4],
            spec.colors, Opt(spec, "tol", 5), spec.w, spec.h, &cx, &cy, &foundColor, Opt(spec, "verifyPercent", 100))
    return FindImage(region[1], region[2], region[3], region[4],
        spec.path, spec.w, spec.h, Opt(spec, "tol", 5), Opt(spec, "transColor", ""), &cx, &cy)
}

WaitForTarget(region, spec, timeoutMs, &cx, &cy, opts := {}) {
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    wanderOpts := Opt(opts, "wander", "")
    fx := 0, fy := 0
    Visible() {
        found := FindTarget(region, spec, &mx, &my, &fc)
        if (found)
            fx := mx, fy := my
        return found
    }
    result := WaitUntil(Visible, timeoutMs, pollMs, wanderOpts)
    cx := fx, cy := fy
    return result
}

WaitForTargetGone(region, spec, timeoutMs, opts := {}) {
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    Gone() {
        return !FindTarget(region, spec, &mx, &my, &fc)
    }
    return WaitUntil(Gone, timeoutMs, pollMs)
}

; ---------- state-indicator watcher ----------

; Watches point (x,y) for any of `colors` to reach targetState
; ("present"/"absent"). &alreadyTrue reports whether the state
; already held at the very first sample (vs a transition witnessed
; during the wait) - a caller watching for "enemy died" needs that
; distinction.
WatchIndicator(x, y, colors, tol, targetState, timeoutMs, pollMs := 0, &alreadyTrue := false) {
    if (pollMs = 0)
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

; ---------- waypoint arrival (exact-position block check) ----------

; Confirms a block whose CENTER lands within posTolPx (per axis) of
; the expected point - "did we arrive", not "is this color anywhere".
; Search box = block + marginPx. &fx/&fy/&foundColor only meaningful
; on true.
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

; ---------- watch-box (snapshot + change detection) ----------

; Strided sampling (~targetSamples points regardless of box size;
; measured: exhaustive ~6s vs strided ~350ms). The snapshot bundles
; its own x/y plus the stride so HasChanged re-samples the exact same
; points (v8 surface change: v7's HasChanged took x/y again as
; params; storing them in the snapshot removes the chance of passing
; a different origin on the re-check).
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
    return {colors: colors, x: x, y: y, w: w, h: h, strideX: strideX, strideY: strideY}
}

; True if any sampled point now differs from the snapshot baseline.
HasChanged(snapshot, tol) {
    idx := 1
    yy := 0
    while (yy < snapshot.h) {
        xx := 0
        while (xx < snapshot.w) {
            current := PixelGetColor(snapshot.x + xx, snapshot.y + yy)
            if (!ColorClose(current, snapshot.colors[idx], tol))
                return true
            idx += 1
            xx += snapshot.strideX
        }
        yy += snapshot.strideY
    }
    return false
}
