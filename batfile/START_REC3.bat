@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERROR_STATE=0"
set "SAVE_ROOT=C:\Users\TMC\Desktop\LogZips"
set "LOG_SESSION_FILE=%~dp0log_session.marker"
set "VIDEO_SESSION_FILE=%~dp0video_session.marker"
set "VIDEO_SESSION_TEMP=%VIDEO_SESSION_FILE%.tmp"
set "RAW_CASE=%~1"
set "RAW_TAG=%~2"
set "CASE_VALID=0"
set "TAG_VALID=0"
set "ARGS_VALID=0"
set "CASE_CANONICAL=UNKNOWN"
set "CASE_DISPLAY=UNKNOWN"
set "TAG_NORMALIZED=UNKNOWN"
set "PARENT_DIR="
set "SESSION_ID=UNKNOWN"
set "LOG_SESSION_LINK_OK=0"
set "SESSION_ID_OK=0"
set "VIDEO_START_UTC=UNKNOWN"
set "VIDEO_START_OK=0"
set "OBS_START_SUCCEEDED=0"
set "CASE_PRESENT=0"
set "TAG_PRESENT=0"
if defined RAW_CASE set "CASE_PRESENT=1"
if defined RAW_TAG set "TAG_PRESENT=1"

call :ValidateArguments
if "%CASE_VALID%"=="1" if "%TAG_VALID%"=="1" set "ARGS_VALID=1"
if "%ARGS_VALID%"=="0" (
  echo [ERROR] Invalid CaseNo or Tag.
  set "ERROR_STATE=1"
)

echo [INFO] Raw arguments: CaseNoPresent=%CASE_PRESENT% TagPresent=%TAG_PRESENT%
echo [INFO] Normalized arguments: ArgsValid=%ARGS_VALID% CaseNo=%CASE_CANONICAL% Tag=%TAG_NORMALIZED%
if "%ARGS_VALID%"=="1" call :PrepareParentFolder

call :ReadLogSession
if "%LOG_SESSION_LINK_OK%"=="1" (
  echo [INFO] Inherited SessionId from "%LOG_SESSION_FILE%": %SESSION_ID%
) else (
  echo [ERROR] Valid SessionId could not be read from "%LOG_SESSION_FILE%".
  set "ERROR_STATE=1"
)
if "%LOG_SESSION_LINK_OK%"=="0" call :CreateFallbackSessionId

set "VIDEO_START_OK=0"
call :GetUtcNow VIDEO_START_UTC VIDEO_START_OK
if "%VIDEO_START_OK%"=="0" (
  echo [ERROR] Failed to get VideoStartTimeUtc.
  set "ERROR_STATE=1"
)
echo [INFO] Video marker path: "%VIDEO_SESSION_FILE%"
echo [INFO] SessionId=%SESSION_ID% VideoStartTimeUtc=%VIDEO_START_UTC%
call :WriteVideoMarker

REM OBS録画スタート
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; try { $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\TMC\Desktop\Veri\batfile\obs_record_start.ps1') -WindowStyle Hidden -PassThru; if(-not $p.WaitForExit(20000)){ try { $p.Kill(); if(-not $p.WaitForExit(2000)){ exit 125 } } catch { exit 125 }; exit 124 }; exit $p.ExitCode } catch { exit 125 }"
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
call :WriteVideoMarker

if "%ERROR_STATE%"=="0" (
  echo [RESULT] START_REC3 completed successfully. ExitCode=0
) else (
  echo [RESULT] START_REC3 completed with errors. ExitCode=1
)
exit /b %ERROR_STATE%

:ValidateArguments
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $c=$env:RAW_CASE; if($c -match '\A[0-9]+\z'){ $canonical=$c.TrimStart('0'); if($canonical.Length -gt 0){ Write-Output 'CASE_VALID=1'; Write-Output ('CASE_CANONICAL='+$canonical); Write-Output ('CASE_DISPLAY='+$canonical.PadLeft(3,'0')) } }; $t=$env:RAW_TAG; if($t -match '\A[A-Za-z0-9_-]+\z'){ Write-Output 'TAG_VALID=1'; Write-Output ('TAG_NORMALIZED='+$t.ToUpperInvariant()) }" 2^>nul`) do (
  if /i "%%A"=="CASE_VALID" set "CASE_VALID=%%B"
  if /i "%%A"=="CASE_CANONICAL" set "CASE_CANONICAL=%%B"
  if /i "%%A"=="CASE_DISPLAY" set "CASE_DISPLAY=%%B"
  if /i "%%A"=="TAG_VALID" set "TAG_VALID=%%B"
  if /i "%%A"=="TAG_NORMALIZED" set "TAG_NORMALIZED=%%B"
)
goto :eof

