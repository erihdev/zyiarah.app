// حارس دائم: **لا شاشةَ بيضاءَ أبديّةً عند الإقلاع.**
//
// `main()` كان يَحملُ أربعةَ نداءاتٍ عاريةٍ **قبلَ `runApp`** — تحميلُ
// `.env`، وتهيئةُ Firebase، وإعداداتُ Firestore، وتفعيلُ Crashlytics —
// ورميُ أيٍّ منها يُنهي `main()` قبلَ أن يُرسَمَ شيء: نافذةٌ بيضاءُ بلا
// رسالةٍ ولا مَخرج، ولا أثرَ في Crashlytics لأنّه لم يُفعَّلْ بعد.
//
// والقاعدةُ كانت مكتوبةً في الملفِّ نفسِه على بُعدِ أسطر — «كل تهيئة محميّة
// داخلياً بـ try/catch فلن تُسقط الإقلاع» — وتُغطّي الثلاثةَ التي تَليها
// وحدَها، وقد تُحقِّقَ أنّها صادقةٌ عليها (كلُّ `await` في
// `ZyiarahNotificationService.initialize` و`GeofenceService.initialize`
// داخلَ `try`). فهي «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد» واقعةً على
// الإقلاع — **والشكلُ عضَّ هنا مرّةً سلفاً**: تعليقُ Crashlytics يَقولُ إنّ
// نداءَه على الويب «يرمي Assertion قبل رسم الواجهة فتظهر شاشة بيضاء».
//
// **ووُجد بتشغيل التطبيق فعلاً** (2026-10-07، ويب بلا رأس): `.env` فارغٌ
// يُنتجُ `EmptyEnvFileError` من أوّلِ سطرٍ في `main`، والنتيجةُ لقطةٌ بيضاءُ
// تماماً — صِفرُ محارفَ في DOM. وهو **كامنٌ لا حيّ**: لا مسارَ نشرٍ يَكتبُ
// ملفّاً فارغاً (Codemagic يَكتبُ ثلاثةَ أسطرٍ دائماً، وسيرا GitHub يَفشلانِ
// على سرٍّ غائب) — لكنّ شدّتَه أنّ الفشلَ كلّيٌّ وصامتٌ ولا يُبلَّغُ عنه.
//
// والتمييزُ قرارٌ لا تعميم: **مفاتيحُ النشرِ تعطّلٌ، وFirebase موت.**
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/env.dart';
import 'package:zyiarah/widgets/boot_failure_app.dart';
import 'helpers/sources_in.dart';

String _code(String p) {
  final s = File(p).readAsStringSync();
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

/// جسمُ `main()` حتّى أوّلِ `runApp` للتطبيقِ الحقيقيّ — بموازنةِ الأقواس.
String _mainBeforeRunApp(String src) {
  final i = src.indexOf('void main() async {');
  expect(i, greaterThan(-1), reason: 'main() اختفت');
  final open = src.indexOf('{', i);
  var depth = 0, j = open;
  while (j < src.length) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) break;
    }
    j++;
  }
  final body = src.substring(open, j);
  // آخرُ `runApp(` هو إقلاعُ التطبيقِ الحقيقيّ (الأوّلُ شاشةُ الفشل).
  final last = body.lastIndexOf('runApp(');
  expect(last, greaterThan(0), reason: 'لا runApp في main');
  return body.substring(0, last);
}

/// جسمُ دالّةٍ مُسمّاةٍ في ملفّ — بموازنةِ قائمةِ المعامَلاتِ ثمّ الجسم.
String _fnBody(String path, String name) {
  final s = _code(path);
  final m = RegExp(r'\n\s*(?:static\s+)?Future<[^>]*>\s+' + name + r'\s*\(')
      .firstMatch(s);
  expect(m, isNotNull, reason: '$path::$name اختفت');
  var j = s.indexOf('(', m!.end - 1), d = 0;
  while (j < s.length) {
    if (s[j] == '(') d++;
    if (s[j] == ')') {
      d--;
      if (d == 0) break;
    }
    j++;
  }
  final b = s.indexOf('{', j);
  d = 0;
  var k = b;
  while (k < s.length) {
    if (s[k] == '{') d++;
    if (s[k] == '}') {
      d--;
      if (d == 0) break;
    }
    k++;
  }
  return s.substring(b + 1, k);
}

