// حارس دائم: **كلُّ نداءٍ شبكيٍّ تنتظره شاشةٌ له مهلة** — وإلّا صار التعليقُ
// شاشةَ تحميلٍ أبديّة.
//
// وُجد هذا بتشغيل التطبيق فعلاً (2026-10-04، دخولٌ بحسابٍ حقيقيّ): شاشاتُ
// الحجز الثلاث تحمل واجهةَ خطأٍ كاملةً — «فشل تحميل الباقات، تحقق من اتصالك»
// وزرَّ «إعادة المحاولة» موصولاً بـ`_fetchPackages` — و`catch` يضبط `_hasError`.
// ومع ذلك رأت العميلةُ هياكلَ تحميلٍ (shimmer) لا تنتهي، وزرُّ إعادة المحاولة
// مكتوبٌ في الشيفرة لم يُرسم قطّ.
//
// السبب: Firestore عندنا بـ`persistenceEnabled` وذاكرةٍ بلا حدّ، فـ`get()` حين
// يتعذّر بلوغُ الخادم ولا نسخةَ مخزَّنة **لا يرمي — ينتظر**. فلا `catch` يعمل،
// و`_isLoading` يبقى `true` إلى الأبد. وكذلك `httpsCallable` و`signIn`: زرُّ
// الدخول بقي دوّاراً بلا رسالةٍ ولا مخرج (شوهد مباشرةً).
//
// ولا يقع هذا بانقطاعٍ كامل — عندها يرمي Firebase `network-request-failed`،
// ورسالتُه مكتوبةٌ سلفاً في شاشة الدخول. يقع حين **يبدو** الاتصال قائماً
// والحزمُ لا تصل: بوّابةُ تسجيلٍ في فندقٍ أو مركزٍ تجاريّ، وكيلٌ شفّاف، أو
// واي-فاي مرتبطٌ بلا منفذ. فالواجهةُ القائمةُ أصلاً كانت تنتظر خطأً لا يأتي.
//
// المهلةُ تجعل التعليقَ خطأً، فتُعرض الواجهةُ التي كُتبت له. والفكرةُ ليست
// جديدة في المشروع: `.timeout()` مستعملةٌ في عشرة مواضع (PDF، ميسر، GPS،
// App Check، نداءات HTTP) — الناقصُ كان Firestore والدوالّ والمصادقة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يُقنّع التعليقات مع حفظ الأطوال — الرأسُ أعلاه يذكر `.timeout(` و`get()`،
/// ومسحُ المصدر الخام يجعل الحارسَ يسقط على شرحه هو.
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

/// **القاعدةُ بالمصرَفِ لا بالحامل، وتَتبعُ غسلَ الاسمِ خُطوةً واحدة.**
///
/// كان النطاقُ كتلةَ `showSnackBar(...)` وحدَها، ففاتَهُ موضعانِ حيّانِ
/// (2026-10-07): `support_screen` يَرسمُ `Text("خطأ: ${snapshot.error}")`
/// في فرعِ `hasError` — حاملٌ مرسومٌ لا شريط — و`orders_list_screen`
/// كان يَكتبُ `final raw = e.toString()...` ثمّ «خطأ: $raw» **داخلَ**
/// الشريطِ، فالنمطُ على المُلتقَطِ لا يَراه. وهذه ثالثُ ثغرةٍ في هذا
/// الفحصِ بعد النمطِ غيرِ النَهِمِ والتعبيرِ مقابلَ الاستقراء — وثلاثتُها
/// في **الكاشفِ** لا في القاعدة.
///
/// فالفحصُ الآن يَجدُ كلَّ ناقلِ استثناءٍ في الملفّ، ثمّ يَسألُ **إلى أين
/// يَصُبّ**: ما يَصُبُّ في مُصرَفٍ تشخيصيٍّ (`debugPrint`/`reportSilent`/…)
/// مسموحٌ، وما عداه في شاشةِ عميلةٍ تسريب. والنواقلُ ثلاثةٌ: استقراءُ
/// مُلتقَطٍ (`$e`)، و`x.toString()` لمُلتقَطٍ، و`snapshot.error` لمُتغيّرٍ
/// يُفحَصُ بـ`.hasError` في الملفِّ نفسِه — والقيدُ الأخيرُ يَستثني
/// `ZyiarahTheme.error` (لونٌ) من غيرِ قائمةِ أسماءٍ تَتعفّن.
///
/// ولا تُضافُ `e` تلقائيّاً إلى أسماءِ المُلتقَطِ: `list.map((e) => e.toString())`
/// سبعُ إيجابيّاتٍ كاذبةٍ في شاشاتِ الحجزِ وحدَها، فالمُلتقَطُ ما صرّحَ به
/// `catch (…)` في هذا الملفّ.
List<String> _rawErrorSinks(String path) =>
    _rawErrorSinksIn(_code(path), path);

/// نفسُ القاعدةِ على نصٍّ مُعطًى — كي يُختبَرَ الكاشفُ على أشكالٍ مُصطنَعةٍ
/// بعدَ أن يَنظُفَ المصدر: فحصٌ سالبٌ لا يُبرهِنُ أنّه يَرى شيئاً.
///
/// **القاعدةُ بالمصرَفِ لا بالحامل.** كان النطاقُ كتلةَ `showSnackBar(...)`
/// وحدَها، ففاتَهُ موضعانِ حيّانِ (2026-10-07): `support_screen` يَرسمُ
/// `Text("خطأ: ${snapshot.error}")` في فرعِ `hasError` — حاملٌ مرسومٌ لا
/// شريط — و`orders_list_screen` كان يَكتبُ `final raw = e.toString()...`
/// ثمّ «خطأ: $raw» **داخلَ** الشريطِ، فالنمطُ على المُلتقَطِ لا يَراه. وهذه
/// ثالثُ ثغرةٍ في هذا الفحصِ بعد النمطِ غيرِ النَهِمِ والتعبيرِ مقابلَ
/// الاستقراء — وثلاثتُها في **الكاشفِ** لا في القاعدة.
///
/// فالكاشفُ يَجدُ كلَّ ناقلِ استثناءٍ في الملفّ ثمّ يَسألُ **إلى أين يَصُبّ**:
/// ما يَصُبُّ في مُصرَفٍ تشخيصيٍّ (`debugPrint`/`reportSilent`/…) مسموحٌ، وما
/// عداه في شاشةِ عميلةٍ تسريب. والناقلُ **في إسنادٍ تسريبٌ أيضاً** ولا
/// يُتعقَّبُ الاسمُ الوسيط: ذاك أبسطُ وأشدُّ، ويَسُدُّ الغسلَ من منبعِه —
/// ومَن أرادَ نصَّ الاستثناءِ للتشخيصِ يَكتبُه في `debugPrint` مباشرةً.
///
/// والنواقلُ ثلاثةٌ: استقراءُ مُلتقَطٍ (`$e`)، و`x.toString()` لمُلتقَطٍ،
/// و`snapshot.error` لمُتغيّرٍ يُفحَصُ بـ`.hasError` في الملفِّ نفسِه —
/// والقيدُ الأخيرُ يَستثني `ZyiarahTheme.error` (لونٌ) من غيرِ قائمةِ أسماءٍ
/// تَتعفّن. ولا تُضافُ `e` تلقائيّاً إلى أسماءِ المُلتقَط، **ولا يُحسَبُ
/// وسيطُ لامدا اسمُه كاسمِ المُلتقَط**: `map((e) => e.toString())` سبعُ
/// إيجابيّاتٍ كاذبةٍ في شاشاتِ الحجزِ وحدَها.
List<String> _rawErrorSinksIn(String src, String path) {
  final caught = RegExp(r'catch\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)')
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
  final snaps = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\.hasError')
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();

  // **الهروبُ طبقةً واحدةً لا طبقتَين.** أوّلُ صياغةٍ كتبت `\\b` في نصٍّ
  // غيرِ خامٍّ، فصارَ التعبيرُ يَطلبُ شرطةً مائلةً حرفيّةً ثمّ `b` — فلا
  // يُطابِقُ شيئاً، والفحصُ أخضرُ أجوف. أمسكَه فحصُ الكاشفِ أدناه.
  final patterns = <RegExp>[
    if (caught.isNotEmpty)
      RegExp('\\\$\\{?\\s*(?:${caught.map(RegExp.escape).join('|')})\\b'),
    if (caught.isNotEmpty)
      RegExp('\\b(?:${caught.map(RegExp.escape).join('|')})'
          '\\.toString\\(\\)'),
    if (snaps.isNotEmpty)
      RegExp('\\b(?:${snaps.map(RegExp.escape).join('|')})\\.error\\b'),
  ];

  final out = <String>[];
  for (final pat in patterns) {
    for (final m in pat.allMatches(src)) {
      if (_diagnosticSink(src, m.start)) continue;
      if (_lambdaBound(src, m.start, m.group(0)!)) continue;
      final ctx = src
          .substring((m.start - 55).clamp(0, src.length),
              (m.start + 35).clamp(0, src.length))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add('$path  ←  ...$ctx...');
    }
  }
  return out;
}

