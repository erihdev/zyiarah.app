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

void main() {
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
    for (final f in [..._allScreens(), ..._allServices()]) {
      final p = f.path.replaceAll(r'\', '/');
      final src = _code(p);
      for (final m in RegExp(r'await\s+[\s\S]{0,180}?\.get\(\)(\s*\.timeout\()?')
          .allMatches(src)) {
        if (m.group(1) == null) {
          offenders.add('$p  ←  ${m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '\n\nقراءةُ Firestore بلا مهلة. مع persistenceEnabled لا ترمي\n'
            'حين يتعذّر بلوغُ الخادم — تنتظر، فيبقى shimmer إلى الأبد:\n'
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
    for (final p in ['lib/screens/login_screen.dart', 'lib/screens/signup_screen.dart']) {
      final src = _code(p);
      expect(src.contains('.timeout(kAuthTimeout)'), isTrue,
          reason: '$p: نداءُ المصادقة بلا مهلة — الزرُّ يبقى دوّاراً بلا مخرج');
      expect(src.contains('on TimeoutException'), isTrue,
          reason: '$p: المهلةُ بلا فرعٍ يُخبر المستخدمَ تساوي رسالةً عامّة مبهمة');
    }
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
    final offenders = <String>[];
    for (final f in [..._allScreens(), ..._allWidgets()]) {
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('/admin/')) continue;
      if (path.split('/').last.startsWith('driver_')) continue;
      final src = _code(path);
      // أسماءُ المُلتقَطِ في هذا الملفّ، فـ`f.message` لا يُطابَقُ خطأً.
      final caught = RegExp(r'catch\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet()
        ..addAll(['e', 'err', 'error', 'ex']);
      final toStr = RegExp(
          '\\b(${caught.map(RegExp.escape).join('|')})\\.toString\\(\\)');
      for (final m in RegExp(r'showSnackBar\(').allMatches(src)) {
        final block = snackBlock(src, m.start);
        final hit = RegExp(r'\$\{?\s*e\b').firstMatch(block) ??
            toStr.firstMatch(block);
        if (hit != null) {
          offenders.add('$path  ←  ...${block.substring(
                  (hit.start - 40).clamp(0, block.length), hit.start + 30)
              .replaceAll(RegExp(r'\s+'), ' ').trim()}...');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '\n\nنصُّ الاستثناء يصل العميلة كما هو:\n  • ${offenders.join('\n  • ')}\n');
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
      // لا نُثبّتُ نصَّ الهروبِ نفسَه (يُفسَّرُ عند الكتابةِ فيَصيرُ حروفاً):
      // نُثبّتُ القرارَ — فحصٌ على الرسالةِ ثمّ سقوطٌ على نصٍّ عربيٍّ عامّ.
      expect(svc.contains('hasMatch(m)'), isTrue,
          reason: 'فحصُ العربيّةِ هو ما يَمنعُ تسريبَ نصٍّ لاتينيّ');
      expect(svc.contains('e.message'), isTrue,
          reason: 'رسالةُ الخادمِ هي الأصلُ متى كانت عربيّة');
      expect(svc.contains('تعذّر بدء الدفع بالتقسيط'), isTrue);
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
