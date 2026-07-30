; ============================================================
; v7 micro 27 - WindMouseMove glide validation
;
; Exercises Lib\Act.ahk's WindMouseMove (standard #29: the single
; movement primitive under every game-input click), promoted from the
; Tools\windmouse.ahk demo once ClickAt + RightClickMenuItem became its
; second caller. Physics params are the WINDMOUSE_* Lib globals
; (retuned 2026-07-27 to 35/7/22/10) - referenced here, never redefined
; (standard #24); this micro only owns its target ranges and pacing.
;
; Moves the cursor to random on-screen points forever, logging each
; move's wall time and landing error. Landing error must be 0px every
; time - the post-loop snap in WindMouseGlide guarantees exact arrival
; even after an overshoot-and-correct pass, and ClickAt clicks at
; current position, so this is load-bearing.
;
; WHAT IT DOES
;   F5  = start: endless random glides, one log line per move
;   F6  = request stop (lands mid-glide - Pause runs on every changed
;         pixel, so the glide itself is interruptible)
;   F12 = exit the script
;
; LIVE CONFIRM:
;   1. F5 - each move is a visible CURVED glide, not a straight line or
;      an instant flick.
;   2. Log shows err=0px on every move.
;   3. Roughly 1 in 3 moves visibly overshoots a few px past the target
;      and snaps back after a brief pause - not every move (that would
;      look robotic too), and never a WRONG final landing spot.
;   4. F6 pressed MID-GLIDE (including during a correction leg) stops
;      cleanly ("STOPPED by F6"), cursor simply stops where it was, no
;      stuck input.
;   5. Overall pace reads as a natural, fairly quick mouse movement -
;      not the old sluggish glide, not an instant teleport.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "27-wind-move"

; ======= EDIT THESE FOR YOUR TEST =======================================
MARGIN_PX := 20           ; keep random targets this far inside the screen edge
MOVE_INTERVAL_MS := 200   ; pause after each move completes
; ========================================================================

RunWindMove() {
    Say("wind-move: physics G=" WINDMOUSE_GRAVITY " W=" WINDMOUSE_WIND
        . " M=" WINDMOUSE_MAX_STEP " D=" WINDMOUSE_TARGET_AREA
        . " stepDelay=" WINDMOUSE_STEP_DELAY_MIN_MS ".." WINDMOUSE_STEP_DELAY_MAX_MS "ms")
    loop {
        targetX := Random(MARGIN_PX, A_ScreenWidth - MARGIN_PX)
        targetY := Random(MARGIN_PX, A_ScreenHeight - MARGIN_PX)
        MouseGetPos(&fromX, &fromY)
        distPx := Round(Sqrt((targetX - fromX) ** 2 + (targetY - fromY) ** 2))

        t0 := A_TickCount
        WindMouseMove(targetX, targetY)
        elapsedMs := A_TickCount - t0

        MouseGetPos(&landX, &landY)
        errPx := Round(Sqrt((targetX - landX) ** 2 + (targetY - landY) ** 2))
        Say("wind-move: " distPx "px in " elapsedMs "ms, err=" errPx "px")

        Pause(MOVE_INTERVAL_MS)
    }
}

InstallBotHarness({
    run: RunWindMove,
    label: "WindMove"
})
