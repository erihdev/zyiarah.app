// ════════════════════════════════════════════════════════════════════════
// «٣٥٫٠ ر.س» على رفِّ المتجر — رقمُ مالٍ يُطبَعُ خامّاً (2026-10-06)
//
// الرقمُ في Firestore قد يكون `int` أو `double` بحسبِ مَن كتبَه، ومحرّرا
// الإدارةِ يَكتبانِ `double.tryParse(...) ?? 0.0` — فسعرُ ٣٥ يُخزَّنُ `35.0`،
// و`'$v'` في دارت تَطبعُه **«35.0 ر.س»**. ولا يَظهرُ ذلك في أيِّ فحص:
// النوعُ صحيحٌ، والنصُّ قبيحٌ فحسب — على رفِّ المتجرِ وفي السلّةِ وفي
// مجموعِها، وفي بطاقاتِ الباقاتِ والعقود.
//
// والقاعدةُ موجودةٌ في المستودعِ من قبل (`formatSar`: صحيحٌ بلا كسور، وإلّا
// خانتان) وتعليقُها يَقول إنّها كُتبت لِيُعرَضَ **نفسُ الرقمِ الذي يُدفَع**؛
// وكانت مُنفَّذةً في شاشةٍ واحدة. و`formatSarAny` تُطبّقُها على قيمةٍ من
// مستندٍ (`Object?`) كي تُستعمَلَ مباشرةً على الخريطة.
//
// والقاعدةُ المشدودةُ: **كلُّ رقمٍ يُسبَقُ بـ«ر.س» في `lib/` مُنسَّق**، مع
// استثناءاتٍ مُسمّاةٍ لصِيَغٍ أخرى مقصودة.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/home_packages.dart';

/// صِيَغُ التنسيقِ المقبولةُ — كلٌّ قرارٌ قائمٌ في موضعِه.
const List<String> _formatters = <String>[
  'formatSarAny(', // القاعدةُ العامّة
  'formatSar(', // الأصلُ لقيمةٍ `double` معروفةِ النوع
  'toStringAsFixed', // خانتانِ دائماً — عمودُ مبالغِ قائمةِ الطلبات
  '_trim(', // «صحيحٌ بلا كسورٍ وإلّا `toString`» — سعرُ الوحدةِ في السوفا
  '_t(', // النسخةُ نفسُها في `service_meta_view`
  'toInt', 'round', 'NumberFormat', 'intl.',
];

