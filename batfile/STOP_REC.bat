@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ERROR_STATE=0"
set "WARNING_STATE=0"
set "FINAL_EXIT_CODE=0"
set "COMMAND_STATE=SUCCEEDED"
set "COMMAND_REASON=OK"
set "COMMAND_NAME=STOP_REC"

set "USER_DATA_ROOT=%USERPROFILE%"
if not defined USER_DATA_ROOT set "USER_DATA_ROOT=C:\Users\TMC"
set "BASEDIR=%USER_DATA_ROOT%\Desktop\LogZips"
set "CAPTURE_DIR=%USER_DATA_ROOT%\Videos\Captures"
set "SCREENSHOT_DIR=%USER_DATA_ROOT%\Pictures\Screenshots"
set "TERATERM_LOG_DIR=C:\teraterm-5.2\log"
set "CAN_LOG_DIR=%BASEDIR%\CANtemp"

set "OBS_SCRIPT=%~dp0obs_record_stop.ps1"
set "OBS_MODE=BOUNDED"
if /i "%RECORDING_USE_LEGACY_OBS_SCRIPT%"=="1" (
  set "OBS_SCRIPT=%~dp0obs_record_stop_legacy.ps1"
  set "OBS_MODE=LEGACY"
)
set "OBS_RESULT_FILE=%~dp0obs_stop.result"
set "LEGACY_SESSION_FILE=%~dp0legacy_session.marker"
set "COMMAND_RESULT_FILE=%~dp0recording_command.result"
set "OPERATION_LOCK_DIR=%~dp0recording_operation.lock"
set "TIMELINE_LOG=%~dp0recording_timeline.log"
set "FILE_PROCESS_OUTPUT=%~dp0file_process.output"

set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "RAW_REPEAT=%~3"
set "RAW_OPERATION_ID=%~4"

set "CASE_VALID=0"
set "TAG_VALID=0"
set "REPEAT_VALID=0"
set "ARGS_VALID=0"
set "CASE_CANONICAL="
set "CASE_DISPLAY="
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
set "COMMAND_START_UTC=UNKNOWN"

set "MARKER_PRESENT=0"
set "MARKER_VALID=0"
set "MARKER_VERSION=UNKNOWN"
set "MARKER_SESSION_ID=UNKNOWN"
set "MARKER_OPERATION_ID="
set "MARKER_ARGS_VALID=UNKNOWN"
set "MARKER_CASE_CANONICAL="
set "MARKER_TAG_NORMALIZED="
set "MARKER_REPEAT_CANONICAL="
set "MARKER_SESSION_START_UTC=UNKNOWN"
set "MARKER_VIDEO_START_UTC=UNKNOWN"
set "MARKER_LOG_START_UTC=UNKNOWN"
set "MARKER_OBS_START_SUCCEEDED=UNKNOWN"

set "NAMING_MODE=NORMAL"
set "SELECTION_MODE=LATEST"
set "DT=UNKNOWN"
set "DT_OK=0"
set "DEST_FOLDER="
set "FILE_PREFIX="
set "NAME_BASE="
set "DEST_READY=0"

set "OBS_OUTCOME=FAILED"
set "OBS_STATE=UNKNOWN"
set "OBS_REASON=NOT_RUN"
set "OBS_OUTPUT_PATH="
set "OBS_FILE_STABLE=0"
set "OBS_EXIT_CODE=99"
set "OBS_PROCESS_END_CONFIRMED=1"

set "MP4_SELECTION_MODE=NOT_PROCESSED"
set "EVIDENCE_CONFIDENCE=NOT_AVAILABLE"
set "MP4_SOURCE_PATH="
set "MP4_SOURCE_CREATION_UTC="
set "MP4_SOURCE_LAST_WRITE_UTC="
set "MP4_SOURCE_LENGTH="

set "CAN_STOP_RESULT=NOT_RUN"
set "TERATERM_STOP_RESULT=NOT_RUN"
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

call :LogEvent "BAT_START" "STOP_REC"
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

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" if "%REPEAT_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid non-empty CaseNo, Tag, or Repeat; marker or date-time fallback will be used.
  set "ERROR_STATE=1"
  set "COMMAND_REASON=INVALID_ARGUMENT"
)

