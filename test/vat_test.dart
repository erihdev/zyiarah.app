// فحص خاصيّة لا أمثلة: يثبت أن دوال `lib/utils/vat.dart` تُعيد **نفس** ما كانت
// تُعيده الصيغ الحرفية المكتوبة يدوياً في سبعة عشر ملفاً قبل التوحيد، على نطاق
// أسعار واقعي كامل — لا على قيمٍ مختارة تُخفي الانحراف عند الحدود.
//
// الغرض ليس التأكّد أن ٠.١٥ تساوي ٠.١٥، بل إثبات أن `1 + 0.15` و`1.15` واحدٌ
// في IEEE754 (كلاهما 1.1499999999999999112) فلا يتسلّل فرقٌ في آخر بتة يقلب
// حدَّ تقريب فيغيّر قرشاً. والقرش هنا ليس تجميلاً: التسعير الخادمي يقارن المدفوع
// بالمتوقَّع بسماحية `> 0.01`، فانحرافٌ على الحدّ = رفض دفعٍ سليم أو قبول ناقص.
//
// ويثبّت أيضاً أن النسبة لم تعد مكتوبة يدوياً في أي ملف حيّ — مع استثناء صريح
// للقيم التي تساوي 0.15 أو 1.15 عرَضاً ولا علاقة لها بالضريبة (شفافية الألوان
// `withValues(alpha: 0.15)`، و`childAspectRatio: 1.15`، وإزاحات إحداثيات
// الخريطة). سقوط هذا الفحص يعني موضعاً جديداً يفلت من المصدر الموحَّد.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/vat.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// القيم التي يُسمح أن تحمل 0.15 أو 1.15 وليست ضريبة.
final _notVat = RegExp(
  r'withValues\(\s*alpha:|withOpacity\(|childAspectRatio:|'
  r'latitude|longitude|LatLng\(',
);

void main() {
  group('المصدر الموحَّد للضريبة', () {
    test('النسبة ١٥٪ والمعامل يطابق الحرفيّ بتةً ببتة', () {
      expect(kVatRate, 0.15);
      expect(kVatMultiplier, 1.15);
      // ليس تحصيلَ حاصل: 0.15 و1.15 غير قابلين للتمثيل تماماً، والمطلوب أن
      // يكون ناتج الجمع هو **نفس** المضاعف الحرفيّ المستعمل قبل التوحيد.
      expect(1 + kVatRate == 1.15, isTrue);
    });

    test('netFromGross يطابق `x / 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(netFromGross(x), x / 1.15, reason: 'انحراف عند $x');
      }
    });

    test('vatInGross يطابق `x - x / 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(vatInGross(x), x - x / 1.15, reason: 'انحراف عند $x');
      }
    });

    test('vatOnBase يطابق `x * 0.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(vatOnBase(x), x * 0.15, reason: 'انحراف عند $x');
      }
    });

    test('grossFromBase يطابق `x * 1.15` الحرفية', () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(grossFromBase(x), x * 1.15, reason: 'انحراف عند $x');
      }
    });

    test('grossFromBaseRounded يطابق `((x * 1.15) * 100).roundToDouble() / 100`',
        () {
      for (var i = 0; i <= 200000; i += 7) {
        final x = i / 100;
        expect(
          grossFromBaseRounded(x),
          ((x * 1.15) * 100).roundToDouble() / 100,
          reason: 'انحراف عند $x',
        );
      }
    });

    test('النموذجان متّسقان: netFromGross يعكس grossFromBase', () {
      // الضريبة فوق الأساس ثم استخراجها من الإجمالي يعود إلى الأساس — في حدود
      // دقّة التعويم. يثبّت أن الدالتين تصفان نموذجاً واحداً لا نموذجين.
      for (var i = 1; i <= 200000; i += 97) {
        final base = i / 100;
        expect(netFromGross(grossFromBase(base)), closeTo(base, 1e-9));
      }
    });

    test('لا نسبة مكتوبة يدوياً في أي ملف حيّ', () {
      final offenders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        if (f.path == 'lib/utils/vat.dart') continue;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final idx = lines[i].indexOf('//');
          final code = idx == -1 ? lines[i] : lines[i].substring(0, idx);
          if (!RegExp(r'\b1\.15\b|\b0\.15\b').hasMatch(code)) continue;
          if (_notVat.hasMatch(code)) continue;
          offenders.add('${f.path}:${i + 1}: ${code.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'النسبة عادت مكتوبة يدوياً — استورد lib/utils/vat.dart:\n'
            '${offenders.join('\n')}',
      );
    });
  });

  _vatLabelGuards();
}