void main() {
  test('(أ) القاعدةُ سلوكاً: صحيحٌ بلا كسور، وإلّا خانتان', () {
    expect(formatSarAny(35), '35');
    expect(formatSarAny(35.0), '35');
    expect(formatSarAny(35.5), '35.50');
    expect(formatSarAny(172.456), '172.46');
    expect(formatSarAny('35.0'), '35', reason: 'نصٌّ رقميٌّ من مستندٍ قديم');
    expect(formatSarAny(null), '0');
    expect(formatSarAny('قيد التسعير'), '0',
        reason: 'غيرُ الرقميِّ يُقرأُ صفراً — فلا يُمرَّرُ نصٌّ هنا');
    expect(formatSarAny(0), '0');
    expect(formatSarAny(-5.5), '-5.50');
  });

  test('(ب) لا رقمَ خامّاً قبلَ «ر.س» في أيِّ ملفٍّ تحتَ lib/', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();
    expect(files.length, greaterThanOrEqualTo(120),
        reason: 'المسحُ لم يَقرأ شيئاً — حارسٌ أجوف');
    var withSar = 0;
    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//') || !l.contains('ر.س')) continue;
        withSar++;
        // **شكلانِ لا شكلٌ واحد:** `${...}` بأيِّ محتوى (ومنه تعبيرٌ يَبدأُ
        // بقوس) و`$ident` العاري. أوّلُ صياغةٍ شَرطت أن يَبدأَ المحتوى
        // بحرفٍ، فكان `${(a ?? b)} ر.س` **لا يُطابَقُ أصلاً** — كشفَه
        // اختبارُ قضمٍ نزعَ المُنسّقَ من تقريرِ الـPDF فمرَّ أخضر.
        for (final m in RegExp(r'\$\{([^}]*)\}\s*ر\.س'
                r'|\$([A-Za-z_][A-Za-z0-9_]*)\s*ر\.س')
            .allMatches(l)) {
          final expr = (m.group(1) ?? m.group(2))!.trim();
          if (_formatters.any(expr.contains)) continue;
          // نصٌّ لا رقم: مُنتقي الوحدةِ (`… ? '%' : 'ر.س'`) ونظائرُه.
          //
          // **والاقتباسُ يُفحَصُ بعدَ نزعِ `[...]`:** أوّلُ صياغةٍ تَخطَّت كلَّ
          // تعبيرٍ فيه علامةُ اقتباس، و`data['amount']` فيه اقتباسانِ —
          // فأُعقِمَ الفحصُ عن **أغلبِ** المواضع، وكشفَه اختبارُ قضمٍ أعادَ
          // بريدَ الإدارةِ خامّاً فمرَّ أخضر.
          final noIndex = expr.replaceAll(RegExp(r'\[[^\]]*\]'), '');
          if (noIndex.contains("'") || noIndex.contains('"')) continue;
          // **مُعرِّفٌ مفردٌ يُحَلُّ إلى تعريفِه في الملفِّ نفسِه** بدلَ
          // قائمةِ أسماءٍ تَتعفّن: `formattedAmount` و`reward` و`v` كلُّها
          // منسَّقةٌ عند الإسناد، وقائمةٌ يدويّةٌ كانت ستَقبلُ غيرَها غداً.
          final bare = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(expr);
          if (bare) {
            final def = RegExp(
                    '(?:final|var|const|double|int|num|String)[^;\n]*\\b'
                    '${RegExp.escape(expr)}\\s*=([^;]*);',
                    dotAll: true)
                .firstMatch(lines.join('\n'));
            if (def != null && _formatters.any(def.group(1)!.contains)) continue;
            if (def == null) {
              offenders.add('$path:${i + 1}  → $expr (لا تعريفَ في الملفّ)');
              continue;
            }
          }
          offenders.add('$path:${i + 1}  → $expr');
        }
      }
    }
    expect(withSar, greaterThanOrEqualTo(60),
        reason: 'لم يُعثَر على أسطرِ «ر.س» — فالمسحُ لا يَفحصُ شيئاً');
    expect(offenders, isEmpty,
        reason: 'رقمُ مالٍ يُطبَعُ خامّاً — «35.0 ر.س»:\n'
            '${offenders.join('\n')}');
  });

  test('(ج) القاعدةُ تَسكنُ موضعاً واحداً ومعها شرحُها', () {
    final util = File('lib/utils/home_packages.dart').readAsStringSync();
    expect(RegExp(r'String formatSarAny\(').allMatches(util).length, 1,
        reason: 'نسخةٌ ثانيةٌ من القاعدةِ تَنحرِف');
    expect(util.contains('formatSar('), isTrue,
        reason: 'لم تَعُد تَستعملُ القاعدةَ الأصليّة — فالصيغتانِ تَفترقان');
    expect(util.contains('35.0'), isTrue,
        reason: 'شرحُ سببِ الوحدةِ زال، فلا يَعرفُ قارئٌ ما تَحرُسُه');
    // **ولا فحصَ «لا صيغةَ رابعة»:** جُرِّبَ بعَدِّ `roundToDouble() ?`
    // فالتقطَ مُنسّقَ النسبةِ (`fmtPercent`) ومُنسّقَ التقييمِ ومُعبّئَ
    // حقلِ نصٍّ في محرّرِ المناطق — ثلاثةٌ لا علاقةَ لها بالريال. فحصٌ لا
    // يُميّزُ المالَ من غيرِه ضجيجٌ، والحارسُ الحقيقيُّ هو (ب): كلُّ موضعِ
    // عرضٍ يُنادي صيغةً مُعتمَدة.
  });

  test('(د) ورفُّ المتجرِ والسلّةُ يُنادِيانِها — الموضعُ الذي ظهرَ فيه', () {
    final store = File('lib/screens/store_screen.dart').readAsStringSync();
    expect(RegExp(r'formatSarAny\(').allMatches(store).length,
        greaterThanOrEqualTo(4),
        reason: 'رفُّ المتجرِ والسلّةُ ومجموعُها: أربعةُ مواضعَ على الأقل');
  });
}
