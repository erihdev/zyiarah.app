// حارس دائم: **نصُّ الشاشةِ يَصفُ الترتيبَ الذي تَفعلُه الشفرةُ فعلاً.**
//
// شاشتا الباقاتِ (الاشتراك، وعاملاتُ المناسبات) كانتا تَقولانِ للعميلة:
// «سيتم توجيه طلبك للإدارة للموافقة عليه **قبل توقيع العقد الإلكتروني**» —
// والترتيبُ معكوس. فاختيارُ الباقةِ يَدفعُ مباشرةً إلى
// `ZyiarahContractSigningScreen`، وهي تُنشئُ مستندَ العقدِ بـ`status:
// 'pending'` و`signedAt` — **أي أنّها تُوقّعُ أوّلاً** — ثمّ تُراجعُ الإدارةُ
// وتَكتبُ `approved_waiting_payment`، ثمّ تُسدَّدُ القيمةُ فيُفعَّلُ العقد.
//
// وهي عائلةُ «نصٌّ يَعِدُ بما لا تَفعلُه الشفرة» المسجَّلةُ هنا مرّاتٍ:
// «فريقنا في الطريق إليكِ» عن طلبٍ بلا سائق، و«الأسعار شاملة الضريبة» فوقَ
// أسعارٍ قبلَ الضريبة، و«سيتم نشر سياسة الخصوصية قريباً» على الرابطِ الذي
// يَفتحُه مُراجِعُ أبل. ولا مالَ فيها هنا، لكنّها تَصفُ للعميلةِ خطواتٍ
// تَفعلُها بترتيبٍ آخر — على شاشةِ دخولِ أغلى منتجٍ في التطبيق.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

const _packageScreens = [
  'lib/screens/subscription_plans_screen.dart',
  'lib/screens/event_worker_packages_screen.dart',
];

void main() {
  test('لا شاشةَ تَقولُ إنّ الاعتمادَ يَسبقُ التوقيع', () {
    for (final p in _packageScreens) {
      final s = _read(p);
      expect(s.contains('قبل توقيع العقد'), isFalse,
          reason: '$p: الاعتمادُ **بعدَ** التوقيعِ لا قبلَه — '
              'الشاشةُ تَصفُ ترتيباً لا يَحدث');
      // والنصُّ يَصفُ الترتيبَ الحقيقيّ: توقيعٌ ثمّ دفعٌ فتفعيل — **بلا
      // اعتماد** (قرار المالك 2026-10-24؛ وكان «ثمّ تعتمده الإدارة» خطوةً لا
      // تَقعُ: التوقيعُ يَنقلُ إلى الدفعِ مباشرةً).
      expect(s.contains('توقّعين العقد إلكترونيّاً'), isTrue,
          reason: '$p: زالَ وصفُ الترتيبِ الصحيح');
      expect(s.contains('ثمّ تُسدّدين فتتفعّل الباقة فوراً'), isTrue);
      expect(s.contains('تعتمده الإدارة'), isFalse,
          reason: '$p: عادت خطوةُ اعتمادٍ لا وجودَ لها');
    }
  });

  test('والترتيبُ الحقيقيُّ مأخوذٌ من الشفرةِ لا من الذاكرة', () {
    // (أ) شاشةُ التوقيعِ تُنشئُ العقدَ `pending` وتَختِمُ التوقيعَ معاً —
    //     فالتوقيعُ أوّلُ ما يَقعُ، والمراجعةُ بعدَه.
    final sign = _read('lib/screens/contract_signing_screen.dart');
    expect(sign.contains("'status': 'pending'"), isTrue,
        reason: 'لم يَعُدْ العقدُ يُنشَأُ pending — راجِعْ نصَّ الشاشتَين');
    expect(sign.contains("'signedAt'"), isTrue,
        reason: 'لم يَعُدْ التوقيعُ يُختَمُ عند الإنشاء');
    // (ب) **ولا اعتمادَ بعدَه** (قرار المالك 2026-10-24): شاشةُ الإدارةِ لا
    //     تَكتبُ انتقالَ الاعتماد، والتوقيعُ يَنقلُ إلى الدفعِ مباشرةً.
    final admin = _read('lib/screens/admin/admin_contracts_screen.dart');
    expect(admin.contains("'status': 'approved_waiting_payment'"), isFalse,
        reason: 'عادَ انتقالُ الاعتماد — فالنصُّ «ثمّ تُسدّدين» يُراجَع');
    expect(_read('lib/screens/contract_signing_screen.dart')
            .contains('PaymentSummaryScreen('),
        isTrue,
        reason: 'التوقيعُ لم يَعُدْ يَنقلُ إلى الدفع');
    // (ج) وشاشتا الباقاتِ تَدفعانِ إلى شاشةِ التوقيعِ مباشرةً، بلا خطوةِ
    //     اعتمادٍ بينهما — وهو ما يَجعلُ «قبل التوقيع» مستحيلاً أصلاً.
    for (final p in _packageScreens) {
      // **شكلُ النداءِ لا مجرَّدُ الاسم**: `contains` يُرضيه
      // `ZyiarahContractSigningScreenX` لأنّه يَحتويه — وهو فخُّ الاحتواءِ
      // المسجَّلُ هنا (`packageFormErrorX` أرضى `packageFormError`). قضمةٌ
      // أعادت التسميةَ مرَّت **خضراءَ** قبلَ هذا التضييق.
      expect(
          RegExp(r'\bZyiarahContractSigningScreen\s*\(').hasMatch(_read(p)),
          isTrue,
          reason: '$p: لم تَعُدْ تَدفعُ إلى التوقيعِ مباشرةً — '
              'راجِعْ النصَّ، فقد يَصيرُ الترتيبُ الآخرُ صحيحاً');
    }
  });
}
