; ============================================================
; Bank.ahk
; The one bank interaction surface every bot should use -
; direct analog of lib/Bank.ahk's BankDepositAll/BankWithdrawPlan/
; BankWithdrawSlot, already used correctly (not inlined) by
; miner/cooker/smith/smelter. Motherlode is the legacy outlier
; that inlines its own bank flow; v4 does not reproduce that -
; Bots/Motherlode's DepositBankPhase goes through this class too.
; ============================================================

#Requires AutoHotkey v2.0

class Bank {
    ; slotLayout: {firstX, firstY, pitchX, slotW, slotH} - slot 1's TOP-LEFT
    ; corner, one row of slots at pitchX spacing (cell width + gap). Optional
    ; ("") for bots that never withdraw by slot.
    __New(chestAnchor, depositAllAnchor, clicker, slotLayout := "") {
        this._chestAnchor := chestAnchor           ; a DynamicTarget or StaticAnchor
        this._depositAllAnchor := depositAllAnchor  ; a StaticAnchor (usually ImageAnchor)
        this._clicker := clicker
        this._slotLayout := slotLayout
    }

    ; Clicks the bank chest/booth. Returns the coords clicked via out-params
    ; so the caller can log/verify.
    OpenChest(&x, &y) {
        if (!this._chestAnchor.Find(&x, &y))
            return false
        this._clicker.ClickAt(x, y)
        return true
    }

    ; Waits for the deposit interface, then clicks "deposit all".
    DepositAll(waiter, profile, pollKey, timeoutMs) {
        if (!this._depositAllAnchor.WaitFor(waiter, profile, pollKey, timeoutMs, &x, &y))
            return false
        this._clicker.ClickAt(x, y)
        return true
    }

    ; Computes a bank slot's center by its 1-based index (single row,
    ; pitchX spacing) via out-params - pure coordinate math, no click.
    ; Unlike OpenChest/DepositAll, this doesn't click itself: a withdraw
    ; click needs a settle delay + optional Ctrl-hold like every other
    ; click in the framework, which requires ctx/waiter - so the caller's
    ; own _Click(ctx,x,y) helper does the actual clicking.
    WithdrawSlot(slotIndex, &x, &y) {
        l := this._slotLayout
        x := l["firstX"] + (slotIndex - 1) * l["pitchX"] + l["slotW"] // 2
        y := l["firstY"] + l["slotH"] // 2
    }

    WithdrawPlan(plan) {
        throw Error("Bank.WithdrawPlan not yet implemented - ported from lib/Bank.ahk in Phase 5")
    }
}
