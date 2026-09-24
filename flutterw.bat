@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "FLUTTER_BAT=%SCRIPT_DIR%.flutter\bin\flutter.bat"

if not defined PUB_CACHE set "PUB_CACHE=E:\Agent\.pub-cache"
if not defined GRADLE_USER_HOME set "GRADLE_USER_HOME=E:\Agent\.gradle"
if not defined ANDROID_HOME set "ANDROID_HOME=E:\Agent\TFTF\toolchain\android-sdk"
if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=E:\Agent\TFTF\toolchain\android-sdk"
if not defined ANDROID_NDK_ROOT set "ANDROID_NDK_ROOT=E:\Agent\TFTF\toolchain\android-ndk-r26b"

if not exist "%FLUTTER_BAT%" (
    echo [flutterw] .flutter submodule not found. Initializing...
    git -C "%SCRIPT_DIR%" submodule update --init --depth 1 .flutter
)

call "%FLUTTER_BAT%" %*
exit /b %ERRORLEVEL%
