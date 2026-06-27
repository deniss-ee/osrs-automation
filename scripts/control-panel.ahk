; ============================================================
;  control-panel.ahk
;  Tabbed GUI front-end for all 6 bots (auto-miner, auto-fisher,
;  auto-smelter, auto-smith, auto-motherlode, auto-fighter). Lets
;  you view/edit each bot's curated parameters, trigger its
;  calibration/recording actions, and start/stop it from one place.
;
;  This script never runs a bot's own phase/TaskRunner logic - it
;  only edits that bot's .ini (via the same lib\ConfigStore.ahk
;  functions the bot's own hotkeys use) and launches/closes the
;  bot's own .ahk file as a separate process. Every bot's F1-F9
;  hotkeys still work exactly as before if you run it standalone -
;  this panel is an additional front-end, not a replacement.
;
;  CAVEATS:
;   - Don't use this panel's "Record"/calibration buttons for a bot
;     while that SAME bot is also running standalone - both
;     processes would try to own the same global mouse hook
;     (~LButton/~RButton), and only one wins.
;   - Saved parameters only take effect the NEXT time that bot's
;     script (re)starts (its LoadConfig() runs once at startup) -
;     if it's already running, Stop then Start it again after
;     saving.
;   - Clicking a GUI button moves the mouse off whatever in-game
;     target you were hovering, so single-point/region captures use
;     a 3-second countdown tooltip instead of capturing instantly
;     the way the bots' own F-key hotkeys do.
;
;  Config files are NOT hardcoded here - this script reads each
;  bot's own `global CONFIG := ...` line out of its .ahk source at
;  startup, so it stays correct even if you swap which .ini a
;  script points to (e.g. auto-miner.ahk's multiple ore profiles).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\ConfigStore.ahk
#Include ..\lib\Grid.ahk
#Include ..\lib\Paths.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global AHK_EXE := "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

; ============================================================
;  BOT DESCRIPTORS - the one source of truth for what each tab
;  contains. Section/key names below must match the matching bot's
;  own LoadConfig()/hotkeys exactly (see DOCUMENTATION.md).
; ============================================================

global DESCRIPTORS := [
    Map("key", "miner", "label", "Miner", "scriptFile", "auto-miner.ahk",
        "flags", [
            Map("key", "runMode", "label", "Run mode (hold Ctrl)"),
            Map("key", "withdrawAfterDeposit", "label", "Withdraw after deposit")
        ],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20),
            Map("key", "withdrawSlotIndex", "label", "Withdraw slot index (1-8)", "type", "number", "default", 1)
        ],
        "calibrations", [
            Map("kind", "pointlist-repeatable", "section", "OreSpots", "label", "Ore spots"),
            Map("kind", "slotpoints", "section", "InventoryEmptyPoints", "label", "Empty-slot reference points"),
            Map("kind", "path", "section", "ToBank", "label", "Walk-to-bank path"),
            Map("kind", "path", "section", "BackToMine", "label", "Walk-back-to-mine path")
        ]
    ),
    Map("key", "fisher", "label", "Fisher", "scriptFile", "auto-fisher.ahk",
        "flags", [
            Map("key", "runMode", "label", "Run mode (hold Ctrl)"),
            Map("key", "withdrawAfterDeposit", "label", "Withdraw after deposit")
        ],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20),
            Map("key", "netBankSlotIndex", "label", "Net bank slot index (1-8)", "type", "number", "default", 1)
        ],
        "calibrations", [
            Map("kind", "region", "section", "FishArea", "label", "Fishing area"),
            Map("kind", "slotpoints", "section", "InventoryEmptyPoints", "label", "Empty-slot reference points"),
            Map("kind", "path", "section", "ToFishingSpot", "label", "Walk-to-fishing-spot path")
        ]
    ),
    Map("key", "smelter", "label", "Smelter", "scriptFile", "auto-smelter.ahk",
        "flags", [
            Map("key", "runMode", "label", "Run mode (hold Ctrl)"),
            Map("key", "checkPreviousSlot", "label", "Check previous slot (not last)")
        ],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20),
            Map("key", "smeltKey", "label", "Smelt confirm key (Space/1/2/3)", "type", "string", "default", "Space")
        ],
        "withdrawSequenceSection", "WithdrawSequence",
        "calibrations", [
            Map("kind", "slotpoints", "section", "InventoryEmptyPoints", "label", "Empty-slot reference points", "previousSlotFlagKey", "checkPreviousSlot"),
            Map("kind", "path", "section", "Smelt", "label", "Smelt path (furnace click only)"),
            Map("kind", "path", "section", "ToBank", "label", "Walk-to-bank path"),
            Map("kind", "path", "section", "ToSmelter", "label", "Walk-to-smelter path")
        ]
    ),
    Map("key", "smith", "label", "Smith", "scriptFile", "auto-smith.ahk",
        "flags", [
            Map("key", "runMode", "label", "Run mode (hold Ctrl)")
        ],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20),
            Map("key", "withdrawSlot1Index", "label", "Withdraw slot 1 index", "type", "number", "default", 1),
            Map("key", "withdrawSlot2Index", "label", "Withdraw slot 2 index", "type", "number", "default", 2)
        ],
        "calibrations", [
            Map("kind", "slotpoints", "section", "InventoryEmptyPoints", "label", "Empty-slot reference points"),
            Map("kind", "path", "section", "ToAnvil", "label", "Walk-to-anvil path"),
            Map("kind", "path", "section", "ToBank", "label", "Walk-to-bank path")
        ]
    ),
    Map("key", "motherlode", "label", "Motherlode", "scriptFile", "auto-motherlode.ahk",
        "flags", [
            Map("key", "runMode", "label", "Run mode (hold Ctrl)")
        ],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20),
            Map("key", "depositRunWaitMs", "label", "Deposit run wait (ms)", "type", "number", "default", 10000)
        ],
        "calibrations", [
            Map("kind", "region", "section", "MiningArea", "label", "Mining area"),
            Map("kind", "slotpoints", "section", "InventoryEmptyPoints", "label", "Empty-slot reference points"),
            Map("kind", "region", "section", "BankMarkerArea", "label", "Bank/hopper marker area"),
            Map("kind", "path", "section", "RunBack", "label", "Run-back path")
        ]
    ),
    Map("key", "fighter", "label", "Fighter", "scriptFile", "auto-fighter.ahk",
        "flags", [],
        "tunables", [
            Map("key", "colorTolerance", "label", "Color tolerance", "type", "number", "default", 20)
        ],
        "calibrations", [
            Map("kind", "region", "section", "CombatArea", "label", "Combat area"),
            Map("kind", "coord", "section", "Character", "key", "center", "label", "Character center")
        ]
    )
]