:PrepareParentFolder
set "PARENT_DIR=%SAVE_ROOT%\Case%CASE_DISPLAY%_%TAG_NORMALIZED%"
if exist "%PARENT_DIR%\" (
  echo [INFO] Reusing parent folder: "%PARENT_DIR%"
  goto :eof
)
mkdir "%PARENT_DIR%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to create parent folder: "%PARENT_DIR%"
  set "ERROR_STATE=1"
  goto :eof
)
if not exist "%PARENT_DIR%\" (
  echo [ERROR] Parent folder was not found after creation: "%PARENT_DIR%"
  set "ERROR_STATE=1"
  goto :eof
)
echo [INFO] Created parent folder: "%PARENT_DIR%"
goto :eof

:ReadLogSession
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $p=$env:LOG_SESSION_FILE; if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ exit 2 }; $version=$null; $session=$null; $sessionStart=$null; $logStart=$null; foreach($line in [IO.File]::ReadAllLines($p)){ if($line -cmatch '\AVersion=(.*)\z'){ if($null -ne $version){ exit 3 }; $version=$Matches[1]; continue }; if($line -cmatch '\ASessionId=(.*)\z'){ if($null -ne $session){ exit 3 }; $session=$Matches[1]; continue }; if($line -cmatch '\ASessionStartTimeUtc=(.*)\z'){ if($null -ne $sessionStart){ exit 3 }; $sessionStart=$Matches[1]; continue }; if($line -cmatch '\ALogStartTimeUtc=(.*)\z'){ if($null -ne $logStart){ exit 3 }; $logStart=$Matches[1]; continue } }; if($version -cne '1'){ exit 3 }; $guid=[Guid]::Empty; if(-not [Guid]::TryParseExact($session,'D',[ref]$guid)){ exit 3 }; [DateTime]$sessionTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($sessionStart,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$sessionTime)){ exit 3 }; if($sessionTime.Kind -ne [DateTimeKind]::Utc){ exit 3 }; [DateTime]$logTime=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($logStart,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$logTime)){ exit 3 }; if($logTime.Kind -ne [DateTimeKind]::Utc){ exit 3 }; Write-Output ('SESSION_ID='+$guid.ToString()); Write-Output 'LOG_SESSION_LINK_OK=1'" 2^>nul`) do (
  if /i "%%A"=="SESSION_ID" set "SESSION_ID=%%B"
  if /i "%%A"=="LOG_SESSION_LINK_OK" set "LOG_SESSION_LINK_OK=%%B"
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

:CreateFallbackSessionId
set "SESSION_ID=UNKNOWN"
set "SESSION_ID_OK=0"
call :GetGuid SESSION_ID SESSION_ID_OK
if "%SESSION_ID_OK%"=="0" (
  echo [ERROR] Failed to create fallback SessionId.
  set "ERROR_STATE=1"
)
goto :eof

:WriteVideoMarker
> "%VIDEO_SESSION_TEMP%" (
  echo Version=1
  echo SessionId=%SESSION_ID%
  echo ArgsValid=%ARGS_VALID%
  echo CaseNoCanonical=%CASE_CANONICAL%
  echo TagNormalized=%TAG_NORMALIZED%
  echo VideoStartTimeUtc=%VIDEO_START_UTC%
  echo ObsStartSucceeded=%OBS_START_SUCCEEDED%
)
if errorlevel 1 (
  echo [ERROR] Failed to write video marker temporary file.
  set "ERROR_STATE=1"
  goto :eof
)
move /y "%VIDEO_SESSION_TEMP%" "%VIDEO_SESSION_FILE%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to replace video session marker.
  set "ERROR_STATE=1"
  goto :eof
)
echo [INFO] Updated video session marker: "%VIDEO_SESSION_FILE%"
goto :eof
