@echo off
REM ============================================================
REM  Arena OS — build a PRODUCTION release APK
REM  Points the app at the live server (erp.arenahere.com).
REM
REM  The default build points at the local emulator
REM  (http://10.0.2.2:8000) — a real phone can't reach that, which
REM  is exactly why login showed "connection timeout". These
REM  --dart-define values override that with the live host.
REM
REM  Run from the arena-team-app folder:  scripts\build-prod.bat
REM ============================================================

flutter build apk --release ^
  --dart-define=APP_ENV=production ^
  --dart-define=API_BASE_URL=https://erp.arenahere.com/api ^
  --dart-define=REVERB_HOST=erp.arenahere.com ^
  --dart-define=REVERB_PORT=443 ^
  --dart-define=REVERB_SCHEME=wss ^
  --dart-define=REVERB_APP_KEY=ef15ebb76813e080d3d380475f7f4de586f9a9aab772c405

echo.
echo ============================================================
echo  Done. APK is at:
echo    build\app\outputs\flutter-apk\app-release.apk
echo  Upload it to: https://erp.arenahere.com/downloads/arena-latest.apk
echo ============================================================