; ============================================================
;  PATH RECORDING - one shared global mouse hook, same single-
;  active-recorder rule every bot already enforces.
; ============================================================

global activeRecorder := ""
global activeRecorderConfig := ""
global activeRecorderSection := ""

Hotkey("~LButton", PanelRecordClick, "Off")
Hotkey("~RButton", PanelRecordClick, "Off")

PanelRecordClick(*) {
    global activeRecorder, activeRecorderConfig
    if (activeRecorder = "")
        return
    MouseGetPos(&mx, &my)
    button := InStr(A_ThisHotkey, "RButton") ? "Right" : "Left"
    running := LoadFlag(activeRecorderConfig, "Settings", "runMode", false) ? 1 : 0
    RecordClickStep(activeRecorder, mx, my, button, running)
}

ToggleRecordButton(cfg, section, label, btn, statusCtrl, descriptor, *) {
    global activeRecorder, activeRecorderConfig, activeRecorderSection
    if (activeRecorder != "" && activeRecorderSection = section && activeRecorderConfig = cfg) {
        steps := StopRecording(activeRecorder)
        SavePath(cfg, section, steps)
        Hotkey("~LButton", PanelRecordClick, "Off")
        Hotkey("~RButton", PanelRecordClick, "Off")
        btn.Text := "Record"
        statusCtrl.Text := BuildStatusText(cfg, descriptor)
        ShowTipFor(label " recording stopped (" steps.Length " clicks)", 1500)
        activeRecorder := ""
        activeRecorderConfig := ""
        activeRecorderSection := ""
        return
    }
    if (activeRecorder != "") {
        ShowTipFor("Finish recording " activeRecorderSection " first", 1500)
        return
    }
    activeRecorder := NewPathRecorder()
    activeRecorderConfig := cfg
    activeRecorderSection := section
    StartRecording(activeRecorder, section)
    Hotkey("~LButton", PanelRecordClick, "On")
    Hotkey("~RButton", PanelRecordClick, "On")
    btn.Text := "Stop Recording"
    ShowTipFor(label " recording started - click your route in-game, then press this button again. Don't run that bot standalone at the same time.", 3000)
}

