@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERROR_STATE=0"
set "WARNING_STATE=0"
set "OBS_SCRIPT=%~dp0obs_record_start.ps1"
set "LEGACY_SESSION_FILE=%~dp0legacy_session.marker"
set "LEGACY_SESSION_TEMP=%LEGACY_SESSION_FILE%.tmp"
set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "CASE_VALID=0"
set "TAG_VALID=0"
set "ARGS_VALID=0"
set "CASE_CANONICAL="
set "TAG_NORMALIZED="
set "SESSION_ID=UNKNOWN"
set "SESSION_START_UTC=UNKNOWN"
set "VIDEO_START_UTC=UNKNOWN"
set "LOG_START_UTC=UNKNOWN"
set "OBS_START_SUCCEEDED=0"
set "SESSION_START_OK=0"
set "SESSION_ID_OK=0"
set "LEGACY_MARKER_CURRENT=0"
set "CASE_PRESENT=0"
set "TAG_PRESENT=0"
if defined RAW_CASE set "CASE_PRESENT=1"
if defined RAW_TAG set "TAG_PRESENT=1"
if not defined RAW_CASE set "CASE_VALID=1"
if not defined RAW_TAG set "TAG_VALID=1"

call :InvalidateLegacyMarker

if not exist "%OBS_SCRIPT%" (
  echo [ERROR] OBS start script was not found: "%OBS_SCRIPT%"
  set "ERROR_STATE=1"
)
if not exist "%~dp0nircmd.exe" (
  echo [ERROR] NirCmd was not found: "%~dp0nircmd.exe"
  set "ERROR_STATE=1"
)

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

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid non-empty CaseNo or Tag; recording will continue using only valid fields.
  set "ERROR_STATE=1"
)

echo [INFO] Raw arguments: CaseNoPresent=%CASE_PRESENT% TagPresent=%TAG_PRESENT%
echo [INFO] Normalized arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED%
echo [INFO] Marker path: "%LEGACY_SESSION_FILE%"
echo [INFO] OBS script path: "%OBS_SCRIPT%"
echo [INFO] NirCmd path: "%~dp0nircmd.exe"
echo [INFO] SessionId=%SESSION_ID% SessionStartTimeUtc=%SESSION_START_UTC%
call :WriteLegacyMarker

REM "画面のスクリーンショットをとる"
REM call "%~dp0"scrshot.bat

REM 録画スタート
set "VIDEO_START_OK=0"
call :GetUtcNow VIDEO_START_UTC VIDEO_START_OK
if "%VIDEO_START_OK%"=="0" (
  echo [ERROR] Failed to get VideoStartTimeUtc.
  set "ERROR_STATE=1"
)
call :WriteLegacyMarker
echo [INFO] VideoStartTimeUtc=%VIDEO_START_UTC%
REM timeout /t 3 > nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; try { $scriptArg=[char]34+$env:OBS_SCRIPT+[char]34; $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptArg) -WindowStyle Hidden -PassThru; if(-not $p.WaitForExit(20000)){ try { $p.Kill(); if(-not $p.WaitForExit(2000)){ exit 125 } } catch { exit 125 }; exit 124 }; exit $p.ExitCode } catch { exit 125 }"
set "OBS_EXIT_CODE=%ERRORLEVEL%"
if "%OBS_EXIT_CODE%"=="0" (
  set "OBS_START_SUCCEEDED=1"
  echo [INFO] OBS start result: success.
) else (
  set "ERROR_STATE=1"
  if "%OBS_EXIT_CODE%"=="124" (
    echo [ERROR] OBS start timed out after 20 seconds.
  ) else (
    echo [ERROR] OBS start failed. ExitCode=%OBS_EXIT_CODE%
  )
)
call :WriteLegacyMarker
REM timeout /t 3 > nul


REM CANログスタート
:CANLOG
REM echo CAN
timeout /t 2 > nul
if errorlevel 1 (
  echo [ERROR] CAN pre-start wait failed.
  set "ERROR_STATE=1"
)
REM call "%~dp0start_stop_CAN_log.bat"
set "LOG_START_OK=0"
call :GetUtcNow LOG_START_UTC LOG_START_OK
if "%LOG_START_OK%"=="0" (
  echo [ERROR] Failed to get LogStartTimeUtc.
  set "ERROR_STATE=1"
)
call :WriteLegacyMarker
echo [INFO] LogStartTimeUtc=%LOG_START_UTC%
"%~dp0nircmd.exe" win activate title "Measurement Setup"
if errorlevel 1 (
  echo [ERROR] Failed to activate Measurement Setup.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] CAN activation wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress t
if errorlevel 1 (
  echo [ERROR] Failed to send CAN log start key.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] CAN post-start wait failed.
  set "ERROR_STATE=1"
)