/// يُفرِّغُ أجسامَ الإغلاقاتِ (`() async* {` / `() async {` / `() {`) مع حفظِ
/// الأطوال: `await` داخلَ إغلاقٍ **ليس في مسارِ الإقلاع** — يُنفَّذُ متى
/// نُودِيَ الإغلاقُ لا عند `main`. وأوّلُ صياغةٍ لهذا الفحصِ أبلغت عن
/// `rootBundle.loadString` داخلَ `LicenseRegistry.addLicense(() async* {…})`
/// وهو كسولٌ لا يَعملُ إلّا حين تُفتَحُ صفحةُ التراخيص.
String _blankClosures(String s) {
  final out = s.split('');
  for (final m in RegExp(r'\(\s*\)\s*(?:async\*?\s*)?\{').allMatches(s)) {
    var d = 0, i = s.indexOf('{', m.start);
    final from = i;
    while (i < s.length) {
      if (s[i] == '{') d++;
      if (s[i] == '}') {
        d--;
        if (d == 0) break;
      }
      i++;
    }
    for (var k = from; k <= i && k < s.length; k++) {
      out[k] = ' ';
    }
  }
  return out.join();
}

/// مواضعُ `await` خارجَ أيِّ `try` في نصٍّ.
List<int> _unguardedAwaits(String body) {
  final out = <int>[];
  final tok = RegExp(r'try\s*\{|\{|\}|await\b');
  var depth = 0;
  final tryDepths = <int>[];
  for (final m in tok.allMatches(body)) {
    final t = m.group(0)!;
    if (t.startsWith('try')) {
      depth++;
      tryDepths.add(depth);
    } else if (t == '{') {
      depth++;
    } else if (t == '}') {
      if (tryDepths.isNotEmpty && tryDepths.last == depth) tryDepths.removeLast();
      depth--;
    } else {
      if (tryDepths.isEmpty) out.add(body.substring(0, m.start).split('\n').length);
    }
  }
  return out;
}

