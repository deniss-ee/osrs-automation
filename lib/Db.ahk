; ============================================================
; Db.ahk
;
; Config "database" - generic typed INI accessor plus named
; composite shape helpers. Stays INI-based (human-editable,
; native AHK IniRead/IniWrite, no parser dependency) but
; collapses v2's 9 near-duplicate Save*/Load* pairs into
; one generic accessor plus structurally-distinct composite shapes.
;
; Replaces v2's ConfigStore.ahk. Key improvements:
; - One DbGet/DbSet pair instead of SaveFlag/LoadFlag/SaveNumber/LoadNumber/etc.
; - Named composite shapes (Element, Marker, Image, SlotSignature, WithdrawPlan, TargetRegion)
; - [Meta] schemaVersion for future migrations
; - All functions tolerate missing keys via defaults (partial .ini is OK)
; ============================================================

#Requires AutoHotkey v2.0

; ============================================================
; Generic typed accessor - replaces most of ConfigStore's pairs
; ============================================================

; DbGet(configFile, section, key, default, type := "auto")
; Reads a single typed value from an INI section.
; type ∈ "auto" (infer from default), "int", "num", "str", "bool", "color"
; Returns the value, or default if the key is missing.
DbGet(configFile, section, key, default, type := "auto") {
    val := IniRead(configFile, section, key, "")

    if (val = "") {
        return default
    }

    inferredType := type
    if (type = "auto") {
        if (IsInteger(default))
            inferredType := "int"
        else if (IsNumber(default))
            inferredType := "num"
        else if (IsObject(default))
            inferredType := "obj"  ; leave as-is
        else
            inferredType := "str"
    }

    switch inferredType {
        case "int":
            return Integer(val)
        case "num":
            return Number(val)
        case "bool":
            return (val = "1" || val = "true")
        case "color":
            return (SubStr(val, 1, 2) = "0x") ? Integer(val) : Integer("0x" val)
        case "str":
            return val
        default:
            return val
    }
}

; DbSet(configFile, section, key, value, type := "auto")
; Writes a single typed value to an INI section.
DbSet(configFile, section, key, value, type := "auto") {
    inferredType := type
    if (type = "auto") {
        if (IsInteger(value))
            inferredType := "int"
        else if (IsNumber(value))
            inferredType := "num"
        else
            inferredType := "str"
    }

    strVal := value
    switch inferredType {
        case "bool":
            strVal := value ? "1" : "0"
        case "color":
            strVal := Format("0x{:06X}", value & 0xFFFFFF)
        case "int", "num":
            strVal := String(value)
    }

    IniWrite(strVal, configFile, section, key)
}

; ============================================================
; Composite shape accessors (multi-key/multi-row by nature)
; ============================================================

; Point (x, y) - returns Map("x", x, "y", y)
DbGetPoint(configFile, section, key, defaultX := 0, defaultY := 0) {
    x := DbGet(configFile, section, key "_x", defaultX, "int")
    y := DbGet(configFile, section, key "_y", defaultY, "int")
    return Map("x", x, "y", y)
}

DbSetPoint(configFile, section, key, x, y) {
    DbSet(configFile, section, key "_x", x, "int")
    DbSet(configFile, section, key "_y", y, "int")
}

; Region (x1, y1, x2, y2) - returns Map("x1", x1, "y1", y1, "x2", x2, "y2", y2)
DbGetRegion(configFile, section, defaultX1 := 0, defaultY1 := 0, defaultX2 := 0, defaultY2 := 0) {
    x1 := DbGet(configFile, section, "x1", defaultX1, "int")
    y1 := DbGet(configFile, section, "y1", defaultY1, "int")
    x2 := DbGet(configFile, section, "x2", defaultX2, "int")
    y2 := DbGet(configFile, section, "y2", defaultY2, "int")
    return Map("x1", x1, "y1", y1, "x2", x2, "y2", y2)
}

DbSetRegion(configFile, section, x1, y1, x2, y2) {
    DbSet(configFile, section, "x1", x1, "int")
    DbSet(configFile, section, "y1", y1, "int")
    DbSet(configFile, section, "x2", x2, "int")
    DbSet(configFile, section, "y2", y2, "int")
}

