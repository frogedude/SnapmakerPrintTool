@echo off
setlocal enabledelayedexpansion
title Snapmaker Print Tool
REM ============================================================
REM Upload + Print + Monitor
REM Based on original scripts: https://forum.snapmaker.com/t/guide-automatic-start-via-drag-drop/29177/33
REM ============================================================
REM USER CONFIGURATION
REM ============================================================
REM MODE : print  = upload and start printing (with monitoring)
REM        upload = upload supported file and firmware only (no printing) 
REM        monitor = monitor current print only (no upload)
set MODE=upload

REM USE_LUBAN   : yes = read IP/token from Luban's machine.json,
REM               no  = use hardcoded IP/TOKEN below
set USE_LUBAN=yes

REM IP and TOKEN : used only if USE_LUBAN=no (or if Luban file missing)
set IP=ip
set TOKEN=token

REM HOMING_MODE : always, auto, prompt, no
set HOMING_MODE=auto

REM LIMIT : file size threshold in bytes for keep-alive (15 MB = 15728640)
set LIMIT=15728640

REM KEEPALIVE : seconds between keep-alive status requests (only for large files)
set KEEPALIVE=2

REM TIMEOUT : seconds to wait after successful completion before closing window
REM           0 = wait for a key press forever (pause)
set TIMEOUT=3

REM TIMEOUT_FAIL : seconds to wait after failure before exiting
set TIMEOUT_FAIL=5

REM MONITOR : yes = show interactive monitoring (only for MODE=print)
set MONITOR=yes

REM SOUND : yes = play beep sound when print completes
REM         no  = no sound
set SOUND=yes

REM SOUND_METHOD : default = use Windows default beep (rundll32)
REM                powershell = use PowerShell beep (customizable)
set SOUND_METHOD=default

REM SOUND_COUNT : number of beeps to play (1-10)
set SOUND_COUNT=1

