#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")

global capturedX := 0, capturedY := 0
global isRunning := false

; F1: Capture the coordinate where you click
F1:: {
    global capturedX, capturedY
    MouseGetPos(&x, &y)
    capturedX := x
    capturedY := y
    ToolTip("Captured: " x "," y)
    SetTimer(() => ToolTip(), 2000)
}

; F2: Start clicking the captured coordinate every 1 second for 10 minutes
F2:: {
    global capturedX, capturedY, isRunning
    if (isRunning) {
        isRunning := false
        ToolTip("Stopped")
        SetTimer(() => ToolTip(), 1000)
        return
    }
    if (capturedX = 0 || capturedY = 0) {
        ToolTip("Click F1 first to capture a coordinate")
        SetTimer(() => ToolTip(), 2000)
        return
    }

    isRunning := true
    ToolTip("Started clicking at " capturedX "," capturedY)
    SetTimer(() => ToolTip(), 2000)

    startTime := A_TickCount
    loop {
        if (!isRunning)
            break
        if (A_TickCount - startTime >= 1200000)  ; 10 minutes = 600000ms
            break

        MouseClick("Left", capturedX, capturedY)
        Sleep(2000)
    }
    isRunning := false
    ToolTip("Done (10 minutes completed)")
    SetTimer(() => ToolTip(), 2000)
}

; F3: Stop the loop early
F3:: {
    global isRunning
    if (isRunning) {
        isRunning := false
        ToolTip("Stopped manually")
        SetTimer(() => ToolTip(), 1500)
    }
}
