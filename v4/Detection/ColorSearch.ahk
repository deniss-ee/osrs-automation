; ============================================================
; ColorSearch.ahk
; Static, stateless pixel/block search primitives. Kept separate
; and static since callers compose them differently - e.g.
; MinePhase searches two candidate colors and picks the closer
; one, while a single-color target just calls it once.
; ============================================================

#Requires AutoHotkey v2.0

class ColorSearch {
    ; Splits two 0xRRGGBB colors into channels and checks each is within
    ; `tol` of the other.
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
    ; requested size (safe against edge anti-aliasing).
    ; directionY: when scanning bottom-up, a found point sits near the
    ; target's BOTTOM edge, so the block must be checked extending UPWARD
    ; (-1) instead of down - there's nothing below a bottom edge to check.
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
    ; center via out-params if found - the small verified block's own
    ; center, not the full contiguous region's bounding-box center (a color
    ; overlay can be a much larger, irregular blob than the verified block).
    ;
    ; scanBottomUp: runs a genuine exhaustive bottom-to-top search (same
    ; stack-splitting algorithm, row order reversed) instead of top-down,
    ; so the first verified pixel is near the bottom instead of the top -
    ; never silently falls back to top-down. Iterative stack, not
    ; recursive, to avoid AHK recursion limits.
    ;
    ; Edge clamp: the returned center is clamped to the searched region's
    ; own bounds, since a match can extend beyond the region's edge.
    static FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy, scanBottomUp := false) {
        ; PixelSearch's scan direction is set by which corner comes first
        ; (y1 > y2 scans bottom-up) - normalize here so the loop below
        ; always walks from startY toward endY either way.
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

            ; Push both sub-rectangles - the rest of the row last, so it's
            ; searched first (LIFO stack). "Below" = further along the
            ; scan direction (toward endY), not necessarily increasing Y.
            stack.Push([rx1, foundY + step, rx2, ry2])
            stack.Push([foundX + 1, foundY, rx2, foundY])
        }

        return false
    }
}
