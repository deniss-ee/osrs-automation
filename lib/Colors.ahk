; ============================================================
;  Colors.ahk
;  Pixel-color reading and comparison helpers. This is the
;  "is the thing I'm looking for actually there?" layer that
;  every gathering script is built on top of.
;
;  Every wait/search helper here takes a timeoutMs and WILL
;  give up and return a failure value once that time is up.
;  The old scripts had wait loops with no timeout at all
;  (they would spin forever until the user pressed Stop) -
;  always pass a real timeoutMs, even a generous one, so a
;  script can never get stuck silently.
;
;  Every wait/search helper also takes an OPTIONAL trailing
;  runningVarGetter (same convention as Paths.ahk's
;  PlayPathWithGuard) - a zero-arg function returning the
;  script's "should I still be going" flag, checked on every
;  poll. Without passing this, a script's Stop hotkey only
;  flips TaskRunner's `running` flag between phases - it can't
;  interrupt a wait already in progress, so Stop appeared to do
;  nothing until that wait's own (sometimes multi-minute)
;  timeoutMs elapsed. Pass `() => taskRunner["running"]` from
;  every phase function that calls these.
; ============================================================

; Reads the pixel at (x,y) and checks it's within `tol` of `color`.
; The one-line wrapper every phase function should use instead of a
; bare PixelGetColor+ColorClose pair, so no script ever calls
; PixelGetColor directly outside a one-time calibration hotkey.
IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y, "RGB"), color, tol)
}

; Splits a 0xRRGGBB color into its three channels and checks
; that each channel of c1 is within `tol` of the matching
; channel in c2. This is the core "close enough" color match
; used everywhere instead of an exact equality check, since
; game pixels can flicker/anti-alias by a few shades.
ColorClose(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8) & 0xFF
    b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8) & 0xFF
    b2 := c2 & 0xFF
    return Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol
}