; ============================================================
;  COUNTDOWN CAPTURE - clicking a GUI button moves the mouse off
;  the in-game target, so captures wait a few seconds (with a
;  tooltip countdown) instead of sampling instantly the way an
;  F-key press (which never moves the mouse) can.
; ============================================================

CountdownThenRun(seconds, message, onDone) {
    loop seconds {
        remaining := seconds - A_Index + 1
        ShowTip(message " - capturing in " remaining "...")
        Sleep(1000)
    }
    HideTip()
    onDone()
}

CountdownThenCapture(seconds, onCapture) {
    CountdownThenRun(seconds, "Hover the target now", CaptureNowAndCall.Bind(onCapture))
}

CaptureNowAndCall(onCapture) {
    MouseGetPos(&mx, &my)
    color := PixelGetColor(mx, my, "RGB")
    onCapture(mx, my, color)
}

; ---- Region (two corners) ----

global regionTemp := Map()

CaptureRegionCorner1(cfg, section, label, *) {
    CountdownThenCapture(3, RegionCorner1Captured.Bind(cfg, section, label))
}
RegionCorner1Captured(cfg, section, label, mx, my, color) {
    global regionTemp
    regionTemp[cfg "|" section] := Map("x", mx, "y", my)
    ShowTipFor(label " corner 1 set at " mx "," my " - now capture corner 2", 2000)
}

CaptureRegionCorner2(cfg, section, label, statusCtrl, descriptor, *) {
    CountdownThenCapture(3, RegionCorner2Captured.Bind(cfg, section, label, statusCtrl, descriptor))
}
RegionCorner2Captured(cfg, section, label, statusCtrl, descriptor, mx, my, color) {
    global regionTemp
    tempKey := cfg "|" section
    if (!regionTemp.Has(tempKey)) {
        ShowTipFor("Capture corner 1 first", 1500)
        return
    }
    c1 := regionTemp[tempKey]
    x1 := Min(c1["x"], mx), y1 := Min(c1["y"], my)
    x2 := Max(c1["x"], mx), y2 := Max(c1["y"], my)
    SaveRegion(cfg, section, x1, y1, x2, y2)
    regionTemp.Delete(tempKey)
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
    ShowTipFor(label " saved: (" x1 "," y1 ") to (" x2 "," y2 ")", 2000)
}

; ---- Single coordinate ----

CaptureCoordNow(cfg, section, key, statusCtrl, descriptor, *) {
    CountdownThenCapture(3, CoordCaptured.Bind(cfg, section, key, statusCtrl, descriptor))
}
CoordCaptured(cfg, section, key, statusCtrl, descriptor, mx, my, color) {
    SaveCoord(cfg, section, key, mx, my)
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
    ShowTipFor("Captured " key " at " mx "," my, 1500)
}

; ---- Inventory empty-slot reference points (last or previous slot) ----

