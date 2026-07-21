@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERROR_STATE=0"
set "WARNING_STATE=0"
set "BASEDIR=C:\Users\TMC\Desktop\LogZips"
set "CAPTURE_DIR=C:\Users\TMC\Videos\Captures"
set "SCREENSHOT_DIR=C:\Users\TMC\Pictures\Screenshots"
set "TERATERM_LOG_DIR=C:\teraterm-5.2\log"
set "CAN_LOG_DIR=C:\Users\TMC\Desktop\LogZips\CANtemp"
set "OBS_SCRIPT=%~dp0obs_record_stop.ps1"
set "LOG_SESSION_FILE=%~dp0log_session.marker"
set "VIDEO_SESSION_FILE=%~dp0video_session.marker"
set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "RAW_REPEAT=%~3"
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
set "LOG_MARKER_PRESENT=0"
set "LOG_MARKER_VALID=0"
set "LOG_SESSION_ID=UNKNOWN"
set "LOG_SESSION_START_UTC=UNKNOWN"
set "LOG_START_UTC=UNKNOWN"
set "VIDEO_MARKER_PRESENT=0"
set "VIDEO_MARKER_VALID=0"
set "VIDEO_SESSION_ID=UNKNOWN"
set "VIDEO_MARKER_ARGS_VALID=UNKNOWN"
set "VIDEO_CASE_CANONICAL="
set "VIDEO_TAG_NORMALIZED="
set "VIDEO_START_UTC=UNKNOWN"
set "VIDEO_OBS_START_SUCCEEDED=UNKNOWN"
set "LOG_SELECTION_MODE=LATEST"
set "VIDEO_SELECTION_MODE=LATEST"
set "NAMING_MODE=NORMAL"
set "SESSION_MISMATCH=0"
set "CASE_MISMATCH=0"
set "VIDEO_ARGS_INVALID=0"
set "SKIP_MP4=0"
set "DT=UNKNOWN"
set "DT_OK=0"
set "PARENT_FOLDER="
set "PARENT_NAME="
set "PARENT_READY=0"
set "FILE_PREFIX="
set "NAME_COMPONENT="
set "RUN_FOLDER_NAME="
set "ARCHIVE_READY=0"
set "DEST_FOLDER="
set "DEST_READY=0"
if defined RAW_CASE set "CASE_PRESENT=1"
if defined RAW_TAG set "TAG_PRESENT=1"
if defined RAW_REPEAT set "REPEAT_PRESENT=1"
if not defined RAW_CASE set "CASE_VALID=1"
if not defined RAW_TAG set "TAG_VALID=1"
if not defined RAW_REPEAT set "REPEAT_VALID=1"

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" if "%REPEAT_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid non-empty CaseNo, Tag, or Repeat.
  set "ERROR_STATE=1"
)
echo [INFO] Raw arguments: CaseNoPresent=%CASE_PRESENT% TagPresent=%TAG_PRESENT% RepeatPresent=%REPEAT_PRESENT%
echo [INFO] Normalized arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED% Repeat=%REPEAT_CANONICAL%
echo [INFO] OBS script path: "%OBS_SCRIPT%"
echo [INFO] NirCmd path: "%~dp0nircmd.exe"

