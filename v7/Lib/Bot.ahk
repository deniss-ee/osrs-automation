; ============================================================
; v7 Lib\Bot.ahk - shared run/stop harness (standard #23)
;
; One InstallBotHarness(opts) call replaces the F5/F6/F12 wiring every
; v6 bot hand-rolled. opts.run is just the bot's actual work - the
; harness owns the stop-flag reset and the try/catch BotStopped (run
; must NOT catch BotStopped itself).
;
;   F5  = start (reset flag, run inside try/catch)
;   F6  = request stop (instant)
;   F12 = exit (never Esc - some bots send a real in-game Esc)
;   F8  = opts.probe (optional)
;   opts.extraHotkeys = optional [{key, handler, label}] list
;
; opts: run (required); label "Bot", probe, extraHotkeys.
; Call ONCE near the bottom of the script, after every referenced
; function is defined.
InstallBotHarness(opts) {
    runFn := opts.run
    label := Opt(opts, "label", "Bot")

    TrimLogOnStart()

    RunWrapped(*) {
        global g_StopRequested
        g_StopRequested := false
        Say(label ": started")
        try {
            runFn()
        } catch BotStopped {
            Say(label ": STOPPED by F6")
        }
    }

    RequestStop(*) {
        global g_StopRequested
        g_StopRequested := true
        LogLine("F6 pressed - stop requested")
    }

    ExitBot(*) {
        LogLine("F12 pressed - exiting")
        ExitApp()
    }

    Hotkey("F5", RunWrapped)
    Hotkey("F6", RequestStop)
    Hotkey("F12", ExitBot)

    hotkeyMsg := "F5=start  F6=stop  F12=exit"

    if (opts.HasOwnProp("probe")) {
        Hotkey("F8", BindHotkeyHandler(opts.probe))
        hotkeyMsg .= "  F8=probe"
    }

    if (opts.HasOwnProp("extraHotkeys")) {
        for entry in opts.extraHotkeys {
            Hotkey(entry.key, BindHotkeyHandler(entry.handler))
            hotkeyMsg .= "  " entry.key "=" Opt(entry, "label", "extra")
        }
    }

    LogLine("Script loaded. " hotkeyMsg ".")
    ToolTip(label " ready - F5 to start", 20, 20)
}

; Factory, never an inline closure in the registration loop: AHK v2's
; `for` variable is ONE reused local, so inline closures would all call
; whichever handler was registered LAST (standard #23). A parameter is
; a fresh binding per call, so each closure captures its own handler.
BindHotkeyHandler(handler) {
    return (*) => handler()
}
