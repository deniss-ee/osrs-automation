@echo off
cd /d "%~dp0"
ren  *  ????????????????????????????????????????????.??????????????
setlocal enabledelayedexpansion

:: Check for .jar files in current directory
set "jarFound=false"
set "firstJar="
for %%f in (*.jar) do (
    if "!jarFound!"=="false" (
        set "jarFound=true"
        set "firstJar=%%f"
    )
    echo Found JAR file: %%f
)

if "%jarFound%"=="false" (
    echo ERROR: No .jar files found in current directory.
    echo Please unzip the file first.
    echo.
    pause
    exit /b 1
)

echo.
echo Checking Java installation...

:: Check if Java is in PATH
java -version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Java is not installed or not in PATH.
    echo.
    echo Please visit the following link to install Java:
    echo https://www.oldschoolscripts.com/plugins/precompiled/#java-not-installed
    echo.
    set /p "openLink=Would you like to open this link in your browser? (y/n): "
    if /i "!openLink!"=="y" (
        start https://www.oldschoolscripts.com/plugins/precompiled/#java-not-installed
    )
    echo.
    pause
    exit /b 1
)

:: Display Java version output
echo Java is installed:
java -version 2>&1

echo.
echo Running: %firstJar%

:: Try different memory allocations with display scaling disabled
set "memorySizes=2048m 1536m 1024m 512m 256m"
set "success=false"

for %%m in (%memorySizes%) do (
    if "!success!"=="false" (
        echo Attempting to run...
        java -Dsun.java2d.dpiaware=false -Xmx%%m -jar "%firstJar%"
        if !errorlevel! equ 0 (
            set "success=true"
            echo Successfully run.
        ) else (
            echo Failed with %%m memory, trying next allocation...
            echo.
        )
    )
)

if "!success!"=="false" (
    echo All memory allocation attempts failed.
    echo Trying to run without memory specification...
    java -Dsun.java2d.dpiaware=false -jar "%firstJar%"
)

pause 