if not exist "%OBS_SCRIPT%" (
  echo [ERROR] OBS stop script was not found: "%OBS_SCRIPT%"
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=OBS_SCRIPT_MISSING"
)
if not exist "%~dp0nircmd.exe" (
  echo [ERROR] NirCmd was not found: "%~dp0nircmd.exe"
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=NIRCMD_MISSING"
)

if exist "%LEGACY_SESSION_FILE%" (
  set "MARKER_PRESENT=1"
  call :ReadLegacyMarker
)
if "%MARKER_VALID%"=="1" (
  echo [INFO] Marker path: "%LEGACY_SESSION_FILE%" Status=valid Version=%MARKER_VERSION%
  echo [INFO] SessionId=%MARKER_SESSION_ID% START OperationId=%MARKER_OPERATION_ID%
) else (
  if "%MARKER_PRESENT%"=="1" (
    echo [ERROR] Marker path: "%LEGACY_SESSION_FILE%" Status=invalid
  ) else (
    echo [ERROR] Marker path: "%LEGACY_SESSION_FILE%" Status=missing
  )
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=START_MARKER_UNAVAILABLE"
)

if "%MARKER_VALID%"=="1" call :ApplyMarkerArgumentFallback
call :DetermineModes

echo [INFO] OperationId=%OPERATION_ID% AutomationMode=%AUTOMATION_MODE%
echo [INFO] Effective arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED% Repeat=%REPEAT_CANONICAL%
echo [INFO] OBS mode: %OBS_MODE% Script="%OBS_SCRIPT%"

call :GetStopDateTime
if "%DT_OK%"=="0" (
  echo [ERROR] Failed to get STOP local date and time.
  set "ERROR_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=STOP_TIME_FAILED"
)

if not exist "%~dp0nircmd.exe" goto :AfterCanStop
call :LogEvent "CAN_NIRCMD_START" "STOP"
timeout /t 2 >nul
call :CheckWindowTitle "Measurement Setup" CAN_WINDOW_COUNT
"%~dp0nircmd.exe" win activate title "Measurement Setup"
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "CAN_NIRCMD_ACTIVATE" "Target=Measurement Setup ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] Failed to activate Measurement Setup.
  set "ERROR_STATE=1"
)
timeout /t 2 >nul
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
  echo [ERROR] Failed to send CAN log stop key.
  set "ERROR_STATE=1"
  set "CAN_STOP_RESULT=FAILED"
) else (
  set "CAN_STOP_RESULT=SUCCEEDED"
)
timeout /t 2 >nul
call :LogEvent "CAN_NIRCMD_END" "%CAN_STOP_RESULT%"

:AfterCanStop
if exist "%OBS_RESULT_FILE%" del /f /q "%OBS_RESULT_FILE%" >nul 2>&1
if not exist "%OBS_SCRIPT%" goto :AfterObsStop

call :LogEvent "OBS_POWERSHELL_START" "STOP"
call :RunObsPowerShell
call :LogEvent "OBS_POWERSHELL_END" "STOP"
if /i "%OBS_OUTCOME%"=="SUCCEEDED" (
  echo [INFO] OBS stop result: success. Reason=%OBS_REASON%
) else (
  echo [WARN] OBS stop completed without a verified stable output. State=%OBS_STATE% Reason=%OBS_REASON% ExitCode=%OBS_EXIT_CODE%
  set "WARNING_STATE=1"
  if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=%OBS_REASON%"
)

:AfterObsStop
if "%OBS_PROCESS_END_CONFIRMED%"=="0" goto :AbortStopAfterObs
if not exist "%~dp0nircmd.exe" goto :AfterTeraTermStop
call :LogEvent "TERATERM_NIRCMD_START" "STOP"
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
  echo [ERROR] COM42 Alt+F failed.
  set "ERROR_STATE=1"
)
timeout /t 1 >nul
call :CheckWindowTitle "COM42 - Tera Term VT" TERATERM_WINDOW_COUNT
"%~dp0nircmd.exe" sendkeypress q
set "NIRCMD_EXIT_CODE=%ERRORLEVEL%"
call :LogEvent "TERATERM_NIRCMD_CONFIRM" "Target=COM42 - Tera Term VT Key=Q ExitCode=%NIRCMD_EXIT_CODE%"
if not "%NIRCMD_EXIT_CODE%"=="0" (
  echo [ERROR] COM42 stop command failed.
  set "ERROR_STATE=1"
  set "TERATERM_STOP_RESULT=FAILED"
) else (
  set "TERATERM_STOP_RESULT=SUCCEEDED"
)
timeout /t 5 >nul
call :LogEvent "TERATERM_NIRCMD_END" "%TERATERM_STOP_RESULT%"

