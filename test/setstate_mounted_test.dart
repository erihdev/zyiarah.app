// حارس دائم: **`setState` بعدَ `await` يُسبَقُ بفحصِ `mounted`.**
//
// بعد `dispose` يَصيرُ `_element` فارغاً، و`setState` تَبلغُ `_element!` —
// والتأكيداتُ (`assert`) التي تُعطي الرسالةَ المفهومةَ في التطوير **تُنزَعُ
// في الإصدار**، فما يَقعُ على جهازِ العميلةِ هو رميُ «Null check operator
// used on a null value». ويَلتقطُه `PlatformDispatcher.onError` في `main.dart`
// فيُسجَّلُ **قاتلاً** (`fatal: !isFontMiss`) — أي أنّه يَظهرُ انهياراً في
// Crashlytics وفي إحصاءاتِ المتجرَين.
//
// **والقاعدةُ عُرفُ المستودعِ أصلاً**: من ١٩٢ موضعاً، ١٧٨ تَفحصُ. والمكشوفُ
// كان ثلاثةَ عشَرَ، **سبعةٌ منها الفحصُ فيها مكتوبٌ وفي الجهةِ الخطأ**: الكاتبُ
// حَرسَ `ScaffoldMessenger` (وهو يَرمي كذلك على ودجةٍ زائلة) و`setState`
// فوقَه بسطرٍ بلا حَرس — فالحارسُ لا يَعملُ أبداً لأنّ ما قبلَه يَرمي أوّلاً.
// وستّةٌ منها على **شاشةِ الدفع**: العميلةُ تَضغطُ «ادفعي» ثمّ تَرجعُ أثناءَ
// كتابةِ الطلب، فيَقعُ الانهيارُ على أهمِّ شاشةٍ في التطبيق.
//
// والعلاجُ أصغرُ ما يَكفي: `if (mounted) setState(...)` — فكلُّ ما يَلي
// يَبقى يَعملُ كما كان، ولا يَتغيّرُ شيءٌ على المسارِ السليم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String p) {
  final s = File(p).readAsStringSync();
  final out = s.split('');
  var i = 0;
  while (i < s.length) {
    if (s[i] == '/' && i + 1 < s.length && (s[i + 1] == '/' || s[i + 1] == '*')) {
      final block = s[i + 1] == '*';
      var j = block ? s.indexOf('*/', i + 2) : s.indexOf('\n', i);
      j = j < 0 ? s.length : (block ? j + 2 : j);
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else {
      i++;
    }
  }
  return out.join();
}

/// مواضعُ تَعودُ إلى **هذه الشاشةِ نفسِها** بعد مُنتقٍ أو شاشةٍ مدفوعة، فهي
/// مُركَّبةٌ بالبناء: ما يُنتظَرُ هو ما يَرجعُ إليها، فلا تَكونُ قد زالت.
/// (المفتاحُ ملفٌّ وترتيبٌ لا رقمُ سطر — تعديلٌ أعلى الملفِّ لا يُسقطُ الحارس.)
const Map<String, int> _returnsHere = {
  // `Navigator.push(_StoreTamaraWebView)` — الرجوعُ منها إلى هذه الشاشة.
  'lib/screens/store_payment_screen.dart': 1,
  // `showTimePicker` ثمّ ضبطُ الموعد.
  'lib/screens/admin/admin_broadcast_screen.dart': 1,
  // `showDatePicker` ثمّ إضافةُ يومِ تعطيل.
  'lib/screens/admin/admin_zone_schedule_editor.dart': 1,
};

void main() {
  test('كلُّ setState بعدَ await مسبوقٌ بفحصِ mounted', () {
    final offenders = <String, int>{};
    var examined = 0;
    for (final f in [
      ...Directory('lib/screens').listSync(recursive: true).whereType<File>(),
      ...Directory('lib/widgets').listSync(recursive: true).whereType<File>(),
    ].where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll(r'\', '/');
      final s = _code(p);
      for (final m in RegExp(r'\bsetState\s*\(').allMatches(s)) {
        // أقربُ بدايةِ جسمٍ غيرِ متزامنٍ قبلَه
        final a = s.lastIndexOf('async {', m.start);
        final b = s.lastIndexOf('async =>', m.start);
        final start = a > b ? a : b;
        if (start < 0) continue;
        var seg = s.substring(start, m.start);
        // لا نَعبُرُ خارجَ الدالّة
        final out = seg.lastIndexOf('\n  }');
        if (out >= 0) seg = seg.substring(out + 1);
        if (!seg.contains('await')) continue;
        examined++;
        if (seg.substring(seg.lastIndexOf('await')).contains('mounted')) continue;
        offenders[p] = (offenders[p] ?? 0) + 1;
      }
    }
    // أرضيّة: كاشفٌ يَنحلُّ يَمرُّ أخضرَ أجوفَ. (١٩٢ اليوم.)
    expect(examined, greaterThanOrEqualTo(150),
        reason: 'انهارَ كاشفُ setState — فحصٌ لا يَرى شيئاً ليس فحصاً');
    // المجموعةُ كاملةً لا عتبةً عدديّة: موضعٌ جديدٌ يُراجَعُ بسببِه.
    expect(offenders, _returnsHere,
        reason: '\n\n`setState` بعدَ `await` بلا فحصِ `mounted`: بعد `dispose`\n'
            'يَرمي في الإصدارِ (التأكيداتُ مَنزوعةٌ هناك) ويُسجَّلُ انهياراً\n'
            'قاتلاً. أضِفْ `if (mounted)` — أو أدخِلْ الموضعَ في `_returnsHere`\n'
            'بسببٍ مكتوبٍ إن كان المُنتظَرُ يَرجعُ إلى هذه الشاشةِ نفسِها.\n');
  });

  test('وشاشةُ الدفعِ بعينِها محروسةٌ — ستّةُ مواضعَ كانت فيها', () {
    // أُفرِدت لأنّها أهمُّ شاشةٍ: الانهيارُ هنا أثناءَ كتابةِ الطلبِ يَقعُ
    // بين ضغطِ «ادفعي» وفتحِ بوّابةِ الدفع.
    final s = _code('lib/screens/payment_summary_screen.dart');
    expect(RegExp(r'if \(mounted\) setState\(').allMatches(s).length,
        greaterThanOrEqualTo(7),
        reason: 'زالَ الحَرسُ عن شاشةِ الدفع');
  });

  test('والفحصُ يَسبقُ ما يَحرُسُه — لا يَليه', () {
    // هذا هو العطلُ بعينِه: `setState` ثمّ `if (mounted) ScaffoldMessenger…`.
    // الحارسُ مكتوبٌ ولا يَعملُ، لأنّ السطرَ فوقَه يَرمي أوّلاً.
    final bad = <String>[];
    for (final f in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll(r'\', '/');
      final lines = _code(p).split('\n');
      for (var i = 0; i + 1 < lines.length; i++) {
        final cur = lines[i].trim();
        if (!cur.startsWith('setState(')) continue;
        final next = lines[i + 1].trim();
        if (next.startsWith('if (mounted)') || next.startsWith('if (!mounted)')) {
          bad.add('$p:${i + 1}  ←  $cur');
        }
      }
    }
    expect(bad, isEmpty,
        reason: '\n\nفحصُ `mounted` تحتَ `setState` مباشرةً: فهو يَحرُسُ السطرَ\n'
            'التالي ولا يَحرُسُ نفسَه، و`setState` يَرمي قبلَ أن يُقرَأ.\n'
            '  • ${bad.join('\n  • ')}\n');
  });
}
