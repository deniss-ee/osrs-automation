; when restarting script, code will update
#SingleInstance Force
Tooltip, Press 1 to start
return

1::
loop {
SendInput, {BackSpace}
sleep, 240000
}
return