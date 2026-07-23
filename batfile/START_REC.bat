@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ERROR_STATE=0"
set "WARNING_STATE=0"
set "FINAL_EXIT_CODE=0"
set "COMMAND_STATE=SUCCEEDED"
set "COMMAND_REASON=OK"
set "COMMAND_NAME=START_REC"

set "OBS_SCRIPT=%~dp0obs_record_start.ps1"
set "OBS_MODE=BOUNDED"
if /i "%RECORDING_USE_LEGACY_OBS_SCRIPT%"=="1" (
  set "OBS_SCRIPT=%~dp0obs_record_start_legacy.ps1"
  set "OBS_MODE=LEGACY"
)
set "OBS_RESULT_FILE=%~dp0obs_start.result"
set "LEGACY_SESSION_FILE=%~dp0legacy_session.marker"
set "LEGACY_SESSION_TEMP=%LEGACY_SESSION_FILE%.tmp"
set "COMMAND_RESULT_FILE=%~dp0recording_command.result"
set "OPERATION_LOCK_DIR=%~dp0recording_operation.lock"
set "TIMELINE_LOG=%~dp0recording_timeline.log"

set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "RAW_REPEAT=%~3"
set "RAW_OPERATION_ID=%~4"

set "CASE_VALID=0"
set "TAG_VALID=0"
set "REPEAT_VALID=0"
set "ARGS_VALID=0"
set "CASE_CANONICAL="
set "TAG_NORMALIZED="
set "REPEAT_CANONICAL="
set "CASE_PRESENT=0"
set "TAG_PRESENT=0"
set "REPEAT_PRESENT=0"
set "AUTOMATION_MODE=0"

set "OPERATION_ID="
set "OPERATION_ID_VALID=0"
set "LOCK_OWNED=0"
set "LOCK_ACQUIRE_REASON=NOT_ATTEMPTED"
set "PRESERVE_OPERATION_LOCK=0"
set "RESULT_WRITE_OK=0"

set "SESSION_ID=UNKNOWN"
set "SESSION_START_UTC=UNKNOWN"
set "VIDEO_START_UTC=UNKNOWN"
set "LOG_START_UTC=UNKNOWN"
set "COMMAND_START_UTC=UNKNOWN"
set "SESSION_START_OK=0"
set "SESSION_ID_OK=0"
set "LEGACY_MARKER_CURRENT=0"
set "OBS_START_SUCCEEDED=0"

set "OBS_OUTCOME=FAILED"
set "OBS_STATE=UNKNOWN"
set "OBS_REASON=NOT_RUN"
set "OBS_EXIT_CODE=99"
set "OBS_PROCESS_END_CONFIRMED=1"
set "CAN_START_RESULT=NOT_RUN"
set "TERATERM_START_RESULT=NOT_RUN"
set "SCREENSHOT_RESULT=NOT_RUN"
set "NIRCMD_EXIT_CODE=NOT_RUN"

if defined RAW_CASE set "CASE_PRESENT=1"
if defined RAW_TAG set "TAG_PRESENT=1"
if defined RAW_REPEAT set "REPEAT_PRESENT=1"
if defined RAW_OPERATION_ID set "AUTOMATION_MODE=1"
if not defined RAW_CASE set "CASE_VALID=1"
if not defined RAW_TAG set "TAG_VALID=1"
if not defined RAW_REPEAT set "REPEAT_VALID=1"

call :GetUtcNow COMMAND_START_UTC COMMAND_START_OK
call :PrepareOperationId
if "%OPERATION_ID_VALID%"=="0" (
  echo [ERROR] Invalid OperationId.
  set "COMMAND_STATE=FAILED"
  set "COMMAND_REASON=INVALID_OPERATION_ID"
  set "FINAL_EXIT_CODE=2"
  call :LogEvent "BAT_END" "FAILED"
  call :WriteCommandResult
  exit /b 2
)

