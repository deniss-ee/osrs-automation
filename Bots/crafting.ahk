; ============================================================
; v6 Crafting bot - general-purpose (first recipe: jewelry)
;
; Loop: click a "start craft" marker, wait for the craft dialog marker
; and press Space to confirm, wait for materials to be consumed (one
; watched inventory slot going empty), bank the crafted items, restock
; two materials, repeat forever until F6.
;
; Built generic on purpose - every constant names a color/role, not
; "jewelry" specifically, so this file can be repointed at a different
; recipe by re-tuning constants alone (same spirit as motherlode2.ahk
; vs motherlode.ahk both being built from the same Lib primitives).
;
; WHAT IT DOES
;   F5  = start the full craft->bank->restock loop, forever
;   F6  = request stop (interrupts instantly, mid-find or mid-wait)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "crafting"
TrimLogOnStart()

; --- Step 2: red "start craft" marker. Corner is what was measured
; live; the center below (corner + size // 2) is what the search/click
; primitives actually need - see Lib\Find.ahk's FindFilledBlock/
; FindImage, both of which return centers, not corners. ---
CRAFT_START_COLOR := 0xFF0000
CRAFT_START_TOL := 5
CRAFT_START_W := 33
CRAFT_START_H := 33
CRAFT_START_CORNER_X := 7
CRAFT_START_CORNER_Y := 702
CRAFT_START_X := CRAFT_START_CORNER_X + CRAFT_START_W // 2
CRAFT_START_Y := CRAFT_START_CORNER_Y + CRAFT_START_H // 2
CRAFT_START_WAIT_TIMEOUT_MS := 15000

; --- Step 3/4: craft dialog marker, then press Space. No click here -
; FindImage is called directly (not FindAndClickImage) since we only
; need to confirm presence before pressing a key, not click anything. ---
CRAFT_MARKER_IMAGE_PATH := A_ScriptDir "\..\Images\craft-marker-2.png"
CRAFT_MARKER_W := 74
CRAFT_MARKER_H := 74
CRAFT_MARKER_TOL := 5
CRAFT_MARKER_TRANS_COLOR := "0x00FF00"   ; assumed - same convention as every other image
                                            ; asset in this project (sack.png, pay-dirt.png,
                                            ; etc). Not yet confirmed via direct pixel
                                            ; inspection - verify if the search misbehaves.
CRAFT_MARKER_CORNER_X := 1397
CRAFT_MARKER_CORNER_Y := 643
CRAFT_MARKER_X := CRAFT_MARKER_CORNER_X + CRAFT_MARKER_W // 2
CRAFT_MARKER_Y := CRAFT_MARKER_CORNER_Y + CRAFT_MARKER_H // 2
CRAFT_MARKER_WAIT_TIMEOUT_MS := 15000

; --- Step 5: which inventory slot to watch empty out. Recipe-specific
; (a different craft might consume from a different starting slot) -
; kept as its own named constant, not hardcoded inline, for exactly
; that reason. ---
CRAFT_CHECK_SLOT := 27
CRAFT_DONE_WAIT_TIMEOUT_MS := 300000   ; generous placeholder - crafting a full inventory
                                          ; takes a while and no real duration has been
                                          ; logged yet. Tune down once one has.

; --- Step 6: green "deposit"-side marker. ---
CRAFT_DEPOSIT_COLOR := 0x00FF00
CRAFT_DEPOSIT_TOL := 5
CRAFT_DEPOSIT_W := 33
CRAFT_DEPOSIT_H := 33
CRAFT_DEPOSIT_CORNER_X := 2419
CRAFT_DEPOSIT_CORNER_Y := 604
CRAFT_DEPOSIT_X := CRAFT_DEPOSIT_CORNER_X + CRAFT_DEPOSIT_W // 2
CRAFT_DEPOSIT_Y := CRAFT_DEPOSIT_CORNER_Y + CRAFT_DEPOSIT_H // 2
CRAFT_DEPOSIT_WAIT_TIMEOUT_MS := 15000

; --- Step 7: deposit-inventory confirm image. ---
DEPOSIT_DEFAULT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-default.png"
DEPOSIT_DEFAULT_W := 72
DEPOSIT_DEFAULT_H := 72
DEPOSIT_DEFAULT_TOL := 5
DEPOSIT_DEFAULT_TRANS_COLOR := "0x00FF00"   ; assumed, same as CRAFT_MARKER_TRANS_COLOR above
DEPOSIT_DEFAULT_CORNER_X := 1327
DEPOSIT_DEFAULT_CORNER_Y := 963
DEPOSIT_DEFAULT_X := DEPOSIT_DEFAULT_CORNER_X + DEPOSIT_DEFAULT_W // 2
DEPOSIT_DEFAULT_Y := DEPOSIT_DEFAULT_CORNER_Y + DEPOSIT_DEFAULT_H // 2
DEPOSIT_DEFAULT_WAIT_TIMEOUT_MS := 15000

; --- Step 8: two bank slots to restock from (recipe-specific, e.g. bars
; + gems for jewelry). BankSlotCenter is Lib\Inv.ahk's new bank-slot-
; grid primitive. Single unconditional click each, no fullness check -
; matches what was asked for exactly. ---
RESTOCK_SLOT_1 := 1
RESTOCK_SLOT_2 := 2

CLICK_USE_CTRL := true   ; uniform with every other bot's clicks (motherlode2 applies
                            ; this to every FindAndClickBlock/Image call regardless of
                            ; whether it's a walk-destination or a UI button)
POLL_MS := 150
SEARCH_MARGIN_PX := 40   ; same margin Lib\Find.ahk's BlockAtPoint uses around an
                            ; expected point

; Constrains a find to a small box around a known point instead of a
; whole-screen search. CRAFT_START_X/Y (~23,718) sits close enough to
; the screen edge that the naive box goes negative - ImageSearch can't
; take that, so clamp to 0.
RegionAround(cx, cy, w, h) {
    x1 := Max(0, cx - w // 2 - SEARCH_MARGIN_PX)
    y1 := Max(0, cy - h // 2 - SEARCH_MARGIN_PX)
    return [x1, y1, cx + w // 2 + SEARCH_MARGIN_PX, cy + h // 2 + SEARCH_MARGIN_PX]
}

; One full craft->bank->restock cycle. Step 1 ("start full at the
; bank") is just the assumed starting precondition, same as every
; other bot's F5 start - no code for it.
CraftCycle() {
    ; 2: click the red start-craft marker
    if (!FindAndClickBlock({
        color: CRAFT_START_COLOR, tol: CRAFT_START_TOL, blockW: CRAFT_START_W, blockH: CRAFT_START_H,
        region: RegionAround(CRAFT_START_X, CRAFT_START_Y, CRAFT_START_W, CRAFT_START_H),
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: CRAFT_START_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Craft", itemLabel: "start-craft marker"
    }))
        return false

    ; 3: wait for the craft dialog marker (no click - just confirm presence)
    region := RegionAround(CRAFT_MARKER_X, CRAFT_MARKER_Y, CRAFT_MARKER_W, CRAFT_MARKER_H)
    Say("Craft: waiting for craft dialog marker")
    found := WaitUntil(() => FindImage(region[1], region[2], region[3], region[4],
        CRAFT_MARKER_IMAGE_PATH, CRAFT_MARKER_W, CRAFT_MARKER_H, CRAFT_MARKER_TOL, CRAFT_MARKER_TRANS_COLOR, &fx, &fy),
        CRAFT_MARKER_WAIT_TIMEOUT_MS, POLL_MS)
    if (!found) {
        Say("Craft: dialog marker never appeared within " CRAFT_MARKER_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }

    ; 4: press Space to confirm
    Send("{Space}")

    ; 5: wait for the watched slot to empty (materials consumed)
    Say("Craft: waiting for slot " CRAFT_CHECK_SLOT " to empty")
    if (!WaitUntil(() => !SlotFull(CRAFT_CHECK_SLOT), CRAFT_DONE_WAIT_TIMEOUT_MS, POLL_MS)) {
        Say("Craft: slot " CRAFT_CHECK_SLOT " never emptied within " CRAFT_DONE_WAIT_TIMEOUT_MS "ms - stopping")
        return false
    }

    ; 6: click the green deposit-side marker
    if (!FindAndClickBlock({
        color: CRAFT_DEPOSIT_COLOR, tol: CRAFT_DEPOSIT_TOL, blockW: CRAFT_DEPOSIT_W, blockH: CRAFT_DEPOSIT_H,
        region: RegionAround(CRAFT_DEPOSIT_X, CRAFT_DEPOSIT_Y, CRAFT_DEPOSIT_W, CRAFT_DEPOSIT_H),
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: CRAFT_DEPOSIT_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Craft", itemLabel: "deposit-side marker"
    }))
        return false

    ; 7: wait for + click "deposit inventory"
    if (!FindAndClickImage({
        imagePath: DEPOSIT_DEFAULT_IMAGE_PATH, imageW: DEPOSIT_DEFAULT_W, imageH: DEPOSIT_DEFAULT_H,
        tol: DEPOSIT_DEFAULT_TOL, transColor: DEPOSIT_DEFAULT_TRANS_COLOR,
        region: RegionAround(DEPOSIT_DEFAULT_X, DEPOSIT_DEFAULT_Y, DEPOSIT_DEFAULT_W, DEPOSIT_DEFAULT_H),
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: DEPOSIT_DEFAULT_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Craft", itemLabel: "deposit-inventory button"
    }))
        return false

    ; 8: restock - one click each on bank slots RESTOCK_SLOT_1/2
    BankSlotCenter(RESTOCK_SLOT_1, &x1, &y1)
    ClickAt(x1, y1, CLICK_USE_CTRL)
    BankSlotCenter(RESTOCK_SLOT_2, &x2, &y2)
    ClickAt(x2, y2, CLICK_USE_CTRL)

    return true
}

RunFullLoop() {
    global g_StopRequested
    g_StopRequested := false
    Say("Crafting started")

    try {
        loop {
            if (!CraftCycle()) {
                Say("Cycle failed - stopping (see log for which step)")
                break
            }
        }
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

F5:: RunFullLoop()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}