/// **نسخةٌ أضيقُ لِما ليس شاشةً ولا ودجة: المصرَفُ ودجةٌ فحسب.**
///
/// في شاشةٍ، أيُّ استعمالٍ غيرِ تشخيصيٍّ لاسمِ المُلتقَطِ عرضٌ عمليّاً.
/// أمّا في خدمةٍ فالاستثناءُ **يُصنَّف** مشروعاً (`e.toString().contains(
/// 'Timeout')` في `zone_locator_service`) و**يُحفَظُ تشخيصاً** في حقلٍ لا
/// يُعرَض (`detail:` في `TamaraCheckoutFailure`) — فالكاشفُ العامُّ أبلغَ عن
/// الثلاثةِ زوراً. ونصُّ خدمةٍ تَرميه يُلتقَطُ عند **الشاشةِ** التي
/// تَعرضُه، وهو ما وجدَ عطلَ «خطأ في بوابة تمارا: Exception: …» أصلاً.
/// فالمصرَفُ هنا ودجةُ نصٍّ بعينِها، بموازنةِ الأقواسِ لا بنافذة.
List<String> _rawErrorInWidgetsIn(String src, String path) {
  final caught = RegExp(r'catch\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)')
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
  if (caught.isEmpty) return const [];
  final pats = <RegExp>[
    RegExp('\\\$\\{?\\s*(?:${caught.map(RegExp.escape).join('|')})\\b'),
    RegExp('\\b(?:${caught.map(RegExp.escape).join('|')})\\.toString\\(\\)'),
  ];
  final out = <String>[];
  for (final pat in pats) {
    for (final m in pat.allMatches(src)) {
      if (_diagnosticSink(src, m.start)) continue;
      if (_lambdaBound(src, m.start, m.group(0)!)) continue;
      if (!_insideTextWidget(src, m.start)) continue;
      final ctx = src
          .substring((m.start - 55).clamp(0, src.length),
              (m.start + 35).clamp(0, src.length))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add('$path  ←  ...$ctx...');
    }
  }
  return out;
}

/// هل الموضعُ [pos] داخلَ وسائطِ ودجةِ نصٍّ تَراها المستخدمة؟
bool _insideTextWidget(String src, int pos) {
  const widgets = {'Text', 'SnackBar', 'AlertDialog', 'SelectableText'};
  var depth = 0;
  var i = pos;
  while (i > 0) {
    i--;
    final c = src[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
      } else {
        final head = src.substring((i - 60).clamp(0, i), i);
        final m = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*$').firstMatch(head);
        if (m != null && widgets.contains(m.group(1)!)) return true;
      }
    }
  }
  return false;
}

/// أسماءُ النداءاتِ المُحيطةِ بالموضعِ [pos] — **بموازنةِ الأقواسِ إلى
/// الوراء** لا بنافذةِ عدِّ أحرف (فخُّ الحدِّ مسجَّلٌ في هذا المستودعِ تسعَ
/// مرّات). كلُّ `(` غيرِ مُطابَقٍ يَعني نداءً نحنُ داخلَ وسائطِه.
bool _diagnosticSink(String src, int pos) {
  const diag = {
    'debugPrint', 'print', 'reportSilent', 'log', 'recordError', 'addError',
  };
  var depth = 0;
  var i = pos;
  while (i > 0) {
    i--;
    final c = src[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
      } else {
        final head = src.substring((i - 80).clamp(0, i), i);
        final m = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)\s*$').firstMatch(head);
        if (m != null && diag.contains(m.group(1)!.split('.').last)) {
          return true;
        }
      }
    }
  }
  return false;
}

/// هل الاسمُ في [match] وسيطُ لامدا لا مُلتقَطُ استثناء؟
///
/// `list.map((e) => e.toString())` يَحجبُ `catch (e)` في الملفِّ نفسِه. فيُبحَثُ
/// عن أقربِ `(` غيرِ مُطابَقٍ قبلَ الموضعِ — وهو قوسُ النداءِ المُحيطِ — فإن
/// جاءَ بعدَه إعلانُ وسيطٍ بالاسمِ نفسِه (`(e) =>` أو `(e) {`) فالاسمُ وسيطٌ.
bool _lambdaBound(String src, int pos, String match) {
  final nm = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').firstMatch(match)?.group(0);
  if (nm == null) return false;
  var depth = 0;
  var i = pos;
  while (i > 0) {
    i--;
    final c = src[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
      } else {
        final after = src.substring(i + 1, (i + 60).clamp(0, src.length));
        return RegExp('^\\s*\\(?\\s*${RegExp.escape(nm)}\\s*\\)?\\s*(?:=>|\\{)')
            .hasMatch(after);
      }
    }
  }
  return false;
}

/// جسمُ الدالّةِ من إعلانِها — **بموازنةِ قائمةِ المعامَلاتِ أوّلاً** ثمّ
/// المعقوفات. أخذُ أوّلِ `{` بعد الاسمِ يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ
/// (`{String cancelledBy = 'client'}`) لا الجسمَ — فخُّ الحدِّ، مسجَّلٌ في هذا
/// المستودعِ مرّاتٍ.
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

/// الشاشاتُ التي بُدئ بها الإصلاح — تبقى مذكورةً لأنّ فحوصاً بعينها تخصّها.
const List<String> _screens = [
  'lib/screens/hourly_details_screen.dart',
  'lib/screens/subscription_plans_screen.dart',
  'lib/screens/event_worker_packages_screen.dart',
  'lib/screens/login_screen.dart',
  'lib/screens/signup_screen.dart',
];

/// **كلُّ** شاشة — القاعدةُ أدناه عامّة: لا قراءةَ Firestore بلا مهلة في أيٍّ
/// منها. بُدئ بخمسٍ ثمّ وُسِّع إلى الـ٤١ كلِّها حين تبيّن أنّ العطل عامّ:
/// ٤١ قراءةً بلا مهلة في ٢٠ ملفّاً.
/// الحوارانِ اللذانِ تَفتحُهما العميلةُ من لوحتِها — نفسُ قاعدةِ الشاشات.
/// (المسحُ على `widgets`/`utils`/`providers`/`models` وجدَ موضعَين فقط، كلاهما
/// في وجهِ العميلة، فالنطاقُ كلُّ `lib/widgets/` بلا استثناء.)
List<File> _allWidgets() => Directory('lib/widgets')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

