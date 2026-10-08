import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/utils/invoice_stamp.dart';
import 'package:zyiarah/utils/ksa_instant.dart';
import 'package:zyiarah/widgets/zatca_invoice_card.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **تاريخُ الوثيقةِ بتوقيتِ الرياضِ لا بساعةِ قارئِها.**
///
/// اللحظةُ صارت صحيحةً ومصدرُها واحداً (`invoiceIssuedAt`)، **وطبعُها بقيَ
/// بمنطقةِ الجهاز** في خمسةِ مواضعَ على وثيقتَين:
///
///   • الفاتورةُ الضريبيّةُ المبسّطة — `zatca_invoice_card._fmt`،
///     و`admin_invoices_screen._fmt` (**نسخةٌ مطابقةٌ بايتاً ببايت**)، و
///     `zyiarah_pdf_service` عبرَ `intl.DateFormat('yyyy-MM-dd HH:mm')`.
///   • وثيقةُ العقدِ الإلكتروني — «تاريخ الإصدار / Issue Date» في الملفّ،
///     وتاريخُ البطاقةِ في «عقودي»، وكلاهما من `createdAt` أي
///     `Timestamp.toDate()`: لحظةٌ مطلقة.
///
/// وثلاثتُها تَقرأُ `d.year`/`d.hour` من لحظةٍ **مطلقة**، ورمزُ ZATCA في
/// الوثيقةِ نفسِها يُشفّرُ Tag 3 من `timestamp.toUtc()` — أي اللحظةَ
/// الصحيحة. فالفاتورةُ الواحدةُ تَحملُ حقلَي تاريخٍ لا يَتّفقان: مقروءٌ
/// بساعةِ القارئِ ومشفَّرٌ باللحظةِ الحقيقيّة.
///
/// **ومُقاسٌ لا مظنون** — خدمةٌ سُلِّمت الواحدةَ صباحاً بالرياضِ في ٩ أكتوبر
/// (22:00Z من الثامن): جهازٌ على +03 يَطبعُ `2026/10/09 01:00` ✓، وبلندن
/// `2026/10/08 23:00` ✗، وبنيويورك `2026/10/08 18:00` ✗ — **اليومُ الخطأ**
/// على فاتورةٍ ضريبيّة. كامنٌ لا حيٌّ (يَلزمُه جهازٌ خارجَ +03، ولا توقيتَ
/// صيفيَّ في السعوديّةِ فداخلَها لا يَقعُ أبداً)، والإصلاحُ **حافظُ السلوكِ
/// على +03** بالضبط.
///
/// **والمسحُ العامُّ لعرضِ الوقتِ في كلِّ الشاشاتِ شريحةٌ أخرى مسجَّلةٌ**
/// (لوحا المواعيدِ ونوافذُ التحليلاتِ) — نطاقُ هذا الحارسِ **وثائقُ** لها
/// نظيرٌ آليٌّ على الوثيقةِ نفسِها، لا كلُّ تاريخٍ مُعروض.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String code(String rel) => stripComments(read(rel));

  /// وسائطُ كلِّ نداءٍ باسمٍ من [names] بموازنةِ الأقواس — لا نافذةَ أحرف.
  ///
  /// **وبحدِّ كلمةٍ قبلَ الاسم**: بلاهُ كان `Text(` يُطابِقُ ذيلَ
  /// `invoiceIssuedAtText(` و`ksaDateText(` — أي أنّ الكاشفَ يَلتقطُ **نداءَ
  /// القاعدةِ نفسِها** فيَقرأُ وسيطَها `issuedAt` «طبعاً بلا قاعدة». فخُّ
  /// «الاسمُ ليس القدرة» معكوساً، وقد أسقطَ الفحصَ على شفرةٍ مُصلَحة.
  List<String> callArgs(String src, List<String> names) {
    bool boundary(int at) {
      if (at == 0) return true;
      return !RegExp(r'[A-Za-z0-9_$.]').hasMatch(src[at - 1]);
    }

    final out = <String>[];
    for (final name in names) {
      var i = 0;
      while (true) {
        final at = src.indexOf('$name(', i);
        if (at < 0) break;
        if (!boundary(at)) {
          i = at + 1;
          continue;
        }
        var depth = 0;
        var j = at + name.length;
        final start = j + 1;
        for (; j < src.length; j++) {
          final c = src[j];
          if (c == '(') depth++;
          if (c == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        if (j < src.length) out.add(src.substring(start, j));
        i = at + name.length + 1;
      }
    }
    return out;
  }

  // ── الوثيقتانِ ومُصيّراتُهما: أربعةُ ملفّاتٍ، لكلٍّ سببُه ─────────────
  const renderers = <String, String>{
    'lib/widgets/zatca_invoice_card.dart':
        'بطاقةُ الفاتورةِ الضريبيّةِ على الشاشة',
    'lib/screens/admin/admin_invoices_screen.dart':
        'صفُّ سجلِّ الفواتيرِ عند المالك',
    'lib/services/zyiarah_pdf_service.dart':
        'ملفُّ الفاتورةِ المرفوع، وملفُّ العقدِ المُنزَّل',
    'lib/screens/contracts_list_screen.dart': 'بطاقةُ العقدِ في «عقودي»',
    'lib/screens/admin/admin_contracts_screen.dart':
        'بطاقةُ العقدِ وتاريخُ توقيعِه عند المالك',
  };

  group('(أ) القاعدةُ: لحظةٌ مطلقةٌ ← ساعةُ حائطٍ سعوديّة', () {
    test('ksaWallOf عكسُ ksaInstantOf بالضبط — خاصيّةٌ لا مثال', () {
      var checked = 0;
      for (var m = 1; m <= 12; m++) {
        for (final d in [1, 15, 28]) {
          for (var h = 0; h < 24; h++) {
            for (final mi in [0, 7, 30, 59]) {
              final wall = DateTime(2026, m, d, h, mi);
              final back = ksaWallOf(ksaInstantOf(wall));
              expect(back.year, wall.year);
              expect(back.month, wall.month);
              expect(back.day, wall.day);
              expect(back.hour, wall.hour);
              expect(back.minute, wall.minute);
              checked++;
            }
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(3000),
          reason: 'الخاصيّةُ لم تُفحَصْ على مدًى حقيقيّ');
    });

    test('ولا تَتأثّرُ بمنطقةِ الجهاز — سلوكاً ومصدراً', () {
      final utc = DateTime.utc(2026, 10, 8, 22, 0);
      final local = utc.toLocal(); // النكهةُ تَختلفُ واللحظةُ واحدة
      expect(local.isAtSameMomentAs(utc), isTrue);
      expect(invoiceIssuedAtText(local), invoiceIssuedAtText(utc));
      expect(ksaDateText(local), ksaDateText(utc));

      // **والسلوكُ وحدَه لا يَكفي، ومُثبَتٌ باختبارِ قضم:** مُشغّلُ الفحصِ
      // في CI على UTC، فمكوّناتُ `x` و`x.toUtc()` واحدةٌ هناك — فقضمةٌ
      // تَنزِعُ `.toUtc()` من `ksaWallOf` مرَّت **خضراءَ** على الفحصِ أعلاه
      // وعلى المجموعةِ كلِّها. فالذي يَعضُّ في مُشغّلٍ على UTC هو المصدرُ:
      // القراءةُ تَبدأُ من `toUtc()`، وإلّا كانت مكوّناتَ جهازِ القارئ.
      final src = code('lib/utils/ksa_instant.dart');
      final i = src.indexOf('DateTime ksaWallOf(');
      expect(i, greaterThan(0));
      final fn = src.substring(i, src.indexOf('\n}', i));
      expect(fn, contains('instant.toUtc()'),
          reason: 'ksaWallOf تَقرأُ مكوّناتَ منطقةِ الجهاز');
      expect(fn, contains('kKsaUtcOffset'));
    });
  });

  group('(ب) النصُّ المطبوع', () {
    test('حدُّ اليومِ — الحالةُ التي كانت تَطبعُ أمس', () {
      // 22:00Z في ٨ أكتوبر == الواحدةُ صباحاً في ٩ أكتوبر بالرياض.
      final instant = DateTime.utc(2026, 10, 8, 22, 0);
      expect(invoiceIssuedAtText(instant), '2026-10-09 01:00 +03');
      expect(ksaDateText(instant), '2026-10-09');
      // وما كانت تَطبعُه الأجهزةُ خارجَ +03 لم يَعُدْ مُمكناً:
      expect(invoiceIssuedAtText(instant), isNot(contains('2026-10-08')));
    });

    test('ومنتصفُ النهارِ كما هو — لا إزاحةَ مزدوجة', () {
      expect(invoiceIssuedAtText(DateTime.utc(2026, 9, 16, 6, 30)),
          '2026-09-16 09:30 +03');
      expect(ksaDateText(DateTime.utc(2026, 9, 16, 6, 30)), '2026-09-16');
    });

    test('والإزاحةُ مُشتَقّةٌ من kKsaUtcOffset لا مكتوبةً نصّاً', () {
      expect(kKsaUtcOffset, const Duration(hours: 3),
          reason: 'الإزاحةُ تغيّرت — يُراجَعُ النصُّ المطبوعُ معها');
      expect(invoiceIssuedAtText(DateTime.utc(2026, 1, 1)), endsWith('+03'));
      final body = code('lib/utils/invoice_stamp.dart');
      final i = body.indexOf('String invoiceIssuedAtText(');
      expect(i, greaterThan(0));
      final fn = body.substring(i, body.indexOf('\n}', i));
      expect(fn, contains('kKsaUtcOffset'),
          reason: 'الإزاحةُ في النصِّ لا تَتبعُ الثابت');
      expect(fn.contains("'+03'"), isFalse,
          reason: 'إزاحةٌ مكتوبةٌ نصّاً تَنحرِفُ عن kKsaUtcOffset بصمت');
    });
  });

  group('(ج) النطاقُ مُشتَقٌّ — لا موضعَ يَطبعُ لحظةً بنفسِه', () {
    test('كلُّ طابعٍ لـissuedAt يَمُرُّ بالقاعدة — المجموعةُ كاملةً', () {
      final printers = <String>{};
      for (final f in sourcesIn('$repo/lib', atLeast: 150)) {
        final rel = f.path.substring(repo.length + 1);
        final src = stripComments(f.readAsStringSync());
        if (!src.contains('issuedAt')) continue;
        // «يَطبع» = اللحظةُ داخلَ وسيطِ بانٍ نصّيّ، لا مُمرَّرةً إلى دالّة.
        final shown = callArgs(src, ['Text', 'pw.Text', '_kv'])
            .where((a) => a.contains('issuedAt'))
            .toList();
        if (shown.isEmpty) continue;
        printers.add(rel);
        for (final a in shown) {
          expect(a, contains('invoiceIssuedAtText('),
              reason: '$rel يَطبعُ لحظةَ الإصدارِ بلا القاعدة: «$a»');
        }
      }
      expect(printers, {
        'lib/widgets/zatca_invoice_card.dart',
        'lib/screens/admin/admin_invoices_screen.dart',
        'lib/services/zyiarah_pdf_service.dart',
      }, reason: 'سطحٌ رابعٌ يَطبعُ تاريخَ الفاتورة — يُراجَعُ بوعي');
    });

    test('وتاريخُ العقدِ كذلك — نطاقٌ مُشتَقٌّ من مَن يُولّدُ الوثيقة', () {
      // **النطاقُ من الشفرةِ لا من قائمة**: سطوحُ وثيقةِ العقدِ هي التي
      // تُولّدُها أو تُولَّدُ فيها. و`createdAt` اسمٌ عامٌّ في المستودعِ
      // (تذاكرُ الدعمِ مثلاً)، فمسحُه على lib/ كلِّها يُبلِغُ عن سطوحٍ لا
      // علاقةَ لها — وقد فعلَ قبلَ التضييق.
      final surfaces = <String>{};
      for (final f in sourcesIn('$repo/lib', atLeast: 150)) {
        final src = stripComments(f.readAsStringSync());
        if (src.contains('generateAndDownloadContract(')) {
          surfaces.add(f.path.substring(repo.length + 1));
        }
      }
      expect(surfaces, {
        'lib/services/zyiarah_pdf_service.dart',
        'lib/screens/contracts_list_screen.dart',
        'lib/screens/admin/admin_contracts_screen.dart',
      }, reason: 'سطحُ عقدٍ رابعٌ — هل يَطبعُ تاريخَه بالقاعدة؟');

      for (final rel in surfaces) {
        final src = code(rel);
        final shown = callArgs(src, ['Text', 'pw.Text', '_buildTableRow',
                '_buildInfoBit'])
            .where((a) =>
                a.contains('startDate') ||
                RegExp(r'\bcreatedAt\b').hasMatch(a))
            .toList();
        expect(shown, isNotEmpty,
            reason: '$rel لم يَعُدْ يَطبعُ تاريخَ العقد — يُراجَعُ الفحص');
        for (final a in shown) {
          expect(a, contains('ksaDateText('),
              reason: '$rel يَطبعُ تاريخَ العقدِ بلا القاعدة: «$a»');
        }
      }
    });

    test('ولا مُصيِّرَ وثيقةٍ يُنسّقُ تاريخاً بنفسِه', () {
      // **ومجموعةُ المُصيّراتِ مُشتَقّةٌ لا مكتوبةٌ بيد**: هي بالضبطِ مَن
      // يَطبعُ أحدَ تاريخَي الوثيقتَين، وإلّا كان نقصُ مُدخَلٍ منها يُسقِطُ
      // الملفَّ من هذا الفحصِ بصمت.
      final derived = <String>{};
      for (final f in sourcesIn('$repo/lib', atLeast: 150)) {
        final rel = f.path.substring(repo.length + 1);
        final src = stripComments(f.readAsStringSync());
        final shown = callArgs(src,
                ['Text', 'pw.Text', '_kv', '_buildTableRow', '_buildInfoBit'])
            .where((a) =>
                a.contains('issuedAt') ||
                a.contains('startDate') ||
                RegExp(r'\bcreatedAt\b').hasMatch(a))
            .toList();
        if (shown.isEmpty) continue;
        if (!src.contains('generateAndDownloadContract(') &&
            !shown.any((a) => a.contains('issuedAt'))) {
          continue; // تاريخٌ آخرُ على سطحٍ ليس وثيقة (تذكرةُ دعمٍ مثلاً)
        }
        derived.add(rel);
      }
      expect(derived, renderers.keys.toSet(),
          reason: 'مجموعةُ مُصيّراتِ الوثيقةِ تَخالفُ المُشتَقَّ من الشفرة');

      for (final entry in renderers.entries) {
        final src = code(entry.key);
        expect(src.contains('DateFormat('), isFalse,
            reason: '${entry.key} (${entry.value}) يُنسّقُ تاريخاً بنفسِه');
        expect(src, matches(RegExp(r'\b(invoiceIssuedAtText|ksaDateText)\(')),
            reason: '${entry.key} لم يَعُدْ يُنادي القاعدةَ');
      }
    });

    test('والنسخُ المكرَّرةُ من _fmt — المجموعةُ كاملةً بسببِ ما بقي', () {
      const dup =
          "return '\${d.year}/\${two(d.month)}/\${two(d.day)} \${two(d.hour)}:\${two(d.minute)}';";
      final copies = <String>{};
      for (final f in sourcesIn('$repo/lib', atLeast: 150)) {
        if (stripComments(f.readAsStringSync()).contains(dup)) {
          copies.add(f.path.substring(repo.length + 1));
        }
      }
      // كانت **ثلاثاً** متطابقةً بايتاً ببايت. اثنتانِ منها على الفاتورةِ
      // فزالتا؛ والباقيةُ تَطبعُ لحظةَ تعديلِ سياسةٍ لمالكٍ في الرياضِ، ولا
      // نظيرَ آليَّ لها على وثيقةٍ تُخالِفُه — فهي أرضُ **المسحِ العامِّ
      // لعرضِ الوقت**، وهو شريحةٌ أخرى مسجَّلةٌ في CLAUDE.md. تُثبَّتُ هنا
      // كي تَبقى مرئيّةً ولئلّا تَصيرَ رابعةً بصمت.
      //
      // **ولا مضادّةَ على الحجبِ هنا بقصد:** المقابَلةُ على **جسمِ**
      // المُنسّقِ، ووحدةُ القاعدةِ تَقتبسُ أسماءَ `_fmt` لا جسمَه — فالحجبُ
      // غيرُ حاملٍ (مُقاسٌ: قضمةٌ تَحذفُ ذكرَ الاسمِ من الشرحِ لا تُغيّرُ
      // شيئاً)، ومضادّةٌ لا يُمكِنُ أن تَسقطَ ليست مضادّة.
      expect(copies, {'lib/screens/admin/admin_policies_screen.dart'},
          reason: 'نسخةٌ جديدةٌ من مُنسّقِ اللحظةِ المحلّيّ، أو زالت الباقيةُ');
    });

  });

  group('(د) شواهدُ التعليل', () {
    test('رمزُ ZATCA ما زال يُشفّرُ اللحظةَ المطلقة (Tag 3)', () {
      final z = code('lib/services/zatca_service.dart');
      expect(z, contains('timestamp.toUtc().toIso8601String()'),
          reason: 'لو صارَ Tag 3 محلّيّاً لَما بقيَ للمقارنةِ معنًى');
    });

    test('والخادمُ ما زال يَقرأُ الساذجَ بتوقيتِ الرياضِ بالإزاحةِ نفسِها', () {
      final k = read('functions/ksa_time.js');
      expect(k, contains('const KSA_OFFSET_MS = 3 * 60 * 60 * 1000;'),
          reason: 'إزاحةُ الخادمِ تغيّرت — تُراجَعُ kKsaUtcOffset معها');
      expect(k, contains('function parseKsaIso('));
    });

    test('ووثيقةُ العقدِ ما زالت تَبني تاريخَها من لحظةٍ مخزَّنة', () {
      // **بالعددِ لا بالحضور**: الصيغةُ ترِدُ مرّتَين — واحدةً لِـ`createdAt`
      // الذي يُطبَعُ على البطاقة، وأخرى لوسيطِ `startDate` المُمرَّرِ إلى
      // مُولِّدِ الملفّ — فـ`contains` وحدَها يُرضيها بقاءُ إحداهما، وقد
      // مرَّت قضمةٌ تَنزِعُ الثانيةَ **خضراءَ**: «موضعٌ آخرُ يُرضي الفحص».
      final admin = code('lib/screens/admin/admin_contracts_screen.dart');
      expect(
          "(data['createdAt'] as Timestamp?)?.toDate()".allMatches(admin).length,
          2,
          reason: 'مصدرُ تاريخِ العقدِ تغيّر — يُراجَعُ ksaDateText معه');
    });
  });

  group('(هـ) على الشاشةِ فعلاً', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    testWidgets('البطاقةُ تَعرضُ يومَ الرياضِ لا يومَ الجهاز', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: ZatcaInvoiceCard(
                view: InvoiceView(
                  orderCode: 'ZY-202600042',
                  serviceName: 'تنظيف منزلي',
                  total: 230,
                  discount: 0,
                  couponCode: null,
                  // 22:00Z في الثامنِ == الواحدةُ صباحاً في التاسعِ بالرياض.
                  issuedAt: DateTime.utc(2026, 10, 8, 22, 0),
                  paymentMethod: 'card',
                  paymentRef: 'MOY-1',
                  isPaid: true,
                  pdfUrl: null,
                  pdfStatus: null,
                ),
                merchantName: 'م',
                vatNumber: '3',
                crNumber: '7',
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('2026-10-09 01:00 +03'), findsOneWidget);
      expect(find.textContaining('2026-10-08'), findsNothing);
    });
  });
}