// ── النسبةُ كما تُقرَأُ ──────────────────────────────────────────────────────
//
// الحسابُ وُحِّدَ (الفحوصُ أعلاه)، **والتسميةُ المرئيّةُ لم تُوحَّد**: «15%» كانت
// مكتوبةً بيدٍ في سبعةَ عشَرَ موضعاً فوقَ `kVatRate` الواحدة. فتغييرُ النسبةِ
// يُصلِحُ الحسابَ ويَترُكُ سبعةَ عشَرَ نصّاً يَقولُ 15% — ومنها **أربعةٌ على
// وثيقةِ الفاتورةِ الضريبيّةِ المبسّطة** (ثلاثٌ في البطاقةِ وواحدةٌ في الملفّ)،
// والنسبةُ هناك حقلٌ نظاميٌّ: فاتورةٌ تُعلِنُ نسبةً تُخالِفُ حسابَها هي.
//
// ولا انحرافَ اليومَ — السبعةَ عشَرَ كلُّها 15% والنسبةُ 0.15 — فالتوحيدُ
// **وقائيٌّ** كشريحةِ `slots.js`، والحارسُ هو ما يُبقيه كذلك.

/// التسميةُ الحرفيّةُ للنسبةِ في نصٍّ مرئيّ: `15%` أو `١٥%` أو `% 15`.
final _handWrittenRate = RegExp(r'15\s*%|١٥\s*%|%\s*15');

/// مواضعُ تَحملُ الشكلَ وليست نسبةَ ضريبةٍ — **بسببٍ مكتوبٍ لكلِّ واحدة**.
const _notVatLabel = <String, String>{
  'lib/screens/admin/admin_settings_screen.dart':
      'مثالُ **نسبةِ الذروة** لا الضريبة: الحقلُ `_surgePercentCtrl` وعنوانُه '
          '«نسبة سعر الذروة (%)»، و«مثال: 15 = زيادة 15%» توضيحُ مدخلٍ يَكتبُه '
          'المالكُ بيدِه ولا علاقةَ له بـ`kVatRate`.',
};

