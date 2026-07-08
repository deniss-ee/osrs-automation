; ============================================================
; Phase.ahk
; Base class for every bot phase. A Phase's Run(ctx) must
; follow the mandatory 4-step shape (acquire -> wait -> act ->
; verify) documented in the v4 ruleset - this base class only
; supplies the Name used for registration/logging/timeouts and
; the contract signature; it does not enforce the 4 steps
; mechanically (that's a code-review concern, not a runtime one).
; ============================================================

#Requires AutoHotkey v2.0

class Phase {
    __New(name) {
        this.name := name
    }

    ; Subclasses override this. Must return a phase name string;
    ; returning this.name means "stay in this phase, tick again".
    Run(ctx) {
        throw Error("Phase subclass '" this.name "' did not implement Run(ctx)")
    }
}