List<File> _allScreens() => Directory('lib/screens')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// **والخدماتُ معها.** المسحُ الأوّل توقّف عند `lib/screens/**`، فبقيت قراءاتُ
/// `lib/services/**` بلا مهلة — وهي ما تقف خلف شاشاتٍ كثيرة. وُجد ذلك حيّاً
/// (2026-10-04) في «حسابي»: «الرصيد المتاح» و«كود الإحالة» كلاهما هيكلُ
/// تحميلٍ لا ينتهي، وكلاهما من خدمة لا من شاشة
/// (`getOrCreateWallet` و`getOrCreateReferralCode`). سبعَ عشرةَ قراءةً في
/// أربعةَ عشرَ ملفّ خدمة.
List<File> _allServices() => Directory('lib/services')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// بقيّةُ `lib/` التي يَبلغُ نصُّها العميلةَ: مزوّداتٌ ونماذجُ وأدوات.
/// (الشاشاتُ والودجاتُ والخدماتُ لها دوالُّها أعلاه.)
List<File> _allProvidersModelsUtils() => [
      for (final d in const ['lib/providers', 'lib/models', 'lib/utils'])
        ...Directory(d)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];

/// ملفّاتٌ نداءاتُها السحابيّة **تُغيّر حالة** لا تقرأ — مهلتُها قرارٌ مختلف.
/// «انقضت المهلة» ليست «لم يحدث شيء»: قد يكون الخادمُ نفّذ. فرسالةُ «فشل» بعد
/// استردادٍ نجح تدفع الأدمنَ لإعادته. تُترك بلا مهلة عمداً حتى يُقرَّر لكلٍّ منها
/// نصٌّ يقول «لا نعرف»، وهو قرارُ المالك لا مسحٌ آليّ.
///
/// (شاشةُ الدفع ليست هنا: نداءاتُها الخمسة مُؤمَّنة أصلاً — verifyMoyasarPayment
///  مُغلَّف بـcatch يصمت عمداً لأنّ المُصالِح الدوري يضمن الطلب، وpayWithWallet
///  idempotent خادميّاً، والمعالجُ الخارجيّ لا يُظهر خطأً بعد دفعٍ بمعرّف إطلاقاً
///  ويقول للمحفظة «لن يُخصم منك مرتين». المهلةُ هناك تُتيح هذا السلوك لا تُغيّره.)
const Map<String, String> _statefulCallFiles = {
  'lib/screens/admin/admin_order_details_screen.dart':
      'استرداد/إلغاء/تحصيل + إسناد سائق + نقل موعد',
  'lib/screens/admin/admin_drivers_screen.dart': 'حذفُ حساب سائق',
  // حذفُ موظّف: يَحذفُ حسابَ Auth **أوّلاً** ثمّ المستندات، فـ«انقضت
  // المهلة» ليست «لم يحدث شيء» بحالٍ — قد يكون الحسابُ أُغلق والمستنداتُ
  // باقية. نصٌّ يَقول «لا نعرف» قرارٌ مستقلٌّ كأخواتِه.
  'lib/screens/admin/admin_managers_screen.dart': 'حذفُ حساب موظّف (Auth أوّلاً)',
};

/// **كاشفُ قراءاتِ Firestore: بنيويٌّ لا نافذةُ أحرف.**
///
/// كان `RegExp(r'await\s+[\s\S]{0,180}?\.get\(\)…')` — ومئةٌ وثمانونَ حرفاً
/// أقصرُ بكثيرٍ من سلسلةِ استعلامٍ حقيقيّة، فسلسلةٌ فيها `where` و`orderBy`
/// و`limit` لا يَبلغُها المُطابِقُ من `await` أصلاً. ومرساةُ `await` نفسُها
/// تُسقِطُ ما لا يُنتظَرُ نصّاً: وسيطَ `future:` في `FutureBuilder`، وعنصراً
/// داخلَ `Future.wait([...])` حيث `await` قبلَ القائمةِ لا قبلَ العنصر.
/// فكانت **تسعَ عشرةَ قراءةً عاريةً غيرَ مرئيّةٍ له** من خمسٍ وسبعين.
///
/// الكاشفُ الآن يَمشي من `.get()` **إلى الوراءِ بموازنةِ الأقواسِ** حتى بدايةِ
/// التعبير، فيَرى السلسلةَ كاملةً أيّاً كان طولُها وسواءٌ أُنتظِرت نصّاً أم
/// سُلِّمت وسيطاً — وهو فخُّ الحدِّ غيرِ المُوازَنِ المسجَّلُ في هذا المستودعِ
/// مرّاتٍ، واقعاً على هذا الحارسِ نفسِه.
class _GetHit {
  _GetHit(this.line, this.expr, this.timed);
  final int line;
  final String expr;
  final bool timed;
}

/// بدايةُ التعبيرِ المنتهي بـ`.get()` عند `i` — مشياً إلى الوراء.
int _chainStart(String s, int i) {
  final ident = RegExp(r'[A-Za-z0-9_$]');
  while (i > 0) {
    final c = s[i - 1];
    // كلُّ مقطعٍ في سلسلةِ Firestore نداءٌ (`collection(…)`، `where(…)`،
    // `limit(…)`)، فموازنةُ القوسِ الدائريِّ وحدَها تَكفي — جُرِّبت إضافةُ
    // `[` فأعطت العددَ نفسَه (٧٥) لأنّ الاختصارَ لا يَزيدُ مطابقةً أبداً،
    // فأُسقِطت: فرعٌ لا يَعضُّ أسوأُ من لا فرع.
    if (c == ')') {
      var depth = 0, j = i - 1;
      while (j >= 0) {
        if (s[j] == ')') {
          depth++;
        } else if (s[j] == '(') {
          depth--;
          if (depth == 0) break;
        }
        j--;
      }
      if (j < 0) return i;
      i = j;
      continue;
    }
    if (ident.hasMatch(c) || c == '.' || c == '!' || c == '?') {
      i--;
      continue;
    }
    if (c == ' ' || c == '\t' || c == '\n') {
      // فراغٌ جزءٌ من سلسلةٍ متعدّدةِ الأسطرِ فقط إن سبقَه طرفُ تعبير.
      var k = i - 1;
      while (k > 0 && (s[k - 1] == ' ' || s[k - 1] == '\t' || s[k - 1] == '\n')) {
        k--;
      }
      if (k > 0 &&
          (s[k - 1] == '.' ||
              s[k - 1] == ')' ||
              s[k - 1] == ']' ||
              ident.hasMatch(s[k - 1]))) {
        i = k;
        continue;
      }
      return i;
    }
    return i;
  }
  return i;
}

final RegExp _fsExpr =
    RegExp(r"FirebaseFirestore|collection\(|\.doc\(|_db|_firestore|firestore\.");

List<_GetHit> _firestoreGets(String src) {
  final hits = <_GetHit>[];
  for (final m in RegExp(r'\.get\(\)').allMatches(src)) {
    final expr = src.substring(_chainStart(src, m.start), m.end);
    if (!_fsExpr.hasMatch(expr)) continue;
    final tail =
        src.substring(m.end, (m.end + 40).clamp(0, src.length)).trimLeft();
    hits.add(_GetHit(src.substring(0, m.start).split('\n').length,
        expr.replaceAll(RegExp(r'\s+'), ' ').trim(), tail.startsWith('.timeout(')));
  }
  return hits;
}