:AfterTeraTermStop
if "%DT_OK%"=="1" call :PrepareDestination
if "%DEST_READY%"=="1" call :ProcessAllFiles
call :DeleteLegacyMarker
goto :FinalizeStopState

:AbortStopAfterObs
set "ERROR_STATE=1"
set "COMMAND_STATE=FAILED"
set "COMMAND_REASON=OBS_POWERSHELL_TERMINATION_UNCONFIRMED"
set "FINAL_EXIT_CODE=2"
set "PRESERVE_OPERATION_LOCK=1"

:FinalizeStopState
if "%OBS_PROCESS_END_CONFIRMED%"=="0" goto :FinalizeStop
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

:FinalizeStop
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

echo [RESULT] NamingMode=%NAMING_MODE% Mp4SelectionMode=%MP4_SELECTION_MODE% EvidenceConfidence=%EVIDENCE_CONFIDENCE%
if /i "%COMMAND_STATE%"=="SUCCEEDED" (
  echo [RESULT] STOP_REC completed successfully. ExitCode=%FINAL_EXIT_CODE%
) else (
  echo [RESULT] STOP_REC completed in %COMMAND_STATE% state. Reason=%COMMAND_REASON% ExitCode=%FINAL_EXIT_CODE%
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
set "OBS_OUTPUT_PATH="
set "OBS_FILE_STABLE=0"
if "%OBS_EXIT_CODE%"=="0" (
  set "OBS_OUTCOME=DEGRADED"
  set "OBS_STATE=NOT_RECORDING"
  set "OBS_REASON=LEGACY_STOP_OUTPUT_UNAVAILABLE"
  goto :eof
)
set "OBS_OUTCOME=FAILED"
set "OBS_STATE=UNKNOWN"
if "%OBS_EXIT_CODE%"=="124" (
  set "OBS_REASON=LEGACY_STOP_TIMEOUT_TERMINATED"
  goto :eof
)
if "%OBS_EXIT_CODE%"=="125" (
  set "OBS_REASON=LEGACY_STOP_TERMINATION_UNCONFIRMED"
  set "OBS_PROCESS_END_CONFIRMED=0"
  goto :eof
)
set "OBS_REASON=LEGACY_STOP_FAILED"
goto :eof

:ValidateArguments
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c.Length -gt 0 -and $c -match '\A[0-9]+\z'){ $v=$c.TrimStart('0'); if($v.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$v); Write-Output ('CASE_DISPLAY='+$v.PadLeft(3,'0')) } }; $t=$env:RAW_TAG; if($t.Length -gt 0 -and $t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }; $r=$env:RAW_REPEAT; if($r.Length -gt 0 -and $r -match '\A[0-9]+\z'){ $v=$r.TrimStart('0'); if($v.Length -gt 0){ Write-Output 'REPEAT_VALID=1'; Write-Output ('REPEAT_CANONICAL='+$v) } }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="CASE_DISPLAY" set "CASE_DISPLAY=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
  if /i "%%A"=="REPEAT_VALID" set "REPEAT_VALID=%%B"
  if /i "%%A"=="REPEAT_CANONICAL" set "REPEAT_CANONICAL=%%B"
)
goto :eof