if exist "%LOG_SESSION_FILE%" (
  set "LOG_MARKER_PRESENT=1"
  call :ReadLogMarker
)
if exist "%VIDEO_SESSION_FILE%" (
  set "VIDEO_MARKER_PRESENT=1"
  call :ReadVideoMarker
)
if "%LOG_MARKER_VALID%"=="1" (
  echo [INFO] Log marker: "%LOG_SESSION_FILE%" Status=valid SessionId=%LOG_SESSION_ID%
  echo [INFO] SessionStartTimeUtc=%LOG_SESSION_START_UTC% LogStartTimeUtc=%LOG_START_UTC%
) else (
  if "%LOG_MARKER_PRESENT%"=="1" (
    echo [ERROR] Log marker: "%LOG_SESSION_FILE%" Status=invalid
  ) else (
    echo [ERROR] Log marker: "%LOG_SESSION_FILE%" Status=missing
  )
  set "ERROR_STATE=1"
)
if "%VIDEO_MARKER_VALID%"=="1" (
  echo [INFO] Video marker: "%VIDEO_SESSION_FILE%" Status=valid SessionId=%VIDEO_SESSION_ID%
  echo [INFO] VideoStartTimeUtc=%VIDEO_START_UTC% ObsStartSucceeded=%VIDEO_OBS_START_SUCCEEDED%
) else (
  if "%VIDEO_MARKER_PRESENT%"=="1" (
    echo [ERROR] Video marker: "%VIDEO_SESSION_FILE%" Status=invalid
  ) else (
    echo [ERROR] Video marker: "%VIDEO_SESSION_FILE%" Status=missing
  )
  set "ERROR_STATE=1"
)
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%OBS_SCRIPT%"
set "OBS_EXIT_CODE=%ERRORLEVEL%"
if "%OBS_EXIT_CODE%"=="0" (
  echo [INFO] OBS stop result: success.
) else (
  set "ERROR_STATE=1"
  echo [ERROR] OBS stop failed. ExitCode=%OBS_EXIT_CODE%
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

if "%DT_OK%"=="1" call :PrepareParentFolder
if "%PARENT_READY%"=="1" call :ArchivePreviousChild
if "%ARCHIVE_READY%"=="1" call :CreateChildFolder
if "%DEST_READY%"=="1" call :ProcessAllFiles
call :DeleteMarker "%LOG_SESSION_FILE%" "log_session.marker"
call :DeleteMarker "%VIDEO_SESSION_FILE%" "video_session.marker"

echo [RESULT] NamingMode=%NAMING_MODE% VideoSelection=%VIDEO_SELECTION_MODE% LogSelection=%LOG_SELECTION_MODE%
echo [RESULT] SessionMismatch=%SESSION_MISMATCH% CaseMismatch=%CASE_MISMATCH% DestinationReady=%DEST_READY%
if "%ERROR_STATE%"=="0" (
  if "%WARNING_STATE%"=="1" (
    echo [RESULT] STOP_REC2 completed with warnings. ExitCode=0
  ) else (
    echo [RESULT] STOP_REC2 completed successfully. ExitCode=0
  )
) else (
  echo [RESULT] STOP_REC2 completed with errors. ExitCode=1
)
exit /b %ERROR_STATE%

:ValidateArguments
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c.Length -gt 0){ if($c -match '\A[0-9]+\z'){ $canonical=$c.TrimStart('0'); if($canonical.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$canonical); Write-Output ('CASE_DISPLAY='+$canonical.PadLeft(3,'0')) } } }; $t=$env:RAW_TAG; if($t.Length -gt 0 -and $t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }; $r=$env:RAW_REPEAT; if($r.Length -gt 0){ if($r -match '\A[0-9]+\z'){ $repeat=$r.TrimStart('0'); if($repeat.Length -gt 0){ Write-Output 'REPEAT_VALID=1'; Write-Output ('REPEAT_CANONICAL='+$repeat) } } }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="CASE_DISPLAY" set "CASE_DISPLAY=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
  if /i "%%A"=="REPEAT_VALID" set "REPEAT_VALID=%%B"
  if /i "%%A"=="REPEAT_CANONICAL" set "REPEAT_CANONICAL=%%B"
)
goto :eof

:ReadLogMarker
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $required=@('Version','SessionId','SessionStartTimeUtc','LogStartTimeUtc'); $values=@{}; foreach($line in [IO.File]::ReadAllLines($env:LOG_SESSION_FILE)){ $i=$line.IndexOf('='); if($i -lt 1){ throw 1 }; $key=$line.Substring(0,$i); if($required -ccontains $key){ if($values.Keys -ccontains $key){ throw 1 }; $values[$key]=$line.Substring($i+1) } }; foreach($key in $required){ if(-not ($values.Keys -ccontains $key)){ throw 1 } }; if($values['Version'] -cne '1'){ throw 1 }; $guid=[Guid]::Empty; if(-not [Guid]::TryParseExact($values['SessionId'],'D',[ref]$guid)){ throw 1 }; [DateTime]$sessionTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['SessionStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$sessionTime)){ throw 1 }; if($sessionTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; [DateTime]$logTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['LogStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$logTime)){ throw 1 }; if($logTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; Write-Output ('LOG_SESSION_ID='+$guid.ToString()); Write-Output ('LOG_SESSION_START_UTC='+$values['SessionStartTimeUtc']); Write-Output ('LOG_START_UTC='+$values['LogStartTimeUtc']); Write-Output 'LOG_MARKER_VALID=1' } catch { exit 3 }" 2^>nul`) do (
  if /i "%%A"=="LOG_SESSION_ID" set "LOG_SESSION_ID=%%B"
  if /i "%%A"=="LOG_SESSION_START_UTC" set "LOG_SESSION_START_UTC=%%B"
  if /i "%%A"=="LOG_START_UTC" set "LOG_START_UTC=%%B"
  if /i "%%A"=="LOG_MARKER_VALID" set "LOG_MARKER_VALID=%%B"
)
goto :eof