call :LogEvent "BAT_START" "START_REC"
call :AcquireOperationLock
if "%LOCK_OWNED%"=="0" (
  echo [ERROR] Failed to acquire the recording operation lock. Reason=%LOCK_ACQUIRE_REASON% Path="%OPERATION_LOCK_DIR%"
  set "COMMAND_STATE=FAILED"
  set "COMMAND_REASON=%LOCK_ACQUIRE_REASON%"
  set "FINAL_EXIT_CODE=2"
  call :LogEvent "BAT_END" "FAILED"
  call :WriteCommandResult
  exit /b 2
)

call :InvalidateLegacyMarker

if not exist "%OBS_SCRIPT%" (
  echo [ERROR] OBS start script was not found: "%OBS_SCRIPT%"
  set "ERROR_STATE=1"
  set "COMMAND_REASON=OBS_SCRIPT_MISSING"
)
if not exist "%~dp0nircmd.exe" (
  echo [ERROR] NirCmd was not found: "%~dp0nircmd.exe"
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=NIRCMD_MISSING"
)

call :GetUtcNow SESSION_START_UTC SESSION_START_OK
if "%SESSION_START_OK%"=="0" (
  echo [ERROR] Failed to get SessionStartTimeUtc.
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=SESSION_TIME_FAILED"
)
call :GetGuid SESSION_ID SESSION_ID_OK
if "%SESSION_ID_OK%"=="0" (
  echo [ERROR] Failed to create SessionId.
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=SESSION_ID_FAILED"
)

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" if "%REPEAT_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid non-empty CaseNo, Tag, or Repeat; valid fields will still be used.
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=INVALID_ARGUMENT"
)

echo [INFO] OperationId=%OPERATION_ID% AutomationMode=%AUTOMATION_MODE%
echo [INFO] Raw arguments: CaseNoPresent=%CASE_PRESENT% TagPresent=%TAG_PRESENT% RepeatPresent=%REPEAT_PRESENT%
echo [INFO] Normalized arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED% Repeat=%REPEAT_CANONICAL%
echo [INFO] Marker path: "%LEGACY_SESSION_FILE%"
echo [INFO] OBS script path: "%OBS_SCRIPT%"
echo [INFO] OBS mode: %OBS_MODE%
echo [INFO] NirCmd path: "%~dp0nircmd.exe"

call :WriteLegacyMarker

set "VIDEO_START_OK=0"
call :GetUtcNow VIDEO_START_UTC VIDEO_START_OK
if "%VIDEO_START_OK%"=="0" (
  echo [ERROR] Failed to get VideoStartTimeUtc.
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=VIDEO_TIME_FAILED"
)
call :WriteLegacyMarker

if exist "%OBS_RESULT_FILE%" del /f /q "%OBS_RESULT_FILE%" >nul 2>&1
if not exist "%OBS_SCRIPT%" goto :AfterObsStart

call :LogEvent "OBS_POWERSHELL_START" "START"
call :RunObsPowerShell
call :LogEvent "OBS_POWERSHELL_END" "START"

if /i "%OBS_STATE%"=="RECORDING" (
  set "OBS_START_SUCCEEDED=1"
  if /i "%OBS_OUTCOME%"=="DEGRADED" (
    echo [WARN] OBS was already recording. Reason=%OBS_REASON%
    set "WARNING_STATE=1"
    if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=%OBS_REASON%"
  ) else (
    echo [INFO] OBS start result: success. Reason=%OBS_REASON%
  )
) else (
  echo [ERROR] OBS recording start was not confirmed. State=%OBS_STATE% Reason=%OBS_REASON% ExitCode=%OBS_EXIT_CODE%
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=%OBS_REASON%"
)

:AfterObsStart
call :WriteLegacyMarker
if "%OBS_PROCESS_END_CONFIRMED%"=="0" goto :AfterScreenshot

