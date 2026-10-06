import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/coupon_uses.dart';

import 'helpers/strip_comments.dart';

/// **صفرُ `maxUses` يَعني «بلا حدّ» — وثلاثةُ أسطحٍ قالت ثلاثةَ أشياءَ.**
///
/// الخادمُ: `if (maxUses > 0 && uses >= maxUses) return "exhausted";` فصفرٌ
/// = لا سقفَ إطلاقاً. ومحرِّرُ التطبيقِ كان يَبتلعُ «١٠» إلى صفرٍ (فيَفتحُ
/// الكوبونَ)، وبطاقتُه تَطبعُ «من 0» (فيُقرأُ «نَفِد»)، وجدولُ اللوحةِ عُرفُه
/// أنّ «بلا حدّ» رقمٌ كبيرٌ فيَرسمُ شريطاً **ممتلئاً** لكوبونٍ مفتوح.
String _code(String path) => stripComments(File(path).readAsStringSync());

/// اقتطاعُ كتلةِ الحالاتِ: من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس —
/// `indexOf('[')` يَلتقطُ قوسَ **تعليقِ النوعِ** لا بدايةَ المصفوفة.
List<List<Object?>> _sharedCases() {
  final src =
      File('admin_panel/src/utils/couponUses.test.ts').readAsStringSync();
  final a = src.indexOf('// ⟦CASES⟧');
  final b = src.indexOf('// ⟦/CASES⟧');
  if (a < 0 || b < 0 || b <= a) {
    throw StateError('علامتا كتلةِ الحالاتِ مفقودتانِ من فحصِ الـTS');
  }
  final block = src.substring(a, b);
  final end = block.lastIndexOf(']');
  if (end < 0) throw StateError('لا قوسَ إغلاقٍ في كتلةِ الحالات');
  var depth = 0;
  var start = -1;
  for (var i = end; i >= 0; i--) {
    if (block[i] == ']') depth++;
    if (block[i] == '[') {
      depth--;
      if (depth == 0) {
        start = i;
        break;
      }
    }
  }
  if (start < 0) throw StateError('تعذّرَ موازنةُ أقواسِ كتلةِ الحالات');
  var json = block.substring(start, end + 1);
  json = json.replaceAll("'", '"');
  // `undefined` ليس JSON — وهو نفسُ غيابِ الحقلِ، فيُقرأُ `null`.
  json = json.replaceAll(RegExp(r'\bundefined\b'), 'null');
  json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
  return (jsonDecode(json) as List<dynamic>)
      .map((r) => (r as List<dynamic>).cast<Object?>())
      .toList();
}

