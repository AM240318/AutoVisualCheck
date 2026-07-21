@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERROR_STATE=0"
set "WARNING_STATE=0"
set "USER_DATA_ROOT=%USERPROFILE%"
if not defined USER_DATA_ROOT set "USER_DATA_ROOT=C:\Users\TMC"
set "BASEDIR=%USER_DATA_ROOT%\Desktop\LogZips"
set "CAPTURE_DIR=%USER_DATA_ROOT%\Videos\Captures"
set "SCREENSHOT_DIR=%USER_DATA_ROOT%\Pictures\Screenshots"
set "TERATERM_LOG_DIR=C:\teraterm-5.2\log"
set "CAN_LOG_DIR=%BASEDIR%\CANtemp"
set "OBS_SCRIPT=%~dp0obs_record_stop.ps1"
set "LEGACY_SESSION_FILE=%~dp0legacy_session.marker"
set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "CASE_VALID=0"
set "TAG_VALID=0"
set "ARGS_VALID=0"
set "CASE_CANONICAL="
set "CASE_DISPLAY="
set "TAG_NORMALIZED="
set "CASE_PRESENT=0"
set "TAG_PRESENT=0"
set "MARKER_PRESENT=0"
set "MARKER_VALID=0"
set "MARKER_SESSION_ID=UNKNOWN"
set "MARKER_ARGS_VALID=UNKNOWN"
set "MARKER_CASE_CANONICAL="
set "MARKER_TAG_NORMALIZED="
set "MARKER_SESSION_START_UTC=UNKNOWN"
set "MARKER_VIDEO_START_UTC=UNKNOWN"
set "MARKER_LOG_START_UTC=UNKNOWN"
set "MARKER_OBS_START_SUCCEEDED=UNKNOWN"
set "NAMING_MODE=NORMAL"
set "SELECTION_MODE=LATEST"
set "SKIP_MP4=0"
set "DT=UNKNOWN"
set "DT_OK=0"
set "DEST_FOLDER="
set "FILE_PREFIX="
set "NAME_BASE="
set "DEST_READY=0"
if defined RAW_CASE set "CASE_PRESENT=1"
if defined RAW_TAG set "TAG_PRESENT=1"
if not defined RAW_CASE set "CASE_VALID=1"
if not defined RAW_TAG set "TAG_VALID=1"

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid non-empty CaseNo or Tag; marker or date-time fallback will be used.
  set "ERROR_STATE=1"
)
echo [INFO] Raw arguments: CaseNoPresent=%CASE_PRESENT% TagPresent=%TAG_PRESENT%
echo [INFO] Normalized arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED%
echo [INFO] OBS script path: "%OBS_SCRIPT%"
echo [INFO] NirCmd path: "%~dp0nircmd.exe"
if not exist "%OBS_SCRIPT%" (
  echo [ERROR] OBS stop script was not found: "%OBS_SCRIPT%"
  set "ERROR_STATE=1"
)
if not exist "%~dp0nircmd.exe" (
  echo [ERROR] NirCmd was not found: "%~dp0nircmd.exe"
  set "ERROR_STATE=1"
)

if exist "%LEGACY_SESSION_FILE%" (
  set "MARKER_PRESENT=1"
  call :ReadLegacyMarker
)
if "%MARKER_VALID%"=="1" (
  echo [INFO] Marker path: "%LEGACY_SESSION_FILE%" Status=valid
  echo [INFO] SessionId=%MARKER_SESSION_ID% SessionStartTimeUtc=%MARKER_SESSION_START_UTC%
  echo [INFO] VideoStartTimeUtc=%MARKER_VIDEO_START_UTC% LogStartTimeUtc=%MARKER_LOG_START_UTC%
) else (
  if "%MARKER_PRESENT%"=="1" (
    echo [ERROR] Marker path: "%LEGACY_SESSION_FILE%" Status=invalid
  ) else (
    echo [ERROR] Marker path: "%LEGACY_SESSION_FILE%" Status=missing
  )
  set "ERROR_STATE=1"
)
if "%MARKER_VALID%"=="1" call :ApplyMarkerArgumentFallback
echo [INFO] Effective arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED%
call :DetermineModes

