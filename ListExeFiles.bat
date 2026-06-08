@echo off
setlocal EnableExtensions

set "initialTarget=%~1"

:main
cls
echo List EXE Files
echo.
echo Output: file names only, one EXE per line.
echo Type Q and press Enter to exit.
echo.

if defined initialTarget (
    set "target=%initialTarget%"
    set "initialTarget="
) else (
    set /p "target=Enter folder path to scan: "
)

set "target=%target:"=%"

if /i "%target%"=="Q" goto :eof

if "%target%"=="" (
    echo.
    echo No path entered.
    echo.
    pause
    goto main
)

if exist "%target%\" (
    set "scanDir=%target%"
) else if exist "%target%" (
    for %%I in ("%target%") do set "scanDir=%%~dpI"
) else (
    echo.
    echo Path does not exist: %target%
    echo.
    pause
    goto main
)

echo.
echo EXE files under:
echo %scanDir%
echo.

set "found="
for /r "%scanDir%" %%F in (*.exe) do (
    set "found=1"
    echo %%~nxF
)

if not defined found (
    echo No exe files found.
)

echo.
pause
goto main
