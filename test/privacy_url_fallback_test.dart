// حارسُ **الرابطِ الذي يَفتحُه مُراجِعُ المتجر**: `zyiarah.com/privacy` يَخدمُ
// سياسةً دائماً، لا «قريباً» ولا رسالةَ عطل.
//
// ═══ لماذا ═══
//
// الصفحةُ تَقرأُ `public_content/privacy` من Firestore، و**لا شيءَ في
// المستودعِ يَزرعُ ذلك المستند**: كاتبُه الوحيدُ هو حفظُ شاشةِ الإعداداتِ في
// تطبيقِ الإدارةِ أو في اللوحة (فُحِصَ كلُّ المستودع). فسياسةٌ لم تُحفَظْ
// بعدُ تَعني أنّ الصفحةَ تَعرضُ «سيتم نشر سياسة الخصوصية قريباً» — **وهذا
// بعينُه الرابطُ الذي يَفتحُه مُراجِعُ آبل**، وغيابُ السياسةِ عنده رفضٌ
// بالبندِ 5.1.1 لا سؤالٌ. والخطأُ كان يُعرَضُ كذلك («تعذّر تحميل سياسة
// الخصوصية حالياً») — فعطلٌ عابرٌ لحظةَ المراجعةِ له الأثرُ نفسُه.
//
// **والقاعدةُ «المنشورُ إن وُجد، وإلّا الثابت» مقرَّرةٌ سلفاً** في
// `lib/screens/terms_privacy_screens.dart`، وتعليقُها يَحكي تصحيحَها:
// «وكانت هذه الشاشة تتجاهله وتعرض نصّاً ثابتاً. الآن تعرض المنشور نفسه،
// **والثابت احتياطاً حين يغيب أو يتعذّر جلبه**». فالصفحةُ الوحيدةُ التي كانت
// تَخرُجُ على القاعدةِ هي السطحُ الذي يَحكمُ على الإصدار — نمطُ «قاعدةٌ عامّةٌ
// مُنفَّذةٌ في سطحٍ واحد» الذي تَكرّر في هذا المستودع.
//
// والاحتياطيُّ **نصُّ `privacy_policy.md` حرفيّاً** لا نسخةً منه: نسخةٌ
// ثانيةٌ تَنحرِفُ بلا أن يَكسِرَ شيء (كما انحرفت مرايا اللوحةِ من قبل)،
// فالحارسُ يُقارِنُهما **بايتاً ببايت**. وعلاماتُ Markdown تُجرَّدُ **عند
// العرضِ** وحدَه، كي يَبقى المصدرُ مطابقاً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _page = 'landing_page/privacy.html';
const String _policy = 'privacy_policy.md';
const String _inApp = 'lib/screens/terms_privacy_screens.dart';

void main() {
  final String html = File(_page).readAsStringSync();
  final String policy = File(_policy).readAsStringSync().trim();

  test('الاحتياطيُّ موجودٌ وهو نصُّ privacy_policy.md بايتاً ببايت', () {
    final m = RegExp(r'<template id="fallback-policy">([\s\S]*?)</template>')
        .firstMatch(html);
    expect(m, isNotNull,
        reason: 'لا احتياطيَّ في الصفحة — فرابطُ المراجعةِ بلا سياسةٍ متى '
            'غابَ مستندُ Firestore');
    expect(m!.group(1), policy,
        reason: 'الاحتياطيُّ انحرفَ عن privacy_policy.md — نسخةٌ ثانيةٌ '
            'تَنحرِفُ بلا أن يَكسِرَ شيء');
    expect(policy.length, greaterThan(400),
        reason: 'السياسةُ المصدرُ انهارت — واحتياطيٌّ فارغٌ أسوأُ من لا شيء');
  });

  test('ولا نصَّ «قريباً» ولا رسالةَ عطلٍ مكانَ السياسة', () {
    for (final bad in const [
      'سيتم نشر سياسة الخصوصية قريباً',
      'تعذّر تحميل سياسة الخصوصية',
    ]) {
      expect(html.contains(bad), isFalse,
          reason: 'الصفحةُ ما زالت تَعرضُ «$bad» — وهو ما يَراه المُراجِع');
    }
  });

  test('والمسارانِ كلاهما يَسقطُ على الاحتياطيّ: الغيابُ والخطأ', () {
    // `showFallback` تُنادى في فرعِ «لا محتوى» **وفي** `catch`.
    final calls = RegExp(r'showFallback\(\)').allMatches(html).length;
    expect(calls, greaterThanOrEqualTo(3),
        reason: 'تعريفٌ ونداءانِ على الأقلّ — الغيابُ والخطأ');
    final i = html.indexOf('} catch (e) {');
    expect(i, greaterThan(-1), reason: 'كتلةُ الخطأِ اختفت');
    expect(html.substring(i).contains('showFallback()'), isTrue,
        reason: 'الخطأُ لا يَسقطُ على الاحتياطيّ');
  });

  test('والعرضُ بـtextContent لا innerHTML — النصُّ من مُحرِّرٍ إداريّ', () {
    expect(html.contains('el.textContent = text'), isTrue,
        reason: 'عادَ innerHTML — ونصُّ السياسةِ يُكتَبُ من مُحرِّرٍ إداريّ');
    // `innerHTML` الوحيدُ المسموحُ هو احتياطيُّ شعارٍ ثابتٌ في الترويسة،
    // وقراءةُ `<template>` (وهي قراءةٌ لا كتابة).
    final writes = RegExp(r'\.innerHTML\s*=').allMatches(html).length;
    expect(writes, lessThanOrEqualTo(1),
        reason: 'كتابةُ innerHTML زادت — راجِعْ المصدرَ ومَن يَكتبُه');
  });

  test('والقاعدةُ نفسُها باقيةٌ في شاشةِ التطبيق — لا تُنتزَعُ منها', () {
    final src = File(_inApp).readAsStringSync();
    expect(src.contains('published.isNotEmpty'), isTrue,
        reason: 'شاشةُ التطبيقِ فقدت «المنشورُ إن وُجد» — وهي سابقةُ القاعدة');
    expect(src.contains('خصوصيتك تهمنا'), isTrue,
        reason: 'فقدت الاحتياطيَّ الثابت');
    // والمضادّة: تعليقُ القرارِ ما زال مكتوباً.
    expect(src.contains('والثابت احتياطاً'), isTrue,
        reason: 'اختفى نصُّ القرارِ الذي تَستندُ إليه هذه الصفحة');
  });

  test('ولا كاتبَ خادميٍّ للمستند — فالاحتياطيُّ ليس ترفاً', () {
    // لو ظهرَ زرعٌ خادميٌّ لـ`public_content/privacy` فالاحتياطيُّ يَصيرُ
    // شبكةَ أمانٍ لا شرطاً — يُراجَعُ وقتَها، لا يُسكَت.
    final fns = File('functions/index.js').readAsStringSync();
    expect(fns.contains('public_content'), isFalse,
        reason: 'ظهرَ مسارٌ خادميٌّ يَكتبُ public_content — راجِعْ هذا الحارس');
  });
}
