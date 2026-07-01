; ============================================================
; auto-agility.ahk - v1 (Agility Course Runner)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Context.ahk
#Include ..\lib\Db.ahk
#Include ..\lib\Colors.ahk
#Include ..\lib\Images.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\Grid.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Slots.ahk
#Include ..\lib\Targeting.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\auto-agility.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-agility-debug.log"
global ctx := NewBotContext(CONFIG)

; Define the obstacle sequence
global STEPS := [
    Map("w", 42, "h", 42, "x", 807, "y", 775, "delay", 1000, "color", 0x003306, "offsetX", 0, "offsetY", 0),
    Map("w", 44, "h", 44, "x", 1069, "y", 699, "delay", 1000, "color", 0x06600b, "offsetX", 0, "offsetY", 0),
    Map("w", 38, "h", 38, "x", 865, "y", 794, "delay", 1000, "color", 0x009407, "offsetX", 0, "offsetY", 0),
    Map("w", 64, "h", 64, "x", 976, "y", 892, "delay", 1000, "color", 0x00cc00, "offsetX", 0, "offsetY", 0),
    Map("w", 43, "h", 65, "x", 1267, "y", 688, "delay", 1000, "color", 0x55ff47, "offsetX", 0, "offsetY", 0),
    Map("w", 87, "h", 90, "x", 1191, "y", 503, "delay", 1000, "color", 0xe4ffe0, "offsetX", 0, "offsetY", 0),
    Map("w", 13, "h", 61, "x", 995, "y", 175, "delay", 1000, "color", 0xffffff, "offsetX", 0, "offsetY", 0)
]

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()

; ============================================================
; BOT LIFECYCLE
; ============================================================

StartBot() {
    global ctx, STEPS
    LoadConfig()
    if (!ValidateSetup())
        return
    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")

    step7 := STEPS[7]
    LogLine(LOG_FILE, "Agility: Started with Step 7 offsets: [" step7["offsetX"] "," step7["offsetY"] "]")

    ctx["runner"] := NewTaskRunner(50) ; 50ms fast ticks
    AddPhase(ctx["runner"], "agility", AgilityPhase, CtxTunable(ctx, "phaseTimeoutAgility", 60000))

    ctx["currentStep"] := 1
    ctx["checkedMarkForStep"] := false
    ctx["dynamicSearchActive"] := false
    ctx["lastClickTime"] := A_TickCount ; Prevents failsafe immediately on start
    StartTaskRunner(ctx["runner"], "agility")
    TickTaskRunner(ctx["runner"])
    LogLine(LOG_FILE, "===== Agility Runner started =====")
}

StopAndLog(runner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    if (runner != "")
        StopTaskRunner(runner, reason)
}

