@echo off
setlocal
cd /d "%~dp0"
if not exist ".tools\hand-venv\Scripts\python.exe" (
  echo First run the OpenCV setup commands in SHOWCASE_GUIDE.md.
  pause
  exit /b 1
)
if not exist ".tools\godot\Godot_v4.5.1-stable_win64.exe" (
  echo Godot is missing. Run python tools/download_tools.py first.
  pause
  exit /b 1
)
".tools\hand-venv\Scripts\python.exe" -c "import cv2, numpy, mediapipe" >nul 2>&1
if errorlevel 1 (
  echo Install the webcam dependencies first:
  echo .tools\hand-venv\Scripts\python.exe -m pip install -r tools/requirements-hand.txt
  pause
  exit /b 1
)
set "APPDATA=%~dp0.tools\user"
set "LOCALAPPDATA=%~dp0.tools\user"
echo Starting Neon Volley with landmark hand controls and webcam preview.
echo Show one palm and press C in the camera/game or click Center. Hold still briefly.
echo Open palm moves away from your center. Return to center or lower your hand to stop without hitting. Close fist to serve/hit; reopen before another hit.
echo Press Q in the camera window to stop tracking. Close the game separately.
start "" "%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" --path "%~dp0." --log-file "%~dp0.tools\hand-demo.log" -- --opencv
".tools\hand-venv\Scripts\python.exe" tools\opencv_hand.py
pause
endlocal
