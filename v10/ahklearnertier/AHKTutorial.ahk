; <COMPILER: v1.1.37.02>
#Persistent
#SingleInstance, Force
filename := "temp.ahk"
currQuestion := 1
questionsListNames := []
questionsList := []
IntroQs := []
arrr := IntroQs
questionsListNames.push("Introduction")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Welcome to the AHK Interactive tutorial!

Follow the intro to learn basics that will be used in later sections

The text area to the right is used to write your code

Edit the text to say
Hello World!

Then click Submit to run the script
Check your answer with the Solution

The script will be written to a temp.ahk file in the same directory
"
)
,
(LTrim 
"MsgBox, Hi
"
)
,
(LTrim 
"MsgBox, Hello World!
"
))
addMultipleChoice(arrr
,
(LTrim 
"Multiple choice questions

To answer these questions, change the number and click submit

1: AHK sucks
2: AHK is cool
"
)
,2)
addQuestion(arrr
,
(LTrim 
"Fix the typo type questions

AHK has some strange naming conventions and syntax structure

It's very common to make simple mistakes like this
"
)
,
(LTrim 
"MessageBox, Hi
"
)
,
(LTrim 
"MsgBox, Hi
"
))
addQuestion(arrr
,
(LTrim 
"Moving the mouse

The first number is the X coordinate or distance in pixels from the left of your screen
The second number is the Y coordinate or distance in pixels from the top of your screen

Currently the script will move the mouse to the top left of your screen
Try changing the numbers to make it move to a different position

See ""Mouse commands"" questions for more related questions
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 0, 0
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 400, 400
"
))
addQuestion(arrr
,
(LTrim 
"Hotkeys

Let's create a shortcut to trigger the script instead of running straight away

Add a hotkey by typing the shortcut key + :: before any code you want to be triggered e.g.
q::

After clicking submit, you will need to press the hotkey to trigger the script

Try to use other keys as the shortcut key!

See ""Hotkeys"" questions for more related questions
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 400, 400
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
q::
MouseMove, 400, 400
"
))
addQuestion(arrr
,
(LTrim 
"Running programs

AHK can help automate running programs, for example Notepad

AHK can also open URLs
Try modifying the script to open the website https://www.google.com

<a href=""https://www.autohotkey.com/docs/commands/Run.htm"">AHK Docs - Run</a>
"
)
,
(LTrim 
"Run, notepad
"
)
,
(LTrim 
"Run, https://www.google.com
"
))
addQuestion(arrr
,
(LTrim 
"Sending key presses

Using Notepad, we can show key presses as they happen

WinActivate is used to bring Notepad into focus

Type Hello World into Notepad

See ""Keypressing"" questions for more related questions

<a href=""https://www.autohotkey.com/docs/commands/Send.htm"">AHK Docs - Send</a>
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hi
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hello World
"
))
addQuestion(arrr
,
(LTrim 
"Loops

Instead of repeating a command over and over, you can use a loop

Increase the number of times the script loops

<a href=""https://www.autohotkey.com/docs/commands/Loop.htm"">AHK Docs - Loop</a>
"
)
,
(LTrim 
"loop, 1 {
MsgBox, Hi
}
"
)
,
(LTrim 
"loop, 5 {
MsgBox, Hi
}
"
))
addQuestion(arrr
,
(LTrim 
"Functions

You can group multiple commands together into a function

Calling the function will run the commands one after another without repeating yourself

Add any commands you have learned into the function and run the script

<a href=""https://www.autohotkey.com/docs/commands/Loop.htm"">AHK Docs - Loop</a>
"
)
,
(LTrim 
"myFunction()

myFunction() {

}
"
)
,
(LTrim 
"myFunction()

myFunction() {
MsgBox, Hi
MouseMove, 400, 400
Run, notepad
}
"
))
addQuestion(arrr
,
(LTrim 
"Variables

Variables let you use a custom name for storing values

You can then repeat that name to use the value over and over

You can also modify the value stored while still using the same name

You should not use spaces or special characters in variable names

Try changing the value of the variable

<a href=""https://www.autohotkey.com/docs/Variables.htm"">AHK Docs - Variables</a>
"
)
,
(LTrim 
"myVariable = 1
MsgBox, myVariable is equal to %myVariable%
Tooltip, myVariable is equal to %myVariable%
"
)
,
(LTrim 
"myVariable = 1
myVariable = haha
MsgBox, myVariable is equal to %myVariable%
Tooltip, myVariable is equal to %myVariable%
"
))
addQuestion(arrr
,
(LTrim 
"Random

The Random command creates a new variable with a random value between the min and max values provided

The value of the variable will only change when you call Random again

Add another Random command so both message boxes show a new random value

" . doc("Random")
)
,
(LTrim 
"Random, myVariable, 0, 100
MsgBox, %myVariable%
MsgBox, %myVariable%
"
)
,
(LTrim 
"Random, myVariable, 0, 100
MsgBox, %myVariable%
Random, myVariable, 0, 100
MsgBox, %myVariable%
"
))
addQuestion(arrr
,
(LTrim 
"If statements

To run a script only if a condition is met e.g. variable is above another value, use If expressions

In an if-else block, the first block will run if the expression is true, otherwise the second block will run

Fill in the else block

" . doc("If")
)
,
(LTrim 
"Random, myVariable, 0, 100
If (myVariable > 50) {
MsgBox, You won with %myVariable%!
} else {

}
"
)
,
(LTrim 
"Random, myVariable, 0, 100
If (myVariable > 50) {
MsgBox, You won with %myVariable%!
} else {
MsgBox, You lost with %myVariable%!
}
"
))
addQuestion(arrr
,
(LTrim 
"Sleep

To delay a script, use the Sleep command

The argument is how long to delay in milliseconds and can also be a variable

Add a sleep for 1 second before the message box shows

" . doc("Sleep")
)
,
(LTrim 
"Sleep, 0
Msgbox, Hi
"
)
,
(LTrim 
"Sleep, 1000
Msgbox, Hi
"
))
ColorQs := []
arrr := ColorQs
questionsListNames.push("Color detection")
questionsList.push(arrr)
markerFunc :=
(LTrim 
"


marker(color)
{
Gui marker: +LastFound +AlwaysOnTop +ToolWindow
Gui marker: Color, %color% 
Gui marker: Show, w50 h50 NA
}
"
)
addQuestion(arrr
,
(LTrim 
"Get pixel color

PixelGetColor is used to get the color at a specific x and y coordinate

The color is stored in the first parameter as a variable

Modify the script to display the found color in a msgbox

" . doc("PixelGetColor")
)
,
(LTrim 
"PixelGetColor, color, 0, 0, RGB
"
)
,
(LTrim 
"PixelGetColor, color, 0, 0, RGB
MsgBox, %color%
"
))
addMultipleChoice(arrr
,
(LTrim 
"RGB

The standard format to retrieve color is RGB - Red Green Blue

The color is stored in hexadecimal format, numbering from 0 to FF

F being the highest value, or 255

What color does 0x00FF00 stand for?

1: Red
2: Green
3: Blue
"
)
,2)
addQuestion(arrr
,
(LTrim 
"Get pixel color

Getting the color of a fixed coordinate is not that useful

Modify the script to use a hotkey and the current mouse coordinates

" . doc("PixelGetColor")
)
,
(LTrim 
"MouseGetPos, x, y
PixelGetColor, color, 0, 0, RGB
MsgBox, %color%
"
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
MsgBox, %color%
"
))
addQuestion(arrr
,
(LTrim 
"Get pixel color

You might want to run a script only if a color is found

0xFFFFFF represents white

Make the message box only appear if hovering over a white pixel using an If expression

" . doc("PixelGetColor")
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
MsgBox, This is white
"
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
if (color == ""0xFFFFFF"") {
MsgBox, This is white
}
"
))
addQuestion(arrr
,
(LTrim 
"Get pixel color

This ""marker"" function will help you display the color you've found onto the screen

Display the color green using the function in hexadecimal format

" . doc("PixelGetColor")
)
,
(LTrim 
"marker(""0xFF0000"")
" . markerFunc
)
,
(LTrim 
"marker(""0x00FF00"")
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Get pixel color

This ""marker"" function will help you display the color you've found onto the screen

Modify the script to display the color instead of using a msgbox

" . doc("PixelGetColor")
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
MsgBox, %color%

" . markerFunc
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
marker(color)
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Common mistakes

PixelGetColor default output is BGR, not RGB

See what color shows when you hover over a blue/red color

" . doc("PixelGetColor")
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y
marker(color)

" . markerFunc
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y, RGB
marker(color)
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Pixel search

PixelSearch is used when you want to check if a certain color pixel exists in an area

PixelSearch will set the x and y values of the top left corner if it finds the color

Run the script and see what coordinates show up depending on what window is active

" . doc("PixelSearch")
)
,
(LTrim 
"marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 3000, 3000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
)
,
(LTrim 
"marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 3000, 3000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Pixel search coord mode

To always get a consistent number on a fullscreen app, it's useful to change the base coordinates using Coord mode

PixelGetColor and PixelSearch are configured by CoordMode, Pixel

" . doc("PixelSearch")
)
,
(LTrim 
"marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 3000, 3000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 3000, 3000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Pixel search area

The 3rd to 6th parameter set the area to search for the color

Each pair of numbers represents the top left/bottom right area to search

0,0 means the top left corner of the screen

1000, 1000 means coordinate x: 1000, y: 1000

If the color is outside the search area, no coordinates will be found

Try move the colored square around the screen

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 1000, 1000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 1000, 1000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"A_ScreenWidth and A_ScreenHeight

A_ScreenWidth and A_ScreenHeight are special variables that match your screen resolution

e.g. for a 1920x1080 display, A_ScreenWidth: 1920, A_ScreenHeight: 1080

Submit script to see what resolution your screen is

" . doc("PixelSearch")
)
,
(LTrim 
"msgbox, %A_ScreenWidth% %A_ScreenHeight%
"
)
,
(LTrim 
"
"
))
addQuestion(arrr
,
(LTrim 
"Pixel search area

A_ScreenWidth and A_ScreenHeight are special variables that match your screen resolution

e.g. for a 1920x1080 display, A_ScreenWidth: 1920, A_ScreenHeight: 1080

Modify the script to search the bottom left corner

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, 1000, 1000, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, A_ScreenHeight/2, A_ScreenWidth/2, A_ScreenHeight, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Clicking found pixel

Once you have the X and Y coordinate, it is very simple to click the position

Make sure the CoordMode for Pixel and Mouse are the same

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0x9d6346, 3, Fast RGB
msgbox, %x% %y%
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0x9d6346, 3, Fast RGB
Click, %x% %y%
" . markerFunc
))
addMultipleChoice(arrr
,
(LTrim 
"Pixel search

Which direction does PixelSearch search the given area?

1: Top left to bottom right
2: Bottom left to top right
3: Bottom right to top left
"
)
,1)
addQuestion(arrr
,
(LTrim 
"Search from a different direction

If you want to find the first pixel from the bottom right, all you need to do is to switch the coordinates of the area you pass into the function

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, 0,0,A_ScreenWidth, A_ScreenHeight, 0x9d6346, 3, Fast RGB
Click, %x% %y% 0
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x9d6346"")
q::
PixelSearch, x, y, A_ScreenWidth, A_ScreenHeight,0,0, 0x9d6346, 3, Fast RGB
Click, %x% %y% 0
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"Color variation

The parameter after the color is the variation, or how different the found pixel can be from the given color

At 0, the color must exactly match
At 255, all colors will match

Increase the variation so the pixel search finds the color

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x00AA68"")
q::
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0x00AA66, 0, Fast RGB
Click, %x% %y% 0
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x00AA68"")
q::
PixelSearch, x, y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0x00AA66, 2, Fast RGB
Click, %x% %y% 0
" . markerFunc
))
addQuestion(arrr
,
(LTrim 
"PixelSearch in a loop

This code will make the color box move around the screen

Run a PixelSearch in a loop to make it follow the box

" . doc("PixelSearch")
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x9d6346"")
SetTimer, MoveGui, 1
x := 0
y := 0
return

MoveGui:
x := mod(x**1.01+1, A_ScreenWidth)
y := mod(y*1.1+1, A_ScreenHeight)
WinMove, % ""temp.ahk"",, %x%, %y%
return
" . markerFunc
)
,
(LTrim 
"CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
marker(""0x9d6346"")
SetTimer, MoveGui, 1
x := 0
y := 0
loop, 50 {
PixelSearch, x2, y2, 0, 0, A_ScreenWidth, A_ScreenHeight, 0x9d6346, 2, Fast RGB
Click, %x2% %y2% 0
}
return

MoveGui:
x := mod(x**1.01+1, A_ScreenWidth)
y := mod(y*1.1+1, A_ScreenHeight)
WinMove, % ""temp.ahk"",, %x%, %y%
return
" . markerFunc
))
MouseQs := []
arrr := MouseQs
questionsListNames.push("Mouse commands")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Coordmode

