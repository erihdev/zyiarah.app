# دليل الإصدار والنشر — زيارة

> **آخر تحديث: 2026-09-11.** هذا الملف كان يصف مساراً يدويّاً بالكامل (بناء من الجهاز
> ثم Archive في Xcode) ويذكر إصدار `1.0.0+1`. الواقع تغيّر: النشر آليّ عبر Codemagic،
> والإصدار الحالي في `pubspec.yaml`. المسار اليدوي أدناه محفوظ للطوارئ لا للاستعمال المعتاد.

## 1. المسار المعتاد — آليّ

**كل دمج إلى `main` يُطلق البناء والنشر تلقائياً على المنصّتين:**

| المنصّة | الوجهة | الملف |
|---|---|---|
| iOS | TestFlight | `codemagic.yaml` ← `ios-release` |
| Android | Google Play — مسار **الاختبار الداخلي** | `codemagic.yaml` ← `android-release` |

النشر للجمهور (App Store / Play production) يبقى **قراراً يدويّاً** من لوحتَي المتجرين.

رقم البناء يتزايد تلقائياً في Codemagic من عدّاد المتجر — لا تُعدّله في `pubspec.yaml`.
ما تُعدّله يدويّاً هو رقم الإصدار وحده (`1.2.47` في `1.2.47+246`).

**لتخطّي البناء** (تغييرات وثائق أو قواعد لا تمسّ التطبيق): أضف `[skip ci]` إلى رسالة
الالتزام. يتخطّى المنصّتين معاً.

### ما يجب أن يكون مُعدّاً في Codemagic

| المجموعة | تحتوي | تخصّ |
|---|---|---|
| `appstore_credentials` | مفاتيح App Store Connect API + `MAPBOX_TOKEN` | iOS |
| `android_credentials` | `ANDROID_KEYSTORE_BASE64`، كلمات مرور المفتاح، `MAPBOX_TOKEN` | Android |
| `payment_keys` | مفاتيح ميسر وتابي وسامسونج باي القابلة للنشر | كلتاهما |
| `google_play` | `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Android |
| تكامل `Zyiarah Key` | مفتاح App Store Connect | iOS |

> ⚠️ **مجموعة `google_play` هي الشرط الوحيد الناقص المعروف.** بلا حساب خدمة من
> Play Console تسقط مهمّة أندرويد عند خطوة النشر — سقوط ظاهر في السجلّ لا صامت.

## 2. حرّاس ما قبل الدمج

`.github/workflows/ci.yml` يشغّل أربع مهامّ على كل طلب دمج، ولا يُدمج شيء وهي حمراء:

| المهمّة | ما تفحصه |
|---|---|
| Flutter Analyze | `flutter analyze --no-fatal-infos` |
| Flutter Test | ٣١٠ فحصاً |
| Cloud Functions Tests | lint + ٤٩ فحص وحدة + ٢٩ فحص محاكي (قواعد، أدوار، محفظة) |
| Admin Panel Build | lint + Vitest + `tsc -b` + بناء |

## 3. اختبار الدخان بعد وصول البناء

على جهاز حقيقي، من TestFlight أو مسار الاختبار الداخلي:

- **الرقم الاختباري** `+966599363888` يتخطّى الـ OTP — يلزم مراجعي أبل للدخول.
- **تسجيل الدخول** والإشعارات — مسارات أصلية (Firebase Auth/Messaging) لا يغطّيها أي
  اختبار آليّ في المستودع، فهي أوّل ما يُجرَّب بعد أي ترقية لحزم Firebase.
- **بوّابة الدفع**: أكمل عملية وتأكّد من الوصول لشاشة «الفاتورة الضريبية».
- **الخريطة**: العلامات تظهر عند إحداثيات الداير/فيفاء.
- **حذف الحساب** من الملف الشخصي يعمل — متطلّب إلزامي من أبل.

## 4. مسار الطوارئ — يدويّ

يُستعمل حين تتعطّل Codemagic فقط.

```bash
flutter clean && flutter pub get
touch .env                      # أو ضع مفاتيحك القابلة للنشر
flutter build appbundle --release   # أندرويد → build/app/outputs/bundle/release/
flutter build ipa --release         # iOS (يتطلّب macOS + Xcode)
```

التوقيع محليّاً يقرأ `android/key.properties` (مُستثنى من git). لـ iOS: افتح
`ios/Runner.xcworkspace` ثم Product ← Archive ← Distribute App.

## 5. مساران لا يصلان المتاجر

لا تستعملهما ظنّاً أنهما ينشران:

- `.github/workflows/android_release.yml` — يبني AAB على وسوم `v*` **بلا نشر**.
- `distribute_android.bat` — يبني APK ويرفعه إلى **Firebase App Distribution**
  (مختبرون داخليون)، لا إلى Google Play.
