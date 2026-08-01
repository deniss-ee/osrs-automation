; ============================================================
; Records real mouse movement to a CSV for later analysis
; (Tools\analyze-movement.ahk) - a calibration input for tuning
; HumanGlide/WanderNear's movement constants against this user's
; actual mouse behavior, instead of guessed defaults.
;
; WHAT IT DOES
;   F5  = start recording: samples MouseGetPos() at a fixed interval,
;         appends "elapsedMs,x,y" rows directly to
;         logs\movement-recording.csv (overwritten each run - move
;         the file first if you want to keep an old recording)
;   F6  = stop recording
;   F12 = exit
;
; HOW TO USE IT
;   Run F5, then move your mouse the way you'd normally play for
;   30-60s (a mix of real distances, some quick, some slow, some
;   pauses) - NOT a deliberate demo of any one style, just normal
;   use. F6 when done. Then run Tools\analyze-movement.ahk to get
;   real statistics from the recording.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "record-movement"

; ======= EDIT THESE FOR YOUR TEST =======================================
SAMPLE_INTERVAL_MS := 15
MAX_DURATION_MS := 120000   ; 2 min safety cap so a forgotten F6 doesn't run forever
OUT_PATH := A_ScriptDir "\..\logs\movement-recording.csv"
; ==========================================================================

RunRecord() {
    f := FileOpen(OUT_PATH, "w")
    f.WriteLine("elapsedMs,x,y")
    f.Close()

    Say("record-movement: recording to " OUT_PATH " - move your mouse naturally, F6 to stop")
    t0 := A_TickCount
    rows := 0
    loop {
        MouseGetPos(&x, &y)
        elapsed := A_TickCount - t0
        FileAppend(elapsed "," x "," y "`n", OUT_PATH)
        rows += 1
        if (elapsed >= MAX_DURATION_MS) {
            Say("record-movement: hit MAX_DURATION_MS safety cap - stopping")
            break
        }
        Pause(SAMPLE_INTERVAL_MS)
    }
    Say("record-movement: DONE - " rows " samples over " Round((A_TickCount - t0) / 1000, 1) "s")
    return true
}

InstallBotHarness({
    run: RunRecord,
    label: "record-movement"
})
