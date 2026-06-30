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
