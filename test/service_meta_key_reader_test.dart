// حارس: **كلُّ مفتاحٍ يَكتبُه العميلُ في `service_meta` له قارئ.**
//
// `service_meta` خريطةٌ يَبنيها جهازُ العميلةِ في خمسِ شاشاتِ حجزٍ، ويَقرؤها
// ثلاثةُ أسطح: `lib/widgets/service_meta_view.dart` (جدولُ التفاصيلِ عند
// الأدمنِ والسائقِ، وملخّصُ البطاقة)، و`admin_panel/src/utils/serviceMeta.ts`
// (مرآتُه المُعلَنة)، و`functions/pricing.js` (يُعيدُ التسعيرَ من مستندِ
// المنطقةِ ومن `products`).
//
// **ومسحٌ مُشتَقٌّ وجدَ أربعةَ مفاتيحَ بلا قارئٍ في المستودعِ كلِّه** — في
// `lib/` و`functions/` و`admin_panel/src/` و`test/` معاً:
//
//   • `materials_total`    (home_package)
//   • `total_area_sqm`     (sofa_rug_sqm)
//   • `sofa_price_per_sqm` (sofa_rug_sqm)
//   • `rug_price_per_sqm`  (sofa_rug_sqm)
//
// وأربعتُها **مُستخرَجةٌ من الصفوفِ نفسِها** التي في الحِملِ: `SqmPiece.toMap`
// يَحملُ `area_sqm` و`price_per_unit` لكلِّ صفّ، وصفوفُ المواد تَحملُ
// `quantity` و`price`. فهي تكرارٌ لا «توصيلٌ مَنسيّ». وثلاثةٌ منها **أرقامُ
// مالٍ يَكتبُها العميلُ ولا يُحقّقُها شيء** — شكلُ `amount` و`discount_amount`
// و`final_amount` بعينِه: مَن يُضيفُ غداً سطرَ مجموعٍ أو عمودَ تصديرٍ يَقرأُ
// رقماً يَضبطُه الجهاز.
//
// **و`total_area_sqm` اسمُه يُخالِفُ محتواه**: تعليقُ `totalArea` في مصدرِه
// يَقولُ «مساحةُ السجادِ الإجماليّة… الكنبُ يُسعَّر بالطولِ فلا يَدخلُها»،
// فهو مجموعُ مساحةِ السجادِ وحدَه تحتَ اسمٍ يَقولُ «المساحةُ الإجماليّة» —
// فتوصيلُه إلى عرضٍ كان سيُظهِرُ رقماً يُسقِطُ الكنبَ تحتَ عنوانٍ يَزعمُ
// الكلّ. وكان مكتوباً «للإحصاء فقط» في تعليقِه، والإحصاءُ بلا جامع.
//
// و`no_dead_code_test` **لا يَرى الحقول** (دوالُّ وجوالبُ فقط)، وهذا سببُ
// نجاتِها — فهذا الحارسُ هو القارئُ الذي كان ناقصاً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// القُرّاءُ الثلاثةُ لـ`service_meta` — بأسمائهم، ولكلٍّ دورُه.
const Map<String, String> _readers = {
  'lib/widgets/service_meta_view.dart':
      'جدولُ التفاصيلِ وملخّصُ البطاقةِ عند الأدمنِ والسائق',
  'admin_panel/src/utils/serviceMeta.ts': 'مرآةُ الجدولِ في لوحةِ الويب',
  'functions/pricing.js': 'إعادةُ التسعيرِ خادميّاً',
};

/// نهايةُ كتلةٍ تَبدأُ عند [b] (حيث `s[b] == '{'`) بموازنةِ المعقوفة.
int _blockEnd(String s, int b) {
  var d = 0;
  for (var k = b; k < s.length; k++) {
    if (s[k] == '{') {
      d++;
    } else if (s[k] == '}') {
      d--;
      if (d == 0) return k;
    }
  }
  return -1;
}

/// كلُّ حِملِ `service_meta` في شاشاتِ الحجز، بمفاتيحِه العُلويّة.
///
/// **النطاقُ مُشتَقٌّ**، والشكلانِ معاً: `serviceMeta: { … }` مباشرةً
/// (`hourly_details`) و`final meta = { … }` ثمّ `serviceMeta: meta`
/// (الأربعُ الأخرى) — فالمِرساةُ هي الحِملُ لا موضعُ التمرير.
///
/// ويُشتَرَطُ **تمريرٌ فعليٌّ** إلى `serviceMeta:` في الملفِّ نفسِه: مِرساةُ
/// `'kind':` وحدَها تَلتقطُ حِملَي البثِّ الإداريِّ (`popup` و
/// `compliance_alert`) وهما مجموعةٌ أخرى بقُرّاءٍ آخرين.
Map<String, Set<String>> serviceMetaWrites() {
  final out = <String, Set<String>>{};
  for (final f in sourcesIn('lib/screens', atLeast: 30)) {
    final src = stripComments(f.readAsStringSync());
    if (!src.contains('serviceMeta:')) continue;
    for (final m in RegExp(r"'kind'\s*:\s*'([a-z_]+)'").allMatches(src)) {
      // اصعدْ إلى المعقوفةِ الحاويةِ لهذا المفتاح.
      var close = 0, i = m.start - 1, open = -1;
      while (i >= 0) {
        final c = src[i];
        if (c == '}') {
          close++;
        } else if (c == '{') {
          if (close == 0) {
            open = i;
            break;
          }
          close--;
        }
        i--;
      }
      if (open == -1) continue;
      final end = _blockEnd(src, open);
      if (end < 0) continue;
      final blk = src.substring(open, end + 1);
      for (final km in RegExp(r"'([A-Za-z_]\w*)'\s*:").allMatches(blk)) {
        final seg = blk.substring(0, km.start);
        // مفتاحٌ عُلويٌّ: عمقٌ واحدٌ داخلَ الحِمل (لا داخلَ صفٍّ متداخل).
        if ('{'.allMatches(seg).length - '}'.allMatches(seg).length == 1) {
          out.putIfAbsent(km.group(1)!, () => <String>{}).add(f.path);
        }
      }
    }
  }
  return out;
}