; Polls a single pixel until its color is within `tol` of
; expectedColor, for `confirmTicks` consecutive polls in a row, or
; gives up after timeoutMs. Returns true once confirmed matched,
; false on timeout. Use this instead of a bare while-loop so every
; wait has a guaranteed exit.
;
; confirmTicks defaults to 1 (the very first matching reading
; counts, same as before). Raise it for the same reason as
; WaitForPixelColorChange below - a one-frame flicker shouldn't be
; mistaken for a real state change.
;
; runningVarGetter (optional, same convention as Paths.ahk's
; PlayPathWithGuard): a zero-arg function returning the script's
; "should I still be going" flag. Without this, a script's Stop
; hotkey only flips TaskRunner's `running` flag - it can't actually
; interrupt a wait already in progress, so pressing Stop while one of
; these polls is mid-flight had no visible effect until its own
; timeoutMs eventually elapsed (which can be minutes). Pass
; `() => taskRunner["running"]` from a phase function so a stop
; request is checked on every poll, not just between phases.
WaitForPixelColor(x, y, expectedColor, tol, timeoutMs, confirmTicks := 1, pollMs := 100, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
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

; The complement to WaitForPixelColor: polls a pixel until its
; color is NO LONGER within `tol` of awayFromColor for
; `confirmTicks` consecutive polls in a row, or gives up after
; timeoutMs. Returns true once confirmed changed (e.g. a rock
; visibly depleting after you click it), false on timeout. Use
; this after clicking something so you wait for visible proof the
; click had an effect before clicking again, instead of
; re-clicking on every loop tick.
;
; confirmTicks defaults to 1 (the very first different reading
; counts, same as before). Raise it to guard against a single
; transient blip being mistaken for a real change - e.g. your
; character's sprite or the camera settling for a moment right as
; you arrive somewhere can flicker one pixel for a tick or two,
; which would otherwise look exactly like "this rock just
; depleted" even though it hasn't. Any poll that DOESN'T show a
; changed color resets the streak back to zero.
WaitForPixelColorChange(x, y, awayFromColor, tol, timeoutMs, confirmTicks := 1, pollMs := 100, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
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

; Same idea as WaitForPixelColor but races two coordinates at
; once (e.g. "ore spot #1" vs "ore spot #2"). Returns 1 if the
; first matched first, 2 if the second matched first, or 0 if
; neither matched before timeoutMs ran out.
WaitForEitherPixelColor(x1, y1, color1, x2, y2, color2, tol, timeoutMs, pollMs := 100, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
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

; Bounded retry wrapper around PixelSearch. Searches the
; rectangle (x1,y1)-(x2,y2) for `color` (within `tol`) every
; pollMs, up to timeoutMs total. On success returns true and
; writes the found position into foundX/foundY (pass by
; reference: WaitForPixelSearch(&fx, &fy, ...)). On failure
; returns false and leaves foundX/foundY untouched.
WaitForPixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol, timeoutMs, pollMs := 150, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
            return false
        if (PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; Finds the pixel within (x1,y1)-(x2,y2) that's APPROXIMATELY
; closest to (refX,refY) and matches `color` within `tol` - for
; cases like an NPC's combat outline highlight, where there's no
; single fixed point to search and "closest to the character" is
; what determines which way to click. DEPRECATED - use
; FindNearestPixelColorSpiral instead for true center-outward
; search. Works by searching a box centered on (refX,refY) that
; starts at +/-stepPx and grows by stepPx each pass (clipped to the
; given rectangle) until PixelSearch finds a match or the box has
; grown to cover the whole rectangle with nothing found. This is an
; approximation, not a true nearest-pixel scan - PixelSearch
; returns whatever match it finds first within the current box, not
; necessarily the closest point in it. On success writes the match
; into foundX/foundY (pass by reference) and returns true; returns
; false (leaving them untouched) if nothing in the whole rectangle
; matches.
FindNearestPixelColor(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY, stepPx := 20) {
    radius := stepPx
    loop {
        bx1 := Max(x1, refX - radius)
        by1 := Max(y1, refY - radius)
        bx2 := Min(x2, refX + radius)
        by2 := Min(y2, refY + radius)
        if (PixelSearch(&foundX, &foundY, bx1, by1, bx2, by2, color, tol))
            return true
        if (bx1 <= x1 && by1 <= y1 && bx2 >= x2 && by2 >= y2)
            return false
        radius += stepPx
    }
}

; True center-outward spiral search: finds the pixel within
; (x1,y1)-(x2,y2) that is ACTUALLY closest (by Chebyshev distance)
; to (refX,refY) and matches `color` within `tol`. Spirals outward
; from center in expanding square rings, so the first match found is
; guaranteed to be one of the closest matches (all equidistant at the
; same spiral ring). Much more accurate than the box-expansion
; approximation, at the cost of checking individual pixels rather
; than batches. For combat targeting, this ensures the NPC outline
; pixel closest to the character is found first, every time.
; On success writes the match into foundX/foundY (pass by reference)
; and returns true; returns false (leaving them untouched) if nothing
; in the whole rectangle matches.
FindNearestPixelColorSpiral(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY, maxDistance := 1000) {
    targetColor := color

    ; Check center point first (distance 0)
    if (ColorClose(PixelGetColor(refX, refY, "RGB"), targetColor, tol)) {
        foundX := refX
        foundY := refY
        return true
    }

    ; Spiral outward from center in square rings (Chebyshev distance)
    loop maxDistance {
        distance := A_Index

        ; Horizontal edges (top and bottom)
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

        ; Vertical edges (left and right, excluding corners already checked above)
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

; Finds the centroid (center of mass) of all pixels matching `color`
; within tolerance in region (x1,y1)-(x2,y2). Scans every pixel,
; collects all matches, and returns their average position - useful for
; detecting the center of a shape like an NPC outline rather than just
; the closest single pixel. On success writes the centroid into
; centerX/centerY (pass by reference) and returns true; returns false
; (leaving them untouched) if no pixels match.
; NOTE: This is slower than FindNearestPixelColor since it checks every
; pixel in the region, not just expanding boxes. For real-time use,
; consider sampling every Nth pixel or limiting the search area.
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

; Generalized "is this inventory/bank slot occupied" check.
; Rather than calibrating a different "expected item color" per
; script/ore (which breaks the moment you gather a different
; item), calibrate ONE empty-slot background color and check
; that the slot's pixel does NOT match it. Works the same way
; for every item, every script, forever.
IsSlotOccupied(x, y, emptyColor, tol := 15) {
    return !ColorClose(PixelGetColor(x, y, "RGB"), emptyColor, tol)
}

; Like IsSlotOccupied, but checks SEVERAL points instead of
; trusting one pixel. A single sampled point can happen to land on
; a spot where a particular item's icon doesn't cover the
; background (a "hole" in its shape) - that one pixel would still
; read as the empty-slot color even though the slot clearly has an
; item in it. Checking multiple points and treating ANY mismatch as
; "occupied" makes that false negative far less likely, since it'd
; require every single sampled point to coincidentally land on a
; gap in the icon at once.
;
; points: array of Maps {x, y, color} - each point's OWN calibrated
; empty-background color (use Grid.ahk's GetSlotSamplePoints() to
; build the x/y side of this, then sample each one while the slot
; is genuinely empty to fill in `color`).
IsAnyPointOccupied(points, tol := 15) {
    for p in points {
        if (IsSlotOccupied(p["x"], p["y"], p["color"], tol))
            return true
    }
    return false
}

; Polls IsAnyPointOccupied(points) until it reads true (occupied)
; for `confirmTicks` consecutive polls in a row, or gives up after
; timeoutMs. Returns true once confirmed occupied, false on
; timeout. Same confirm-ticks debounce as WaitForPixelColorChange,
; for the same reason - a single transient blip shouldn't count.
WaitUntilOccupied(points, tol, timeoutMs, confirmTicks := 1, pollMs := 100, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
            return false
        if (IsAnyPointOccupied(points, tol)) {
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

; The complement: polls until IsAnyPointOccupied(points) reads
; false (empty) for `confirmTicks` consecutive polls in a row, or
; gives up after timeoutMs. Returns true once confirmed empty,
; false on timeout. This is the smelter's "ore is gone from the
; last slot" check - the same multi-point reference the mining
; script uses for "is it full", just waiting for the opposite
; direction.
WaitUntilNotOccupied(points, tol, timeoutMs, confirmTicks := 1, pollMs := 100, runningVarGetter := "") {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (runningVarGetter != "" && !runningVarGetter())
            return false
        if (!IsAnyPointOccupied(points, tol)) {
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

; Tolerant ore-color match with an optional "green-dominant"
; fallback (ported from motherlode-miner's IsStillOreColor).
; Some ore veins render with a color gradient, so a plain
; ColorClose() against one sampled color can miss. When
; useGreenFallback is true, a pixel that is clearly green-
; dominant (greener than both red and blue by a wide margin)
; also counts as a match. Leave it false for ores that aren't
; green-themed.
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