There are 3 modes for coordinates

Screen - relative to the desktop (entire screen)
Relative/Window - relative to the active window
Client - relative to the active window's client area

Try each of these and see where the mouse lands

<a href=""https://www.autohotkey.com/docs/commands/CoordMode.htm"">Coordmode</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 0, 0
"
)
,
(LTrim 
"CoordMode, Mouse, Client
MouseMove, 0, 0
"
))
addMultipleChoice(arrr
,
(LTrim 
"Coordmode

Which mode is the default?

1. Screen - relative to the desktop (entire screen)
2. Relative/Window - relative to the active window
3. Client - relative to the active window's client area
"
)
,2)
addQuestion(arrr
,
(LTrim 
"Fix the typo type questions

AHK has some strange naming conventions and syntax structure

It's very common to make simple mistakes like this
"
)
,
(LTrim 
"MessageBox, Hi
"
)
,
(LTrim 
"MsgBox, Hi
"
))
addQuestion(arrr
,
(LTrim 
"Mouse speed

MouseMove let's you set the speed of movement with its third parameter
0 fastest
100 slowest

Change the speed of mouse movement

<a href=""https://www.autohotkey.com/docs/commands/MouseMove.htm"">MouseMove</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 0, 0
"
)
,
(LTrim 
"CoordMode, Mouse, Window
MouseMove, 0, 0, 100
"
))
addQuestion(arrr
,
(LTrim 
"Mouse relative movement

MouseMove can also move relative to the current position with its 4th parameter when set to R

Make the mouse movement relative.

q:: is a Hotkey, after submitting press q to trigger the script

<a href=""https://www.autohotkey.com/docs/commands/MouseMove.htm"">MouseMove</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
q::
MouseMove, 10, 10
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
q::
MouseMove, 10, 10, 0, R
"
))
addQuestion(arrr
,
(LTrim 
"Clicking the mouse

Click is extremely simple at this point

Just add the word Click on a new line after the MouseMove

<a href=""https://www.autohotkey.com/docs/commands/Click.htm"">AHK Docs - Click</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 400, 400
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
MouseMove, 400, 400
Click
"
))
addQuestion(arrr
,
(LTrim 
"Clicking the mouse

You can also pass coordinates directly to the click

Notice that you do not put a comma inbetween.

<a href=""https://www.autohotkey.com/docs/commands/Click.htm"">AHK Docs - Click</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
Click, 0 0
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
Click, 400 400
"
))
addQuestion(arrr
,
(LTrim 
"Clicking the mouse

To change the type of click you perform, add an extra word at the end

Left/Right
Up/Down
0 to move without clicking

<a href=""https://www.autohotkey.com/docs/commands/Click.htm"">AHK Docs - Click</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
Click, 400 400
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
Click, 400 400 Right
"
))
HotkeysQs := []
arrr := HotkeysQs
questionsListNames.push("Hotkeys")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Hotkey modifiers

