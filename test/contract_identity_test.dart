// حارسٌ دائم: **لا هُويّةً مُلفَّقةً على وثيقةٍ تُوقَّع.**
//
// وُجد باختيارِ أقلِّ شاشاتِ العميلِ ذِكراً في `CLAUDE.md` — طريقةٌ أنتجت
// عطلَ شاشتَي ميسر قبلَ هذا بساعة. و`contract_signing_screen` هو السطحُ الذي
// تُوقَّعُ فيه أكبرُ مبالغِ التطبيق.
//
// **العطل:** `_userName` و`_userPhone` كانتا تَبدآنِ `"..."`، و`_loadUserData()`
// يُطلَقُ في `initState` **بلا انتظار**، وزرُّ التوثيقِ مشروطٌ بـ`_isSubmitting`
// **وحدَه** — فجسمُ العقدِ يَقول «الطرف الثاني: السيد/ة ...» و«رقم الجوال: ...»
// وهي تُوقّعُ عليه.
//
// وثلاثةُ مساراتٍ تُبقيه كذلك **إلى الأبد**: رميُ القراءةِ (وكانت بلا `try`،
// والدالّةُ غيرُ مُنتظَرةٍ فالرميُ خطأٌ غيرُ مُعالَجٍ لا يَبلغُ أحداً)،
// و`doc.exists == false` (حسابٌ لم يُجهَّز مستندُه بعد)، وزوالُ الودجةِ في تلك
// اللحظة. وعلى وصلةٍ بطيئةٍ نافذةُ الـ`"..."` هي مهلةُ القراءةِ كلُّها (٢٠ث).
//
// **والمخزونُ في المستندِ كان صحيحاً** (قراءةٌ طازجةٌ عند الإرسال) — فالمعروضُ
// والمسجَّلُ يَختلفان على وثيقةٍ قانونيّة؛ وسجلُّ التدقيقِ كان يُسجّلُ
// `'client': "..."`، أي أنّ الأثرَ الذي يُراجَعُ لاحقاً يَحملُ النائبَ لا الاسم.
//
// وهي عائلةُ «لا رقمَ قبل أن نعرفه» (التقييمُ ٤٫٩، ورقاقةُ القطرات، وتحذيرُ
// رصيدِ المحفظةِ قبلَ الحذف) مُطبَّقةً على **الهُويّةِ** في موضعِ التوقيع.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يُقنّع التعليقات — ترويسةُ الشاشةِ تَقتبسُ النائبَ لتشرحَ زوالَه، فمسحُ
/// النصِّ الخامِّ يَجعلُ الحارسَ يَسقطُ على توثيقِه (مسجَّلٌ في هذا المستودعِ
/// اثنتَي عشرةَ مرّة).
String _code(String path) {
  final s = File(path).readAsStringSync();
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

void main() {
  const String path = 'lib/screens/contract_signing_screen.dart';
  final String src = _code(path);
  final String raw = File(path).readAsStringSync();

  test('لا نائبَ `"..."` في الهُويّةِ — والحقلانِ يَبدآنِ مجهولَين', () {
    expect(src.contains('String? _userName'), isTrue);
    expect(src.contains('String? _userPhone'), isTrue);
    expect(RegExp(r'_user(Name|Phone)\s*=\s*"\.\.\."').hasMatch(src), isFalse,
        reason: 'عادَ النائبُ — تُوقّعُ عقداً باسمِ «...»');
    // ومضادّةٌ: الشرحُ ما زال في الخامّ، فالحجبُ لم يُجوِّفِ الفحص.
    expect(raw.contains('"..."'), isTrue,
        reason: 'زالَ شرحُ العطلِ من رأسِ الشاشة');
  });

  test('زرُّ التوثيقِ مُقفَلٌ حتى تُعرَفَ الهُويّة — ومع سببٍ مكتوب', () {
    expect(src.contains('!_identityKnown) ? null : _submitContract'), isTrue,
        reason: 'الزرُّ لا يَنتظرُ الهُويّة');
    // زرٌّ مُقفَلٌ بلا سببٍ عطلٌ آخر (عائلةُ «زرٌّ يُضغَطُ فلا يَحدثُ شيء»).
    expect(src.contains('جارٍ تحميل بياناتكِ لإدراجها في العقد'), isTrue);
    expect(src.contains('لا يمكن التوثيق قبل ظهور اسمكِ ورقمكِ في العقد'),
        isTrue);
    // والسببُ **قبلَ** الزرِّ في الشجرة، لا بعدَه.
    final iReason = src.indexOf('جارٍ تحميل بياناتكِ لإدراجها في العقد');
    final iBtn = src.indexOf('_submitContract,');
    expect(iReason, lessThan(iBtn),
        reason: 'السببُ أسفلَ الزرِّ لا يُقرأُ قبلَ الضغط');
    // **والشرطُ حيٌّ لا موضعٌ فحسب.** قياسُ الترتيبِ وحدَه يَرضى بـ
    // `if (false)` فوقَ النصِّ نفسِه — ومرَّ اختبارُ قضمٍ بذلك أخضرَ.
    final cond = src.lastIndexOf('if (!_identityKnown)', iReason);
    expect(cond, greaterThan(-1),
        reason: 'النصُّ غيرُ مشروطٍ بجهلِ الهُويّة — فإمّا يَظهرُ دائماً أو لا يَظهرُ أبداً');
    // ويُبدَأُ البحثُ **بعدَ** نصِّ الشرطِ نفسِه، وإلّا طابقَ ذاتَه.
    expect(
        src
            .substring(cond + 'if (!_identityKnown)'.length, iReason)
            .contains('if ('),
        isFalse,
        reason: 'شرطٌ آخرُ أقربُ — فالسببُ ليس تحتَ `!_identityKnown`');
  });

  test('جسمُ العقدِ لا يَعرضُ هُويّةً مجهولةً، ويُفرِّقُ الانتظارَ من الفشل', () {
    expect(src.contains('جارٍ تحميل بياناتكِ…'), isTrue,
        reason: 'الانتظارُ يُقالُ لا يُرسَمُ نائباً');
    expect(src.contains('تعذّر تحميل بياناتكِ، تحقّقي من الاتصال'), isTrue,
        reason: 'الفشلُ يُقالُ — وهو ما كان يَبقى «...» إلى الأبد');
    // **والاستقراءُ مشروطٌ، لا غائبٌ:** الاسمُ يُعرَضُ متى عُرف. فالمشدودُ
    // أنّ كلَّ `$_userName`/`$_userPhone` في الشجرةِ يَقعُ داخلَ فرعِ
    // `_identityKnown` — أي أنّ أقربَ `_identityKnown` قبلَه أقربُ من أقربِ
    // `_buildContractSection(` (بدايةِ الجملةِ التي تَحملُه).
    expect(src.contains('_identityKnown ?'), isTrue);
    var checked = 0;
    for (final needle in [r'$_userName', r'$_userPhone']) {
      var at = src.indexOf(needle);
      while (at > -1) {
        final guard = src.lastIndexOf('_identityKnown', at);
        final stmt = src.lastIndexOf('_buildContractSection(', at);
        if (stmt > -1) {
          expect(guard, greaterThan(stmt),
              reason: 'استقراءُ $needle خارجَ فرعِ `_identityKnown`');
          checked++;
        }
        at = src.indexOf(needle, at + 1);
      }
    }
    expect(checked, greaterThanOrEqualTo(2),
        reason: 'لم يُفحَص أيُّ موضعِ استقراءٍ — فالفحصُ أجوف');
    // وزرُّ إعادةٍ يُنادي المُحمِّلَ نفسَه — لا شاشةٌ عالقةٌ بلا مخرج.
    expect(src.contains('onPressed: _loadUserData'), isTrue);
  });

  test('المُحمِّلُ يَلتقطُ الرميَ ولا يَكتبُ نائباً عند الفشل', () {
    final i = src.indexOf('Future<void> _loadUserData()');
    expect(i, greaterThan(-1));
    final body = _fnBody(src, i);
    // **والـ`try` تُغلّفُ قراءةَ `users` بعينِها.** صياغةٌ أولى قالت
    // `body.contains('try {')` — وفي الجسمِ `try` ثانيةٌ لقراءةِ شروطِ العقد،
    // فمرَّ اختبارُ قضمٍ نزعَ الأولى **أخضرَ**: الفحصُ رَضيَ بـ`try` لا
    // علاقةَ لها.
    final read = body.indexOf("collection('users')");
    expect(read, greaterThan(-1), reason: 'زالت قراءةُ المستخدم');
    final tryAt = body.lastIndexOf('try {', read);
    expect(tryAt, greaterThan(-1), reason: 'القراءةُ عاريةٌ من try');
    expect(body.substring(tryAt, read).contains('}'), isFalse,
        reason: 'الـ`try` أقربُ منها كتلةٌ أخرى — القراءةُ ما زالت عارية');
    expect(body.contains('_identityFailed = true'), isTrue);
    // وغيابُ المستندِ ليس جهلاً: لـAuth اسمُها وهاتفُها.
    expect(body.contains('user?.displayName'), isTrue);
    expect(body.contains('user?.phoneNumber'), isTrue);
    // ولا كتابةَ نائبٍ في فرعِ الفشل.
    final catchAt = body.indexOf('} catch (e) {');
    expect(catchAt, greaterThan(-1));
    final tail = body.substring(catchAt);
    expect(RegExp(r'_userName\s*=').hasMatch(tail), isFalse,
        reason: 'فرعُ الفشلِ يَكتبُ اسماً — وهو ما لا نَعرفُه');
  });

  test('المسجَّلُ والمعروضُ لا يَختلفان — وسجلُّ التدقيقِ يَحملُ الاسمَ لا النائب', () {
    // الكتابةُ تَقرأُ طازجاً (هذا ما كان صحيحاً ويَبقى).
    expect(src.contains("'userName': finalName"), isTrue);
    expect(src.contains("'clientName': finalName"), isTrue);
    // وسجلُّ التدقيقِ كان `'client': _userName` — أي النائبُ في الأثر.
    expect(src.contains("'client': finalName"), isTrue,
        reason: 'سجلُّ التدقيقِ يَحملُ المعروضَ لا المسجَّل');
    expect(src.contains("'client': _userName"), isFalse);
  });

  test('«غير مسجل» قيمةٌ معروفةٌ لا نائبة — فلا تُقفِلُ الزرّ', () {
    // هاتفٌ غيرُ مُسجَّلٍ فعلاً يُعرَضُ ويُوقَّع؛ المُقفِلُ هو **الجهلُ** وحدَه.
    expect(src.contains("'غير مسجل'"), isTrue);
    final i = src.indexOf('bool get _identityKnown');
    expect(i, greaterThan(-1), reason: 'زالَ تعريفُ «نَعرفُ مَن تُوقّع»');
    final body = src.substring(i, (i + 220).clamp(0, src.length));
    expect(body.contains('غير مسجل'), isFalse,
        reason: 'لو عُدَّت «غير مسجل» جهلاً لَأُقفِلَ الزرُّ على عميلةٍ بلا هاتف');
  });
}

/// جسمُ الدالّةِ — **بموازنةِ قائمةِ المعامَلاتِ أوّلاً** ثمّ المعقوفات.
/// أخذُ أوّلِ `{` بعدَ الاسمِ يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ لا الجسمَ
/// (فخُّ الحدِّ، مسجَّلٌ في هذا المستودعِ عشرَ مرّات).
String _fnBody(String src, int declStart) {
  var i = src.indexOf('(', declStart);
  var depth = 1;
  i++;
  while (i < src.length && depth > 0) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') depth--;
    i++;
  }
  final open = src.indexOf('{', i);
  depth = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, j + 1);
    }
  }
  return src.substring(open);
}
