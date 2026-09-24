@echo off
setlocal
cd /d "%~dp0\.."

call flutterw clean
copy /y flavors\pubspec_libre.lock pubspec.lock
copy /y flavors\pubspec_libre.yaml pubspec.yaml
call flutterw pub get --enforce-lockfile