:ReadVideoMarker
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $required=@('Version','SessionId','ArgsValid','CaseNoCanonical','TagNormalized','VideoStartTimeUtc','ObsStartSucceeded'); $values=@{}; foreach($line in [IO.File]::ReadAllLines($env:VIDEO_SESSION_FILE)){ $i=$line.IndexOf('='); if($i -lt 1){ throw 1 }; $key=$line.Substring(0,$i); if($required -ccontains $key){ if($values.Keys -ccontains $key){ throw 1 }; $values[$key]=$line.Substring($i+1) } }; foreach($key in $required){ if(-not ($values.Keys -ccontains $key)){ throw 1 } }; $version=$values['Version']; if($version -cne '1' -and $version -cne '2'){ throw 1 }; $guid=[Guid]::Empty; if(-not [Guid]::TryParseExact($values['SessionId'],'D',[ref]$guid)){ throw 1 }; $args=$values['ArgsValid']; if($args -cne '0' -and $args -cne '1'){ throw 1 }; $case=$values['CaseNoCanonical']; if($version -ceq '1' -and $case -ceq 'UNKNOWN'){ $case='' }; if($case.Length -gt 0){ if($case -notmatch '\A[0-9]+\z'){ throw 1 }; $case=$case.TrimStart('0'); if($case.Length -eq 0){ throw 1 } }; $tag=$values['TagNormalized']; if($version -ceq '1' -and $tag -ceq 'UNKNOWN'){ $tag='' }; if($tag.Length -gt 0 -and $tag -notmatch '\A[A-Z0-9_-]+\z'){ throw 1 }; if($version -ceq '1' -and $args -ceq '1' -and ($case.Length -eq 0 -or $tag.Length -eq 0)){ throw 1 }; [DateTime]$videoTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($values['VideoStartTimeUtc'],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$videoTime)){ throw 1 }; if($videoTime.Kind -ne [DateTimeKind]::Utc){ throw 1 }; $obs=$values['ObsStartSucceeded']; if($obs -cne '0' -and $obs -cne '1'){ throw 1 }; Write-Output ('VIDEO_SESSION_ID='+$guid.ToString()); Write-Output ('VIDEO_MARKER_ARGS_VALID='+$args); Write-Output ('VIDEO_CASE_CANONICAL='+$case); Write-Output ('VIDEO_TAG_NORMALIZED='+$tag); Write-Output ('VIDEO_START_UTC='+$values['VideoStartTimeUtc']); Write-Output ('VIDEO_OBS_START_SUCCEEDED='+$obs); Write-Output 'VIDEO_MARKER_VALID=1' } catch { exit 3 }" 2^>nul`) do (
  if /i "%%A"=="VIDEO_SESSION_ID" set "VIDEO_SESSION_ID=%%B"
  if /i "%%A"=="VIDEO_MARKER_ARGS_VALID" set "VIDEO_MARKER_ARGS_VALID=%%B"
  if /i "%%A"=="VIDEO_CASE_CANONICAL" set "VIDEO_CASE_CANONICAL=%%B"
  if /i "%%A"=="VIDEO_TAG_NORMALIZED" set "VIDEO_TAG_NORMALIZED=%%B"
  if /i "%%A"=="VIDEO_START_UTC" set "VIDEO_START_UTC=%%B"
  if /i "%%A"=="VIDEO_OBS_START_SUCCEEDED" set "VIDEO_OBS_START_SUCCEEDED=%%B"
  if /i "%%A"=="VIDEO_MARKER_VALID" set "VIDEO_MARKER_VALID=%%B"
)
goto :eof

:DetermineModes
set "LOG_SELECTION_MODE=LATEST"
set "VIDEO_SELECTION_MODE=LATEST"
set "NAMING_MODE=NORMAL"
set "SKIP_MP4=0"
if "%LOG_MARKER_VALID%"=="1" set "LOG_SELECTION_MODE=MARKER"
if "%VIDEO_MARKER_VALID%"=="1" set "VIDEO_SELECTION_MODE=MARKER"
if "%LOG_MARKER_VALID%"=="1" if "%VIDEO_MARKER_VALID%"=="1" if /i not "%LOG_SESSION_ID%"=="%VIDEO_SESSION_ID%" goto :DetermineSessionMismatch
if "%VIDEO_MARKER_VALID%"=="1" if "%VIDEO_OBS_START_SUCCEEDED%"=="0" call :MarkObsStartFailed
if "%VIDEO_MARKER_VALID%"=="1" if not "%VIDEO_MARKER_ARGS_VALID%"=="1" call :DetermineVideoArgsInvalid
if "%VIDEO_MARKER_VALID%"=="1" if not "%CASE_CANONICAL%"=="%VIDEO_CASE_CANONICAL%" goto :DetermineCaseMismatch
if "%VIDEO_MARKER_VALID%"=="1" if /i not "%TAG_NORMALIZED%"=="%VIDEO_TAG_NORMALIZED%" goto :DetermineCaseMismatch
set "NAMING_MODE=NORMAL"
echo [INFO] STOP arguments and available video marker arguments match.
goto :eof

