@echo off
setlocal
rem ============================================================
rem  Builds the browser (HTML5) version of the game into
rem  export\web\ and export\AutobatLegions-web.zip (for itch.io).
rem
rem  Needs Godot 4.3 (Windows 64-bit): put
rem  Godot_v4.3-stable_win64_console.exe in this "tools" folder or
rem  in the "server" folder - or set GODOT below to its full path.
rem  Also needs the 4.3 export templates: open the project in the
rem  Godot editor once, then Editor - Manage Export Templates -
rem  Download and Install.
rem ============================================================
set "GODOT="

cd /d "%~dp0.."
if defined GODOT goto have_godot
for %%F in ("%~dp0Godot_v4*_win64_console.exe" "%~dp0..\server\Godot_v4*_win64_console.exe" "%~dp0Godot_v4*_win64.exe") do if not defined GODOT if exist "%%~F" set "GODOT=%%~F"
if defined GODOT goto have_godot
echo Could not find Godot. Copy Godot_v4.3-stable_win64_console.exe into
echo   %~dp0
pause
exit /b 1

:have_godot
echo Importing the project...
"%GODOT%" --headless --path "%CD%" --import > export_web.log 2>&1
if not exist export\web mkdir export\web
del /q export\web\* >nul 2>&1
echo Exporting the Web build...
"%GODOT%" --headless --path "%CD%" --export-release "Web" export/web/index.html >> export_web.log 2>&1
if not exist export\web\index.wasm (
  echo Export failed. See export_web.log - are the Godot 4.3 export templates installed?
  pause
  exit /b 1
)
powershell -NoProfile -Command "Compress-Archive -Force -Path 'export\web\*' -DestinationPath 'export\AutobatLegions-web.zip'"
echo.
echo Done:
echo   export\web\                    the game's web files
echo   export\AutobatLegions-web.zip  upload this to itch.io
echo.
echo To play it on this PC, open the project in the Godot editor and use the
echo "Run in browser" button (top right, the HTML5 icon), or see WEB.md.
pause
