; ============================================================
; v8 micro 09 - Grid.ahk + Inv.ahk + grid-consuming Steps composites
;
; Combines v7 micros 12 (grid addressing), 13 (slot occupancy), 18
; (drop one slot), and 19 (verify-slots-and-drop walker) into one
; micro, plus exercises RunRestockPlan (moved here from v7's micro
; 24 since it's fundamentally a grid/bank composite, not a
; deposit-flow one).
;
; BANK_GRID (Lib\Inv.ahk) row 1 (slots 1-8) carries v7's real
; live-measured values (confirmed 2026-08-01). Rows beyond 1 are
; still unmeasured - live-measure a real second bank row before
; trusting any slot index > 8.
;
; WHAT IT DOES
;   F5  = grid addressing: moves mouse through CENTER, CORNER, and
;         logs the CellRegion box for a few inventory indices
;   F6  = request stop
;   F7  = slot occupancy: Full/Empty map of all 28 inventory slots
;         (SlotFull), logged as a grid
;   F8  = probe: DropSlot on TEST_DROP_SLOT (SlotFull before/after,
;         logged)
;   F9  = VerifySlotsAndDrop walker: classifies slots
;         VERIFY_START..VERIFY_END against KEEP_TARGET, drops
;         non-matches, re-checking the same slot after each drop -
;         ALSO use this run to eyeball real bank slot positions if
;         you're recalibrating BANK_GRID (watch where DropSlot's
;         inventory clicks land, not bank - see header note above
;         for the bank recalibration step itself)
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - logged centers/corners/regions match the real inventory
;      grid on screen.
;   2. F7 - Full/Empty map matches what's actually in the inventory.
;   3. F8 - slot goes from Full to Empty (or stays Empty if it
;      already was) after the shift-click drop; click visibly lands
;      inside the slot's cell, not dead-center every time.
;   4. F9 - walks start..end, correctly keeps matches and drops
;      non-matches, re-checks the same index after a drop (confirm
;      by watching a slot that needed two drops in a row). An EMPTY
;      slot makes the walker WAIT (it's designed to run during
;      active gathering) - so fill the test slots first, or the run
;      just times out with done=false.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "09-grid-inventory"

; ======= EDIT THESE FOR YOUR TEST =======================================
TEST_DROP_SLOT := 28

VERIFY_START := 1
VERIFY_END := 4
KEEP_TARGET := {path: IMAGES_DIR "\gold-bar.png", w: 72, h: 64, tol: 5, transColor: "0x00FF00"}
VERIFY_POLL_MS := 300
VERIFY_TIMEOUT_MS := 30000

RESTOCK_PLAN := [[1, 1], [2, 3]]
; ==========================================================================

RunGridAddressing() {
    loop 3 {
        idx := A_Index
        GridCenter(INV_GRID, idx, &cx, &cy)
        GridCorner(INV_GRID, idx, &corX, &corY)
        region := GridCellRegion(INV_GRID, idx)
        Say("grid: slot " idx " center=" cx "," cy " corner=" corX "," corY
            . " region=[" region[1] "," region[2] "]-[" region[3] "," region[4] "]")
        MouseMove(cx, cy, 0)
        Pause(600)
    }
}

RunSlotOccupancy() {
    line := ""
    loop INV_GRID.cols * INV_GRID.rows {
        line .= SlotFull(A_Index) ? "F" : "."
        if (Mod(A_Index, INV_GRID.cols) = 0)
            line .= " "
    }
    Say("slots: " line)
}

ProbeDropSlot() {
    before := SlotFull(TEST_DROP_SLOT)
    DropSlot(TEST_DROP_SLOT)
    Pause(300)
    after := SlotFull(TEST_DROP_SLOT)
    Say("drop-slot " TEST_DROP_SLOT ": before=" before " after=" after)
}

RunVerifyWalk() {
    verifyNext := VerifySlotsAndDrop({startSlot: VERIFY_START, endSlot: VERIFY_END, target: KEEP_TARGET, label: "micro09-verify"})
    done := WaitUntil(verifyNext, VERIFY_TIMEOUT_MS, VERIFY_POLL_MS)
    Say("verify-walk: done=" done)
    return done
}

RunRestock() {
    return RunRestockPlan({plan: RESTOCK_PLAN, label: "micro09-restock"})
}

InstallBotHarness({
    run: RunGridAddressing,
    label: "micro09",
    probe: ProbeDropSlot,
    extraHotkeys: [
        {key: "F7", handler: RunSlotOccupancy, label: "slot-occupancy"},
        {key: "F9", handler: RunVerifyWalk, label: "verify-walk"},
        {key: "F10", handler: RunRestock, label: "restock-plan"}
    ]
})
