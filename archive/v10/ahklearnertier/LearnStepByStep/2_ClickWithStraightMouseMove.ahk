; when restarting script, code will update
#SingleInstance Force

Gui, New, hwndhGui AlwaysOnTop Resize MinSize
Gui, Add, Text, section w200, 1. Pressing 1 will trigger a click at a fixed location (600`,500)
Gui, Show,, Instructions

; pressing 1 will trigger everything in sequence until Return
1::
Click, 600, 500
return

; pressing Escape will close the script
Esc::
ExitApp
return