; Point list [{x, y, color}, ...] - for ore spots, slot calibration points, etc.
DbGetPointList(configFile, section) {
    result := []
    count := DbGet(configFile, section, "count", 0, "int")
    loop count {
        i := A_Index
        x := DbGet(configFile, section, "point" i "_x", 0, "int")
        y := DbGet(configFile, section, "point" i "_y", 0, "int")
        color := DbGet(configFile, section, "point" i "_color", -1, "color")
        result.Push(Map("x", x, "y", y, "color", color))
    }
    return result
}

DbSetPointList(configFile, section, points) {
    DbSet(configFile, section, "count", points.Length, "int")
    for i, p in points {
        DbSet(configFile, section, "point" i "_x", p["x"], "int")
        DbSet(configFile, section, "point" i "_y", p["y"], "int")
        DbSet(configFile, section, "point" i "_color", p["color"], "color")
    }
}

; Element (x, y, w, h) - named UI region
DbGetElement(configFile, section) {
    x := DbGet(configFile, section, "x", 0, "int")
    y := DbGet(configFile, section, "y", 0, "int")
    w := DbGet(configFile, section, "w", 0, "int")
    h := DbGet(configFile, section, "h", 0, "int")
    return Map("x", x, "y", y, "w", w, "h", h)
}

DbSetElement(configFile, section, x, y, w, h) {
    DbSet(configFile, section, "x", x, "int")
    DbSet(configFile, section, "y", y, "int")
    DbSet(configFile, section, "w", w, "int")
    DbSet(configFile, section, "h", h, "int")
}

; Marker (color + search region + click offsets)
DbGetMarker(configFile, section) {
    color := DbGet(configFile, section, "color", -1, "color")
    tolerance := DbGet(configFile, section, "tolerance", 20, "int")
    x1 := DbGet(configFile, section, "x1", 0, "int")
    y1 := DbGet(configFile, section, "y1", 0, "int")
    x2 := DbGet(configFile, section, "x2", 0, "int")
    y2 := DbGet(configFile, section, "y2", 0, "int")
    clickOffsetX := DbGet(configFile, section, "clickOffsetX", 0, "int")
    clickOffsetY := DbGet(configFile, section, "clickOffsetY", 0, "int")
    return Map("color", color, "tolerance", tolerance, "x1", x1, "y1", y1, "x2", x2, "y2", y2, "clickOffsetX", clickOffsetX, "clickOffsetY", clickOffsetY)
}

DbSetMarker(configFile, section, color, tolerance, x1, y1, x2, y2, clickOffsetX := 0, clickOffsetY := 0) {
    DbSet(configFile, section, "color", color, "color")
    DbSet(configFile, section, "tolerance", tolerance, "int")
    DbSet(configFile, section, "x1", x1, "int")
    DbSet(configFile, section, "y1", y1, "int")
    DbSet(configFile, section, "x2", x2, "int")
    DbSet(configFile, section, "y2", y2, "int")
    DbSet(configFile, section, "clickOffsetX", clickOffsetX, "int")
    DbSet(configFile, section, "clickOffsetY", clickOffsetY, "int")
}

; Image spec {file, w, h, options, x1, y1, x2, y2}
DbGetImage(configFile, section) {
    file := DbGet(configFile, section, "file", "", "str")
    w := DbGet(configFile, section, "w", 0, "int")
    h := DbGet(configFile, section, "h", 0, "int")
    options := DbGet(configFile, section, "options", "", "str")
    x1 := DbGet(configFile, section, "x1", 0, "int")
    y1 := DbGet(configFile, section, "y1", 0, "int")
    x2 := DbGet(configFile, section, "x2", 0, "int")
    y2 := DbGet(configFile, section, "y2", 0, "int")
    return Map("file", file, "w", w, "h", h, "options", options, "x1", x1, "y1", y1, "x2", x2, "y2", y2)
}

DbSetImage(configFile, section, file, w, h, options, x1, y1, x2, y2) {
    DbSet(configFile, section, "file", file, "str")
    DbSet(configFile, section, "w", w, "int")
    DbSet(configFile, section, "h", h, "int")
    DbSet(configFile, section, "options", options, "str")
    DbSet(configFile, section, "x1", x1, "int")
    DbSet(configFile, section, "y1", y1, "int")
    DbSet(configFile, section, "x2", x2, "int")
    DbSet(configFile, section, "y2", y2, "int")
}

