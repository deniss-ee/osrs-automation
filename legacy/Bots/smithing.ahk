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
;   F12 = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "crafting"
TrimLogOnStart()

; --- Step 2: red "start craft" marker. X/Y is the measured top-left
; CORNER, as-is - RegionAround builds the search box directly from it,
; no center math needed here. ---
CRAFT_START_COLOR := 0xFFFF00
CRAFT_START_TOL := 0
CRAFT_START_W := 11
CRAFT_START_H := 11
CRAFT_START_X := 1568
CRAFT_START_Y := 600
CRAFT_START_WAIT_TIMEOUT_MS := 30000

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
; Measured top-left CORNER, as-is - same convention as CRAFT_START_X/Y.
CRAFT_MARKER_X := 1397
CRAFT_MARKER_Y := 643
CRAFT_MARKER_WAIT_TIMEOUT_MS := 30000

; --- Step 5: which inventory slot to watch empty out. Recipe-specific
; (a different craft might consume from a different starting slot) -
; kept as its own named constant, not hardcoded inline, for exactly
; that reason. ---
CRAFT_CHECK_SLOT := 26
CRAFT_DONE_WAIT_TIMEOUT_MS := 300000   ; generous placeholder - crafting a full inventory
                                          ; takes a while and no real duration has been
                                          ; logged yet. Tune down once one has.

; --- Step 6: green "deposit"-side marker. ---
CRAFT_DEPOSIT_COLOR := 0xFF00FF
CRAFT_DEPOSIT_TOL := 0
CRAFT_DEPOSIT_W := 21
CRAFT_DEPOSIT_H := 21
; Measured top-left CORNER, as-is - same convention as CRAFT_START_X/Y.
CRAFT_DEPOSIT_X := 902
CRAFT_DEPOSIT_Y := 779
CRAFT_DEPOSIT_WAIT_TIMEOUT_MS := 30000

; --- Step 7: deposit-inventory confirm image. ---
DEPOSIT_DEFAULT_IMAGE_PATH := A_ScriptDir "\..\Images\deposit-default.png"
DEPOSIT_DEFAULT_W := 72
DEPOSIT_DEFAULT_H := 72
DEPOSIT_DEFAULT_TOL := 5
DEPOSIT_DEFAULT_TRANS_COLOR := "0x00FF00"   ; assumed, same as CRAFT_MARKER_TRANS_COLOR above
; Measured top-left CORNER, as-is - same convention as CRAFT_START_X/Y.
DEPOSIT_DEFAULT_X := 1327
DEPOSIT_DEFAULT_Y := 963
DEPOSIT_DEFAULT_WAIT_TIMEOUT_MS := 30000

; --- Step 8: bank slots to restock from - a "withdraw plan" list of
; [slot, clicks] pairs (same shape TEMPLATES.md's Firemaking/Smelter specs
; call "for each (slot, clicks): Click [bank slot N] x clicks"). Add or
; remove entries here to change what's restocked each cycle; BankSlotCenter
; (Lib\Inv.ahk) maps slot -> screen point, no fullness check - matches
; what was asked for exactly. ---
RESTOCK_PLAN := [
    [1, 1]   ; [slot, clicks]
]

DEPOSIT_SETTLE_MS := 200   ; small pause after banking, before the loop starts again

CLICK_USE_CTRL := true   ; uniform with every other bot's clicks (motherlode2 applies
                            ; this to every FindAndClickBlock/Image call regardless of
                            ; whether it's a walk-destination or a UI button)
POLL_MS := 100
SEARCH_MARGIN_PX := 40   ; same margin Lib\Find.ahk's BlockAtPoint uses around an
                            ; expected point - passed into Lib\Steps.ahk's shared
                            ; RegionAround below (marginPx param)

