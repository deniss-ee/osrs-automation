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
    __New(chestAnchor, depositAllAnchor, clicker) {
        this._chestAnchor := chestAnchor           ; a DynamicTarget or StaticAnchor
        this._depositAllAnchor := depositAllAnchor  ; a StaticAnchor (usually ImageAnchor)
        this._clicker := clicker
    }

    ; Clicks the bank chest/booth. Returns the coords clicked via out-params
    ; so the caller can log/verify.
    OpenChest(&x, &y) {
        if (!this._chestAnchor.Find(&x, &y))
            return false
        this._clicker.Click(x, y)
        return true
    }

    ; Waits for the deposit interface, then clicks "deposit all".
    DepositAll(waiter, profile, pollKey, timeoutMs) {
        if (!this._depositAllAnchor.WaitFor(waiter, profile, pollKey, timeoutMs, &x, &y))
            return false
        this._clicker.Click(x, y)
        return true
    }

    WithdrawSlot(slotIndex, &x, &y) {
        throw Error("Bank.WithdrawSlot not yet implemented - ported from lib/Bank.ahk in Phase 5")
    }

    WithdrawPlan(plan) {
        throw Error("Bank.WithdrawPlan not yet implemented - ported from lib/Bank.ahk in Phase 5")
    }
}