:ReadLegacyMarker
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $values=@{}; foreach($line in [IO.File]::ReadAllLines($env:LEGACY_SESSION_FILE)){ $i=$line.IndexOf('='); if($i -lt 1){ throw 1 }; $key=$line.Substring(0,$i); if($values.Keys -ccontains $key){ throw 1 }; $values[$key]=$line.Substring($i+1) }; $base=@('Version','SessionId','ArgsValid','CaseNoCanonical','TagNormalized','SessionStartTimeUtc','VideoStartTimeUtc','LogStartTimeUtc','ObsStartSucceeded'); foreach($key in $base){ if(-not ($values.Keys -ccontains $key)){ throw 1 } }; $version=$values['Version']; if($version -cne '1' -and $version -cne '2' -and $version -cne '3'){ throw 1 }; $guid=[Guid]::Empty; if(-not [Guid]::TryParseExact($values['SessionId'],'D',[ref]$guid)){ throw 1 }; $args=$values['ArgsValid']; if($args -cne '0' -and $args -cne '1'){ throw 1 }; $case=$values['CaseNoCanonical']; if($version -ceq '1' -and $case -ceq 'UNKNOWN'){ $case='' }; if($case.Length -gt 0){ if($case -notmatch '\A[0-9]+\z'){ throw 1 }; $case=$case.TrimStart('0'); if($case.Length -eq 0){ throw 1 } }; $tag=$values['TagNormalized']; if($version -ceq '1' -and $tag -ceq 'UNKNOWN'){ $tag='' }; if($tag.Length -gt 0 -and $tag -notmatch '\A[A-Z0-9_-]+\z'){ throw 1 }; $repeat=''; $operation=''; if($version -ceq '3'){ foreach($key in @('OperationId','RepeatCanonical')){ if(-not ($values.Keys -ccontains $key)){ throw 1 } }; $operation=$values['OperationId']; if($operation -notmatch '\A[A-Za-z0-9_-]+\z'){ throw 1 }; $repeat=$values['RepeatCanonical']; if($repeat.Length -gt 0){ if($repeat -notmatch '\A[0-9]+\z'){ throw 1 }; $repeat=$repeat.TrimStart('0'); if($repeat.Length -eq 0){ throw 1 } } }; foreach($name in @('SessionStartTimeUtc','VideoStartTimeUtc','LogStartTimeUtc')){ [DateTime]$parsed=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values[$name],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)){ throw 1 }; if($parsed.Kind -ne [DateTimeKind]::Utc){ throw 1 } }; $obs=$values['ObsStartSucceeded']; if($obs -cne '0' -and $obs -cne '1'){ throw 1 }; Write-Output ('MARKER_VERSION='+$version); Write-Output ('MARKER_SESSION_ID='+$guid.ToString()); Write-Output ('MARKER_OPERATION_ID='+$operation); Write-Output ('MARKER_ARGS_VALID='+$args); Write-Output ('MARKER_CASE_CANONICAL='+$case); Write-Output ('MARKER_TAG_NORMALIZED='+$tag); Write-Output ('MARKER_REPEAT_CANONICAL='+$repeat); Write-Output ('MARKER_SESSION_START_UTC='+$values['SessionStartTimeUtc']); Write-Output ('MARKER_VIDEO_START_UTC='+$values['VideoStartTimeUtc']); Write-Output ('MARKER_LOG_START_UTC='+$values['LogStartTimeUtc']); Write-Output ('MARKER_OBS_START_SUCCEEDED='+$obs); Write-Output 'MARKER_VALID=1' } catch { exit 3 }" 2^>nul`) do (
  if /i "%%A"=="MARKER_VERSION" set "MARKER_VERSION=%%B"
  if /i "%%A"=="MARKER_SESSION_ID" set "MARKER_SESSION_ID=%%B"
  if /i "%%A"=="MARKER_OPERATION_ID" set "MARKER_OPERATION_ID=%%B"
  if /i "%%A"=="MARKER_ARGS_VALID" set "MARKER_ARGS_VALID=%%B"
  if /i "%%A"=="MARKER_CASE_CANONICAL" set "MARKER_CASE_CANONICAL=%%B"
  if /i "%%A"=="MARKER_TAG_NORMALIZED" set "MARKER_TAG_NORMALIZED=%%B"
  if /i "%%A"=="MARKER_REPEAT_CANONICAL" set "MARKER_REPEAT_CANONICAL=%%B"
  if /i "%%A"=="MARKER_SESSION_START_UTC" set "MARKER_SESSION_START_UTC=%%B"
  if /i "%%A"=="MARKER_VIDEO_START_UTC" set "MARKER_VIDEO_START_UTC=%%B"
  if /i "%%A"=="MARKER_LOG_START_UTC" set "MARKER_LOG_START_UTC=%%B"
  if /i "%%A"=="MARKER_OBS_START_SUCCEEDED" set "MARKER_OBS_START_SUCCEEDED=%%B"
  if /i "%%A"=="MARKER_VALID" set "MARKER_VALID=%%B"
)
goto :eof

