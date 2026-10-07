// حارس دائم: **شريحةُ حارسٍ تُحَدُّ بالبنيةِ التي تَقصدُها، لا بعدِّ أحرف.**
//
// هذا الفخُّ عضَّ في هذا المستودعِ تسعَ مرّاتٍ مسجَّلة، وفي كلِّ مرّةٍ كان
// العلاجُ موضعيّاً: شريحةُ ١٦٠٠ حرفٍ في حارسِ تحقّقِ السعرِ تَجاوزت فرعَها
// إلى شفرةٍ فيها `throw`، و`indexOf(']);')` في حارسِ COD تَجاوزَ قائمةَ
// السائقِ إلى فرعِ العميل، و`indexOf('}')` في حارسِ المخزَنِ توقّفَ عند قوسٍ
// داخلَ `match /banners/{file=**}`، و`indexOf('.get());')` في حارسِ نشاطِ
// الطلباتِ أبطلَه إلحاقُ `.timeout(...)` بالقراءةِ نفسِها، ونافذةُ ١٨٠ حرفٍ
// في حارسِ المهلاتِ أعمَته عن **تسعةَ عشرَ** موضعاً.
//
// وُسِعَ القياسُ على المستودعِ كلِّه (2026-10-07): أربعٌ وثلاثون شريحةً
// بعدِّ أحرف، منها إحدى عشرةَ مُرتكِزةً على **إعلانِ دالّة** — وهناك الحدُّ
// المقصودُ لا لبسَ فيه (أوّلُ إعلانٍ عُلويٍّ بعدَها). تسعٌ من الإحدى عشرةَ
// كانت مُخطِئةً بالقياس:
//
//   • `sweepUnassignedPaidOrders`: الشريحةُ ٣٢٠٠ والدالّةُ ٤٧٢١ ⇒ **٣٢٪
//     خارجَ النظر** — وفيها فحصٌ **يَعُدُّ** الدفعاتِ، فكان يُثبّتُ «دفعةٌ
//     إداريّةٌ واحدة» والدالّةُ تَحملُ موضعَين، ويَمرُّ أخضرَ لأنّه لا يَرى
//     الثاني. والأسوأُ أنّ حرسَ الموضعِ الثاني من التكرار
//     (`if (d.stranded_alerted === true) continue;`) لم يَشُدَّه فحصٌ في
//     المستودعِ كلِّه — وهو وحدَه ما يَمنعُ تنبيهاً ثانياً عن الطلبِ نفسِه.
//   • وثمانٍ **تَتجاوزُ** دوالَّها (من ٩١ حرفاً إلى ١٤١١)، فتَقرأُ شفرةَ
//     دالّةٍ أخرى وتَحكمُ بها. لم يَكن أثرُها عطلاً بعدُ — قِيسَ: لا مصطلحَ
//     مَحروساً في المُتجاوَز — لكنّها على بُعدِ تعديلٍ واحدٍ من نتيجةٍ كاذبة.
//
// والنطاقُ مقصورٌ على مِرساةِ **الدالّة** بقصد: بقيّةُ الشرائحِ تَرتكِزُ على
// ودجةٍ أو جملةٍ أو كتلةٍ، وحدُّها المقصودُ ليس واحداً بيّناً، فمنعُها
// سيَكونُ ضجيجاً يُدرَّبُ المراجعُ على تجاهلِه — وذاك أسوأُ من لا حارس.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كلُّ ملفّاتِ الفحصِ في الجهتَين — النطاقُ مُشتَقٌّ لا مكتوبٌ بيد.
List<File> _guardFiles() => [
      ...Directory('test').listSync(recursive: true).whereType<File>().where(
          (f) => f.path.endsWith('.dart')),
      ...Directory('functions/test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.js')),
    ];

/// شريحةٌ بعدِّ أحرفٍ: `X = SRC.substring(i, i + N)` أو `.slice(...)`.
final RegExp _fixedWindow = RegExp(
    r'(\w+)\s*=\s*(\w+)\.(?:substring|slice)\(\s*([A-Za-z_][\w.]*)\s*,'
    r'\s*\3\s*\+\s*(\d+)\s*\)');

/// آخرُ `anchor = SRC.indexOf(<literal>)` قبلَ الموضع — هو ما يُسمّي المقصود.
String? _anchorLiteral(String src, String anchor, int before) {
  String? lit;
  for (final m in RegExp('${RegExp.escape(anchor)}'
          r'\s*=\s*\w+\.indexOf\(\s*(.+?)\s*\)\s*;')
      .allMatches(src.substring(0, before))) {
    lit = m.group(1);
  }
  return lit;
}

/// هل تُسمّي المِرساةُ إعلانَ دالّة؟ (حيث الحدُّ المقصودُ بيّن.)
bool _namesFunction(String lit) {
  final t = lit.replaceAll(RegExp(r'''^[rf]?['"`]|['"`]$'''), '');
  return t.startsWith('exports.') ||
      t.startsWith('async function ') ||
      t.startsWith('function ');
}

