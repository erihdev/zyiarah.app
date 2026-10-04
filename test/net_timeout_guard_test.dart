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
List<File> _allScreens() => Directory('lib/screens')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// نداءاتُ دوالَّ سحابيّة **تُغيّر حالة** (لا تقرأ): مهلتُها قرارٌ مختلف، لأنّ
/// «انقضت المهلة» ليست «لم يحدث شيء» — قد يكون الخادمُ نفّذ. تُعالَج كلٌّ على
/// حدة برسالةٍ تقول «لا نعرف» لا «فشل»، ولا تدخل القاعدةَ العامّة.
const Map<String, String> _statefulCalls = {
  'deleteDriverAccount': 'حذفُ حساب سائق — إعادةُ المحاولة بعد نجاحٍ صامت تُربك',
  'approveAndAssignOrder': 'إسنادُ سائق — الخادمُ يرفض الثاني، لكنّ الرسالة تُضلّل',
  'rescheduleAssignedOrder': 'نقلُ موعد — نفسُ الاعتبار',
  'verifyMoyasarPayment': 'تأكيدُ دفعٍ تمّ فعلاً عند البوّابة — «فشل» كذبة',
  'payWithWallet': 'خصمٌ من المحفظة — idempotent خادميّاً، والرسالةُ هي المسألة',
  'payContractWithWallet': 'كسابقه',
  'moyasarRefundPayment': 'استرداد — تكرارُه بعد نجاحٍ صامت خطر',
};

void main() {
  test('كلُّ نداءِ دالّةٍ سحابيّة في شاشات الحجز له مهلة', () {
    final offenders = <String>[];
    for (final p in _screens) {
      final src = _code(p);
      // `.call({...})` ينتهي بـ`});` — نطلب `.timeout(` بعدها مباشرةً.
      for (final m in RegExp(r'\.call\(\{[\s\S]*?\n\s*\}\)(\.timeout\()?')
          .allMatches(src)) {
        if (m.group(1) == null) offenders.add('$p  ←  httpsCallable بلا مهلة');
      }
    }
    expect(offenders, isEmpty,
        reason: '\n\nنداءٌ سحابيٌّ بلا مهلة: حين لا يردّ الخادم ولا يرمي، يبقى\n'
            'مؤشّرُ التحميل دائراً ولا تُعرض واجهةُ الخطأ المكتوبة أصلاً.\n'
            '  • ${offenders.join('\n  • ')}\n');
  });

  test('كلُّ قراءةِ Firestore في كلّ شاشة لها مهلة', () {
    final offenders = <String>[];
    for (final f in _allScreens()) {
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

  test('المصادقة لها مهلة ورسالةٌ عند انقضائها', () {
    for (final p in ['lib/screens/login_screen.dart', 'lib/screens/signup_screen.dart']) {
      final src = _code(p);
      expect(src.contains('.timeout(kAuthTimeout)'), isTrue,
          reason: '$p: نداءُ المصادقة بلا مهلة — الزرُّ يبقى دوّاراً بلا مخرج');
      expect(src.contains('on TimeoutException'), isTrue,
          reason: '$p: المهلةُ بلا فرعٍ يُخبر المستخدمَ تساوي رسالةً عامّة مبهمة');
    }
  });

  test('لا نصَّ استثناءٍ خامّاً في وجه العميلة', () {
    // شاشةُ الدخول تُترجم رموزَ Firebase عمداً («رسائل عربية واضحة بدل استثناء
    // Firebase الإنجليزي الخام»)، وشاشتا الحجز كانتا تسرّبانه: شوهد
    // «[firebase_functions/internal] internal [0]» في شريطٍ أحمر بواجهةٍ عربيّة.
    // لا نحاول تفكيك `Text(...)` بالأقواس: أوّلُ نسخةٍ فعلت ذلك بنمطٍ غيرِ نهم،
    // فتوقّف عند القوس المغلق داخل `toString()` نفسه وصار الفحصُ **عاطلاً** —
    // كشفه اختبارُ العضّة. الآن نأخذ كتلةَ الشريط كاملةً ونبحث فيها عن استبدالٍ
    // لمتغيّر الاستثناء، أيّاً كان شكلُ النداء.
    final offenders = <String>[];
    for (final p in _screens) {
      final src = _code(p);
      for (final m in RegExp(r'showSnackBar\(').allMatches(src)) {
        final end = (m.start + 450).clamp(0, src.length);
        final block = src.substring(m.start, end);
        final hit = RegExp(r'\$\{?\s*e\b').firstMatch(block);
        if (hit != null) {
          offenders.add('$p  ←  ...${block.substring(
                  (hit.start - 40).clamp(0, block.length), hit.start + 30)
              .replaceAll(RegExp(r'\s+'), ' ').trim()}...');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '\n\nنصُّ الاستثناء يصل العميلة كما هو:\n  • ${offenders.join('\n  • ')}\n');
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
}
