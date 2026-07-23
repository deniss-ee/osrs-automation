; ============================================================
; v7 Lib\Bot.ahk - shared F5/F6/F12 run/stop harness (micro 26)
;
; Fixes the 7-way duplication confirmed across every v6 bot
; (autoclicker/crafting/motherlode2/seller/smithing/sudoku/woodcutting):
; each one hand-rolled the identical `g_StopRequested := false` reset,
; `try { <loop> } catch BotStopped { Say("STOPPED by F6") }` wrapper,
; and F5/F6 hotkey registration - only the loop body itself (SellCycle,
; FullCycle, RunChopLoop, ...) actually differed bot to bot. `F12` (exit)
; was already promoted to v6's Lib\v6.ahk umbrella; this goes further
; and promotes the WHOLE harness, not just F12, and moves F12 here too
; (a bot script no longer defines any of F5/F6/F12 itself).
;
; ONE registration call - InstallBotHarness(opts) - wires:
;   F5  = start (resets g_StopRequested, Says "<label>: started", runs
;         opts.run() inside a try/catch BotStopped, Says "<label>:
;         STOPPED by F6" if interrupted)
;   F6  = request stop (instant - sets g_StopRequested, same as every
;         micro's F6 so far)
;   F12 = exit (ExitApp) - the only way to fully quit a v7 bot; NOT Esc,
;         since several bots' own action sequences send a real Esc
;         in-game (same reasoning as v6's F12 promotion)
;   F8  = OPTIONAL probe hotkey (opts.probe) - motherlode2's F8
;         "probe check slot + sack slots" is the confirmed real use case
;   extraHotkeys = OPTIONAL further bot-specific keys (motherlode2's F9
;         debug-mode toggle is the confirmed real use case that proves
;         this extension point is needed, not just F8)
;
; opts.run is NOT expected to include its own try/catch or stop-flag
; reset - Bot.ahk owns that now. A bot's `run` is just "the actual
; work," e.g. a function that calls GatherBankLoop (micro 25) or a
; bot's own hand-rolled loop - Bot.ahk doesn't assume or impose any
; particular loop shape, only wraps whatever `run` does.
;
; opts:
;   run    - zero-arg function; the bot's actual entry point (required).
;            Bot.ahk resets g_StopRequested to false, Says "<label>:
;            started", then calls this inside its own try/catch
;            BotStopped - the bot's run function should NOT catch
;            BotStopped itself (let it propagate up to here).
;   label  - Say()/log prefix (default "Bot")
;   probe  - OPTIONAL zero-arg function bound to F8 (default: F8 not
;            registered at all)
;   extraHotkeys - OPTIONAL array of {key, handler} objects (handler is
;            a zero-arg function) for further bot-specific keys, e.g.
;            {key: "F9", handler: ToggleDebugMode}
;
; CLOSURE-PER-ENTRY BUG AVOIDED: registering extraHotkeys via a plain
; `for entry in opts.extraHotkeys { Hotkey(entry.key, (*) => entry.handler()) }`
; would be wrong - AHK v2's `for` loop variable is a single reused local,
; not a fresh binding per iteration, so every extra hotkey's closure
; would end up calling whichever handler was assigned LAST once any of
; them actually fires (they all fire long after the loop has finished).
; Fixed by routing each registration through BindHotkeyHandler(handler),
; a small factory function - `handler` is a genuine parameter of THAT
; call, so each call gets its own distinct local for the closure to
; capture, instead of all closures sharing the loop's one variable.
;
; Call InstallBotHarness(opts) ONCE, near the bottom of a bot/micro
; script, after every function it references (run/probe/extraHotkeys
; handlers) is already defined.
InstallBotHarness(opts) {
    runFn := opts.run
    label := opts.HasOwnProp("label") ? opts.label : "Bot"

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
            hotkeyMsg .= "  " entry.key "=" (entry.HasOwnProp("label") ? entry.label : "extra")
        }
    }

    LogLine("Script loaded. " hotkeyMsg ".")
    ToolTip(label " ready - F5 to start", 20, 20)
}

; Factory, not inline in the loop - see InstallBotHarness's doc comment
; for why a plain per-iteration `(*) => entry.handler()` closure would
; be wrong (all extra hotkeys would end up calling the LAST one
; registered). `handler` here is a fresh parameter per CALL, so each
; returned closure captures its own distinct value.
BindHotkeyHandler(handler) {
    return (*) => handler()
}