ClearConfigAndReload() {
    global CONFIG
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
; PHASES
; ============================================================

AgilityPhase(runner) {
    global ctx, LOG_FILE, STEPS
    static lastLogTime := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "AgilityPhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "agility")
    }

    currentStep := ctx["currentStep"]
    step := STEPS[currentStep]
    searchTol := CtxTunable(ctx, "searchTolerancePx", 15)
    colorTolerance := CtxTunable(ctx, "colorTolerance", 5)
    lastClickTime := ctx.Has("lastClickTime") ? ctx["lastClickTime"] : A_TickCount

    ; 1. Next marker detection check
    dynamicActive := ctx.Has("dynamicSearchActive") && ctx["dynamicSearchActive"]
    found := false
    cx := 0, cy := 0

    if (dynamicActive) {
        ; Whole screen search, smaller size (due to perspective shift)
        searchSize := CtxTunable(ctx, "searchBlockSizePx", 12)
        found := FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, step["color"], colorTolerance, searchSize,
            searchSize, &cx, &cy)
        if (found) {
            ; Shift from center coordinates to bottom-right corner with configured offsets
            foundX := cx - searchSize // 2
            foundY := cy - searchSize // 2
            dx := CtxTunable(ctx, "dynamicOffsetX", 4)
            dy := CtxTunable(ctx, "dynamicOffsetY", 4)
            cx := foundX + searchSize - 1 + dx
            cy := foundY + searchSize - 1 + dy
        }
    } else {
        ; Normal coordinate search with inset
        inset := CtxTunable(ctx, "blockInsetPx", 1)
        w := step["w"] - (2 * inset)
        h := step["h"] - (2 * inset)
        x := step["x"] + inset
        y := step["y"] + inset

        x1 := x - searchTol
        y1 := y - searchTol
        x2 := x + searchTol
        y2 := y + searchTol
        found := FindFilledBlock(x1, y1, x2, y2, step["color"], colorTolerance, w, h, &cx, &cy)
    }

    if (found) {
        ; 2. standing still check: next marker is in place, check for Mark of Grace once per step
        checkedMark := ctx.Has("checkedMarkForStep") ? ctx["checkedMarkForStep"] : false
        if (!checkedMark) {
            ctx["checkedMarkForStep"] := true

            ; Settle delay before scanning to let camera and ground item models stabilize
            preDelay := CtxTunable(ctx, "gracePrePickupDelayMs", 500)
            Sleep(preDelay)

            imgW := 136
            imgH := 24
            images := [
                A_ScriptDir "\..\images\mark-of-grace.png",
                A_ScriptDir "\..\images\mark-of-grace-transparent.png"
            ]
            options := "*Trans0x00FF00"

            loop {
                if (!CtxIsRunning(ctx))
                    break

                if (FindAnyImageCenter(0, 0, A_ScreenWidth, A_ScreenHeight, images, imgW, imgH, &mcx, &mcy, &matchedImg,
                    options)) {
                    ; Mark of Grace is present! Capture inventory slot 1 signature
                    sig := GetSlot1QtySignature()

                    ; Apply click offsets (defaults to x+2px, y+6px)
                    graceOffsetX := CtxTunable(ctx, "graceClickOffsetX", 2)
                    graceOffsetY := CtxTunable(ctx, "graceClickOffsetY", 2)
                    mcx := mcx + graceOffsetX
                    mcy := mcy + graceOffsetY

                    ; Click the Mark of Grace to loot it
                    HumanClick(mcx, mcy, 0, 0, ctx["runMode"])
                    LogLine(LOG_FILE, "Agility: Found Mark of Grace! Clicked center at [" mcx "," mcy "]")
                    ShowTip("Agility: Looting Mark of Grace...")

                    ; Wait for slot 1 quantity to change
                    pickupTimeout := CtxTunable(ctx, "gracePickupTimeoutMs", 3000)
                    deadline := A_TickCount + pickupTimeout
                    looted := false
                    loop {
                        if (!CtxIsRunning(ctx))
                            break
                        if (HasSlot1QtyChanged(sig)) {
                            looted := true
                            break
                        }
                        if (A_TickCount >= deadline)
                            break
                        Sleep(50) ; Poll faster for quicker response
                    }

                    if (looted) {
                        LogLine(LOG_FILE, "Agility: Successfully looted Mark of Grace (inventory slot 1 changed)")
                    } else {
                        LogLine(LOG_FILE,
                            "Agility: Mark of Grace pickup timed out or failed to update inventory. Exiting looting loop to continue course."
                        )
                        ; We probably moved trying to pick it up, activate dynamic search
                        ctx["dynamicSearchActive"] := true
                        postDelay := CtxTunable(ctx, "gracePostPickupDelayMs", 1500)
                        Sleep(postDelay)
                        break ; Break the loop to go next
                    }

                    ; Post-pickup delay to let player settle before searching/looting again
                    postDelay := CtxTunable(ctx, "gracePostPickupDelayMs", 1500)
                    Sleep(postDelay)

                    ; We moved to pick it up, activate dynamic search for this step
                    ctx["dynamicSearchActive"] := true
                } else {
                    break ; No more Marks of Grace found on screen
                }
            }

            ; If we looted (or tried to), restart tick to locate next marker dynamically
            if (ctx.Has("dynamicSearchActive") && ctx["dynamicSearchActive"]) {
                return GoToPhase(runner, "agility")
            }
        }

        ; 3. Click the next obstacle
        cooldown := CtxTunable(ctx, "clickCooldownMs", 1000)
        if (A_TickCount - lastClickTime > cooldown) {
            ; Apply step-specific offsets
            offX := step.Has("offsetX") ? step["offsetX"] : 0
            offY := step.Has("offsetY") ? step["offsetY"] : 0
            cx := cx + offX
            cy := cy + offY

            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            ctx["lastClickTime"] := A_TickCount
            LogLine(LOG_FILE, "Agility: Clicked Step " currentStep " at [" cx "," cy "] (offset: " offX "," offY ") (" step[
                "w"] "x" step["h"] ")")
            ShowTipFor("Agility: Running obstacle " currentStep, 1500)

            ; Safe configurable pause for this step
            delayMs := step.Has("delay") ? step["delay"] : 1000
            Sleep(delayMs)

            ; Advance to next step immediately after the pause
            nextStep := currentStep + 1
            if (nextStep > STEPS.Length)
                nextStep := 1
            ctx["currentStep"] := nextStep
            ctx["checkedMarkForStep"] := false
            ctx["dynamicSearchActive"] := false

            ResetPhaseTimer(ctx["runner"])
            ctx["lastClickTime"] := A_TickCount ; Reset so failsafe measures from after the sleep!
        }
    } else {
        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "Agility: Waiting for Step " currentStep " highlight (" step["w"] "x" step["h"] " at " step[
                "x"] "," step["y"] ")")
        }
        ShowTip("Agility: Waiting for obstacle " currentStep "...")

        ; Failsafe: if we timed out waiting for too long, check if the previous step's highlight is still visible
        failsafeTimeout := CtxTunable(ctx, "failsafeTimeoutMs", 15000)
        if (A_TickCount - lastClickTime > failsafeTimeout) {
            prevStep := currentStep - 1
            if (prevStep < 1)
                prevStep := STEPS.Length
            pStep := STEPS[prevStep]

            inset := CtxTunable(ctx, "blockInsetPx", 1)
            pw := pStep["w"] - (2 * inset)
            ph := pStep["h"] - (2 * inset)
            px := pStep["x"] + inset
            py := pStep["y"] + inset

            px1 := px - searchTol
            py1 := py - searchTol
            px2 := px + searchTol
            py2 := py + searchTol

            if (FindFilledBlock(px1, py1, px2, py2, pStep["color"], colorTolerance, pw, ph, &pcx, &pcy)) {
                LogLine(LOG_FILE, "Agility Failsafe: Timed out waiting for Step " currentStep ", but Step " prevStep " is still visible. Reverting step index."
                )
                ctx["currentStep"] := prevStep
                ctx["lastClickTime"] := 0 ; permit instant click on revert
            }
        }
    }

    return GoToPhase(runner, "agility")
}

