; ============================================================
; v8 micro 05 - image search + unified target-spec dispatch
; (Find.ahk image half)
;
; Combines v7 micros 07 (one-shot FindImage) and 16 (polled
; WaitForImage/WaitForImageGone) into one micro, plus proves the new
; FindTarget/WaitForTarget/WaitForTargetGone spec dispatch (v8-only -
; v7 had no unified spec type) against BOTH a block spec and an
; image spec, showing one call site now handles either kind.
;
; WHAT IT DOES
;   F5  = FindTarget with an IMAGE spec (deposit-bank.png at its
;         known fixed position) - one-shot, moves mouse to center
;         if found
;   F6  = request stop
;   F7  = FindTarget with a BLOCK spec (TARGET_COLORS) - same
;         dispatch function, different spec shape, proves both
;         branches share one call site
;   F8  = probe: WaitForTarget (image spec, polled) then
;         WaitForTargetGone - logs appear/disappear timing; useful
;         as a rehearsal for how the fail-safe engine's `done`
;         closures will use these
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - with Images\deposit-bank.png's real position on screen
;      (or any known fixed image), cursor moves to the found center;
;      confirm "not found" is reported cleanly when it's off-screen.
;   2. F7 - block spec search behaves like micro 04's F5, through
;      the SAME FindTarget function.
;   3. F8 - appear/disappear timing logs are sane (roughly matches
;      how long the image actually stays on/off screen).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "05-find-image"

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_TARGET := {path: IMAGES_DIR "\deposit-bank.png", w: BANK_DEPOSIT_IMAGE_W, h: BANK_DEPOSIT_IMAGE_H,
    tol: 5, transColor: "0x00FF00"}
IMAGE_REGION := BANK_DEPOSIT_IMAGE_REGION

BLOCK_TARGET := {colors: [0x00FF00, 0x00B809], tol: 5, w: 20, h: 20}

WAIT_TIMEOUT_MS := 15000
; ==========================================================================

RunImageSearch() {
    found := FindTarget(IMAGE_REGION, IMAGE_TARGET, &cx, &cy)
    if (found) {
        Say("find-image: found at " cx "," cy)
        MouseMove(cx, cy, 0)
    } else {
        Say("find-image: not found in fixed region")
    }
    return found
}

RunBlockSearch() {
    region := GameZoneRegion()
    found := FindTarget(region, BLOCK_TARGET, &cx, &cy, &foundColor)
    if (found) {
        Say("find-image: (block spec) found " HexColor(foundColor) " at " cx "," cy)
        MouseMove(cx, cy, 0)
    } else {
        Say("find-image: (block spec) not found")
    }
}

ProbeWaitCycle() {
    Say("find-image: waiting for target to APPEAR (timeout " WAIT_TIMEOUT_MS "ms)")
    appeared := WaitForTarget(IMAGE_REGION, IMAGE_TARGET, WAIT_TIMEOUT_MS, &cx, &cy)
    if (!appeared) {
        Say("find-image: never appeared - probe ending")
        return
    }
    Say("find-image: appeared at " cx "," cy " - now waiting for it to be GONE")
    gone := WaitForTargetGone(IMAGE_REGION, IMAGE_TARGET, WAIT_TIMEOUT_MS)
    Say("find-image: gone=" gone)
}

InstallBotHarness({
    run: RunImageSearch,
    label: "micro05",
    probe: ProbeWaitCycle,
    extraHotkeys: [
        {key: "F7", handler: RunBlockSearch, label: "block-spec"}
    ]
})
