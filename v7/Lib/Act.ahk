; ============================================================
; v7 Lib\Act.ahk - the click primitive
;
; Port of v6 Lib\Act.ahk's ClickAt, with two confirmed contract changes
; from the v7 plan/live testing:
;
; 1. settleMs/holdMs are real parameters (v6 had them as file-local
;    statics, not caller-configurable - a confirmed anti-pattern). Same
;    defaults (100/100) so nothing changes unless a caller opts in.
;
; 2. holdMs no longer blocks the caller (2026-07-22, live finding on
;    micro 08): holding a physical Ctrl/Shift key doesn't cost real
;    time - you can do something else while your finger holds it down.
;    v6's ClickAt (and this file's first v7 draft) blocked synchronously
;    for holdMs before returning, meaning every Ctrl/Shift click added
;    holdMs of dead time to the bot loop for no real reason. Now the
;    modifier is released by a background timer after holdMs, and
;    ClickAt returns immediately after the click.
;
;    This creates a real risk: if the NEXT action starts before that
;    background release fires, Windows still sees the modifier key
;    down, so an unrelated plain click could silently become
;    Ctrl/Shift-modified too. The guard: g_PendingModifierKeys tracks
;    which keys a just-fired ClickAt is waiting to release; every
;    ClickAt call (and any future action function - PressKey, etc.)
;    calls ReleasePendingModifiersNow() at its own start, which forces
;    an early release + cancels the pending timer if one is still
;    outstanding. So a modifier is never held longer than holdMs, AND
;    is always guaranteed released before any later action's own input
;    is sent - the timer is just how it happens WITHOUT blocking the
;    caller when nothing else needs to run in between.
;
; Also adds the universal preDelayMs/postDelayMs pair every action
; function gets (spec req: every click/keypress/game-affecting action
; exposes its own pre/post delay, default 0 = no-op). These route
; through Pause (interruptible, F6 lands mid-delay) - unlike settleMs,
; which stays Sleep, since it's a tiny, load-bearing mechanical gap
; (see below), not a caller's scheduling choice. postDelayMs runs right
; after Click() and does NOT wait for the async modifier release -
; that release is now understood to cost nothing, so nothing should
; block on it.
;
; useShift (2026-07-21 in v6, motherlode2's gem-drop step): same
; down/hold/up mechanics as useCtrl, for the same client-processing-lag
; reason. Purely additive - every positional call is unaffected since
; useShift defaults false.
;
; PressKey (micro 09): raw Send-syntax key/chord primitive, replacing
; the bare Send("{Space}")/Send("{Esc}")/Send("^+{Right}") calls
; scattered across v6's crafting/smithing/seller/sudoku bots. Also
; calls ReleasePendingModifiersNow() at its own start, for the same
; modifier-bleed reason ClickAt does - a key sent right after a
; Ctrl/Shift-held click must not itself inherit that still-pending
; modifier. preDelayMs=0/postDelayMs=0 by default means PressKey right
; after ClickAt with postDelayMs=0 has zero gap between them - this is
; load-bearing for seller.ahk's click-then-immediate-Esc sequence,
; not a bug to "fix" by adding an implicit gap.
; ============================================================

g_PendingModifierKeys := []

ClickAt(x, y, useCtrl := false, useShift := false, settleMs := 100, holdMs := 100, preDelayMs := 0, postDelayMs := 0) {
    global g_PendingModifierKeys

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ; Guard: force any previous click's still-pending modifier release
    ; to happen NOW, before this click presses anything - so this click
    ; (modified or not) can never silently inherit a modifier still
    ; held from the last one.
    ReleasePendingModifiersNow()

    if (useCtrl)
        Send("{Ctrl down}")
    if (useShift)
        Send("{Shift down}")

    MouseMove(x, y, 5)
    Sleep(settleMs)
    Click()

    ; Release is deferred to a background timer, not a blocking Sleep -
    ; holding the modifier doesn't cost real time, so the caller
    ; shouldn't have to wait through holdMs just to let go of it.
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

; Releases any modifier keys still virtually held from a previous
; ClickAt's async hold-timer, and cancels that timer if it hasn't fired
; yet. Called two ways: (a) by the timer itself, naturally, once
; holdMs has elapsed; (b) defensively, at the start of the next
; action-function call, forcing an early release if the timer hasn't
; fired yet - either way, a modifier is released at most once and
; never bleeds into an action that didn't ask for it.
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

; Raw Send-syntax key/chord: "{Space}", "{Esc}", "^+{Right}", etc. -
; whatever AHK's Send() itself accepts, unchanged. Guards against
; modifier bleed the same way ClickAt does (see file header).
PressKey(keys, preDelayMs := 0, postDelayMs := 0) {
    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    Send(keys)
    LogLine("PressKey: sent " keys)

    if (postDelayMs > 0)
        Pause(postDelayMs)
}