void main() {
  test('لا شريحةَ حارسٍ بعدِّ أحرفٍ على مِرساةِ دالّة', () {
    final offenders = <String>[];
    var windows = 0;
    for (final f in _guardFiles()) {
      final p = f.path.replaceAll(r'\', '/');
      // ملفُّ هذا الحارسِ نفسُه هو الموضعُ الوحيدُ الذي **يَجبُ** أن يَحملَ
      // الشكلَ المحظور: هو الشاهدُ المُصطنَعُ الذي يُثبِتُ أنّ المُستخرِجَ
      // يَعضّ. وأمسكَ الحارسُ شاهدَه في أوّلِ تشغيلٍ — وهو نظيرُ «الحارسُ
      // يَسقطُ على توثيقِه» المسجَّلِ هنا مرّاتٍ، فالعلاجُ واحد: استثناءٌ
      // **مع مضادّةٍ** تُثبِتُ أنّ الشاهدَ ما زال قائماً (أدناه)، وإلّا كان
      // الاستثناءُ باباً لإسكاتِ الحارسِ من داخلِه.
      if (p.endsWith('test/guard_window_bound_test.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in _fixedWindow.allMatches(src)) {
        windows++;
        final lit = _anchorLiteral(src, m.group(3)!, m.start);
        if (lit == null || !_namesFunction(lit)) continue;
        final line = src.substring(0, m.start).split('\n').length;
        offenders.add('$p:$line  ←  ${m.group(1)} = …(${m.group(3)}, '
            '${m.group(3)} + ${m.group(4)})  على  $lit');
      }
    }
    // أرضيّة: مُستخرِجٌ يَنحلُّ إلى صفرٍ يَمرُّ أخضرَ أجوفَ. (٣٤ اليوم، ولا
    // واحدةَ منها على دالّة.)
    expect(windows, greaterThanOrEqualTo(20),
        reason: 'انهارَ مُستخرِجُ الشرائح — فحصٌ لا يَرى شيئاً ليس فحصاً');
    // المضادّة: الشاهدُ المُصطنَعُ في هذا الملفِّ لم يُحذَفْ بحجّةِ الاستثناء.
    final self = File('test/guard_window_bound_test.dart').readAsStringSync();
    expect(_fixedWindow.hasMatch(self), isTrue,
        reason: 'زالَ الشاهدُ المُصطنَعُ — فالاستثناءُ صارَ بلا ما يُبرِّرُه، '
            'ولا شيءَ يُثبِتُ أنّ المُستخرِجَ يَعضُّ أصلاً');
    expect(offenders, isEmpty,
        reason: '\n\nشريحةٌ بعدِّ أحرفٍ على دالّة: إمّا تَقصُرُ عنها فيَصيرُ\n'
            'كلُّ فحصٍ بعدَها أجوفَ على الباقي، أو تَتجاوزُها فتَحكمُ بشفرةِ\n'
            'دالّةٍ أخرى. الحدُّ أوّلُ إعلانٍ عُلويٍّ بعدَ المِرساة:\n'
            '  • ${offenders.join('\n  • ')}\n');
  });

  test('والمُستخرِجُ يَعضُّ فعلاً — يُقرَأُ على شكلٍ مُصطنَع', () {
    // الحارسُ سالبٌ، فلا يُبرهِنُ نجاحُه أنّه يَرى شيئاً: مصدرُ المستودعِ
    // نظيفٌ بعد الإصلاح. فيُقرَأُ على نصٍّ يَحملُ الشكلَ المحظورَ بعينِه.
    const bad = '''
  final i = idx.indexOf('exports.sweepUnassignedPaidOrders');
  final body = idx.substring(i, i + 3200);
''';
    final m = _fixedWindow.firstMatch(bad);
    expect(m, isNotNull, reason: 'المُستخرِجُ لا يَرى الشكلَ المحظور');
    final lit = _anchorLiteral(bad, m!.group(3)!, m.start);
    expect(lit, isNotNull, reason: 'المِرساةُ لا تُحَلُّ إلى نصِّ indexOf');
    expect(_namesFunction(lit!), isTrue, reason: 'لم تُقرَأْ المِرساةُ دالّةً');

    // ولا إيجابيّةَ كاذبة: مِرساةٌ على ودجةٍ أو جملةٍ لا تُمنَع.
    const okWidget = '''
  final i = src.indexOf('itemCount: 30');
  final body = src.substring(i, i + 4000);
''';
    final w = _fixedWindow.firstMatch(okWidget)!;
    expect(_namesFunction(_anchorLiteral(okWidget, w.group(3)!, w.start)!),
        isFalse, reason: 'مِرساةُ ودجةٍ تُقرَأُ دالّةً — نطاقٌ أوسعُ من قصدِه');
  });

  test('والبدائلُ البنيويّةُ قائمةٌ فعلاً — لا دعوى بلا مُنفِّذ', () {
    // الإصلاحُ ليس حذفَ الشرائحِ بل إبدالَها بحدٍّ بنيويّ. فلو زالت تلك
    // الدوالُّ عادَ عدُّ الأحرفِ أسهلَ طريقٍ، فيُشَدُّ وجودُها.
    final pairs = {
      'test/crew_delay_notice_test.dart': 'String fnBody(',
      'test/contract_activation_test.dart': 'String fnBody(',
      'test/staff_removal_guard_test.dart': 'String _decl(',
      'functions/test/ops_sweep_window.test.js': 'function fnBody(',
      'functions/test/ticket_authorship.test.js': 'function fnBody(',
    };
    pairs.forEach((p, decl) {
      final src = File(p).readAsStringSync();
      expect(src.contains(decl), isTrue,
          reason: '$p: زالَ الاقتطاعُ البنيويُّ ($decl)');
      // وكلٌّ منها يَحمي نفسَه من الانهيار: اقتطاعٌ يَنحلُّ إلى سطرٍ
      // يُفرِغُ كلَّ فحصٍ بعدَه بلا أن يَسقطَ أحدها.
      expect(src.contains('انهار'), isTrue,
          reason: '$p: الاقتطاعُ بلا أرضيّةٍ عند الانهيار');
    });
  });
}
