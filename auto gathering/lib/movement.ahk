; ============================================================
;  movement.ahk - MOVING THE MOUSE AND CLICKING, IN ONE PLACE
; ------------------------------------------------------------
;  ELI5: Every single click the bot makes (mining, walking,
;  banking, future fishing/cooking bots) goes through THIS file.
;  Why one file? Because if you ever want to change HOW clicking
;  works (e.g. add a wiggle, or slow it down), you fix it here
;  ONCE instead of hunting through every script that clicks.
;
;  We support a few "action types" so future bots aren't stuck
;  with plain left-click only:
;    "click"       - normal left click (mining, walking)
;    "ctrlClick"   - hold Ctrl while clicking (e.g. force-run move)
;    "shiftClick"  - hold Shift while clicking (e.g. drop item)
;    "rightClick"  - right click then nothing else (open menu)
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; DoAction: the one function everything else should call to
; interact with the game. `actionType` picks which modifier key
; (if any) to hold. Mouse always moves first, then a short pause
; (so the game "sees" the cursor arrive before the click, just
; like a human would), then the click itself.
; --------------------------------------------------------------
DoAction(x, y, actionType := "click") {
    modifierDown := ""
    modifierUp := ""
    clickButton := "Left"

    if (actionType = "ctrlClick") {
        modifierDown := "{Ctrl down}"
        modifierUp := "{Ctrl up}"
    } else if (actionType = "shiftClick") {
        modifierDown := "{Shift down}"
        modifierUp := "{Shift up}"
    } else if (actionType = "rightClick") {
        clickButton := "Right"
    }

    if (modifierDown != "") {
        Send(modifierDown)
        SleepJittered(50)
    }

    MouseMove(x, y, 5)
    SleepJittered(150)
    Click(clickButton, x, y)

    if (modifierUp != "") {
        SleepJittered(50)
        Send(modifierUp)
    }
}

; --------------------------------------------------------------
; DoClick: kept as a thin alias to DoAction for backwards
; compatibility with the simple "just click here" use case (e.g.
; clicking a gathering spot) - reads clearer at call sites than
; DoAction(x, y, "click") everywhere.
; --------------------------------------------------------------
DoClick(x, y) {
    DoAction(x, y, "click")
}
