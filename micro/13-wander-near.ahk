; ============================================================
; v8 micro 13 - WanderNear idle-wander validation (Act.ahk)
;
; Backfills the one-micro-per-primitive discipline WanderNear skipped
; when it was built live inside Bots\woodcutting.ahk (see PROGRESS.md
; "Lib growth" #5) - its loop+hop redesigns, the avoidRadius geometry
; fix, and the RandTri-float crash were all found live inside that bot
; without a dedicated harness. This gives it one, after the fact.
;
; WHAT IT DOES
;   F5  = endless WanderNear runs near screen center, no exclusion -
;         long duration per run so both LOOPS (round/sweeping motion)
;         and HOPS (long jumps to a fresh loop center) are clearly
;         visible; loops forever until F6
;   F7  = same, but with avoidRadiusPx set around a fixed marked point
;         (a persistent ToolTip pins it) - watch the cursor never
;         enter that circle across the whole run
;   F6  = request stop (mid-wander - GlideStepDelay checks the stop
;         flag on every changed pixel, same as any HumanGlide leg)
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - motion reads as loops (smooth circular sweeps) punctuated
;      by hops (long straight-ish jumps to a new area), never choppy
;      or teleport-y even at full-screen range.
;   2. F6 mid-wander - stops within one glide step, no stuck input.
;   3. F7 - the cursor's path visibly avoids the marked point's
;      exclusion circle for the entire run.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "13-wander-near"

; ======= EDIT THESE FOR YOUR TEST =======================================
WANDER_CENTER_X := A_ScreenWidth // 2
WANDER_CENTER_Y := A_ScreenHeight // 2
WANDER_DURATION_MS := [4000, 8000]

AVOID_RADIUS_PX := 200
; ==========================================================================

RunWander() {
    Say("13-wander-near: endless plain runs, no exclusion (F6 to stop)")
    loop {
        WanderNear(WANDER_CENTER_X, WANDER_CENTER_Y, {durationMs: WANDER_DURATION_MS})
    }
}

RunWanderAvoiding() {
    Say("13-wander-near: endless runs avoiding r=" AVOID_RADIUS_PX "px around "
        . WANDER_CENTER_X "," WANDER_CENTER_Y " (F6 to stop)")
    ToolTip("AVOID (r=" AVOID_RADIUS_PX "px)", WANDER_CENTER_X, WANDER_CENTER_Y, 2)
    try {
        loop {
            WanderNear(WANDER_CENTER_X, WANDER_CENTER_Y, {
                durationMs: WANDER_DURATION_MS, avoidRadiusPx: AVOID_RADIUS_PX
            })
        }
    } finally {
        ToolTip(, , , 2)
    }
}

InstallBotHarness({
    run: RunWander,
    label: "13-wander-near",
    extraHotkeys: [
        {key: "F7", handler: RunWanderAvoiding, label: "avoiding"}
    ]
})
