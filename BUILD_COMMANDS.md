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

flutter build apk --release `
  --dart-define=API_BASE_URL=https://erp.arenahere.com/api `
  --dart-define=REVERB_HOST=erp.arenahere.com `
  --dart-define=REVERB_PORT=443 `
  --dart-define=REVERB_SCHEME=wss `
  --dart-define=REVERB_APP_KEY=ef15ebb76813e080d3d380475f7f4de586f9a9aab772c405 `
  --dart-define=APP_ENV=production
```

APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

Note: WebSocket realtime only works once Cloudways has the Nginx
`/app` reverse proxy in place. Until then, FCM push covers
notifications but typing indicator / instant message delivery require
a hard refresh.
