; ============================================================
;  gui.ahk - THE ON-SCREEN CONTROL PANEL
; ------------------------------------------------------------
;  ELI5: Up to now everything was hotkeys (F1, F2, F3...) and a
;  tiny tooltip - easy to forget which key does what. This file
;  builds one simple window with buttons and lists so you can see
;  and control everything without memorizing function keys. The
;  hotkeys still work too - both call the exact same functions.
; ============================================================

#Requires AutoHotkey v2.0

global MainGui := ""
global StatusTextCtrl := ""
global SpotsListView := ""
global ToBankListView := ""
global BackListView := ""

; --------------------------------------------------------------
; BuildGui: creates the window and all controls ONCE. Call this
; from main.ahk after State is loaded. We keep references to the
; controls we need to update later (status text, list views) in
; the globals above.
; --------------------------------------------------------------
BuildGui() {
    global MainGui, StatusTextCtrl, SpotsListView, ToBankListView, BackListView

    MainGui := Gui("+AlwaysOnTop", "OSRS Gathering Bot")
    MainGui.SetFont("s10")

    MainGui.Add("Text", "xm y10 w400", "Status:")
    StatusTextCtrl := MainGui.Add("Text", "xm y30 w400 h20", "Idle")

    MainGui.Add("Button", "xm y60 w120 h30", "Start (F6)").OnEvent("Click", (*) => GuiStart())
    MainGui.Add("Button", "x+10 y60 w120 h30", "Stop (F7)").OnEvent("Click", (*) => StopMining("Stopped via GUI"))
    MainGui.Add("Button", "x+10 y60 w120 h30", "Pause/Resume").OnEvent("Click", (*) => GuiTogglePause())

    ; ---- spots list ----
    MainGui.Add("Text", "xm y100", "Gathering spots (F1 to add one under your cursor):")
    SpotsListView := MainGui.Add("ListView", "xm y120 w400 h120", ["Enabled", "Name", "X", "Y"])
    MainGui.Add("Button", "xm y245 w130 h25", "Toggle Enabled").OnEvent("Click", (*) => GuiToggleSpotEnabled())
    MainGui.Add("Button", "x+10 y245 w130 h25", "Remove Selected").OnEvent("Click", (*) => GuiRemoveSpot())

    ; ---- path steps + "run from here" debug jump ----
    MainGui.Add("Text", "xm y285", "TO-BANK steps (F4 record, F9 toggle run while recording):")
    ToBankListView := MainGui.Add("ListView", "xm y305 w400 h100", ["#", "X", "Y", "Delay", "Run?"])

    MainGui.Add("Text", "xm y415", "BACK-TO-MINE steps (F5 record):")
    BackListView := MainGui.Add("ListView", "xm y435 w400 h100", ["#", "X", "Y", "Delay", "Run?"])

    MainGui.Add("Text", "xm y545", "Debug: start gathering cycle from a specific step:")
    stepDropdown := MainGui.Add("DropDownList", "xm y565 w200", STEP_ORDER)
    stepDropdown.OnEvent("Change", (ctrl, *) => SetStartStep(ctrl.Text))
    stepDropdown.Choose(1)

    MainGui.Add("Text", "xm y600", "Min stamina % to allow running:")
    staminaEdit := MainGui.Add("Edit", "x+10 y598 w50", State["minRunStamina"])
    staminaEdit.OnEvent("Change", (ctrl, *) => SetMinRunStamina(ctrl.Text))

    MainGui.OnEvent("Close", (*) => StopMining("GUI closed"))
    MainGui.Show()

    RefreshGuiLists()
    ; Keep the status text + lists fresh without you having to click anything.
    SetTimer(RefreshGuiStatus, 250)
}

; --------------------------------------------------------------
; RefreshGuiStatus: ticks every 250ms to pull the latest
; State["statusText"] (and stamina%) into the window. Cheap and
; simple - good enough since this isn't a high-frequency display.
; --------------------------------------------------------------
RefreshGuiStatus() {
    global State, StatusTextCtrl
    if (StatusTextCtrl = "")
        return
    stamina := GetStaminaPercent()
    StatusTextCtrl.Text := State["statusText"] . "  |  Stamina: " stamina "%"
}

; --------------------------------------------------------------
; RefreshGuiLists: rebuilds the spots/paths ListViews from
; current State. Called after any add/remove/record so the GUI
; never shows stale data.
; --------------------------------------------------------------
RefreshGuiLists() {
    global State, SpotsListView, ToBankListView, BackListView

    SpotsListView.Delete()
    for spot in State["spots"]
        SpotsListView.Add(, spot["enabled"] ? "Yes" : "No", spot["name"], spot["x"], spot["y"])

    ToBankListView.Delete()
    i := 1
    for step in State["paths"]["toBank"] {
        ToBankListView.Add(, i, step["x"], step["y"], step["delay"], step["run"] ? "Run" : "Walk")
        i += 1
    }

    BackListView.Delete()
    i := 1
    for step in State["paths"]["backToMine"] {
        BackListView.Add(, i, step["x"], step["y"], step["delay"], step["run"] ? "Run" : "Walk")
        i += 1
    }
}

; --------------------------------------------------------------
; GUI button handlers - thin wrappers that call into the shared
; logic functions (same ones the hotkeys use), so there is only
; ONE place that actually implements each behavior.
; --------------------------------------------------------------
GuiStart() {
    global State
    if (!ValidateSetup())
        return
    State["running"] := true
    State["paused"] := false
    RunGatheringCycle()
}

GuiTogglePause() {
    global State
    State["paused"] := !State["paused"]
    State["statusText"] := State["paused"] ? "Paused" : "Resumed"
    if (!State["paused"] && State["running"])
        RunGatheringCycle()
}

GuiToggleSpotEnabled() {
    global State, SpotsListView
    row := SpotsListView.GetNext()
    if (row = 0)
        return
    State["spots"][row]["enabled"] := !State["spots"][row]["enabled"]
    SaveConfig()
    RefreshGuiLists()
}

GuiRemoveSpot() {
    global State, SpotsListView
    row := SpotsListView.GetNext()
    if (row = 0)
        return
    State["spots"].RemoveAt(row)
    SaveConfig()
    RefreshGuiLists()
}

SetStartStep(stepName) {
    global State
    State["startStep"] := stepName
    State["statusText"] := "Next start will begin at: " stepName
}

SetMinRunStamina(text) {
    global State
    val := Integer(text)
    if (val < 0)
        val := 0
    if (val > 100)
        val := 100
    State["minRunStamina"] := val
    SaveConfig()
}
