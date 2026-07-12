; ============================================================
; KeyAction.ahk
; Key-press actions (e.g. Space to confirm a "make X" dialog).
; Zero Sleep calls, matching Click.ahk - any settle delay after
; a press is the calling Phase's responsibility via Waiter.
; ============================================================

#Requires AutoHotkey v2.0

class KeyAction {
    Press(key) {
        Send("{" key "}")
    }
}
