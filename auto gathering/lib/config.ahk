; ============================================================
;  config.ahk - SAVING AND LOADING YOUR SETTINGS TO A FILE
; ------------------------------------------------------------
;  ELI5: When you close the script, the computer forgets
;  everything that was just in memory. This file writes all your
;  calibrated coordinates/colors/paths to a text file
;  (miner_part1.ini) on disk, so next time you open the script it
;  remembers them instead of making you redo F1-F5 every time.
;
;  INI files look like this:
;     [SectionName]
;     key=value
;  AHK has built-in IniRead/IniWrite for this format - no extra
;  libraries needed, and you can open the file in Notepad and
;  read it yourself if you're curious.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; SaveConfig: writes every calibrated value + both recorded
; paths into the INI file next to the script.
; --------------------------------------------------------------
SaveConfig() {
    global CONFIG
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global invX, invY, invDefaultColor
    global enableRun
    global toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    IniWrite(ore1X,         CONFIG, "Ore1", "x")
    IniWrite(ore1Y,         CONFIG, "Ore1", "y")
    IniWrite(ore1FullColor, CONFIG, "Ore1", "color")

    IniWrite(ore2X,         CONFIG, "Ore2", "x")
    IniWrite(ore2Y,         CONFIG, "Ore2", "y")
    IniWrite(ore2FullColor, CONFIG, "Ore2", "color")

    IniWrite(invX,              CONFIG, "Inv", "x")
    IniWrite(invY,              CONFIG, "Inv", "y")
    IniWrite(invDefaultColor,   CONFIG, "Inv", "color")

    IniWrite(enableRun,     CONFIG, "Run", "enabled")

    SavePathToIni("ToBank", toBankPath)
    SavePathToIni("BackToMine", backToMinePath)

    IniWrite(toBankTailDelay,   CONFIG, "ToBank", "tail_delay")
    IniWrite(backToMineTailDelay, CONFIG, "BackToMine", "tail_delay")
}

; --------------------------------------------------------------
; SavePathToIni: writes one recorded path (a list of click steps)
; into its own INI section, numbering each step (step1_x,
; step2_x, ...) so LoadPathFromIni can read them back in order.
; --------------------------------------------------------------
SavePathToIni(section, path) {
    global CONFIG
    IniWrite(path.Length, CONFIG, section, "count")

    i := 1
    for _, step in path {
        IniWrite(step["x"],     CONFIG, section, "step" i "_x")
        IniWrite(step["y"],     CONFIG, section, "step" i "_y")
        IniWrite(step["delay"], CONFIG, section, "step" i "_delay")
        i += 1
    }
}

; --------------------------------------------------------------
; LoadConfig: reads the INI file back into memory when the
; script starts. If the file doesn't exist yet (first run ever),
; we just leave everything at its default "not set" value.
; --------------------------------------------------------------
LoadConfig() {
    global CONFIG
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global invX, invY, invDefaultColor
    global enableRun
    global toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    if !FileExist(CONFIG)
        return

    ore1X         := Integer(IniRead(CONFIG, "Ore1", "x", 0))
    ore1Y         := Integer(IniRead(CONFIG, "Ore1", "y", 0))
    ore1FullColor := Integer(IniRead(CONFIG, "Ore1", "color", -1))

    ore2X         := Integer(IniRead(CONFIG, "Ore2", "x", 0))
    ore2Y         := Integer(IniRead(CONFIG, "Ore2", "y", 0))
    ore2FullColor := Integer(IniRead(CONFIG, "Ore2", "color", -1))

    invX              := Integer(IniRead(CONFIG, "Inv", "x", 0))
    invY              := Integer(IniRead(CONFIG, "Inv", "y", 0))
    invDefaultColor   := Integer(IniRead(CONFIG, "Inv", "color", -1))

    enableRun := Integer(IniRead(CONFIG, "Run", "enabled", 0))

    toBankPath := LoadPathFromIni("ToBank")
    backToMinePath := LoadPathFromIni("BackToMine")
    toBankTailDelay := Integer(IniRead(CONFIG, "ToBank", "tail_delay", 0))
    backToMineTailDelay := Integer(IniRead(CONFIG, "BackToMine", "tail_delay", 0))

    ShowTip("Loaded saved miner config")
    SetTimer(HideTip, -1500)
}

; --------------------------------------------------------------
; LoadPathFromIni: the reverse of SavePathToIni - reads "count",
; then step1_x/step1_y/step1_delay, step2_x/..., and so on, and
; rebuilds the array of click steps.
; --------------------------------------------------------------
LoadPathFromIni(section) {
    global CONFIG

    path := []
    count := Integer(IniRead(CONFIG, section, "count", 0))
    i := 1
    while (i <= count) {
        x := Integer(IniRead(CONFIG, section, "step" i "_x", 0))
        y := Integer(IniRead(CONFIG, section, "step" i "_y", 0))
        d := Integer(IniRead(CONFIG, section, "step" i "_delay", 250))

        if (x != 0 || y != 0)
            path.Push(Map("x", x, "y", y, "delay", d))

        i += 1
    }

    return path
}
