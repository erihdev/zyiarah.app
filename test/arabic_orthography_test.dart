// حارسٌ دائم: **صيغةٌ شاذّةٌ في نصٍّ تَقرؤه العميلة.**
//
// وُجدَ بتشغيلِ التطبيقِ (2026-10-07): شاشةُ الدخولِ تُسمّي الحقلَ **«كلمه
// المرور»** بهاءٍ، وفي الشاشةِ نفسِها «نسيت **كلمة** المرور؟» و«و**كلمة**
// المرور» — فالخطأُ يُقرأُ أوّلَ ما تُفتَحُ الشاشة، وتُناقضُه الشاشةُ نفسُها
// سطرَين أعلاه. وشاشةُ التسجيلِ تَحملُ أربعةً («كلمه»، «تاكيد»، «البريد
// الالكتروني»، «انشاء») — وهما **أوّلُ شاشتَين** يَراهما كلُّ مستخدمٍ
// جديدٍ، ومُراجِعُ أبل كذلك.
//
// **والحكمُ مُشتَقٌّ من المستودعِ لا من قائمةٍ مُختَرَعة**، وهذا هو بيتُ
// القصيد: لكلِّ كلمةٍ عربيّةٍ في نصٍّ **مرئيّ** تُولَّدُ صِيَغُها المتغيّرةُ
// (هاءٌ/تاءٌ مربوطة، وألفٌ/همزةٌ في أوّلِها أو بعدَ «ال»)، فإن كانت إحداها
// غالبةً غلبةً ساحقةً والأخرى نادرةً فالنادرةُ شاذّة. فلا رأيَ لي في
// الإملاءِ هنا: المستودعُ هو الحَكَم — «كلمة»×١٠ مقابلَ «كلمه»×٣،
// و«إنشاء»×١٦ مقابلَ «انشاء»×٢، و«تأكيد»×٣٦ مقابلَ «تاكيد»×١.
//
// ويُستثنى من المسحِ: التعليقاتُ (تَشرحُ الخطأَ فتَحملُه)، وملفّاتُ الفحصِ،
// وأسماءُ الحقولِ والمعرّفاتُ (ليست نصّاً مرئيّاً).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _ar = r'ء-ي';

/// كلُّ نصٍّ حرفيٍّ فيه عربيّةٌ، بلا أسطرِ التعليق.
Iterable<(String, int, String)> _visibleLiterals() {
  final out = <(String, int, String)>[];
  const roots = <String, List<String>>{
    'lib': ['.dart'],
    'admin_panel/src': ['.ts', '.tsx'],
    'landing_page': ['.html'],
  };
  for (final e in roots.entries) {
    final d = Directory(e.key);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      final name = f.path.split('/').last;
      if (!e.value.any(name.endsWith)) continue;
      if (name.contains('.test.') || name.endsWith('_test.dart')) continue;
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
          continue;
        }
        for (final m
            in RegExp(r"""(['"])((?:\\.|(?!\1)[^\\])*)\1""").allMatches(lines[i])) {
          final s = m.group(2)!;
          if (RegExp('[$_ar]').hasMatch(s)) out.add((f.path, i + 1, s));
        }
      }
    }
  }
  return out;
}

/// الصِيَغُ المتغيّرةُ لكلمةٍ — هاءٌ/تاءٌ مربوطة، وألفٌ/همزةٌ أوّلاً أو بعدَ «ال».
Set<String> _variants(String w) {
  final out = <String>{};
  if (w.endsWith('ه')) out.add('${w.substring(0, w.length - 1)}ة');
  if (w.endsWith('ة')) out.add('${w.substring(0, w.length - 1)}ه');
  final rest = w.length > 1 ? w.substring(1) : '';
  if (w.startsWith('ا')) {
    out..add('إ$rest')..add('أ$rest');
  }
  if (w.startsWith('إ') || w.startsWith('أ')) out.add('ا$rest');
  // **وبعدَ «ال» كذلك** — وهذه هي الحالةُ التي فاتت أوّلَ صياغةٍ فأخفت
  // «البريد الالكتروني» و«باقات الإشتراك»: المُولِّدُ كان يَنظرُ في الحرفِ
  // الأوّلِ وحدَه.
  if (w.length > 2 && w.startsWith('ال')) {
    final tail = w.substring(3);
    final c = w[2];
    if (c == 'ا') out..add('الإ$tail')..add('الأ$tail');
    if (c == 'إ' || c == 'أ') out.add('الا$tail');
  }
  return out..remove(w);
}