; Slot signature {slot, points:[{x, y, color}]}
DbGetSlotSignature(configFile, section) {
    slot := DbGet(configFile, section, "slot", 0, "int")
    count := DbGet(configFile, section, "count", 0, "int")
    points := []
    loop count {
        i := A_Index
        x := DbGet(configFile, section, "point" i "_x", 0, "int")
        y := DbGet(configFile, section, "point" i "_y", 0, "int")
        color := DbGet(configFile, section, "point" i "_color", -1, "color")
        points.Push(Map("x", x, "y", y, "color", color))
    }
    return Map("slot", slot, "points", points)
}

DbSetSlotSignature(configFile, section, slotIndex, points) {
    DbSet(configFile, section, "slot", slotIndex, "int")
    DbSet(configFile, section, "count", points.Length, "int")
    for i, p in points {
        DbSet(configFile, section, "point" i "_x", p["x"], "int")
        DbSet(configFile, section, "point" i "_y", p["y"], "int")
        DbSet(configFile, section, "point" i "_color", p["color"], "color")
    }
}

; Withdraw plan [{slot, count}, ...]
DbGetWithdrawPlan(configFile, section) {
    result := []
    count := DbGet(configFile, section, "count", 0, "int")
    loop count {
        i := A_Index
        slot := DbGet(configFile, section, "entry" i "_slot", 0, "int")
        slotCount := DbGet(configFile, section, "entry" i "_count", 0, "int")
        result.Push(Map("slot", slot, "count", slotCount))
    }
    return result
}

DbSetWithdrawPlan(configFile, section, plan) {
    DbSet(configFile, section, "count", plan.Length, "int")
    for i, entry in plan {
        DbSet(configFile, section, "entry" i "_slot", entry["slot"], "int")
        DbSet(configFile, section, "entry" i "_count", entry["count"], "int")
    }
}

; Target region {color, tolerance, x1, y1, x2, y2} - for NPC/enemy targeting
DbGetTargetRegion(configFile, section) {
    color := DbGet(configFile, section, "color", -1, "color")
    tolerance := DbGet(configFile, section, "tolerance", 20, "int")
    x1 := DbGet(configFile, section, "x1", 0, "int")
    y1 := DbGet(configFile, section, "y1", 0, "int")
    x2 := DbGet(configFile, section, "x2", 0, "int")
    y2 := DbGet(configFile, section, "y2", 0, "int")
    return Map("color", color, "tolerance", tolerance, "x1", x1, "y1", y1, "x2", x2, "y2", y2)
}

DbSetTargetRegion(configFile, section, color, tolerance, x1, y1, x2, y2) {
    DbSet(configFile, section, "color", color, "color")
    DbSet(configFile, section, "tolerance", tolerance, "int")
    DbSet(configFile, section, "x1", x1, "int")
    DbSet(configFile, section, "y1", y1, "int")
    DbSet(configFile, section, "x2", x2, "int")
    DbSet(configFile, section, "y2", y2, "int")
}

; Recorded path [{x, y, pause, button, running}, ...]
DbGetPath(configFile, section) {
    result := []
    count := DbGet(configFile, section, "count", 0, "int")
    loop count {
        i := A_Index
        x := DbGet(configFile, section, "step" i "_x", 0, "int")
        y := DbGet(configFile, section, "step" i "_y", 0, "int")
        pause := DbGet(configFile, section, "step" i "_pause", 0, "int")
        button := DbGet(configFile, section, "step" i "_button", "Left", "str")
        running := DbGet(configFile, section, "step" i "_running", 0, "int")
        result.Push(Map("x", x, "y", y, "pause", pause, "button", button, "running", running))
    }
    return result
}

DbSetPath(configFile, section, steps) {
    DbSet(configFile, section, "count", steps.Length, "int")
    for i, step in steps {
        DbSet(configFile, section, "step" i "_x", step["x"], "int")
        DbSet(configFile, section, "step" i "_y", step["y"], "int")
        DbSet(configFile, section, "step" i "_pause", step["pause"], "int")
        DbSet(configFile, section, "step" i "_button", step["button"], "str")
        DbSet(configFile, section, "step" i "_running", step["running"], "int")
    }
}

; ============================================================
; Metadata/versioning
; ============================================================

; Ensure schema version is written so future migrations can detect old files
EnsureDbVersion(configFile) {
    version := DbGet(configFile, "Meta", "schemaVersion", 0, "int")
    if (version = 0) {
        DbSet(configFile, "Meta", "schemaVersion", 1, "int")
    }
}
