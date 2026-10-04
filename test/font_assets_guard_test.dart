import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **لا يُطلب من `google_fonts` إلّا ما هو مُضمَّنٌ في الأصول.**
///
/// `main.dart` يضبط `GoogleFonts.config.allowRuntimeFetching = false` عمداً
/// (أوّلُ تشغيلٍ بلا إنترنت كان يعرض خطّاً بديلاً مشوّهاً في كلّ الواجهة).
/// فكلُّ طلبِ عائلةٍ أو وزنٍ غيرِ موجودٍ في `pubspec.yaml` **يفشل**: الحزمة
/// ترمي استثناءً، تلتقطه بنفسها، وتُعيد نمطاً **بلا عائلة** — فيُرسم النصّ
/// بخطّ النظام لا بـTajawal. لا انهيار، ولا فحصٌ يسقط، ولا شيءَ في `analyze`.
///
/// **اكتُشف بتشغيل التطبيق فعليّاً** (2026-10-04): ٣٧٦ استثناءً لـ`Roboto-Bold`
/// في ٢٨ ثانية من شاشة البداية وحدها، وواحدٌ لـ`Tajawal-ExtraBold`. والمسحُ
/// الكامل بعدها كشف **٤٥ موضعَ وزنٍ** غيرِ مُضمَّن و**عائلتين** غيرِ مُضمَّنتين
/// (`roboto` في شعار البداية، `ibmPlexMono` في رمز الطلب بشاشة النجاح).
///
/// **ليس هنا فحصٌ لوجود ملفّ الخطّ على القرص**: جُرّب فوُجد خاملاً — أداةُ
/// فلاتر نفسها تفشل قبله («unable to locate asset entry in pubspec.yaml»)
/// فلا يصل التنفيذُ إليه أبداً. وفحصٌ لا يعضّ أسوأُ من غيابه.
///
/// التصحيح: الوزنُ يُقرَّب لأقرب مُضمَّن وعند التعادل إلى الأثقل (600→700،
/// 800→900)، والعائلتان إلى Tajawal. ولاحظ أنّ **وزن 600 لا وجود له لخطّ
/// Tajawal أصلاً** عند Google، فلا تُحلّه إضافةُ أصلٍ جديد — تغييرُ الطلب هو
/// الحلُّ الوحيد.
void main() {
  // ── الأوزان المُضمَّنة، تُقرأ من pubspec لا تُكتب هنا ──
  final String pubspec = File('pubspec.yaml').readAsStringSync();
  final Set<String> families = {};
  final Set<int> weights = {};
  String? current;
  for (final line in pubspec.split('\n')) {
    final f = RegExp(r'^\s*-\s*family:\s*(\w+)').firstMatch(line);
    if (f != null) current = f.group(1);
    final w = RegExp(r'^\s*weight:\s*(\d+)').firstMatch(line);
    if (w != null && current != null) {
      families.add(current);
      weights.add(int.parse(w.group(1)!));
    }
  }

  /// محتوى التعليقات مُبدَّلٌ بمسافات — الطولُ محفوظٌ فتبقى الإزاحات صحيحة.
  /// (التجريدُ بحذف الأسطر يزيح المواضع ويجعل الفحص يقرأ نصّاً آخر.)
  String mask(String t) {
    final out = t.split('');
    for (int i = 0; i < t.length - 1; i++) {
      if (t[i] == '/' && t[i + 1] == '/') {
        int j = t.indexOf('\n', i);
        if (j < 0) j = t.length;
        for (int k = i; k < j; k++) {
          out[k] = ' ';
        }
        i = j;
      }
    }
    return out.join();
  }

  int? callEnd(String t, int open) {
    int depth = 0;
    for (int j = open; j < t.length; j++) {
      if (t[j] == '(') depth++;
      if (t[j] == ')') {
        depth--;
        if (depth == 0) return j;
      }
    }
    return null;
  }

  const Map<String, int> wNames = {
    'normal': 400, 'bold': 700,
    'w100': 100, 'w200': 200, 'w300': 300, 'w400': 400, 'w500': 500,
    'w600': 600, 'w700': 700, 'w800': 800, 'w900': 900,
  };

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final Set<String> usedFamilies = {};
  final List<String> badWeights = [];
  final List<String> maskDrift = [];

  for (final f in files) {
    final src = f.readAsStringSync();
    final code = mask(src);
    if (code.length != src.length) maskDrift.add(f.path);
    for (final m in RegExp(r'GoogleFonts\.(\w+)\s*\(').allMatches(code)) {
      usedFamilies.add(m.group(1)!);
      final open = code.indexOf('(', m.start);
      final end = callEnd(code, open);
      if (end == null) continue;
      final body = src.substring(open + 1, end);
      for (final w in RegExp(r'FontWeight\.(\w+)').allMatches(body)) {
        final n = wNames[w.group(1)];
        if (n != null && !weights.contains(n)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          badWeights.add('${f.path}:$line → FontWeight.${w.group(1)}');
        }
      }
    }
  }

  group('خطوطُ google_fonts مُضمَّنة', () {
    test('الفحصُ نفسه سليم: إخفاءُ التعليقات لا يُزيح المواضع', () {
      // تجريدٌ يغيّر الطولَ يجعل كلّ ما بعده يقرأ نصّاً في غير موضعه — وهو
      // بالضبط ما أفسد أوّلَ محاولةٍ لتصحيح هذه المواضع.
      expect(maskDrift, isEmpty);
      expect(files.length, greaterThan(50), reason: 'لم تُمسح شجرةُ lib');
      expect(usedFamilies, isNotEmpty, reason: 'لم يُعثر على أيّ GoogleFonts.');
    });

    test('pubspec يُصرّح بعائلةٍ وأوزانٍ تُقرأ فعلاً', () {
      expect(families, isNotEmpty, reason: 'لم تُقرأ أيُّ عائلةٍ من pubspec');
      expect(weights, isNotEmpty);
      expect(families, {'Tajawal'},
          reason: 'عائلةٌ مُضمَّنةٌ جديدة — راجع هذا الحارس عمداً');
    });

    test('لا تُطلب عائلةٌ غيرُ مُضمَّنة', () {
      // كلُّ ما بعد `GoogleFonts.` اسمُ عائلةٍ أو مُولّدُ TextTheme لها.
      final lower = families.map((e) => e.toLowerCase()).toSet();
      final offenders = usedFamilies
          .where((u) => !lower.any((f) => u.toLowerCase().startsWith(f)))
          .toList()
        ..sort();
      expect(offenders, isEmpty,
          reason: 'عائلاتٌ غيرُ مُضمَّنة ⇒ خطُّ النظام بدل Tajawal: $offenders');
    });

    test('لا يُطلب وزنٌ غيرُ مُضمَّن', () {
      expect(badWeights, isEmpty,
          reason: 'الأوزانُ المُضمَّنة ${weights.toList()..sort()} — '
              'وهذه المواضع تطلب غيرها:\n${badWeights.join('\n')}');
    });

    test('الجلبُ الشبكيّ ما زال مُطفأً — وهو سببُ صرامة ما سبق', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('GoogleFonts.config.allowRuntimeFetching = false'),
          isTrue,
          reason: 'لو عاد الجلب، فالوزنُ الناقص يُنزَّل بدل أن يفشل — '
              'لكنّ أوّلَ تشغيلٍ بلا إنترنت يعود مشوّهاً. القرار موثّقٌ في main.dart');
    });
  });
}