void main() {
  group('كلُّ مفتاحِ service_meta له قارئ', () {
    final writes = serviceMetaWrites();
    final readerSrc = {
      for (final p in _readers.keys)
        p: p.endsWith('.dart')
            ? stripComments(File(p).readAsStringSync())
            : File(p).readAsStringSync(),
    };

    test('(أ) ولا مفتاحَ بلا قارئٍ في الأسطحِ الثلاثة', () {
      // أرضيّةٌ: مسحٌ يَنحلُّ إلى صفرٍ يَمرُّ أخضرَ أجوفَ.
      expect(writes.length, greaterThanOrEqualTo(10),
          reason: 'انحلَّ مسحُ حِملِ service_meta — وجدَ ${writes.length} مفتاحاً');
      final orphans = <String>[];
      for (final k in writes.keys) {
        // **حدٌّ للكلمةِ في `.$k` كذلك**: `.kindX` يَحتوي `.kind`، فالاحتواءُ
        // وحدَه يَقرأُ قارئاً زائلاً «ما زال يَقرأ».
        final dot = RegExp(r'\.' + RegExp.escape(k) + r'\b');
        final seen = readerSrc.values.any((s) =>
            s.contains("'$k'") || s.contains('"$k"') || dot.hasMatch(s));
        if (!seen) orphans.add('$k ← ${writes[k]!.map((p) => p.split('/').last).join(", ")}');
      }
      expect(orphans, isEmpty,
          reason: '\n\nمفتاحٌ يَكتبُه العميلُ في service_meta ولا يَقرؤه أحد. '
              'إمّا أن يُقرَأَ أو يُحذَف — وإن كان رقمَ مالٍ فبقاؤه فخٌّ '
              'لمَن يُوصّلُه غداً إلى عرضٍ أو تصدير:\n  • ${orphans.join("\n  • ")}\n');
    });

    test('(ب) والأربعةُ المحذوفةُ لا تَعود', () {
      // حُذفت في 2026-10-08؛ عودةُ أيٍّ منها تَعني رقماً بلا قارئٍ من جديد.
      for (final k in const [
        'materials_total',
        'total_area_sqm',
        'sofa_price_per_sqm',
        'rug_price_per_sqm',
      ]) {
        expect(writes.containsKey(k), isFalse, reason: 'عادَ المفتاحُ $k بلا قارئ');
      }
      // والبديلُ الذي يَجعلُ حذفَها سليماً: الصفوفُ تَحملُ ما يَلزم.
      final piece = stripComments(File('lib/models/sqm_piece.dart').readAsStringSync());
      expect(piece, contains("'area_sqm'"),
          reason: 'صفُّ القطعةِ لم يَعُد يَحملُ مساحتَه — فحذفُ المجموعِ يُراجَع');
      expect(piece, contains("'price_per_unit'"),
          reason: 'صفُّ القطعةِ لم يَعُد يَحملُ سعرَ وحدتِه — فحذفُ السعرَين يُراجَع');
    });

    test('(ج) والقُرّاءُ الثلاثةُ ما زالوا يَقرؤون — وإلّا الفحصُ أجوف', () {
      for (final e in _readers.entries) {
        expect(File(e.key).existsSync(), isTrue, reason: '${e.key} زالَ (${e.value})');
        // **حدٌّ للكلمةِ لا احتواء**: `kindX` يَحتوي `kind`، فمرَّ اختبارُ
        // قضمٍ أعادَ تسميةَ المفتاحِ في القارئِ **أخضرَ** — فخُّ
        // `packageFormErrorX` بعينِه.
        expect(RegExp(r'\bkind\b').hasMatch(readerSrc[e.key]!), isTrue,
            reason: '${e.key} لم يَعُد يَتفرّعُ على kind — ${e.value}');
      }
      // ومِرساةُ النطاقِ: حِملُ البثِّ الإداريِّ ليس service_meta.
      expect(writes.containsKey('sent_by'), isFalse,
          reason: 'التقطَ المسحُ حِملَ البثِّ الإداريِّ (popup/compliance_alert) '
              '— مجموعةٌ أخرى بقُرّاءٍ آخرين');
    });
  });
}
