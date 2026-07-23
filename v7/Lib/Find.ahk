; ============================================================
; v7 Lib\Find.ahk - detection primitives
;
; Built incrementally, one function (or tightly-coupled group) per
; micro: SolidBlockBitmap/FindFilledBlock/HexColor for micro 03,
; RegionAround for micro 04, AcquireClosestInBox for micro 05,
; ColorClose/IsColorAt/IsAnyColorAt/FindAnyFilledBlock/BlockAtPoint for
; micro 06, ImagePattern/FindImage for micro 07, TakeSnapshot/HasChanged
; for micro 14, WatchIndicator for micro 15, WaitForImage/
; WaitForImageGone for micro 16. Do not add functions here ahead of the
; micro that will exercise them.
;
; STANDARD (2026-07-22): every script-level color config is a COLORS
; ARRAY, always - even a single-color script uses TARGET_COLORS := [c]
; - so adding/removing candidate colors never means restructuring the
; script. FindAnyFilledBlock/IsAnyColorAt are the no-reference-point
; multi-color primitives this implies (list-order first match, since
; there's no proximity concept without a reference point);
; AcquireClosestInBox (micro 05) remains the reference-point,
; proximity-tie-break version for when one exists. FindFilledBlock/
; IsColorAt (single scalar color) stay as the underlying one-color
; engine both loop over - not removed, just no longer called directly
; from script-level config.
;
; SolidBlockBitmap/FindFilledBlock/HexColor ported byte-identical from
; v6 Lib\Find.ahk (confirmed live in v6 micros 01/02/03/05/08/12). The
; "SPEED OVERHAUL" note below is the confirmed-in-v6 justification for
; keeping the synthesized-bitmap approach in v7 rather than a
; pixel-by-pixel scan - see the v7 plan's search-mode design notes.
; ============================================================

; ---------- detection (fast native block search) ----------
;
; The old verify-and-split loop paid a stack of ~7ms pixel-API calls
; per rejected candidate, so whole-screen speed depended on how much of
; the color was elsewhere on screen (measured live: 42 yellow UI specks
; cost ~3s). Replaced with ONE native ImageSearch for a solid reqW x
; reqH block of the color: only a full-size solid block can match,
; decoys/specks cost nothing, and whole-screen search runs at a
; constant ~100-200 ms no matter what else is visible.

; Builds (and caches per color+size) the solid-color in-memory bitmap
; that ImageSearch matches against.
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

; True if a solid block of `color` at least reqW x reqH (scaled by
; verifyPercent) exists in the region; &cx/&cy get the center of the
; matched area. verifyPercent 100 = strict full size; lower it only if
; a real target's soft/anti-aliased edges make the strict match miss.
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

; ---------- region math ----------

; Builds a [x1,y1,x2,y2] search box around a corner-measured marker
; area (cornerX,cornerY,w,h), padded by marginPx and clamped to >=0.
; Moved here from v6's Steps.ahk - region math belongs with search, not
; with the higher-level composites that call it. marginPx is caller-
; configurable (default 40, matching v6's BlockAtPoint slack).
RegionAround(cornerX, cornerY, w, h, marginPx := 40) {
    x1 := Max(0, cornerX - marginPx)
    y1 := Max(0, cornerY - marginPx)
    return [x1, y1, cornerX + w + marginPx, cornerY + h + marginPx]
}

; Single-flag switch (2026-07-23) between the three region shapes every
; script's own config already boils down to (standard #3): "full" (whole
; game viewport, GameZoneRegion()), "area" (a rough box bigger than the
; target - opts.x/y/w/h ARE that area's own box), or "fixed" (an exact
; box the same size as the object itself - opts.x/y are the object's own
; measured corner, opts.w/h its own block size, marginPx should stay 0).
;
; Added because switching a script between these by hand meant deleting/
; re-adding whichever X/Y/W/H constants that mode needs - and a
; RegionAround(...) call left referencing a deleted constant breaks the
; whole script. This collapses that decision into ONE field
; (opts.mode) a script can flip without touching its position constants.
;
; IMPORTANT for callers: do NOT keep separate MARKER_AREA_X/Y/W/H-style
; globals and conditionally copy them into the opts object based on
; opts.mode - AHK v2's "variable never assigned" check is a WHOLE-FILE
; static scan, not a per-branch runtime one, so a global referenced in a
; branch that never executes (e.g. an "area" block while mode is "full")
; still gets flagged as unassigned if its own assignment line is
; commented out. Confirmed live (2026-07-23): exactly this pattern
; warned on MARKER_AREA_X even though the "area" branch was dead code.
;
; Instead, write ONE opts object literal PER MODE inline, right where
; the mode is chosen, and comment out the other modes' lines - e.g.:
;   MARKER_ZONE := {mode: "full"}
;   ; MARKER_ZONE := {mode: "area", x: 693, y: 229, w: 708, h: 636, marginPx: 0}
;   ; MARKER_ZONE := {mode: "fixed", x: 1044, y: 928, w: 15, h: 15, marginPx: 0}
; then pass that single variable straight to SearchZone (SearchZone(MARKER_ZONE)).
; Exactly one assignment to MARKER_ZONE ever exists in the file, so
; there's nothing for the unassigned-variable check to flag, and the
; other modes' x/y/w/h live as object-literal fields (not separate
; globals) so they're never independently "unassigned" either.
;
; opts:
;   mode     - "full" | "area" | "fixed" (required)
;   x/y/w/h  - required for "area"/"fixed", not read at all for "full"
;   marginPx - extra slack around x/y/w/h (default 0 - "fixed" should
;              always leave this at 0, per standard #17/#18)
;
; Returns a [x1,y1,x2,y2] region - drop-in for any composite's `region`/
; `markerRegion`/`depositRegion` opt.
SearchZone(opts) {
    if (opts.mode = "full")
        return GameZoneRegion()
    marginPx := opts.HasOwnProp("marginPx") ? opts.marginPx : 0
    return RegionAround(opts.x, opts.y, opts.w, opts.h, marginPx)
}

; ---------- proximity acquire (multi-color, equal priority) ----------

; Searches every color in `colors` within [x1,y1]-[x2,y2] and returns
; the match closest to refX,refY (squared-distance compare - no need
; for the actual distance, just which is smaller). Every color is
; searched every call - none is favored by list order, so a farther
; match in an earlier-listed color never wins over a closer match in a
; later-listed one. This is the per-stage core of the expanding-ring
; acquire pattern (M4): a caller tries this in a small box around a
; reference point first, then progressively wider boxes, stopping at
; the first stage that finds anything.
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

; ---------- game zone (fixed screen calibration) ----------

; The game viewport as measured on this setup: a sub-region of the
; full 2560x1440 screen, NOT the whole screen - starts at (0,45),
; sized 2499x1335. Search regions for in-game targets (trees, rocks,
; NPCs, travel markers) should clamp to this, since nothing real can
; ever appear outside it (chat box, minimap chrome, taskbar, etc. are
; excluded). Fixed per-setup calibration, same category as v6 Inv.ahk's
; INV_FIRST_X/Y - lives in Lib once, not redefined per script.
;
; Bank/inventory UI grid coordinates are UNAFFECTED by this and stay
; exactly as measured on screen (e.g. v6's INV_FIRST_X/Y=2099,801) -
; those were captured directly on screen, not derived from this box.
GAME_ZONE_X1 := 0
GAME_ZONE_Y1 := 45
GAME_ZONE_X2 := 2499
GAME_ZONE_Y2 := 1380

; Convenience accessor returning the game zone as a [x1,y1,x2,y2] box,
; the same shape RegionAround returns - so callers that want "clamp to
; the game zone" can use it interchangeably with a RegionAround result.
GameZoneRegion() {
    return [GAME_ZONE_X1, GAME_ZONE_Y1, GAME_ZONE_X2, GAME_ZONE_Y2]
}

; ---------- character position (fixed screen calibration) ----------
;
; The character's on-screen center in this setup's fixed camera/zoom -
; the reference point ring-expansion acquires (M4) expand outward from.
; Same category as GAME_ZONE_*: measured once, lives in Lib, not
; redefined per script. Named distinctly from the generic refX/refY
; parameters that AcquireClosestInBox etc. take, since a caller could
; in principle pass a different reference point - but in practice this
; IS that reference point almost everywhere.
CHAR_X := 1249
CHAR_Y := 712

; Default expanding-ring padding (M4): how far each acquire ring
; extends outward from CHAR_X/CHAR_Y on every side. Box size for a
; given padding is 2*padding square (radius math, not corner+size -
; e.g. ACQUIRE_PADDING_SMALL=64 gives a 128x128 box, not 130x130; the
; character's own ~2px footprint is not separately added). Two named
; stages, small then large, tried in that order before the region-wide
; fallback. Fixed per-setup default - a bot can still pass its own
; acquireRadii array to TrackAndClick/AcquireClosestInBox if a specific
; target type genuinely needs different stages.
ACQUIRE_PADDING_SMALL := 64
ACQUIRE_PADDING_LARGE := 128

; ---------- bank deposit-image position (fixed screen calibration) ----------
;
; Same category as GAME_ZONE_*/CHAR_X/Y: measured once on this setup,
; lives in Lib, not redefined per script. ONLY the deposit-all PNG
; buttons are fixed like this - the bank/deposit-box MARKER (a colored
; box the bot right-clicks/finds to open the bank in the first place)
; is NOT fixed and stays per-script config (it can be a different
; color/position per bank location) - do not add a marker position
; constant here, only PNG button positions belong in this category.
BANK_DEPOSIT_IMAGE_X := 1327
BANK_DEPOSIT_IMAGE_Y := 963
BANK_DEPOSIT_IMAGE_W := 72
BANK_DEPOSIT_IMAGE_H := 72

; ---------- color helpers (pixel-level) ----------

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
}

; ---------- multi-color search (no reference point - list-order first match) ----------
;
; Loops every color in `colors` and returns the FIRST one that matches -
; in list order, since there's no reference point here to break ties by
; proximity (that's what AcquireClosestInBox, micro 05, is for). Lets
; every script standardize on a colors array even when there's no
; proximity concept to apply to it - add/remove candidate colors from
; the array without touching the search call.
FindAnyFilledBlock(x1, y1, x2, y2, colors, tol, blockW, blockH, &cx, &cy, &foundColor, verifyPercent := 100) {
    for color in colors {
        if (FindFilledBlock(x1, y1, x2, y2, color, tol, blockW, blockH, &mx, &my, verifyPercent)) {
            cx := mx, cy := my, foundColor := color
            return true
        }
    }
    return false
}

; Single-pixel version of the same "any of these colors" check.
IsAnyColorAt(x, y, colors, tol, &foundColor) {
    for color in colors {
        if (IsColorAt(x, y, color, tol)) {
            foundColor := color
            return true
        }
    }
    return false
}

; ---------- state-indicator watcher (gap primitive, no v6 precedent) ----------
;
; Watches a single point (x,y) for ANY of `colors` to reach a caller-
; specified targetState ("present" or "absent"), polling via WaitUntil.
; Built for health-bar-style indicators: watch an enemy's healthbar
; point for its colors to go ABSENT (died), or watch for a healthbar
; color to become PRESENT (target acquired / now in combat) - one
; generic primitive covers both directions, since they're the same
; polling shape with the presence check inverted.
;
; The "already true at start" guard: a single point sample is taken
; BEFORE the poll loop starts. If the target state already holds at
; that very first sample, this is reported distinctly (via
; &alreadyTrue) from a genuine transition observed during the wait -
; a caller watching for "enemy died" needs to know whether it actually
; witnessed the kill just now, or whether there was simply no live
; healthbar from the moment it started watching (e.g. it started
; watching too late, or never had a real target). Either way the
; function still returns true once the target state holds - alreadyTrue
; only distinguishes HOW it became true.
WatchIndicator(x, y, colors, tol, targetState, timeoutMs, pollMs := 300, &alreadyTrue := false) {
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

; Confirms a color block whose CENTER lands within posTolPx of
; (expectedCx, expectedCy) - not just "this color is somewhere on
; screen". Used for "did we arrive at a known waypoint" checks (e.g.
; Motherlode's GoToSackArea()/ReturnToMine()). Outputs the real matched
; center via &fx/&fy (only meaningful when true is returned).
;
; marginPx is now a real caller-configurable parameter (default 40,
; matching v6's value) - v6 hardcoded this as a file-local static, one
; of the confirmed anti-patterns this rewrite fixes. `colors` is an
; array (standard, see file header) - any of them counts as a match at
; this waypoint; &foundColor reports which one.
;
; Box built via RegionAround (not hand-rolled arithmetic) - this is the
; ONE place this padded box gets computed; any caller-side diagnostic
; that needs to re-probe the same box (e.g. a micro's "found elsewhere
; vs not found at all" fallback) should call RegionAround the same way
; instead of re-deriving the formula, so the two can never drift apart.
; Also means this box now clamps to >=0 near screen edges (RegionAround
; does; the old hand-rolled formula didn't) - a genuine small
; correctness fix, not just deduplication.
;
; verifyPercent (default 100, added 2026-07-23 for config consistency -
; every color-block search in the project now exposes this same knob,
; even where it's expected to stay at the default) is passed straight
; through to FindAnyFilledBlock/FindFilledBlock - see that function's
; own doc comment for what it does.
BlockAtPoint(expectedCx, expectedCy, colors, tol, blockW, blockH, posTolPx, &fx, &fy, &foundColor, marginPx := 40, verifyPercent := 100) {
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

; Builds the "*tol *TransColor path" ImageSearch pattern string.
; transColor := "" omits the *Trans option entirely.
ImagePattern(path, tol, transColor := "") {
    pattern := "*" tol
    if (transColor != "")
        pattern .= " *Trans" transColor
    return pattern " " path
}

; Searches [x1,y1]-[x2,y2] for the image at path (w x h, its real pixel
; size - ImageSearch returns the match's UPPER-LEFT corner, not its
; center, so the caller-supplied w/h drive the center math); &cx/&cy
; get the center of the matched area. Single-image only (not an array
; like the color primitives) - unlike colors, a different image asset
; has its own distinct w/h, so multi-candidate image search would need
; a list of {path,w,h} entries, not a flat array; no current bot needs
; that, so it's deferred until one does.
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

; ---------- wait-for-image (thin poll wrapper over FindImage, M2) ----------
;
; Polls FindImage via WaitUntil until it appears (WaitForImage) or
; disappears (WaitForImageGone), instead of a single one-shot check -
; the same "wait for a state" shape WatchIndicator (micro 15) gives
; colors, applied to a PNG marker instead. &cx/&cy report the found
; center (WaitForImage only - meaningless once the image is gone).
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

; ---------- watch-box (pixel-box snapshot + change detection) ----------
;
; Ported byte-identical from v6 Lib\Inv.ahk (confirmed live there, v6
; micros 10/11 - md5-verified strided sampling). Samples roughly
; targetSamples points spread evenly across a w x h box whose top-left
; corner is x,y - NOT every pixel (v6 measured exhaustive sampling at
; ~6 SECONDS for an 832-pixel box vs ~350ms strided). The stride is
; DERIVED from box size + targetSamples, not fixed, so a big box and a
; small box both cost about the same regardless of raw pixel area.
; Returns one snapshot object bundling the samples with the
; stride/size used to take them, so HasChanged always re-samples at
; the exact same points.
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

; True if any sampled point now differs from the snapshot's baseline.
; x,y: the box's CURRENT top-left corner (usually unchanged from the
; snapshot, but kept separate in case the box legitimately moves).
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
