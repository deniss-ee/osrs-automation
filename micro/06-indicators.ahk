; ============================================================
; v8 micro 06 - state watchers (Find.ahk indicator half)
;
; Combines v7 micros 06 (point presence + arrival check), 14
; (pixel-diff snapshot), and 15 (polled present/absent watcher) into
; one micro - all three are variations on "is/has something at this
; point changed," just at different time granularities (instant vs
; polled-wait vs before/after diff).
;
; WHAT IT DOES
;   F5  = WatchIndicator: waits for WATCH_COLORS to become PRESENT
;         at WATCH_X/Y (reports if it was already true on the first
;         sample vs a real transition)
;   F6  = request stop
;   F7  = WatchIndicator waiting for ABSENT instead
;   F8  = probe: BlockAtPoint - confirms a block near EXPECTED_X/Y
;         matches within POS_TOL_PX (per axis)
;   F9  = TakeSnapshot + HasChanged: snapshots SNAPSHOT_X/Y/W/H, then
;         waits up to 10s reporting the moment anything in the box
;         changes
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5/F7 - transitions are detected within POLL_MS of actually
;      happening; alreadyTrue is correctly reported when the state
;      is already right at the first sample.
;   2. F8 - moving the expected point slightly off a real block still
;      finds it (within tolerance) and reports the real found
;      position; moving it far away correctly fails.
;   3. F9 - triggers promptly when the watched box visibly changes
;      (e.g. an inventory slot filling), stays quiet when it doesn't.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "06-indicators"

; ======= EDIT THESE FOR YOUR TEST =======================================
WATCH_X := 1534
WATCH_Y := 891
WATCH_COLORS := [0x00B809]
WATCH_TOL := 5
WATCH_TIMEOUT_MS := 15000

EXPECTED_X := 1549
EXPECTED_Y := 911
BLOCK_W := 5
BLOCK_H := 5
POS_TOL_PX := 5

SNAPSHOT_X := 2099
SNAPSHOT_Y := 801
SNAPSHOT_W := 72
SNAPSHOT_H := 64
SNAPSHOT_WAIT_MS := 10000
; ==========================================================================

RunWatchPresent() {
    found := WatchIndicator(WATCH_X, WATCH_Y, WATCH_COLORS, WATCH_TOL, "present", WATCH_TIMEOUT_MS, POLL_MS_DEFAULT, &alreadyTrue)
    Say("indicators: present=" found " alreadyTrue=" alreadyTrue)
    return found
}

RunWatchAbsent() {
    found := WatchIndicator(WATCH_X, WATCH_Y, WATCH_COLORS, WATCH_TOL, "absent", WATCH_TIMEOUT_MS, POLL_MS_DEFAULT, &alreadyTrue)
    Say("indicators: absent=" found " alreadyTrue=" alreadyTrue)
}

ProbeArrival() {
    ok := BlockAtPoint(EXPECTED_X, EXPECTED_Y, WATCH_COLORS, WATCH_TOL, BLOCK_W, BLOCK_H, POS_TOL_PX, &fx, &fy, &foundColor, 40)
    if (ok)
        Say("indicators: arrived - found " HexColor(foundColor) " at " fx "," fy " (within tol of " EXPECTED_X "," EXPECTED_Y ")")
    else
        Say("indicators: NOT arrived (no match within tolerance)")
}

RunSnapshotWatch() {
    snap := TakeSnapshot(SNAPSHOT_X, SNAPSHOT_Y, SNAPSHOT_W, SNAPSHOT_H)
    Say("indicators: snapshot taken (" snap.colors.Length " samples) - watching for change up to " SNAPSHOT_WAIT_MS "ms")
    changed := WaitUntil(() => HasChanged(snap, WATCH_TOL), SNAPSHOT_WAIT_MS)
    Say("indicators: changed=" changed)
}

InstallBotHarness({
    run: RunWatchPresent,
    label: "micro06",
    probe: ProbeArrival,
    extraHotkeys: [
        {key: "F7", handler: RunWatchAbsent, label: "watch-absent"},
        {key: "F9", handler: RunSnapshotWatch, label: "snapshot-watch"}
    ]
})
