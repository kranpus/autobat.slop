@echo off
rem ============================================================
rem  Lets other devices on your HOME network reach the
rem  Legion Draft server (UDP 24702-24703, TCP 24704-24705 for browsers).
rem  Right-click this file and choose "Run as administrator".
rem  Only needed once.
rem ============================================================
net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)
netsh advfirewall firewall delete rule name="Legion Draft server" >nul 2>&1
netsh advfirewall firewall add rule name="Legion Draft server" dir=in action=allow protocol=UDP localport=24702-24703 profile=private,domain
netsh advfirewall firewall delete rule name="Legion Draft server (browsers)" >nul 2>&1
netsh advfirewall firewall add rule name="Legion Draft server (browsers)" dir=in action=allow protocol=TCP localport=24704-24705 profile=private,domain
if errorlevel 1 (
  echo Could not add the firewall rule.
) else (
  echo Done: devices on your home network can now reach the server.
  echo Make sure your Wi-Fi or Ethernet network is set to "Private" in
  echo Settings - Network and internet - your connection - Network profile type.
)
pause