CaptureSlotPoints(cfg, section, previousSlotFlagKey, statusCtrl, descriptor, *) {
    usePrevious := previousSlotFlagKey ? LoadFlag(cfg, "Settings", previousSlotFlagKey, false) : false
    CountdownThenRun(2, "Make sure the inventory is empty", SlotPointsCaptured.Bind(cfg, section, usePrevious, statusCtrl, descriptor))
}
SlotPointsCaptured(cfg, section, usePrevious, statusCtrl, descriptor) {
    slots := GetInventorySlots()
    idx := usePrevious ? slots.Length - 1 : slots.Length
    targetSlot := slots[idx]
    points := GetSlotSamplePoints(targetSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    SaveColorPointList(cfg, section, points)
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
    ShowTipFor("Empty-slot points saved (slot " idx " of " slots.Length ")", 1800)
}

; ---- Repeatable point list (ore spots) ----

CaptureAddOreSpot(cfg, section, statusCtrl, descriptor, *) {
    CountdownThenCapture(3, OreSpotCaptured.Bind(cfg, section, statusCtrl, descriptor))
}
OreSpotCaptured(cfg, section, statusCtrl, descriptor, mx, my, color) {
    spots := LoadColorPointList(cfg, section)
    spots.Push(Map("x", mx, "y", my, "color", color))
    SaveColorPointList(cfg, section, spots)
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
    ShowTipFor("Ore spot #" spots.Length " saved", 1500)
}
ClearOreSpots(cfg, section, statusCtrl, descriptor, *) {
    SaveColorPointList(cfg, section, [])
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
    ShowTipFor("Ore spots cleared", 1200)
}

; ============================================================
;  WITHDRAW-SEQUENCE SHORTHAND (smelter only): "slot:count,slot:count"
; ============================================================

TextToSlotSequence(text) {
    seq := []
    text := Trim(text)
    if (text = "")
        return seq
    for part in StrSplit(text, ",") {
        part := Trim(part)
        if (part = "")
            continue
        pieces := StrSplit(part, ":")
        if (pieces.Length < 2)
            continue
        seq.Push(Map("slot", Integer(Trim(pieces[1])), "count", Integer(Trim(pieces[2]))))
    }
    return seq
}

SlotSequenceToText(seq) {
    text := ""
    for i, entry in seq {
        if (i > 1)
            text .= ","
        text .= entry["slot"] ":" entry["count"]
    }
    return text
}

; ============================================================
;  BOT PROCESS START/STOP
; ============================================================

global runningPids := Map()

StartBotProcess(key, scriptPath, statusCtrl, *) {
    global runningPids, AHK_EXE
    if (runningPids.Has(key) && ProcessExist(runningPids[key])) {
        ShowTipFor("Already running (PID " runningPids[key] ")", 1500)
        return
    }
    if (!FileExist(AHK_EXE)) {
        ShowTipFor("AutoHotkey64.exe not found at " AHK_EXE, 2500)
        return
    }
    Run('"' AHK_EXE '" "' scriptPath '"', , , &pid)
    runningPids[key] := pid
    statusCtrl.Text := "Running (PID " pid ")"
}

StopBotProcess(key, statusCtrl, *) {
    global runningPids
    if (!runningPids.Has(key) || !ProcessExist(runningPids[key])) {
        ShowTipFor("Not currently running", 1200)
        statusCtrl.Text := "Not running"
        return
    }
    ProcessClose(runningPids[key])
    runningPids.Delete(key)
    statusCtrl.Text := "Not running"
}

; ============================================================
;  CONFIG PATH RESOLUTION - reads each bot's OWN `CONFIG :=` line
;  out of its .ahk source instead of hardcoding the .ini path here,
;  so this stays correct if the user swaps which profile a script
;  points to (e.g. auto-miner.ahk's per-ore profiles).
; ============================================================

ResolveConfigPath(scriptFile) {
    scriptPath := A_ScriptDir "\" scriptFile
    text := FileRead(scriptPath)
    if (RegExMatch(text, '\\config\\([^"]+)"', &m))
        return A_ScriptDir "\..\config\" m[1]
    return ""
}

; ============================================================
;  STATUS SUMMARY
; ============================================================

BuildStatusText(cfg, descriptor) {
    lines := []
    for calib in descriptor["calibrations"] {
        kind := calib["kind"]
        section := calib["section"]
        label := calib["label"]
        if (kind = "region") {
            r := LoadRegion(cfg, section)
            ok := !(r[1] = 0 && r[2] = 0 && r[3] = 0 && r[4] = 0)
            lines.Push((ok ? "[OK] " : "[--] ") label (ok ? " (" r[1] "," r[2] " to " r[3] "," r[4] ")" : " - not set"))
        } else if (kind = "coord") {
            c := LoadCoord(cfg, section, calib["key"])
            ok := !(c[1] = 0 && c[2] = 0)
            lines.Push((ok ? "[OK] " : "[--] ") label (ok ? " (" c[1] "," c[2] ")" : " - not set"))
        } else if (kind = "slotpoints") {
            pts := LoadColorPointList(cfg, section)
            lines.Push((pts.Length > 0 ? "[OK] " : "[--] ") label " (" pts.Length " points)")
        } else if (kind = "pointlist-repeatable") {
            pts := LoadColorPointList(cfg, section)
            lines.Push((pts.Length > 0 ? "[OK] " : "[--] ") label " (" pts.Length " saved)")
        } else if (kind = "path") {
            steps := LoadPath(cfg, section)
            lines.Push((steps.Length > 0 ? "[OK] " : "[--] ") label " (" steps.Length " steps)")
        }
    }
    text := ""
    for i, line in lines
        text .= (i > 1 ? "`n" : "") line
    return text
}

RefreshStatusClicked(cfg, statusCtrl, descriptor, *) {
    statusCtrl.Text := BuildStatusText(cfg, descriptor)
}

; ============================================================
;  PARAMETER SAVE
; ============================================================

SaveParamsClicked(cfg, descriptor, flagCtrls, tunableCtrls, seqCtrl, *) {
    for flag in descriptor["flags"] {
        chk := flagCtrls[flag["key"]]
        SaveFlag(cfg, "Settings", flag["key"], chk.Value = 1)
    }
    for tunable in descriptor["tunables"] {
        edit := tunableCtrls[tunable["key"]]
        if (tunable["type"] = "string")
            SaveString(cfg, "Tunables", tunable["key"], edit.Text)
        else
            SaveNumber(cfg, "Tunables", tunable["key"], Number(edit.Text))
    }
    if (descriptor.Has("withdrawSequenceSection") && seqCtrl != "")
        SaveSlotSequence(cfg, descriptor["withdrawSequenceSection"], TextToSlotSequence(seqCtrl.Text))
    ShowTipFor("Parameters saved to " cfg, 1800)
}

; ============================================================
;  GUI BUILD
; ============================================================

; Layout constants - one column/row rhythm reused for every tab so
; tightening these in one place keeps every label/control pair
; aligned consistently instead of drifting per-row magic numbers.
global MARGIN_X := 10
global TOP_Y := 10
global LABEL_W := 220
global CONTROL_X := MARGIN_X + LABEL_W
global BTN_H := 22
global GAP_SM := 6
global GAP_MD := 10
global ROW_FLAG := 22
global ROW_TUNABLE := 24
global ROW_CALIB := 26
global STATUS_LINE_H := 15
global CONTENT_W := 860

BuildBotTab(g, descriptor) {
    global MARGIN_X, TOP_Y, LABEL_W, CONTROL_X, BTN_H, GAP_SM, GAP_MD
    global ROW_FLAG, ROW_TUNABLE, ROW_CALIB, STATUS_LINE_H, CONTENT_W
    cfg := ResolveConfigPath(descriptor["scriptFile"])
    scriptPath := A_ScriptDir "\" descriptor["scriptFile"]
    mx := MARGIN_X
    y := TOP_Y

    g.Add("Text", "x" mx " y" y " w" CONTENT_W " h16", descriptor["label"] " - " descriptor["scriptFile"] " - " cfg)
    y += 16 + GAP_SM

    statusH := STATUS_LINE_H * descriptor["calibrations"].Length + 6
    statusCtrl := g.Add("Text", "x" mx " y" y " w" CONTENT_W " h" statusH, BuildStatusText(cfg, descriptor))
    y += statusH + GAP_SM

    refreshBtn := g.Add("Button", "x" mx " y" y " w120 h" BTN_H, "Refresh Status")
    refreshBtn.OnEvent("Click", RefreshStatusClicked.Bind(cfg, statusCtrl, descriptor))
    y += BTN_H + GAP_MD

    flagCtrls := Map()
    for flag in descriptor["flags"] {
        val := LoadFlag(cfg, "Settings", flag["key"], false)
        chk := g.Add("Checkbox", "x" mx " y" y " w400" (val ? " Checked" : ""), flag["label"])
        flagCtrls[flag["key"]] := chk
        y += ROW_FLAG
    }
    if (descriptor["flags"].Length > 0)
        y += GAP_SM

    tunableCtrls := Map()
    for tunable in descriptor["tunables"] {
        g.Add("Text", "x" mx " y" (y + 2) " w" (LABEL_W - 10), tunable["label"] ":")
        curVal := (tunable["type"] = "string")
            ? LoadString(cfg, "Tunables", tunable["key"], tunable["default"])
            : LoadNumber(cfg, "Tunables", tunable["key"], tunable["default"])
        edit := g.Add("Edit", "x" CONTROL_X " y" y " w120", String(curVal))
        tunableCtrls[tunable["key"]] := edit
        y += ROW_TUNABLE
    }

    seqCtrl := ""
    if (descriptor.Has("withdrawSequenceSection")) {
        g.Add("Text", "x" mx " y" (y + 2) " w" CONTENT_W, "Withdraw sequence (slot:count,slot:count - e.g. 1:2,2:1; empty = use script's built-in default):")
        y += 18 + GAP_SM
        curSeq := SlotSequenceToText(LoadSlotSequence(cfg, descriptor["withdrawSequenceSection"]))
        seqCtrl := g.Add("Edit", "x" mx " y" y " w300", curSeq)
        y += 22 + GAP_SM
    }
    y += GAP_SM

    saveBtn := g.Add("Button", "x" mx " y" y " w140 h" BTN_H, "Save Parameters")
    saveBtn.OnEvent("Click", SaveParamsClicked.Bind(cfg, descriptor, flagCtrls, tunableCtrls, seqCtrl))
    y += BTN_H + GAP_MD

    for calib in descriptor["calibrations"] {
        kind := calib["kind"]
        section := calib["section"]
        label := calib["label"]
        g.Add("Text", "x" mx " y" (y + 2) " w" (LABEL_W - 10), label ":")
        if (kind = "region") {
            b1 := g.Add("Button", "x" CONTROL_X " y" y " w110 h" BTN_H, "Corner 1")
            b1.OnEvent("Click", CaptureRegionCorner1.Bind(cfg, section, label))
            b2 := g.Add("Button", "x" (CONTROL_X + 120) " y" y " w110 h" BTN_H, "Corner 2")
            b2.OnEvent("Click", CaptureRegionCorner2.Bind(cfg, section, label, statusCtrl, descriptor))
        } else if (kind = "coord") {
            b := g.Add("Button", "x" CONTROL_X " y" y " w160 h" BTN_H, "Capture")
            b.OnEvent("Click", CaptureCoordNow.Bind(cfg, section, calib["key"], statusCtrl, descriptor))
        } else if (kind = "slotpoints") {
            previousFlagKey := calib.Has("previousSlotFlagKey") ? calib["previousSlotFlagKey"] : ""
            b := g.Add("Button", "x" CONTROL_X " y" y " w220 h" BTN_H, "Capture (inventory empty)")
            b.OnEvent("Click", CaptureSlotPoints.Bind(cfg, section, previousFlagKey, statusCtrl, descriptor))
        } else if (kind = "pointlist-repeatable") {
            b := g.Add("Button", "x" CONTROL_X " y" y " w110 h" BTN_H, "Add Point")
            b.OnEvent("Click", CaptureAddOreSpot.Bind(cfg, section, statusCtrl, descriptor))
            cb := g.Add("Button", "x" (CONTROL_X + 120) " y" y " w110 h" BTN_H, "Clear")
            cb.OnEvent("Click", ClearOreSpots.Bind(cfg, section, statusCtrl, descriptor))
        } else if (kind = "path") {
            steps := LoadPath(cfg, section)
            rb := g.Add("Button", "x" CONTROL_X " y" y " w160 h" BTN_H, steps.Length > 0 ? "Re-record" : "Record")
            rb.OnEvent("Click", ToggleRecordButton.Bind(cfg, section, label, rb, statusCtrl, descriptor))
        }
        y += ROW_CALIB
    }

    y += GAP_SM
    g.Add("Text", "x" mx " y" (y + 2) " w90 h16", "Bot process:")
    runStatus := g.Add("Text", "x" (mx + 90) " y" (y + 2) " w200 h16", "Not running")
    startBtn := g.Add("Button", "x" (mx + 300) " y" y " w90 h" BTN_H, "Start")
    startBtn.OnEvent("Click", StartBotProcess.Bind(descriptor["key"], scriptPath, runStatus))
    stopBtn := g.Add("Button", "x" (mx + 400) " y" y " w90 h" BTN_H, "Stop")
    stopBtn.OnEvent("Click", StopBotProcess.Bind(descriptor["key"], runStatus))
    y += BTN_H + GAP_MD

    return y
}

BuildPanel() {
    global DESCRIPTORS, CONTENT_W
    g := Gui("+Resize", "OSRS Bot Control Panel")
    names := []
    for d in DESCRIPTORS
        names.Push(d["label"])
    ; Tab3's own height is provisional here - it's recomputed below
    ; once every tab's actual content height is known, so the window
    ; shrinks to fit the tallest tab instead of leaving dead space.
    tabW := CONTENT_W + 40
    tab := g.Add("Tab3", "x10 y10 w" tabW " h400", names)
    maxY := 0
    loop DESCRIPTORS.Length {
        tab.UseTab(A_Index)
        contentY := BuildBotTab(g, DESCRIPTORS[A_Index])
        if (contentY > maxY)
            maxY := contentY
    }
    tab.UseTab(0)
    tab.Choose(1)

    ; +90 covers the Tab3 control's own header-strip height (not part
    ; of maxY, which only tracks content row positions) plus a small
    ; safety margin against rounding in the per-row constants above.
    tabH := maxY + 90
    tab.Move(, , tabW, tabH)
    g.OnEvent("Close", (*) => ExitApp())
    g.Show("w" (tabW + 20) " h" (tabH + 40))
}

BuildPanel()
