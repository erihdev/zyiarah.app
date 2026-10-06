# زيارة — Zyiarah

منصّةُ حجزِ خدماتٍ منزليّةٍ (تنظيف، كنب وسجّاد، مكيّفات، مقصورةُ سيّارة، عاملاتُ
مناسبات، ومتجرُ موادّ) لمنطقةِ جازان. ثلاثةُ أسطحٍ على خادمٍ واحد:

| السطح | المجلّد | التقنية |
|---|---|---|
| تطبيقُ العميلةِ والسائقِ والإدارة | `lib/` | Flutter (iOS + Android) |
| لوحةُ الإدارةِ على الويب | `admin_panel/` | React 19 + TypeScript (Vite) |
| الخادم | `functions/` | Cloud Functions, Node 22 |
| الصفحةُ العامّةُ (`zyiarah.com`) | `landing_page/` | HTML ثابت |

ثلاثةُ أدوارٍ — **عميلة**، **سائق**، **إدارة** (بأربعةِ أدوارٍ فرعيّة:
`super_admin`، `orders_manager`، `accountant_admin`، `marketing_admin`) —
و`firestore.rules` هي ما يَفصلُ بينها فعلاً، لا الواجهة.

## الأوامر

```bash
# التطبيق
flutter pub get && flutter analyze && flutter test
flutter build web --release        # تصريفُ التطبيقِ كلِّه بلا Android SDK

# اللوحة
cd admin_panel && npm ci && npm run lint && npm test && npm run build

# الخادم
cd functions && npm ci && npm run lint && npm test
# فحوصُ المُحاكي تُشغَّل من جذرِ المستودع (حيث firebase.json)، وتَلزمُها JDK 21+
npx firebase-tools@15 emulators:exec --only firestore --project demo-zyiarah-rules \
  'npm --prefix functions run test:emulator'
```

`admin_panel/src/services/firebase.ts` مُستثنى من git ويُولَّد بـ
`admin_panel/scripts/gen_firebase_config.mjs` من `lib/firebase_options.dart`.

## قبلَ أن تُعدِّل شيئاً

**اقرأ [`CLAUDE.md`](CLAUDE.md).** ليس دليلَ أسلوب: هو سجلُّ القراراتِ وما
تَعلّمناه من كلِّ عطلٍ وُجد — لماذا لا عودةَ للدفعِ عند التسليمِ ولا Tabby ولا
قبول/رفضٍ من السائق، ولماذا تَسكنُ الضريبةُ ومبالغُ الاسترداد وساعاتُ الطلبِ في
وحدةٍ واحدةٍ لكلِّ جهة، وأينَ تُخفي Firestore أسنانَها. وكلُّ قرارٍ فيه مشدودٌ
بفحصٍ في `test/` أو `functions/test/`.

ومنه ثلاثُ قواعدَ تُغني عن الكثير:

- **الفحوصُ تَحرُسُ قراراتٍ لا شفرةً.** حين يَسقطُ فحصٌ، السؤالُ هو «أيُّ قرارٍ
  أنقُضُه؟» لا «كيف أُخرِسُه؟». واقرأ تعليقَ الفحصِ قبلَ تعديلِ ما يَحرُسُه.
- **القاعدةُ تَسكنُ مرّةً واحدةً لكلِّ جهة**، ومرايا Dart↔TypeScript تُشَدُّ
  بجدولِ حالاتٍ مشترَكٍ يَقرؤه الطرفان — لا بتعليقٍ يَقولُ «مرآة».
- **ما لا يُعرَفُ إلّا بالتشغيلِ لا يُدوَّنُ في وثيقة**، وما يُمكِنُ اشتقاقُه
  يُشتَقّ. وثيقةٌ تَذكرُ رقماً من الشفرةِ تَبيت.

## النشر

أربعةُ أهدافٍ تَنشرُ تلقائيّاً على `main` (الدوالّ، اللوحة، فهارسُ Firestore،
الصفحةُ العامّة)، و`.github/workflows/deploy_drift.yml` يُنبّهُ يوميّاً إن بقيت
شفرةٌ مدمَجةٌ غيرَ منشورة — **ولا يَنشرُ بنفسِه**. وإصدارُ iOS/Android عبر
Codemagic. التفاصيلُ والمَخرَجُ اليدويُّ في
[`production_deployment_guide.md`](production_deployment_guide.md).

**ولا يُنشَرُ من الأتمتةِ إطلاقاً:** `firestore.rules` و`storage.rules` — نشرُهما
مقرونٌ بانتشارِ الإصدارِ (حجزُ STAGE-C)، وهو قرارُ المالكِ بيدِه.

## الملكيّة

تطبيقٌ تجاريٌّ لمؤسسةِ معاذ يحي محمد المالكي، طوّرَته **إرث** —
انظر [`handover_document.md`](handover_document.md).
