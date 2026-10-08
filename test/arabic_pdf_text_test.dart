import 'dart:io';
import 'dart:typed_data';
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/arabic_pdf_text.dart';
import 'helpers/strip_comments.dart';
import 'helpers/sources_in.dart';

/// **عربيُّ الـPDF: حرفٌ منفصلٌ وحرفٌ ساقط.**
///
/// حزمةُ `pdf` **لا تُشكّلُ** العربيّةَ بإعداداتِها الافتراضيّة
/// (`useBidi = true` ⇒ `useArabic = !useBidi` = false)، فتُعيدُ الترتيبَ
/// البصريَّ وحدَه. فـ`pdf_report_util` — «التقريرُ الماليُّ الرسميُّ» — كان
/// يُسلّمُ العربيّةَ خامّةً فتُطبَعُ **بحروفٍ منفصلة**، بينما
/// `zyiarah_pdf_service` يُشكّلُ في أربعينَ موضعاً.
///
/// **والنصفُ الثاني أخفى: الخطُّ المُضمَّنُ لا يَملكُ أشكالَ الانفصال.**
/// `arabic_reshaper` يُخرِجُ «أشكالَ العرض-ب» (U+FE70–FEFF)، و`Tajawal`
/// يَملكُ أشكالَ البداية/الوسط/النهاية و**لا يَملكُ أشكالَ الانفصالِ**
/// — فكلُّ ألفٍ في أوّلِ كلمةٍ («الرقم»، «المبلغ») وكلُّ تاءٍ مربوطةٍ في
/// آخرِها («فاتورة»، «مؤسسة»، «ضريبية») كانت تُطبَعُ **لا شيئاً**
/// (`.notdef`) على **فاتورةٍ ضريبيّةٍ** وعلى **عقدٍ موقَّع**.
///
/// وهذا الفحصُ **يَشتقُّ الفجوةَ من الخطِّ المُضمَّنِ نفسِه**: يَقرأُ
/// `cmap` ويَحلُّ معرّفَ الرسمةِ لكلِّ شكلٍ يُمكِنُ للمُشكِّلِ أن يُخرِجَه،
/// فلا يُصدّقُ جدولاً مكتوباً بيد. ولو استُبدلَ الخطُّ بآخرَ كاملٍ سقطَ
/// الفحصُ ليُراجَعَ الجدولُ لا ليَبقى.
void main() {
  /// حلُّ معرّفِ الرسمةِ من `cmap` صيغةِ 4 — `0` يَعني `.notdef` أي **لا
  /// رسمةَ**. (وجودُ المحرفِ داخلَ مقطعٍ لا يَكفي: المقطعُ قد يُسنِدُ `0`.)
  int glyphId(Uint8List d, int cp) {
    int u16(int o) => (d[o] << 8) | d[o + 1];
    int i16(int o) {
      final v = u16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    int u32(int o) => (u16(o) << 16) | u16(o + 2);

    final numTables = u16(4);
    var cmap = -1;
    for (var i = 0; i < numTables; i++) {
      final off = 12 + 16 * i;
      final tag = String.fromCharCodes(d.sublist(off, off + 4));
      if (tag == 'cmap') cmap = u32(off + 8);
    }
    expect(cmap, greaterThan(0), reason: 'لا جدولَ cmap في الخطّ');
    final n = u16(cmap + 2);
    var sub = -1;
    for (var i = 0; i < n; i++) {
      final off = u32(cmap + 4 + 8 * i + 4);
      if (u16(cmap + off) == 4) sub = cmap + off;
    }
    expect(sub, greaterThan(0), reason: 'لا جدولَ cmap صيغةِ 4');
    final segX2 = u16(sub + 6);
    final seg = segX2 ~/ 2;
    final endO = sub + 14;
    final startO = endO + segX2 + 2;
    final deltaO = startO + segX2;
    final rangeO = deltaO + segX2;
    for (var i = 0; i < seg; i++) {
      final end = u16(endO + 2 * i);
      if (cp > end) continue;
      final start = u16(startO + 2 * i);
      if (cp < start) return 0;
      final delta = i16(deltaO + 2 * i);
      final ro = u16(rangeO + 2 * i);
      if (ro == 0) return (cp + delta) & 0xFFFF;
      final g = u16(rangeO + 2 * i + ro + 2 * (cp - start));
      return g == 0 ? 0 : (g + delta) & 0xFFFF;
    }
    return 0;
  }

  /// كلُّ شكلٍ يُمكِنُ للمُشكِّلِ أن يُخرِجَه: كلُّ حرفٍ في المواضعِ الأربعة.
  Set<int> emittedForms() {
    const b = 'ب'; // الباءُ تَصِلُ الجهتَين
    final out = <int>{};
    for (var c = 0x0621; c <= 0x064A; c++) {
      final l = String.fromCharCode(c);
      for (final s in <String>[l, '$l$b', '$b$l$b', '$b$l']) {
        out.addAll(ArabicReshaper().reshape(s).codeUnits);
      }
    }
    return out.where((c) => c >= 0xFE70 && c <= 0xFEFF).toSet();
  }

  final fonts = <String, Uint8List>{
    for (final n in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf'])
      n: File('assets/fonts/$n').readAsBytesSync(),
  };

  test('(أ) الخطّانِ مقروءانِ والحروفُ الأساسيّةُ كلُّها فيهما', () {
    expect(fonts.length, 2);
    for (final e in fonts.entries) {
      expect(e.value.length, greaterThan(10000), reason: e.key);
      // أساسُ الفجوةِ: الحرفُ الأساسيُّ موجودٌ دائماً، فالردُّ إليه ممكن.
      for (final base in kPdfIsolatedFallback.values) {
        expect(glyphId(e.value, base), greaterThan(0),
            reason: '${e.key}: الحرفُ الأساسيُّ U+${base.toRadixString(16)} '
                'غيرُ موجود — فالردُّ إليه لا يُصلِح');
      }
    }
  });

  test('(ب) الخريطةُ = فجوةُ الخطِّ بالضبط، مُشتَقّةً لا مكتوبةً بيد', () {
    final forms = emittedForms();
    expect(forms.length, greaterThanOrEqualTo(100),
        reason: 'المُشكِّلُ لم يُخرِجْ أشكالاً — الفحصُ أجوف');
    for (final e in fonts.entries) {
      final missing = forms.where((c) => glyphId(e.value, c) == 0).toSet();
      expect(missing, kPdfIsolatedFallback.keys.toSet(),
          reason: '${e.key}: فجوةُ الخطِّ والخريطةُ افترقتا — '
              'شكلٌ ناقصٌ بلا ردٍّ يُطبَعُ لا شيئاً، '
              'ومُدخَلٌ لشكلٍ يَملكُه الخطُّ يُبدّلُ رسمةً سليمة');
    }
  });

  test('(ج) ولا حرفَ يَسقطُ من نصٍّ حقيقيّ', () {
    const samples = <String>[
      'فاتورة ضريبية مبسطة',
      'مؤسسة معاذ يحي محمد المالكي',
      'الرقم الضريبي',
      'إجمالي المبلغ شامل الضريبة',
      'التقرير المالي الرسمي',
      'سجل آخر المعاملات',
      'بانتظار الدفع',
      'أ ب ة و ر د ذ ز',
    ];
    final reg = fonts['Tajawal-Regular.ttf']!;
    for (final s in samples) {
      // قبل: التشكيلُ وحدَه يُسقِطُ حروفاً.
      final rawReshaped = ArabicReshaper().reshape(s);
      final lost = rawReshaped.codeUnits
          .where((c) => c >= 0xFE70 && c <= 0xFEFF && glyphId(reg, c) == 0)
          .length;
      // بعد: البوّابةُ لا تُخرِجُ محرفاً بلا رسمة.
      final after =
          pdfArabic(s).codeUnits.where((c) => glyphId(reg, c) == 0).toList();
      expect(after, isEmpty,
          reason: '«$s» ما زال يَحملُ محرفاً بلا رسمة: '
              '${after.map((c) => 'U+${c.toRadixString(16)}').join(', ')}');
      if (s.contains('فاتورة') || s.contains('الرقم')) {
        expect(lost, greaterThan(0),
            reason: 'لو صفرَ لَما كان العطلُ قائماً — فالفحصُ يَحرُسُ وهماً');
      }
    }
  });

  test('(د) والتشكيلُ يَحدثُ فعلاً — ليست دالّةَ عبور', () {
    expect(pdfArabic('الرقم') == 'الرقم', isFalse,
        reason: 'البوّابةُ لا تُشكّلُ — فالحروفُ تُطبَعُ منفصلة');
    expect(pdfArabic(''), '');
    expect(pdfArabic('ZY-12345'), 'ZY-12345', reason: 'اللاتينيُّ لا يُمَسّ');
    // وطولُ النصِّ لا يَتغيّر (استبدالٌ محرفاً بمحرف).
    expect(pdfArabic('فاتورة').length, 'فاتورة'.length);
  });

  group('والبوّابةُ واحدةٌ لمسارَي الـPDF', () {
    String code(String p) => stripComments(File(p).readAsStringSync());

    test('(ه) لا نداءَ مباشرَ للمُشكِّلِ خارجَ البوّابة', () {
      final offenders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        if (f.path.endsWith('arabic_pdf_text.dart')) continue;
        if (code(f.path).contains('ArabicReshaper(')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'تشكيلٌ خارجَ البوّابةِ يَتخطّى ردَّ أشكالِ الانفصال:\n'
              '${offenders.join('\n')}');
    });

    test('(و) ومسارا الـPDF كلاهما يُنادِيانِها', () {
      expect(
          code('lib/services/zyiarah_pdf_service.dart'), contains('pdfArabic('),
          reason: 'الفاتورةُ لا تَمُرُّ بالبوّابة');
      final report = code('lib/utils/pdf_report_util.dart');
      expect(report, contains('pdfArabic('),
          reason: 'التقريرُ الماليُّ لا يُشكّلُ أصلاً');
      // وكلُّ نصٍّ عربيٍّ في التقريرِ مُشكَّلٌ: لا `pw.Text('عربي'` عارياً.
      final bare = RegExp(r"pw\.Text\(\s*'[^']*[ء-ي]")
          .allMatches(report)
          .map((m) => m.group(0)!)
          .toList();
      expect(bare, isEmpty,
          reason: 'نصٌّ عربيٌّ يُسلَّمُ خامّاً إلى pw.Text:\n'
              '${bare.join('\n')}');
    });

    test('(ز) ومضادَّةُ فرطِ الحجب: شرحُ القرارِ في الخامّ', () {
      final raw = File('lib/utils/arabic_pdf_text.dart').readAsStringSync();
      for (final t in ['useArabic', 'notdef', 'U+FE70']) {
        expect(raw, contains(t),
            reason: 'زالَ شرحُ العطلِ، فلا يَعرفُ قارئٌ ما تَحرُسُه الخريطة');
      }
    });
  });
}