:ApplyMarkerArgumentFallback
if "%CASE_PRESENT%"=="0" call :UseMarkerCaseFallback
if "%CASE_VALID%"=="0" call :UseMarkerCaseFallback
if "%TAG_PRESENT%"=="0" call :UseMarkerTagFallback
if "%TAG_VALID%"=="0" call :UseMarkerTagFallback
if "%REPEAT_PRESENT%"=="0" call :UseMarkerRepeatFallback
if "%REPEAT_VALID%"=="0" call :UseMarkerRepeatFallback
set "ARGS_VALID=0"
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" if "%REPEAT_VALID%"=="1" set "ARGS_VALID=1"
goto :eof

:UseMarkerCaseFallback
if not defined MARKER_CASE_CANONICAL goto :eof
set "CASE_CANONICAL=%MARKER_CASE_CANONICAL%"
set "CASE_DISPLAY=%MARKER_CASE_CANONICAL%"
if "%MARKER_CASE_CANONICAL:~2,1%"=="" set "CASE_DISPLAY=0%CASE_DISPLAY%"
if "%MARKER_CASE_CANONICAL:~1,1%"=="" set "CASE_DISPLAY=0%CASE_DISPLAY%"
set "CASE_VALID=1"
goto :eof

:UseMarkerTagFallback
if not defined MARKER_TAG_NORMALIZED goto :eof
set "TAG_NORMALIZED=%MARKER_TAG_NORMALIZED%"
set "TAG_VALID=1"
goto :eof

:UseMarkerRepeatFallback
if not defined MARKER_REPEAT_CANONICAL goto :eof
set "REPEAT_CANONICAL=%MARKER_REPEAT_CANONICAL%"
set "REPEAT_VALID=1"
goto :eof

:DetermineModes
set "NAMING_MODE=NORMAL"
set "SELECTION_MODE=LATEST"
if "%MARKER_VALID%"=="0" goto :eof
set "SELECTION_MODE=MARKER"
if not "%MARKER_ARGS_VALID%"=="1" (
  echo [WARN] START marker contained invalid arguments.
  set "WARNING_STATE=1"
)
if defined CASE_CANONICAL if defined MARKER_CASE_CANONICAL if not "%CASE_CANONICAL%"=="%MARKER_CASE_CANONICAL%" goto :ArgumentsMismatch
if defined TAG_NORMALIZED if defined MARKER_TAG_NORMALIZED if /i not "%TAG_NORMALIZED%"=="%MARKER_TAG_NORMALIZED%" goto :ArgumentsMismatch
if defined REPEAT_CANONICAL if defined MARKER_REPEAT_CANONICAL if not "%REPEAT_CANONICAL%"=="%MARKER_REPEAT_CANONICAL%" goto :ArgumentsMismatch
if "%MARKER_OBS_START_SUCCEEDED%"=="0" (
  echo [WARN] OBS start was not verified; latest MP4 fallback remains enabled by policy.
  set "WARNING_STATE=1"
)
goto :eof

:ArgumentsMismatch
echo [ERROR] START and STOP CaseNo, Tag, or Repeat do not match; date-time fallback naming will be used.
set "NAMING_MODE=DATETIME"
set "ERROR_STATE=1"
if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=START_STOP_ARGUMENT_MISMATCH"
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
  if /i "%%A"=="OutputPath" set "OBS_OUTPUT_PATH=%%B"
  if /i "%%A"=="FileStable" set "OBS_FILE_STABLE=%%B"
)
goto :eof

:GetStopDateTime
set "STOP_DT_RESULT="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[DateTime]::Now.ToString('yyyyMMdd_HHmmss',[Globalization.CultureInfo]::InvariantCulture)" 2^>nul`) do if not defined STOP_DT_RESULT set "STOP_DT_RESULT=%%I"
if not defined STOP_DT_RESULT goto :eof
set "DT=%STOP_DT_RESULT%"
set "DT_OK=1"
goto :eof

:PrepareDestination
set "NAME_BASE="
if /i not "%NAMING_MODE%"=="NORMAL" goto :FinalizeDestinationName
if "%CASE_VALID%"=="1" if defined CASE_DISPLAY set "NAME_BASE=Case%CASE_DISPLAY%"
if not "%TAG_VALID%"=="1" goto :FinalizeDestinationName
if not defined TAG_NORMALIZED goto :FinalizeDestinationName
if defined NAME_BASE goto :AppendTagToDestinationName
set "NAME_BASE=%TAG_NORMALIZED%"
goto :FinalizeDestinationName