/// مواضعُ نداءِ دالّةٍ سحابيّة بلا مهلة في مصدرٍ مُقنَّع.
///
/// الارتكازُ على `httpsCallable` إلزاميّ: مطابقةُ `.call(` وحدَها تلتقط
/// `onTap?.call()` وأمثالَه — وهو ما حدث فعلاً وكشفه هذا الفحص على نفسه.
int _bareCallableCalls(String src) {
  var n = 0;
  for (final m in RegExp(r'\.call\(').allMatches(src)) {
    final from = (m.start - 220).clamp(0, src.length);
    if (!src.substring(from, m.start).contains('httpsCallable')) continue;
    // **موازنةُ أقواسٍ لا نمطٌ للوسائط.** النسخةُ الأولى طابقت «خريطةً
    // متعدّدةَ الأسطر أو لا وسائط»، فأفلت منها `.call({'code': code})` في
    // سطرٍ واحد — `applyReferralCode` في خدمة الإحالة — فقرأ النداءُ بلا
    // مهلةٍ كأنّه محصَّن. كشفه فحصُ مجموعةِ الخدمات أدناه.
    var i = m.end, depth = 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    final tail = src.substring(i, (i + 40).clamp(0, src.length)).trimLeft();
    if (!tail.startsWith('.timeout(')) n++;
  }
  return n;
}

/// نداءاتُ المصادقةِ التي تَعبُرُ الشبكةَ — مباشرةً أو عبرَ الخدمة.
///
/// `signOut` **ليست منها بقصد**: محلّيّةٌ تَمسحُ الرمزَ وتَنتهي بلا شبكة،
/// فمهلةٌ عليها حلٌّ لمشكلةٍ لا وجودَ لها (ولو تَعلَّقت فمعناها «لا نعرف
/// أهل خرجتِ» — قرارٌ آخر، كـ`_statefulCalls`).
const List<String> kAuthNetCalls = [
  'signInWithRealEmailAndPassword',
  'signUpWithRealEmailAndPassword',
  'signInWithEmailAndPassword',
  'createUserWithEmailAndPassword',
  'sendPasswordResetEmail',
];

