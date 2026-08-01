; when restarting script, code will update
#SingleInstance Force

; pressing 1 will trigger everything in sequence until Return
; we will use this to trigger clicks/key presses later
1::
msgbox, You pressed 1
return

; pressing Escape will close the script
Esc::
ExitApp
return