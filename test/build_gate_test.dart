// حارسُ **بوّابةِ الإصدار**: الرقمُ المنشورُ يُقرَّرُ مرّةً، والصفرُ غياب.
//
// العقدُ ثلاثيٌّ (كاتبان وقارئٌ واحد) وقد عَطبَ مرّتَين، والثانيةُ أدخلَها
// إصلاحُ الأولى:
//
//   ١) 2026-10-04: المحرّرانِ كانا يَكتبانِ `latest_build` الموحّدَ وحدَه
//      والقارئُ يُفضّلُ حقلَ المنصّة ⇒ رقمُ الأدمنِ لا يَقرؤه أحد.
//   ٢) فصارا يَكتبانِ حقلَي المنصّة — و**الصندوقُ الفارغُ يُكتَبُ صفراً**،
//      والصفرُ ليس `null` فيُفضَّلُ على الاحتياطيِّ الموحّد و
//      `currentBuild >= 0` صحيحٌ أبداً ⇒ المطالبةُ تَموتُ لتلك المنصّةِ
//      **بصمت**، والمفتاحُ والمفتاحُ الإجباريُّ يَبدوانِ عاملَين.
//
// و`app_update_keys_test` — الحارسُ المكتوبُ للعطبِ الأوّل — مرَّ أخضرَ طُوال
// الثاني: يُقارِنُ **مجموعةَ المفاتيحِ** المكتوبةِ بالمقروءةِ، والمفتاحُ كان
// مكتوباً في الجهتَين. المقارنةُ على **الأسماءِ** لا على **القدرة** — نفسُ
// عمًى `restricted_zones: []` في حارسِ الكوبونات. فالقاعدةُ المضافةُ هنا:
// **لا كاتبَ يُسقِطُ رقمَ بناءٍ إلى صفرٍ** (`?? 0` / `|| 0`)، وقيمةٌ غيرُ
// صالحةٍ تُرفَضُ برسالةٍ مرئيّةٍ لا تُبتلَع.
//
// والنوعُ ثالثُ الأخطار: حقلا الإنتاجِ ضُبطا **بيدٍ** في الكونسول، ونصٌّ هناك
// كان يَرمي على `as num?` فيَبتلعُه `catch (_) {}` ⇒ البوّابةُ ميّتةٌ
// للمنصّتَين بلا أثر. القراءةُ تَتسامحُ مع النوعَين الآن، والفشلُ يُسجَّلُ
// بـ`reportSilent` (المعاملُ الثالث: يُسجَّلُ ولا يُعرَض).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/build_gate.dart';

/// يُقنّع أسطرَ التعليقِ: التعليقاتُ هنا تُسمّي المفاتيحَ والأنماطَ التي
/// يَبحثُ عنها الحارس، فمسحُ الخامِّ يُسقطُه على شرحِه هو (تِسعُ مرّاتٍ في هذه
/// الجلسة). وكلُّ فحصٍ يَسحبُ يُقابِلُه فحصٌ يُثبِتُ بقاءَ النصِّ في الخامّ.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

const String _service = 'lib/services/app_update_service.dart';
const String _appEditor = 'lib/screens/admin/admin_settings_screen.dart';
const String _webEditor = 'admin_panel/src/pages/Settings.tsx';
const String _webRule = 'admin_panel/src/utils/buildGate.ts';
const String _webTest = 'admin_panel/src/utils/buildGate.test.ts';

/// جدولُ الحالاتِ المشتركُ بين اللغتَين. **نسخةٌ بعينِها** في
/// `admin_panel/src/utils/buildGate.test.ts` بين العلامتَين نفسِهما.
// ── BUILD_GATE_CASES_BEGIN ──
const List<List<Object?>> _cases = [
  [261, 261],
  ['261', 261],
  [' 261 ', 261],
  [261.9, 261],
  [0, null],
  ['0', null],
  [-1, null],
  ['-1', null],
  ['', null],
  ['  ', null],
  ['v261', null],
  ['26.1', null],
  [null, null],
  [null, null],
  [true, null],
  [<Object?>[], null],
];
// ── BUILD_GATE_CASES_END ──

