#NoEnv
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Client
SendMode Input
#SingleInstance Force
SetTitleMatchMode 2
#WinActivateForce
SetControlDelay 1
SetWinDelay 0
SetKeyDelay -1
SetMouseDelay -1
SetBatchLines -1

ToolTip, How to use`nPress F5 to toggle recording`nPress F6 to playback,0,0
SetTimer, RemoveToolTip, -10000
recording := False
points := []
currtime := A_TickCount
return

F5::
recording := !recording
MouseGetPos, currx, curry
if (recording) {
	points := {}
	currtime := A_TickCount
	ToolTip, Recording!,%currx%,%curry%
} else {
	ToolTip, Stopped recording,%currx%,%curry%
}
return

F6::
ToolTip
MouseGetPos, currx, curry
For index, p In points
{
	Sleep, p.d
	MouseClick,% p.c, p.x, p.y
}
return

~LButton::
if (!recording) {
	return
}
MouseGetPos, currx, curry
delay := A_TickCount-currtime
currtime := A_TickCount
points.push({"x":currx,"y":curry,"d":delay,"c":"left"})
ToolTip, Added LClick %delay% ms,%currx%,%curry%
return

~RButton::
if (!recording) {
	return
}
MouseGetPos, currx, curry
delay := A_TickCount-currtime
currtime := A_TickCount
points.push({"x":currx,"y":curry,"d":delay,"c":"right"})
ToolTip, Added RClick %delay% ms,%currx%,%curry%
return

Esc::
ExitApp
return


RemoveToolTip:
ToolTip
return