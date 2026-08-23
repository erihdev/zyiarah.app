# خدمة عاملات المناسبات — نظام باقات مطابق لباقات الاشتراك

## المشكلة
خدمة "عاملات للمناسبات" حالياً حاسبة سعر حيّة (عدد عاملات × ساعات × سعر ساعة
المنطقة) تنتج طلباً مباشراً واحداً. المالك يريدها بنظام باقات ثابتة يصنعها
ويسمّيها ويتحكم في تفاصيلها من لوحة التحكم — **نفس نظام باقات الاشتراك بالضبط**،
بما في ذلك تدفّق توقيع العقد وجدولة الزيارات المتعددة.

## القرار
يحل نظام الباقات محل الحاسبة الحيّة بالكامل (لا خيار بديل). بعد اختيار الباقة:
توقيع عقد إلكتروني + جدولة عدد الزيارات المشمولة، تماماً كباقات الاشتراك.

## نموذج البيانات
مجموعة جديدة `event_worker_packages` — نسخة من `subscription_packages` بحقل
إضافي واحد:

```
title, subtitle, price (قبل الضريبة), visits, hours (لكل زيارة),
workers ⭐ (عدد العاملات لكل زيارة — الحقل الجديد), features[], isPremium, rank
```

العقد (`contracts/{id}`) يكتسب حقلين اختياريين عند الإنشاء من هذا المسار:
- `contract_kind: 'event_workers'` (غياب الحقل = سلوك اشتراك التنظيف الحالي، صفر تغيير)
- `workers: number`

كل زيارة مولَّدة لعقد من نوع `event_workers` تحمل:
```
service_meta: { kind: 'event_workers', workers, event_hours: hours }
```
هذه البنية **مدعومة فعلياً** في `ZyiarahServiceMetaView` (Flutter) و`serviceMeta.ts`
(لوحة الويب) من مسار الحاسبة القديم — فتُعرض تلقائياً في شاشات تفاصيل الطلب
للإدارة والسائق بلا أي كود واجهة جديد.

## إدارة الباقات — تكافؤ التطبيق ولوحة الويب
1. **Flutter**: `AdminEventWorkerPackagesScreen` — نسخة من
   `admin_subscriptions_screen.dart` تكتب على `event_worker_packages`، مع حقل
   "عدد العاملات" إضافي في نموذج الإضافة/التعديل. تُضاف لقائمة
   `admin_more_screen.dart` بجانب "باقات الاشتراك"، بنفس صلاحيات
   `['super_admin', 'marketing_admin']`.
2. **لوحة الويب**: تبويب جديد "باقات عاملات المناسبات" داخل `Contracts.tsx`
   (نفس الصفحة التي فيها تبويب "باقات الاشتراك" اليوم)، بنفس نمط CRUD.
3. **قاعدة Firestore** جديدة مطابقة حرفياً لقاعدة `subscription_packages`:
   `allow read: isLoggedIn(); allow write: isMarketingAdmin();`

## رحلة العميل
1. شاشة جديدة `EventWorkerPackagesScreen` — نسخة من `subscription_plans_screen.dart`:
   بطاقات باقات من `event_worker_packages` → اختيار باقة → نفس تقويم الإتاحة
   المشترك (`getHourlyAvailability` — السعة موزّعة على كل أنواع الخدمات
   تلقائياً، لا تعديل خادمي) → جدولة موعد لكل زيارة مشمولة → توقيع العقد.
2. `ZyiarahContractSigningScreen` يُعاد استخدامه كما هو + بارامترين اختياريين
   جديدين (`contractKind`, `workers`) يُمرَّران للعقد.
3. بلاطة "عاملات للمناسبات" في `client_dashboard.dart` تُشير للشاشة الجديدة
   بدل الحاسبة القديمة؛ العنوان الفرعي يُحدَّث ليعكس الباقات الجاهزة.
4. الدفع/المحفظة/الفاتورة/الاسترداد: بلا تعديل — تمر عبر مسار العقود الحالي
   حرفياً.

## التحقق الخادمي وتوليد الزيارات (functions/index.js)
- `_validateContractPlan`: تبحث في `event_worker_packages` بدل
  `subscription_packages` عندما `contract_kind === 'event_workers'`، وتضيف
  تحقق عدد العاملات (مطابقة عدد عاملات الباقة الحقيقية) فوق تحقق السعر/الزيارات
  الحالي — يغلق نفس ثغرة "تلاعب السعر عميلياً" للنوع الجديد.
- `generateSubscriptionVisits` و`_generateContractVisits`: تكتب `service_meta`
  فقط لعقود `event_workers`؛ توليد اشتراكات التنظيف يبقى حرفياً كما هو.
- كل ما عداه (تفعيل الدفع، الدفع بالمحفظة، إسناد السائقين، الإشعارات) كود
  مشترك بلا تعديل.

## خارج النطاق (يُترك عمداً)
`event_workers_details_screen.dart` **تُحذف** (ميتة فعلياً بعد تحويل البلاطة)
مع إزالة استيرادها من `client_dashboard.dart`. أما منطق `event_workers` في
`pricing.js`، وحقل `eventWorkerHourPrice` في مناطق الخدمة، وملفا الاختبار
القديمان (`test/event_workers_and_materials_test.dart`،
`functions/test/pricing.test.js`) — **تُترك بلا لمس**: معزولة وغير مؤذية، وإزالتها
تنظيف غير متعلق بهذه الميزة.

## الاختبارات
- Flutter: `flutter analyze` على كل ملف مُنشأ/معدَّل، واختبار مصدري (source-guard)
  جديد للتحقق من سلامة النموذج والحدود إن كان مناسباً.
- Functions: اختبار وحدة جديد لـ `_validateContractPlan` مع باقة `event_workers`
  (سعر مطابق، سعر متلاعَب به، عدد عاملات غير مطابق) — بجانب `npm test` الحالي.
- بوابة تكامل نهائية: `node --check`، `npm test` (functions)، `flutter analyze`،
  `flutter test`، `npm run build` (admin_panel) — كلها خضراء قبل الإعلان بالإنجاز.
