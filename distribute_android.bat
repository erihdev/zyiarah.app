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
:: "flutter build" has no --clean flag (the old line failed before building
:: anything). Cleaning is its own command, run right before the build.
call flutter clean
call flutter build apk --release
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

:: Firebase App ID of the REAL app (package com.zyiarah.zyiarah) from
:: android/app/google-services.json. The old value pointed at com.zyiarah.app,
:: so every upload was rejected for a package mismatch. Kept in sync with
:: codemagic.yaml by test/app_distribution_guard_test.dart.
set APP_ID=1:275681992607:android:8359bdc64c9ac43fb127aa
set APK_PATH=build\app\outputs\flutter-apk\app-release.apk

:: Testers come from the App Distribution group "testers" - the same group
:: codemagic.yaml publishes to on every build. testers.txt was never in the
:: repo, so the old file-based tester list always failed. (Do not spell the
:: old flag here: test/app_distribution_guard_test.dart matches text.)
call firebase appdistribution:distribute %APK_PATH% ^
    --app %APP_ID% ^
    --groups testers ^
    --release-notes "!release_notes!"

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
