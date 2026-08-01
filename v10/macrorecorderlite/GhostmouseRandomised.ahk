#Persistent
#SingleInstance, Force
CoordMode, Mouse, Screen


recording:=False
logg:=""

Gui, a: New, hwndhGui AlwaysOnTop Resize MinSize
Gui, Add, Text, x10 w120, Start/stop recording Alt+1`nCancel playback Esc
Gui, Add, Button, xs section w180 gRunRecording, Playback Alt+2
Gui, Add, Button, xs section w180 gDeleteRecording, Delete recording Alt+3
Gui, Add, Edit, xs section w50
Gui, Add, UpDown, vRandomPercent Range0-100, 20
Gui, Add, Text,yp+3 x+5, Random delay `%
Gui, Add, Edit, xs section w50
Gui, Add, UpDown, vRandomPixels Range0-10000, 5
Gui, Add, Text,yp+3 x+5, Random clicks (pixels)
Gui, Add, Text, xs w120 vStatus, Idle
Gui, Add, Link,xs, <a href="https://www.patreon.com/nomscripts">Nom Scripts</a>

Gui, Show,, GhostMouse AHK
OnMessage(0x112, "WM_SYSCOMMAND")
return

~Esc::
UpdateText("Status", "Idle")
return

!1::
ToggleRecord:
Gui, a: Submit, Nohide
if (recording) {
	recording:=False
	Goto SaveRecording
} else {
	recording:=True
	UpdateText("Status", "Recording")
	SetTimer, MouseMovementListener, 10
	logg := ""
	timeSinceLast := A_TickCount
	lastX := 0
	lastY := 0
	lineCount := 0
}
return

MouseMovementListener:
MouseGetPos, x,y
if (lastX == x && lastY == y) {
	return
}
LogMove(x, y)
lastX := x
lastY := y
return

LogPress() {
	global logg
	butt := RegExReplace(A_ThisHotkey, "[~!@#$%^&*()]", "")
	k := butt
	LogSleep(true)
	logg .= "Send {" . k . " down}`n"
	KeyWait, k, L
	loop {
		GetKeyState, state, %k%
		if (state = "D") {
			Sleep, 1
		} else {
			break
		}
	}
	LogSleep(true)
	logg .= "Send {" . k . " up}`n"
}


LogClick() {
	global logg, RandomPixels
	MouseGetPos, X, Y
	butt := RegExReplace(A_ThisHotkey, "[~!@#$%^&*()]", "")
	stateKey := butt
	k := SubStr(butt,1,1)
	LogSleep(true)
	strX := "rand(" . (X - RandomPixels) . "," . (X + RandomPixels) . ")"
	strY := "rand(" . (Y - RandomPixels) . "," . (Y + RandomPixels) . ")"
	startClick := A_TickCount
	dragging := False
	loop {
		GetKeyState, state, %stateKey%
		if (state = "D") {
			MouseGetPos, x2,y2
			if (!dragging && (x2 != X || y2 != Y)) {
				logg .= "MouseClick," . k . "," . X . "," . Y . ",,,D`n"
				dragging := True
			}
			Sleep, 1
		} else {
			if (!dragging) {
				if (RandomPixels > 0) {
					logg .= "MouseClick," . k . "," . strX . "," . strY . ",,,`n"
				} else {
					logg .= "MouseClick," . k . "," . X . "," . Y . ",,,`n"
				}
				return
			}
			break
		}
	}
	tooltip
	MouseGetPos, X, Y
	LogSleep(true)
	LogMove(X, Y)
	logg .= "MouseClick," . k . ",,,,,U`n"
}

LogMove(X, Y) {
	global logg
	LogSleep()
	logg .= "MouseMove, " X ", " Y "`n"
}

LogSleep(rand:=False) {
	global logg, timeSinceLast, lineCount, recording, RandomPercent
	if (!recording) {
		return
	}
	if (A_TickCount - timeSinceLast == 0) {
		return
	}
	delay := max(A_TickCount - timeSinceLast,10)
	if (rand && RandomPercent > 0) {
		randd := RandomPercent * delay / 100 + delay + 1
		logg .= "Sleep, rand`(" . delay . "," . Round(randd) . "`)`n"
	} else {
		logg .= "Sleep, " . (A_TickCount - timeSinceLast) . "`n"
	}
	timeSinceLast := A_TickCount
	lineCount++
}

*~LButton::
*~RButton::
*~MButton::
LogClick()
return

*~F1::
*~F2::
*~F3::
*~F4::
*~F5::
*~F6::
*~F7::
*~F8::
*~F9::
*~F10::
*~F11::
*~F12::
*~q::
*~w::
*~e::
*~r::
*~t::
*~y::
*~u::
*~i::
*~o::
*~p::
*~a::
*~s::
*~d::
*~f::
*~g::
*~h::
*~j::
*~k::
*~l::
*~z::
*~x::
*~c::
*~v::
*~b::
*~n::
*~m::
*~CapsLock::
*~Space::
*~Tab::
*~Enter::
*~Return::
*~BS::
*~ScrollLock::
*~Del::
*~Ins::
*~Home::
*~End::
*~PgUp::
*~PgDn::
*~Up::
*~Down::
*~Left::
*~Right::
*~LShift::
*~RShift::
*~LCtrl::
*~RCtrl::
LogPress()
return

UpdateText(ControlID, NewText)
{
	; Unlike using a pure GuiControl, this function causes the text of the
	; controls to be updated only when the text has changed, preventing periodic
	; flickering (especially on older systems).
	static OldText := {}
	global hGui
	if (OldText[ControlID] != NewText)
	{
		GuiControl, %hGui%:, % ControlID, % NewText
		OldText[ControlID] := NewText
	}
}

!2::
RunRecording:
UpdateText("Status", "Playing " . filename)
ahk:=A_IsCompiled ? A_ScriptDir "\AutoHotkey.exe" : A_AhkPath
IfNotExist, %ahk%
{
  MsgBox, 4096, Error, Can't Find %ahk% !
  Exit
}
Run, %ahk% /r "%filename%"
return

!3::
DeleteRecording:
UpdateText("Status", "Deleted " . filename)
FileDelete, %filename%
return

SaveRecording:
filename := lineCount . "Lines"  . mod(A_TickCount, 1000) . ".ahk"
Array := []
Array.Push("CoordMode, Mouse, Screen")
Array.Push("SetKeyDelay -1")
Array.Push("SetMouseDelay -1")
Array.Push("SetBatchLines -1")
Array.Push("loop")
Array.Push("{")
for index, element in Array
{
    FileAppend, % element, %filename%
	FileAppend, `n, %filename%
}

FileAppend, % logg, %filename%

Array := []
Array.Push("}")
Array.Push("return")
Array.Push("rand`(min,max`){")
Array.Push("Random, rrr,min,max")
Array.Push("return rrr")
Array.Push("}")
Array.Push("~Esc::")
Array.Push("ExitApp")
for index, element in Array
{
    FileAppend, % element, %filename%
	FileAppend, `n, %filename%
}
UpdateText("Status", "Saved " . filename)
return


WM_SYSCOMMAND(wp, lp, msg, hwnd)  {
   static SC_CLOSE := 0xF060
   if (wp != SC_CLOSE)
      Return
   
   ExitApp
}

GuiClose:		;close Gui to Exit
GuiEscape:		;press Esc to Exit
ExitApp