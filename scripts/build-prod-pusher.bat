@echo off
REM ============================================================
REM  Arena OS — PRODUCTION APK pointed at HOSTED PUSHER
REM  (temporary, until Cloudways enables the Reverb WS proxy —
REM   then go back to scripts\build-prod.bat)
REM
REM  BEFORE RUNNING: replace YOUR_PUSHER_KEY below with the "key"
REM  from your pusher.com app (cluster assumed: eu — if you chose
REM  a different cluster, also change ws-eu accordingly).
REM
REM  The API still points at YOUR server — only the realtime
REM  WebSocket moves to Pusher. /broadcasting/auth stays on your
REM  server too (private channels keep working unchanged).
REM
REM  Run from the arena-team-app folder:  scripts\build-prod-pusher.bat
REM ============================================================

flutter build apk --release ^
  --dart-define=APP_ENV=production ^
  --dart-define=API_BASE_URL=https://erp.arenahere.com/api ^
  --dart-define=REVERB_HOST=ws-eu.pusher.com ^
  --dart-define=REVERB_PORT=443 ^
  --dart-define=REVERB_SCHEME=wss ^
  --dart-define=REVERB_APP_KEY=b587dc29173ecaf4f770

echo.
echo ============================================================
echo  Done. APK is at:
echo    build\app\outputs\flutter-apk\app-release.apk
echo  Upload it to: https://erp.arenahere.com/downloads/arena-latest.apk
echo ============================================================
