; ============================================================
; Targeting.ahk - NEW
;
; Colored-outline-blob centroid targeting for NPC/enemy combat.
; v3 correction: real working behavior finds the CENTER of the colored
; outline blob, not the nearest edge pixel + guessed offset.
;
; The current scripts\auto-fighter.ahk approach (nearest-pixel-plus-offset)
; is superseded here. FindNearestOutlineBlobCenter uses a nearest-pixel search
; only as a SEED to locate which blob is closest (when multiple targets exist),
; then computes the actual click target as the centroid of that blob.
;
; Depends on: Colors.ahk (FindNearestColor, FindShapeCentroid, ColorClose), Click.ahk (HumanClick, JitterDelay), TaskRunner.ahk (ResetPhaseTimer), Context.ahk
; ============================================================

#Requires AutoHotkey v2.0

#Include Colors.ahk
#Include Click.ahk
#Include TaskRunner.ahk
#Include Context.ahk

; Finds the centroid (geometric center) of ALL pixels matching a color
; within tolerance inside (x1,y1)-(x2,y2), unrestricted. Useful when there's
; only one target blob in the region or when you want the center of the
; whole region's match. On success writes centroid into &targetX/&targetY,
; returns true; false otherwise (leaves them untouched).
FindOutlineBlobCenter(x1, y1, x2, y2, color, tolerance, &targetX, &targetY, sampleRate := 2) {
    return FindShapeCentroid(x1, y1, x2, y2, color, tolerance, &targetX, &targetY, sampleRate)
}

; When several DISTINCT blobs can exist in the same region (multiple targetable
; NPCs), this finds the blob CLOSEST to (refX, refY) - typically the character's
; position. Works by:
; 1. Using FindNearestColor to locate the nearest matching pixel (seed)
; 2. Computing the centroid of only the matching pixels within a blobRadius box
;    around that seed (NOT the seed pixel itself - the centroid is the click target)
;
; This ensures the true center of the nearest blob, without guessing an offset direction.
; On success writes centroid into &targetX/&targetY, returns true; false otherwise.
FindNearestOutlineBlobCenter(x1, y1, x2, y2, refX, refY, color, tolerance, &targetX, &targetY, blobRadius := 60, sampleRate := 2) {
    if (!FindNearestColor(x1, y1, x2, y2, refX, refY, color, tolerance, &seedX, &seedY))
        return false

    ; Box around the seed point (constrained to the original search region)
    bx1 := Max(x1, seedX - blobRadius)
    by1 := Max(y1, seedY - blobRadius)
    bx2 := Min(x2, seedX + blobRadius)
    by2 := Min(y2, seedY + blobRadius)

    return FindShapeCentroid(bx1, by1, bx2, by2, color, tolerance, &targetX, &targetY, sampleRate)
}

