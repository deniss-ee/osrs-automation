; when restarting script, code will update
#SingleInstance Force


Gui, New, AlwaysOnTop Resize MinSize
Gui, Add, Text, section w200, 1. Pressing 1 will press F5 instead
Gui, Show,, Instructions

; pressing 1 will trigger everything in sequence until Return
1::
Send, {F5}
return

; pressing Escape will close the script
Esc::
ExitApp
return