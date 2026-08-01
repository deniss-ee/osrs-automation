; ============================================================
; v7 micro 27 - HumanMove glide validation
;
; Exercises Lib\Act.ahk's HumanMove (standard #29: the single movement
; primitive under every game-input click). 2026-07-30 rewrite: this
; used to validate WindMouseMove (a BenLand100 physics glide); it now
; validates HumanMove, a minimum-jerk glide promoted/adapted from
; Tools\humanized-mouse.ahk, retuned for an expert user who already
; knows exactly where the target is - fast, nearly straight, with
; tremor only right at the start/end of the path. Same choke point,
; same micro slot, new algorithm underneath - see PROGRESS.md standard
; #29 for the full rationale (including why the old WindMouse tuning
; saga's speed arithmetic mattered and applies here too).
;
; Physics/pacing params are the HUMANMOVE_* Lib globals - referenced
; here, never redefined (standard #24); this micro only owns its
; target ranges and pacing.
;
; Moves the cursor to random on-screen points forever, logging each
; move's wall time and landing error. Landing error must be 0px every
; time - the post-loop snap in HumanGlide guarantees exact arrival, and
; ClickAt clicks at current position, so this is load-bearing.
;
; WHAT IT DOES
;   F5  = start: endless random glides, one log line per move
;   F6  = request stop (lands mid-glide - GlideStepDelay checks the
;         stop flag on every changed pixel, so the glide itself is
;         interruptible)
;   F12 = exit the script
;
; LIVE CONFIRM:
;   1. F5 - each move is a visible, subtly curved glide - not a dead
;      straight line, not an instant teleport.
;   2. Log shows err=0px on every move.
;   3. Tremor is visible only right as the cursor leaves its start
;      point and right as it settles onto the target - the middle of
;      the path should look clean and steady, not shaky throughout
;      (this is the point of TremorWeight - the opposite of the old
;      source demo's mid-flight-peaked wobble).
;   4. Overall pace reads as near-instant/expert - for each logged
;      "NNpx in MMms" line, sanity-check against PROGRESS.md standard
;      #29's speed table (roughly: 100px well under 65ms, 500-1500px
;      well under 150ms).
;   5. F6 pressed MID-GLIDE stops cleanly ("STOPPED by F6"), cursor
;      simply stops where it was, no stuck input.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "27-human-move"

; ======= EDIT THESE FOR YOUR TEST =======================================
MARGIN_PX := 20           ; keep random targets this far inside the screen edge
MOVE_INTERVAL_MS := 200   ; pause after each move completes
; ========================================================================

RunHumanMove() {
    Say("human-move: pxPerStep=" HUMANMOVE_PX_PER_STEP " steps=" HUMANMOVE_MIN_STEPS ".." HUMANMOVE_MAX_STEPS
        . " stepDelay=" HUMANMOVE_STEP_DELAY_MIN_MS ".." HUMANMOVE_STEP_DELAY_MAX_MS "ms"
        . " tremor=" HUMANMOVE_TREMOR_PX "px@edge" HUMANMOVE_TREMOR_EDGE_FRAC)
    loop {
        targetX := Random(MARGIN_PX, A_ScreenWidth - MARGIN_PX)
        targetY := Random(MARGIN_PX, A_ScreenHeight - MARGIN_PX)
        MouseGetPos(&fromX, &fromY)
        distPx := Round(Sqrt((targetX - fromX) ** 2 + (targetY - fromY) ** 2))

        t0 := A_TickCount
        HumanMove(targetX, targetY)
        elapsedMs := A_TickCount - t0

        MouseGetPos(&landX, &landY)
        errPx := Round(Sqrt((targetX - landX) ** 2 + (targetY - landY) ** 2))
        Say("human-move: " distPx "px in " elapsedMs "ms, err=" errPx "px")

        Pause(MOVE_INTERVAL_MS)
    }
}

InstallBotHarness({
    run: RunHumanMove,
    label: "HumanMove"
})