if not exist "%~dp0nircmd.exe" goto :AfterCanStart
call :LogEvent "CAN_NIRCMD_START" "START"
timeout /t 2 >nul
if errorlevel 1 (
  echo [ERROR] CAN pre-start wait failed.
  set "ERROR_STATE=1"
)
call :CheckWindowTitle "Measurement Setup" CAN_WINDOW_COUNT
"%~dp0nircmd.exe" win activate title "Measurement Setup"
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "CAN_NIRCMD_ACTIVATE" "Target=Measurement Setup ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to activate Measurement Setup.
  set "ERROR_STATE=1"
)
timeout /t 1 >nul
call :CheckWindowTitle "Measurement Setup" CAN_WINDOW_COUNT
"%~dp0nircmd.exe" win activate title "Measurement Setup"
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "CAN_NIRCMD_REACTIVATE" "Target=Measurement Setup ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to reactivate Measurement Setup.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress t
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "CAN_NIRCMD_KEY" "Target=Measurement Setup Key=t ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to send CAN log start key.
  set "ERROR_STATE=1"
  set "CAN_START_RESULT=FAILED"
) else (
  set "CAN_START_RESULT=SUCCEEDED"
)
timeout /t 1 >nul
call :LogEvent "CAN_NIRCMD_END" "%CAN_START_RESULT%"

:AfterCanStart
set "LOG_START_OK=0"
call :GetUtcNow LOG_START_UTC LOG_START_OK
if "%LOG_START_OK%"=="0" (
  echo [ERROR] Failed to get LogStartTimeUtc.
  set "ERROR_STATE=1"
)
call :WriteLegacyMarker

if not exist "%~dp0nircmd.exe" goto :AfterTeraTermStart
call :LogEvent "TERATERM_NIRCMD_START" "START"
call :CheckWindowTitle "COM42 - Tera Term VT" TERATERM_WINDOW_COUNT
"%~dp0nircmd.exe" win activate title "COM42 - Tera Term VT"
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "TERATERM_NIRCMD_ACTIVATE" "Target=COM42 - Tera Term VT ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to activate COM42 Tera Term.
  set "ERROR_STATE=1"
)
timeout /t 1 >nul
call :CheckWindowTitle "COM42 - Tera Term VT" TERATERM_WINDOW_COUNT
"%~dp0nircmd.exe" sendkeypress alt+f
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "TERATERM_NIRCMD_MENU" "Target=COM42 - Tera Term VT Key=Alt+F ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to open the COM42 File menu.
  set "ERROR_STATE=1"
)
timeout /t 1 >nul
"%~dp0nircmd.exe" sendkeypress l
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "TERATERM_NIRCMD_SELECT" "Target=COM42 - Tera Term VT Key=L ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to select COM42 log start.
  set "ERROR_STATE=1"
)
timeout /t 1 >nul
call :CheckWindowTitle "COM42 - Tera Term VT" TERATERM_WINDOW_COUNT
"%~dp0nircmd.exe" sendkeypress enter
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "TERATERM_NIRCMD_CONFIRM" "Target=COM42 - Tera Term VT Key=Enter ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to confirm COM42 log start.
  set "ERROR_STATE=1"
  set "TERATERM_START_RESULT=FAILED"
) else (
  set "TERATERM_START_RESULT=SUCCEEDED"
)
timeout /t 1 >nul
call :LogEvent "TERATERM_NIRCMD_END" "%TERATERM_START_RESULT%"

:AfterTeraTermStart
if not exist "%~dp0nircmd.exe" goto :AfterScreenshot
call :LogEvent "SCREENSHOT_NIRCMD_START" "START"
"%~dp0nircmd.exe" sendkeypress rwin+printscreen
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "SCREENSHOT_NIRCMD_KEY" "Target=Desktop Key=RWin+PrintScreen ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to capture the screenshot.
  set "ERROR_STATE=1"
  set "SCREENSHOT_RESULT=FAILED"
) else (
  set "SCREENSHOT_RESULT=SUCCEEDED"
)
call :LogEvent "SCREENSHOT_NIRCMD_END" "%SCREENSHOT_RESULT%"

