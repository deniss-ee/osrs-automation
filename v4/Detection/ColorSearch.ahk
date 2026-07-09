; ============================================================
; ColorSearch.ahk
; Static, stateless pixel/block search primitives - direct port
; of lib/Colors.ahk's ColorClose/IsColorAt/VerifyBlock/
; FindFilledBlock. This is the raw building block that
; DynamicTarget classes and phases call into; kept separate and
; static because callers compose it differently - e.g. MinePhase
; searches for TWO equally-valid candidate colors (light/dark
; vein overlay) and picks whichever is closer to the character,
; while a single-color tracking target just calls it once.
; ============================================================

#Requires AutoHotkey v2.0

class ColorSearch {
    ; Splits two 0xRRGGBB colors into channels and checks each is within
    ; `tol` of the other. Ported from lib/Colors.ahk's ColorClose exactly.
    static ColorClose(c1, c2, tol) {
        r1 := (c1 >> 16) & 0xFF
        g1 := (c1 >> 8) & 0xFF
        b1 := c1 & 0xFF
        r2 := (c2 >> 16) & 0xFF
        g2 := (c2 >> 8) & 0xFF
        b2 := c2 & 0xFF
        return Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol
    }

    static IsColorAt(x, y, color, tol) {
        return ColorSearch.ColorClose(PixelGetColor(x, y, "RGB"), color, tol)
    }

    ; Fast 5-point cross-check that a reqW x reqH block is solidly filled
    ; with `color`, anchored at the found point (x,y). Checks 75% of the
    ; requested size (safe against edge anti-aliasing), matching
    ; lib/Colors.ahk's VerifyBlock - PLUS a directionY parameter (default 1,
    ; matching legacy exactly): when scanning bottom-up, a found point sits
    ; near the vein's BOTTOM edge, so the block must be checked extending
    ; UPWARD (directionY=-1) from it - there are no vein pixels further
    ; below a bottom edge, so checking downward there would almost always
    ; fail. x is always treated as the block's left edge either way (only
    ; the y-direction flips, matching PixelSearch's own left-to-right scan
    ; within a row being unaffected by the bottom-up/top-down row order).
    static VerifyBlock(x, y, color, tol, reqW, reqH, directionY := 1) {
        checkW := reqW * 3 // 4
        checkH := reqH * 3 // 4
        yStep := directionY  ; +1 = check downward, -1 = check upward

        cx := x + checkW // 2
        cy := y + yStep * (checkH // 2)

        if (!ColorSearch.IsColorAt(cx, cy, color, tol))
            return false
        if (!ColorSearch.IsColorAt(x, y + yStep * (checkH // 2), color, tol))
            return false
        if (!ColorSearch.IsColorAt(x + checkW // 2, y, color, tol))
            return false
        if (!ColorSearch.IsColorAt(x + checkW - 1, y + yStep * (checkH // 2), color, tol))
            return false
        if (!ColorSearch.IsColorAt(x + checkW // 2, y + yStep * (checkH - 1), color, tol))
            return false
        return true
    }

    ; Searches [x1,y1]-[x2,y2] for a continuous block of `color` at least
    ; reqW x reqH in size. Returns true and writes the verified block's own
    ; center via out-params if found (foundX/foundY + reqW/reqH//2) - the
    ; small 15x15-ish block's own center, matching lib/Colors.ahk's
    ; FindFilledBlock exactly. (A previous attempt measured the FULL extent
    ; of the whole contiguous colored region and centered on that instead -
    ; but a vein's color overlay is a much larger, irregular blob than the
    ; small verified block, so that bounding-box center landed well below
    ; the intended click point. Reverted: the small block's own center is
    ; the actually-correct target.)
    ;
    ; scanBottomUp: when true, runs a genuine exhaustive bottom-to-top
    ; search (same stack-splitting algorithm as the default top-down path,
    ; just with the row order reversed throughout) instead of only the
    ; default top-down search - so the first-found, verified pixel is near
    ; the bottom-left of the vein overlay instead of the top-left, and the
    ; search keeps going bottom-up until a valid block is found or the
    ; whole region is exhausted (never silently falls back to top-down).
    ; Iterative stack (not recursive) to avoid AHK recursion limits -
    ; otherwise ported from lib/Colors.ahk's FindFilledBlock exactly,
    ; including the search-order comment (rest-of-row before below-rows).
    ;
    ; Edge clamp: the returned center is still clamped to the searched
    ; region's own bounds (a real vein can extend beyond the search
    ; region's edge, which shouldn't push the click outside it).
    static FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy, scanBottomUp := false) {
        ; PixelSearch's own scan direction is set by which corner is passed
        ; first (per AHK docs: y1 > y2 scans bottom-up) - normalize once
        ; here so the stack-splitting loop below stays identical either way,
        ; just walking from startY toward endY (top-down: startY=y1,
        ; endY=y2; bottom-up: startY=y2, endY=y1).
        startY := scanBottomUp ? y2 : y1
        endY := scanBottomUp ? y1 : y2
        step := scanBottomUp ? -1 : 1

        stack := [[x1, startY, x2, endY]]

        while (stack.Length > 0) {
            rect := stack.Pop()
            rx1 := rect[1], ry1 := rect[2], rx2 := rect[3], ry2 := rect[4]

            if (rx1 > rx2 || (step > 0 ? ry1 > ry2 : ry1 < ry2))
                continue

            if (!PixelSearch(&foundX, &foundY, rx1, ry1, rx2, ry2, color, tol))
                continue

            if (ColorSearch.VerifyBlock(foundX, foundY, color, tol, reqW, reqH, step)) {
                cx := Min(Max(foundX + reqW // 2, x1), x2)
                cy := Min(Max(foundY + step * (reqH // 2), y1), y2)
                return true
            }

            ; Push the two sub-rectangles (order matters! search the rest of
            ; the row first, so push it last). "Below" means "further along
            ; the scan direction" - toward endY, not necessarily increasing Y.
            stack.Push([rx1, foundY + step, rx2, ry2])
            ; 1. The rest of the current horizontal line segment
            stack.Push([foundX + 1, foundY, rx2, foundY])
        }

        return false
    }
}