REM VLC RTSP camera (Requires: https://www.videolan.org)
set VLC=no
set CAMERA_RTSP=rtsp://username:password@ip:port/path

REM KASA smart plug (Requires: https://github.com/frogedude/hs100)
set KASA=no
set KASA_IP=192.168.1.100
set KASA_AUTO_POWER_ON=yes
set KASA_AUTO_POWER_OFF=yes
REM ============================================================

goto :skip_cleanup_temp

REM CLEANUP FUNCTION – removes old temporary files and orphaned keepalive processes
:cleanup_temp
    REM Delete all keepalive batch scripts from temp folder
    if exist "%TEMP%\keepalive_*.bat" del /f /q "%TEMP%\keepalive_*.bat" 2>nul
    
    REM Delete all monitor and print status temp files
    if exist "%TEMP%\monitor_status_*.txt" del /f /q "%TEMP%\monitor_status_*.txt" 2>nul
    if exist "%TEMP%\print_status_*.txt" del /f /q "%TEMP%\print_status_*.txt" 2>nul
    
    REM Delete kasa status temp file
    if exist "%TEMP%\kasa_status.txt" del /f /q "%TEMP%\kasa_status.txt" 2>nul
    
    REM Kill any orphaned keepalive processes (by window title)
    taskkill /FI "WindowTitle eq KeepAlive_*" /F >nul 2>&1
    
    REM Also kill any leftover processes that might have lost their window title
    for /f "tokens=2" %%a in ('tasklist /fi "imagename eq cmd.exe" /v /fo csv ^| findstr /i "KeepAlive" 2^>nul') do (
        taskkill /PID %%a /F >nul 2>&1
    )
goto :eof

:skip_cleanup_temp

REM Call cleanup at start
call :cleanup_temp

REM KASA SMART PLUG FUNCTIONS
if /i "%KASA%"=="yes" (
    set "HS100_EXE="
    
    if exist "%~dp0hs100\hs100.exe" (
        set "HS100_EXE=%~dp0hs100\hs100.exe"
        echo Found hs100.exe in script hs100 subfolder
    )
    
    if not defined HS100_EXE (
        if exist "hs100.exe" (
            set "HS100_EXE=hs100.exe"
            echo Found hs100.exe in current folder
        )
    )
    
    if not defined HS100_EXE (
        where hs100.exe >nul 2>&1
        if %errorlevel% equ 0 (
            for /f "delims=" %%i in ('where hs100.exe') do set "HS100_EXE=%%i"
            echo Found hs100.exe in system PATH
        )
    )
    
    if not defined HS100_EXE (
        echo Warning: hs100.exe not found. Kasa disabled.
        set KASA=no
        set KASA_AUTO_POWER_ON=no
        set KASA_AUTO_POWER_OFF=no
    )
)

goto :skip_kasa_defs

:check_kasa_status
set "KASA_IS_ON=0"
if "%KASA_IP%"=="" goto :eof
if "%HS100_EXE%"=="" goto :eof

"%HS100_EXE%" "%KASA_IP%" info > "%TEMP%\kasa_status.txt" 2>&1

set "KASA_IS_ON=UNKNOWN"

for /f "usebackq delims=" %%L in ("%TEMP%\kasa_status.txt") do (
    echo "%%L" | findstr /i /c:"OFF" >nul 2>&1
    if not errorlevel 1 (
        set "KASA_IS_ON=0"
        goto :break_loop
    )
    echo "%%L" | findstr /i /c:"ON" >nul 2>&1
    if not errorlevel 1 (
        set "KASA_IS_ON=1"
        goto :break_loop
    )
)

:break_loop
del "%TEMP%\kasa_status.txt" 2>nul
goto :eof

:kasa_on
echo Turning Kasa plug ON...
"%HS100_EXE%" "%KASA_IP%" outlet 1 on
if %errorlevel% equ 0 (
    echo Kasa plug turned outlet 1 ON.
) else (
    echo Failed to turn ON Kasa plug.
)
goto :eof

:kasa_off
echo Turning Kasa plug OFF...
"%HS100_EXE%" "%KASA_IP%" outlet 1 off
if %errorlevel% equ 0 (
    echo Kasa plug turned outlet 1 OFF.
) else (
    echo Failed to turn OFF Kasa plug.
)
goto :eof

:auto_power_on_kasa
if "%KASA_AUTO_POWER_ON%"=="no" goto :eof
echo Checking Kasa plug status...
call :check_kasa_status
if %KASA_IS_ON% equ 1 (
    echo Kasa plug is already ON.
    goto :eof
)
echo Kasa plug is OFF. Turning ON...
call :kasa_on
echo Waiting 60 seconds for printer to boot...
timeout /t 60 /nobreak >nul
goto :eof

:play_sound
if /i "%SOUND%"=="no" goto :eof

set "BEEP_COUNT=%SOUND_COUNT%"
if "%BEEP_COUNT%"=="" set BEEP_COUNT=1
if %BEEP_COUNT% lss 1 set BEEP_COUNT=1
if %BEEP_COUNT% gtr 10 set BEEP_COUNT=10

if /i "%SOUND_METHOD%"=="powershell" (
    for /l %%i in (1,1,%BEEP_COUNT%) do (
        powershell -Command "[System.Console]::Beep(880, 300)" >nul 2>&1
        if %%i lss %BEEP_COUNT% timeout /t 1 /nobreak >nul
    )
) else (
    for /l %%i in (1,1,%BEEP_COUNT%) do (
        rundll32 user32.dll,MessageBeep >nul 2>&1
        if %%i lss %BEEP_COUNT% timeout /t 2 /nobreak >nul
    )
)
goto :eof

:start_keepalive
set "KEEPALIVE_PID="
set "temp_keepalive="
set "rand="

if %SIZE% leq %LIMIT% goto :eof

echo Starting keep-alive...
set rand=%RANDOM%
set temp_keepalive=%TEMP%\keepalive_%rand%.bat
(
echo @echo off
echo title KeepAlive_%rand%
echo echo Maintaining connection...
echo curl.exe -s -X POST "http://%IP%:8080/api/v1/connect?token=%TOKEN%" ^>nul 2^>^&1
echo :loop
echo curl.exe -s -X GET "http://%IP%:8080/api/v1/status?token=%TOKEN%" ^>nul 2^>^&1
echo timeout /t %KEEPALIVE% /nobreak ^>nul 2^>^&1
echo goto loop
) > "%temp_keepalive%" 2>nul
start "KeepAlive_%rand%" /min cmd /c "%temp_keepalive%"
timeout /t 1 /nobreak >nul
for /f "tokens=2" %%a in ('tasklist /fi "windowtitle eq KeepAlive_%rand%" /nh 2^>nul') do set KEEPALIVE_PID=%%a
goto :eof

:stop_keepalive
if defined KEEPALIVE_PID (
    taskkill /PID %KEEPALIVE_PID% /F >nul 2>&1
) else if defined rand (
    taskkill /FI "WindowTitle eq KeepAlive_%rand%" /F >nul 2>&1
)
if defined temp_keepalive if exist "%temp_keepalive%" del "%temp_keepalive%" 2>nul
REM Also delete any remaining keepalive script (cleanup)
if defined rand if exist "%TEMP%\keepalive_%rand%.bat" del "%TEMP%\keepalive_%rand%.bat" 2>nul
goto :eof

:skip_kasa_defs

set "JSON_FILE=%APPDATA%\snapmaker-luban\machine.json"
if /i "%USE_LUBAN%"=="yes" (
    if exist "%JSON_FILE%" (
        echo Reading Luban config...
        for /f "usebackq delims=" %%i in (`
            powershell -Command "$json = Get-Content '%JSON_FILE%' -Raw | ConvertFrom-Json; $json.state.server.address; $json.state.server.token"
        `) do (
            if not defined LUBAN_IP (set "LUBAN_IP=%%i") else (set "LUBAN_TOKEN=%%i")
        )
        if defined LUBAN_IP if defined LUBAN_TOKEN (
            set "IP=!LUBAN_IP!"
            set "TOKEN=!LUBAN_TOKEN!"
            echo Using Luban settings
        ) else (
            echo Warning: Could not parse machine.json - using hardcoded values.
        )
    ) else (
        echo machine.json not found - using hardcoded values.
    )
) else (
    echo Using hardcoded IP and token.
)

where curl.exe >nul 2>&1
if %errorlevel% neq 0 (
    echo curl.exe missing
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)

if /i "%MODE%"=="monitor" goto monitor_only

if /i "%KASA%"=="yes" if "%KASA_AUTO_POWER_ON%"=="yes" call :auto_power_on_kasa

echo Checking printer at %IP%...
curl.exe -s -o nul --connect-timeout 3 "http://%IP%:8080/api/v1/status?token=%TOKEN%"
if %errorlevel% neq 0 (
    echo ERROR: Printer not reachable at %IP%:8080.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)
echo Printer is online.

curl.exe -s -X POST "http://%IP%:8080/api/v1/connect?token=%TOKEN%" >nul 2>&1
set "TOOLHEAD="
for /f "usebackq delims=" %%i in (`
    powershell -Command "$resp = (curl.exe -s -X GET 'http://%IP%:8080/api/v1/status?token=%TOKEN%'); $json = $resp | ConvertFrom-Json; $tool = $json.toolHead; if ($tool -match 'LASER') { 'Laser' } elseif ($tool -match 'CNC') { 'CNC' } elseif ($tool -match '3DP') { '3DP' } else { 'Unknown' }"
`) do set "TOOLHEAD=%%i"
if not defined TOOLHEAD set "TOOLHEAD=Unknown"
echo Detected toolhead: %TOOLHEAD%

REM File validation
if "%~1"=="" (
    echo Drag and drop a file.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)
set "FILE=%~f1"
if not exist "%FILE%" (
    echo File not found. Possible cause: Filename contains unsupported special characters.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)

set "EXT=%~x1"
set "EXT=%EXT:.=%"
set "ALLOWED=0"
if /i "%EXT%"=="gcode" (
    if /i "%MODE%"=="upload" (
        REM In UPLOAD mode, .gcode is only for 3DP
        if /i "%TOOLHEAD%"=="3DP" (
            set "ALLOWED=1"
            set "TYPE=3DP"
            echo .gcode accepted for 3DP upload
        ) else (
            echo Error: In UPLOAD mode, .gcode files require 3DP toolhead
            echo Current toolhead: %TOOLHEAD%
        )
    ) else (
        REM In PRINT mode, .gcode works with all toolheads
        set "ALLOWED=1"
        set "TYPE=%TOOLHEAD%"
        echo .gcode accepted for toolhead %TYPE%
    )
)
if /i "%EXT%"=="nc" (
    if /i "%TOOLHEAD%"=="Laser" (
        set "ALLOWED=1"
        set "TYPE=Laser"
        echo .nc accepted for Laser
    ) else (
        echo Error: .nc requires Laser toolhead
    )
)
if /i "%EXT%"=="cnc" (
    if /i "%TOOLHEAD%"=="CNC" (
        set "ALLOWED=1"
        set "TYPE=CNC"
        echo .cnc accepted for CNC
    ) else (
        echo Error: .cnc requires CNC toolhead
    )
)
if /i "%EXT%"=="bin" (
    if /i "%MODE%"=="upload" (
        set "ALLOWED=1"
        set "TYPE=FIRMWARE"
        echo .bin file accepted for firmware upload
    ) else (
        echo Error: .bin files are for firmware only. Use MODE=upload
    )
)

if %ALLOWED% equ 0 (
    echo Error: File type ".%EXT%" not allowed.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)

echo Checking printer idle status...
for /f "usebackq delims=" %%i in (`powershell -Command "$resp = (curl.exe -s -X GET 'http://%IP%:8080/api/v1/status?token=%TOKEN%'); $json = $resp | ConvertFrom-Json; $json.status"`) do set "PRINT_STATUS=%%i"
if not "!PRINT_STATUS!"=="IDLE" (
    echo Error: Printer is not idle. Current status: !PRINT_STATUS!.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)
echo Printer is idle, proceeding.

set "NEED_HOME=0"
if /i "%HOMING_MODE%"=="always" (
    set "NEED_HOME=1"
) else if /i "%HOMING_MODE%"=="auto" (
    for /f "usebackq delims=" %%a in (`powershell -Command "(curl.exe -s -X GET 'http://%IP%:8080/api/v1/status?token=%TOKEN%' | ConvertFrom-Json).homed"`) do set "H=%%a"
    if /i "!H!"=="false" set "NEED_HOME=1"
) else if /i "%HOMING_MODE%"=="prompt" (
    for /f "usebackq delims=" %%a in (`powershell -Command "(curl.exe -s -X GET 'http://%IP%:8080/api/v1/status?token=%TOKEN%' | ConvertFrom-Json).homed"`) do set "H=%%a"
    if /i "!H!"=="false" (
        echo.
        echo The machine is not homed. Homing is recommended before printing.
        choice /C YN /N /T 10 /D Y /M "Home now? (Y/N, default Y in 10 sec): "
        if errorlevel 2 (
            echo Homing skipped.
        ) else (
            set "NEED_HOME=1"
        )
    )
)
if %NEED_HOME% equ 1 (
    echo Homing machine...
    curl.exe -s -X POST "http://%IP%:8080/api/v1/execute_code?token=%TOKEN%&code=G28" >nul 2>&1
    timeout /t 2 /nobreak >nul
    echo Homing finished.
)

REM Branch based on mode
if /i "%MODE%"=="upload" goto upload_only

REM ============================================================
REM MODE: PRINT - Full upload and print
REM ============================================================

set SIZE=%~z1
if "%SIZE%"=="" set SIZE=0
call :start_keepalive

:upload_print
echo Uploading "%FILE%" (%SIZE% bytes)...
curl.exe -# -X POST -F "file=@\"%FILE%\"" "http://%IP%:8080/api/v1/prepare_print?token=%TOKEN%&type=%TYPE%" -o nul
set UPLOAD_ERROR=%errorlevel%

call :stop_keepalive

if %UPLOAD_ERROR% neq 0 (
    echo Upload failed.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)

echo Starting print...
curl.exe -s -X POST "http://%IP%:8080/api/v1/start_print?token=%TOKEN%" >nul 2>&1

set "STATUS_FILE=%TEMP%\print_status_%rand%.txt"
set "RUNNING=0"
for /l %%i in (1,1,30) do (
    timeout /t 1 >nul
    curl.exe -s -X GET "http://%IP%:8080/api/v1/status?token=%TOKEN%" > "%STATUS_FILE%"
    findstr /i "RUNNING" "%STATUS_FILE%" >nul
    if !errorlevel! equ 0 set "RUNNING=1"
    if !RUNNING! equ 1 goto :monitor_print
)

:monitor_print
if /i "%MONITOR%"=="yes" (
    goto :monitor_only
)
goto :end

REM ============================================================
REM MODE: UPLOAD - Upload file only
REM ============================================================

:upload_only
echo Upload mode selected.

set SIZE=%~z1
if "%SIZE%"=="" set SIZE=0
call :start_keepalive

:upload_file
echo Uploading "%FILE%" (%SIZE% bytes)...
curl.exe -# -X POST -F "file=@\"%FILE%\"" "http://%IP%:8080/api/v1/upload?token=%TOKEN%" -o nul
set UPLOAD_ERROR=%errorlevel%

call :stop_keepalive

if %UPLOAD_ERROR% neq 0 (
    echo Upload failed.
    if %TIMEOUT_FAIL% equ 0 (pause) else timeout /t %TIMEOUT_FAIL% /nobreak >nul
    exit /b 1
)

echo Upload completed successfully.
goto :end

REM ============================================================
REM MODE: MONITOR - Monitor current print only
REM ============================================================

:monitor_only
echo Monitor mode selected.
echo Waiting for print to start or become active...
echo Press X to exit.

if /i "%VLC%"=="yes" (
    if not "%CAMERA_RTSP%"=="" (
        set "VLC_EXE="
        for /f "skip=2 tokens=2*" %%a in ('reg query "HKLM\Software\VideoLAN\VLC" /v "InstallDir" 2^>nul') do set "VLC_DIR=%%b"
        if defined VLC_DIR if exist "%VLC_DIR%\vlc.exe" set "VLC_EXE=%VLC_DIR%\vlc.exe"
        if not defined VLC_EXE (
            if exist "C:\Program Files\VideoLAN\VLC\vlc.exe" set "VLC_EXE=C:\Program Files\VideoLAN\VLC\vlc.exe"
            if exist "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe" set "VLC_EXE=C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        )
        if defined VLC_EXE (
            echo Launching VLC with RTSP source: %CAMERA_RTSP%
            start "" "!VLC_EXE!" "%CAMERA_RTSP%"
        )
    )
)

set "STATUS_FILE=%TEMP%\monitor_status_%rand%.txt"
set "lastStatus="
set "MONITOR_ACTIVE=1"

:wait_for_print
timeout /t 2 >nul
curl -s -X GET "http://%IP%:8080/api/v1/status?token=%TOKEN%" > "%STATUS_FILE%" 2>nul

findstr /i "RUNNING" "%STATUS_FILE%" >nul 2>&1
if %errorlevel% equ 0 goto :monitor_loop_mon

findstr /i "PAUSED" "%STATUS_FILE%" >nul 2>&1
if %errorlevel% equ 0 goto :monitor_loop_mon

cls
echo Waiting for print to start...
echo Press X to exit.

for /f "delims=" %%k in ('powershell -Command "if ($Host.UI.RawUI.KeyAvailable) { $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); Write-Host $k.Character }"') do set "KEY=%%k"
if defined KEY (
    if /i "!KEY!"=="X" goto :end
)

goto :wait_for_print

:monitor_loop_mon
if %MONITOR_ACTIVE% equ 0 goto :end

timeout /t 2 >nul

curl -s -X GET "http://%IP%:8080/api/v1/status?token=%TOKEN%" > "%STATUS_FILE%" 2>nul
if %errorlevel% neq 0 goto :monitor_loop_mon

for /f "usebackq delims=" %%a in (`
    powershell -Command "$ErrorActionPreference='Stop'; $j = Get-Content '%STATUS_FILE%' -Raw | ConvertFrom-Json 2>$null; if ($j) { Write-Host $j.status '|' $j.progress '|' $j.remainingTime } else { Write-Host 'ERROR| |' }"
`) do (
    for /f "tokens=1-3 delims=|" %%x in ("%%a") do (
        set "STATUS=%%x"
        set "PCT=%%y"
        set "REM=%%z"
    )
)

set "STATUS=!STATUS: =!"
set "PCT=!PCT: =!"
set "REM=!REM: =!"

if not "!PCT!"=="" (
    if not "!PCT!"=="null" (
        for /f %%c in ('powershell -Command "!PCT! * 100" 2^>nul') do set "PCT=%%c"
        set "PCT=!PCT:~0,5!"
    ) else (
        set "PCT="
    )
)

if not "!REM!"=="" (
    if "!REM!"=="null" set "REM="
)

cls
echo ===========================================
echo Snapmaker Print Monitor
echo ===========================================
if defined STATUS (
    if /i "!STATUS!"=="RUNNING" echo Status: RUNNING
    if /i "!STATUS!"=="PAUSED" echo Status: PAUSED
    if /i "!STATUS!"=="IDLE" echo Status: IDLE - Print completed
    if /i "!STATUS!"=="ERROR" echo Status: ERROR - Check connection
)
if defined PCT if not "!PCT!"=="" echo Progress: !PCT!%%
if defined REM if not "!REM!"=="" echo Remaining: !REM! seconds
echo ===========================================
echo Commands: P=Pause, R=Resume, S=Stop, X=Exit
echo ===========================================

if /i "!STATUS!"=="IDLE" (
    echo.
    echo Print completed.
    set "MONITOR_ACTIVE=0"
    
    call :play_sound

    if /i "%KASA%"=="yes" if "%KASA_AUTO_POWER_OFF%"=="yes" (
        call :kasa_off
    )

    goto :end
)

for /f "delims=" %%k in ('powershell -Command "if ($Host.UI.RawUI.KeyAvailable) { $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); Write-Host $k.Character }"') do set "KEY=%%k"
if defined KEY (
    if /i "!KEY!"=="P" curl -s -X POST "http://%IP%:8080/api/v1/pause_print?token=%TOKEN%" >nul 2>&1
    if /i "!KEY!"=="R" curl -s -X POST "http://%IP%:8080/api/v1/resume_print?token=%TOKEN%" >nul 2>&1
    if /i "!KEY!"=="S" (
        curl -s -X POST "http://%IP%:8080/api/v1/stop_print?token=%TOKEN%" >nul 2>&1
        echo Stopped
        set "MONITOR_ACTIVE=0"
        goto :end
    )
    if /i "!KEY!"=="X" (
        set "MONITOR_ACTIVE=0"
        goto :end
    )
)

goto :monitor_loop_mon

:end
REM Clean up status temp file
if defined STATUS_FILE if exist "%STATUS_FILE%" del "%STATUS_FILE%" 2>nul

REM Final cleanup of any leftover temp files and processes
call :cleanup_temp

if /i "%MODE%"=="monitor" (
    echo Monitor ended.
    echo.
) else if /i "%MODE%"=="upload" (
    REM No message for upload mode (silent)
    echo.
) else if /i "%MODE%"=="print" (
    if /i "%MONITOR%"=="yes" (
        echo Monitor ended.
        echo.
    ) else if /i "%MONITOR%"=="no" (
        echo Monitoring disabled.
        echo.
    )
)

if %TIMEOUT% equ 0 (
    pause
) else (
    timeout /t %TIMEOUT% /nobreak >nul
)
exit /b