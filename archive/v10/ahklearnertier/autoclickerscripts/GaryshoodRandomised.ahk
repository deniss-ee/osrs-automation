#SingleInstance force
CoordMode, Mouse, Screen
SetKeyDelay -1
SetMouseDelay 0
SetBatchLines -1

isClicking:=False

Gui, a: New, hwndhGui AlwaysOnTop Resize MinSize
Gui, Add, Button, section w100 gStartClicking, Start F1 or F6
Gui, Add, Button, w100 yp x+5 gStopClicking, Stop F2 or F7
Gui, Add, Text,section xs+10 w120, Usage`n1. Set a speed range`n2. Hit start

Gui, Add, Edit, w50
Gui, Add, UpDown, vDelaySecondsMin Range0-50000, 1
Gui, Add, Text,yp+3 x+5, -
Gui, Add, Edit, w50 yp-3 x+5
Gui, Add, UpDown, vDelaySecondsMax Range0-50000, 2
Gui, Add, Text,yp+3 x+5, Seconds


Gui, Add, Edit, w50 section xs
Gui, Add, UpDown, vDelayMillisMin Range0-50000, 100
Gui, Add, Text,yp+3 x+5, -
Gui, Add, Edit, w50 yp-3 x+5
Gui, Add, UpDown, vDelayMillisMax Range0-50000, 200
Gui, Add, Text,yp+3 x+5, Milliseconds

Gui, Add, Edit, w50 section xs
Gui, Add, UpDown, vRandomPosition Range0-50000, 0
Gui, Add, Text,yp+3 x+5, Pixel range
Gui, Add, Edit, w50 yp-3 x+5
Gui, Add, UpDown, vPositionChance Range0-100, 100
Gui, Add, Text,yp+3 x+5, Chance

Gui, Add, Text,xs vStatus w120, Idle
Gui, Add, Link,xs, <a href="https://www.patreon.com/nomscripts">Nom Scripts</a>

Gui, Show,, Auto Clicker
OnMessage(0x112, "WM_SYSCOMMAND")
return

ClickTimer:
MouseGetPos, startX, startY
loop {
	if (!isClicking) {
		Tooltip, Stopped!
		Sleep, 1000
		Tooltip
		return
	}
	Random chance, 0, 100
	if (RandomPosition > 0 && chance <= PositionChance) {
		newX := startX + midRandom(-RandomPosition,RandomPosition)
		newY := startY + midRandom(-RandomPosition,RandomPosition)
		MouseMove, newX, newY
	}
	
	Click
	Random, sec, DelaySecondsMin,DelaySecondsMax
	Random, milli, DelayMillisMin,DelayMillisMax
	delay := sec*1000 + milli
	Sleep, delay
}
return

~F1::
~F6::
StartClicking:
Gui, a: Submit, Nohide
if (!isClicking) {
	isClicking:=True
	Settimer, ClickTimer, -1
	UpdateText("Status", "Clicking!")
}
return

~F2::
~F7::
StopClicking:
Gui, a: Submit, Nohide
isClicking:=False
UpdateText("Status", "Idle")
return

midRandom(min,max) {
	mid := (min+max)/2
	Random, rand1, min,mid
	Random, rand2, mid,max
	Random, rand3, rand1,rand2
	return rand3
}


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


WM_SYSCOMMAND(wp, lp, msg, hwnd)  {
   static SC_CLOSE := 0xF060
   if (wp != SC_CLOSE)
      Return
   
   ExitApp
}