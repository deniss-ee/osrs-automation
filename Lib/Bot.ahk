; ============================================================
; v8 Lib\Bot.ahk - hotkey harness (F5 run, F6 stop, F8 probe,
; F12 exit, optional extraHotkeys)
;
; Refactored from v7\Lib\Bot.ahk. v7 had a real footgun: F5's run
; went through RunWrapped, which reset g_StopRequested and caught
; BotStopped - but extraHotkeys handlers went through a bare
; BindHotkeyHandler factory that did NEITHER. Any extraHotkey that
; ran a real interruptible loop had to hand-roll its own reset/catch
; (v7 micro 28's F7 did this) or risk a stale stop flag aborting it
; instantly, or an uncaught BotStopped crashing the script on F6.
;
; v8 fixes this structurally: WrapHandler(handler, label) is the
; ONE wrapping path, applied uniformly to run, probe, AND every
; extraHotkeys entry. No handler in v8 needs to know about
; g_StopRequested or BotStopped at all.
;
; RunWrapped also now captures and reports the run function's
; return value (v7 discarded it - Bots\woodcutting.ahk:160 called
; GatherBankLoop as a bare statement, so a FAILED run looked
; identical to a clean stop except in the log). v8's steps/StepLoop
; return true (clean stop) or false (FAILED) - WrapHandler surfaces
; the difference on screen.
; ============================================================

; Wraps any handler for hotkey use: resets g_StopRequested, catches
; BotStopped, and reports DONE/FAILED/STOPPED based on the handler's
; return value (handlers that return nothing are treated as "ran to
; completion" -> DONE, e.g. one-shot probes).
WrapHandler(handler, label) {
    return WrappedHandler

    WrappedHandler(*) {
        global g_StopRequested
        g_StopRequested := false
        try {
            result := handler()
            if (result = false)
                Say(label ": FAILED - still loaded, F5 to restart")
            else
                Say(label ": DONE")
        } catch BotStopped {
            Say(label ": STOPPED by F6")
        }
    }
}

InstallBotHarness(opts) {
    run := opts.run
    label := Opt(opts, "label", "Bot")
    probe := Opt(opts, "probe", "")
    extraHotkeys := Opt(opts, "extraHotkeys", [])

    global g_LogName
    TrimLogOnStart()

    Hotkey("F5", WrapHandler(run, label))
    Hotkey("F6", RequestStop)
    Hotkey("F12", ExitBot)

    if (probe)
        Hotkey("F8", WrapHandler(probe, label . " probe"))

    for entry in extraHotkeys
        Hotkey(entry.key, WrapHandler(entry.handler, Opt(entry, "label", entry.key)))

    Say(label ": ready - F5 run, F6 stop, F12 exit" (probe ? ", F8 probe" : ""))
}

RequestStop(*) {
    global g_StopRequested
    g_StopRequested := true
    Say("stop requested")
}

ExitBot(*) {
    ExitApp()
}
