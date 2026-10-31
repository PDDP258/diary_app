@echo off
rem NOTE: CRLF + ASCII only. cmd.exe mis-parses LF-only batch files
rem (it would split a line and try to run "DATA" as a command).
rem The sandbox bash env has no LOCALAPPDATA, and package:test_core's
rem _globalConfigPath does Platform.environment['LOCALAPPDATA']!,
rem so without this the whole test run dies with a null-check error.
set "LOCALAPPDATA=C:\Users\PDXX\AppData\Local"
set "APPDATA=C:\Users\PDXX\AppData\Roaming"
set "USERPROFILE=C:\Users\PDXX"
set "TEMP=%LOCALAPPDATA%\Temp"
set "TMP=%LOCALAPPDATA%\Temp"
set "PATH=C:\flutter\flutter\bin;C:\flutter\flutter\bin\cache\dart-sdk\bin;C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%"
set "ProgramFiles=C:\Program Files"
set "ProgramFiles(x86)=C:\Program Files (x86)"
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
cd /d "E:\main\work\diary_app"
flutter.bat test --no-pub %*