Say you want to hold Ctrl, Shift or Alt along with the key to trigger the script

AHK has special key codes you need to add to the beginning of the hotkey

# - Windows logo key
! - Alt
^ - Ctrl
+ - Shift

Try modifying the hotkey to Ctrl+q

<a href=""https://www.autohotkey.com/docs/Hotkeys.htm"">AHK Docs - Hotkeys</a>
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
q::
MouseMove, 400, 400
"
)
,
(LTrim 
"CoordMode, Mouse, Screen
^q::
MouseMove, 400, 400
"
))
addQuestion(arrr
,
(LTrim 
"Rebinding keys

Autohotkey makes this very simple, you can also use modifiers for more complex rebinding

After running this script, a will now type b

Even after rebinding a to b, you can still bind your b key to another key.

Try that now.

# - Windows logo key
! - Alt
^ - Ctrl
+ - Shift
"
)
,
(LTrim 
"a::b
"
)
,
(LTrim 
"a::b
b::c
"
))
KeypressQs := []
arrr := KeypressQs
questionsListNames.push("Keypressing")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Sending key presses

Try clicking submit, did you notice the ! did not show?

This is because it's a modifer key and will press Alt on the next letter afterward

Place {} around the ! to type it properly

<a href=""https://www.autohotkey.com/docs/commands/Send.htm"">AHK Docs - Send</a>
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hello World!
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hello World{!}
"
))
addQuestion(arrr
,
(LTrim 
"Sending key presses

There are many other special keys that need to have {} around them.

See the link below for the full list.

Try typing some more special characters and pressing Enter inbetween

<a href=""https://www.autohotkey.com/docs/commands/Send.htm#keynames"">AHK Docs - All key names</a>
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hello World{!}
"
)
,
(LTrim 
"Run, notepad
WinActivate, Untitled - Notepad
WinWaitActive, Untitled - Notepad
Send, Hello World{!}
Send, {Enter}
Send, {^}_{^}
"
))
RandomQs := []
arrr := RandomQs
questionsListNames.push("Random")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Random in a loop

