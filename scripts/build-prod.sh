#!/usr/bin/env bash
# ============================================================
#  Arena OS — build a PRODUCTION release APK
#  Points the app at the live server (erp.arenahere.com).
#
#  All values come from live.json so there is exactly ONE place
#  to change them. Hardcoding --dart-define here is what let the
#  app and the server drift onto different brokers (app on Pusher,
#  server signing with the Reverb key) — a failure that produces
#  NO error, just a chat that never updates.
#
#  Run from the arena-team-app folder:  bash scripts/build-prod.sh
# ============================================================
set -e

flutter build apk --release --dart-define-from-file=live.json

echo ""
echo "Done. APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Upload to: https://erp.arenahere.com/downloads/arena-latest.apk"
