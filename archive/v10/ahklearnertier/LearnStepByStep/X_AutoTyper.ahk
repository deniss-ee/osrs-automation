; when restarting script, code will update
#SingleInstance Force
Tooltip, Press 1 to set word, 2 to type once, 3 to autotype every 5 seconds
return
1::
Tooltip
InputBox, words, Enter words to autotype
return

2::
SendInput, %words%
return

3::
loop {
SendInput, %words%
sleep, 5000
}
return

; pressing Escape will close the script
Esc::
ExitApp
return