import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

/// **سعرٌ مكتوبٌ أنّه شاملُ الضريبةِ وهو أساس — في الملفِّ الذي يُعلِنُ نفسَه
/// «مصدرَ الحقيقةِ الواحد» لتلك الأرقام.**
///
/// ترويسةُ `service_pricing_defaults.dart` كانت تَقول «هذه أسعارٌ **شاملةُ
/// ضريبةِ القيمةِ المضافةِ 15%** (كبقيّةِ أسعارِ التطبيق)» — كاذبةٌ في
/// شقَّيها: المعدَّلاتُ التسعُ أساسٌ تُضافُ الضريبةُ فوقَه، وبقيّةُ أسعارِ
/// التطبيقِ أساسٌ كذلك (قرارٌ مُقرَّرٌ يَحرُسُه `vat_display_claim_test`).
/// وهي عائلةُ «سعرٌ مكتوبٌ أنّه شاملُ الضريبةِ فوق سعرٍ ليس كذلك» بعينِها،
/// واقعةً هذه المرّةَ على **مُدخَلِ** السعرِ لا على عرضِه.
///
/// ومعها شقّانِ من الشكلِ نفسِه:
///
///   * **خمسُ مجموعاتِ أسعارٍ في محرِّرِ المناطق، اثنتانِ تَقولانِ «قبل
///     الضريبة» وثلاثٌ لا** — على السطحَين معاً. فالمالكُ يُدخِلُ معدَّلاً
///     ولا يَعرفُ أتَدفعُ العميلةُ ٣٥ أم ٤٠٫٢٥.
///   * **والأرقامُ التسعةُ مكتوبةٌ مرّتَين** (الدارتُ و`Settings.tsx`) بتعليقٍ
///     في اللوحةِ يُعلِنُ الدارتَ مصدرَها — ولا شيءَ يُبقيهما متساويَين.
///     والتعليقانِ كانا **يَختلفانِ في المعنى**: اللوحةُ تَقولُ «أساس قبل
///     الضريبة» (صحيح) والدارتُ «شاملة» (خطأ). نفسُ الأرقامِ بمعنيَين.
void main() {
  final String defaults =
      File('lib/utils/service_pricing_defaults.dart').readAsStringSync();
  final String zoneScr = File('lib/screens/admin/admin_hourly_zones_screen.dart')
      .readAsStringSync();
  final String panel =
      File('admin_panel/src/pages/Settings.tsx').readAsStringSync();
  final String pricing = File('functions/pricing.js').readAsStringSync();

  /// التسعةُ بأسماءِ حقولِ Firestore التي يَقرؤها الخادمُ، مقرونةً بثوابتِ
  /// الدارت — فالمقارنةُ بالاسمِ لا بالترتيب.
  const Map<String, String> fieldToConst = {
    'sofaSqmPrice': 'kDefaultSofaSqmPrice',
    'rugSqmPrice': 'kDefaultRugSqmPrice',
    'acMaintWindowPrice': 'kDefaultAcMaintWindowPrice',
    'acMaintSplitPrice': 'kDefaultAcMaintSplitPrice',
    'acWashWindowPrice': 'kDefaultAcWashWindowPrice',
    'acWashSplitPrice': 'kDefaultAcWashSplitPrice',
    'carSmallPrice': 'kDefaultCarSmallPrice',
    'carMediumPrice': 'kDefaultCarMediumPrice',
    'carLargePrice': 'kDefaultCarLargePrice',
  };

  group('المعدَّلاتُ التسعةُ أساسٌ قبلَ الضريبة', () {
    test('(أ) الدعوى الكاذبةُ زالت، وشرحُ زوالِها باقٍ', () {
      final String code = stripComments(defaults);
      // لا دعوى شمولٍ في **الشفرة** (التعليقُ يَقتبسُها ليَشرحَ زوالَها).
      for (final claim in const [
        'شاملة ضريبة',
        'شامل الضريبة',
        'شاملة الضريبة',
      ]) {
        expect(code.contains(claim), isFalse,
            reason: 'دعوى «$claim» عادت إلى شفرةِ ملفِّ المعدَّلات');
      }
      // ومضادَّةٌ: الاقتباسُ الذي يَشرحُ العطلَ ما زال في الخامّ — فلو
      // أُزيلَ التعليقُ كلُّه لَسقطَ هذا، ولا يَبقى في الملفِّ ما يَمنعُ
      // عودةَ الدعوى بحسنِ نيّة.
      expect(defaults.contains('أسعارٌ شاملةُ ضريبةِ القيمةِ المضافةِ 15%'),
          isTrue,
          reason: 'شرحُ الدعوى الكاذبةِ اختفى — فالقارئُ لا يَعرفُ لِمَ '
              'صارَ السطرُ كما هو');
      expect(defaults.contains('أسعارُ أساسٍ قبلَ الضريبة'), isTrue,
          reason: 'الدعوى الصحيحةُ غيرُ مكتوبة');
    });

    test('(ب) وكلُّ مجموعةِ أسعارٍ في المحرِّرَين تَقولُ «قبل الضريبة»', () {
      // النطاقُ مُشتَقٌّ: كلُّ ترويسةِ مجموعةٍ تَحملُ كلمةَ «أسعار» أو
      // «تنظيف»/«باقات»/«عاملات» ومعها «ر.س» أو «المتر» — فمجموعةٌ سادسةٌ
      // تُضافُ غداً تَدخلُ النطاقَ بنفسِها.
      final RegExp dartHeader =
          RegExp(r'const Text\("([^"]*(?:ر\.س|المتر)[^"]*)"');
      final List<String> dartHeaders = dartHeader
          .allMatches(stripComments(zoneScr))
          .map((m) => m.group(1)!)
          .where((h) => h.contains(':'))
          .toList();
      expect(dartHeaders.length, greaterThanOrEqualTo(5),
          reason: 'مسحُ تروايسِ المحرِّرِ انحلَّ (${dartHeaders.length}) — '
              'الفحصُ يَصيرُ أخضرَ أجوف');
      for (final h in dartHeaders) {
        expect(h.contains('قبل الضريبة'), isTrue,
            reason: 'ترويسةُ أسعارٍ بلا «قبل الضريبة» في محرِّرِ التطبيق: «$h»');
      }

      final RegExp panelHeader =
          RegExp(r'text-sm mb-[12]">([^<]*(?:ر\.س|المتر)[^<]*)</h5>');
      final List<String> panelHeaders = panelHeader
          .allMatches(stripComments(panel))
          .map((m) => m.group(1)!)
          .toList();
      expect(panelHeaders.length, greaterThanOrEqualTo(5),
          reason: 'مسحُ تروايسِ اللوحةِ انحلَّ (${panelHeaders.length})');
      for (final h in panelHeaders) {
        expect(h.contains('قبل الضريبة'), isTrue,
            reason: 'ترويسةُ أسعارٍ بلا «قبل الضريبة» في اللوحة: «$h»');
      }
    });

    test('(ج) والأرقامُ التسعةُ متساويةٌ بين الدارتِ واللوحة', () {
      final String pCode = stripComments(panel);
      for (final e in fieldToConst.entries) {
        final RegExpMatch? dm = RegExp(
                r'const double ' + e.value + r'\s*=\s*([\d.]+)\s*;')
            .firstMatch(defaults);
        expect(dm, isNotNull, reason: 'ثابتُ ${e.value} اختفى');
        final double dart = double.parse(dm!.group(1)!);
        final RegExpMatch? pm =
            RegExp(e.key + r":\s*'([\d.]+)'").firstMatch(pCode);
        expect(pm, isNotNull,
            reason: 'افتراضُ ${e.key} اختفى من نموذجِ اللوحة');
        final double tsv = double.parse(pm!.group(1)!);
        expect(tsv, dart,
            reason: '${e.key}: الدارتُ $dart واللوحةُ $tsv — نسختانِ '
                'لرقمٍ واحدٍ انحرفتا، ولا شيءَ غيرُ هذا الفحصِ يُبقيهما سواءً');
      }
      // ومجموعةُ الحقولِ كاملةً: حقلٌ عاشرٌ يُراجَعُ بدلَ أن يَبقى بلا نظير.
      final Set<String> tsFields = RegExp(r"\b(\w+Price):\s*'[\d.]*'")
          .allMatches(pCode)
          .map((m) => m.group(1)!)
          .where((k) => k != 'eventWorkerHourPrice')
          .toSet();
      expect(tsFields, fieldToConst.keys.toSet(),
          reason: 'مجموعةُ حقولِ الأسعارِ في نموذجِ اللوحةِ تغيّرت — '
              'راجِعْ الجديدَ: أله ثابتٌ في الدارت؟');
    });

    test('(د) وشاهدا التعليل: الخادمُ يُعيدُ الأساسَ والشاشاتُ تُضيفُ فوقَه',
        () {
      // الخادمُ: الدالّةُ اسمُها «الأساس» وتَقرأُ هذه الحقولَ بعينِها.
      //
      // والمشدودُ **شكلُ** الاسمِ لا احتواؤه: اختبارُ قضمٍ أعادَ التسميةَ إلى
      // `computeExpectedBasePriceX` فمرَّ أخضرَ، لأنّ الاحتواءَ يُرضيه أيُّ
      // اسمٍ يَبدأُ بالقديم — فخُّ `packageFormErrorX` بعينِه. ومعه أنّها
      // **مُصدَّرةٌ**، فالاسمُ الذي يُنادِيه بقيّةُ الخادمِ هو المشدود.
      final String pc = stripComments(pricing);
      expect(RegExp(r'function\s+computeExpectedBasePrice\s*\(').hasMatch(pc),
          isTrue,
          reason: 'دالّةُ حسابِ الأساسِ لم تَعُد بهذا الاسمِ — يُراجَعُ التعليل');
      expect(
          RegExp(r'module\.exports\s*=\s*\{[^}]*\bcomputeExpectedBasePrice\b')
              .hasMatch(pc),
          isTrue,
          reason: 'دالّةُ الأساسِ لم تَعُد مُصدَّرةً بهذا الاسم');
      for (final f in const ['sofaSqmPrice', 'rugSqmPrice']) {
        expect(RegExp('zone\\.$f' r'\b').hasMatch(pc), isTrue,
            reason: 'الخادمُ لم يَعُد يَقرأُ $f — يُراجَعُ التعليل');
      }
      // والشاشاتُ الثلاثُ تُضيفُ الضريبةَ فوقَ المجموع.
      for (final f in const [
        'sofa_rug_details_screen',
        'ac_service_details_screen',
        'car_interior_details_screen',
      ]) {
        final String src =
            stripComments(File('lib/screens/$f.dart').readAsStringSync());
        expect(src.contains('vatOnBase(totalAmount)'), isTrue,
            reason: '$f لم يَعُد يُضيفُ الضريبةَ فوقَ الأساس — '
                'فدعوى «أساس» تُراجَعُ لا تُسكَت');
        expect(src.contains('totalAmount + vat'), isTrue,
            reason: '$f لم يَعُد يَشحنُ الأساسَ + الضريبة');
      }
    });

    test('(هـ) وسعرُ الكنبِ طوليٌّ لا مربّع — في الوصفِ كما في الحساب', () {
      expect(
          RegExp(r'measure\s*=\s*isRug\s*\?\s*len\s*\*\s*wid\s*:\s*len')
              .hasMatch(stripComments(pricing)),
          isTrue,
          reason: 'الخادمُ لم يَعُد يَقيسُ الكنبَ بالطولِ وحدَه — '
              'يُراجَعُ وصفُ الثابت');
      // والنافذةُ هي كتلةُ التوثيقِ **الملاصقةُ** للثابتِ وحدَها، لا كلُّ ما
      // قبلَه: `substring(0, at)` يَرضى بذكرٍ في أيِّ موضعٍ أعلى الملفِّ
      // بينما الوصفُ نفسُه يَقولُ «المربع» — «موضعٌ آخرُ يُرضي الفحصَ».
      final List<String> lines = defaults.split('\n');
      final int ci =
          lines.indexWhere((l) => l.startsWith('const double kDefaultSofaSqmPrice'));
      expect(ci, greaterThan(0), reason: 'ثابتُ سعرِ الكنبِ اختفى');
      int top = ci;
      while (top > 0 && lines[top - 1].trimLeft().startsWith('///')) {
        top--;
      }
      expect(ci - top, greaterThanOrEqualTo(2),
          reason: 'ثابتُ سعرِ الكنبِ بلا كتلةِ توثيقٍ ملاصقة — '
              'فلا موضعَ يُقالُ فيه إنّ القياسَ طوليّ');
      final String doc = lines.sublist(top, ci).join('\n');
      expect(doc.contains('المتر الطولي'), isTrue,
          reason: 'وصفُ ثابتِ الكنبِ لا يَقولُ «الطولي» — وكان يَقولُ '
              '«المتر المربع» وهو خطأُ وحدة');
    });
  });
}
