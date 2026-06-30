; ============================================================
; Colors.ahk - v3 REDESIGNED
;
; Pixel-color reading and comparison helpers. This is the
; "is the thing I'm looking for actually there?" layer that
; every gathering script is built on top of.
;
; v3 changes:
; - Every wait function takes ctx as first parameter (for paused checks)
; - confirmTicks default raised to 3 (debounce-by-default)
; - Drop FindNearestPixelColor (deprecated; FindNearestColor spiral is kept)
; - Drop IsSlotOccupied/IsAnyPointOccupied/WaitUntil* (moved to Slots.ahk)
; - Keep FindShapeCentroid (used by Targeting.ahk)
;
; Depends on: Context.ahk (CtxIsRunning)
; ============================================================

#Requires AutoHotkey v2.0

#Include Context.ahk

; Reads the pixel at (x,y) and checks it's within `tol` of `color`.
; The one-line wrapper every phase function should use instead of a
; bare PixelGetColor+ColorClose pair, so no script ever calls
; PixelGetColor directly outside a one-time calibration hotkey.
IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y, "RGB"), color, tol)
}

; Splits a 0xRRGGBB color into its three channels and checks that
; each channel of c1 is within `tol` of the matching channel in c2.
; This is the core "close enough" color match used everywhere instead
; of exact equality, since game pixels can flicker/anti-alias by a few shades.
ColorClose(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8) & 0xFF
    b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8) & 0xFF
    b2 := c2 & 0xFF
    return Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol
}

