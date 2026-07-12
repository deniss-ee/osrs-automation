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

    ; Finds the color pixel in [x1,y1]-[x2,y2] nearest to (refX, refY) -
    ; a single-pixel seed search, no block/shape requirement. Returns false
    ; if no matching pixel exists in the region.
    ;
    ; rowStep: rows are sampled at this stride (not every literal row) -
    ; a whole-viewport scan (thousands of rows) calling PixelSearch per row
    ; is too slow to be usable as a per-tick poll; a seed only needs to land
    ; somewhere on a matching blob; a real row is always at most rowStep-1
    ; px away vertically, which FindCentroid's blobRadius box comfortably
    ; absorbs afterward.
    ;
    ; Only the FIRST match on each sampled row is taken (not every match on
    ; that row) - when many small blobs/outline pixels are scattered across
    ; the region (e.g. several irregularly-shaped NPC overlays), exhaustively
    ; walking every match on every row multiplies into a multi-second scan;
    ; a seed just needs to land near a blob, so one candidate per row is
    ; enough precision for this step.
    static FindNearestColor(x1, y1, x2, y2, refX, refY, color, tol, &nearX, &nearY, rowStep := 4) {
        found := false
        bestDistSq := 0
        bestX := 0
        bestY := 0

        y := y1
        while (y <= y2) {
            if (PixelSearch(&px, &py, x1, y, x2, y, color, tol)) {
                dx := px - refX
                dy := py - refY
                distSq := (dx * dx) + (dy * dy)
                if (!found || distSq < bestDistSq) {
                    found := true
                    bestDistSq := distSq
                    bestX := px
                    bestY := py
                }
            }
            y += rowStep
        }

        if (!found)
            return false

        nearX := bestX
        nearY := bestY
        return true
    }

    ; Centroid (average position) of `color` pixels inside [x1,y1]-[x2,y2],
    ; one sampled row per `sampleRate` rows (first match per row, same
    ; cheap-approximation shape as FindNearestColor) - NOT a per-pixel
    ; PixelGetColor loop. On this framework's target machines, individual
    ; PixelGetColor/PixelSearch calls carry a large fixed per-call cost (the
    ; underlying screen-capture setup, not the pixel comparison itself), so
    ; a brute-force per-pixel loop over even a small 120x120 box multiplies
    ; into a multi-second stall - PixelSearch already scans a whole row
    ; natively in one call, so this reuses that same primitive instead of
    ; re-implementing the scan by hand. Returns false if nothing matches.
    static FindCentroid(x1, y1, x2, y2, color, tol, &cx, &cy, sampleRate := 2) {
        sumX := 0
        sumY := 0
        count := 0

        y := y1
        while (y <= y2) {
            if (PixelSearch(&px, &py, x1, y, x2, y, color, tol)) {
                sumX += px
                sumY += py
                count += 1
            }
            y += sampleRate
        }

        if (count = 0)
            return false

        cx := Round(sumX / count)
        cy := Round(sumY / count)
        return true
    }

    ; Finds the NEAREST irregular color blob to (refX, refY) inside
    ; [x1,y1]-[x2,y2] and returns its centroid - unlike FindFilledBlock,
    ; this makes no assumption about the blob being a solid fixed-size
    ; rectangle, so it correctly handles the irregular, variably-shaped/sized
    ; overlays OSRS paints on NPCs (a fixed-block search misses/mis-clicks
    ; on these). Two-step, ported from legacy's FindNearestOutlineBlobCenter
    ; (lib/Targeting.ahk), which the legacy codebase's own comments say
    ; supersedes the old solid-block approach for exactly this reason:
    ; 1. Seed: nearest single matching pixel to (refX, refY) - picks WHICH
    ;    blob is closest when several exist simultaneously.
    ; 2. Centroid: average position of matching pixels within a
    ;    blobRadius box around that seed (clamped to the original region) -
    ;    the real click target, not the seed pixel itself (which is likely
    ;    on the blob's edge, not its middle).
    static FindNearestBlobCenter(x1, y1, x2, y2, refX, refY, color, tol, blobRadius, &targetX, &targetY, sampleRate := 2, seedRowStep := 4) {
        if (!ColorSearch.FindNearestColor(x1, y1, x2, y2, refX, refY, color, tol, &seedX, &seedY, seedRowStep))
            return false

        bx1 := Max(x1, seedX - blobRadius)
        by1 := Max(y1, seedY - blobRadius)
        bx2 := Min(x2, seedX + blobRadius)
        by2 := Min(y2, seedY + blobRadius)

        return ColorSearch.FindCentroid(bx1, by1, bx2, by2, color, tol, &targetX, &targetY, sampleRate)
    }
}
