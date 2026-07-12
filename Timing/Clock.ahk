; ============================================================
; Clock.ahk
; Pure time source + cooldown tracking, no side effects (never
; calls Sleep). Exists separately from Waiter so "has enough
; time passed since X" can be checked without blocking - e.g.
; a Phase checking a cooldown before deciding whether to click
; again, without stalling the tick loop.
; ============================================================

#Requires AutoHotkey v2.0

class Clock {
    Now() => A_TickCount

    ; True once at least ms have elapsed since sinceTick.
    Elapsed(sinceTick, ms) => (A_TickCount - sinceTick) >= ms

    Remaining(sinceTick, ms) => Max(0, ms - (A_TickCount - sinceTick))
}