A common mistake is to randomise once then reuse the variable

To refresh a random variable, you must call Random again

An easy way to do this is in a loop

Fix this code to always randomise the variable

" . doc("Random")
)
,
(LTrim 
"Random, myVariable, 100, 200
loop, 5 {
Msgbox, %myVariable%
}
"
)
,
(LTrim 
"loop, 5 {
Random, myVariable, 100, 200
Msgbox, %myVariable%
}
"
))
addQuestion(arrr
,
(LTrim 
"Random in a function

To make your own custom random, you can use a function

" . doc("Random")
)
,
(LTrim 
"myVariable := myRandom()
msgbox, %myVariable%
myRandom() {
return 4
}
"
)
,
(LTrim 
"myVariable := myRandom()
msgbox, %myVariable%
myRandom() {
Random, r, 5, 10
r += 5
return r
}
"
))
addQuestion(arrr
,
(LTrim 
"Click random spot

Use two random variables to click a random spot

" . doc("Random")
)
,
(LTrim 
"Random, x, 100, 200
Click, %x% 200 0
"
)
,
(LTrim 
"Random, x, 100, 200
Random, y, 100, 200
Click, %x% %y% 0
"
))
arrr := []
questionsListNames.push("OSRS Basic scripts")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Click one spot

Click clicks the current mouse location

