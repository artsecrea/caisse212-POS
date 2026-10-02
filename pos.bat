@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pos.ps1" %*
exit /b %ERRORLEVEL%
