@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo   Zyiarah Android Distribution Utility
echo ====================================================

:: 1. Check for Firebase CLI
echo [*] Checking Firebase CLI...
call firebase --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Firebase CLI not found. Please install it first.
    pause
    exit /b 1
)

:: 2. Check for Flutter
echo [*] Checking Flutter...
call flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Flutter not found. Please ensure Flutter is in your PATH.
    pause
    exit /b 1
)

:: 3. Interactive Release Notes
echo.
set /p release_notes="[?] Enter Release Notes (what's new?): "
if "!release_notes!"=="" set release_notes="New build for testing"

echo.
echo ====================================================
echo   Step 1: Building APK (Release Mode)
echo ====================================================
call flutter build apk --release --clean
if %errorlevel% neq 0 (
    echo [ERROR] Flutter build failed. Stopping.
    pause
    exit /b 1
)

echo.
echo ====================================================
echo   Step 2: Uploading to Firebase App Distribution
echo ====================================================
echo [*] Uploading build...

:: Firebase App ID from google-services.json
set APP_ID=1:275681992607:android:369f833ebbd0a9f7b127aa
set APK_PATH=build\app\outputs\flutter-apk\app-release.apk

call firebase appdistribution:distribute %APK_PATH% ^
    --app %APP_ID% ^
    --release-notes "!release_notes!" ^
    --testers-file testers.txt

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Upload failed. Check if you are logged in (firebase login).
) else (
    echo.
    echo ====================================================
    echo   SUCCESS: Build is now available for testers!
    echo ====================================================
)

pause
