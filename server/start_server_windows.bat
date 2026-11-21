@echo off
setlocal
rem ============================================================
rem  Legion Draft server for Windows
rem  Double-click to start. Close this window to stop the server.
rem
rem  Needs Godot 4.3 (Windows 64-bit):
rem    https://godotengine.org/download/archive/4.3-stable/
rem  Unzip it and copy Godot_v4.3-stable_win64_console.exe into
rem  this "server" folder - or set GODOT below to its full path.
rem ============================================================
set "GODOT="
set "PORT=24702"

cd /d "%~dp0.."
set "PROJECT=%CD%"

rem Look for Godot next to this script if GODOT isn't set.
if defined GODOT goto have_godot
for %%F in ("%~dp0Godot_v4*_win64_console.exe" "%~dp0Godot_v4*_win64.exe") do if not defined GODOT if exist "%%~F" set "GODOT=%%~F"
if defined GODOT goto have_godot
echo Could not find Godot.
echo Download Godot 4.3 for Windows, unzip it, and copy
echo Godot_v4.3-stable_win64_console.exe into this folder:
echo   %~dp0
echo.
pause
exit /b 1

:have_godot
rem Import every time: it registers scripts added by updates (otherwise the
rem server fails with "Identifier ... not declared"). After the first run
rem this only takes a few seconds.
echo Preparing the project (the first time takes a minute)...
"%GODOT%" --headless --path "%PROJECT%" --import > "%~dp0import.log" 2>&1
if not exist "%PROJECT%\.godot\global_script_class_cache.cfg" (
  echo Importing the project failed. See server\import.log for details.
  pause
  exit /b 1
)
echo.
echo ============================================================
echo  Other devices in your house: open the game, go to
echo  Legion Draft - Online, and set Server to one of these:
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)\.' } | ForEach-Object { '     ' + $_.IPAddress + '    [' + $_.InterfaceAlias + ']' }"
echo  On this PC itself, use:  localhost
echo.
echo  Browser version (after tools\build_web_windows.bat): open
echo     http://ADDRESS:24705   using one of the addresses above
echo ============================================================
echo.
echo Starting the server on UDP port %PORT%. Close this window to stop it.
echo.
"%GODOT%" --headless --path "%PROJECT%" -- --server --port=%PORT%
echo.
echo The server stopped.
pause
