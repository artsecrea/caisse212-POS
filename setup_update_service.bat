@echo off
REM Quick Setup Script for Update Service (Windows)

echo.
echo ========================================
echo   Update Service Setup
echo ========================================
echo.

REM Step 1: Create Android FileProvider directory
echo [1/3] Creating Android FileProvider directory...
if not exist "android\app\src\main\res\xml" mkdir "android\app\src\main\res\xml"

REM Step 2: Create file_paths.xml
echo [2/3] Creating file_paths.xml...
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<paths xmlns:android="http://schemas.android.com/apk/res/android"^>
echo     ^<external-path name="external_files" path="."/^>
echo     ^<external-cache-path name="external_cache" path="."/^>
echo ^</paths^>
) > "android\app\src\main\res\xml\file_paths.xml"

REM Step 3: Install dependencies
echo [3/3] Installing dependencies...
call flutter pub get

echo.
echo ========================================
echo   Setup Complete!
echo ========================================
echo.
echo Next steps:
echo   1. Implement your update API in lib/services/update_service.dart
echo   2. Add update check to your login screen
echo   3. Test the update flow
echo.
echo Documentation:
echo   - Full guide: UPDATE_SERVICE_README.md
echo   - Installation: UPDATE_INSTALLATION.md
echo   - Summary: UPDATE_IMPLEMENTATION_SUMMARY.md
echo.
echo Ready to implement updates!
echo.

pause