/// الصِيَغُ الشاذّة: نادرةٌ (≤٣) مقابلَ غالبةٍ (≥أربعةِ أضعافِها).
List<String> _oddForms({Map<String, int>? inject}) {
  final counts = <String, int>{};
  final where = <String, List<String>>{};
  for (final (p, ln, s) in _visibleLiterals()) {
    for (final m in RegExp('[$_ar]+').allMatches(s)) {
      final w = m.group(0)!;
      counts[w] = (counts[w] ?? 0) + 1;
      (where[w] ??= <String>[]).add('$p:$ln');
    }
  }
  inject?.forEach((k, v) {
    counts[k] = (counts[k] ?? 0) + v;
    (where[k] ??= <String>[]).add('<حقنُ فحصٍ>');
  });
  final out = <String>[];
  counts.forEach((w, c) {
    if (c > 3) return;
    for (final v in _variants(w)) {
      final cv = counts[v] ?? 0;
      if (cv >= c * 4) {
        out.add('«$w»×$c ⇐ «$v»×$cv  @ ${where[w]!.take(3).join(", ")}');
        return;
      }
    }
  });
  out.sort();
  return out;
}

void main() {
  group('إملاءُ النصِّ المرئيّ', () {
    test('(أ) لا صيغةَ شاذّةً يُناقضُها المستودعُ نفسُه', () {
      expect(_oddForms(), isEmpty,
          reason: 'صيغةٌ نادرةٌ والمستودعُ يَكتبُ غيرَها أربعةَ أضعافٍ على '
              'الأقلّ — فإمّا خطأٌ إملائيٌّ في نصٍّ تَقرؤه العميلة، أو '
              'كلمةٌ جديدةٌ تَستحقُّ أن تُوحَّدَ مع إخوتِها');
    });

    test('(ب) والكاشفُ يَعضُّ — حقنٌ صناعيٌّ يَجبُ أن يُلتقَط', () {
      // بلا هذا يَكونُ (أ) أخضرَ لأنّ المسحَ لم يَجدْ شيئاً، لا لأنّ النصَّ
      // سليم. وكلُّ صنفٍ يُحقَنُ وحدَه كي لا يُخفيَ عطلُ أحدِهما الآخرَ.
      expect(_oddForms(inject: {'كلمه': 1}), isNotEmpty,
          reason: 'هاءٌ مكانَ تاءٍ مربوطة');
      expect(_oddForms(inject: {'انشاء': 1}), isNotEmpty,
          reason: 'ألفٌ مكانَ همزة');
      expect(_oddForms(inject: {'الالكتروني': 1}), isNotEmpty,
          reason: 'همزةٌ بعدَ «ال» — وهي الحالةُ التي فاتت أوّلَ صياغة');
      expect(_oddForms(inject: {'الإشتراك': 1}), isNotEmpty,
          reason: 'همزةٌ زائدةٌ بعدَ «ال»');
    });

    test('(ج) والمسحُ يَقرأُ نصوصاً فعلاً', () {
      final lits = _visibleLiterals().toList();
      expect(lits.length, greaterThanOrEqualTo(400),
          reason: 'انهارَ المسح: ${lits.length} نصّاً — '
              'حارسٌ لا يَقرأُ شيئاً أسوأُ من لا حارس');
      // ومرجعٌ حقيقيٌّ من الشاشةِ التي كشفت العطل.
      expect(
          lits.any((e) =>
              e.$1 == 'lib/screens/login_screen.dart' && e.$3.contains('كلمة المرور')),
          isTrue);
    });

    test('(د) ولا مسافةَ قبلَ علامةِ ترقيمٍ عربيّة', () {
      // «ليس لديك حساب ؟» — العربيّةُ لا تَفصلُ العلامةَ عن الكلمة.
      final bad = <String>[];
      for (final (p, ln, s) in _visibleLiterals()) {
        if (RegExp('[$_ar][ ]+[؟!،؛]').hasMatch(s)) bad.add('$p:$ln  «$s»');
      }
      expect(bad, isEmpty, reason: 'مسافةٌ قبلَ علامةِ ترقيم');
    });
  });
}
