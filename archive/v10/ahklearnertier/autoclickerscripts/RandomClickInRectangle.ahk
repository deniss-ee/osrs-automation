#SingleInstance force
CoordMode, Mouse, Screen
SetKeyDelay -1
SetMouseDelay 0
SetBatchLines -1

isClicking:=False

Gui, a: New, hwndhGui AlwaysOnTop Resize MinSize
Gui, Add, Button, section w100 gStartClicking, Start F1 or F6
Gui, Add, Button, w100 yp x+5 gStopClicking, Stop F2 or F7
Gui, Add, Text,section xs+10 w200, Usage`n1. Set a speed range`n2. Alt+Left drag to draw rectangle`n3. Hit start

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

Gui, Add, Edit, section xs w50
Gui, Add, UpDown, vPositionChance Range0-100, 100
Gui, Add, Text,yp+3 x+5, Change position chance `%

Gui, Add, Text,xs vStatus w120, Idle
Gui, Add, Link,xs, <a href="https://www.patreon.com/nomscripts">Nom Scripts</a>

Gui, Show,, Auto Clicker
OnMessage(0x112, "WM_SYSCOMMAND")
return

ClickTimer:
loop {
	if (!isClicking) {
		Tooltip, Stopped!
		Sleep, 1000
		Tooltip
		return
	}
	Random chance, 0, 100
	if (chance <= PositionChance) {
		newX := midRandom(x1,x2)
		newY := midRandom(y1,y2)
		MouseMove, newX, newY
		Sleep, 1
	}
	
	Click
	Random, sec, DelaySecondsMin,DelaySecondsMax
	Random, milli, DelayMillisMin,DelayMillisMax
	delay := sec*1000 + milli
	Sleep, delay
}
return

F1::
F6::
StartClicking:
Gui, a: Submit, Nohide
if (!isClicking) {
	isClicking:=True
	Settimer, ClickTimer, -1
	UpdateText("Status", "Clicking!")
}
return

F2::
F7::
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

marker(X:=0, Y:=0, W:=0, H:=0)
{
T:=3,
w2:=W-T,
h2:=H-T

Gui marker: +LastFound +AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x80020
Gui marker: Color, Red ;Color
Gui marker: Show, w%W% h%H% x%X% y%Y% NA

WinSet, Transparent, 150
WinSet, Region, 0-0 %W%-0 %W%-%H% 0-%H% 0-0 %T%-%T% %w2%-%T% %w2%-%h2% %T%-%h2% %T%-%T%
Return
}

!LButton::
Tooltip
WinGetPos XN, YN, , , A
MouseGetPos x1, y1
While GetKeyState("LButton","P") {
   MouseGetPos x2, y2
   x:= (x1<x2)?(x1):(x2)
   y:= (y1<y2)?(y1):(y2)
   
   w:= Abs(x2-x1), h:= Abs(y2-y1)
   marker(x, y, w, h)
}
if (x2<x1) {
	tempX := x2
	x2 := x1
	x1 := tempX
}
if (y2<y1) {
	tempY := y2
	y2 := y1
	y1 := tempy
}
Return