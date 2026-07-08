; ============================================================
; Bank.ahk - v3 REDESIGNED
;
; Unified bank deposit/withdraw operations. Two core actions:
; 1. BankDepositAll - waits for button image, clicks it
; 2. BankWithdrawSlot - clicks one slot (settleMs before return)
; 3. BankWithdrawPlan - NEW: unified [{slot,count}] sequence
;
; v3: ctx-aware, unified withdraw shape. No more two separate
; smith/smelter patterns.
;
; Depends on: Grid.ahk (GetDepositAllButton, GetBankSlots), Images.ahk (WaitForImageNearButton), Click.ahk (HumanClick, JitterDelay), Context.ahk
; ============================================================

#Requires AutoHotkey v2.0

#Include Grid.ahk
#Include Images.ahk
#Include Click.ahk
#Include Context.ahk

; Opens-and-deposits in one call: a small settle pause, then wait
; until the Deposit All button image is actually visible near its
; known position (instead of guessing how long the walk + bank-open
; takes), click it once, then a fail-safe pause. Returns true once
; deposited, or false if the bank never visibly opened within openTimeoutMs.
;
; v3: ctx-aware; only settleMs and failsafeMs vary per script (deliberate
; per-script hand-tuning). Deposit-image parameters default but can be
; overridden if needed.
BankDepositAll(ctx, depositImg, settleMs, failsafeMs, imgW := 72, imgH := 72, openTimeoutMs := 15000, searchMargin := 20, imgOptions := "*20") {
    Sleep(JitterDelay(settleMs))

    depositBtn := GetDepositAllButton()
    if (!WaitForImageNearButton(ctx, depositBtn, depositImg, imgW, imgH, &dcx, &dcy, openTimeoutMs, searchMargin, imgOptions))
        return false

    HumanClick(dcx, dcy, depositBtn["w"], depositBtn["h"])
    Sleep(JitterDelay(failsafeMs))
    return true
}

; Withdraws one bank slot (1-8, left to right): a single left-click
; = "withdraw all" with this user's bank settings, then a settle pause.
; The settle matters - checking inventory occupancy too soon after
; a withdrawal reads stale (display hasn't updated), confirmed via
; debug logs - so pass a settleMs long enough before the caller
; re-checks occupancy.
BankWithdrawSlot(slotIndex, settleMs) {
    slot := GetBankSlots()[slotIndex]
    HumanClick(slot["x"], slot["y"], slot["w"], slot["h"])
    Sleep(JitterDelay(settleMs))
}

; NEW: Unified withdraw plan execution - replaces smelter's array-of-{slot,count}
; AND smith's two hardcoded WITHDRAW_SLOT_1_INDEX/WITHDRAW_SLOT_2_INDEX constants
; with one shape and one primitive.
;
; plan: [{slot: N, count: M}, ...] - ordered sequence, click each slot count times
; interSettleMs: pause after every click EXCEPT the last
; finalSettleMs: pause after the final click (longer, for display catchup)
;
; Example: plan=[{slot:1,count:2},{slot:2,count:1}] withdraws slot 1 twice, then slot 2 once.
BankWithdrawPlan(plan, interSettleMs, finalSettleMs) {
    totalClicks := 0
    for entry in plan
        totalClicks += entry["count"]

    clicksDone := 0
    for entry in plan {
        loop entry["count"] {
            clicksDone += 1
            settle := (clicksDone = totalClicks) ? finalSettleMs : interSettleMs
            BankWithdrawSlot(entry["slot"], settle)
        }
    }
}
