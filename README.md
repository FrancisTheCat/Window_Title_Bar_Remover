# Window_Title_Bar_Remover
Simple Cli App to remove the *default* title bar from all windows, matching a specified title, classname or filename
```
Usage:
$ title_remover.exe <Criterium> <Verb> <Arg>

Verbs:
	- exact    | x = exact match
	- regex    | r = regex match
	- contains | c = arg contained

Criterium:
	- title | t = window title
	- class | c = window class
	- file  | f = window executable file path

Example:
$ title_remover.exe title exact 'Minecraft Launcher'
```
# Building:
```
odin.exe build .
```