; ============================================================
; HELPERS
; ============================================================

VerifyBlock(x, y, color, tol, reqW, reqH) {
    cx := x + reqW // 2
    cy := y + reqH // 2

    ; We verify that it is AT LEAST checkW x checkH solid fill.
    ; Checking 75% of the requested size is safe against edge anti-aliasing.
    checkW := reqW * 3 // 4
    checkH := reqH * 3 // 4

    ; Check internal points using type-safe IsColorAt
    if (!IsColorAt(cx, cy, color, tol))
        return false
    if (!IsColorAt(x, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y, color, tol))
        return false
    if (!IsColorAt(x + checkW - 1, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y + checkH - 1, color, tol))
        return false

    return true
}

FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy) {
    if (x1 > x2 || y1 > y2)
        return false

    if (!PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol))
        return false

    if (VerifyBlock(foundX, foundY, color, tol, reqW, reqH)) {
        cx := foundX + reqW // 2
        cy := foundY + reqH // 2
        return true
    }

    ; Recursive search to cover the remaining areas:
    ; 1. The rest of the current horizontal line segment
    if (FindFilledBlock(foundX + 1, foundY, x2, foundY, color, tol, reqW, reqH, &cx, &cy))
        return true

    ; 2. All subsequent lines below the current pixel row
    if (FindFilledBlock(x1, foundY + 1, x2, y2, color, tol, reqW, reqH, &cx, &cy))
        return true

    return false
}

GetSlot1QtySignature() {
    sig := []
    loop 16 {
        row := A_Index - 1
        loop 16 {
            col := A_Index - 1
            if (Mod(row, 3) = 0 && Mod(col, 3) = 0) {
                px := 1615 + col
                py := 801 + row
                sig.Push(PixelGetColor(px, py, "RGB"))
            }
        }
    }
    return sig
}