call :GetStopDateTime
if "%DT_OK%"=="0" (
  echo [ERROR] Failed to get STOP local date and time.
  set "ERROR_STATE=1"
) else (
  echo [INFO] STOP local date and time: %DT%
)

REM CANログ停止
echo [INFO] Stopping CAN log.
timeout /t 2 > nul
if errorlevel 1 (
  echo [ERROR] CAN pre-stop wait failed.
  set "ERROR_STATE=1"
)
REM call "%~dp0start_stop_CAN_log.bat"
"%~dp0nircmd.exe" win activate title "Measurement Setup"
if errorlevel 1 (
  echo [ERROR] Failed to activate Measurement Setup.
  set "ERROR_STATE=1"
)
timeout /t 2 > nul
if errorlevel 1 (
  echo [ERROR] CAN activation wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress t
if errorlevel 1 (
  echo [ERROR] CAN stop key failed.
  set "ERROR_STATE=1"
)
timeout /t 2 > nul
if errorlevel 1 (
  echo [ERROR] CAN stop wait failed.
  set "ERROR_STATE=1"
)

REM OBS録画停止
echo [INFO] Stopping OBS recording.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; try { $scriptArg=[char]34+$env:OBS_SCRIPT+[char]34; $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptArg) -WindowStyle Hidden -PassThru; if(-not $p.WaitForExit(20000)){ try { $p.Kill(); if(-not $p.WaitForExit(2000)){ exit 125 } } catch { exit 125 }; exit 124 }; exit $p.ExitCode } catch { exit 125 }"
set "OBS_EXIT_CODE=%ERRORLEVEL%"
if "%OBS_EXIT_CODE%"=="0" (
  echo [INFO] OBS stop result: success.
) else (
  set "ERROR_STATE=1"
  if "%OBS_EXIT_CODE%"=="124" (
    echo [ERROR] OBS stop timed out after 20 seconds.
  ) else (
    echo [ERROR] OBS stop failed. ExitCode=%OBS_EXIT_CODE%
  )
)

REM COM42 Tera Termログ停止
echo [INFO] Stopping COM42 Tera Term log.
REM call "%~dp0stop_teraterm_log_com42.bat"
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
  echo [ERROR] COM42 Alt+F failed.
  set "ERROR_STATE=1"
)
timeout /t 1 > nul
if errorlevel 1 (
  echo [ERROR] COM42 menu wait failed.
  set "ERROR_STATE=1"
)
"%~dp0nircmd.exe" sendkeypress q
if errorlevel 1 (
  echo [ERROR] COM42 stop command failed.
  set "ERROR_STATE=1"
)
timeout /t 5 > nul
if errorlevel 1 (
  echo [ERROR] Post-stop wait failed.
  set "ERROR_STATE=1"
)

if "%DT_OK%"=="1" call :PrepareDestination
if "%DEST_READY%"=="1" call :ProcessAllFiles
call :DeleteLegacyMarker

echo [RESULT] NamingMode=%NAMING_MODE% SelectionMode=%SELECTION_MODE% DestinationReady=%DEST_READY%
if "%ERROR_STATE%"=="0" (
  if "%WARNING_STATE%"=="1" (
    echo [RESULT] STOP_REC completed with warnings. ExitCode=0
  ) else (
    echo [RESULT] STOP_REC completed successfully. ExitCode=0
  )
) else (
  echo [RESULT] STOP_REC completed with errors. ExitCode=1
)
exit /b %ERROR_STATE%

:ApplyMarkerArgumentFallback
if "%CASE_PRESENT%"=="0" call :UseMarkerCaseFallback
if "%CASE_VALID%"=="0" call :UseMarkerCaseFallback
if "%TAG_PRESENT%"=="0" call :UseMarkerTagFallback
if "%TAG_VALID%"=="0" call :UseMarkerTagFallback
set "ARGS_VALID=0"
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" set "ARGS_VALID=1"
goto :eof