void main() {
  final mainSrc = _code('lib/main.dart');

  test('لا نداءَ عارياً قبلَ runApp — رميُه شاشةٌ بيضاءُ أبديّة', () {
    final head = _mainBeforeRunApp(mainSrc);
    // أرضيّة: اقتطاعٌ يَنحلُّ يُفرِغُ الفحص.
    expect(head.length, greaterThan(1500), reason: 'اقتطاعُ main انهار');
    expect(RegExp(r'\bawait\b').allMatches(head).length, greaterThanOrEqualTo(4),
        reason: 'لم يُقرَأْ أيُّ await — المُحلِّلُ انهار');
    // النداءانِ الوحيدانِ المسموحُ لهما بلا `try` في موضعِ النداء، لأنّ
    // جسمَيهما **مُغلَّفانِ بالكاملِ** — وذلك مُتحقَّقٌ منه أدناه لا مُدَّعى.
    const selfGuarded = ['ZyiarahNotificationService().initialize()',
      'GeofenceService.initialize()'];
    var scan = _blankClosures(head);
    for (final c in selfGuarded) {
      expect(scan.contains(c), isTrue, reason: 'زالَ النداءُ $c من الإقلاع');
      scan = scan.replaceAll('await $c', ' ' * ('await $c'.length));
    }
    expect(_unguardedAwaits(scan), isEmpty,
        reason: 'نداءٌ عارٍ قبلَ runApp: رميُه يُنهي main قبلَ رسمِ أيِّ شيء، '
            'فيَرى المستخدمُ بياضاً بلا رسالةٍ ولا مَخرجٍ ولا أثرٍ في Crashlytics');
  });

  test('ودعوى «كل تهيئة محميّة داخلياً» تُتحقَّقُ لا تُصدَّق', () {
    // الدعوى مكتوبةٌ في `main.dart` بلا قارئ — وهي عائلةُ «ادّعاءٌ بلا قارئ»
    // المسجَّلةُ هنا ستَّ مرّات. فتُقرَأُ الآن: جسمُ كلٍّ من المُهيِّئَين
    // **كلُّه** داخلَ `try` واحدةٍ من أوّلِه إلى آخرِه، فلا شيءَ يَخرجُ منه
    // — لا رميٌ متزامنٌ قبلَ أوّلِ `await` ولا بعدَ آخرِ `catch`.
    // الدعوى في **تعليق**، و`mainSrc` مُجرَّدٌ من التعليقات — فتُقرَأُ من
    // النصِّ الخامّ. (المضادُّ المعتادُ هنا، معكوساً: لا «أثبِتْ أنّ المصطلحَ
    // باقٍ بعدَ التجريد» بل «اقرأِ الدعوى حيث تَسكنُ فعلاً».)
    //
    // **وتُشَدُّ في موضعِها لا في الملفّ**: أوّلُ صياغةٍ طلبت وجودَ العبارةِ
    // في `main.dart` فحسب، فمرَّ اختبارُ قضمٍ حذفَ الدعوى **أخضرَ** — لأنّ
    // تعليقي أعلى الملفِّ يَقتبسُها ليَشرحَ العطل. وهو «الحارسُ يَسقطُ على
    // توثيقِه» مقلوباً: يَرضى بالتوثيقِ بدلَ أن يَسقطَ عليه. فالمقياسُ
    // قُربُها من النداءَين اللذَين تُبرِّرُهما.
    final raw = File('lib/main.dart').readAsStringSync();
    final claimAt = raw.lastIndexOf('محميّة داخلياً');
    final callAt = raw.indexOf('ZyiarahNotificationService().initialize()');
    expect(claimAt, greaterThan(-1),
        reason: 'زالت الدعوى من main.dart — فالفحصُ بلا محلّ');
    expect(callAt, greaterThan(claimAt),
        reason: 'الدعوى لم تَعُدْ فوقَ النداءَين اللذَين تُبرِّرُهما');
    expect(callAt - claimAt, lessThan(400),
        reason: 'الدعوى بعيدةٌ عن موضعِها — فما بقي منها اقتباسٌ في شرحٍ آخر، '
            'والنداءانِ العاريانِ بلا تبرير');
    for (final e in {
      'lib/services/notification_service.dart': 'initialize',
      'lib/services/geofence_service.dart': 'initialize',
    }.entries) {
      final b = _fnBody(e.key, e.value).trim();
      expect(b.startsWith('try'), isTrue,
          reason: '${e.key}: الجسمُ لا يَبدأُ بـtry — فرميٌ قبلَها يَصعدُ '
              'إلى main ويُسقطُ الإقلاع');
      expect(b.endsWith('}'), isTrue);
      expect(_unguardedAwaits(b), isEmpty,
          reason: '${e.key}: `await` خارجَ الحماية');
    }
  });

  test('وفشلُ Firebase يَرسمُ شاشةً ويَخرج — لا يَسقطُ صامتاً', () {
    final head = _mainBeforeRunApp(mainSrc);
    final at = head.indexOf('Firebase.initializeApp');
    expect(at, greaterThan(0));
    // الفرعُ نفسُه: من `catch` الذي يَلي النداءَ حتّى نهايتِه.
    final c = head.indexOf('} catch', at);
    expect(c, greaterThan(at), reason: 'تهيئةُ Firebase بلا catch');
    final branch = head.substring(c, head.indexOf('\n  }', c) + 4);
    expect(branch.contains('runApp('), isTrue,
        reason: 'الفشلُ لا يَرسمُ شيئاً — وهو البياضُ بعينِه');
    expect(branch.contains('ZyiarahBootFailureApp'), isTrue);
    expect(branch.contains('return;'), isTrue,
        reason: 'بلا return يَمضي الإقلاعُ على Firebase غيرِ مُهيَّأ');
  });

  test('وشاشةُ الفشلِ لا تَعتمِدُ على ما قد يَكونُ فشل', () {
    final w = _code('lib/widgets/boot_failure_app.dart');
    for (final forbidden in [
      'firebase_core',
      'cloud_firestore',
      'firebase_auth',
      'flutter_dotenv',
      'FirebaseFirestore',
      'Firebase.',
    ]) {
      expect(w.contains(forbidden), isFalse,
          reason: 'شاشةُ تعذّرِ الإقلاع تَستعمِلُ $forbidden — وقد يَكونُ هو '
              'ما فشل، فتَصيرُ الشاشةُ نفسُها بياضاً');
    }
  });

  testWidgets('وتَعرضُ سبباً ومَخرجاً — لا دوّارةً ولا فراغاً', (tester) async {
    var retried = 0;
    await tester.pumpWidget(ZyiarahBootFailureApp(onRetry: () => retried++));
    await tester.pump();
    expect(find.text('تعذّر تشغيل التطبيق'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'دوّارةٌ بلا نهايةٍ هي البياضُ بثوبٍ آخر');
    // والاتّجاهُ من اليمين **عند النصِّ نفسِه**: `MaterialApp` يُنصّبُ
    // `Directionality` خاصّاً به من لغتِه، فأقربُ ما إلى الجذرِ هو LTR —
    // وهو الفخُّ المسجَّلُ في هذا المستودعِ («المِحَكُّ يَضَعُ RTL **داخلَ**
    // MaterialApp، وهو ترتيبُ الشاشاتِ الحقيقيّةِ نفسُه»). فالمقياسُ أقربُ
    // `Directionality` **فوقَ النصّ** لا أوّلُ ما في الشجرة.
    final dir = tester.widget<Directionality>(find
        .ancestor(
            of: find.text('تعذّر تشغيل التطبيق'),
            matching: find.byType(Directionality))
        .first);
    expect(dir.textDirection, TextDirection.rtl);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    expect(retried, 1, reason: 'زرُّ الإعادةِ لا يَفعلُ شيئاً');
  });

  test('ومفتاحُ `.env` يُقرَأُ من بوّابةٍ واحدةٍ تَحتمِلُ غيابَ التحميل', () {
    // `dotenv.env` **يَرمي** `NotInitializedError` متى لم يَنجحْ `load()` —
    // لا يُعيدُ خريطةً فارغة. فمواضعُ القراءةِ العشرُ كانت تَكتبُ `?? ''`
    // أي تَقصدُ «مفتاحٌ غائبٌ ⇒ تعطّلُ الميزة»، ولا تَبلغُ `??` أصلاً.
    final offenders = <String>[];
    for (final f in sourcesIn('lib', atLeast: 100)) {
      final p = f.path.replaceAll(r'\', '/');
      if (p.endsWith('lib/utils/env.dart')) continue;
      if (_code(p).contains('dotenv.env')) offenders.add(p);
    }
    expect(offenders, isEmpty,
        reason: 'قراءةٌ مباشرةٌ لـdotenv.env ترمي حين يَفشلُ التحميل:\n'
            '  • ${offenders.join('\n  • ')}');
  });

  test('والبوّابةُ تُعيدُ فراغاً حين لم يُحمَّلْ الملفُّ أصلاً', () {
    // لم يُنادَ `dotenv.load` في هذا الاختبار، فهذه هي الحالةُ بعينِها.
    expect(envOrEmpty('MOYASAR_PUBLISHABLE_KEY'), '');
    expect(envOrEmpty('MAPBOX_TOKEN'), '');
  });
}