:AfterScreenshot
if "%OBS_PROCESS_END_CONFIRMED%"=="0" goto :SetUnconfirmedObsStartFailure
if not "%ERROR_STATE%"=="0" if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=NON_OBS_OPERATION_FAILED"
if "%ERROR_STATE%"=="0" if "%WARNING_STATE%"=="1" if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=OPERATION_WARNING"
if "%ERROR_STATE%"=="0" if "%WARNING_STATE%"=="0" (
  set "COMMAND_STATE=SUCCEEDED"
  set "FINAL_EXIT_CODE=0"
)
if not "%ERROR_STATE%"=="0" (
  set "COMMAND_STATE=DEGRADED"
  set "FINAL_EXIT_CODE=1"
)
if "%ERROR_STATE%"=="0" if "%WARNING_STATE%"=="1" (
  set "COMMAND_STATE=DEGRADED"
  set "FINAL_EXIT_CODE=0"
)
goto :FinalizeStart

:SetUnconfirmedObsStartFailure
set "COMMAND_STATE=FAILED"
set "COMMAND_REASON=OBS_POWERSHELL_TERMINATION_UNCONFIRMED"
set "FINAL_EXIT_CODE=2"
set "PRESERVE_OPERATION_LOCK=1"

:FinalizeStart
if "%PRESERVE_OPERATION_LOCK%"=="0" call :ReleaseOperationLock
if "%PRESERVE_OPERATION_LOCK%"=="0" if "%LOCK_OWNED%"=="1" (
  set "COMMAND_STATE=FAILED"
  set "COMMAND_REASON=OPERATION_LOCK_RELEASE_FAILED"
  set "FINAL_EXIT_CODE=2"
)
call :LogEvent "BAT_END" "%COMMAND_STATE%"
call :WriteCommandResult
if "%RESULT_WRITE_OK%"=="0" (
  echo [ERROR] Failed to publish recording command result.
  exit /b 3
)

if /i "%COMMAND_STATE%"=="SUCCEEDED" (
  echo [RESULT] START_REC completed successfully. ExitCode=%FINAL_EXIT_CODE%
) else (
  echo [RESULT] START_REC completed in %COMMAND_STATE% state. Reason=%COMMAND_REASON% ExitCode=%FINAL_EXIT_CODE%
)
exit /b %FINAL_EXIT_CODE%

:PrepareOperationId
if not defined RAW_OPERATION_ID goto :GenerateOperationId
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$v=$env:RAW_OPERATION_ID; if($v -match '\A[A-Za-z0-9_-]+\z'){ Write-Output ('OPERATION_ID='+$v); Write-Output 'OPERATION_ID_VALID=1' }" 2^>nul`) do (
  if /i "%%A"=="OPERATION_ID" set "OPERATION_ID=%%B"
  if /i "%%A"=="OPERATION_ID_VALID" set "OPERATION_ID_VALID=%%B"
)
goto :eof

:GenerateOperationId
call :GetGuid OPERATION_ID OPERATION_ID_VALID
goto :eof

:AcquireOperationLock
mkdir "%OPERATION_LOCK_DIR%" >nul 2>&1
if errorlevel 1 (
  set "LOCK_ACQUIRE_REASON=OPERATION_LOCK_BUSY_OR_CREATE_FAILED"
  goto :eof
)
set "LOCK_OWNED=1"
set "LOCK_ACQUIRE_REASON=ACQUIRED"
> "%OPERATION_LOCK_DIR%\owner.marker" (
  echo Version=1
  echo OperationId=%OPERATION_ID%
  echo Command=%COMMAND_NAME%
  echo StartedTimeUtc=%COMMAND_START_UTC%
)
if errorlevel 1 goto :OperationLockMetadataFailed
if not exist "%OPERATION_LOCK_DIR%\owner.marker" goto :OperationLockMetadataFailed
call :LogEvent "LOCK_ACQUIRED" "%COMMAND_NAME%"
goto :eof

:OperationLockMetadataFailed
echo [ERROR] Failed to write recording operation lock metadata.
rmdir /s /q "%OPERATION_LOCK_DIR%" >nul 2>&1
set "LOCK_OWNED=0"
set "LOCK_ACQUIRE_REASON=OPERATION_LOCK_METADATA_FAILED"
goto :eof

