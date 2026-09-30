@echo off
set PROGRAMFILES(X86)=C:\Program Files (x86)
set PATH=%PATH%;C:\WINDOWS\System32\WindowsPowerShell\v1.0;C:\flutter\flutter\bin
cd /d E:\main\work\diary_app
del /q build_done.flag 2>nul
flutter build apk --release > build_apk.log 2>&1
echo %errorlevel% > build_done.flag