void main() {
  const rule = 'lib/utils/coupon_uses.dart';
  const mirror = 'admin_panel/src/utils/couponUses.ts';
  const flutterScreen = 'lib/screens/admin/admin_coupons_screen.dart';
  const panelPage = 'admin_panel/src/pages/Marketing.tsx';

  group('صفرُ maxUses = بلا حدّ', () {
    test('(أ) الجدولُ المشترَكُ مع الـTypeScript — حالةً حالةً', () {
      final cases = _sharedCases();
      expect(cases.length, greaterThanOrEqualTo(12),
          reason: 'كتلةُ الحالاتِ انهارت — اقتطاعٌ فاشلٌ لا جدولٌ قصير');
      // **أصنافٌ لا عدد** (درسُ `catalog_number`): الحدُّ وحدَه لا يَكشفُ ضياعَ
      // صنفٍ كامل، فتُشدُّ الأصنافُ التي وُجد الجدولُ لها.
      bool anyMax(bool Function(Object?) p) => cases.any((r) => p(r[1]));
      expect(anyMax((m) => m == 0), isTrue, reason: 'لا حالةَ بسقفٍ صفريّ');
      expect(anyMax((m) => m == null), isTrue, reason: 'لا حالةَ بسقفٍ غائب');
      expect(anyMax((m) => m is String && num.tryParse(m) == null), isTrue,
          reason: 'لا حالةَ بسقفٍ غيرِ رقميّ');
      expect(anyMax((m) => m is num && m < 0), isTrue,
          reason: 'لا حالةَ بسقفٍ سالب');
      expect(cases.any((r) => r[3] == true), isTrue,
          reason: 'لا حالةَ نافدةٍ — وهي نصفُ القاعدة');
      expect(anyMax((m) => m is num && m >= 10000), isTrue,
          reason: 'لا حالةَ بسقفٍ كبير — وهي ما يَنقضُ عُرفَ «> 9999»');

      for (final r in cases) {
        final uses = r[0];
        final max = r[1];
        final l = 'uses=${jsonEncode(uses)} max=${jsonEncode(max)}';
        expect(couponIsUnlimited(max), r[2], reason: 'unlimited $l');
        expect(couponIsExhausted(uses, max), r[3], reason: 'exhausted $l');
        final p = couponUsesProgress(uses, max);
        if (r[4] == null) {
          expect(p, isNull, reason: 'progress $l');
        } else {
          expect(p, closeTo((r[4] as num).toDouble(), 1e-9),
              reason: 'progress $l');
        }
      }
    });

    test('(ب) النصُّ يَقولُ «بلا حدّ» بالكلماتِ لا برقمٍ صفريّ', () {
      expect(couponUsesLabel(5, 0), 'الاستخدام: 5 (بلا حدّ)');
      expect(couponUsesLabel(5, 20), 'الاستخدام: 5 من 20');
      // «من 0» هي الصياغةُ التي كانت تُقرأُ «نَفِد»
      expect(couponUsesLabel(5, 0).contains('من 0'), isFalse);
    });

    test('(ج) السطحانِ يُنادِيانِ القاعدةَ ولا نسخةَ إنلاين', () {
      final f = _code(flutterScreen);
      final t = _code(panelPage);
      // شكلُ النداءِ لا حضورُ الاسم (درسُ `packageFormErrorX`).
      for (final call in ['couponUsesProgress', 'couponUsesLabel']) {
        expect(RegExp('\\b$call\\s*\\(').hasMatch(f), isTrue,
            reason: '$flutterScreen لا يُنادي $call');
      }
      for (final call in [
        'couponUsesProgress',
        'couponMaxUsesLabel',
        'couponIsUnlimited',
      ]) {
        expect(RegExp('\\b$call\\s*\\(').hasMatch(t), isTrue,
            reason: '$panelPage لا يُنادي $call');
      }
      // النسخُ الإنلاين التي كانت
      expect(f.contains("data['uses'] ?? 0} من"), isFalse,
          reason: 'نصُّ «من maxUses» الإنلاين عادَ');
      expect(f.contains("(data['maxUses'] ?? 1) > 0 ?"), isFalse,
          reason: 'حسابُ الشريطِ الإنلاين عادَ');
      expect(t.contains('> 9999'), isFalse,
          reason: 'عُرفُ «> 9999» عادَ — وهو يُخالِفُ الخادمَ في الجهتَين');
      // مضادّةٌ: العبارةُ ما زالت في النصِّ الخامِّ (تعليقي يَشرحُ إزالتَها)،
      // فتجريدٌ مُفرِطٌ لا يُجوِّفُ الفحصَ.
      expect(File(panelPage).readAsStringSync(), contains('> 9999'),
          reason: 'شرحُ القرارِ زالَ من الملفّ — فالفحصُ بلا ما يُميّزُه');
      expect(t.contains('coupon.uses / coupon.maxUses'), isFalse,
          reason: 'القسمةُ على صفرٍ عادت (Infinity ⇒ شريطٌ ممتلئ)');
    });

    test('(د) المحرِّرانِ: الفراغُ قرارٌ والخطأُ يُرفَض', () {
      final f = _code(flutterScreen);
      expect(f.contains("int.tryParse(maxUsesCtrl.text) ?? 0"), isFalse,
          reason: 'الابتلاعُ عادَ: «١٠» تَصيرُ كوبوناً بلا حدّ');
      expect(RegExp(r'optionalInt\(\s*maxUsesCtrl\.text').hasMatch(f), isTrue,
          reason: 'الحدُّ الأقصى لا يَمُرُّ بالقاعدة');
      expect(f, contains('maxUsesVal == null'),
          reason: 'لا رفضَ لقيمةٍ غيرِ صالحة');
      // الأرقامُ العربيّةُ في قيمةِ الخصمِ كانت تُرفَضُ صامتةً
      expect(RegExp(r'positiveNum\(valueCtrl\.text\)').hasMatch(f), isTrue,
          reason: 'قيمةُ الخصمِ لا تُطبَّعُ — «٣٥» تُرفَضُ بحقلٍ أحمرَ بلا سبب');
      // والقرارُ مُعلَنٌ للمالكِ في السطحَين بالنصِّ نفسِه
      for (final src in [f, _code(panelPage)]) {
        expect(src, contains('0 أو فارغ = بلا حدّ'),
            reason: 'القرارُ غيرُ مُعلَنٍ في أحدِ المحرِّرَين');
      }
    });

    test('(هـ) المرآةُ تُصدِّرُ كلَّ ما يُصدِّرُه الأصل', () {
      final m = _code(mirror);
      for (final n in [
        'couponMaxUses',
        'couponUses',
        'couponIsUnlimited',
        'couponIsExhausted',
        'couponUsesProgress',
      ]) {
        expect(_code(rule), contains(n), reason: 'الأصلُ فقدَ $n');
        expect(m, contains('export function $n'), reason: 'المرآةُ فقدَت $n');
      }
    });

    test('(و) شاهدُ التعليلِ: شرطُ الخادمِ ما زال قائماً', () {
      final c = _code('functions/coupons.js');
      expect(c, contains('if (maxUses > 0 && uses >= maxUses)'),
          reason: 'شرطُ الخادمِ تغيّرَ — فمعنى الصفرِ يُراجَعُ لا يُفترَض');
      expect(c, contains('Number(coupon.maxUses) || 0'),
          reason: 'تسامحُ قراءةِ الخادمِ تغيّرَ — والقاعدةُ مرآتُه');
      // مضادّةٌ: الاسمُ ما زال في النصِّ الخامِّ فتجريدٌ مُفرِطٌ لا يُجوِّفُ
      expect(File('functions/coupons.js').readAsStringSync(),
          contains('exhausted'));
    });
  });
}
