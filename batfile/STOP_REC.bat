@echo off
setlocal

echo CAN
timeout /t 2 > nul
REM call "%~dp0start_stop_CAN_log.bat"
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe win activate title "Measurement Setup"
timeout /t 2 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress t
timeout /t 2 > nul

echo 録画
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\TMC\Desktop\Veri\batfile\obs_record_stop.ps1"
if errorlevel 1 exit /b 1
REM timeout /t 2 > nul

echo Teraterm42
REM call "%~dp0stop_teraterm_log_com42.bat"
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe win activate title "COM42 - Tera Term VT"
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress alt+f
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress q
timeout /t 5 > nul

REM アーカイブ
REM コピー先のフォルダを作成する ーーーー 
REM   c:\Users\TMC\Desktop\LogZipsの中のLogZip内の日付時刻フォルダを作成する
set BASEDIR=C:\Users\TMC\Desktop\LogZips
set DT=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set DT=%DT: =0%
REM echo "%BASEDIR%\%DT%"
set DESTFOLDER=%BASEDIR%\%DT%
mkdir %DESTFOLDER%

move C:\Users\TMC\Videos\Captures\*.mp4 %DESTFOLDER%
move C:\Users\TMC\Pictures\Screenshots\*.png %DESTFOLDER%
REM move C:\work\teraterm-5.2\teraterm-5.2\log\*.log %DESTFOLDER%
move C:\teraterm-5.2\log\*.log %DESTFOLDER%
move C:\Users\TMC\Desktop\LogZips\CANtemp\*.asc %DESTFOLDER%

REM 7z 圧縮
REM set "SEVENZIP=%ProgramFiles%7-Zip\7z.exe"
REM "%SEVENZIP%" a -t7z "%DESTFOLDER%.7z" "%DESTFOLDER%" -mx=9 >nul


exit /b

echo Teraterm39
REM call "%~dp0stop_teraterm_log_com39.bat"
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe win activate title "COM39 - Tera Term VT"
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress alt+f
timeout /t 1 > nul
C:\Users\TMC\Desktop\Veri\batfile\nircmd.exe sendkeypress q
timeout /t 5 > nul

exit /b