void _vatLabelGuards() {
  group('النسبةُ المرئيّةُ مُشتَقّةٌ لا مكتوبة', () {
    final vatSrc = File('lib/utils/vat.dart').readAsStringSync();

    test('(أ) التسميةُ تُطابقُ النسبةَ — سلوكاً', () {
      expect(kVatRateLabel.endsWith('%'), isTrue);
      final digits = kVatRateLabel.substring(0, kVatRateLabel.length - 1);
      expect(double.parse(digits), closeTo(kVatRate * 100, 1e-9),
          reason: 'التسميةُ انحرفت عن النسبة — وهي ما يُطبَعُ على الفاتورة');
      // اليومَ: لا ذيلَ عشريٌّ من ضوضاءِ IEEE754 (`0.15 * 100`).
      expect(kVatRateLabel, '15%');
    });

    test('(ب) ومُشتَقّةٌ بنيويّاً — لا حرفيٌّ يُوافقُ بالمصادفة', () {
      // الفحصُ (أ) وحدَه يَمُرُّ على `'15%'` مكتوبةً بيدٍ ما دامت النسبةُ 0.15.
      final i = vatSrc.indexOf('kVatRateLabel =');
      expect(i, greaterThan(0));
      final init = vatSrc.substring(i, vatSrc.indexOf(';', i));
      expect(init.contains('kVatRate'), isTrue,
          reason: 'التسميةُ لا تَقرأُ النسبة — فتغييرُها لا يَبلغُ الفاتورة');
      expect(_handWrittenRate.hasMatch(init), isFalse,
          reason: 'نسبةٌ مكتوبةٌ في مُهيِّئِ التسميةِ نفسِه');
    });

    test('(ج) والجملةُ المعيارُ تَستقرِئُ التسميةَ لا الرقم', () {
      final i = vatSrc.indexOf('kVatAddedAtPaymentNotice =');
      expect(i, greaterThan(0));
      final init = vatSrc.substring(i, vatSrc.indexOf(';', i));
      expect(init.contains(r'$kVatRateLabel'), isTrue);
      expect(_handWrittenRate.hasMatch(init), isFalse);
    });

    test('(د) لا تسميةً مكتوبةً بيدٍ في نصٍّ مرئيّ — المجموعةُ كاملةً', () {
      // `stripComments` يَحجبُ التعليقاتِ **ويَحفظُ النصوص**: المقصودُ ما
      // تَقرؤه العميلةُ، وتعليقٌ يَشرحُ القرارَ بذكرِ «15%» ليس تسميةً.
      final offenders = <String, List<String>>{};
      for (final f in sourcesIn('lib', atLeast: 100)) {
        if (f.path == 'lib/utils/vat.dart') continue;
        final code = stripComments(f.readAsStringSync());
        final hits = <String>[];
        for (final m in _handWrittenRate.allMatches(code)) {
          final ln = code.substring(0, m.start).split('\n').length;
          hits.add('$ln');
        }
        if (hits.isNotEmpty) offenders[f.path] = hits;
      }
      expect(offenders.keys.toSet(), _notVatLabel.keys.toSet(),
          reason: 'موضعٌ يَكتبُ النسبةَ بيدٍ — استعمل `kVatRateLabel`:\n'
              '${offenders.entries.map((e) => '${e.key}:${e.value.join(",")}').join('\n')}');
    });

    test('(هـ) والكاشفُ يَعضُّ — يُجرَّبُ على الأشكالِ الثلاثة', () {
      // المصدرُ بعدَ التوحيدِ نظيفٌ، فنجاحُ (د) وحدَه لا يُبرهِنُ أنّ الكاشفَ
      // يَرى شيئاً. ومعه نفيُ إيجابيّةٍ كاذبة: `0.15` حسابيّةٌ ليست تسمية.
      for (final s in ["Text('ضريبة 15%')", "Text('١٥%')", "Text('% 15')"]) {
        expect(_handWrittenRate.hasMatch(s), isTrue, reason: s);
      }
      for (final s in ['vatOnBase(x)', 'alpha: 0.15', 'base * 1.15']) {
        expect(_handWrittenRate.hasMatch(s), isFalse, reason: s);
      }
      // وحجبُ التعليقاتِ حاملٌ: تعليقٌ يَذكرُ النسبةَ لا يُسقِطُ (د).
      expect(_handWrittenRate.hasMatch(stripComments('// الضريبة 15% فوق')),
          isFalse);
      expect(_handWrittenRate.hasMatch(stripComments("x('الضريبة 15%');")),
          isTrue, reason: 'النصُّ يُحفَظُ — وإلّا صارَ (د) أخضرَ أجوف');
    });

    test('(و) مجموعةُ قارئي التسميةِ كاملةً — موضعٌ يَفقدُها يُراجَع', () {
      final readers = <String>{};
      for (final f in sourcesIn('lib', atLeast: 100)) {
        if (f.path == 'lib/utils/vat.dart') continue;
        final code = stripComments(f.readAsStringSync());
        if (code.contains('kVatRateLabel') ||
            code.contains('kVatAddedAtPaymentNotice')) {
          readers.add(f.path);
        }
      }
      expect(readers, {
        // شاشاتُ الحجزِ الخمس: الجملةُ المعيار
        'lib/screens/ac_service_details_screen.dart',
        'lib/screens/car_interior_details_screen.dart',
        'lib/screens/hourly_details_screen.dart',
        'lib/screens/sofa_rug_details_screen.dart',
        'lib/screens/store_schedule_screen.dart',
        // سلّةُ المتجر: جملتانِ (مسارُ الشركاتِ ومسارُ العميلة)
        'lib/screens/store_screen.dart',
        // صفُّ الضريبةِ في شاشتَي الدفع
        'lib/screens/payment_summary_screen.dart',
        'lib/screens/store_payment_screen.dart',
        // الأسطحُ الإداريّة
        'lib/screens/admin/admin_analytics_screen.dart',
        'lib/screens/admin/admin_insights_screen.dart',
        'lib/screens/admin/admin_invoices_screen.dart',
        'lib/utils/pdf_report_util.dart',
        // وثيقةُ الفاتورةِ الضريبيّة
        'lib/services/zyiarah_pdf_service.dart',
        'lib/widgets/zatca_invoice_card.dart',
      }, reason: 'قارئٌ جديدٌ أو مفقود — راجع قبل تعديل الحارس');
    });

    test('(ز) والجملةُ المعيارُ لخمسِ شاشاتٍ بعينِها', () {
      final users = <String>{};
      for (final f in sourcesIn('lib/screens', atLeast: 40)) {
        if (stripComments(f.readAsStringSync())
            .contains('kVatAddedAtPaymentNotice')) {
          users.add(f.path);
        }
      }
      expect(users, {
        'lib/screens/ac_service_details_screen.dart',
        'lib/screens/car_interior_details_screen.dart',
        'lib/screens/hourly_details_screen.dart',
        'lib/screens/sofa_rug_details_screen.dart',
        'lib/screens/store_schedule_screen.dart',
      }, reason: 'شاشةٌ سادسةٌ كتبت جملتَها، أو خامسةٌ فقدتها');
    });

    test('(ح) وثيقةُ الفاتورةِ الضريبيّةِ ما زالت تُعلِنُ النسبة', () {
      // تعليلُ الشريحةِ قائمٌ على أنّ النسبةَ حقلٌ مُعلَنٌ على وثيقةِ ZATCA.
      // فلو كَفَّ أيُّ سطحٍ منهما عن طبعِها يُراجَعُ التعليلُ لا يُسكَت.
      final card =
          stripComments(File('lib/widgets/zatca_invoice_card.dart')
              .readAsStringSync());
      expect(r'$kVatRateLabel'.allMatches(card).length, 3,
          reason: 'بطاقةُ الفاتورة: البند، وصفُّ الضريبة، وسطرُ «شامل»');
      final pdf = stripComments(
          File('lib/services/zyiarah_pdf_service.dart').readAsStringSync());
      expect(pdf.contains(r'VAT ($kVatRateLabel)'), isTrue,
          reason: 'ملفُّ الفاتورةِ المبسّطة');
    });

    test('(ط) ولا نظيرَ يَلزمُ خادميّاً ولا في اللوحة — نتيجةٌ سالبةٌ مشدودة', () {
      // الخادمُ لا يَطبعُ النسبةَ في أيِّ نصٍّ يَقرؤه إنسان (الدفعاتُ والبريد)،
      // واللوحةُ لا تَعرضُها — فمرآةٌ لـ`kVatRateLabel` هناك تصديرٌ بلا مُنادٍ،
      // وهو ما يَرفُضُه `no_dead_code_test` على الجهةِ الأخرى. فلو ظهرَ نصٌّ
      // يُعلِنُ النسبةَ في أيٍّ منهما فالقرارُ يُراجَعُ لا يُسكَت.
      final offenders = <String>[];
      for (final f in [
        ...sourcesIn('functions', atLeast: 10, exts: ['.js'])
            .where((f) => !f.path.contains('node_modules') &&
                !f.path.contains('/test/')),
        ...sourcesIn('admin_panel/src', atLeast: 20, exts: ['.ts', '.tsx'])
            .where((f) => !f.path.contains('.test.')),
      ]) {
        final code = stripComments(f.readAsStringSync());
        if (_handWrittenRate.hasMatch(code)) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'نسبةٌ مرئيّةٌ ظهرت خارجَ `lib/` — راجع قرارَ «لا مرآة»:\n'
              '${offenders.join('\n')}');
    });
  });
}
