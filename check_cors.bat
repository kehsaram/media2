@echo off
REM Script to check if CORS is properly configured on Firebase Storage

echo ================================================
echo Firebase Storage CORS Configuration Checker
echo ================================================
echo.

REM Check if gsutil is installed
where gsutil >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo X ERROR: gsutil is not installed
    echo.
    echo Please install Google Cloud SDK:
    echo   https://cloud.google.com/sdk/docs/install
    echo.
    pause
    exit /b 1
)

echo * gsutil found
echo.

REM Set bucket name
set BUCKET=gs://media2-38118.appspot.com

echo Checking CORS configuration for: %BUCKET%
echo.

REM Try to get CORS configuration
gsutil cors get %BUCKET% > cors_check.tmp 2>&1

if %ERRORLEVEL% EQU 0 (
    echo * CORS is configured!
    echo.
    echo Current CORS configuration:
    echo ----------------------------
    type cors_check.tmp
    echo.
    
    findstr /C:"\"origin\": [\"*\"]" cors_check.tmp >nul
    if %ERRORLEVEL% EQU 0 (
        echo ! WARNING: Using wildcard origin (*)
        echo    For production, restrict to specific domains
        echo.
    )
    
    echo * Your Firebase Storage is properly configured for web access
    echo.
) else (
    echo X CORS is NOT configured or there was an error
    echo.
    echo Error details:
    type cors_check.tmp
    echo.
    echo To fix this, run:
    echo   gsutil cors set cors.json %BUCKET%
    echo.
    echo See CORS_SETUP.md for detailed instructions
    echo.
    del cors_check.tmp
    pause
    exit /b 1
)

del cors_check.tmp

echo ================================================
echo Next steps:
echo 1. Clear your browser cache (Ctrl+Shift+Delete)
echo 2. Hard reload your app (Ctrl+Shift+R)
echo 3. Check Chrome DevTools Console for errors
echo ================================================
echo.
pause