; Polls a single pixel until its color is within `tol` of expectedColor,
; for `confirmTicks` consecutive polls in a row, or gives up after timeoutMs.
; Returns true once confirmed matched, false on timeout.
;
; v3: ctx is now required (first param), not optional. CtxIsRunning(ctx)
; is checked every poll so Stop hotkey interrupts mid-wait immediately.
WaitForPixelColor(ctx, x, y, expectedColor, tol, timeoutMs, confirmTicks := 3, pollMs := 100) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (ColorClose(PixelGetColor(x, y, "RGB"), expectedColor, tol)) {
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

; The complement: polls a pixel until its color is NO LONGER within `tol`
; of awayFromColor for `confirmTicks` consecutive polls, or gives up after
; timeoutMs. Returns true once confirmed changed (e.g. a rock depleting),
; false on timeout.
;
; v3: ctx is required (first param), confirmTicks defaults to 3.
WaitForPixelColorChange(ctx, x, y, awayFromColor, tol, timeoutMs, confirmTicks := 3, pollMs := 100) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (!ColorClose(PixelGetColor(x, y, "RGB"), awayFromColor, tol)) {
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

; Races two coordinates at once (e.g. "ore spot #1" vs "ore spot #2").
; Returns 1 if the first matched first, 2 if the second matched first,
; or 0 if neither matched before timeoutMs ran out.
;
; v3: ctx is required (first param).
WaitForEitherPixelColor(ctx, x1, y1, color1, x2, y2, color2, tol, timeoutMs, pollMs := 100) {
    deadline := A_TickCount + timeoutMs
    loop {
        if (!CtxIsRunning(ctx))
            return 0
        if (ColorClose(PixelGetColor(x1, y1, "RGB"), color1, tol))
            return 1
        if (ColorClose(PixelGetColor(x2, y2, "RGB"), color2, tol))
            return 2
        if (A_TickCount >= deadline)
            return 0
        Sleep(pollMs)
    }
}

; Bounded retry wrapper around PixelSearch. Searches the rectangle
; (x1,y1)-(x2,y2) for `color` (within `tol`) every pollMs, up to timeoutMs total.
; On success returns true and writes the found position into foundX/foundY
; (pass by reference). On failure returns false and leaves them untouched.
;
; v3: ctx is required (first param).
WaitForPixelSearch(ctx, &foundX, &foundY, x1, y1, x2, y2, color, tol, timeoutMs, pollMs := 150) {
    deadline := A_TickCount + timeoutMs
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; True center-outward spiral search: finds the pixel within (x1,y1)-(x2,y2)
; that is ACTUALLY closest (by Chebyshev distance) to (refX,refY) and matches
; `color` within `tol`. Spirals outward from center in expanding square rings,
; so the first match found is guaranteed to be one of the closest matches.
; Much more accurate than box-expansion approximation.
; On success writes the match into foundX/foundY and returns true;
; returns false (leaving them untouched) if nothing matches.
FindNearestColor(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY, maxDistance := 1000) {
    targetColor := color

    if (ColorClose(PixelGetColor(refX, refY, "RGB"), targetColor, tol)) {
        foundX := refX
        foundY := refY
        return true
    }

    loop maxDistance {
        distance := A_Index

        y := refY - distance
        if (y >= y1 && y <= y2) {
            loop (distance * 2 + 1) {
                x := refX - distance + (A_Index - 1)
                if (x >= x1 && x <= x2) {
                    if (ColorClose(PixelGetColor(x, y, "RGB"), targetColor, tol)) {
                        foundX := x
                        foundY := y
                        return true
                    }
                }
            }
        }

        y := refY + distance
        if (y >= y1 && y <= y2) {
            loop (distance * 2 + 1) {
                x := refX - distance + (A_Index - 1)
                if (x >= x1 && x <= x2) {
                    if (ColorClose(PixelGetColor(x, y, "RGB"), targetColor, tol)) {
                        foundX := x
                        foundY := y
                        return true
                    }
                }
            }
        }

        x := refX - distance
        if (x >= x1 && x <= x2) {
            loop (distance * 2 - 1) {
                y := refY - distance + (A_Index)
                if (y >= y1 && y <= y2) {
                    if (ColorClose(PixelGetColor(x, y, "RGB"), targetColor, tol)) {
                        foundX := x
                        foundY := y
                        return true
                    }
                }
            }
        }

        x := refX + distance
        if (x >= x1 && x <= x2) {
            loop (distance * 2 - 1) {
                y := refY - distance + (A_Index)
                if (y >= y1 && y <= y2) {
                    if (ColorClose(PixelGetColor(x, y, "RGB"), targetColor, tol)) {
                        foundX := x
                        foundY := y
                        return true
                    }
                }
            }
        }
    }

    return false
}

; Finds the centroid (center of mass) of all pixels matching `color` within
; tolerance in region (x1,y1)-(x2,y2). Scans pixels (optionally sampling
; every Nth pixel for speed), collects all matches, and returns their average
; position - useful for detecting the center of a shape like an NPC outline.
; On success writes the centroid into centerX/centerY and returns true;
; returns false (leaving them untouched) if no pixels match.
;
; NOTE: This scans every pixel (or every Nth pixel), so it's slower than
; FindNearestColor. For real-time use, consider sampling every 2nd or 4th pixel
; or limiting the search area.
FindShapeCentroid(x1, y1, x2, y2, color, tol, &centerX, &centerY, sampleRate := 1) {
    targetColor := color
    totalX := 0, totalY := 0, matchCount := 0

    loop (y2 - y1 + 1) {
        y := y1 + (A_Index - 1)
        if (Mod(y - y1, sampleRate) != 0 && A_Index != 1)
            continue

        loop (x2 - x1 + 1) {
            x := x1 + (A_Index - 1)
            if (Mod(x - x1, sampleRate) != 0 && A_Index != 1)
                continue

            if (ColorClose(PixelGetColor(x, y, "RGB"), targetColor, tol)) {
                totalX += x
                totalY += y
                matchCount += 1
            }
        }
    }

    if (matchCount = 0)
        return false

    centerX := Round(totalX / matchCount)
    centerY := Round(totalY / matchCount)
    return true
}

; Tolerant ore-color match with an optional "green-dominant" fallback
; (ported from motherlode-miner's IsStillOreColor). Some ore veins render
; with a color gradient, so a plain ColorClose() against one sampled color
; can miss. When useGreenFallback is true, a pixel that is clearly
; green-dominant (greener than both red and blue by a wide margin) also
; counts as a match. Leave it false for ores that aren't green-themed.
IsAnyOreColor(currentColor, baseColor, tol, useGreenFallback := false) {
    if (ColorClose(currentColor, baseColor, tol))
        return true
    if (!useGreenFallback)
        return false

    r := (currentColor >> 16) & 0xFF
    g := (currentColor >> 8) & 0xFF
    b := currentColor & 0xFF
    return (g >= r + 30) && (g >= b + 30) && (g >= 100)
}

; Checks once (instantly, no wait/loop) if a color is present in the region.
; Returns true and writes the found position into foundX/foundY if found, false otherwise.
IsColorInRegion(x1, y1, x2, y2, color, tol, &foundX := 0, &foundY := 0) {
    return PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol) ? true : false
}