; One full craft->bank->restock cycle. Step 1 ("start full at the
; bank") is just the assumed starting precondition, same as every
; other bot's F5 start - no code for it.
CraftCycle() {
    ; 2: click the red start-craft marker. clickX/Y pin the click to the
    ; measured corner's own center - the region search only confirms
    ; something matching is actually visible nearby, it doesn't relocate
    ; the click (a search region can't guarantee the match it finds is
    ; centered exactly on the real button, see Lib\Steps.ahk's clickX/Y doc).
    if (!FindAndClickBlock({
        color: CRAFT_START_COLOR, tol: CRAFT_START_TOL, blockW: CRAFT_START_W, blockH: CRAFT_START_H,
        region: RegionAround(CRAFT_START_X, CRAFT_START_Y, CRAFT_START_W, CRAFT_START_H, SEARCH_MARGIN_PX),
        clickX: CenterX(CRAFT_START_X, CRAFT_START_W), clickY: CenterY(CRAFT_START_Y, CRAFT_START_H),
        ctrl: CLICK_USE_CTRL, waitTimeoutMs: CRAFT_START_WAIT_TIMEOUT_MS, pollMs: POLL_MS,
        label: "Craft", itemLabel: "start-craft marker"
    }))
        return false

    ; 3: wait for the craft dialog marker (no click - just confirm presence)
    region := RegionAround(CRAFT_MARKER_X, CRAFT_MARKER_Y, CRAFT_MARKER_W, CRAFT_MARKER_H, SEARCH_MARGIN_PX)
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

    ; 6+7: green deposit-side marker -> deposit-inventory image, via
    ; Lib\Steps.ahk's DepositAllToBank (shared with Woodcutting/Motherlode2).
    ; No confirmCondition - crafting deposits then restocks, with no
    ; empty-check in between (that's what the following bank clicks assume).
    ; Both searches stay region-constrained via RegionAround, but the
    ; actual clicks are pinned to the measured corners' own centers via
    ; markerClickX/Y + depositClickX/Y - same reasoning as CRAFT_START above.
    if (!DepositAllToBank({
        markerColor: CRAFT_DEPOSIT_COLOR, markerTol: CRAFT_DEPOSIT_TOL,
        markerBlockW: CRAFT_DEPOSIT_W, markerBlockH: CRAFT_DEPOSIT_H,
        markerRegion: RegionAround(CRAFT_DEPOSIT_X, CRAFT_DEPOSIT_Y, CRAFT_DEPOSIT_W, CRAFT_DEPOSIT_H, SEARCH_MARGIN_PX),
        markerClickX: CenterX(CRAFT_DEPOSIT_X, CRAFT_DEPOSIT_W), markerClickY: CenterY(CRAFT_DEPOSIT_Y, CRAFT_DEPOSIT_H),
        markerWaitTimeoutMs: CRAFT_DEPOSIT_WAIT_TIMEOUT_MS, markerItemLabel: "deposit-side marker",
        depositImagePath: DEPOSIT_DEFAULT_IMAGE_PATH, depositImageW: DEPOSIT_DEFAULT_W, depositImageH: DEPOSIT_DEFAULT_H,
        depositTol: DEPOSIT_DEFAULT_TOL, depositTransColor: DEPOSIT_DEFAULT_TRANS_COLOR,
        depositRegion: RegionAround(DEPOSIT_DEFAULT_X, DEPOSIT_DEFAULT_Y, DEPOSIT_DEFAULT_W, DEPOSIT_DEFAULT_H, SEARCH_MARGIN_PX),
        depositClickX: CenterX(DEPOSIT_DEFAULT_X, DEPOSIT_DEFAULT_W), depositClickY: CenterY(DEPOSIT_DEFAULT_Y, DEPOSIT_DEFAULT_H),
        depositWaitTimeoutMs: DEPOSIT_DEFAULT_WAIT_TIMEOUT_MS, depositItemLabel: "deposit-inventory button",
        ctrl: CLICK_USE_CTRL, pollMs: POLL_MS, label: "Craft"
    }))
        return false

    ; 8: restock - Lib\Steps.ahk's shared RunRestockPlan
    RunRestockPlan(RESTOCK_PLAN, CLICK_USE_CTRL)

    Pause(DEPOSIT_SETTLE_MS)
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
; F12 (exit) is defined once in Lib\v6.ahk, shared by every bot.
