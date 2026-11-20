@echo off
rem ag-zh Windows launcher: prefer PowerShell 7, fall back to Windows PowerShell 5.1
chcp 65001 >nul
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0ag-zh.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ag-zh.ps1" %*
)
exit /b %ERRORLEVEL%
