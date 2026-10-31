@echo off
rem 给 Windows 计划任务用：从 WebDAV 拉最新备份、重建索引。
rem 路径全部用绝对路径，因为计划任务的工作目录不可控。
setlocal
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

if not exist "%~dp0..\data" mkdir "%~dp0..\data"
"%~dp0..\.venv\Scripts\python.exe" -m diary_mcp -c "%~dp0..\config.toml" sync >> "%~dp0..\data\sync.log" 2>&1
exit /b %ERRORLEVEL%
