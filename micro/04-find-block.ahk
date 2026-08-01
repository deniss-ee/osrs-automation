; ============================================================
; v8 micro 04 - color-block search (Find.ahk block half)
;
; Combines v7 micros 03 (whole-screen search), 04 (padded region
; search), and 05 (expanding rings / nearest-match) into one micro -
; v7's own audit found 05 effectively subsumes 03/04 (a big enough
; region search IS a whole-screen search, and 05's last-resort stage
; is exactly what 04 does), and SearchZone's mode switch collapses
; the "where do I search" decision into one config field anyway.
;
; WHAT IT DOES
;   F5  = whole game-zone search for the first match among
;         TARGET_COLORS (FindAnyFilledBlock), moves mouse to it
;   F6  = request stop
;   F7  = SearchZone("area") padded-region search around a fixed
;         corner (RegionAround) - proves the clamped-region fix by
;         using a corner deliberately near a screen edge
;   F8  = probe: AcquireClosestInBox - nearest match to CHAR_X/Y
;         among all TARGET_COLORS, logs which one won and its
;         distance
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - cursor moves to a real on-screen match; if nothing on
;      screen matches TARGET_COLORS, confirm it reports "not found"
;      cleanly rather than erroring.
;   2. F7 - same idea in a small region near a screen edge; confirm
;      no "region out of bounds" style ImageSearch error even though
;      REGION's x/y/w/h + marginPx would overflow the screen
;      (RegionAround's 4-edge clamp is what prevents this).
;   3. F8 - with two+ different-colored targets on screen, confirm
;      it picks the genuinely nearest one to CHAR_X/Y, not just the
;      first color in the list.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "04-find-block"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLORS := [0x00FF00, 0x00B809]
COLOR_TOL := 5
BLOCK_W := 20
BLOCK_H := 20

REGION := {x: 1382, y: 870, w: 334, h: 228, marginPx: 0}
; ==========================================================================

RunWholeScreenSearch() {
    region := GameZoneRegion()
    found := FindAnyFilledBlock(region[1], region[2], region[3], region[4],
        TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, &foundColor)
    if (found) {
        Say("find-block: found " HexColor(foundColor) " at " cx "," cy)
        MouseMove(cx, cy, 0)
    } else {
        Say("find-block: no match in game zone")
    }
    return found
}

RunRegionSearch() {
    clampedRegion := SearchZone({mode: "area", x: REGION.x, y: REGION.y,
        w: REGION.w, h: REGION.h, marginPx: REGION.marginPx})
    Say("find-block: searching region [" clampedRegion[1] "," clampedRegion[2] "]-[" clampedRegion[3] "," clampedRegion[4] "] (clamped to screen)")
    found := FindAnyFilledBlock(clampedRegion[1], clampedRegion[2], clampedRegion[3], clampedRegion[4],
        TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, &foundColor)
    if (found) {
        Say("find-block: found " HexColor(foundColor) " at " cx "," cy)
        MouseMove(cx, cy, 0)
    } else {
        Say("find-block: no match in clamped region")
    }
}

ProbeNearest() {
    region := GameZoneRegion()
    found := AcquireClosestInBox(region[1], region[2], region[3], region[4],
        TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, 100, CHAR_X, CHAR_Y, &tx, &ty, &foundColor)
    if (found) {
        dist := Round(Sqrt((tx - CHAR_X) ** 2 + (ty - CHAR_Y) ** 2))
        Say("find-block: nearest=" HexColor(foundColor) " at " tx "," ty " (dist=" dist "px)")
    } else {
        Say("find-block: no match found for nearest-search")
    }
}

InstallBotHarness({
    run: RunWholeScreenSearch,
    label: "micro04",
    probe: ProbeNearest,
    extraHotkeys: [
        {key: "F7", handler: RunRegionSearch, label: "region-search"}
    ]
})
