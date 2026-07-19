; ============================================================
; v6 micro 12 - acquire/track/depleted loop ("TrackAndClick")
;
; The biggest composite: click a target, keep tracking it in a
; narrowed box as it's worked, re-click on a cadence, detect depletion
; (color stops matching) and re-acquire a fresh target - until an
; "until" condition is met (here: an inventory indicator slot full,
; the same condition real Woodcutting/Motherlode/AutoFighter use).
;
; This composite now lives in Lib\Steps.ahk as TrackAndClick(opts) -
; this file just builds the opts from calibration constants and calls
; it, so this test also re-confirms the promoted Lib version behaves
; identically to the original inline loop.
;
; WHAT IT DOES
;   F8  = COLOR PROBE: hover any pixel, get its TRUE on-screen color,
;         the per-channel delta vs EVERY color in TARGET_COLORS, and
;         the minimum tolerance that would match each - use this FIRST
;         whenever a new color "isn't found" (on-screen rendering often
;         blends/shades the configured pure hex)
;   F5  = start the loop: acquire a target -> track/click it -> on
;         depletion (color stops matching), re-acquire -> repeat, until
;         the indicator slot is full OR the overall failsafe timeout
;         elapses. Every tick logged (acquire/track/click/stable state).
;   F6  = request stop (interrupts instantly, same as all prior micros)
;   Esc = exit the script
;
; TEST IT: use the same marker color you've been testing with. Move it
; to simulate a target moving (walk toward it), hide it to simulate
; depletion (should re-acquire), and fill your indicator slot to
; confirm the until-condition stops the loop cleanly. If two targets
; sit close enough that their highlight boxes visually merge, or if
; different trees/veins render in different overlay shades, add more
; entries to TARGET_COLORS - every color in the list is searched every
; acquire attempt with EQUAL priority (none is favored by list order);
; track mode then locks onto whichever color actually matched, same as
; v5 Motherlode's light/dark vein pattern.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "12-track-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
; One or more candidate colors, ALL equal priority - none is favored by
; list order or position. Acquire searches EVERY entry, every attempt
; (v5 Motherlode's veinColorLight/veinColorDark pattern generalized to
; any count). Track mode then LOCKS onto whichever color actually
; matched and re-searches only that one from then on.
TARGET_COLORS := [0x00FF00, 0x00B809]

COLOR_TOL    := 5
BLOCK_W      := 31
BLOCK_H      := 31

; How much of BLOCK_W/H must match as one solid block, in percent.
; 100 = strict full size. Lower slightly (e.g. 90) only if a real
; target's soft/anti-aliased edges make the strict match miss -
; F8-probe first.
VERIFY_PERCENT := 100

; Acquire proximity: the character's on-screen point. Acquire prefers
; the target NEAREST this point instead of the native scan-order match.
; Recalibrate if the camera zoom/layout changes.
REF_X := 1248, REF_Y := 707

; Expanding search rings around REF, tried in order, before falling
; back to the whole screen. Tune radii to taste.
ACQUIRE_RADII := [250, 600]

TRACK_RADIUS_PX := 220   ; narrowed search box half-size once a target is locked

; Max px a found match may be from the last known position and still be
; accepted as "the same target" - see Lib\Steps.ahk's TrackAndClick for
; why this gate exists (native ImageSearch has no ref-steering, so two
; same-colored targets within TRACK_RADIUS_PX of each other could
; otherwise get silently swapped).
MAX_DRIFT_PX := 40

; Pacing below is Motherlode-tuned (v5 Bots\Motherlode\motherlode.ahk /
; auto-motherlode-v2.ini: mineStableTicks=2, clickCooldownMs=1500,
; walkReclickTimeoutMs=3000), NOT Woodcutting's slower tree-pace numbers
; (3/4000/9000) this micro originally shipped with - a real bot's own
; .ini picks whichever pace fits it in Stage 2, these are just this
; micro's calibration defaults.
STABLE_TICKS_REQUIRED := 2    ; consecutive within-tolerance ticks before "stable"
MOVE_TOLERANCE_PX     := 10   ; how much drift still counts as "the same spot"

