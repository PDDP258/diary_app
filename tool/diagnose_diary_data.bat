@echo off
REM ============================================================
REM  小记日记 · 数据诊断与恢复工具
REM
REM  用途：当 App 显示「日记 0 篇」时，直接检查手机上的真实数据。
REM
REM  这会读取 App 私有目录，需要 adb root 或 run-as（debug 包可用）。
REM  Release 包通常无法直接读私有目录，此时请用「备份管理」页面导出。
REM ============================================================

setlocal
set ADB="C:\Users\PDXX\AppData\Local\Android\Sdk\platform-tools\adb.exe"
set PKG=com.example.diary_app

echo.
echo ==== 1. 检查设备连接 ====
%ADB% devices
echo.

echo ==== 2. 检查 App 是否安装 ====
%ADB% shell pm list packages ^| findstr %PKG%
echo.

echo ==== 3. 检查 SharedPreferences 文件是否存在于私有目录 ====
%ADB% shell run-as %PKG% ls -l /data/data/%PKG%/shared_prefs/
echo.

echo ==== 4. 查看 prefs 文件大小（关键：看 diaries 相关键还在不在） ====
%ADB% shell run-as %PKG% cat /data/data/%PKG%/shared_prefs/FlutterSharedPreferences.xml ^| findstr /C:"diaries_data" /C:"diary_index" /C:"diary_" /C:"diary_split"
echo.

echo ==== 5. 统计各键的长度（判断数据量） ====
%ADB% shell run-as %PKG% cat /data/data/%PKG%/shared_prefs/FlutterSharedPreferences.xml ^| findstr /O /C:"diaries_data"
echo.

echo ==== 6. 导出 prefs 到电脑（用于恢复） ====
if not exist "%~dp0recovered" mkdir "%~dp0recovered"
%ADB% shell run-as %PKG% cat /data/data/%PKG%/shared_prefs/FlutterSharedPreferences.xml > "%~dp0recovered\FlutterSharedPreferences.xml"
echo 已尝试导出到: %~dp0recovered\FlutterSharedPreferences.xml
echo.

echo ==== 7. 检查自动备份目录 ====
%ADB% shell run-as %PKG% ls -l /data/data/%PKG%/app_flutter/auto_backups/ 2>nul
%ADB% shell ls -l /sdcard/Android/data/%PKG%/files/auto_backups/ 2>nul
echo.

echo ==== 完毕 ====
echo 若第 3/4 步显示 diaries_data 或 diary_ 键存在，说明数据没丢，可以恢复。
pause
