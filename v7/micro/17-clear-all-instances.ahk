; ============================================================
; v7 micro 17 - repeat-click until a search comes up empty
; (ClearAllInstances)
;
; Promoted from v6 sudoku.ahk's hand-rolled ClearSearchZone (confirmed
; live there) - see the v7 plan's "ClearAllInstances IN" decision. Real
; test case: the sudoku menu's search zone, a STATIC field of repeating
; slot icons that does NOT respawn - the correct stop condition is "one
; search attempt right now found nothing," not a timeout (that's what
; distinguishes this from FindAndClickBlock/WaitForImage).
;
; WHAT IT DOES
;   F5  = ClearAllInstances: repeatedly finds+clicks every instance of
;         SLOT_IMAGE_PATH within the search zone until a single search
;         attempt finds none, or MAX_ITERATIONS is hit
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: open the sudoku puzzle interface's menu to a tab with
; several slot icons showing, set SEARCH_X/Y/W/H to the real zone
; (same measured area as v6 sudoku.ahk), press F5 - should click every
; visible icon one at a time and report "zone clear (N instances
; clicked)". Also confirm it stops cleanly (reports maxIterations hit)
; if a click genuinely isn't registering, rather than looping forever -
; and that F6 interrupts mid-clear.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "17-clear-all-instances"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Search zone (whole area where slot icons can appear) - corner + size,
; same convention as every other micro's AREA_X/Y/W/H (e.g. micro 04).
; Same measured zone as v6 sudoku.ahk (708x636 at 451,229).
SEARCH_X := 693
SEARCH_Y := 229
SEARCH_W := 708
SEARCH_H := 636

; Slot icon (FindImage - white transparency, same asset v6 used).
SLOT_IMAGE_PATH := A_ScriptDir "\..\Images\sudoku-slot.png"
SLOT_IMAGE_W := 72
SLOT_IMAGE_H := 64
SLOT_IMAGE_TOL := 5
SLOT_TRANS_COLOR := "0xFFFFFF"

CLICK_USE_CTRL := false   ; UI-only interaction, not a game-world object
SETTLE_MS := 100
MAX_ITERATIONS := 200
; ========================================================================

; Derived search region - RegionAround with marginPx=0 (exact box, no
; slack), same call micro 04/07 use to turn a corner+size input into a
; [x1,y1,x2,y2] region instead of hand-rolled corner-to-corner math.
region := RegionAround(SEARCH_X, SEARCH_Y, SEARCH_W, SEARCH_H, 0)
SEARCH_X1 := region[1]
SEARCH_Y1 := region[2]
SEARCH_X2 := region[3]
SEARCH_Y2 := region[4]

F5:: RunClear()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunClear() {
    global g_StopRequested
    g_StopRequested := false

    Say("ClearAllInstances: clearing search zone " SEARCH_X1 "," SEARCH_Y1 " -> " SEARCH_X2 "," SEARCH_Y2)

    try {
        result := ClearAllInstances({
            region: [SEARCH_X1, SEARCH_Y1, SEARCH_X2, SEARCH_Y2],
            path: SLOT_IMAGE_PATH,
            w: SLOT_IMAGE_W,
            h: SLOT_IMAGE_H,
            tol: SLOT_IMAGE_TOL,
            transColor: SLOT_TRANS_COLOR,
            ctrl: CLICK_USE_CTRL,
            settleMs: SETTLE_MS,
            maxIterations: MAX_ITERATIONS,
            label: "micro17"
        })
    } catch BotStopped {
        Say("micro17: STOPPED by F6")
        return
    }

    Say("micro17: " (result ? "done (zone clear)" : "stopped early - see log"))
}

LogLine("Script loaded. F5=clear search zone  F6=request stop  Esc=exit."
    . " Zone=" SEARCH_X1 "," SEARCH_Y1 " -> " SEARCH_X2 "," SEARCH_Y2 " image=" SLOT_IMAGE_PATH)
ToolTip("micro 17 ready - F5 to clear the search zone", 20, 20)
