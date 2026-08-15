# Arena OS Mobile — build / run cheat-sheet

The Flutter app reads its API + Reverb config from build-time
`--dart-define` args (see `lib/core/config/env.dart`). Two environments
are supported: **local** (default) and **production**.

---

## Local development (Android emulator)

```powershell
cd D:\XamppPhp8.2\htdocs\arena-team-app
flutter run
```

That's it — `env.dart` defaults already point at:

* API:    `http://10.0.2.2:8000/api`   ← emulator → host loopback
* Reverb: `ws://10.0.2.2:8080`
* App key: `teamos-local-dev-key`

Make sure on the host machine:

```powershell
# Terminal A — Laravel
cd D:\XamppPhp8.2\htdocs\arena-team
php artisan serve --host=0.0.0.0 --port=8000

# Terminal B — Reverb daemon
cd D:\XamppPhp8.2\htdocs\arena-team
php artisan reverb:start --host=0.0.0.0 --port=8080
```

## Local development (real phone on the same WiFi)

Find your Windows IP (`ipconfig | findstr IPv4`), then:

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.10:8000/api `
  --dart-define=REVERB_HOST=192.168.1.10 `
  --dart-define=REVERB_PORT=8080 `
  --dart-define=REVERB_SCHEME=ws `
  --dart-define=REVERB_APP_KEY=teamos-local-dev-key
```

(Replace `192.168.1.10` with your actual LAN IP.)

---

## Production APK (erp.arenahere.com)

```powershell
cd D:\XamppPhp8.2\htdocs\arena-team-app

flutter clean
flutter pub get

flutter build apk --release --dart-define-from-file=live.json
```

All live values (API host, broker host, app key) come from
`live.json` — the single source of truth. Do NOT pass `--dart-define`
flags by hand: `REVERB_APP_KEY` must match the key the SERVER signs
`/broadcasting/auth` with, and when the two drift apart nothing errors.
`/broadcasting/auth` still returns 200, the subscribe is rejected as an
invalid signature, and the chat simply never updates.

The dashboard's `VITE_REVERB_APP_KEY` / `VITE_REVERB_HOST` must point
at that same broker, or web and mobile end up on different ones.

APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

Note: the Cloudways Nginx `/app` reverse proxy is now in place —
`wss://erp.arenahere.com/app/<reverb-key>` completes a WebSocket
handshake and answers `X-Powered-By: Laravel Reverb`. Either broker
works; what matters is that the app, the dashboard and the server all
name the SAME one.
