// حارس: **زرٌّ يُضغط فلا يحدث شيء ولا تُقال كلمة.**
//
// عائلةٌ تكرّرت الليلة ثلاث مرّات، كلُّها `return;` عارٍ بعد فحصٍ فاشل:
//
//   * زرُّ نسخ كود الإحالة (`profile_screen`): `if (_referralCode == null)
//     return;` — والكبسولةُ فوقه تعرض «--------» التي تقرأ ككودٍ مُعتَّم.
//   * «تم الإنجاز» في لوحة السائق: `if (data == null) return;` — الطلبُ
//     حُذف أو أُلغي من الإدارة بينما بطاقتُه على جهاز السائق، فيضغط ويضغط
//     والزرُّ يعود قابلاً للضغط في `finally` بلا أيّ أثر.
//   * «فتح PDF» و«مشاركة» في سجلّ الفواتير: `if (url == null) return;`
//     والأزرارُ تظهر على `status == 'ready'`، فوثيقةٌ «جاهزة» بلا رابطٍ
//     تعطي زرَّين ميّتَين.
//
// القاعدةُ ليست «لا return عارٍ» — كثيرٌ منها صحيح (إلغاءُ حوار، ودجةٌ
// مُفكَّكة، حقلٌ فارغ، نداءٌ جارٍ أصلاً). القاعدةُ أنّ **هذه المواضع بعينها**
// تقول شيئاً، لأنّ كلًّا منها نهايةُ ضغطةٍ قصدها المستخدم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// هل قيلت كلمةٌ خلال [window] محرفاً بعد الموضع؟
bool _speaks(String src, int at, {int window = 700}) {
  final end = (at + window).clamp(0, src.length);
  final seg = src.substring(at, end);
  return seg.contains('ScaffoldMessenger') ||
      seg.contains('_snack(') ||
      seg.contains('showDialog');
}

void main() {
  test('لوحةُ السائق: طلبٌ لم يعد موجوداً يُقال', () {
    final src = File('lib/screens/driver_dashboard.dart').readAsStringSync();
    final at = src.indexOf('if (data == null) {');
    expect(at, greaterThan(0),
        reason: 'عاد `if (data == null) return;` العاري — ضغطةٌ بلا أثرٍ ولا كلمة');
    expect(_speaks(src, at), isTrue);
    expect(src.contains('لم يعد هذا الطلب موجوداً'), isTrue);
  });

  test('سجلُّ الفواتير: «جاهزة بلا رابط» تُقال في الفتح والمشاركة معاً', () {
    final src = File('lib/screens/admin/admin_invoices_screen.dart').readAsStringSync();
    var n = 0;
    for (final m in RegExp(r'if \(url == null\) \{').allMatches(src)) {
      n++;
      expect(_speaks(src, m.start, window: 260), isTrue,
          reason: 'فرعٌ صامتٌ عند ${m.start}');
    }
    expect(n, 2, reason: 'المسارانِ (فتح ومشاركة) كلاهما يحتاج الرسالة');
    // وفحصُ «جارٍ أصلاً» يبقى صامتاً بحقّ: لا كلامَ على ضغطةٍ مكرّرة.
    expect(src.contains('if (_busy.contains(e.docId)) return;'), isTrue);
  });

  test('الملفّ الشخصيّ: كود الإحالة الغائب يُقال وتُتاح الإعادة', () {
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();
    final at = src.indexOf('if (_referralCode == null) {');
    expect(at, greaterThan(0));
    expect(_speaks(src, at), isTrue);
    expect(src.substring(at, at + 700).contains('_loadReferralCode'), isTrue,
        reason: 'رسالةٌ بلا إعادةِ محاولةٍ تترك العميلةَ عالقة');
  });

  test('والصامتُ بحقٍّ يبقى صامتاً (لا نُغرق المستخدمَ برسائل)', () {
    // أمثلةٌ مقصودة: إلغاءُ حوارٍ، ودجةٌ مُفكَّكة، ونصٌّ فارغ.
    final driver = File('lib/screens/driver_dashboard.dart').readAsStringSync();
    expect(driver.contains('if (confirm != true) return;'), isTrue);
    final support = File('lib/screens/support_screen.dart').readAsStringSync();
    expect(support.contains('if (text.isEmpty) return;'), isTrue);
  });
}