:AppendTagToDestinationName
set "NAME_BASE=%NAME_BASE%_%TAG_NORMALIZED%"

:FinalizeDestinationName
if defined NAME_BASE goto :UseNamedDestination
set "FILE_PREFIX=%DT%"
set "DEST_FOLDER=%BASEDIR%\%DT%"
goto :CreateDestination

:UseNamedDestination
set "FILE_PREFIX=%NAME_BASE%"
set "DEST_FOLDER=%BASEDIR%\%NAME_BASE%_%DT%"

:CreateDestination
echo [INFO] Destination folder: "%DEST_FOLDER%"
if exist "%DEST_FOLDER%" (
  echo [ERROR] Destination already exists; file movement will be skipped.
  set "ERROR_STATE=1"
  goto :eof
)
mkdir "%DEST_FOLDER%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to create destination folder.
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%DEST_FOLDER%\" (
  echo [ERROR] Destination folder was not found after creation.
  set "ERROR_STATE=1"
  goto :eof
)
set "DEST_READY=1"
goto :eof

:ProcessAllFiles
call :ProcessMp4
call :ProcessFileType "PNG" "%SCREENSHOT_DIR%" "png" "CreationTimeUtc" "%MARKER_SESSION_START_UTC%" "1"
call :ProcessFileType "LOG" "%TERATERM_LOG_DIR%" "log" "LastWriteTimeUtc" "%MARKER_LOG_START_UTC%" "1"
call :ProcessFileType "ASC" "%CAN_LOG_DIR%" "asc" "LastWriteTimeUtc" "%MARKER_LOG_START_UTC%" "1"
goto :eof

:ProcessMp4
if not defined OBS_OUTPUT_PATH goto :ProcessLatestMp4
if not "%OBS_FILE_STABLE%"=="1" (
  echo [WARN] OBS returned an output path, but the file was not stable; MP4 will not be moved.
  set "MP4_SELECTION_MODE=EXACT_OUTPUT_UNSTABLE"
  set "EVIDENCE_CONFIDENCE=NOT_AVAILABLE"
  set "WARNING_STATE=1"
  goto :eof
)
if /i not "%OBS_OUTPUT_PATH:~-4%"==".mp4" goto :ProcessLatestMp4
call :ProcessExactMp4
goto :eof

:ProcessLatestMp4
set "MP4_SELECTION_MODE=LATEST_FALLBACK"
set "EVIDENCE_CONFIDENCE=UNVERIFIED_FALLBACK"
echo [WARN] Exact OBS MP4 path was unavailable; the latest stable MP4 will be used.
set "WARNING_STATE=1"
if "%COMMAND_REASON%"=="OK" set "COMMAND_REASON=LATEST_MP4_FALLBACK"
set "SAVED_SELECTION_MODE=%SELECTION_MODE%"
set "SELECTION_MODE=LATEST"
call :ProcessFileType "MP4" "%CAPTURE_DIR%" "mp4" "CreationTimeUtc" "UNKNOWN" "0"
set "SELECTION_MODE=%SAVED_SELECTION_MODE%"
goto :eof