REM echo Teraterm42
REM call "%~dp0start_teraterm_ltog_com42.bat"
"%~dp0nircmd.exe" win activate title "COM42 - Tera Term VT"
if errorlevel 1 (
  echo [ERROR] Failed to activate COM42 Tera Term.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 activation wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress alt+f
if errorlevel 1 (
  echo [ERROR] Failed to open the COM42 File menu.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 File menu wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress l
if errorlevel 1 (
  echo [ERROR] Failed to select COM42 log start.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 log dialog wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress enter
if errorlevel 1 (
  echo [ERROR] Failed to confirm COM42 log start.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 post-start wait failed.
  set "ERROR_STATE=1"
)


REM if not "%minimized%"=="" goto :minimized
REM set minimized=true
REM start "" /min cmd /C "%~dpnx0" &*
REM goto EOF

REM :minimized
REM timeout /t 2 > nul
"%~dp0nircmd.exe" sendkeypress rwin+printscreen
if errorlevel 1 (
  echo [ERROR] Failed to capture the screenshot.
  set "ERROR_STATE=1"
)

if "%ERROR_STATE%"=="0" (
  if "%WARNING_STATE%"=="1" (
    echo [RESULT] START_REC completed with warnings. ExitCode=0
  ) else (
    echo [RESULT] START_REC completed successfully. ExitCode=0
  )
) else (
  echo [RESULT] START_REC completed with errors. ExitCode=1
)
exit /b %ERROR_STATE%

echo Teraterm39
REM call "%~dp0start_teraterm_log_com39.bat"
"%~dp0nircmd.exe" win activate title "COM39 - Tera Term VT"
timeout /t 1 > nul
"%~dp0nircmd.exe" sendkeypress alt+f
timeout /t 1 > nul
"%~dp0nircmd.exe" sendkeypress l
timeout /t 2 > nul
"%~dp0nircmd.exe" sendkeypress enter
timeout /t 1 > nul



exit /b

:GetUtcNow
set "UTC_RESULT="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)" 2^>nul`) do if not defined UTC_RESULT set "UTC_RESULT=%%I"
if not defined UTC_RESULT goto :eof
set "%~1=%UTC_RESULT%"
set "%~2=1"
goto :eof

:GetGuid
set "GUID_RESULT="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[Guid]::NewGuid().ToString()" 2^>nul`) do if not defined GUID_RESULT set "GUID_RESULT=%%I"
if not defined GUID_RESULT goto :eof
set "%~1=%GUID_RESULT%"
set "%~2=1"
goto :eof

:ValidateArguments
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c.Length -gt 0){ if($c -match '\A[0-9]+\z'){ $canonical=$c.TrimStart('0'); if($canonical.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$canonical) } } }; $t=$env:RAW_TAG; if($t.Length -gt 0 -and $t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
)
goto :eof

:WriteLegacyMarker
set "MARKER_WRITE_OK=0"
> "%LEGACY_SESSION_TEMP%" (
  echo Version=2
  echo SessionId=%SESSION_ID%
  echo ArgsValid=%ARGS_VALID%
  echo CaseNoCanonical=%CASE_CANONICAL%
  echo TagNormalized=%TAG_NORMALIZED%
  echo SessionStartTimeUtc=%SESSION_START_UTC%
  echo VideoStartTimeUtc=%VIDEO_START_UTC%
  echo LogStartTimeUtc=%LOG_START_UTC%
  echo ObsStartSucceeded=%OBS_START_SUCCEEDED%
)
if errorlevel 1 (
  echo [ERROR] Failed to write marker temporary file.
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [ERROR] Legacy session marker path is a directory and cannot be replaced: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
move /y "%LEGACY_SESSION_TEMP%" "%LEGACY_SESSION_FILE%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to replace legacy_session.marker.
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [ERROR] Replaced legacy session marker is not a regular file: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
if not exist "%LEGACY_SESSION_FILE%" (
  echo [ERROR] Replaced legacy session marker was not found: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
if exist "%LEGACY_SESSION_TEMP%" (
  echo [ERROR] Legacy session marker temporary file remained after replacement: "%LEGACY_SESSION_TEMP%"
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
set "LEGACY_MARKER_CURRENT=1"
set "MARKER_WRITE_OK=1"
echo [INFO] Marker updated: "%LEGACY_SESSION_FILE%"
goto :eof

:InvalidateLegacyMarker
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [ERROR] Legacy session marker path is a directory and could not be invalidated: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%LEGACY_SESSION_FILE%" goto :eof
del /f /q "%LEGACY_SESSION_FILE%" >nul 2>&1
if exist "%LEGACY_SESSION_FILE%" (
  echo [ERROR] Failed to invalidate legacy session marker: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
) else (
  echo [INFO] Invalidated legacy session marker: "%LEGACY_SESSION_FILE%"
)
goto :eof
