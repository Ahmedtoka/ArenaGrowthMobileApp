# البرومبت لإرساله للـ Claude اللي عنده أكسيس لسيستم لارفيل

انسخ النص اللي تحت بالظبط وابعتهولـ Claude التاني (اللي عنده فولدر لارفيل مفتوح).

---

```
عندي سيستم Laravel كامل وعاوز أحوّله لتطبيق موبايل بـ Flutter.
محتاج منك ملخص تقني شامل ومنظّم يكون جاهز أديه لـ Claude تاني علشان يبدأ يبني الـ Flutter app.
ابعتلي المعلومات دي بالترتيب واحفظها في ملف Markdown اسمه LARAVEL_SUMMARY.md:

## 1) نظرة عامة على السيستم
- اسم المشروع والغرض منه باختصار
- نسخة Laravel + نسخة PHP
- الـ packages الأساسية المستخدمة (من composer.json)
- نوع قاعدة البيانات (MySQL/PostgreSQL/...)

## 2) قاعدة البيانات (Database Schema)
- كل الجداول مع الأعمدة وأنواع البيانات
- العلاقات بين الجداول (Foreign Keys / Relationships)
- اطلع كل الـ Migrations الموجودة في database/migrations
- اطلع كل الـ Models في app/Models مع علاقاتها (hasMany, belongsTo, ...)
- لو في Seeders، اعرض شكل البيانات المتوقع

## 3) الـ Authentication
- نوع المصادقة المستخدمة (Sanctum / Passport / JWT / Session)
- هل في Roles & Permissions؟ (Spatie أو غيرها) - اعرض الأدوار الموجودة
- خطوات تسجيل الدخول والتسجيل والـ password reset
- الـ Middleware المستخدمة على الـ routes

## 4) الـ API Endpoints (الجزء الأهم!)
- كل الـ routes الموجودة في routes/api.php و routes/web.php
- لكل endpoint اعمل جدول بـ:
  * الـ HTTP method (GET/POST/PUT/DELETE)
  * الـ URL الكامل
  * الـ Controller والـ method
  * الـ parameters المطلوبة (من Request validation rules)
  * شكل الـ Response (JSON structure مع مثال حقيقي)
  * الـ authentication المطلوبة (نعم/لا)
  * الـ middleware اللي بتشتغل عليه
  * الـ roles/permissions المطلوبة لو في

## 5) الـ Business Logic
- أهم الـ Services والـ Repositories والـ Actions
- الـ Jobs والـ Queues
- الـ Notifications والـ Mail
- الـ Events والـ Listeners
- أي logic معقد في الـ Controllers أحب أعرفه

## 6) الـ File Uploads
- إزاي بيتعامل مع الملفات والصور (Storage facade / Spatie Media Library / غيرها)
- الـ Storage disk المستخدم (local/s3/...)
- شكل الـ URLs اللي بترجع للملفات
- حجم/نوع الملفات المسموح بها

## 7) المميزات الأساسية (Features)
- اعمل ليستة بكل feature في السيستم وشرح بسيط لكل واحدة
- مين بيستخدم كل feature (admin/user/guest)
- الحالة (شغّال / تحت التطوير)

## 8) Configuration & Environment
- محتوى .env.example (من غير القيم الحساسة)
- الإعدادات المهمة في config/ (خصوصاً auth, services, mail)

## 9) أمثلة Real Responses
- ادي Sample JSON response لأهم 10 endpoints (نسخ من Postman أو من اختبار فعلي)
- علشان أبني الـ Models في Flutter بنفس البنية بالظبط
- ركّز على الحقول الـ nullable وأنواع البيانات الدقيقة

## 10) ملاحظات للموبايل
- في أي endpoints محتاجة تتعدل علشان تشتغل مع موبايل بشكل أحسن؟
- في Push Notifications؟ (FCM/APNS) - لو لا، نحتاج نضيف
- في WebSockets / Real-time؟ (Pusher/Laravel Echo/Reverb)
- في Payment Gateway؟ (Stripe/Paymob/...)
- في رفع صور/فيديوهات بطريقة معينة؟
- في تنسيق تاريخ معين أو timezone معين بيستخدمه السيستم؟

## 11) Pagination & Filtering
- شكل الـ pagination response (Laravel default / custom)
- إزاي بيشتغل الـ filtering والـ sorting والـ search

## 12) أخطاء معروفة / حاجات لازم تتنبه ليها
- أي API response شكله غريب أو غير قياسي
- أي endpoint بياخد وقت كبير
- أي logic لازم يحصل client-side

---

مهم جداً:
1. اطلع الملفات الفعلية ومتعتمدش على افتراضات
2. لو في حاجة مش متأكد منها قولي
3. احفظ النتيجة في ملف LARAVEL_SUMMARY.md منظّم بالـ headers
4. لو الملخص طويل، قسّمه على ملفات: API_ENDPOINTS.md، DATABASE_SCHEMA.md، AUTH.md
```

---

## بعد ما يجيك الملخص:

ابعت الملف (أو الملفات) لـ Claude هنا، وقوله:

> "ده ملخص سيستم لارفيل بتاعي. ابدأ تطبق الـ features على Flutter project اللي عندنا، واحدة واحدة بالأولوية: Auth الأول، بعدين [أهم feature عندك]، بعدين باقي الـ features."