" . doc("Click")
)
,
(LTrim 
"q::
Click
"
)
,
(LTrim 
"q::
Click
Sleep, 1000
Click
"
))
addQuestion(arrr
,
(LTrim 
"Click one spot loop

Loop as many times as you want to click for a long time

Edit the number of times to loop, now you have a functioning auto clicker

Now you can bot
High alchemy
Teleport spam
Cannoning
Anti-log splashing/blast furnace pump
Shooting stars

" . doc("Click")
)
,
(LTrim 
"q::
Loop, 1 {
Click
Sleep, 1000
}
"
)
,
(LTrim 
"q::
Loop, 5 {
Click
Sleep, 1000
}
"
))
addQuestion(arrr
,
(LTrim 
"Input number of loops at script start

Rather than editing the script, you can edit the number of loops on script start

" . doc("InputBox")
)
,
(LTrim 
"loops := 1
q::
Loop, %loops% {
Click
Sleep, 1000
}
"
)
,
(LTrim 
"InputBox, loops
q::
Loop, %loops% {
Click
Sleep, 1000
}
"
))
addQuestion(arrr
,
(LTrim 
"Save location to click

For more complex scripts you want to save one or more locations to click

Edit the script to save the click location saved by pressing Q

" . doc("MouseGetPos")
)
,
(LTrim 
"q::
MouseGetPos, x, y
return

w::
Click
return
"
)
,
(LTrim 
"q::
MouseGetPos, x, y
return

w::
Click %x% %y%
return
"
))
addQuestion(arrr
,
(LTrim 
"Save multiple locations to click

Copy the save location part to save multiple locations and then click them, using different variable names

Now you can bot
Fletching darts
Splashing curse spells
Power mine one iron rock
Thieving stalls

" . doc("MouseGetPos")
)
,
(LTrim 
"q::
MouseGetPos, x, y
return

w::
Click %x% %y%
return
"
)
,
(LTrim 
"q::
MouseGetPos, x0, y0
return

w::
MouseGetPos, x1, y1
return

e::
Click %x0% %y0%
Click %x1% %y1%
return
"
))
arrr := []
questionsListNames.push("OSRS Helper scripts")
questionsList.push(arrr)
addQuestion(arrr
,
(LTrim 
"Single high alch

" . doc("MouseGetPos")
)
,
(LTrim 
"^q::
MouseGetPos, x, y
return

q::
MouseGetPos, xx, yy
my_click(x, y, 15)
Random r1, 200,350
Sleep, % r1
Click
Click %xx% %yy% 0
return

my_click(x, y, r){
	Random r1, % x+r, % x-r
	Random r2, % y+r, % y-r
	Click %r1% %r2%
}
"
)
,
(LTrim 
"
"
))
addQuestion(arrr
,
(LTrim 
"Fletch

" . doc("MouseGetPos")
)
,
(LTrim 
"counter := 0
Settimer, lol, 1000
return

lol:
MouseGetPos, a, b
clicked:=False
while (counter > 0) {
my_click(x, y, 20)
my_click(xx, yy, 20)
counter--
sleep,100
clicked:=True
}
if (clicked) {
Click %a% %b% 0
}
return

^q::
MouseGetPos, x, y
return
^w::
MouseGetPos, xx, yy
return

Space::
counter++

return

my_click(x, y, r){
	Random r1, % x+r, % x-r
	Random r2, % y+r, % y-r
	Click %r1% %r2%
}
"
)
,
(LTrim 
"
"
))
addQuestion(arrr
,
(LTrim 
"Toggle two points

" . doc("MouseGetPos")
)
,
(LTrim 
"toggle := True

^q::
MouseGetPos, x, y
return
^w::
MouseGetPos, xx, yy
return

Space::
if (toggle) {
my_click(x, y, 20)
} else {
my_click(xx, yy, 20)
}
toggle:=!toggle
return

my_click(x, y, r){
	Random r1, % x+r, % x-r
	Random r2, % y+r, % y-r
	Click %r1% %r2%
}
"
)
,
(LTrim 
"
"
))
addQuestion(arrr
,
(LTrim 
"Prayer switch

" . doc("MouseGetPos")
)
,
(LTrim 
"^q::
MouseGetPos, x, y
return
^w::
MouseGetPos, xx, yy
return
^e::
MouseGetPos, xxx, yyy
return

q::
my_click(x,y,30)
return
w::
my_click(xx,yy,30)
return
e::
my_click(xxx,yyy,30)
return

my_click(x, y, r){
	Send, {F2}
	MouseGetPos, a, b
	Random r1, % x+r, % x-r
	Random r2, % y+r, % y-r
	Click %r1% %r2%
	Click %a% %b% 0
	Send, {Esc}
}
"
)
,
(LTrim 
"
"
))
addQuestion(arrr
,
(LTrim 
"Click single outline

" . doc("MouseGetPos")
)
,
(LTrim 
"Space::
ClickOutlineSingle(0xE83831)
return

ClickOutlineSingle(color, width := 200, instant:=True) {
	MyPixelSearch(startX1, startY1, color)
	MyPixelSearch(startX2, startY2, color, 3)

	if (!startX1 || !startX2) {
		return False
	}
	Random, randY, startY1, startY2
	randY := mid_rand(startY1, startY2)

	MyPixelSearch(startX3, startY3, color, 1,startX1-width,randY,startX1+width,randY)
	MyPixelSearch(startX4, startY4, color, 3,startX1-width,randY,startX1+width,randY)

	Random, randX, startX3, startX4
	randX := mid_rand(startX3, startX4)

	if (!startX3 || !startX4) {
		return False
	} else {
		Click %randX% %randY%
		return True
	}
}


MyPixelSearch(ByRef x, ByRef y, color, mode := 1, a:=0, b:=0, c:=-1, d:=-1, vari:= 3) {
	if (c == -1) {
		c := A_ScreenWidth
	}
	if (d == -1) {
		d := A_ScreenHeight
	}
	Switch mode
	{
	Case 1:
		PixelSearch, x, y, a, b, c, d, color , vari, Fast RGB
	Case 2:
		PixelSearch, x, y, c, b, a, d, color , vari, Fast RGB
	Case 3:
		PixelSearch, x, y, c, d, a, b, color , vari, Fast RGB
	Case 4:
		PixelSearch, x, y, a, d, c, b, color , vari, Fast RGB
	}
	if (!x || !y) {
		return False
	}
	return True
}
mid_rand(min, max){
	target := (min+max)/2
	Return target_random(min, target, max)
}

target_random(min, target, max){
	Random, lower, min, target
	Random, upper, target, max
	Random, weighted, lower, upper
	Return, weighted
}
"
)
,
(LTrim 
"
"
))
DYCQs := []
arrr := DYCQs
questionsListNames.push("Game - Defend Your Castle")
questionsList.push(arrr)
markerFunc :=
(LTrim 
"


marker(color)
{
Gui marker: +LastFound +AlwaysOnTop +ToolWindow
Gui marker: Color, %color% 
Gui marker: Show, w50 h50 NA
}
"
)
addQuestion(arrr
,
(LTrim 
"Open the game

If you haven't played this game before, spend a minute or two to play through

" . doc("Run")
)
,
(LTrim 
"Run, https://www.newgrounds.com/portal/view/102209
"
)
,
(LTrim 
"Run, https://www.newgrounds.com/portal/view/102209
"
))
addQuestion(arrr
,
(LTrim 
"Get the color of the stickman's head

Take a screenshot and use Window Spy

Or run the following script

" . doc("PixelGetColor")
)
,
(LTrim 
"q::
MouseGetPos, x, y
PixelGetColor, color, x, y
Tooltip, % color
"
)
,
(LTrim 
"0xCCCCCC
"
))
addQuestion(arrr
,
(LTrim 
"Pixel search

Fix the pixel search to find the color of the stickman

" . doc("PixelSearch")
)
,
(LTrim 
"q::
color := ""0xCCCCCC""
PixelSearch, FoundX, FoundY, 0, 0, 0, 0, color, 0, Fast RGB
MsgBox, % FoundX "" "" FoundY
"
)
,
(LTrim 
"q::
color := ""0xCCCCCC""
PixelSearch, FoundX, FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, color, 0, Fast RGB
If (ErrorLevel = 0) {
MsgBox, % FoundX "" "" FoundY
}
"
))
addQuestion(arrr
,
(LTrim 
"Click and drag

This script will use your mouse as the center of search so it can work on any screen size

Modify it so it performs a click then drag upwards

Test it using your screenshot of a stickman

" . doc("Click")
)
,
(LTrim 
"q::
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-size, % y-size, % x+size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
}
"
)
,
(LTrim 
"q::
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-size, % y-size, % x+size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 0 -600 0 Rel
Click, Up
}
"
))
addQuestion(arrr
,
(LTrim 
"Polish

Make the mouse move back to the original position after dragging

Change the search area to be a rectangle across the field

Increase the speed of the mouse

" . doc("Click")
)
,
(LTrim 
"q::
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-size, % y-size, % x+size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 0 -600 0 Rel
Click, Up
}
"
)
,
(LTrim 
"SetDefaultMouseSpeed, 1
q::
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-3*size, % y-size, % x+3*size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 0 -600 0 Rel
Click, Up
Click, %x% %y% 0
}
"
))
addQuestion(arrr
,
(LTrim 
"Polish

Make the script toggle whether it is active or not

" . doc("Click")
)
,
(LTrim 
"q::
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-size, % y-size, % x+size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 0 -600 0 Rel
Click, Up
}
"
)
,
(LTrim 
"SetDefaultMouseSpeed, 1
toggle := false
loop {
if (!toggle) {
continue
}
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100
PixelSearch, FoundX, FoundY, % x-3*size, % y-size, % x+3*size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 0 -600 0 Rel
Click, Up
Click, %x% %y% 0
}
}
q::
toggle := !toggle 
"
))
addQuestion(arrr
,
(LTrim 
"Polish

The castle also contains the color of the stickman's head

These changes should help reduce errors

Add a check for the mouse cursor

Make the PixelSearch switch search direction

Use the color of the stickman's body

" . doc("A_Cursor")
)
,
(LTrim 
"SetDefaultMouseSpeed, 1
toggle := false
loop {
if (!toggle) {
continue
}
MouseGetPos x, y
color := ""0xCCCCCC""
size := 100

PixelSearch, FoundX, FoundY, % x-3*size, % y-size, % x+3*size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {

Click, %FoundX% %FoundY% 0
Click, %FoundX% %FoundY% Down
Click, 300 -600 0 Rel
Click, Up
Click, %x% %y% 0
}
}
q::
toggle := !toggle 
"
)
,
(LTrim 
"SetDefaultMouseSpeed, 1
toggle := false
loop {
if (!toggle) {
continue
}
MouseGetPos x, y
color := ""0x1A1A1A""
size := 100
if (mod(A_Index, 2) == 1) {
	size *= -1
}
PixelSearch, FoundX, FoundY, % x-3*size, % y-size, % x+3*size, % y+size, color, 0, Fast RGB
If (ErrorLevel = 0) {
Click, %FoundX% %FoundY% 0
Sleep, 1
if (A_Cursor != ""Unknown"") {
Click, %x% %y% 0
continue
}
Click, %FoundX% %FoundY% Down
Click, 300 -600 0 Rel
Click, Up
Click, %x% %y% 0
}
}
q::
toggle := !toggle 
"
))
choices := Join("|",questionsListNames)
questions := questionsList[1]
Join(sep, params) {
for index,param in params
str .= param . sep
return SubStr(str, 1, -StrLen(sep))
}
Gui, New, hwndhGui Resize MinSize
Gui, Font, s12, Calibri
Gui, Add, DropDownList,section vQuestionsChoice gLoadQuestions AltSubmit Choose1, %choices%
Gui, Add, Text, w300 vQuestionNumber,
Gui, Add, Link, w300 r20 vDescription, Description
Gui, Font, s18, Courier New
Gui, Add, Edit, section ys r17 w800 vUserEnteredCode, Enter code
Gui, Font, s12, Calibri
Gui, Add, Button, xs w180 h60 gRunCode, Submit
Gui, Add, Button, yp xp+200 w90 gResetText, Reset
Gui, Add, Button, yp xp+90 w90 gShowSolution, Solution
Gui, Add, Button, xp-90 yp+30 w90 gPreviousQuestion, Previous
Gui, Add, Button, yp xp+90 w90 gNextQuestion, Next
Gui, Add, Link,xs, More questions to come! Vote here <a href="https://www.patreon.com/posts/ahk-interactive-67746401">Poll</a>
Gui, Show,, AHK Interactive Tutorial
GoSub, ResetText
return
addQuestion(ByRef arr, desc, initial, solution) {
arr.push({"desc":desc,"initial":initial,"solution":solution})
}
addMultipleChoice(ByRef arr, desc, solution) {
initial := "choice:="
initial .= "`n(`n0`n)"
loop, 20 {
initial .= "`n"
}
initial .= "Msgbox, % (choice == "
initial .= solution
initial .= " ? ""Correct"" : ""Incorrect"")"
arr.push({"desc":desc,"initial":initial,"solution":solution})
}
LoadQuestions:
Gui, Submit, NoHide
questions := questionsList[QuestionsChoice]
currQuestion := 1
GoSub, ResetText
return
PreviousQuestion:
currQuestion := max(1,currQuestion-1)
GoSub, ResetText
return
NextQuestion:
currQuestion := min(questions.length(),currQuestion+1)
GoSub, ResetText
return
ResetText:
Gui, Submit, NoHide
UpdateText("UserEnteredCode", "")
UpdateText("Description", questions[currQuestion].desc)
UpdateText("UserEnteredCode", questions[currQuestion].initial)
UpdateText("QuestionNumber", "Question " currQuestion "/" questions.length())
return
ShowSolution:
Gui, Submit, NoHide
UpdateText("UserEnteredCode", "")
UpdateText("UserEnteredCode", questions[currQuestion].solution)
return
RunCode:
Gui, Submit, NoHide
FileDelete, %filename%
UpdateText("Status", "Playing back")
ahk:=A_IsCompiled ? A_ScriptDir "\AutoHotkey.exe" : A_AhkPath
IfNotExist, %ahk%
{
MsgBox, 4096, Error, Can't Find %ahk% !
Exit
}
FileAppend, % UserEnteredCode, %filename%
Run, %ahk% /r "%filename%"
return
UpdateText(ControlID, NewText)
{
static OldText := {}
global hGui
if (OldText[ControlID] != NewText)
{
GuiControl, %hGui%:, % ControlID, % NewText
OldText[ControlID] := NewText
}
}
doc(name) {
retvalue := "<a href=""https://www.autohotkey.com/docs/"
retvalue .= name
retvalue .= ".htm"">AHK Docs - "
retvalue .= name
retvalue .= "</a>"
return retvalue
}
GuiClose:
GuiEscape:
ExitApp
