; ============================================================
;  ConfigStore.ahk
;  Generic INI read/write helpers. This file has no idea what
;  an "ore" or a "bank" is - it only knows how to persist a
;  coordinate, a color, a region, or a recorded path under
;  whatever section/key names the calling script chooses.
;  No dependencies on any other lib file.
; ============================================================

; ---- Coordinates ----

SaveCoord(configFile, section, key, x, y) {
    IniWrite(x, configFile, section, key "_x")
    IniWrite(y, configFile, section, key "_y")
}

; Returns [x, y]. Missing values fall back to defaultX/defaultY.
LoadCoord(configFile, section, key, defaultX := 0, defaultY := 0) {
    x := Integer(IniRead(configFile, section, key "_x", defaultX))
    y := Integer(IniRead(configFile, section, key "_y", defaultY))
    return [x, y]
}

; ---- Flags (plain on/off settings, e.g. a run-mode switch) ----

SaveFlag(configFile, section, key, value) {
    IniWrite(value ? 1 : 0, configFile, section, key)
}

LoadFlag(configFile, section, key, default := false) {
    return Integer(IniRead(configFile, section, key, default ? 1 : 0)) = 1
}

; ---- Numbers (any numeric tunable - color tolerance, slot indices, wait times) ----

SaveNumber(configFile, section, key, value) {
    IniWrite(value, configFile, section, key)
}

LoadNumber(configFile, section, key, default := 0) {
    return Number(IniRead(configFile, section, key, default))
}

; ---- Strings (plain text tunables, e.g. a confirm-dialog key name) ----

SaveString(configFile, section, key, value) {
    IniWrite(value, configFile, section, key)
}

LoadString(configFile, section, key, default := "") {
    return IniRead(configFile, section, key, default)
}

; ---- Colors ----

SaveColor(configFile, section, key, color) {
    IniWrite(color, configFile, section, key)
}

; -1 is this codebase's "not calibrated yet" sentinel.
LoadColor(configFile, section, key, defaultColor := -1) {
    return Integer(IniRead(configFile, section, key, defaultColor))
}

; ---- Color-tagged coordinate lists (e.g. several ore spots) ----
; Each entry is a Map: {x, y, color}. Order is preserved on
; load - callers that treat earlier entries as higher priority
; (e.g. "check spot 1 before spot 2") can rely on that.

SaveColorPointList(configFile, section, points) {
    IniWrite(points.Length, configFile, section, "count")
    for i, p in points {
        IniWrite(p["x"], configFile, section, "point" i "_x")
        IniWrite(p["y"], configFile, section, "point" i "_y")
        IniWrite(p["color"], configFile, section, "point" i "_color")
    }
}

LoadColorPointList(configFile, section) {
    count := Integer(IniRead(configFile, section, "count", 0))
    points := []
    loop count {
        i := A_Index
        x := Integer(IniRead(configFile, section, "point" i "_x", 0))
        y := Integer(IniRead(configFile, section, "point" i "_y", 0))
        color := Integer(IniRead(configFile, section, "point" i "_color", -1))
        points.Push(Map("x", x, "y", y, "color", color))
    }
    return points
}

; ---- Regions (rectangles defined by two corners) ----

SaveRegion(configFile, section, x1, y1, x2, y2) {
    IniWrite(x1, configFile, section, "x1")
    IniWrite(y1, configFile, section, "y1")
    IniWrite(x2, configFile, section, "x2")
    IniWrite(y2, configFile, section, "y2")
}

; Returns [x1, y1, x2, y2].
LoadRegion(configFile, section, defaultX1 := 0, defaultY1 := 0, defaultX2 := 0, defaultY2 := 0) {
    x1 := Integer(IniRead(configFile, section, "x1", defaultX1))
    y1 := Integer(IniRead(configFile, section, "y1", defaultY1))
    x2 := Integer(IniRead(configFile, section, "x2", defaultX2))
    y2 := Integer(IniRead(configFile, section, "y2", defaultY2))
    return [x1, y1, x2, y2]
}

; ---- Paths (the canonical record/playback format from Paths.ahk) ----
; Each step is a Map with keys: x, y, pause, button, running.
; `pause` is the wait AFTER this step's click, before the next one
; (or before the path is considered finished, for the last step) -
; there's no separate "tail delay" key, the last step's own pause
; covers that.

SavePath(configFile, section, steps) {
    IniWrite(steps.Length, configFile, section, "count")
    for i, step in steps {
        IniWrite(step["x"], configFile, section, "step" i "_x")
        IniWrite(step["y"], configFile, section, "step" i "_y")
        IniWrite(step["pause"], configFile, section, "step" i "_pause")
        IniWrite(step["button"], configFile, section, "step" i "_button")
        IniWrite(step["running"], configFile, section, "step" i "_running")
    }
}

; Returns the steps array. Missing pause/button/running fields
; default gracefully so a hand-edited INI still loads.
LoadPath(configFile, section) {
    count := Integer(IniRead(configFile, section, "count", 0))
    steps := []
    loop count {
        i := A_Index
        x := Integer(IniRead(configFile, section, "step" i "_x", 0))
        y := Integer(IniRead(configFile, section, "step" i "_y", 0))
        pause := Integer(IniRead(configFile, section, "step" i "_pause", 0))
        button := IniRead(configFile, section, "step" i "_button", "Left")
        running := Integer(IniRead(configFile, section, "step" i "_running", 0))
        steps.Push(Map("x", x, "y", y, "pause", pause, "button", button, "running", running))
    }
    return steps
}

; ---- Slot sequences (an ordered list of {slot, count} - e.g. an
; ordered bank-withdrawal plan, click bank slot N "count" times
; before moving to the next entry). Same count + indexed-key shape
; as SaveColorPointList/LoadColorPointList above. Returns [] if the
; section is absent - same "unconfigured" convention as the other
; list loaders, so a caller that wants a non-empty hardcoded default
; when nothing's been saved yet should check the result's Length
; itself rather than relying on a built-in default here.

SaveSlotSequence(configFile, section, sequence) {
    IniWrite(sequence.Length, configFile, section, "count")
    for i, entry in sequence {
        IniWrite(entry["slot"], configFile, section, "entry" i "_slot")
        IniWrite(entry["count"], configFile, section, "entry" i "_count")
    }
}

LoadSlotSequence(configFile, section) {
    count := Integer(IniRead(configFile, section, "count", 0))
    sequence := []
    loop count {
        i := A_Index
        slot := Integer(IniRead(configFile, section, "entry" i "_slot", 0))
        entryCount := Integer(IniRead(configFile, section, "entry" i "_count", 0))
        sequence.Push(Map("slot", slot, "count", entryCount))
    }
    return sequence
}