:ProcessExactMp4
set "MP4_PROCESS_EXIT=1"
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $file=Get-Item -LiteralPath $env:OBS_OUTPUT_PATH -ErrorAction Stop; if($file.Extension -ine '.mp4'){ throw 'Not an MP4' }; $target=Join-Path -Path $env:DEST_FOLDER -ChildPath ($env:FILE_PREFIX+'.mp4'); if(Test-Path -LiteralPath $target){ throw 'Destination exists' }; Write-Output ('MP4_SOURCE_PATH='+$file.FullName); Write-Output ('MP4_SOURCE_CREATION_UTC='+$file.CreationTimeUtc.ToString('o',[Globalization.CultureInfo]::InvariantCulture)); Write-Output ('MP4_SOURCE_LAST_WRITE_UTC='+$file.LastWriteTimeUtc.ToString('o',[Globalization.CultureInfo]::InvariantCulture)); Write-Output ('MP4_SOURCE_LENGTH='+$file.Length); Move-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop; Write-Output 'MP4_PROCESS_EXIT=0' } catch { Write-Output 'MP4_PROCESS_EXIT=1' }" 2^>nul`) do (
  if /i "%%A"=="MP4_SOURCE_PATH" set "MP4_SOURCE_PATH=%%B"
  if /i "%%A"=="MP4_SOURCE_CREATION_UTC" set "MP4_SOURCE_CREATION_UTC=%%B"
  if /i "%%A"=="MP4_SOURCE_LAST_WRITE_UTC" set "MP4_SOURCE_LAST_WRITE_UTC=%%B"
  if /i "%%A"=="MP4_SOURCE_LENGTH" set "MP4_SOURCE_LENGTH=%%B"
  if /i "%%A"=="MP4_PROCESS_EXIT" set "MP4_PROCESS_EXIT=%%B"
)
if "%MP4_PROCESS_EXIT%"=="0" (
  set "MP4_SELECTION_MODE=EXACT_OUTPUT_PATH"
  set "EVIDENCE_CONFIDENCE=VERIFIED_OUTPUT_PATH"
  echo [INFO] Moved the exact OBS output MP4.
) else (
  set "MP4_SELECTION_MODE=EXACT_OUTPUT_MOVE_FAILED"
  set "EVIDENCE_CONFIDENCE=NOT_AVAILABLE"
  echo [ERROR] Failed to move the exact OBS output MP4; latest fallback was not attempted.
  set "ERROR_STATE=1"
)
goto :eof

:ProcessFileType
set "SOURCE_KIND=%~1"
set "SOURCE_DIR=%~2"
set "SOURCE_EXT=%~3"
set "TIME_PROPERTY=%~4"
set "SELECT_START_UTC=%~5"
set "ALL_ON_MARKER=%~6"
if exist "%FILE_PROCESS_OUTPUT%" del /q "%FILE_PROCESS_OUTPUT%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $hadError=$false; $hadWarning=$false; try { $property=$env:TIME_PROPERTY; $files=@(Get-ChildItem -LiteralPath $env:SOURCE_DIR -File -Filter ('*.'+$env:SOURCE_EXT) -ErrorAction Stop); if($env:SELECTION_MODE -eq 'MARKER'){ [DateTime]$start=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($env:SELECT_START_UTC,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$start)){ throw 'Invalid selection time' }; $files=@($files | Where-Object { $_.$property -ge $start } | Sort-Object -Property $property -Descending); if($env:ALL_ON_MARKER -ne '1' -and $files.Count -gt 1){ $files=@($files[0]) } } else { $files=@($files | Sort-Object -Property $property -Descending | Select-Object -First 1) }; if($files.Count -eq 0){ Write-Output ('[WARN] No '+$env:SOURCE_KIND+' file matched the selection rule.'); $hadWarning=$true } else { foreach($file in $files){ if($env:SOURCE_KIND -eq 'MP4'){ $length=$file.Length; $write=$file.LastWriteTimeUtc; Start-Sleep -Milliseconds 500; $file.Refresh(); if($file.Length -ne $length -or $file.LastWriteTimeUtc -ne $write){ Write-Output '[WARN] Latest MP4 is still changing and was not moved.'; $hadWarning=$true; continue }; $stream=$null; try { $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None) } catch { Write-Output '[WARN] Latest MP4 is locked and was not moved.'; $hadWarning=$true; continue } finally { if($null -ne $stream){ $stream.Dispose() } }; Write-Output ('MP4_SOURCE_PATH='+$file.FullName); Write-Output ('MP4_SOURCE_CREATION_UTC='+$file.CreationTimeUtc.ToString('o',[Globalization.CultureInfo]::InvariantCulture)); Write-Output ('MP4_SOURCE_LAST_WRITE_UTC='+$file.LastWriteTimeUtc.ToString('o',[Globalization.CultureInfo]::InvariantCulture)); Write-Output ('MP4_SOURCE_LENGTH='+$file.Length); $targetName=$env:FILE_PREFIX+'.mp4' } else { $targetName=$env:FILE_PREFIX+'_'+$file.Name }; $target=Join-Path -Path $env:DEST_FOLDER -ChildPath $targetName; if(Test-Path -LiteralPath $target){ Write-Output ('[ERROR] Destination file already exists: "'+$target+'"'); $hadError=$true; continue }; try { Move-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop; Write-Output ('[INFO] Renamed destination file: "'+$target+'"') } catch { Write-Output ('[ERROR] Failed to move selected '+$env:SOURCE_KIND+' file.'); $hadError=$true } } } } catch { Write-Output ('[ERROR] Failed to enumerate or select '+$env:SOURCE_KIND+' files.'); $hadError=$true }; if($hadError){ exit 1 }; if($hadWarning){ exit 2 }; exit 0" >"%FILE_PROCESS_OUTPUT%" 2>&1
set "FILE_PROCESS_EXIT=%ERRORLEVEL%"
if exist "%FILE_PROCESS_OUTPUT%" (
  type "%FILE_PROCESS_OUTPUT%"
  for /f "usebackq tokens=1,* delims==" %%A in ("%FILE_PROCESS_OUTPUT%") do (
    if /i "%%A"=="MP4_SOURCE_PATH" set "MP4_SOURCE_PATH=%%B"
    if /i "%%A"=="MP4_SOURCE_CREATION_UTC" set "MP4_SOURCE_CREATION_UTC=%%B"
    if /i "%%A"=="MP4_SOURCE_LAST_WRITE_UTC" set "MP4_SOURCE_LAST_WRITE_UTC=%%B"
    if /i "%%A"=="MP4_SOURCE_LENGTH" set "MP4_SOURCE_LENGTH=%%B"
  )
  del /q "%FILE_PROCESS_OUTPUT%" >nul 2>&1
)
if "%FILE_PROCESS_EXIT%"=="2" (
  set "WARNING_STATE=1"
  goto :eof
)
if not "%FILE_PROCESS_EXIT%"=="0" set "ERROR_STATE=1"
goto :eof

