; when restarting script, code will update
#SingleInstance Force
; needed to use WindHumanMouse properly
SetMouseDelay -1


Gui, New, AlwaysOnTop Resize MinSize
Gui, Add, Text, section w200, 1. Pressing 1 will trigger a click at a randomised location using realistic mouse movements after a random delay
Gui, Show,, Instructions

; pressing 1 will trigger everything in sequence until Return
1::
; x will be a random number between 500 and 600
Random, x, 500, 600
; y will be a random number between 700 and 800
Random, y, 700, 800
; sleepTime will be a random number between 1000ms and 2000ms or 1 and 2 seconds
Random, sleepTime, 1000, 2000

; Sleep a random time before clicking a random location
Sleep, sleepTime
Click, %x%, %y%
return

; pressing Escape will close the script
Esc::
ExitApp
return