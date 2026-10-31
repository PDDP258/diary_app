@echo off
rem NOTE: CRLF + ASCII only. cmd.exe mis-parses LF-only batch files.
rem Same env hardening as run_flutter_test.bat: the sandbox bash exports no
rem LOCALAPPDATA, and flutter's PowerShell/registry lookups need the
rem ProgramFiles variables to exist.
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
flutter.bat analyze --no-pub %*
