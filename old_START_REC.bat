@echo off
setlocal
REM "画面のスクリーンショットをとる"
REM call "%~dp0"scrshot.bat

REM 録画スタート
REM timeout /t 3 > nul
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\TMC\Desktop\Veri\batfile\obs_record_start.ps1"
if errorlevel 1 exit /b 1
REM timeout /t 3 > nul


REM CANログスタート
:CANLOG
REM echo CAN
timeout /t 2 > nul
REM call "%~dp0start_stop_CAN_log.bat"
%~dp0nircmd.exe win activate title "Measurement Setup"
timeout /t 1 > nul
%~dp0nircmd.exe sendkeypress t
timeout /t 1 > nul

REM echo Teraterm42
REM call "%~dp0start_teraterm_ltog_com42.bat"
%~dp0nircmd.exe win activate title "COM42 - Tera Term VT"
timeout /t 1 > nul
%~dp0nircmd.exe sendkeypress alt+f
timeout /t 1 > nul
%~dp0nircmd.exe sendkeypress l
timeout /t 1 > nul
%~dp0nircmd.exe sendkeypress enter
timeout /t 1 > nul


REM if not "%minimized%"=="" goto :minimized
REM set minimized=true
REM start "" /min cmd /C "%~dpnx0" &*
REM goto EOF

REM :minimized
REM timeout /t 2 > nul
%~dp0nircmd.exe sendkeypress rwin+printscreen
exit /b

echo Teraterm39
REM call "%~dp0start_teraterm_log_com39.bat"
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe win activate title "COM39 - Tera Term VT"
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress alt+f
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress l
timeout /t 2 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress enter
timeout /t 1 > nul



exit /b