:ReleaseOperationLock
if not "%LOCK_OWNED%"=="1" goto :eof
rmdir /s /q "%OPERATION_LOCK_DIR%" >nul 2>&1
if exist "%OPERATION_LOCK_DIR%\" (
  echo [WARN] Failed to release recording operation lock: "%OPERATION_LOCK_DIR%"
  set "WARNING_STATE=1"
  goto :eof
)
set "LOCK_OWNED=0"
call :LogEvent "LOCK_RELEASED" "%COMMAND_NAME%"
goto :eof

:CheckWindowTitle
set "TARGET_WINDOW_TITLE=%~1"
set "WINDOW_COUNT_RESULT=0"
set "WINDOW_COUNT_CAPTURED="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$c=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $env:TARGET_WINDOW_TITLE }).Count; Write-Output $c" 2^>nul`) do if not defined WINDOW_COUNT_CAPTURED (
  set "WINDOW_COUNT_RESULT=%%I"
  set "WINDOW_COUNT_CAPTURED=1"
)
set "%~2=%WINDOW_COUNT_RESULT%"
call :LogEvent "WINDOW_CHECK" "Target=%TARGET_WINDOW_TITLE% Count=%WINDOW_COUNT_RESULT%"
if "%WINDOW_COUNT_RESULT%"=="0" (
  echo [WARN] Target window was not found: "%TARGET_WINDOW_TITLE%"
  set "WARNING_STATE=1"
)
if not "%WINDOW_COUNT_RESULT%"=="0" if not "%WINDOW_COUNT_RESULT%"=="1" (
  echo [WARN] Multiple target windows were found: "%TARGET_WINDOW_TITLE%" Count=%WINDOW_COUNT_RESULT%
  set "WARNING_STATE=1"
)
goto :eof

:RunObsPowerShell
if /i "%OBS_MODE%"=="LEGACY" goto :RunLegacyObsPowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File "%OBS_SCRIPT%" -ResultPath "%OBS_RESULT_FILE%"
set "OBS_EXIT_CODE=%ERRORLEVEL%"
call :ReadObsResult
goto :eof

:RunLegacyObsPowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $scriptArg=[char]34+$env:OBS_SCRIPT+[char]34; $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptArg) -WindowStyle Hidden -PassThru; if(-not $p.WaitForExit(20000)){ try { $p.Kill(); if(-not $p.WaitForExit(2000)){ exit 125 } } catch { exit 125 }; exit 124 }; exit $p.ExitCode } catch { exit 125 }"
set "OBS_EXIT_CODE=%ERRORLEVEL%"
if "%OBS_EXIT_CODE%"=="0" (
  set "OBS_OUTCOME=SUCCEEDED"
  set "OBS_STATE=RECORDING"
  set "OBS_REASON=LEGACY_START_SUCCEEDED"
  goto :eof
)
set "OBS_OUTCOME=FAILED"
set "OBS_STATE=UNKNOWN"
if "%OBS_EXIT_CODE%"=="124" (
  set "OBS_REASON=LEGACY_START_TIMEOUT_TERMINATED"
  goto :eof
)
if "%OBS_EXIT_CODE%"=="125" (
  set "OBS_REASON=LEGACY_START_TERMINATION_UNCONFIRMED"
  set "OBS_PROCESS_END_CONFIRMED=0"
  goto :eof
)
set "OBS_REASON=LEGACY_START_FAILED"
goto :eof

:ReadObsResult
if not exist "%OBS_RESULT_FILE%" (
  set "OBS_OUTCOME=FAILED"
  set "OBS_STATE=UNKNOWN"
  set "OBS_REASON=OBS_RESULT_MISSING"
  goto :eof
)
for /f "usebackq tokens=1,* delims==" %%A in ("%OBS_RESULT_FILE%") do (
  if /i "%%A"=="Outcome" set "OBS_OUTCOME=%%B"
  if /i "%%A"=="State" set "OBS_STATE=%%B"
  if /i "%%A"=="Reason" set "OBS_REASON=%%B"
)
goto :eof

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
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c.Length -gt 0 -and $c -match '\A[0-9]+\z'){ $v=$c.TrimStart('0'); if($v.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$v) } }; $t=$env:RAW_TAG; if($t.Length -gt 0 -and $t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }; $r=$env:RAW_REPEAT; if($r.Length -gt 0 -and $r -match '\A[0-9]+\z'){ $v=$r.TrimStart('0'); if($v.Length -gt 0){ Write-Output 'REPEAT_VALID=1'; Write-Output ('REPEAT_CANONICAL='+$v) } }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
  if /i "%%A"=="REPEAT_VALID" set "REPEAT_VALID=%%B"
  if /i "%%A"=="REPEAT_CANONICAL" set "REPEAT_CANONICAL=%%B"
)
goto :eof