:UseMarkerCaseFallback
if not defined MARKER_CASE_CANONICAL goto :eof
set "CASE_CANONICAL=%MARKER_CASE_CANONICAL%"
set "CASE_DISPLAY=%MARKER_CASE_CANONICAL%"
if "%MARKER_CASE_CANONICAL:~2,1%"=="" set "CASE_DISPLAY=0%CASE_DISPLAY%"
if "%MARKER_CASE_CANONICAL:~1,1%"=="" set "CASE_DISPLAY=0%CASE_DISPLAY%"
set "CASE_VALID=1"
echo [INFO] CaseNo was obtained from the START marker.
goto :eof

:UseMarkerTagFallback
if not defined MARKER_TAG_NORMALIZED goto :eof
set "TAG_NORMALIZED=%MARKER_TAG_NORMALIZED%"
set "TAG_VALID=1"
echo [INFO] Tag was obtained from the START marker.
goto :eof

:ValidateArguments
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c.Length -gt 0){ if($c -match '\A[0-9]+\z'){ $canonical=$c.TrimStart('0'); if($canonical.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$canonical); Write-Output ('CASE_DISPLAY='+$canonical.PadLeft(3,'0')) } } }; $t=$env:RAW_TAG; if($t.Length -gt 0 -and $t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="CASE_DISPLAY" set "CASE_DISPLAY=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
)
goto :eof

