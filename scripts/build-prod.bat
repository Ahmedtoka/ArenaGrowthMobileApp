@echo off
REM ============================================================
REM  Arena OS — build a PRODUCTION release APK
REM  Points the app at the live server (erp.arenahere.com).
REM
REM  All values come from live.json so there is exactly ONE place
REM  to change them. Hardcoding --dart-define here is what let the
REM  app and the server drift onto different brokers (app on Pusher,
REM  server signing with the Reverb key) — a failure that produces
REM  NO error, just a chat that never updates.
REM
REM  Run from the arena-team-app folder:  scripts\build-prod.bat
REM ============================================================

flutter build apk --release --dart-define-from-file=live.json

echo.
echo ============================================================
echo  Done. APK is at:
echo    build\app\outputs\flutter-apk\app-release.apk
echo  Upload it to: https://erp.arenahere.com/downloads/arena-latest.apk
echo ============================================================