HasSlot1QtyChanged(sig, tol := 10) {
    idx := 1
    loop 16 {
        row := A_Index - 1
        loop 16 {
            col := A_Index - 1
            if (Mod(row, 3) = 0 && Mod(col, 3) = 0) {
                current := PixelGetColor(1615 + col, 801 + row, "RGB")
                if (!ColorClose(current, sig[idx], tol))
                    return true
                idx += 1
            }
        }
    }
    return false
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"] := DbGet(CONFIG, "Tunables", "colorTolerance", 5, "int")
    ctx["tunables"]["searchTolerancePx"] := DbGet(CONFIG, "Tunables", "searchTolerancePx", 15, "int")
    ctx["tunables"]["blockInsetPx"] := DbGet(CONFIG, "Tunables", "blockInsetPx", 1, "int")
    ctx["tunables"]["clickCooldownMs"] := DbGet(CONFIG, "Tunables", "clickCooldownMs", 1000, "int")
    ctx["tunables"]["failsafeTimeoutMs"] := DbGet(CONFIG, "Tunables", "failsafeTimeoutMs", 15000, "int")
    ctx["tunables"]["gracePickupTimeoutMs"] := DbGet(CONFIG, "Tunables", "gracePickupTimeoutMs", 3000, "int")
    ctx["tunables"]["gracePrePickupDelayMs"] := DbGet(CONFIG, "Tunables", "gracePrePickupDelayMs", 500, "int")
    ctx["tunables"]["gracePostPickupDelayMs"] := DbGet(CONFIG, "Tunables", "gracePostPickupDelayMs", 1500, "int")
    ctx["tunables"]["graceClickOffsetX"] := DbGet(CONFIG, "Tunables", "graceClickOffsetX", 2, "int")
    ctx["tunables"]["graceClickOffsetY"] := DbGet(CONFIG, "Tunables", "graceClickOffsetY", 2, "int")
    ctx["tunables"]["searchBlockSizePx"] := DbGet(CONFIG, "Tunables", "searchBlockSizePx", 12, "int")
    ctx["tunables"]["dynamicOffsetX"] := DbGet(CONFIG, "Tunables", "dynamicOffsetX", 4, "int")
    ctx["tunables"]["dynamicOffsetY"] := DbGet(CONFIG, "Tunables", "dynamicOffsetY", 4, "int")
    ctx["tunables"]["phaseTimeoutAgility"] := DbGet(CONFIG, "Tunables", "phaseTimeoutAgility", 60000, "int")

    ; Write back
    DbSet(CONFIG, "Tunables", "colorTolerance", ctx["tunables"]["colorTolerance"], "int")
    DbSet(CONFIG, "Tunables", "searchTolerancePx", ctx["tunables"]["searchTolerancePx"], "int")
    DbSet(CONFIG, "Tunables", "blockInsetPx", ctx["tunables"]["blockInsetPx"], "int")
    DbSet(CONFIG, "Tunables", "clickCooldownMs", ctx["tunables"]["clickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "failsafeTimeoutMs", ctx["tunables"]["failsafeTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "gracePickupTimeoutMs", ctx["tunables"]["gracePickupTimeoutMs"], "int")
    DbSet(CONFIG, "Tunables", "gracePrePickupDelayMs", ctx["tunables"]["gracePrePickupDelayMs"], "int")
    DbSet(CONFIG, "Tunables", "gracePostPickupDelayMs", ctx["tunables"]["gracePostPickupDelayMs"], "int")
    DbSet(CONFIG, "Tunables", "graceClickOffsetX", ctx["tunables"]["graceClickOffsetX"], "int")
    DbSet(CONFIG, "Tunables", "graceClickOffsetY", ctx["tunables"]["graceClickOffsetY"], "int")
    DbSet(CONFIG, "Tunables", "searchBlockSizePx", ctx["tunables"]["searchBlockSizePx"], "int")
    DbSet(CONFIG, "Tunables", "dynamicOffsetX", ctx["tunables"]["dynamicOffsetX"], "int")
    DbSet(CONFIG, "Tunables", "dynamicOffsetY", ctx["tunables"]["dynamicOffsetY"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutAgility", ctx["tunables"]["phaseTimeoutAgility"], "int")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", true, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")

    ; --- Configurable Step Pauses & Colors ---
    loop STEPS.Length {
        i := A_Index
        STEPS[i]["delay"] := DbGet(CONFIG, "Step:" i, "delayMs", STEPS[i]["delay"], "int")
        STEPS[i]["color"] := DbGet(CONFIG, "Step:" i, "color", STEPS[i]["color"], "int")
        STEPS[i]["offsetX"] := DbGet(CONFIG, "Step:" i, "offsetX", STEPS[i]["offsetX"], "int")
        STEPS[i]["offsetY"] := DbGet(CONFIG, "Step:" i, "offsetY", STEPS[i]["offsetY"], "int")

        DbSet(CONFIG, "Step:" i, "delayMs", STEPS[i]["delay"], "int")
        DbSet(CONFIG, "Step:" i, "color", Format("0x{:06X}", STEPS[i]["color"]), "string")
        DbSet(CONFIG, "Step:" i, "offsetX", STEPS[i]["offsetX"], "int")
        DbSet(CONFIG, "Step:" i, "offsetY", STEPS[i]["offsetY"], "int")
    }
}

ValidateSetup() {
    return true
}
