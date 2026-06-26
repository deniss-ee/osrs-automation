; ============================================================
;  Bank.ahk
;  The two bank operations every gathering/processing script
;  shares: "open the bank and deposit everything" and "withdraw
;  one bank slot". These used to be copy-pasted into each script's
;  BankPhase, which let the delay constants drift apart over time -
;  here they live in ONE place so every script's banking behaves
;  identically by construction. Anything that legitimately differs
;  per script (the settle/failsafe pauses, which bank slot) is a
;  parameter, not a hardcoded value.
;
;  Depends on: Grid.ahk (GetDepositAllButton, GetBankSlots),
;  Images.ahk (WaitForImageNearButton), Click.ahk (HumanClick,
;  JitterDelay).
; ============================================================

#Include Grid.ahk
#Include Images.ahk
#Include Click.ahk

; Opens-and-deposits in one call: a small settle pause, then wait
; until the Deposit All button image is actually visible near its
; known position (instead of guessing how long the walk + bank-open
; takes), click it once (no right-click menu), then a fail-safe
; pause. Returns true once deposited, or false if the bank never
; visibly opened within openTimeoutMs - the caller decides how to
; react to false (stop, retry, log).
;
; Only settleMs and failsafeMs vary per script (deliberate per-
; script hand-tuning); the deposit-image parameters are identical
; everywhere today, so they default - pass overrides only if a
; future script uses a different button image/size.
BankDepositAll(depositImg, settleMs, failsafeMs, imgW := 72, imgH := 72, openTimeoutMs := 15000, searchMargin := 20, imgOptions := "*20") {
    ; Small settle before we even start polling - not a substitute
    ; for detecting the bank is open, just a brief buffer so we
    ; don't start checking the very same instant as the path's last
    ; click / the bank-open click.
    Sleep(JitterDelay(settleMs))

    depositBtn := GetDepositAllButton()
    if (!WaitForImageNearButton(depositBtn, depositImg, imgW, imgH, &dcx, &dcy, openTimeoutMs, searchMargin, imgOptions))
        return false

    ; Deposit everything - one left-click on where the button was
    ; actually found.
    HumanClick(dcx, dcy, depositBtn["w"], depositBtn["h"])
    ; Fail-safe pause after detecting AND clicking - applies every
    ; time, even if the button was visible the instant we started
    ; polling, same as the settle delay above.
    Sleep(JitterDelay(failsafeMs))
    return true
}

; Withdraws one bank slot (1-8, left to right - see GetBankSlots):
; a single left-click = "withdraw all" with this user's bank
; settings, then a settle pause. The settle matters - checking
; "is the last inventory slot occupied" too soon after a withdrawal
; click can read stale (the inventory display hadn't finished
; updating yet), confirmed via the smith/smelter debug logs - so
; pass a settleMs long enough for the display to catch up before
; the caller re-checks occupancy or fires another click.
BankWithdrawSlot(slotIndex, settleMs) {
    slot := GetBankSlots()[slotIndex]
    HumanClick(slot["x"], slot["y"], slot["w"], slot["h"])
    Sleep(JitterDelay(settleMs))
}
