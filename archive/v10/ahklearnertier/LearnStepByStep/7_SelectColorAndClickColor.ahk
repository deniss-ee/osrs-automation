; when restarting script, code will update
#SingleInstance Force


Gui, New, AlwaysOnTop Resize MinSize
Gui, Add, Text, section w200, 1. Pressing 1 will store the current color at your cursor
Gui, Add, Text, w200, 2. Pressing 1 will trigger a click on the first pixel of the same color stored
Gui, Show,, Instructions

1::
; put current mouse position into x and y
MouseGetPos x, y
; get the color at coordinates, in this case current mouse position
; myColor will store the value
PixelGetColor, myColor, x, y , RGB
Msgbox, %myColor%
return

; pressing 2 will trigger everything in sequence until Return
2::
; x, y are the names of the variables that will get the position
; 0,0 is the top left corner to start looking for pixels
; A_Screen Width and A_ScreenHeight are special variables
; 0xFFFFFF is the hex color code for white
; 0 variation so only click pure white pixels
; Fast is needed for modern systems
; RGB so the color code is read as Red Green Blue
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, myColor, 0, Fast RGB
Click, %x%, %y%
return

; pressing Escape will close the script
Esc::
ExitApp
return