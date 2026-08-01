; ============================================================
; v8 micro 03 - click-jitter hard guarantee (Act.ahk click half)
;
; Combines v7 micros 08 (ClickAt/settle/hold/pre/post-delay) and 09
; (PressKey) into one micro, PLUS the new proof v7 never had: a
; scatter test that calls JitterInCell many times against a drawn
; target cell and asserts every single offset lands inside the
; cell's own bounds. v7 had no such test - the -1 sentinel /flat
; 40px fallback bug on TravelToPoint's pin was found by code
; reading, not by any test catching it live. This micro is the
; regression guard against that class of bug recurring.
;
; WHAT IT DOES
;   F5  = scatter test: call JitterInCell against SCATTER_TARGET
;         SCATTER_COUNT times (no real mouse movement - this tests
;         the offset MATH, fast and repeatable), log every offset,
;         FAIL loudly if any single offset falls outside the
;         target's own w/h bounds. This is the hard-guarantee proof.
;   F6  = request stop
;   F8  = probe: LIVE_CLICK_COUNT real ClickAt calls onto
;         SCATTER_TARGET so you can watch the cursor actually land
;         inside the cell each time (left-click, settle/hold visible)
;   F7  = one right-click via ClickAt(target, {button:"right"}) then
;         Esc - proves the single click prologue handles both
;         buttons (no separate right-click code path exists anymore)
;   F9  = PressKey test: plain Send, a chord, and the
;         confirm-marker-then-immediate-Esc pattern (needs
;         Images\deposit-bank.png on screen to see the marker
;         confirm step do anything meaningful - safe to run without
;         it, the Esc still sends)
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - log ends with "SCATTER: PASS (N/N offsets in-cell)" -
;      any FAIL line means the hard guarantee is broken, stop and
;      fix before continuing to micro 04.
;   2. F8 - watch the cursor: every click visibly lands somewhere
;      inside the drawn/expected cell area, never outside it, never
;      the exact same pixel twice.
;   3. F7 - right-click fires (context menu opens if run over a
;      real UI element), Esc closes it.
;   4. F9 - chord/plain sends work, no stuck modifiers after.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "03-click-jitter"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Corner-measured, per standard #2 - top-left, not center.
SCATTER_TARGET_CORNER_X := 809
SCATTER_TARGET_CORNER_Y := 344
SCATTER_TARGET_W := 80
SCATTER_TARGET_H := 60
SCATTER_COUNT := 100

LIVE_CLICK_COUNT := 5
; ==========================================================================

SCATTER_TARGET_X := SCATTER_TARGET_CORNER_X + SCATTER_TARGET_W / 2
SCATTER_TARGET_Y := SCATTER_TARGET_CORNER_Y + SCATTER_TARGET_H / 2

RunScatterTest() {
    target := ClickTarget(SCATTER_TARGET_X, SCATTER_TARGET_Y, SCATTER_TARGET_W, SCATTER_TARGET_H)
    x1 := target.x - target.w / 2
    x2 := target.x + target.w / 2
    y1 := target.y - target.h / 2
    y2 := target.y + target.h / 2

    passCount := 0
    loop SCATTER_COUNT {
        JitterInCell(target, &jx, &jy)
        inBounds := (jx >= x1 && jx <= x2 && jy >= y1 && jy <= y2)
        if (inBounds)
            passCount += 1
        else
            Say("SCATTER: FAIL offset (" jx "," jy ") outside cell [" Round(x1) "," Round(y1) "]-[" Round(x2) "," Round(y2) "]")
        LogLine("scatter " A_Index ": (" jx "," jy ") inBounds=" inBounds)
    }

    verdict := (passCount = SCATTER_COUNT) ? "PASS" : "FAIL"
    Say("SCATTER: " verdict " (" passCount "/" SCATTER_COUNT " offsets in-cell)")
    return (passCount = SCATTER_COUNT)
}

ProbeLiveClicks() {
    target := ClickTarget(SCATTER_TARGET_X, SCATTER_TARGET_Y, SCATTER_TARGET_W, SCATTER_TARGET_H)
    loop LIVE_CLICK_COUNT {
        ClickAt(target)
        Say("live-click " A_Index "/" LIVE_CLICK_COUNT " done")
        Pause(400)
    }
}

RunRightClick() {
    target := ClickTarget(SCATTER_TARGET_X, SCATTER_TARGET_Y, SCATTER_TARGET_W, SCATTER_TARGET_H)
    ClickAt(target, {button: "right"})
    Pause(300)
    PressKey("{Esc}")
    Say("right-click: fired + Esc sent")
}

RunPressKeyTest() {
    PressKey("a")
    Pause(200)
    PressKey("^c")
    Pause(200)

    found := WaitForImage(0, 0, A_ScreenWidth, A_ScreenHeight,
        IMAGES_DIR "\deposit-bank.png", 72, 72, 5, "0x00FF00", 500, 100, &cx, &cy)
    if (found) {
        Say("press-key: marker confirmed at " cx "," cy " - sending immediate Esc")
        PressKey("{Esc}")
    } else {
        Say("press-key: marker not on screen (expected if not testing near a bank) - sending Esc anyway")
        PressKey("{Esc}")
    }
}

InstallBotHarness({
    run: RunScatterTest,
    label: "micro03",
    probe: ProbeLiveClicks,
    extraHotkeys: [
        {key: "F7", handler: RunRightClick, label: "right-click"},
        {key: "F9", handler: RunPressKeyTest, label: "press-key"}
    ]
})