:WriteLegacyMarker
> "%LEGACY_SESSION_TEMP%" (
  echo Version=3
  echo SessionId=%SESSION_ID%
  echo OperationId=%OPERATION_ID%
  echo ArgsValid=%ARGS_VALID%
  echo CaseNoCanonical=%CASE_CANONICAL%
  echo TagNormalized=%TAG_NORMALIZED%
  echo RepeatCanonical=%REPEAT_CANONICAL%
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
  echo [ERROR] Legacy session marker path is a directory: "%LEGACY_SESSION_FILE%"
  set "ERROR_STATE=1"
  goto :eof
)
move /y "%LEGACY_SESSION_TEMP%" "%LEGACY_SESSION_FILE%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to replace legacy_session.marker.
  set "ERROR_STATE=1"
  if "%LEGACY_MARKER_CURRENT%"=="0" call :InvalidateLegacyMarker
  goto :eof
)
set "LEGACY_MARKER_CURRENT=1"
goto :eof

:InvalidateLegacyMarker
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [ERROR] Legacy session marker path is a directory and could not be invalidated.
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%LEGACY_SESSION_FILE%" goto :eof
del /f /q "%LEGACY_SESSION_FILE%" >nul 2>&1
if exist "%LEGACY_SESSION_FILE%" (
  echo [ERROR] Failed to invalidate legacy session marker.
  set "ERROR_STATE=1"
)
goto :eof

:WriteCommandResult
set "RESULT_WRITE_OK=0"
set "COMMAND_COMPLETE_UTC=UNKNOWN"
set "COMMAND_COMPLETE_OK=0"
call :GetUtcNow COMMAND_COMPLETE_UTC COMMAND_COMPLETE_OK
set "COMMAND_RESULT_TEMP=%COMMAND_RESULT_FILE%.tmp.%OPERATION_ID%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $lines=@('Version=1','OperationId='+$env:OPERATION_ID,'Command='+$env:COMMAND_NAME,'State='+$env:COMMAND_STATE,'ExitCode='+$env:FINAL_EXIT_CODE,'Reason='+$env:COMMAND_REASON,'StartedTimeUtc='+$env:COMMAND_START_UTC,'CompletedTimeUtc='+$env:COMMAND_COMPLETE_UTC,'CaseNoCanonical='+$env:CASE_CANONICAL,'TagNormalized='+$env:TAG_NORMALIZED,'RepeatCanonical='+$env:REPEAT_CANONICAL,'SessionId='+$env:SESSION_ID,'ObsState='+$env:OBS_STATE,'ObsReason='+$env:OBS_REASON,'ObsStartSucceeded='+$env:OBS_START_SUCCEEDED,'Mp4SelectionMode=NOT_APPLICABLE','EvidenceConfidence=NOT_APPLICABLE'); [IO.File]::WriteAllLines($env:COMMAND_RESULT_TEMP,$lines,[Text.UTF8Encoding]::new($false)); Move-Item -LiteralPath $env:COMMAND_RESULT_TEMP -Destination $env:COMMAND_RESULT_FILE -Force"
if errorlevel 1 goto :eof
if exist "%COMMAND_RESULT_TEMP%" goto :eof
set "RESULT_WRITE_OK=1"
goto :eof

:LogEvent
>> "%TIMELINE_LOG%" echo [%date% %time%] OperationId=%OPERATION_ID% Event=%~1 Detail=%~2
goto :eof
