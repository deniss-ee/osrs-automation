; ============================================================
; v7 micro 06 - exact-point presence check (M6)
;
; Never had its own micro in v6 (BlockAtPoint was promoted straight
; from Bots\motherlode.ahk without a dedicated live test, and its
; MARGIN_PX slack was a hardcoded file-local static). This micro closes
; that gap: proves IsAnyColorAt (single-pixel check) and BlockAtPoint
; (confirm a block's CENTER lands within posTolPx of a specific
; expected point - not just "this color is somewhere on screen") with
; marginPx now a real parameter instead of a hidden constant.
;
; NAMING STANDARD (applies to every v7 micro/bot going forward):
;   TARGET_COLORS - always an array, even for a single-color script -
;     add/remove candidate colors without restructuring anything.
;   MARKER_X/MARKER_Y - the ONE corner-measured input for a marker's
;     position (top-left corner). Never a second top-level "EDIT THESE"
;     constant for the derived center - CenterX/CenterY compute that
;     once, right after the edit block, as a plain (non-edited) value.
;
; WHAT IT DOES
;   F5  = IsAnyColorAt: single-pixel check at the marker's center
;   F7  = BlockAtPoint: search a marginPx-padded box around the
;         marker's expected center for a block of any color in
;         TARGET_COLORS sized BLOCK_W x BLOCK_H; true only if its
;         center lands within POS_TOL_PX of the expected point. If it
;         fails, also reports whether any target color was found
;         ANYWHERE in the padded box (position wrong) or not found at
;         all (marker genuinely absent) - same diagnostic distinction
;         TravelToPoint (micro 24) will rely on later.
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: put a marker exactly at MARKER_X,MARKER_Y - both F5 and
; F7 should report true/ARRIVED. Nudge it slightly (still within
; POS_TOL_PX) - F7 should stay true. Move it further out (still within
; the marginPx search net, but outside POS_TOL_PX) - F7 should report
; false with "found nearby but outside tolerance". Hide it entirely -
; F7 should report "not found anywhere in padded box".
;
; HOTKEYS STANDARDIZED: F5 always starts the primary action, F6 always
; requests a stop (sets g_StopRequested, same as micro 01) - no longer
; "just clears the tooltip" like earlier drafts of this micro suite did.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "06-point-presence"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLORS := [0xFFB232]   ; array of candidate colors - add/remove freely
COLOR_TOL := 5
BLOCK_W := 17
BLOCK_H := 17

; Corner-measured marker position (top-left corner) - the ONE position
; input, same convention as every other micro.
MARKER_X := 1657
MARKER_Y := 775

POS_TOL_PX := 0   ; how far the matched center may drift and still count as "arrived"
MARGIN_PX := 16    ; search slack around the expected block area (was v6's hardcoded static)
; ========================================================================

; Derived center - computed once here via CenterX/CenterY, never
; hand-typed or re-edited as its own constant.
CENTER_X := CenterX(MARKER_X, BLOCK_W)
CENTER_Y := CenterY(MARKER_Y, BLOCK_H)

F5:: RunColorAtCheck()
F7:: RunBlockAtPointCheck()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunColorAtCheck() {
    global g_StopRequested
    g_StopRequested := false

    isThere := IsAnyColorAt(CENTER_X, CENTER_Y, TARGET_COLORS, COLOR_TOL, &foundColor)
    actual := PixelGetColor(CENTER_X, CENTER_Y)
    msg := "IsAnyColorAt(" CENTER_X "," CENTER_Y ") = " (isThere ? "TRUE (" HexColor(foundColor) ")" : "FALSE")
        . " (actual=" HexColor(actual) " targets=" JoinMsg(TARGET_COLORS, "/", HexColor) " tol=" COLOR_TOL ")"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunBlockAtPointCheck() {
    global g_StopRequested
    g_StopRequested := false

    t0 := A_TickCount
    arrived := BlockAtPoint(CENTER_X, CENTER_Y, TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H,
        POS_TOL_PX, &fx, &fy, &foundColor, MARGIN_PX)
    elapsedMs := A_TickCount - t0

    if (arrived) {
        MouseMove(fx, fy, 5)
        msg := "ARRIVED: block center at " fx "," fy " (" HexColor(foundColor) ") within " POS_TOL_PX
            . "px of " CENTER_X "," CENTER_Y " (" elapsedMs " ms)"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    ; BlockAtPoint only returns a bool - re-run the same padded-box
    ; search directly to tell "found but outside tolerance" apart from
    ; "not found anywhere" for diagnostic purposes (does not change the
    ; Lib contract, just probes the same box a second time here). Uses
    ; RegionAround, the SAME call BlockAtPoint makes internally, so this
    ; diagnostic box can never drift from the one BlockAtPoint actually
    ; searched.
    box := RegionAround(CENTER_X - BLOCK_W // 2, CENTER_Y - BLOCK_H // 2, BLOCK_W, BLOCK_H, MARGIN_PX)
    foundElsewhere := FindAnyFilledBlock(box[1], box[2], box[3], box[4], TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, &mx, &my, &fc)

    if (foundElsewhere) {
        MouseMove(mx, my, 5)
        drift := "dx=" (mx - CENTER_X) " dy=" (my - CENTER_Y)
        msg := "NOT ARRIVED: found " HexColor(fc) " nearby at " mx "," my " but outside " POS_TOL_PX
            . "px tolerance (" drift ", " elapsedMs " ms)"
    } else {
        msg := "NOT ARRIVED: not found anywhere in padded box (margin=" MARGIN_PX "px, " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=IsAnyColorAt check  F7=BlockAtPoint check  F6=request stop  Esc=exit."
    . " Targets=" JoinMsg(TARGET_COLORS, "/", HexColor) " at " CENTER_X "," CENTER_Y
    . " posTol=" POS_TOL_PX " margin=" MARGIN_PX)
ToolTip("micro 06 ready - F5=IsAnyColorAt  F7=BlockAtPoint", 20, 20)