:DetermineSessionMismatch
set "SESSION_MISMATCH=1"
set "LOG_MARKER_VALID=0"
set "VIDEO_MARKER_VALID=0"
set "LOG_SELECTION_MODE=LATEST"
set "VIDEO_SELECTION_MODE=LATEST"
set "SKIP_MP4=0"
set "NAMING_MODE=FALLBACK"
echo [ERROR] Log and video SessionId values do not match; both marker timelines are discarded.
set "ERROR_STATE=1"
goto :eof

:MarkObsStartFailed
set "SKIP_MP4=1"
echo [ERROR] OBS start was not successful; MP4 will not be moved.
set "ERROR_STATE=1"
goto :eof

:DetermineVideoArgsInvalid
set "VIDEO_ARGS_INVALID=1"
echo [ERROR] Video marker contained an invalid non-empty CaseNo or Tag; valid matching fields will still be used.
set "ERROR_STATE=1"
goto :eof

:DetermineCaseMismatch
set "CASE_MISMATCH=1"
set "NAMING_MODE=FALLBACK"
echo [ERROR] START and STOP CaseNo/Tag do not match; CaseNo and Tag will be omitted from names.
set "ERROR_STATE=1"
goto :eof

:GetStopDateTime
set "STOP_DT_RESULT="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[DateTime]::Now.ToString('yyyyMMdd_HHmmss',[Globalization.CultureInfo]::InvariantCulture)" 2^>nul`) do if not defined STOP_DT_RESULT set "STOP_DT_RESULT=%%I"
if not defined STOP_DT_RESULT goto :eof
set "DT=%STOP_DT_RESULT%"
set "DT_OK=1"
goto :eof

:PrepareParentFolder
set "PARENT_NAME="
set "NAME_COMPONENT="
if /i not "%NAMING_MODE%"=="NORMAL" goto :AppendRepeatToName
if "%CASE_VALID%"=="1" if defined CASE_DISPLAY set "PARENT_NAME=Case%CASE_DISPLAY%"
if not "%TAG_VALID%"=="1" goto :CopyParentToName
if not defined TAG_NORMALIZED goto :CopyParentToName
if defined PARENT_NAME goto :AppendTagToParentName
set "PARENT_NAME=%TAG_NORMALIZED%"
goto :CopyParentToName

:AppendTagToParentName
set "PARENT_NAME=%PARENT_NAME%_%TAG_NORMALIZED%"

:CopyParentToName
set "NAME_COMPONENT=%PARENT_NAME%"

:AppendRepeatToName
if not "%REPEAT_VALID%"=="1" goto :FinalizeNames
if not defined REPEAT_CANONICAL goto :FinalizeNames
if defined NAME_COMPONENT goto :AppendRepeatSuffix
set "NAME_COMPONENT=Repeat%REPEAT_CANONICAL%"
goto :FinalizeNames

:AppendRepeatSuffix
set "NAME_COMPONENT=%NAME_COMPONENT%#%REPEAT_CANONICAL%"

:FinalizeNames
set "PARENT_FOLDER=%BASEDIR%"
if defined PARENT_NAME set "PARENT_FOLDER=%BASEDIR%\%PARENT_NAME%"
if defined NAME_COMPONENT goto :UseNameComponent
set "FILE_PREFIX=%DT%"
set "RUN_FOLDER_NAME=%DT%"
goto :EnsureParentFolder

:UseNameComponent
set "FILE_PREFIX=%NAME_COMPONENT%"
set "RUN_FOLDER_NAME=%NAME_COMPONENT%_%DT%"

:EnsureParentFolder
echo [INFO] Parent folder: "%PARENT_FOLDER%"
if exist "%PARENT_FOLDER%\" (
  echo [INFO] Reusing parent folder: "%PARENT_FOLDER%"
  set "PARENT_READY=1"
  goto :eof
)
mkdir "%PARENT_FOLDER%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to create parent folder: "%PARENT_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%PARENT_FOLDER%\" (
  echo [ERROR] Parent folder was not found after creation: "%PARENT_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
