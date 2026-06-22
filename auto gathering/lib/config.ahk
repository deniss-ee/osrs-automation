; ============================================================
;  config.ahk - SAVING AND LOADING YOUR SETTINGS TO A FILE
; ------------------------------------------------------------
;  ELI5: When you close the script, the computer forgets
;  everything in `State` (it's just RAM). This file writes
;  `State` to a text file (.ini) on disk so next time you open
;  the script, it remembers your ore spots, paths, and stamina
;  settings instead of making you redo F1-F5 every time.
;
;  INI files look like this:
;     [SectionName]
;     key=value
;  We pick INI (not JSON) because AHK has built-in IniRead/
;  IniWrite commands - no extra libraries needed, and it's easy
;  for a beginner to open the file in Notepad and understand it.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; SaveConfig: dumps the important parts of `State` into the INI
; file at State["configPath"]. Wrapped in try/catch so a locked
; file or bad disk doesn't crash the whole bot mid-mining - it
; just shows a status message instead (this is one of the
; failsafe improvements from the plan).
; --------------------------------------------------------------
SaveConfig() {
    global State
    cfg := State["configPath"]

    try {
        ; ---- spots: write count, then spot1_x, spot1_y, ... ----
        IniWrite(State["spots"].Length, cfg, "Spots", "count")
        i := 1
        for spot in State["spots"] {
            IniWrite(spot["name"],    cfg, "Spots", "spot" i "_name")
            IniWrite(spot["x"],       cfg, "Spots", "spot" i "_x")
            IniWrite(spot["y"],       cfg, "Spots", "spot" i "_y")
            IniWrite(spot["color"],   cfg, "Spots", "spot" i "_color")
            IniWrite(spot["enabled"], cfg, "Spots", "spot" i "_enabled")
            i += 1
        }

        ; ---- inventory slot ----
        IniWrite(State["invX"],            cfg, "Inv", "x")
        IniWrite(State["invY"],            cfg, "Inv", "y")
        IniWrite(State["invDefaultColor"], cfg, "Inv", "color")

        ; ---- stamina orb calibration ----
        IniWrite(State["orbX"],          cfg, "Stamina", "x")
        IniWrite(State["orbY"],          cfg, "Stamina", "y")
        IniWrite(State["orbEmptyColor"], cfg, "Stamina", "emptyColor")
        IniWrite(State["orbFullColor"],  cfg, "Stamina", "fullColor")
        IniWrite(State["minRunStamina"], cfg, "Stamina", "minRunStamina")

        ; ---- paths (each step now also stores a "run" flag) ----
        SavePathToIni(cfg, "ToBank", State["paths"]["toBank"])
        SavePathToIni(cfg, "BackToMine", State["paths"]["backToMine"])
        IniWrite(State["pathTailDelay"]["toBank"],     cfg, "ToBank", "tail_delay")
        IniWrite(State["pathTailDelay"]["backToMine"], cfg, "BackToMine", "tail_delay")

        State["statusText"] := "Config saved"
    } catch as err {
        ; Don't crash the bot just because we couldn't save a file.
        State["statusText"] := "SAVE FAILED: " err.Message
    }
}

; --------------------------------------------------------------
; SavePathToIni: writes one recorded path (array of step Maps)
; into its own INI section. Pulled out as its own function
; because we do this exact thing twice (toBank + backToMine) -
; copy-pasting it twice would mean two places to fix bugs in.
; --------------------------------------------------------------
SavePathToIni(cfg, section, path) {
    IniWrite(path.Length, cfg, section, "count")
    i := 1
    for step in path {
        IniWrite(step["x"],     cfg, section, "step" i "_x")
        IniWrite(step["y"],     cfg, section, "step" i "_y")
        IniWrite(step["delay"], cfg, section, "step" i "_delay")
        IniWrite(step["run"],   cfg, section, "step" i "_run")
        i += 1
    }
}

; --------------------------------------------------------------
; LoadConfig: reads the INI file back into `State`. If the file
; doesn't exist yet (first run), we just leave the defaults from
; state.ahk in place - nothing to load.
; --------------------------------------------------------------
LoadConfig() {
    global State
    cfg := State["configPath"]

    if !FileExist(cfg) {
        MigrateOldConfig()
        return
    }

    try {
        ; ---- spots ----
        spots := []
        count := Integer(IniRead(cfg, "Spots", "count", 0))
        loop count {
            i := A_Index
            name := IniRead(cfg, "Spots", "spot" i "_name", "Spot " i)
            x := Integer(IniRead(cfg, "Spots", "spot" i "_x", 0))
            y := Integer(IniRead(cfg, "Spots", "spot" i "_y", 0))
            color := Integer(IniRead(cfg, "Spots", "spot" i "_color", -1))
            enabled := Integer(IniRead(cfg, "Spots", "spot" i "_enabled", 1))
            spots.Push(Map("name", name, "x", x, "y", y, "color", color, "enabled", enabled))
        }
        State["spots"] := spots

        ; ---- inventory ----
        State["invX"]            := Integer(IniRead(cfg, "Inv", "x", 0))
        State["invY"]            := Integer(IniRead(cfg, "Inv", "y", 0))
        State["invDefaultColor"] := Integer(IniRead(cfg, "Inv", "color", -1))

        ; ---- stamina orb ----
        State["orbX"]          := Integer(IniRead(cfg, "Stamina", "x", 0))
        State["orbY"]          := Integer(IniRead(cfg, "Stamina", "y", 0))
        State["orbEmptyColor"] := Integer(IniRead(cfg, "Stamina", "emptyColor", -1))
        State["orbFullColor"]  := Integer(IniRead(cfg, "Stamina", "fullColor", -1))
        State["minRunStamina"] := Integer(IniRead(cfg, "Stamina", "minRunStamina", 30))

        ; ---- paths ----
        State["paths"]["toBank"]     := LoadPathFromIni(cfg, "ToBank")
        State["paths"]["backToMine"] := LoadPathFromIni(cfg, "BackToMine")
        State["pathTailDelay"]["toBank"]     := Integer(IniRead(cfg, "ToBank", "tail_delay", 0))
        State["pathTailDelay"]["backToMine"] := Integer(IniRead(cfg, "BackToMine", "tail_delay", 0))

        State["statusText"] := "Config loaded"
    } catch as err {
        State["statusText"] := "LOAD FAILED: " err.Message
    }
}

; --------------------------------------------------------------
; LoadPathFromIni: the reverse of SavePathToIni. Defaults
; step["run"] to false if the key is missing, since old configs
; (before this rewrite) never had a "run" key at all.
; --------------------------------------------------------------
LoadPathFromIni(cfg, section) {
    path := []
    count := Integer(IniRead(cfg, section, "count", 0))
    loop count {
        i := A_Index
        x := Integer(IniRead(cfg, section, "step" i "_x", 0))
        y := Integer(IniRead(cfg, section, "step" i "_y", 0))
        d := Integer(IniRead(cfg, section, "step" i "_delay", 250))
        r := Integer(IniRead(cfg, section, "step" i "_run", 0))
        if (x != 0 || y != 0)
            path.Push(Map("x", x, "y", y, "delay", d, "run", r))
    }
    return path
}

; --------------------------------------------------------------
; MigrateOldConfig: ELI5 - if you used the OLD script before
; (miner_part1.ini with just 2 ores), this copies that
; calibration into the new format automatically so you don't
; have to redo F1-F5. It only runs once, when no new-format
; config exists yet.
; --------------------------------------------------------------
MigrateOldConfig() {
    global State
    oldCfg := A_ScriptDir "\miner_part1.ini"
    if !FileExist(oldCfg)
        return

    try {
        spots := []

        ore1Color := Integer(IniRead(oldCfg, "Ore1", "color", -1))
        if (ore1Color != -1) {
            spots.Push(Map(
                "name", "Ore 1",
                "x", Integer(IniRead(oldCfg, "Ore1", "x", 0)),
                "y", Integer(IniRead(oldCfg, "Ore1", "y", 0)),
                "color", ore1Color,
                "enabled", true))
        }

        ore2Color := Integer(IniRead(oldCfg, "Ore2", "color", -1))
        if (ore2Color != -1) {
            spots.Push(Map(
                "name", "Ore 2",
                "x", Integer(IniRead(oldCfg, "Ore2", "x", 0)),
                "y", Integer(IniRead(oldCfg, "Ore2", "y", 0)),
                "color", ore2Color,
                "enabled", true))
        }

        State["spots"] := spots
        State["invX"]            := Integer(IniRead(oldCfg, "Inv", "x", 0))
        State["invY"]            := Integer(IniRead(oldCfg, "Inv", "y", 0))
        State["invDefaultColor"] := Integer(IniRead(oldCfg, "Inv", "color", -1))

        ; old script had ONE global "run" toggle - apply it to every
        ; step of every path as a starting point. You can fine-tune
        ; per-step afterwards with F9 during re-recording, or the GUI.
        oldRun := Integer(IniRead(oldCfg, "Run", "enabled", 0))

        toBank := []
        tbCount := Integer(IniRead(oldCfg, "ToBank", "count", 0))
        loop tbCount {
            i := A_Index
            x := Integer(IniRead(oldCfg, "ToBank", "step" i "_x", 0))
            y := Integer(IniRead(oldCfg, "ToBank", "step" i "_y", 0))
            d := Integer(IniRead(oldCfg, "ToBank", "step" i "_delay", 250))
            if (x != 0 || y != 0)
                toBank.Push(Map("x", x, "y", y, "delay", d, "run", oldRun))
        }
        State["paths"]["toBank"] := toBank
        State["pathTailDelay"]["toBank"] := Integer(IniRead(oldCfg, "ToBank", "tail_delay", 0))

        backToMine := []
        btmCount := Integer(IniRead(oldCfg, "BackToMine", "count", 0))
        loop btmCount {
            i := A_Index
            x := Integer(IniRead(oldCfg, "BackToMine", "step" i "_x", 0))
            y := Integer(IniRead(oldCfg, "BackToMine", "step" i "_y", 0))
            d := Integer(IniRead(oldCfg, "BackToMine", "step" i "_delay", 250))
            if (x != 0 || y != 0)
                backToMine.Push(Map("x", x, "y", y, "delay", d, "run", oldRun))
        }
        State["paths"]["backToMine"] := backToMine
        State["pathTailDelay"]["backToMine"] := Integer(IniRead(oldCfg, "BackToMine", "tail_delay", 0))

        SaveConfig()
        State["statusText"] := "Migrated old miner_part1.ini -> new profile"
    } catch as err {
        State["statusText"] := "MIGRATION FAILED: " err.Message
    }
}
