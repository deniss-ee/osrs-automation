; ============================================================
;  failsafe.ahk - "PLEASE DON'T LET THE BOT DO SOMETHING DUMB"
; ------------------------------------------------------------
;  ELI5: Bots can break in annoying ways - get stuck walking into
;  a wall forever, click off-screen because you calibrated wrong,
;  or just look exactly like a robot because every click takes
;  EXACTLY the same amount of time. This file is a small toolbox
;  of safety nets for all of that.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; SleepJittered: like the built-in Sleep(), but adds a small
; random +/- wobble (State["jitterPercent"]) so delays aren't
; perfectly identical every single time. Real humans never wait
; EXACTLY 150ms between moving the mouse and clicking - adding a
; little randomness is a cheap, simple way to look less robotic.
; --------------------------------------------------------------
SleepJittered(baseMs) {
    global State
    pct := State["jitterPercent"]
    ; Random(-pct, pct) gives a random whole number between -pct and pct.
    wobble := Random(-pct, pct) / 100
    actualMs := Round(baseMs * (1 + wobble))
    if (actualMs < 0)
        actualMs := 0
    Sleep(actualMs)
}

; --------------------------------------------------------------
; IsCoordOnScreen: checks a calibrated x/y is actually within the
; bounds of your screen. Without this, a misclick during
; calibration (e.g. clicking a second monitor) would silently
; save a bad coordinate and the bot would click into nothing
; forever without any error.
; --------------------------------------------------------------
IsCoordOnScreen(x, y) {
    return (x >= 0 && y >= 0 && x <= A_ScreenWidth && y <= A_ScreenHeight)
}

; --------------------------------------------------------------
; ValidateCoordOrWarn: wraps the check above with a popup so
; calibration hotkeys (F1, F2, F3...) can call this right after
; sampling a coordinate and immediately tell you if something
; looks wrong, instead of failing silently hours later.
; Returns true if the coordinate is fine to use.
; --------------------------------------------------------------
ValidateCoordOrWarn(x, y, label) {
    if (IsCoordOnScreen(x, y))
        return true

    MsgBox("Warning: " label " coordinate (" x "," y ") looks like it's "
        . "outside your screen (" A_ScreenWidth "x" A_ScreenHeight "). "
        . "Did you click on the wrong monitor?", "Failsafe: bad coordinate", 48)
    return false
}

; --------------------------------------------------------------
; EstimatePathDuration: adds up a path's step delays + tail delay
; so we know roughly "how long should this take". Used by
; PlayPath (in paths.ahk) to detect a stuck path - if actual time
; taken blows way past this estimate, something is wrong (maybe
; the character got stuck on terrain) and we should stop instead
; of clicking forever into the void.
; --------------------------------------------------------------
EstimatePathDuration(path, tailDelay) {
    total := tailDelay
    for step in path
        total += step["delay"]
    return total
}

; --------------------------------------------------------------
; CheckPanicCorner: call this periodically (e.g. once per main
; loop tick) - if the user has thrown the mouse into the very
; top-left corner of the screen, treat it as an emergency stop.
; This is a very old, very common AHK botting convention: corners
; are places your mouse never naturally ends up mid-game, so
; parking it there on purpose is an unmistakable "STOP NOW".
; --------------------------------------------------------------
CheckPanicCorner() {
    MouseGetPos(&x, &y)
    return (x <= 2 && y <= 2)
}