echo [WARN] Parent folder was missing and was created by STOP_REC2: "%PARENT_FOLDER%"
set "WARNING_STATE=1"
set "PARENT_READY=1"
goto :eof

:ArchivePreviousChild
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { if([string]::IsNullOrEmpty($env:NAME_COMPONENT)){ $pattern='\A[0-9]{8}_[0-9]{6}\z' } else { $pattern='\A'+[Regex]::Escape($env:NAME_COMPONENT)+'_[0-9]{8}_[0-9]{6}\z' }; $candidate=@(Get-ChildItem -LiteralPath $env:PARENT_FOLDER -Directory -ErrorAction Stop | Where-Object { $_.Name -notmatch '_OLD_' -and $_.Name -match $pattern } | Sort-Object -Property Name -Descending | Select-Object -First 1); if($candidate.Count -eq 0){ Write-Output '[INFO] No previous matching child folder requires archiving.'; exit 0 }; $archiveBase=$candidate[0].Name+'_OLD_'+$env:DT; $archiveName=$archiveBase; $index=1; while(Test-Path -LiteralPath (Join-Path -Path $env:PARENT_FOLDER -ChildPath $archiveName)){ $archiveName=$archiveBase+'_'+$index.ToString('00',[Globalization.CultureInfo]::InvariantCulture); $index++ }; Rename-Item -LiteralPath $candidate[0].FullName -NewName $archiveName -ErrorAction Stop; Write-Output ('[INFO] Archived OLD folder: "'+(Join-Path -Path $env:PARENT_FOLDER -ChildPath $archiveName)+'"'); exit 0 } catch { Write-Output '[ERROR] Failed to archive the latest previous matching child folder.'; exit 1 }"
set "ARCHIVE_EXIT_CODE=%ERRORLEVEL%"
if "%ARCHIVE_EXIT_CODE%"=="0" (
  set "ARCHIVE_READY=1"
  goto :eof
)
echo [ERROR] New child creation and file movement will be skipped because OLD archiving failed.
set "ERROR_STATE=1"
goto :eof

:CreateChildFolder
set "DEST_FOLDER=%PARENT_FOLDER%\%RUN_FOLDER_NAME%"
echo [INFO] Destination child folder: "%DEST_FOLDER%"
if exist "%DEST_FOLDER%" (
  echo [ERROR] Destination child already exists; file movement will be skipped: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
mkdir "%DEST_FOLDER%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to create destination child folder: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%DEST_FOLDER%\" (
  echo [ERROR] Destination child folder was not found after creation: "%DEST_FOLDER%"
  set "ERROR_STATE=1"
  goto :eof
)
set "DEST_READY=1"
goto :eof

:ProcessAllFiles
if "%SKIP_MP4%"=="1" goto :SkipMp4Processing
set "SELECTION_MODE=%VIDEO_SELECTION_MODE%"
call :ProcessFileType "MP4" "%CAPTURE_DIR%" "mp4" "CreationTimeUtc" "%VIDEO_START_UTC%" "0"
goto :AfterMp4Processing

:SkipMp4Processing
echo [WARN] MP4 processing skipped because ObsStartSucceeded=0.
set "WARNING_STATE=1"

:AfterMp4Processing
set "SELECTION_MODE=%LOG_SELECTION_MODE%"
call :ProcessFileType "PNG" "%SCREENSHOT_DIR%" "png" "CreationTimeUtc" "%LOG_SESSION_START_UTC%" "1"
call :ProcessFileType "LOG" "%TERATERM_LOG_DIR%" "log" "LastWriteTimeUtc" "%LOG_START_UTC%" "1"
call :ProcessFileType "ASC" "%CAN_LOG_DIR%" "asc" "LastWriteTimeUtc" "%LOG_START_UTC%" "1"
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

:DeleteMarker
set "DELETE_PATH=%~1"
set "DELETE_NAME=%~2"
if exist "%DELETE_PATH%\NUL" (
  echo [WARN] %DELETE_NAME% path is a directory and was not deleted: "%DELETE_PATH%"
  set "WARNING_STATE=1"
  goto :eof
)
if not exist "%DELETE_PATH%" (
  echo [INFO] %DELETE_NAME% is already absent.
  goto :eof
)
del /q "%DELETE_PATH%" >nul 2>&1
if exist "%DELETE_PATH%" (
  echo [WARN] Failed to delete %DELETE_NAME%: "%DELETE_PATH%"
  set "WARNING_STATE=1"
) else (
  echo [INFO] Deleted %DELETE_NAME%: "%DELETE_PATH%"
)
goto :eof
