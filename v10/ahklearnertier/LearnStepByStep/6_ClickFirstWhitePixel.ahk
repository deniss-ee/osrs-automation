; when restarting script, code will update
#SingleInstance Force


Gui, New, AlwaysOnTop Resize MinSize
Gui, Add, Text, section w200, 1. Pressing 1 will trigger a click on the first white pixel on the screen from top left to bottom right
Gui, Show,, Instructions

; pressing 1 will trigger everything in sequence until Return
1::
; x, y are the names of the variables that will get the position
; 0,0 is the top left corner to start looking for pixels
; A_Screen Width and A_ScreenHeight are special variables
; 0xFFFFFF is the hex color code for white
; 0 variation so only click pure white pixels
; Fast is needed for modern systems
; RGB so the color code is read as Red Green Blue
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0xFFFFFF, 0, Fast RGB
Click, %x%, %y%
return

; pressing Escape will close the script
Esc::
ExitApp
return