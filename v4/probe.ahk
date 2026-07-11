#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; Logs the exact combat-indicator pixel's color every 1s automatically -
; no hotkey needed. Move the mouse near [2135,1265] to visually confirm
; what's there while this runs (a tooltip could appear under the cursor
; and change the color at that point, which is itself worth knowing).
logPath := A_ScriptDir "\probe_out.txt"

SetTimer(DoScan, 1000)
DoScan()

DoScan() {
    global logPath
    c := PixelGetColor(2135, 1265, "RGB")
    MouseGetPos(&mx, &my)
    FileAppend("[" A_Hour ":" A_Min ":" A_Sec "] Indicator [2135,1265]=" Format("0x{:06X}", c) " | Mouse=[" mx "," my "]`n", logPath)
}

F12:: ExitApp()
