@echo off
setlocal
cd /d "%~dp0"
echo Neon Volley AR - Android setup and build
echo Read and answer Google's SDK license prompts yourself if shown.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_android.ps1" -InstallSdk -ExportApk
if errorlevel 1 (
  echo Build did not finish. Read the error above; see MOBILE_AR_GUIDE.md.
) else (
  echo Build finished. Connect your phone, then run Install Android AR.cmd.
)
pause
endlocal
