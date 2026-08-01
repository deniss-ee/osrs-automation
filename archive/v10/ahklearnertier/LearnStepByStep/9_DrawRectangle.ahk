#SingleInstance Force
SetBatchLines, -1
#Persistent

Tooltip, Hold Alt+Left click to draw

Return

Esc::
ExitApp
Return

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
x1+=XN, y1+=YN
While GetKeyState("LButton","P") {
   MouseGetPos x2, y2
   x2+=XN, y2+=YN
   x:= (x1<x2)?(x1):(x2)    ;x-coordinate of the top left corner
   y:= (y1<y2)?(y1):(y2)    ;y-coordinate of the top left corner
   
   w:= Abs(x2-x1), h:= Abs(y2-y1)
   marker(x, y, w, h)
}
Return