; The full combat-targeting action in one call: locate the nearest target blob's
; centroid and click it directly. NO offset parameter at all - the centroid is
; already inside the blob. Clicks clickCount times with clickDelayMs between clicks.
; Returns true (and resets phase timer) if target found and clicked; false otherwise.
;
; targetRegion: {color, tolerance, x1, y1, x2, y2}
; refX, refY: character's approximate screen position (for "nearest to character" bias)
; blobRadius: how far from the seed point to search for pixels belonging to the same blob
; sampleRate: pixel-sampling stride (2 = check every 2nd pixel for speed; 1 = check all)
; Polls FindOutlineBlobCenter over a region until a centroid is found, or
; gives up after timeoutMs. Same call shape as Colors.ahk's
; WaitForPixelSearch, but returns the CENTER of the whole matching blob
; instead of the first/nearest matching pixel - for ground markers/regions
; painted as a solid colored area, where the real click target is the
; middle of that area, not whichever edge pixel is scanned first.
WaitForBlobCenter(ctx, &foundX, &foundY, x1, y1, x2, y2, color, tol, timeoutMs, sampleRate := 2, pollMs := 150) {
    deadline := A_TickCount + timeoutMs
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (FindOutlineBlobCenter(x1, y1, x2, y2, color, tol, &foundX, &foundY, sampleRate))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; Builds a sparse per-row pixel set for one color inside a region.
; Result shape: rows[y][x] := true
BuildColorPixelRowsForRegion(x1, y1, x2, y2, color, tolerance := 0) {
    rows := Map()
    y := y1
    while (y <= y2) {
        row := Map()
        startX := x1
        while (startX <= x2) {
            if (!PixelSearch(&px, &py, startX, y, x2, y, color, tolerance))
                break
            row[px] := true
            startX := px + 1
        }
        if (row.Count > 0)
            rows[y] := row
        y += 1
    }
    return rows
}

HasPixelInRows(rows, x, y) {
    return rows.Has(y) && rows[y].Has(x)
}

; True only when every pixel in the block is present in rows.
IsSolidColorBlockInRows(rows, topLeftX, topLeftY, blockSize) {
    endY := topLeftY + blockSize - 1
    endX := topLeftX + blockSize - 1

    y := topLeftY
    while (y <= endY) {
        if (!rows.Has(y))
            return false
        row := rows[y]

        x := topLeftX
        while (x <= endX) {
            if (!row.Has(x))
                return false
            x += 1
        }
        y += 1
    }
    return true
}

; Finds the center of the nearest fully-filled solid-color block.
; A candidate block is valid only if all blockSize*blockSize pixels match.
FindNearestSolidColorBlockCenter(x1, y1, x2, y2, refX, refY, color, tolerance, &targetX, &targetY, blockSize := 17) {
    if (blockSize < 1)
        return false

    maxTopLeftX := x2 - blockSize + 1
    maxTopLeftY := y2 - blockSize + 1
    if (maxTopLeftX < x1 || maxTopLeftY < y1)
        return false

    rows := BuildColorPixelRowsForRegion(x1, y1, x2, y2, color, tolerance)
    if (rows.Count = 0)
        return false

    found := false
    bestDistSq := 0
    bestX := 0
    bestY := 0
    half := Floor(blockSize / 2)

    for y, row in rows {
        if (y > maxTopLeftY)
            continue

        for x, _ in row {
            if (x > maxTopLeftX)
                continue

            endX := x + blockSize - 1
            endY := y + blockSize - 1
            if (!HasPixelInRows(rows, endX, y) || !HasPixelInRows(rows, x, endY) || !HasPixelInRows(rows, endX, endY))
                continue

            if (!IsSolidColorBlockInRows(rows, x, y, blockSize))
                continue

            cx := x + half
            cy := y + half
            dx := cx - refX
            dy := cy - refY
            distSq := (dx * dx) + (dy * dy)

            if (!found || distSq < bestDistSq) {
                found := true
                bestDistSq := distSq
                bestX := cx
                bestY := cy
            }
        }
    }

    if (!found)
        return false

    targetX := bestX
    targetY := bestY
    return true
}

; Exact solid-block targeting flow: find nearest valid block center and click it.
; targetRegion: {color, tolerance, x1, y1, x2, y2}
AcquireSolidColorBlockTarget(ctx, targetRegion, refX, refY, blockSize := 17, clickCount := 1, clickDelayMs := 10) {
    if (!FindNearestSolidColorBlockCenter(targetRegion["x1"], targetRegion["y1"], targetRegion["x2"], targetRegion["y2"], refX, refY, targetRegion["color"], targetRegion["tolerance"], &tx, &ty, blockSize))
        return false

    loop clickCount {
        HumanClick(tx, ty, 0, 0, ctx["runMode"])
        if (A_Index < clickCount)
            Sleep(JitterDelay(clickDelayMs))
    }

    ResetPhaseTimer(ctx["runner"])
    return true
}

AcquireTarget(ctx, targetRegion, refX, refY, blobRadius := 60, sampleRate := 2, clickCount := 1, clickDelayMs := 10) {
    if (!FindNearestOutlineBlobCenter(targetRegion["x1"], targetRegion["y1"], targetRegion["x2"], targetRegion["y2"], refX, refY, targetRegion["color"], targetRegion["tolerance"], &tx, &ty, blobRadius, sampleRate))
        return false

    loop clickCount {
        HumanClick(tx, ty, 0, 0, ctx["runMode"])
        if (A_Index < clickCount)
            Sleep(JitterDelay(clickDelayMs))
    }

    ResetPhaseTimer(ctx["runner"])
    return true
}