void main() {
  test('الكاشفُ نفسُه يُختبَرُ كالشفرة — الأشكالُ الثلاثةُ التي أعمَت النمطَ', () {
    // النمطُ القديمُ (`await` + ١٨٠ حرفاً) أفلتَ منه ٭كلُّ٭ موضعٍ من التسعةَ
    // عشرَ. فالكاشفُ البديلُ يُثبَّتُ على الأشكالِ التي أعمَته بعينِها، لا
    // على مصدرِ المشروعِ وحدَه: مصدرُ المشروعِ نظيفٌ اليومَ فلا يُبرهِنُ أنّ
    // الكاشفَ يَرى شيئاً.
    //
    // (١) وسيطٌ لا يُنتظَرُ نصّاً — `future:` في `FutureBuilder`.
    var h = _firestoreGets(
        "FutureBuilder(future: FirebaseFirestore.instance.collection('d').doc(u).get(),)");
    expect(h.length, 1, reason: 'قراءةٌ غيرُ مُنتظَرةٍ نصّاً لم تُرَ');
    expect(h.single.timed, isFalse);

    // (٢) عنصرٌ داخلَ `Future.wait` — `await` قبلَ القائمةِ لا قبلَ العنصر،
    //     وعاريةٌ واحدةٌ تُبطِلُ مهلةَ أختِها لأنّ الانتظارَ للكلّ.
    h = _firestoreGets("await Future.wait([a.collection('x').get().timeout(k), "
        "b.collection('y').get(),]);");
    expect(h.length, 2);
    expect(h.map((e) => e.timed).toList(), [true, false]);

    // (٣) سلسلةٌ أطولُ من مئةٍ وثمانينَ حرفاً — الطولُ وحدَه كان يُخفيها.
    final long = "await db.collection('orders')"
        "${".where('a', isEqualTo: 1)" * 9}.orderBy('created_at').limit(500).get();";
    expect(long.length, greaterThan(180), reason: 'السلسلةُ أقصرُ من أن تُبرهِن');
    h = _firestoreGets(long);
    expect(h.length, 1, reason: 'سلسلةٌ طويلةٌ أفلتت — عادت نافذةُ عدِّ الأحرف');
    expect(h.single.timed, isFalse);

    // ولا إيجابيّةَ كاذبة: `.get()` على ما ليس Firestore لا يُحسَب.
    expect(_firestoreGets('final v = await prefs.get();'), isEmpty);
    expect(_firestoreGets('final v = map.get();'), isEmpty);
  });

  test('كلُّ نداءِ دالّةٍ سحابيّة له مهلة، إلّا المُغيِّرةَ للحالة صراحةً', () {
    final offenders = <String>[];
    for (final f in _allScreens()) {
      final p = f.path.replaceAll(r'\', '/');
      if (_statefulCallFiles.containsKey(p)) continue;
      final n = _bareCallableCalls(_code(p));
      if (n > 0) offenders.add('$p  ←  $n نداءً سحابيّاً بلا مهلة');
    }
    expect(offenders, isEmpty,
        reason: '\n\nنداءٌ سحابيٌّ بلا مهلة: حين لا يردّ الخادم ولا يرمي، يبقى\n'
            'مؤشّرُ التحميل دائراً ولا تُعرض واجهةُ الخطأ المكتوبة أصلاً.\n'
            'إن كان النداءُ يُغيّر حالةً فأضِف ملفَّه إلى _statefulCallFiles بسببٍ مكتوب.\n'
            '  • ${offenders.join('\n  • ')}\n');
  });

  test('قائمةُ الاستثناء لا تتعفّن — كلُّ ملفٍّ فيها ما زال يحمل نداءً بلا مهلة', () {
    // قائمةٌ تُجيز ما لم يعد موجوداً تتعفّن (كما تعفّن شاهدُ COD في status_util).
    _statefulCallFiles.forEach((p, why) {
      expect(_bareCallableCalls(_code(p)), greaterThan(0),
          reason: '$p لم يعد يحمل نداءً بلا مهلة ($why) — أزِله من القائمة');
    });
  });

  test('كلُّ قراءةِ Firestore في كلّ شاشة وكلّ خدمة لها مهلة', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final f in [..._allScreens(), ..._allServices()]) {
      final p = f.path.replaceAll(r'\', '/');
      for (final h in _firestoreGets(_code(p))) {
        scanned++;
        if (!h.timed) {
          offenders.add('$p:${h.line}  ←  '
              '${h.expr.substring((h.expr.length - 110).clamp(0, h.expr.length))}');
        }
      }
    }
    // أرضيّةٌ: كاشفٌ يَنحلُّ إلى صفرٍ يَمرُّ أخضرَ أجوفَ. (٧٥ اليوم.)
    expect(scanned, greaterThanOrEqualTo(60),
        reason: 'انهارَ كاشفُ القراءات — فحصٌ لا يَرى شيئاً ليس فحصاً');
    expect(offenders, isEmpty,
        reason: '\n\nقراءةُ Firestore بلا مهلة. مع persistenceEnabled لا ترمي\n'
            'حين يتعذّر بلوغُ الخادم — تنتظر، فيبقى shimmer إلى الأبد:\n'
            '  • ${offenders.join('\n  • ')}\n');
  });

  test('والمهلةُ هي الثابتُ المشترَك لا مُدّةٌ مكتوبةٌ في موضعِها', () {
    // القاعدةُ أدناه («المهلتان معرَّفتان مرّةً واحدة») تَفحصُ الخمسَ الأُولى
    // وحدَها، وهذه تَشدُّها على **كلِّ** قراءةٍ في النطاقِ المُشتَقّ: مُدّةٌ
    // محلّيّةٌ تَعني أنّ تغييرَ المهلةِ لا يَبلغُها.
    final offenders = <String>[];
    for (final f in [..._allScreens(), ..._allServices()]) {
      final p = f.path.replaceAll(r'\', '/');
      final src = _code(p);
      for (final m in RegExp(r'\.get\(\)\s*\.timeout\(([^)]*)').allMatches(src)) {
        final arg = m.group(1)!.trim();
        if (arg != 'kNetCallTimeout') {
          offenders.add('$p  ←  .timeout($arg)');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '\n\nمهلةُ قراءةٍ ليست kNetCallTimeout — فلا تَتغيّرُ من مكانٍ واحد:\n'
            '  • ${offenders.join('\n  • ')}\n');
  });

  test('نداءاتُ الخدمات السحابيّة الأربعةُ مُغيِّرةٌ للحالة — تُترك عمداً', () {
    // `verifyMoyasarPayment`، `autoAssignDriverDirectly`، `createTamaraCheckout`،
    // `applyReferralCode`: كلُّها تُغيّر حالةً خادميّة، فـ«انقضت المهلة» ليست
    // «لم يحدث شيء» — القرارُ نفسُه المُسجَّل في `_statefulCallFiles` أعلاه،
    // ممتدّاً إلى الخدمات. الفحصُ يثبّت أنّها ما زالت **هي** الأربعة: نداءٌ
    // خامسٌ بلا مهلة يجب أن يُراجَع لا أن يمرّ ضمن استثناءٍ مفتوح.
    final stateful = <String>{
      'lib/services/moyasar_service.dart',
      'lib/services/order_service.dart',
      'lib/services/tamara_service.dart',
      'lib/services/zyiarah_referral_service.dart',
    };
    final bare = <String>{};
    for (final f in _allServices()) {
      final p = f.path.replaceAll(r'\', '/');
      if (_bareCallableCalls(_code(p)) > 0) bare.add(p);
    }
    expect(bare, stateful,
        reason: 'تغيّرت مجموعةُ النداءات السحابيّة بلا مهلة في الخدمات — '
            'راجِع الجديدَ منها: أهو مُغيِّرٌ للحالة فعلاً؟');
  });

  test('مهلةٌ على قراءةٍ غير حرجة لا تقف أمام قراءةٍ ماليّة', () {
    // المهلةُ تُنهي التعليق، لكنّها **عشرون ثانية**. فقراءةٌ «غير حرجة»
    // موضوعةٌ قبل قراءةٍ ماليّة تُورِّثها تأخيرَها كاملاً.
    //
    // وُجد حيّاً (2026-10-04): في «حسابي» كان عدُّ الحجوزات (`count()`، يسقط
    // إلى «—» عند الفشل بنصِّ تعليقه) يُنتظَر قبل إطلاق `_loadWallet`. وقد
    // فشل فعلاً — `RunAggregationQuery` يرجع `unavailable` ويعيد المحاولة —
    // فبقيت بطاقةُ الرصيد هيكلَ تحميلٍ عشرين ثانيةً **قبل أن تبدأ أصلاً**.
    // لا تبعيةَ بينهما: كلتاهما تحتاج `uid` وحده.
    // الفحصُ داخل `_loadUserData` وحدَها: للمحفظة مواضعُ نداءٍ أخرى مشروعة
    // (إعادةُ تحميلٍ بعد استبدال النقاط، وزرُّ إعادة المحاولة).
    final full = _code('lib/screens/profile_screen.dart');
    final from = full.indexOf('Future<void> _loadUserData() async {');
    expect(from, greaterThan(0));
    final src = full.substring(from, full.indexOf('\n  Future<', from + 10));
    final wallet = src.indexOf('_loadWallet(uid);');
    final referral = src.indexOf('_loadReferralCode(uid);');
    final count = src.indexOf('.count()');
    expect(wallet, greaterThan(0), reason: 'لم تعد تُحمَّل المحفظةُ هنا أصلاً');
    expect(referral, greaterThan(0));
    expect(count, greaterThan(0));
    expect(wallet, lessThan(count),
        reason: 'عادت بطاقةُ الرصيد تنتظر عدّاً غير حرِج');
    expect(referral, lessThan(count),
        reason: 'عاد كودُ الإحالة ينتظر عدّاً غير حرِج');
    // ولا تُطلَقان مرّتين داخل الدالّة (نسخةٌ قديمة بقيت في الذيل تُضاعف
    // القراءات بلا أن يظهر شيء).
    expect('_loadWallet(uid);'.allMatches(src).length, 1);
    expect('_loadReferralCode(uid);'.allMatches(src).length, 1);
  });


  test('المصادقة لها مهلة ورسالةٌ عند انقضائها', () {
    // **كان هذا الفحصُ مشدوداً إلى ملفَّين بأسمائهما وقاعدتُه عامّة
    // (2026-10-07)** — «حارسٌ ضيّقٌ وقاعدةٌ عامّة» للمرّةِ التاسعةِ هنا.
    // فنجا `forgot_password_screen`: `FirebaseAuth.instance
    // .sendPasswordResetEmail` **بلا مهلة**، فإن بدا الاتّصالُ قائماً
    // والحزمُ لا تَنفُذ بَقي الزرُّ دوّاراً إلى الأبدِ بلا رسالةٍ ولا مخرج.
    // والدليلُ **مسحُ المصدر**: ثمانيةُ نداءاتِ مصادقةٍ في `lib/`،
    // مُمهَلانِ اثنانِ وستّةٌ بلا مهلة.
    //
    // فالنطاقُ **مُشتَقٌّ**: كلُّ ملفٍّ في `lib/screens/**` يُنادي نداءَ
    // مصادقةٍ يَعبُرُ الشبكةَ يَجبُ أن يُمهِلَه وأن يَكونَ له فرعٌ يُخبرُها.
    final offenders = <String>[];
    final scanned = <String>[];
    for (final f in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = _code(f.path);
      final calls = kAuthNetCalls.where((c) => src.contains('$c(')).toList();
      if (calls.isEmpty) continue;
      scanned.add(f.path);
      if (!src.contains('.timeout(kAuthTimeout)')) {
        offenders.add('${f.path} (${calls.join(", ")}): بلا مهلة');
      } else if (!src.contains('on TimeoutException')) {
        offenders.add('${f.path}: مهلةٌ بلا فرعٍ يُخبرُ المستخدم');
      }
    }
    expect(scanned.length, greaterThanOrEqualTo(3),
        reason: 'انهارَ المسح: ${scanned.length} شاشةَ مصادقة');
    expect(scanned, contains('lib/screens/forgot_password_screen.dart'),
        reason: 'الشاشةُ التي كشفت العطلَ خرجت من النطاق');
    expect(offenders, isEmpty,
        reason: 'نداءُ مصادقةٍ بلا مهلة — الزرُّ يبقى دوّاراً بلا مخرج، '
            'أو مهلةٌ بلا فرعٍ يُخبرُها فتُساوي رسالةً عامّةً مبهمة');
  });

  test('ولا نداءَ مصادقةٍ يَتخطّى الخدمةَ إلى الـSDK من شاشة', () {
    // المصادقةُ نطاقُ `ZyiarahFirebaseService` بقرارِ المشروع، وكان
    // `forgot_password_screen` وحدَه يَتخطّاها — فبَقيت
    // `sendPasswordResetEmail` في الخدمةِ **بلا مُنادٍ**، ولم يَرَها
    // `no_dead_code_test` لأنّ اسمَها اسمُ دالّةِ الحزمة (عمًى موثَّقٌ هناك).
    for (final f in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = _code(f.path);
      for (final c in kAuthNetCalls) {
        expect(RegExp(r'FirebaseAuth\.instance\s*\.\s*' + c).hasMatch(src),
            isFalse,
            reason: '${f.path}: `$c` مباشرةً على الـSDK — '
                'تُنادى عبر ZyiarahFirebaseService كشقيقتَيها');
      }
    }
    // وشاهدُ التعليل: الخدمةُ ما زالت تَحملُ الدالّةَ، ولها مُنادٍ.
    expect(_code('lib/services/firebase_service.dart'),
        contains('Future<void> sendPasswordResetEmail('));
    expect(_code('lib/screens/forgot_password_screen.dart'),
        contains('_firebaseService.sendPasswordResetEmail('));
  });

  /// كتلةُ `showSnackBar(...)` بحدودِها الحقيقيّةِ — **بموازنةِ الأقواس**.
  ///
  /// نافذةُ عدِّ أحرفٍ (٤٥٠ حرفاً) كانت تَتجاوزُ نهايةَ الشريطِ فتَلتقطُ ما
  /// بعدَه: في `driver_dashboard` الشريطُ نصُّه عربيٌّ ثابتٌ تماماً، و`$e`
  /// في `debugPrint` في الفرعِ **التالي** — إيجابيّةٌ كاذبةٌ محضة. والموازنةُ
  /// ليست النمطَ غيرَ النَهِمِ الذي عطّل أوّلَ نسخةٍ من هذا الفحص: ذاك توقّف
  /// عند قوسٍ مغلقٍ داخل `toString()`، والموازنةُ تَعُدُّ الفتحَ والإغلاقَ معاً
  /// فتَجتازُه صحيحاً.
  String snackBlock(String src, int start) {
    final open = src.indexOf('(', start);
    var depth = 1;
    var i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    return src.substring(start, i);
  }

  test('لا نصَّ استثناءٍ خامّاً في وجه العميلة', () {
    // شاشةُ الدخول تُترجم رموزَ Firebase عمداً («رسائل عربية واضحة بدل استثناء
    // Firebase الإنجليزي الخام»)، وشاشتا الحجز كانتا تسرّبانه: شوهد
    // «[firebase_functions/internal] internal [0]» في شريطٍ أحمر بواجهةٍ عربيّة.
    //
    // **والنطاقُ كان خمسَ شاشاتٍ والقاعدةُ عامّة.** قاعدةُ المهلةِ في هذا
    // الملفِّ وُسّعت إلى الـ٤١ كلِّها حين تبيّن أنّ العطلَ عامّ، وهذا الفحصُ
    // بقي على الخمس — فوُجد **١٣ موضعاً** في وجه العميلةِ في ١١ شاشةً أخرى
    // («خطأ في بوابة تمارا: Exception: فشل الاتصال ببوابة التقسيط: …» كان
    // أسوأَها: بادئتانِ مكرّرتان و`Exception` بحرفٍ لاتينيّ). النطاقُ الآن
    // **كلُّ شاشاتِ العميلة**.
    //
    // **والأدمنُ والسائقُ مُستثنيانِ بقصد:** النصُّ الخامُّ عندهما تشخيصٌ
    // مطلوب — `admin_order_details` يَعرضُ «خطأ غير متوقع: $e» عن عمدٍ،
    // و٦٢ موضعاً في شاشاتِ الإدارةِ على هذا النهج. إخفاؤه عنهم خسارةٌ لا ربح.
    //
    // **والنطاقُ وُسّع ثالثةً إلى `lib/widgets/` (2026-10-05).** كان
    // `lib/screens/**` وحدَه، و`rating_dialog` و`support_fab` حوارانِ
    // تَفتحُهما العميلةُ من لوحتِها — فكان أحدُهما يَعرضُ «تعذّر فتح
    // الكاميرا — … من الإعدادات: $e» والآخرُ «تعذّر الاتصال بالدعم: $e».
    // ومسحُ `widgets`+`utils`+`providers`+`models` وجدَ هذَين وحدَهما، فلا
    // موضعَ إداريّاً هناك يَلزمُ استثناؤه.
    //
    // **والنمطُ كان يَرى الاستقراءَ وحدَه (`$e`) لا التعبيرَ (2026-10-06).**
    // القاعدةُ عامّةٌ — «لا نصَّ استثناءٍ خامّاً» — والنمطُ `\$\{?\s*e\b`
    // يُطابِقُ `$e` و`${e.toString()}` ولا يُطابِقُ `e.toString()` **تعبيراً
    // مباشراً**. وكان ذلك موضعاً حيّاً واحداً، على **شاشةِ الدفع**: مُعالِجُ
    // Google Pay يَعرضُ `e.toString().replaceAll('Exception: ', '')`، فمهلةُ
    // الثلاثينَ ثانيةً في `processGooglePayToken` تُقرأُ «TimeoutException
    // after 0:00:30.000000: Future not completed» وانقطاعُ الشبكةِ
    // «ClientException with SocketException: Failed host lookup» — ولا
    // تَمَسُّهما `replaceAll` لأنّهما لا يَبدآنِ بـ`Exception: `.
    //
    // **ورابعةً إلى `lib/services/` (2026-10-08) — وهو ما أغفلَه المسحُ
    // الثالثُ بعينِه:** التعليقُ أعلاه يَقولُ «ومسحُ
    // `widgets`+`utils`+`providers`+`models`» — و`services` ليست فيها،
    // بينما `_allServices()` موجودةٌ في هذا الملفِّ ويُنادِيها فحصُ
    // **المهلةِ** مرّتَين. فمُسِحَت الأربعةُ مع الخدماتِ فوُجد موضعٌ واحدٌ:
    // `popup_service` يَعرضُ «تعذّر فتح الرابط: $e» في حوارِ الإعلانِ
    // المنبثقِ الذي تَفتحُه **لوحةُ العميلة**، و`launchUrl` يَرمي
    // `PlatformException` فتُقرأُ «… PlatformException(ACTIVITY_NOT_FOUND,
    // No Activity found to handle Intent…)» بحرفٍ لاتينيّ. والسطرُ
    // المجاورُ (فرعُ `!ok`) يَقولُ الجملةَ الصحيحةَ أصلاً.
    final offenders = <String>[];
    for (final f in [..._allScreens(), ..._allWidgets()]) {
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('/admin/')) continue;
      if (path.split('/').last.startsWith('driver_')) continue;
      offenders.addAll(_rawErrorSinks(path));
    }
    var nonUi = 0;
    for (final f in [..._allServices(), ..._allProvidersModelsUtils()]) {
      final path = f.path.replaceAll('\\', '/');
      nonUi++;
      offenders.addAll(_rawErrorInWidgetsIn(_code(path), path));
    }
    expect(nonUi, greaterThanOrEqualTo(60),
        reason: 'انحلَّ مسحُ الخدماتِ والأدواتِ — اشتقاقٌ فاشلٌ لا مستودعٌ أصغر');
    expect(offenders, isEmpty,
        reason: '\n\nنصُّ الاستثناء يصل العميلة كما هو:\n  • ${offenders.join('\n  • ')}\n');
  });

  test('كاشفُ النصِّ الخامِّ يُختبَرُ كالشفرة — الحاملُ والمصرَفُ والغسل', () {
    // المصدرُ نظيفٌ بعد الإصلاح، فنجاحُ الفحصِ أعلاه لا يُبرهِنُ أنّ الكاشفَ
    // يَرى شيئاً. وثغراتُه الثلاثُ التاريخيّةُ كانت كلُّها في **الكاشفِ** لا
    // في القاعدة، فتُثبَّتُ هنا واحدةً واحدة.

    // (أ) حاملٌ مرسومٌ لا شريط — عطلُ `support_screen` بنصِّه.
    expect(
        _rawErrorSinksIn(
            'builder: (c, snapshot) {\n'
            '  if (snapshot.hasError) {\n'
            r'    return Center(child: Text("خطأ: ${snapshot.error}"));'
            '\n  }\n}\n',
            'synthetic'),
        isNotEmpty,
        reason: 'حاملٌ مرسومٌ (Text) خارجَ الشريطِ يَجبُ أن يُرى');

    // (ب) الناقلُ **في إسنادٍ** تسريبٌ أيضاً — فالغسلُ يُسَدُّ من منبعِه.
    // كان `orders_list_screen` يَكتبُ `final raw = e.toString()...` ثمّ
    // «خطأ: $raw»، فلا يُتعقَّبُ الاسمُ الوسيطُ ولا حاجةَ إليه: الإسنادُ
    // نفسُه يُبلَّغُ عنه.
    expect(
        _rawErrorSinksIn(
            'try { f(); } catch (e) {\n'
            r'  final raw = e.toString().replaceAll("Exception: ", "");'
            '\n'
            r"  messenger.showSnackBar(SnackBar(content: Text('خطأ: $raw')));"
            '\n}\n',
            'synthetic'),
        isNotEmpty,
        reason: 'ناقلٌ في إسنادٍ يَجبُ أن يُرى — وإلّا كفى غسلُ الاسمِ لتخطّيه');

    // (و) واستثناءُ وسيطِ اللامدا لا يَجوزُ أن يَبتلعَ تسريباً حقيقيّاً
    // داخلَ لامدا: استثناءٌ ضيّقٌ يَأكلُ القاعدةَ أسوأُ من لا استثناء.
    expect(
        _rawErrorSinksIn(
            'try { f(); } catch (e) {\n'
            r"  setState(() { _msg = 'خطأ: $e'; });"
            '\n}\n',
            'synthetic'),
        isNotEmpty,
        reason: 'نصُّ الاستثناءِ داخلَ لامدا بلا وسيطٍ بالاسمِ نفسِه تسريب');

    // (ج) المصرَفُ التشخيصيُّ مسموح — وإلّا صارَ الفحصُ يَمنعُ التشخيصَ نفسَه.
    expect(
        _rawErrorSinksIn(
            'try { f(); } catch (e) {\n'
            r"  debugPrint('support tickets stream error: $e');"
            '\n'
            r"  reportSilent(e, reason: 'x');"
            '\n}\n',
            'synthetic'),
        isEmpty,
        reason: 'debugPrint و reportSilent تشخيصٌ لا عرض');

    // (د) وسيطُ لامدا اسمُه `e` ليس استثناءً — سبعُ إيجابيّاتٍ كاذبةٍ في
    // شاشاتِ الحجزِ وحدَها لو أُضيفَ `e` تلقائيّاً إلى أسماءِ المُلتقَط.
    expect(
        _rawErrorSinksIn(
            r"final f = (data['features'] as List?)?.map((e) => e.toString()).toList();"
            '\n'
            r"return Text(f?.join(' ') ?? '');"
            '\n',
            'synthetic'),
        isEmpty,
        reason: 'map((e) => e.toString()) بلا catch ليس ناقلَ استثناء');

    // (هـ) و`X.error` مُقيَّدٌ بما يُفحَصُ بـ`.hasError` في الملفِّ نفسِه —
    // فلونُ القالبِ (`ZyiarahTheme.error`) لا يُقرأُ استثناءً، بلا قائمةِ
    // أسماءٍ تَتعفّن.
    expect(
        _rawErrorSinksIn(
            r"return Text('x', style: TextStyle(color: ZyiarahTheme.error));"
            '\n',
            'synthetic'),
        isEmpty,
        reason: 'Theme.error لونٌ لا استثناء');
  });

  test('وكاشفُ ما ليس شاشةً يُختبَرُ كذلك — الودجةُ تَعضُّ والتشخيصُ لا', () {
    // المصدرُ نظيفٌ بعدَ الإصلاح، فنجاحُ الفحصِ أعلاه لا يُبرهِنُ أنّ
    // الكاشفَ الأضيقَ يَرى شيئاً. فيُختبَرُ على الأشكالِ التي أعمَت العامَّ
    // أو أضلَّته، كلٌّ وحدَه.
    String sink(String body) => 'void f() { try { g(); } catch (e) { $body } }';

    // (١) ودجةُ نصٍّ ⇒ يُلتقَط. وهو عطلُ `popup_service` بعينِه.
    expect(
        _rawErrorInWidgetsIn(
            sink("show(SnackBar(content: Text('تعذّر فتح الرابط: \$e')));"),
            'x.dart'),
        isNotEmpty,
        reason: 'نصٌّ خامٌّ داخلَ ودجةٍ لم يُلتقَط — الكاشفُ أعمى');

    // (٢) حقلُ تشخيصٍ مُسمّى ⇒ لا. (`detail:` في `TamaraCheckoutFailure`.)
    expect(
        _rawErrorInWidgetsIn(
            sink("throw F(userFacingError(e), detail: '\${e.code}: \${e.message}');"),
            'x.dart'),
        isEmpty,
        reason: 'حقلُ التشخيصِ ليس عرضاً — إيجابيّةٌ كاذبة');

    // (٣) تصنيفُ الاستثناءِ ⇒ لا. (`zone_locator_service`.)
    expect(
        _rawErrorInWidgetsIn(
            sink("return e.toString().contains('Timeout') ? a : b;"), 'x.dart'),
        isEmpty,
        reason: 'تصنيفُ الاستثناءِ ليس عرضاً — إيجابيّةٌ كاذبة');

    // (٤) مصرَفٌ تشخيصيٌّ داخلَ ودجةٍ؟ لا يُجتمَعان؛ والتشخيصُ وحدَه لا.
    expect(_rawErrorInWidgetsIn(sink("debugPrint('x: \$e');"), 'x.dart'),
        isEmpty);
  });

  test('والنصُّ الخامُّ يَبقى للأدمنِ — تشخيصٌ لا عطل', () {
    // لو صفرَت فقد أُخفي عن المالكِ ما يَحتاجُه.
    var hits = 0;
    for (final f in _allScreens()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.contains('/admin/')) continue;
      final src = _code(path);
      for (final m in RegExp(r'showSnackBar\(').allMatches(src)) {
        if (RegExp(r'\$\{?\s*e\b').hasMatch(snackBlock(src, m.start))) {
          hits++;
        }
      }
    }
    expect(hits, greaterThan(20),
        reason: 'أُخفي نصُّ الاستثناء عن شاشاتِ الإدارة — وهو تشخيصُها');
  });

  test('إلغاءُ الطلبِ: الحاملُ يُعلِنُ نفسَه ولا استخراجَ نصّيّاً', () {
    final svc = _code('lib/services/order_service.dart');
    final scr = _code('lib/screens/orders_list_screen.dart');

    // الحاملُ صنفٌ يُصرّحُ بأنّ رسالتَه مكتوبةٌ للعرض — لا `Exception` عامٌّ
    // تَستخرجُه الشاشةُ من نصِّه.
    expect(svc.contains('class OrderCancelRefused implements UserFacingFailure'),
        isTrue,
        reason: 'الحاملُ المُعلِنُ لنفسِه هو ما يُغني عن الاستخراجِ النصّيّ');

    // والثلاثُ تُرمى به — لا `Exception("…")` عامّاً داخلَ `cancelOrder`.
    final i = svc.indexOf('Future<void> cancelOrder(');
    expect(i, greaterThan(0));
    final body = _fnBody(svc, i);
    expect(RegExp(r'OrderCancelRefused\(').allMatches(body).length, 3,
        reason: 'الجملُ الثلاثُ المكتوبةُ للعميلةِ تُرمى بالحاملِ المُعلِن');
    expect(body.contains('throw Exception('), isFalse,
        reason: 'جملةٌ رابعةٌ في `Exception` عامٍّ تُستخرَجُ نصّيّاً مرّةً أخرى');

    // والشاشةُ تَمُرُّ بالقاعدةِ، وفحصُ الصلاحيّةِ **بالنوعِ لا بالنصّ**.
    expect(scr.contains('userFacingError(e'), isTrue);
    expect(scr.contains("e is FirebaseException && e.code == 'permission-denied'"),
        isTrue,
        reason: 'الفحصُ بالنوعِ: مُطابقةُ النصِّ تَلتقطُ أيَّ استثناءٍ يَذكرُ الكلمة');
    expect(scr.contains("replaceAll(\"Exception: \""), isFalse,
        reason: 'الاستخراجُ النصّيُّ هو ما كان يُسرِّبُ كلَّ ما عدا الثلاث');
  });

  test('شاشةُ الدعم: فرعُ الخطأِ جملةٌ عربيّةٌ وزرُّ إعادةٍ يُعيدُ الاشتراك', () {
    final src = _code('lib/screens/support_screen.dart');

    expect(src.contains('تعذّر تحميل التذاكر، تحقّقي من الاتصال'), isTrue,
        reason: 'جملةٌ عربيّةٌ مكانَ نصِّ الاستثناء');
    expect(src.contains('إعادة المحاولة'), isTrue);

    // **والزرُّ يُحاولُ فعلاً**: مفتاحُ البناءِ يَتغيّرُ فيُعادُ الاشتراكُ ببثٍّ
    // جديد. زرٌّ يُغيّرُ الحالةَ بلا مفتاحٍ يُعيدُ رسمَ `StreamBuilder` نفسِه
    // بالبثِّ القديمِ الحامِلِ للخطأ — أي زرٌّ لا يَفعلُ شيئاً، وهي عائلةٌ
    // مسجَّلةٌ في هذا المستودع.
    expect(src.contains('_reloadKey++'), isTrue,
        reason: 'الزرُّ يُبدّلُ المفتاح');
    expect(src.contains(r"key: ValueKey('tickets-"), isTrue,
        reason: 'والمفتاحُ على `StreamBuilder` نفسِه، وإلّا لم يُعَد الاشتراك');
    final k = src.indexOf(r"key: ValueKey('tickets-");
    expect(src.lastIndexOf('StreamBuilder<QuerySnapshot>(', k),
        greaterThan(src.lastIndexOf('Widget _buildTicketList', k) - 1),
        reason: 'المفتاحُ داخلَ `StreamBuilder` الذي يَحملُ البثّ');
    expect(src.contains(r'$_reloadKey'), isTrue);

    // ونصُّ الاستثناءِ يَبقى في السجلِّ لا في الشاشة.
    expect(src.contains(r"debugPrint('support tickets stream error:"), isTrue,
        reason: 'التشخيصُ لا يُفقَد — يُنقَلُ إلى المصرَفِ الصحيح');
  });

  test('المهلتان معرَّفتان مرّةً واحدة ولا تُكتبان بالأرقام', () {
    final u = _code('lib/utils/net_timeout.dart');
    expect(u.contains('kNetCallTimeout'), isTrue);
    expect(u.contains('kAuthTimeout'), isTrue);
    for (final p in _screens) {
      final src = _code(p);
      expect(RegExp(r'\.timeout\(\s*const\s+Duration').hasMatch(src), isFalse,
          reason: '$p: مهلةٌ مكتوبةٌ بالأرقام في موضعها — '
              'استعمل kNetCallTimeout/kAuthTimeout كي تتغيّر من مكانٍ واحد');
    }
  });
  group('مسارُ تمارا: لا نصَّ لاتينيّاً ولا سبباً مُلفَّقاً', () {
    test('الغلافُ لا يَنسبُ السببَ خطأً', () {
      final svc = _code('lib/services/tamara_service.dart');
      // كان كلُّ خطأٍ يُلفُّ بـ«فشل الاتصال ببوابة التقسيط: » — فيُقرأ خطأُ
      // المصادقةِ («يجب تسجيل الدخول أولاً») انقطاعاً في الشبكة.
      expect(svc.contains('فشل الاتصال ببوابة التقسيط'), isFalse);
      // ورسالةُ الخادمِ تَصلُ كما هي إن كانت عربيّةً، وإلّا نصٌّ عامّ.
      //
      // **سقطَ هذا الفحصُ بالنقلِ لا بالانحراف (2026-10-07):** كان يُثبّتُ
      // `hasMatch(m)` و`e.message` **هنا**، والقرارُ انتقلَ إلى
      // `userFacingError` حين تبيّنَ أنّ هذه النسخةَ **كانت تُطرَحُ عند
      // المُنادِيَين كليهما** (شاشةُ دفعِ المتجرِ تَطبعُ احتياطيَّها العامَّ
      // أيّاً كان ما قالَه الخادم، وملخّصُ الدفعِ يَصُبُّ في المُعالِجِ العامِّ
      // الذي كان يَطرحُ `message`). فيُثبَّتُ القرارُ **حيث يَسكنُ**، ويُثبَّتُ
      // أنّ الخدمةَ تَبلغُه — فنسخةٌ محلّيّةٌ ثانيةٌ أو نداءٌ مفقودٌ يَسقط.
      expect(RegExp(r'\buserFacingError\s*\(').hasMatch(svc), isTrue,
          reason: 'الخدمةُ تَبلغُ القرارَ ولا تُعيدُ كتابتَه');
      final rule = _code('lib/utils/user_facing_error.dart');
      expect(rule.contains('_isArabic(m)'), isTrue,
          reason: 'فحصُ العربيّةِ هو ما يَمنعُ تسريبَ نصٍّ لاتينيّ');
      expect(rule.contains('error.message'), isTrue,
          reason: 'رسالةُ الخادمِ هي الأصلُ متى كانت عربيّة');
      expect(svc.contains('hasMatch(m)'), isFalse,
          reason: 'نسخةٌ محلّيّةٌ ثانيةٌ من فحصِ العربيّة — القرارُ مرّةً واحدة');
      // والاحتياطيُّ الخاصُّ بالبوّابةِ باقٍ (أنفعُ من الجملةِ العامّةِ: يَقولُ
      // لها إنّ بوسعها اختيارَ طريقةٍ أخرى) — ويُمرَّرُ من موضعِ النداء.
      expect(
          _code('lib/screens/store_payment_screen.dart')
              .contains('تعذّر بدء الدفع بالتقسيط'),
          isTrue);
      expect(
          _code('lib/screens/payment_summary_screen.dart')
              .contains('تعذّر بدء الدفع بالتقسيط'),
          isTrue);
    });

    test('ورسائلُ الخادمِ في هذا المسارِ مكتوبةٌ للعميلة', () {
      final fn = File('functions/index.js').readAsStringSync();
      final i = fn.indexOf('exports.createTamaraCheckout');
      final j = fn.indexOf('\nexports.', i + 10);
      final body = fn.substring(i, j);
      // لا «السيرفر» في وجهِ العميلة، ولا أمرٌ لها بما لا تَقدرُ عليه.
      expect(body.contains('السيرفر'), isFalse);
      expect(body.contains('تحقق من بيانات الطلب'), isFalse,
          reason: 'أمرٌ لا تَقدرُ العميلةُ على تنفيذِه');
      expect(body.contains('أعيدي المحاولة'), isTrue);
    });
  });
}
