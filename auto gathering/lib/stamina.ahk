; ============================================================
;  stamina.ahk - READING YOUR RUN ENERGY AND DECIDING RUN VS WALK
; ------------------------------------------------------------
;  ELI5: In OSRS there's a little round "orb" near the minimap
;  that shows how much running energy you have. It's basically a
;  fuel gauge that empties as you run and fills back up as you
;  walk/rest. This file teaches the bot to "look" at that orb's
;  fill color and turn that into a 0-100% number, then decide
;  per movement step "should I actually run here, or walk?" -
;  that decision is what lets the bot use running ONLY on the
;  steps you marked as worth it, AND only when there's enough
;  energy left, instead of one big on/off switch for everything.
;
;  HOW CALIBRATION WORKS (you do this once per OSRS UI/resolution):
;    1. Drain your run energy to ~0% (run around) and press the
;       calibrate-empty hotkey while hovering the orb.
;    2. Let it refill to 100% and press calibrate-full while
;       hovering the orb again.
;    3. Now the bot knows what "0%" and "100%" look like as a
;       color, and can guess anything in between.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; CalibrateOrbEmpty / CalibrateOrbFull: sample the pixel under
; the mouse and remember it as the 0% / 100% reference color.
; Also remembers the x/y so future reads always check the same
; spot (the orb doesn't move once you've found it).
; --------------------------------------------------------------
CalibrateOrbEmpty() {
    global State
    MouseGetPos(&x, &y)
    State["orbX"] := x
    State["orbY"] := y
    State["orbEmptyColor"] := PixelGetColor(x, y, "RGB")
    State["statusText"] := "Stamina orb EMPTY color set at " x "," y
}

CalibrateOrbFull() {
    global State
    MouseGetPos(&x, &y)
    ; Reuse the same x/y the empty calibration used, if it exists,
    ; so both samples come from the exact same pixel. If empty
    ; hasn't been set yet, fall back to wherever the mouse is now.
    if (State["orbX"] != 0 || State["orbY"] != 0) {
        x := State["orbX"]
        y := State["orbY"]
    }
    State["orbX"] := x
    State["orbY"] := y
    State["orbFullColor"] := PixelGetColor(x, y, "RGB")
    State["statusText"] := "Stamina orb FULL color set at " x "," y
}

; --------------------------------------------------------------
; GetStaminaPercent: turns the live orb color into a 0-100 guess
; by seeing how far along it is between the remembered empty and
; full colors, channel by channel (red/green/blue), then
; averaging. If you haven't calibrated yet (-1 colors), we can't
; know anything, so we return 100 - "assume full" is the SAFE
; default here because it just means "allow running", same as
; today's script before this feature existed. It does NOT block
; mining if you skip stamina calibration entirely.
; --------------------------------------------------------------
GetStaminaPercent() {
    global State
    if (State["orbEmptyColor"] = -1 || State["orbFullColor"] = -1)
        return 100

    live := PixelGetColor(State["orbX"], State["orbY"], "RGB")

    percent := ChannelPercent(live, State["orbEmptyColor"], State["orbFullColor"], 16)  ; red
        + ChannelPercent(live, State["orbEmptyColor"], State["orbFullColor"], 8)        ; green
        + ChannelPercent(live, State["orbEmptyColor"], State["orbFullColor"], 0)        ; blue
    percent := percent / 3

    ; Clamp so noisy pixels can't report negative% or over 100%.
    if (percent < 0)
        percent := 0
    if (percent > 100)
        percent := 100
    return Round(percent)
}

; --------------------------------------------------------------
; ChannelPercent: helper for ONE color channel (red, green, or
; blue - chosen via `shift`, same bit-shift trick as ColorClose).
; Works out "live is what % of the way from empty to full?".
; Example: if empty=50, full=200, live=125, that's halfway -> 50%.
; --------------------------------------------------------------
ChannelPercent(live, empty, full, shift) {
    liveC  := (live  >> shift) & 0xFF
    emptyC := (empty >> shift) & 0xFF
    fullC  := (full  >> shift) & 0xFF

    span := fullC - emptyC
    if (span = 0)
        return 100  ; empty and full look identical on this channel - can't use it, assume full

    return ((liveC - emptyC) / span) * 100
}

; --------------------------------------------------------------
; ShouldRun: THE core min/max-stamina decision for one path step.
; A step only runs if BOTH:
;   1. You marked that specific step as "run" while recording
;      (per-coordinate control, not a single global toggle), AND
;   2. Current stamina is above the configured floor
;      (State["minRunStamina"], editable in the GUI).
; This means the bot automatically stops running once energy
; gets low, even mid-path, instead of blindly running until you
; get stuck out of energy in the open world.
; --------------------------------------------------------------
ShouldRun(step) {
    global State
    if (!step["run"])
        return false
    return GetStaminaPercent() >= State["minRunStamina"]
}
