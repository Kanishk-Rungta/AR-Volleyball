@echo off
setlocal
set "APPDATA=%~dp0.tools\user"
set "LOCALAPPDATA=%~dp0.tools\user"
"%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" --path "%~dp0." --log-file "%~dp0.tools\desktop.log"
endlocal
