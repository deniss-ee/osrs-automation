; ============================================================
; v7 Lib\Act.ahk - click + keypress primitives
;
; ClickAt releases Ctrl/Shift ASYNCHRONOUSLY (standard #7): holding a
; key costs no real time, so ClickAt returns right after the click and
; a background timer lets go after holdMs. The guard against modifier
; bleed: every action function calls ReleasePendingModifiersNow() at
; its own start, forcing any still-pending release before new input.
;
; preDelayMs/postDelayMs (standard #8) bracket every action, route
; through Pause (F6-interruptible), default 0. settleMs/holdMs stay
; Sleep - tiny mechanical gaps, not scheduling choices. postDelayMs=0
; between ClickAt and PressKey means a true zero gap (load-bearing for
; seller's click-then-immediate-Esc).
; ============================================================

g_PendingModifierKeys := []

ClickAt(x, y, useCtrl := false, useShift := false, settleMs := 100, holdMs := 100, preDelayMs := 0, postDelayMs := 0) {
    global g_PendingModifierKeys

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    if (useCtrl)
        Send("{Ctrl down}")
    if (useShift)
        Send("{Shift down}")

    MouseMove(x, y, 5)
    Sleep(settleMs)
    Click()

    keysToRelease := []
    if (useCtrl)
        keysToRelease.Push("Ctrl")
    if (useShift)
        keysToRelease.Push("Shift")
    if (keysToRelease.Length > 0) {
        g_PendingModifierKeys := keysToRelease
        SetTimer(ReleasePendingModifiersNow, -holdMs)
    }

    if (postDelayMs > 0)
        Pause(postDelayMs)
}

; Releases any modifiers still held from a previous ClickAt and cancels
; its timer. Fired by the timer after holdMs, and defensively at the
; start of every action function - released at most once either way.
ReleasePendingModifiersNow() {
    global g_PendingModifierKeys
    if (g_PendingModifierKeys.Length = 0)
        return
    SetTimer(ReleasePendingModifiersNow, 0)
    keys := g_PendingModifierKeys
    for key in keys
        Send("{" key " up}")
    g_PendingModifierKeys := []
    LogLine("ReleasePendingModifiersNow: released " JoinMsg(keys))
}

; Raw Send-syntax key/chord: "{Space}", "{Esc}", "^+{Right}", ... -
; whatever Send() accepts. Same modifier-bleed guard as ClickAt.
PressKey(keys, preDelayMs := 0, postDelayMs := 0) {
    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    Send(keys)
    LogLine("PressKey: sent " keys)

    if (postDelayMs > 0)
        Pause(postDelayMs)
}