void main() {
  group('publishedBuild', () {
    test('الصفرُ والسالبُ والفارغُ وغيرُ الرقميِّ غيابٌ — لا بوّابةٌ مفتوحة', () {
      for (final c in _cases) {
        expect(publishedBuild(c[0]), c[1], reason: 'publishedBuild(${c[0]})');
      }
    });

    test('ونصُّ الكونسولِ اليدويُّ مقبولٌ — كان يَرمي على as num?', () {
      // `('261' as num?)` يَرمي TypeError، والـcatch المحيطُ صامتٌ عمداً،
      // فتَموتُ البوّابةُ **للمنصّتَين** بلا أثرٍ في أيِّ مكان.
      expect(publishedBuild('261'), 261);
      expect(() => publishedBuild('x'), returnsNormally);
    });
  });

  group('latestBuildFor', () {
    test('حقلُ المنصّةِ أوّلاً — وعكسُه عطلُ 2026-08-31', () {
      const d = {
        'latest_build_ios': 261,
        'latest_build_android': 208,
        'latest_build': 208,
      };
      expect(latestBuildFor(d, isIos: true), 261);
      expect(latestBuildFor(d, isIos: false), 208);
    });

    test('والسقوطُ إلى الموحّدِ للمستنداتِ القديمةِ وحدَها', () {
      const old = {'latest_build': 208};
      expect(latestBuildFor(old, isIos: true), 208);
      expect(latestBuildFor(old, isIos: false), 208);
    });

    test('والصفرُ يَسقطُ إلى الموحّدِ ولا يُطفئُ البوّابة — هذا هو العطل', () {
      const zeroed = {
        'latest_build_ios': 261,
        'latest_build_android': 0,
        'latest_build': 208,
      };
      expect(latestBuildFor(zeroed, isIos: false), 208,
          reason: 'الصفرُ فُضِّل على الاحتياطيّ ⇒ لا مطالبةَ لأندرويد أبداً');
      expect(latestBuildFor(zeroed, isIos: true), 261);
    });

    test('ولا بوّابةَ حين لا رقمَ منشوراً إطلاقاً', () {
      expect(latestBuildFor(const {'latest_build_ios': 0, 'latest_build': 0},
          isIos: true), isNull);
      expect(latestBuildFor(const {}, isIos: true), isNull);
    });
  });

  group('القارئُ يَسألُ القاعدةَ، والفشلُ يُسجَّل', () {
    final String src = _code(_service);

    test('الخدمةُ تُنادي latestBuildFor ولا تُعيدُ كتابةَ الأسبقيّة', () {
      expect(src.contains('latestBuildFor(d'), isTrue,
          reason: 'عادت الأسبقيّةُ مكتوبةً بيدٍ في الخدمة');
      expect(src.contains("d[platformField] ?? d['latest_build']"), isFalse,
          reason: 'النسخةُ القديمةُ باقيةٌ — والصفرُ فيها يُطفئُ البوّابة');
      expect(src.contains('as num?'), isFalse,
          reason: 'as num? يَرمي على نصٍّ من الكونسول، والـcatch صامت');
      // والمضادّة: شرحُ العطلِ ما زال في الخامِّ (الفحصُ يَقرأُ المُجرَّد).
      expect(File(_service).readAsStringSync().contains('latest_build'), isTrue);
    });

    test('ولا بوّابةَ غيرَ مضبوطةٍ تُقرأُ كبوّابةٍ مفتوحة', () {
      expect(src.contains('if (latestBuild == null) return;'), isTrue,
          reason: 'غيابُ الرقمِ يَجبُ أن يَعني «لا بوّابة» صراحةً');
    });

    test('وفشلُ القراءةِ يُسجَّلُ ولا يُعرَض — المعاملُ الثالث', () {
      expect(src.contains("reportSilent("), isTrue,
          reason: 'catch (_) {} كان يَترك فشلَ بوّابةِ الأمانِ بلا أثر');
      expect(src.contains("reason: 'app_update_gate_failed'"), isTrue,
          reason: 'Crashlytics يُجمّعُ بالسبب — فليَكن ثابتاً');
      expect(RegExp(r'catch \(_\) \{\s*\}').hasMatch(src), isFalse,
          reason: 'الـcatch الصامتُ تماماً عادَ');
    });
  });

  group('ولا كاتبَ يُسقِطُ رقمَ بناءٍ إلى صفر', () {
    test('المحرّرانِ يَرفضانِ غيرَ الصالحِ بدلَ ابتلاعِه', () {
      final app = _code(_appEditor);
      expect(app.contains('publishedBuild(_latestBuildIosCtrl.text)'), isTrue,
          reason: 'محرّرُ التطبيقِ لا يَسألُ القاعدةَ عن صلاحيّةِ الرقم');
      expect(app.contains("'latest_build_ios': iosBuild"), isTrue);
      expect(app.contains("'latest_build_android': androidBuild"), isTrue);
      expect(app.contains('iosBuild == null || androidBuild == null'), isTrue,
          reason: 'لا رفضَ ⇒ الصندوقُ الفارغُ يُكتَبُ ويُطفئُ البوّابة');

      final web = _code(_webEditor);
      expect(web.contains('publishedBuild(appUpdate.latest_build_ios)'), isTrue,
          reason: 'لوحةُ الويبِ لا تَسألُ القاعدةَ — والعطلُ واحدٌ في الجهتَين');
      expect(web.contains('iosBuild === null || androidBuild === null'), isTrue);
      expect(web.contains('latest_build_ios: iosBuild'), isTrue);
    });

    test('والقاعدةُ المضافة: لا `?? 0` ولا `|| 0` على رقمِ بناءٍ في أيِّ كاتب', () {
      // هذا هو ما كان يُعمي `app_update_keys_test`: مجموعةُ المفاتيحِ متطابقةٌ
      // والقدرةُ مفقودة. الصفرُ قيمةٌ **تُطفئُ** الفحصَ، فكتابتُه ليست خياراً.
      for (final f in [_appEditor, _webEditor]) {
        final src = _code(f);
        expect(
            RegExp(r'latest_build\w*[^\n]*(\?\?|\|\|)\s*0').hasMatch(src),
            isFalse,
            reason: '$f يُسقِطُ رقمَ البناءِ إلى صفرٍ — والصفرُ يُطفئُ البوّابة');
      }
      // والمضادّة: النمطُ الممنوعُ ما زال مشروحاً في الخامِّ لئلّا يُحذَفَ شرحُه.
      expect(File(_appEditor).readAsStringSync().contains('?? 0'), isTrue,
          reason: 'شرحُ النمطِ الممنوعِ اختفى من التوثيق');
    });

    test('والصندوقُ الفارغُ يُعرَضُ فارغاً لا صفراً', () {
      // عرضُ «0» يَدعو إلى حفظِه، وحفظُه يُطفئُ البوّابة.
      final app = _code(_appEditor);
      expect(app.contains("publishedBuild(u['latest_build_ios']"), isTrue,
          reason: 'التعبئةُ تُظهرُ 0 عند الغياب ⇒ يُحفَظُ فيُطفئ');
      // واللوحةُ أبعدُ من ذلك: الحقلانِ **نصٌّ خامٌّ** لا رقمٌ، فلا قيمةَ
      // بديلةً تُخترَعُ للفارغِ أصلاً — والنوعُ يَقبلُ النصَّ في القاعدة.
      final web = _code(_webEditor);
      expect(web.contains("latest_build_ios: ''"), isTrue,
          reason: 'الافتراضُ 0 ⇒ قراءةٌ فاشلةٌ أو حقلٌ غائبٌ يُحفَظُ صفراً');
      expect(web.contains('latest_build_ios: number | string'), isTrue);
      expect(web.contains('parseInt(e.target.value) || 0'), isFalse,
          reason: 'الصندوقُ الفارغُ يَعودُ صفراً في الحالة');
    });
  });

  group('المرآةُ بين اللغتَين', () {
    List<Object?> table(String path, {required bool dart}) {
      final s = File(path).readAsStringSync();
      final a = s.indexOf('BUILD_GATE_CASES_BEGIN');
      final b = s.indexOf('BUILD_GATE_CASES_END');
      expect(a, greaterThan(-1), reason: 'علامةُ البدايةِ اختفت من $path');
      expect(b, greaterThan(a), reason: 'علامةُ النهايةِ اختفت من $path');
      // من آخرِ `]` إلى الوراءِ **بموازنةِ الأقواس**: `indexOf('[')` يَلتقطُ
      // قوسَ تعليقِ النوعِ (`[unknown, number | null][]` على جهةِ TypeScript،
      // و`List<List<Object?>>` هنا) لا بدايةَ المصفوفة.
      final seg = s.substring(a, b);
      final end = seg.lastIndexOf(']');
      var depth = 0;
      var start = -1;
      for (var i = end; i >= 0; i--) {
        if (seg[i] == ']') depth++;
        if (seg[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThan(-1), reason: 'تعذّر اقتطاعُ الجدولِ من $path');
      var json = seg.substring(start, end + 1);
      // توحيدُ الصياغةِ قبل المقارنة: الاقتباسُ المفرد، و`undefined`
      // و`<Object?>[]`، والفواصلُ المتدلّية — اختلافُ لغةٍ لا اختلافُ حالة.
      json = json
          .replaceAll('<Object?>[]', '[]')
          .replaceAll('undefined', 'null')
          .replaceAll("'", '"')
          .replaceAllMapped(
              // `replaceAll` في Dart يَضعُ `$1` حرفيّاً — لا مجموعةَ التقاط.
              RegExp(r',(\s*[\]}])'), (m) => m.group(1)!);
      return jsonDecode(json) as List<Object?>;
    }

    test('جدولُ الحالاتِ واحدٌ — حالةٌ لجهةٍ دون الأخرى تَسقط', () {
      final dart = table('test/build_gate_test.dart', dart: true);
      final ts = table(_webTest, dart: false);
      expect(ts, dart,
          reason: 'جدولا الحالاتِ افترقا — القاعدةُ مرآةٌ أو ليست مرآة');
      expect(dart.length, greaterThanOrEqualTo(14),
          reason: 'الجدولُ انهار — واختبارٌ على جدولٍ فارغٍ أخضرُ وأجوف');
    });

    test('والقاعدةُ تَعيشُ مرّةً في كلِّ جهةٍ لا في الصفحة', () {
      expect(File(_webRule).existsSync(), isTrue);
      final rule = _code(_webRule);
      expect(rule.contains('export function publishedBuild'), isTrue);
      expect(rule.contains('export function latestBuildFor'), isTrue);
      // ولا نسخةَ ثانيةً داخلَ الصفحة.
      expect(_code(_webEditor).contains('function publishedBuild'), isFalse,
          reason: 'نسخةٌ ثانيةٌ من القاعدةِ في الصفحة');
    });
  });
}
