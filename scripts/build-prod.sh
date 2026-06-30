#!/usr/bin/env bash
# ============================================================
#  Arena OS — build a PRODUCTION release APK
#  Points the app at the live server (erp.arenahere.com).
#
#  The default build targets the local emulator
#  (http://10.0.2.2:8000) which a real phone can't reach — that's
#  the "connection timeout" on login. These --dart-define values
#  override it with the live host.
#
#  Run from the arena-team-app folder:  bash scripts/build-prod.sh
# ============================================================
set -e

flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://erp.arenahere.com/api \
  --dart-define=REVERB_HOST=erp.arenahere.com \
  --dart-define=REVERB_PORT=443 \
  --dart-define=REVERB_SCHEME=wss \
  --dart-define=REVERB_APP_KEY=ef15ebb76813e080d3d380475f7f4de586f9a9aab772c405

echo ""
echo "Done. APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Upload to: https://erp.arenahere.com/downloads/arena-latest.apk"