:DeleteLegacyMarker
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [WARN] Marker path is a directory and was not deleted.
  set "WARNING_STATE=1"
  goto :eof
)
if not exist "%LEGACY_SESSION_FILE%" goto :eof
del /q "%LEGACY_SESSION_FILE%" >nul 2>&1
if exist "%LEGACY_SESSION_FILE%" (
  echo [WARN] Failed to delete legacy session marker.
  set "WARNING_STATE=1"
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

:WriteCommandResult
set "RESULT_WRITE_OK=0"
set "COMMAND_COMPLETE_UTC=UNKNOWN"
set "COMMAND_COMPLETE_OK=0"
call :GetUtcNow COMMAND_COMPLETE_UTC COMMAND_COMPLETE_OK
set "COMMAND_RESULT_TEMP=%COMMAND_RESULT_FILE%.tmp.%OPERATION_ID%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $lines=@('Version=1','OperationId='+$env:OPERATION_ID,'Command='+$env:COMMAND_NAME,'State='+$env:COMMAND_STATE,'ExitCode='+$env:FINAL_EXIT_CODE,'Reason='+$env:COMMAND_REASON,'StartedTimeUtc='+$env:COMMAND_START_UTC,'CompletedTimeUtc='+$env:COMMAND_COMPLETE_UTC,'CaseNoCanonical='+$env:CASE_CANONICAL,'TagNormalized='+$env:TAG_NORMALIZED,'RepeatCanonical='+$env:REPEAT_CANONICAL,'SessionId='+$env:MARKER_SESSION_ID,'ObsState='+$env:OBS_STATE,'ObsReason='+$env:OBS_REASON,'ObsOutputPath='+$env:OBS_OUTPUT_PATH,'Mp4SelectionMode='+$env:MP4_SELECTION_MODE,'EvidenceConfidence='+$env:EVIDENCE_CONFIDENCE,'Mp4SourcePath='+$env:MP4_SOURCE_PATH,'Mp4SourceCreationTimeUtc='+$env:MP4_SOURCE_CREATION_UTC,'Mp4SourceLastWriteTimeUtc='+$env:MP4_SOURCE_LAST_WRITE_UTC,'Mp4SourceLength='+$env:MP4_SOURCE_LENGTH); [IO.File]::WriteAllLines($env:COMMAND_RESULT_TEMP,$lines,[Text.UTF8Encoding]::new($false)); Move-Item -LiteralPath $env:COMMAND_RESULT_TEMP -Destination $env:COMMAND_RESULT_FILE -Force"
if errorlevel 1 goto :eof
if exist "%COMMAND_RESULT_TEMP%" goto :eof
set "RESULT_WRITE_OK=1"
goto :eof

:LogEvent
>> "%TIMELINE_LOG%" echo [%date% %time%] OperationId=%OPERATION_ID% Event=%~1 Detail=%~2
goto :eof