CLICK_COOLDOWN_MS       := 1500   ; re-click cadence once STABLE (tick-aligned)
WALK_RECLICK_TIMEOUT_MS := 3000   ; re-click cadence while NOT YET stable (still walking toward it)
CLICK_USE_CTRL := true

; Until-condition: the same inventory-full check as micro 09, using
; Lib\Inv.ahk's confirmed layout. Indicator slot 28 matches v5's convention.
INDICATOR_SLOT := 28

POLL_MS  := 300    ; tick-aligned loop interval
OVERALL_TIMEOUT_MS := 600000   ; safety failsafe - stop if nothing meets the until-condition this
                                ; long. 90s, then 5 min, were both too tight for slower trees
                                ; (yew etc. take a lot longer than 28 slots-worth of normal/
                                ; willow chops) - 10 min gives real chopping room while still
                                ; catching a genuinely stuck bot.
; ========================================================================

F5:: RunTrackAndClick()
F8:: ProbeColor()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

; Calibration probe (AutoHotkey.pdf's official method for determining
; color IDs: "Color IDs can be determined using Window Spy or via
; PixelGetColor"). Hover the target block, press F8: reports the TRUE
; on-screen color under the cursor, the per-channel difference from
; EVERY color in TARGET_COLORS, and the minimum tolerance each would
; need. If the reported color differs from what you configured, the
; on-screen rendering is blended/shaded - use the REPORTED value.
ProbeColor() {
    MouseGetPos(&mx, &my)
    actual := PixelGetColor(mx, my)

    msg := "PROBE at " mx "," my ": actual=" HexColor(actual)
    for i, configured in TARGET_COLORS
        msg .= (i = 1 ? "  " : "  |  ") ProbeAgainst(actual, "TARGET_COLORS[" i "]", configured)
    Say(msg)
}

; Formats one color's comparison for ProbeColor - shared so every
; entry in TARGET_COLORS reads identically.
ProbeAgainst(actual, label, configured) {
    dR := Abs(((actual >> 16) & 0xFF) - ((configured >> 16) & 0xFF))
    dG := Abs(((actual >> 8) & 0xFF) - ((configured >> 8) & 0xFF))
    dB := Abs((actual & 0xFF) - (configured & 0xFF))
    minTol := Max(dR, dG, dB)

    return label "=" HexColor(configured) " delta R/G/B=" dR "/" dG "/" dB
        . " -> " (minTol <= COLOR_TOL
            ? "MATCHES at current tol " COLOR_TOL
            : "needs tol >= " minTol " (or set " label " := " HexColor(actual) ")")
}

RunTrackAndClick() {
    global g_StopRequested
    g_StopRequested := false

    colorsMsg := ""
    for i, c in TARGET_COLORS
        colorsMsg .= (i = 1 ? "" : "/") HexColor(c)
    Say("TrackAndClick started (via Lib\Steps.ahk): colors=" colorsMsg " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " trackRadius=" TRACK_RADIUS_PX
        . " indicatorSlot=" INDICATOR_SLOT " overallTimeout=" OVERALL_TIMEOUT_MS "ms")

    opts := {
        colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H, verifyPercent: VERIFY_PERCENT,
        refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, trackRadius: TRACK_RADIUS_PX,
        maxDriftPx: MAX_DRIFT_PX, stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: WALK_RECLICK_TIMEOUT_MS, ctrl: CLICK_USE_CTRL,
        until: () => SlotFull(INDICATOR_SLOT), timeoutMs: OVERALL_TIMEOUT_MS, pollMs: POLL_MS
    }

    try {
        TrackAndClick(opts)
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

startColorsMsg := ""
for i, c in TARGET_COLORS
    startColorsMsg .= (i = 1 ? "" : "/") HexColor(c)
LogLine("Script loaded. F5=start loop  F8=probe color under cursor  F6=stop  Esc=exit. Targets=" startColorsMsg
    . " IndicatorSlot=" INDICATOR_SLOT " VerifyPercent=" VERIFY_PERCENT)
ToolTip("micro 12 ready - F8 to probe a color, F5 to start the loop", 20, 20)