:ReadLegacyMarker
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $required=@('Version','SessionId','ArgsValid','CaseNoCanonical','TagNormalized','SessionStartTimeUtc','VideoStartTimeUtc','LogStartTimeUtc','ObsStartSucceeded'); $values=@{}; foreach($line in [IO.File]::ReadAllLines($env:LEGACY_SESSION_FILE)){ $i=$line.IndexOf('='); if($i -lt 1){ throw 1 }; $key=$line.Substring(0,$i); if($required -ccontains $key){ if($values.Keys -ccontains $key){ throw 1 }; $values[$key]=$line.Substring($i+1) } }; foreach($key in $required){ if(-not ($values.Keys -ccontains $key)){ throw 1 } }; $version=$values['Version']; if($version -cne '1' -and $version -cne '2'){ throw 1 }; $guid=[Guid]::Empty; if(-not [Guid]::TryParseExact($values['SessionId'],'D',[ref]$guid)){ throw 1 }; $args=$values['ArgsValid']; if($args -cne '0' -and $args -cne '1'){ throw 1 }; $case=$values['CaseNoCanonical']; if($version -ceq '1' -and $case -ceq 'UNKNOWN'){ $case='' }; if($case.Length -gt 0){ if($case -notmatch '\A[0-9]+\z'){ throw 1 }; $case=$case.TrimStart('0'); if($case.Length -eq 0){ throw 1 } }; $tag=$values['TagNormalized']; if($version -ceq '1' -and $tag -ceq 'UNKNOWN'){ $tag='' }; if($tag.Length -gt 0 -and $tag -notmatch '\A[A-Z0-9_-]+\z'){ throw 1 }; if($version -ceq '1' -and $args -ceq '1' -and ($case.Length -eq 0 -or $tag.Length -eq 0)){ throw 1 }; [DateTime]$sessionTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['SessionStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$sessionTime)){ throw 1 }; if($sessionTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; [DateTime]$videoTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['VideoStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$videoTime)){ throw 1 }; if($videoTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; [DateTime]$logTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['LogStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$logTime)){ throw 1 }; if($logTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; $obs=$values['ObsStartSucceeded']; if($obs -cne '0' -and $obs -cne '1'){ throw 1 }; Write-Output ('MARKER_SESSION_ID='+$guid.ToString()); Write-Output ('MARKER_ARGS_VALID='+$args); Write-Output ('MARKER_CASE_CANONICAL='+$case); Write-Output ('MARKER_TAG_NORMALIZED='+$tag); Write-Output ('MARKER_SESSION_START_UTC='+$values['SessionStartTimeUtc']); Write-Output ('MARKER_VIDEO_START_UTC='+$values['VideoStartTimeUtc']); Write-Output ('MARKER_LOG_START_UTC='+$values['LogStartTimeUtc']); Write-Output ('MARKER_OBS_START_SUCCEEDED='+$obs); Write-Output 'MARKER_VALID=1' } catch { exit 3 }" 2^>nul`) do (
  if /i "%%A"=="MARKER_SESSION_ID" set "MARKER_SESSION_ID=%%B"
  if /i "%%A"=="MARKER_ARGS_VALID" set "MARKER_ARGS_VALID=%%B"
  if /i "%%A"=="MARKER_CASE_CANONICAL" set "MARKER_CASE_CANONICAL=%%B"
  if /i "%%A"=="MARKER_TAG_NORMALIZED" set "MARKER_TAG_NORMALIZED=%%B"
  if /i "%%A"=="MARKER_SESSION_START_UTC" set "MARKER_SESSION_START_UTC=%%B"
  if /i "%%A"=="MARKER_VIDEO_START_UTC" set "MARKER_VIDEO_START_UTC=%%B"
  if /i "%%A"=="MARKER_LOG_START_UTC" set "MARKER_LOG_START_UTC=%%B"
  if /i "%%A"=="MARKER_OBS_START_SUCCEEDED" set "MARKER_OBS_START_SUCCEEDED=%%B"
  if /i "%%A"=="MARKER_VALID" set "MARKER_VALID=%%B"
)
goto :eof

:DetermineModes
set "NAMING_MODE=NORMAL"
set "SELECTION_MODE=LATEST"
set "SKIP_MP4=0"
if "%MARKER_VALID%"=="0" goto :DetermineWithoutMarker
set "SELECTION_MODE=MARKER"
if "%MARKER_OBS_START_SUCCEEDED%"=="0" (
  echo [ERROR] OBS start was not successful; MP4 will not be moved.
  set "SKIP_MP4=1"
  set "ERROR_STATE=1"
)
if not "%MARKER_ARGS_VALID%"=="1" (
  echo [ERROR] START marker contained an invalid non-empty CaseNo or Tag; valid matching fields will still be used.
  set "ERROR_STATE=1"
)
if defined CASE_CANONICAL if defined MARKER_CASE_CANONICAL if not "%CASE_CANONICAL%"=="%MARKER_CASE_CANONICAL%" goto :DetermineCaseMismatch
if defined TAG_NORMALIZED if defined MARKER_TAG_NORMALIZED if /i not "%TAG_NORMALIZED%"=="%MARKER_TAG_NORMALIZED%" goto :DetermineCaseMismatch
set "NAMING_MODE=NORMAL"
echo [INFO] START and STOP CaseNo/Tag are compatible.
goto :eof

:DetermineWithoutMarker
echo [INFO] Marker-time selection unavailable; latest-one fallback selection will be used.
goto :eof

:DetermineCaseMismatch
echo [ERROR] START and STOP CaseNo/Tag do not match; date-time fallback naming will be used.
set "NAMING_MODE=DATETIME"
set "ERROR_STATE=1"
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
  echo [ERROR] Destination already exists; file movement will be skipped: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
mkdir "%DEST_FOLDER%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to create destination folder: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%DEST_FOLDER%\" (
  echo [ERROR] Destination folder was not found after creation: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
set "DEST_READY=1"
goto :eof

:ProcessAllFiles
if "%SKIP_MP4%"=="1" goto :SkipMp4Processing
call :ProcessFileType "MP4" "%CAPTURE_DIR%" "mp4" "CreationTimeUtc" "%MARKER_VIDEO_START_UTC%" "0"
goto :AfterMp4Processing

:SkipMp4Processing
echo [WARN] MP4 processing skipped because ObsStartSucceeded=0.
set "WARNING_STATE=1"

:AfterMp4Processing
call :ProcessFileType "PNG" "%SCREENSHOT_DIR%" "png" "CreationTimeUtc" "%MARKER_SESSION_START_UTC%" "1"
call :ProcessFileType "LOG" "%TERATERM_LOG_DIR%" "log" "LastWriteTimeUtc" "%MARKER_LOG_START_UTC%" "1"
call :ProcessFileType "ASC" "%CAN_LOG_DIR%" "asc" "LastWriteTimeUtc" "%MARKER_LOG_START_UTC%" "1"
goto :eof

:ProcessFileType
set "SOURCE_KIND=%~1"
set "SOURCE_DIR=%~2"
set "SOURCE_EXT=%~3"
set "TIME_PROPERTY=%~4"
set "SELECT_START_UTC=%~5"
set "ALL_ON_MARKER=%~6"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $hadError=$false; $hadWarning=$false; try { $property=$env:TIME_PROPERTY; $files=@(Get-ChildItem -LiteralPath $env:SOURCE_DIR -File -Filter ('*.'+$env:SOURCE_EXT) -ErrorAction Stop); if($env:SELECTION_MODE -eq 'MARKER'){ [DateTime]$start=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($env:SELECT_START_UTC,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$start)){ throw 'Invalid selection time' }; $files=@($files | Where-Object { $_.$property -ge $start } | Sort-Object -Property $property -Descending); if($env:SOURCE_KIND -eq 'MP4' -and $files.Count -gt 1){ Write-Output ('[WARN] Multiple MP4 candidates found: '+$files.Count+'. The latest one will be used.'); $hadWarning=$true }; if($env:ALL_ON_MARKER -ne '1' -and $files.Count -gt 1){ $files=@($files[0]) } } else { $files=@($files | Sort-Object -Property $property -Descending | Select-Object -First 1) }; if($files.Count -eq 0){ Write-Output ('[WARN] No '+$env:SOURCE_KIND+' file matched the selection rule.'); $hadWarning=$true } else { foreach($file in $files){ if($env:SOURCE_KIND -eq 'MP4'){ $targetName=$env:FILE_PREFIX+'.mp4' } else { $targetName=$env:FILE_PREFIX+'_'+$file.Name }; $target=Join-Path -Path $env:DEST_FOLDER -ChildPath $targetName; Write-Output ('[INFO] Selected source file: "'+$file.FullName+'"'); if(Test-Path -LiteralPath $target){ Write-Output ('[ERROR] Destination file already exists: "'+$target+'"'); $hadError=$true; continue }; try { Move-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop; Write-Output ('[INFO] Renamed destination file: "'+$target+'"') } catch { Write-Output ('[ERROR] Failed to move selected '+$env:SOURCE_KIND+' file.'); $hadError=$true } } } } catch { Write-Output ('[ERROR] Failed to enumerate or select '+$env:SOURCE_KIND+' files.'); $hadError=$true }; if($hadError){ exit 1 }; if($hadWarning){ exit 2 }; exit 0"
set "FILE_PROCESS_EXIT=%ERRORLEVEL%"
if "%FILE_PROCESS_EXIT%"=="2" (
  set "WARNING_STATE=1"
  goto :eof
)
if not "%FILE_PROCESS_EXIT%"=="0" set "ERROR_STATE=1"
goto :eof

:DeleteLegacyMarker
if exist "%LEGACY_SESSION_FILE%\NUL" (
  echo [WARN] Marker path is a directory and was not deleted: "%LEGACY_SESSION_FILE%"
  set "WARNING_STATE=1"
  goto :eof
)
if not exist "%LEGACY_SESSION_FILE%" (
  echo [INFO] Legacy session marker is already absent.
  goto :eof
)
del /q "%LEGACY_SESSION_FILE%" >nul 2>&1
if exist "%LEGACY_SESSION_FILE%" (
  echo [WARN] Failed to delete legacy session marker: "%LEGACY_SESSION_FILE%"
  set "WARNING_STATE=1"
) else (
  echo [INFO] Deleted legacy session marker: "%LEGACY_SESSION_FILE%"
)
goto :eof
