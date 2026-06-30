# Arena Team — Flutter Mobile App

تطبيق موبايل يتكامل مع Laravel API.

البنية متبعة نمط **Feature-based / Clean** لتسهيل الإضافة عند تحويل كل feature من السيستم القديم.

---

## 🚀 خطوات التشغيل أول مرة

```bash
# 1) ادخل على فولدر المشروع
cd D:\XamppPhp8.2\htdocs\arena-team-app

# 2) لازم flutter create يضيف فولدرات android/ios/web لأن المشروع ده structure فقط
flutter create . --org com.arenateam --project-name arena_team_app --platforms=android,ios

# 3) جيب الـ packages
flutter pub get

# 4) شغّل
flutter run
```

> ملاحظة: عند تشغيل `flutter create .` ممكن يسأل هل يستبدل الملفات الموجودة. اضغط **n** (no) عشان ميمسحش الكود اللي تحت `lib/`.

---

## 📂 هيكل المشروع

```
lib/
├── main.dart                   # entry point - يجهّز الـ dependencies
├── app.dart                    # MaterialApp + Theme + Locale + RTL
├── core/                       # كل الحاجات المشتركة
│   ├── constants/              # API_BASE_URL، storage keys، app constants
│   ├── theme/                  # ألوان، خطوط، Theme كامل
│   ├── network/                # Dio client + interceptors (auth, logger)
│   ├── storage/                # SharedPrefs + Flutter Secure Storage
│   ├── routing/                # go_router + كل المسارات
│   ├── errors/                 # ApiException موحّد
│   ├── utils/                  # validators + helpers (snackbar/dialog)
│   └── widgets/                # CustomButton, CustomTextField, Loading, Empty
└── features/                   # كل feature في فولدر مستقل
    ├── auth/
    │   ├── data/
    │   │   ├── models/         # UserModel
    │   │   └── repositories/   # AuthRepository يكلم Laravel
    │   └── presentation/
    │       ├── providers/      # AuthProvider (ChangeNotifier)
    │       └── screens/        # Splash / Login / Register
    ├── home/
    ├── profile/
    └── settings/
```

---

## 🔌 ربط Laravel API

ربط الـ Backend في خطوة واحدة:

افتح `lib/core/constants/api_constants.dart` وعدّل:

```dart
static const String baseUrl = 'http://10.0.2.2:8000/api'; // Android emulator
// أو 'http://127.0.0.1:8000/api' للـ iOS simulator
// أو 'https://api.arenateam.com/api' للـ production
```

### أمثلة الـ URLs المحلية:
- **Android Emulator** → `http://10.0.2.2:8000/api`
- **iOS Simulator** → `http://127.0.0.1:8000/api`
- **جهاز حقيقي على نفس الشبكة** → `http://192.168.x.x:8000/api`

---

## 🧱 إزاي تضيف feature جديدة (مثال: Teams)

```bash
mkdir -p lib/features/teams/data/models
mkdir -p lib/features/teams/data/repositories
mkdir -p lib/features/teams/presentation/providers
mkdir -p lib/features/teams/presentation/screens
```

ثم:
1. اعمل `team_model.dart` بنفس شكل جدول `teams` من Laravel
2. اعمل `teams_repository.dart` يستخدم `DioClient` ويستدعي endpoints الـ Laravel
3. اعمل `teams_provider.dart` يدير state القائمة (loading/data/error)
4. اعمل الـ screen واربطه بالـ provider
5. ضيف الـ route في `lib/core/routing/routes.dart` و `app_router.dart`
6. سجّل الـ provider في `lib/main.dart` ضمن `MultiProvider`

---

## 🔐 ملاحظات الـ Authentication

التطبيق متوقع رد لارفيل بالشكل التالي (عدّل في `auth_repository.dart` لو شكل الرد عندك مختلف):

```json
{
  "data": {
    "user": { "id": 1, "name": "...", "email": "..." },
    "token": "1|abc..."
  }
}
```

التطبيق بيخزن الـ token في **flutter_secure_storage** ويبعته في كل request في الهيدر:
```
Authorization: Bearer {token}
```

---

## ✅ Packages المستخدمة

| Package | الغرض |
|--------|-------|
| `dio` | HTTP client |
| `pretty_dio_logger` | لوج للـ requests في debug |
| `provider` | إدارة الـ state |
| `go_router` | التنقل بين الصفحات |
| `flutter_secure_storage` | حفظ آمن للـ tokens |
| `shared_preferences` | إعدادات بسيطة |
| `google_fonts` | خط Cairo للعربي |
| `flutter_screenutil` | Responsive sizes |
| `connectivity_plus` | فحص الإنترنت |
| `cached_network_image` | كاش للصور |
| `image_picker` / `file_picker` | رفع ملفات |
| `permission_handler` | إذن الكاميرا/الميديا |
| `intl` | تنسيق التواريخ والأرقام |

---

## 📱 الخطوات الجاية لما يجيلك ملخص لارفيل

1. حدّث `UserModel` بالحقول الفعلية من جدول `users`
2. عدّل endpoints في `api_constants.dart` بناءً على الملخص
3. لكل جدول في قاعدة البيانات → اعمل feature جديدة بالخطوات اللي فوق
4. عدّل `auth_repository.dart` بناءً على شكل response لارفيل الفعلي
5. ضيف الـ FCM token endpoint لو في إشعارات

---

## 🐛 لو حصل خطأ

- **"Failed host lookup"** → غيّر الـ baseUrl للـ IP المناسب
- **CORS error** → ده على لارفيل نفسه - تأكد من `cors.php`
- **401 Unauthorized** → الـ token غلط أو expired
- **422** → validation error - شوف `error.validationErrors`
