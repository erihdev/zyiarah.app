// حارس دائم: **ما يكتبه محرّرا الإعدادات في `system_configs/app_update` هو ما
// تقرؤه `app_update_service` بعينه.** عقدٌ ثلاثيّ: كاتبان وقارئٌ واحد يقرّر.
//
// لماذا حارس: لأنّ العقد انكسر صامتاً وبقي مكسوراً. القارئ يُفضّل
// `latest_build_ios` / `latest_build_android` ولا يسقط إلى `latest_build`
// الموحّد إلا عند **غياب** حقل المنصّة — بينما الكاتبان (لوحة الويب وشاشة
// إعدادات التطبيق) كانا يكتبان الموحّد وحده، و**لا شيء في المستودع يكتب حقلي
// المنصّة**. فالحقلان موجودان في الإنتاج لأنّ أحداً ضبطهما بيده مرّة، والقراءة
// تُفضّلهما، فرقمُ البناء الذي يكتبه الأدمن في أيّ اللوحتين **لا يقرؤه أحد**:
// بوّابةُ الإصدار مجمَّدة على قيمةٍ يدويّة قديمة، والزرّ يبدو عاملاً وهو لا يعمل.
//
// وتعليقا الكاتبَين كانا يؤكّدان العكس — نصُّ لوحة الويب حرفيّاً: «نكتب
// بالمفاتيح التي يقرأها التطبيق فعلاً».
//
// ولماذا لم يُصلَح بجعل القارئ يقرأ الموحّد: لأنّ الموحّد هو العطل الأصليّ.
// ضُبط مرّةً على رقم بناء iOS فرأى **كلُّ** مختبري أندرويد — وهم على أحدث نسخة —
// مطالبةَ تحديثٍ إجباريّةً زائفة لأسابيع (2026-08-31). فصلُ العدّادين هو
// الإصلاح، وموضعُه الكاتبان لا القارئ.
//
// والحارسُ القديم `admin_settings_merge_test` كان يُثبِّت `'latest_build':
// int.tryParse` — أي يحرس المفتاح العاطل، فيمرّ أبداً ويقاوم الإصلاح.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يُقنّع التعليقات مع حفظ الأطوال: التعليقات هنا **تشرح المفاتيح بأسمائها**،
/// ففحصُ المصدر الخام يُسقط الحارسَ على شرحه هو.
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

const String _service = 'lib/services/app_update_service.dart';
const String _appEditor = 'lib/screens/admin/admin_settings_screen.dart';
const String _webEditor = 'admin_panel/src/pages/Settings.tsx';

void main() {
  test('القارئ يُفضّل حقلَ المنصّة ويسقط للموحّد عند غيابه فقط', () {
    final src = _code(_service);
    expect(src.contains("'latest_build_ios'"), isTrue);
    expect(src.contains("'latest_build_android'"), isTrue);
    // الترتيب هو القرار: حقلُ المنصّة أوّلاً ثمّ الموحّد.
    expect(src.contains("d[platformField] ?? d['latest_build']"), isTrue,
        reason: 'عكسُ الترتيب يُعيد عطلَ 2026-08-31: رقمُ iOS يُطالب أندرويد');
  });

  test('كلا المحرّرَين يكتب حقلي المنصّة', () {
    final app = _code(_appEditor);
    expect(app.contains("'latest_build_ios'"), isTrue,
        reason: 'شاشةُ إعدادات التطبيق تكتب الموحّد وحده ⇒ ما يكتبه الأدمن لا يُقرأ');
    expect(app.contains("'latest_build_android'"), isTrue);

    final web = _code(_webEditor);
    expect(web.contains('latest_build_ios'), isTrue,
        reason: 'لوحةُ الويب تكتب الموحّد وحده ⇒ ما يكتبه الأدمن لا يُقرأ');
    expect(web.contains('latest_build_android'), isTrue);
  });

  test('لا كاتبَ يكتب الموحّد — كتابتُه هي العطل نفسه', () {
    // القارئ يُفضّل حقلَ المنصّة، فكتابةُ الموحّد لا تصل. والأسوأ أنّ قيمةً
    // موحّدةً واحدةً لمنصّتين عدّاداهما مختلفان هي بعينها إنذارُ 2026-08-31.
    for (final f in [_appEditor, _webEditor]) {
      final src = _code(f);
      expect(RegExp(r'''latest_build['"]?\s*:''').hasMatch(src), isFalse,
          reason: '$f يكتب latest_build الموحّد — أزِله وأبقِ حقلي المنصّة');
    }
  });

  test('المفاتيح المكتوبة = المفاتيح المقروءة، كمجموعة', () {
    // مقارنةُ المجموعة كاملةً (كما يفعل amounts.test.js): مفتاحٌ سادسٌ يكتبه
    // محرّرٌ ولا يقرؤه أحد — أو العكس — يسقط هنا بدل أن يصمت سنةً.
    const expected = {
      'enabled',
      'latest_build_ios',
      'latest_build_android',
      'force',
      'message',
    };

    final app = _code(_appEditor);
    final i = app.indexOf("doc('app_update').set");
    expect(i, greaterThan(-1), reason: 'كتابةُ app_update اختفت — حدِّث الحارس');
    final appBlock = app.substring(i, app.indexOf('));', i));
    final appKeys = RegExp(r"'(\w+)'\s*:")
        .allMatches(appBlock)
        .map((m) => m.group(1)!)
        .toSet();
    expect(appKeys, expected, reason: 'مفاتيحُ شاشة التطبيق تخالف ما يقرؤه الخادم');

    final web = _code(_webEditor);
    final j = web.indexOf('setDoc(updRef, {');
    expect(j, greaterThan(-1), reason: 'كتابةُ app_update في اللوحة اختفت');
    final webBlock = web.substring(j, web.indexOf('}, { merge: true })', j));
    final webKeys = RegExp(r'(\w+)\s*:')
        .allMatches(webBlock)
        .map((m) => m.group(1)!)
        .where((k) => k != 'merge')
        .toSet();
    expect(webKeys, expected, reason: 'مفاتيحُ لوحة الويب تخالف ما يقرؤه الخادم');
  });

  test('اللوحتان تعرضان حقلين لا حقلاً واحداً', () {
    // حقلٌ واحد في الواجهة يدعو الأدمن لوضع رقمٍ واحد لمنصّتين عدّاداهما
    // مختلفان — وهو مدخلُ عطل 2026-08-31 حتى لو كُتب في الحقلين.
    final web = _code(_webEditor);
    expect(web.contains('latest-build-ios'), isTrue);
    expect(web.contains('latest-build-android'), isTrue);

    final app = _code(_appEditor);
    expect(app.contains('_latestBuildIosCtrl'), isTrue);
    expect(app.contains('_latestBuildAndroidCtrl'), isTrue);
    expect(app.contains('_latestBuildCtrl'), isFalse,
        reason: 'المتحكّمُ الموحّد القديم باقٍ — حقلٌ واحد لمنصّتين');
  });
}
