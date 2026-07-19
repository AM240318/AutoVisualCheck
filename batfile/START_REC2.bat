@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERROR_STATE=0"
set "LOG_SESSION_FILE=%~dp0log_session.marker"
set "LOG_SESSION_TEMP=%LOG_SESSION_FILE%.tmp"
set "SESSION_ID=UNKNOWN"
set "SESSION_START_UTC=UNKNOWN"
set "LOG_START_UTC=UNKNOWN"
set "SESSION_START_OK=0"
set "SESSION_ID_OK=0"

call :GetUtcNow SESSION_START_UTC SESSION_START_OK
if "%SESSION_START_OK%"=="0" (
  echo [ERROR] Failed to get SessionStartTimeUtc.
  set "ERROR_STATE=1"
)
call :GetGuid SESSION_ID SESSION_ID_OK
if "%SESSION_ID_OK%"=="0" (
  echo [ERROR] Failed to create SessionId.
  set "ERROR_STATE=1"
)

echo [INFO] Marker path: "%LOG_SESSION_FILE%"
echo [INFO] SessionId=%SESSION_ID% SessionStartTimeUtc=%SESSION_START_UTC%

REM CANログスタート
:CANLOG
REM echo CAN
timeout /t 2 > nul
if errorlevel 1 (
  echo [ERROR] CAN pre-wait failed.
  set "ERROR_STATE=1"
)
REM call "%~dp0start_stop_CAN_log.bat"
set "LOG_START_OK=0"
call :GetUtcNow LOG_START_UTC LOG_START_OK
if "%LOG_START_OK%"=="0" (
  echo [ERROR] Failed to get LogStartTimeUtc.
  set "ERROR_STATE=1"
)
call :WriteLogMarker
echo [INFO] LogStartTimeUtc=%LOG_START_UTC%
"%~dp0nircmd.exe" win activate title "Measurement Setup"
if errorlevel 1 (
  echo [ERROR] CAN window activation failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] CAN activation wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress t
if errorlevel 1 (
  echo [ERROR] CAN start key failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] CAN start wait failed.
  set "ERROR_STATE=1"
)

REM TeraTermログスタート
:TERATERMLOG
REM echo TERATERM
"%~dp0nircmd.exe" win activate title "COM42 - Tera Term VT"
if errorlevel 1 (
  echo [ERROR] COM42 window activation failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 activation wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress alt+f
if errorlevel 1 (
  echo [ERROR] COM42 Alt+F failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 menu wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress l
if errorlevel 1 (
  echo [ERROR] COM42 log command failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 log dialog wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress enter
if errorlevel 1 (
  echo [ERROR] COM42 log confirmation failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 confirmation wait failed.
  set "ERROR_STATE=1"
)

REM スクリーンショット
:SCREENSHOT
"%~dp0nircmd.exe" sendkeypress rwin+printscreen
if errorlevel 1 (
  echo [ERROR] Screenshot failed.
  set "ERROR_STATE=1"
)

if "%ERROR_STATE%"=="0" (
  echo [RESULT] START_REC2 completed successfully. ExitCode=0
) else (
  echo [RESULT] START_REC2 completed with errors. ExitCode=1
)
exit /b %ERROR_STATE%

:GetUtcNow
set "%~1=UNKNOWN"
set "%~2=0"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)" 2^>nul`) do (
  set "%~1=%%I"
  set "%~2=1"
)
goto :eof

:GetGuid
set "%~1=UNKNOWN"
set "%~2=0"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[Guid]::NewGuid().ToString()" 2^>nul`) do (
  set "%~1=%%I"
  set "%~2=1"
)
goto :eof

:WriteLogMarker
> "%LOG_SESSION_TEMP%" (
  echo Version=1
  echo SessionId=%SESSION_ID%
  echo SessionStartTimeUtc=%SESSION_START_UTC%
  echo LogStartTimeUtc=%LOG_START_UTC%
)
if errorlevel 1 (
  echo [ERROR] Failed to write temporary log session marker.
  set "ERROR_STATE=1"
  goto :eof
)
move /y "%LOG_SESSION_TEMP%" "%LOG_SESSION_FILE%" > nul
if errorlevel 1 (
  echo [ERROR] Failed to replace log session marker.
  set "ERROR_STATE=1"
  goto :eof
)
echo [INFO] Updated log session marker: "%LOG_SESSION_FILE%"
goto :eof
