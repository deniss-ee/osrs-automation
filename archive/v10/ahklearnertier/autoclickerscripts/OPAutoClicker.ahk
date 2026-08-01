#SingleInstance force
CoordMode, Mouse, Screen
SetKeyDelay -1
SetMouseDelay 0
SetBatchLines -1

isClicking:=False

StartHotkey := "F6"
StopHotkey := StartHotkey
Hotkey, ~%StartHotkey%, Bowfa
prevStart := StartHotkey
prevStop := StartHotkey

XXX := 0
YYY := 0

Gui, a: New, hwndhGui AlwaysOnTop Resize MinSize
Gui, Add, GroupBox, section w380 r2, Click interval
Gui, Add, Edit, yp+20 xp+10 w50 r1
Gui, Add, UpDown, yp Range0-50000 vDelayHours, 0
Gui, Add, Text,yp+3 x+5, hours

Gui, Add, Edit, ys+20 x+5 w50
Gui, Add, UpDown, yp Range0-50000 vDelayMins, 0
Gui, Add, Text,yp+3 x+5, mins

Gui, Add, Edit, ys+20 x+5 w50
Gui, Add, UpDown, yp Range0-50000 vDelaySecs, 0
Gui, Add, Text,yp+3 x+5, secs

Gui, Add, Edit, ys+20 x+5 w50
Gui, Add, UpDown, yp Range0-50000 vDelayMillis, 300
Gui, Add, Text,yp+3 x+5, millis

Gui, Add, GroupBox, section xs w185 r4, Click options

Gui, Add, Text,ys+25 r1 xs+5, Mouse button:
Gui, Add, DropDownList,w80 yp-3 x+5 vClickButton, Left||Right|Middle

Gui, Add, Text,ys+55 r1 xs+5, Click type:
Gui, Add, DropDownList,w80 yp-3 x+22 vClickType, Single||Double|Triple


Gui, Add, GroupBox, section ys w185 r4, Click repeat

Gui, Add, Radio, ys+25 xs+10 vRepeatType, Repeat

Gui, Add, Radio, ys+55 xs+10 Checked, Repeat until stopped

Gui, Add, Edit, ys+22 xs+80 w50
Gui, Add, UpDown, yp Range0-50000 vRepeatCount, 1
Gui, Add, Text,yp+3 x+5, times

Gui, Add, GroupBox, section xs-195 w380 r2, Cursor position

Gui, Add, Radio, ys+23 xs+10 Checked vClickPositionType, Cursor position

Gui, Add, Radio, yp xs+150, 
Gui, Add, Button, yp-3 xp+20 w80 h20 gSetPosition, Pick location

Gui, Add, Text,yp+3 x+5, X
Gui, Add, Edit, yp-3 x+5 w40 vSelectPositionX gSetXY, 0
Gui, Add, Text,yp+3 x+5, Y
Gui, Add, Edit, yp-3 x+5 w40 vSelectPositionY gSetXY, 0

Gui, Add, Button, xs w180 h30 gStartClicking, Start
Gui, Add, Button, x+20 w180 h30 gStopClicking, Stop

Gui, Add, Hotkey, xs w180 h30 gSetHotkeys vStartHotkey, %StartHotkey%
Gui, Add, Hotkey, x+20 w180 h30 gSetHotkeys vStopHotkey, %StopHotkey%

Gui, Add, Text,xs vStatus w200, Idle
Gui, Add, Link,xs, <a href="https://www.patreon.com/nomscripts">Patreon</a> - Help me make more safe and open source autoclickers
Gui, Add, Link,xs, and also get access to my advanced random scripts and auto clickers!

Gui, Show,, OPen source Auto Clicker by Nom https://www.patreon.com/nomscripts
OnMessage(0x112, "WM_SYSCOMMAND")
return

SetXY:
Gui, a: Submit, Nohide
XXX := SelectPositionX
YYY := SelectPositionY
return

Bowfa:
if (isClicking) {
	GoSub, StopClicking
} else {
	GoSub, StartClicking
}
return

SetHotkeys:
if (StartHotkey == StopHotkey) {
	Hotkey, ~%prevStart% ,StartClicking, OFF
	Hotkey, ~%prevStop% ,StopClicking, OFF
	Hotkey, ~%StartHotkey%, Bowfa, ON
	prevStart := StartHotkey
	prevStop := StopHotkey
} else {
	if (StartHotkey) {
		Hotkey, ~%prevStart%, StartClicking, OFF
		Hotkey, ~%prevStart%, Bowfa, OFF
		Hotkey, ~%StartHotkey%, StartClicking, ON
		prevStart := StartHotkey
	}
	if (StopHotkey) {
		Hotkey, ~%prevStop% ,StopClicking, OFF
		Hotkey, ~%prevStop%, Bowfa, OFF
		Hotkey, ~%StopHotkey%, StopClicking, ON
		prevStop := StopHotkey
	}
}
UpdateText("Status", "Start: " StartHotkey "   Stop: " StopHotkey)
return

ClickTimer:
MouseGetPos, startX, startY
loop {
	if (!isClicking) {
		return
	}
	
	clickTimes := 1
	if (ClickType == "Double") {
		clickTimes := 2
	}
	if (ClickType == "Triple") {
		clickTimes := 3
	}
	loop, %clickTimes% {
		if (ClickPositionType == 2) {
			Click, %XXX% %YYY% 0
		}
		Click, %ClickButton%
		if (clickTimes > 1) {
			sleep, 1
		}
	}
	
	if (RepeatType == 1 && A_index >= RepeatCount) {
		isClicking := False
		continue
	}
	
	delay := DelayHours*60*60*1000 + DelayMins*60*100 + DelaySecs*1000 + DelayMillis
	Sleep, delay
}
return

StartClicking:
Gui, a: Submit, Nohide
if (!isClicking) {
	isClicking:=True
	Settimer, ClickTimer, -1
	UpdateText("Status", "Clicking!")
}
return

StopClicking:
Gui, a: Submit, Nohide
if (isClicking) {
	isClicking:=False
	UpdateText("Status", "Idle")
}
return

SetPosition:
KeyWait, LButton, D
MouseGetPos XXX, YYY
UpdateText("SelectPositionX", XXX)
UpdateText("SelectPositionY", YYY)
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