; ============================================================
; v7 micro 05 - expanding-ring acquire from a reference point (M4)
;
; Distinct from micro 04's fixed single-region search and from v6
; micro 03's fixed 3-stage cascade (small/expanded/whole-screen boxes
; that don't move): this proves the REAL Motherlode/Woodcutting acquire
; shape - try a small square ring CENTERED ON refX/refY first, then
; progressively wider rings, whole-region as the last resort, checking
; MULTIPLE candidate colors at equal priority each stage (nearest match
; wins the tie-break, not scan order). This is the core loop
; TrackAndClick's acquire phase runs every time it needs a new target;
; here it's isolated and tested standalone before TrackAndClick (micro
; 22) is built on top of it.
;
; WHAT IT DOES
;   F5  = for each radius in ACQUIRE_RADII (near -> far), search a
;         square box of that half-size centered on REF_X,REF_Y for any
;         color in TARGET_COLORS; stop at the first ring that finds
;         something. If every ring misses, fall back to the whole
;         REGION. Move mouse onto the match (no click). Tooltip+log
;         report which ring/stage found it, at what coords, in which
;         color.
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: put a marker of one of TARGET_COLORS within the first
; (smallest) ring around REF_X,REF_Y - confirm it's found via that
; ring. Then move it out to only be within a wider ring - confirm the
; stage label advances and it's still found. Then hide it entirely -
; confirm region-wide fallback correctly reports NOT FOUND. Also test
; two markers of different colors at different distances - confirm the
; CLOSER one wins regardless of which color is listed first in
; TARGET_COLORS.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "05-expanding-rings"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLORS := [0xFFB232, 0xCC5D02]   ; equal-priority candidate colors
COLOR_TOL := 5
BLOCK_W := 21
BLOCK_H := 21
VERIFY_PERCENT := 100

; The reference point rings expand FROM - character's on-screen
; position. CHAR_X/CHAR_Y now live in Lib\Find.ahk (fixed per-setup
; calibration, same category as GAME_ZONE_*) instead of being
; redefined per script. Half-sizes in px, near to far.
REF_X := CHAR_X
REF_Y := CHAR_Y

; ACQUIRE_PADDING_SMALL/LARGE now live in Lib\Find.ahk (fixed per-setup
; defaults, same category as CHAR_X/GAME_ZONE_*) instead of being
; redefined per script. Box size is 2*padding square (see Find.ahk
; comment) - so 64/128 gives 128x128 then 256x256 before region-wide.
ACQUIRE_RADII := [ACQUIRE_PADDING_SMALL, ACQUIRE_PADDING_LARGE]

; Outer bound clamping every ring AND the final region-wide fallback.
; GAME_ZONE_* now lives in Lib\Find.ahk (fixed per-setup calibration,
; same category as v6 Inv.ahk's INV_FIRST_X/Y) instead of being
; redefined in every script - GameZoneRegion() returns it as a
; [x1,y1,x2,y2] box, same shape RegionAround returns.
gameZone := GameZoneRegion()
REGION_X1 := gameZone[1]
REGION_Y1 := gameZone[2]
REGION_X2 := gameZone[3]
REGION_Y2 := gameZone[4]
; ========================================================================

F5:: RunAcquire()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunAcquire() {
    global g_StopRequested
    g_StopRequested := false

    t0 := A_TickCount
    LogLine("Acquire started: colors=" JoinMsg(TARGET_COLORS, "/", HexColor) " ref=" REF_X "," REF_Y
        . " radii=" JoinMsg(ACQUIRE_RADII) " region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)

    found := false
    stageLabel := ""
    for radius in ACQUIRE_RADII {
        rx1 := Max(REGION_X1, REF_X - radius)
        ry1 := Max(REGION_Y1, REF_Y - radius)
        rx2 := Min(REGION_X2, REF_X + radius)
        ry2 := Min(REGION_Y2, REF_Y + radius)

        tStage := A_TickCount
        found := AcquireClosestInBox(rx1, ry1, rx2, ry2, TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H,
            VERIFY_PERCENT, REF_X, REF_Y, &tx, &ty, &foundColor)
        if (found) {
            stageLabel := "ring " radius
            break
        }
        LogLine("ring " radius ": not found (" (A_TickCount - tStage) " ms)")
    }

    if (!found) {
        tStage := A_TickCount
        found := AcquireClosestInBox(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2, TARGET_COLORS, COLOR_TOL,
            BLOCK_W, BLOCK_H, VERIFY_PERCENT, REF_X, REF_Y, &tx, &ty, &foundColor)
        stageLabel := "region-wide"
        if (!found)
            LogLine("region-wide: not found (" (A_TickCount - tStage) " ms)")
    }

    elapsedMs := A_TickCount - t0
    if (found) {
        MouseMove(tx, ty, 5)
        msg := "FOUND via " stageLabel " at " tx "," ty " color=" HexColor(foundColor) " (" elapsedMs " ms total)"
    } else {
        msg := "NOT FOUND at any stage (" elapsedMs " ms total)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=acquire (rings->whole region)  F6=clear tooltip  Esc=exit.")
ToolTip("micro 05 ready - F5 to acquire nearest target", 20, 20)
