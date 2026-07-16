// حارس دائم: لا تُدفع شاشة يملكها الراوتر عبر Navigator أبداً.
//
// العطل الذي يمنعه (ظهر في الإنتاج و TestFlight، وأبلغ عنه المستخدم مرتين):
//   شاشة الدخول مسار في GoRouter ('/login')، لكنها كانت تُدفع فوق مكدّس Navigator يدوياً
//   من onboarding_screen و guest_explore_screen. فحين ينجح الدخول ويُنفَّذ context.go('/')،
//   يعيد GoRouter بناء المسار **تحت** الشاشة المدفوعة وهي تبقى فوقه. المستخدم يرى شاشة
//   الدخول كما هي فيظنّ أن الزر لا يعمل ويضغط ثانيةً.
//
// هذا **فشل صامت**: لا استثناء، لا سجلّ، لا شيء. لا يلتقطه flutter analyze ولا اختبار
// وحدة عادي — لأن كل سطر على حدة سليم. العطل في الخلط بين نظامَي تنقّل.
//
// لذلك الحارس يفحص **المصدر نفسه**: أي Navigator.push* لشاشة مسجّلة في lib/router.dart
// يُسقط هذا الاختبار مع رسالة تشرح البديل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الشاشات التي يملكها GoRouter (lib/router.dart). دفع أيٍّ منها عبر Navigator = العطل.
const _routerOwnedScreens = <String, String>{
  'OnboardingScreen': "context.go('/onboarding')  أو  context.go('/')",
  'ZyiarahLoginScreen': "context.go('/login')",
  'GuestExploreScreen': "context.push('/guest')",
  'ClientDashboard': "context.go('/client')",
  'DriverDashboard': "context.go('/driver')",
  'AdminDashboardScreen': "context.go('/admin')",
  'OrderTrackingScreen': "context.push('/track/<orderId>')",
  'ZyiarahSignupScreen': "context.push('/signup')",
  'AuthWrapper': "context.go('/')",
};

/// القاعدة الثانية — تُكتشَف من المصدر لا من قائمة يدوية:
/// **أي شاشة تستدعي context.go('/') يجب ألا تُدفَع عبر Navigator أبداً.**
///
/// لماذا '/' تحديداً وليس أي go؟ لأن الآلية دقيقة:
///   • Navigator.push لا يغيّر موقع الراوتر — الشاشة المدفوعة تجلس فوق الصفحة الحالية.
///   • كل الشاشات تُدفع فوق '/' (حيث يعيش AuthWrapper).
///   • فـ context.go('/') من شاشة جالسة على '/' = **لا تغيير في الموقع = لا شيء يحدث**.
///     الشاشة تبقى معروضة كما هي. لا استثناء، لا سجلّ. هذا بالضبط ما حدث في الدخول
///     والتسجيل والملف الشخصي.
///   • أما context.go('/orders') من شاشة على '/' فيغيّر الموقع فعلاً، فتُزال الشاشة
///     المدفوعة معه ويعمل الانتقال. لذلك لا نُنذر عنه — حارسٌ يُنذر كذباً يُتجاهَل ثم
///     يُعطَّل، فيصير أسوأ من لا شيء.
///
/// القائمة أعلاه وحدها لم تكن لتكفي: ZyiarahSignupScreen ليست مساراً في الراوتر، ومع
/// ذلك حملت العطل نفسه — تُدفع من login_screen وتستدعي context.go('/') عند نجاح التسجيل،
/// فتبقى معروضة. المستخدم يظنّ أن التسجيل فشل فيعيد المحاولة على حسابه الذي أُنشئ للتوّ،
/// فيُقابَل بـ«البريد مستخدم بالفعل».
Set<String> _screensThatGoHome() {
  final classDecl = RegExp(r'class\s+(\w+)\s+extends\s+(?:StatefulWidget|StatelessWidget)\b');
  final goHome = RegExp(r"""(?:context|GoRouter\.of\(context\))\s*\.\s*go\s*\(\s*['"]/['"]\s*\)""");
  final screens = <String>{};
  for (final file in _dartSources()) {
    final source = file.readAsStringSync();
    if (!goHome.hasMatch(source)) continue;
    for (final m in classDecl.allMatches(source)) {
      screens.add(m.group(1)!);
    }
  }
  return screens;
}

/// يلتقط: Navigator.push( / Navigator.pushReplacement( / Navigator.pushAndRemoveUntil(
/// وأيضاً Navigator.of(context).push*( — عبر عدّة أسطر.
final _navigatorPush = RegExp(
  r'Navigator\s*\.\s*(?:of\s*\([^)]*\)\s*\.\s*)?push(?:Replacement|AndRemoveUntil|Named)?\s*\(',
);

List<File> _dartSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test("لا شاشة يملكها الراوتر أو تستدعي go('/') تُدفَع عبر Navigator (فشل صامت)", () {
    final violations = <String>[];
    final goCallers = _screensThatGoHome();

    for (final file in _dartSources()) {
      final source = file.readAsStringSync();
      if (!source.contains('Navigator')) continue;

      for (final match in _navigatorPush.allMatches(source)) {
        // نافذة تكفي لتغطية MaterialPageRoute(builder: (_) => const XScreen())
        // بما فيها الملفوفة على عدّة أسطر.
        final end = (match.end + 220).clamp(0, source.length);
        final window = source.substring(match.start, end);

        // القائمة الصريحة + كل شاشة تستدعي context.go تُكتشَف من المصدر.
        final suspects = <String, String>{
          ..._routerOwnedScreens,
          for (final s in goCallers)
            if (!_routerOwnedScreens.containsKey(s))
              s: 'سجّلها مساراً في lib/router.dart وانتقل إليها بـ context.push(...)',
        };

        for (final entry in suspects.entries) {
          // حدود الكلمة تمنع مطابقة اسم أطول يحتوي الاسم كجزء منه.
          if (!RegExp('\\b${entry.key}\\b').hasMatch(window)) continue;

          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          final why = goCallers.contains(entry.key)
              ? "تستدعي context.go('/') بداخلها، والدفع يُجلسها فوق '/' ⇒ الـ go لا يغيّر"
                  ' الموقع ⇒ لا شيء يحدث والشاشة تبقى معروضة'
              : 'مسار في GoRouter ⇒ مصدرا تنقّل متنازعان';
          violations.add(
            '${file.path.replaceAll(r'\', '/')}:$line\n'
            '      دُفعت «${entry.key}» عبر Navigator — ${entry.key} $why.\n'
            '      البديل: ${entry.value}',
          );
          break;
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '\n\nشاشة يملكها GoRouter دُفعت فوق مكدّس Navigator.\n'
          'حين تُنفِّذ تلك الشاشة context.go(...) سيتغيّر مسار الراوتر **تحتها** وتبقى هي\n'
          'معروضة فوقه — فيرى المستخدم الشاشة كما هي ويظنّ أن الزر لا يعمل. فشل صامت تماماً.\n'
          'استخدم context.go(...) — طرف واحد يملك التنقّل.\n\n'
          'المخالفات:\n  • ${violations.join('\n  • ')}\n',
    );
  });

  test('كل شاشة مذكورة في الحارس ما زالت مسجّلة فعلاً في router.dart', () {
    // يمنع تعفّن الحارس: لو أُزيل مسار من الراوتر، هذه القائمة تصير كذباً وتحجب أعطالاً.
    final router = File('lib/router.dart').readAsStringSync();
    final stale = _routerOwnedScreens.keys
        .where((screen) => !RegExp('\\b$screen\\b').hasMatch(router))
        .toList();

    expect(
      stale,
      isEmpty,
      reason:
          'هذه الشاشات في قائمة الحارس لكنها لم تعد في lib/router.dart: $stale\n'
          'حدِّث _routerOwnedScreens — حارسٌ يفحص شاشات غير موجودة يعطي أماناً كاذباً.',
    );
  });

  test('تسجيل الخروج لا يدفع شاشة يدوياً — الراوتر يتفاعل مع authStateChanges', () {
    // GoRouter مربوط بـ refreshListenable على authStateChanges، و AuthWrapper على '/'
    // يعرض الترحيب تلقائياً بعد الخروج. دفع OnboardingScreen يدوياً بعد signOut يضع
    // نسخة ثانية **فوق** الراوتر: تبقى معلّقة بعد أي دخول لاحق.
    final router = File('lib/router.dart').readAsStringSync();
    expect(
      router.contains('refreshListenable'),
      isTrue,
      reason: 'الراوتر يجب أن يبقى مربوطاً بـ authStateChanges — وإلا صار الدفع اليدوي ضرورة.',
    );

    for (final file in _dartSources()) {
      final source = file.readAsStringSync();
      if (!source.contains('signOut')) continue;

      for (final match in 'signOut'.allMatches(source)) {
        final end = (match.end + 400).clamp(0, source.length);
        final window = source.substring(match.start, end);
        if (_navigatorPush.hasMatch(window)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          fail(
            '${file.path.replaceAll(r'\', '/')}:$line — دفعٌ يدوي عبر Navigator بعد signOut.\n'
            'الراوتر يتكفّل بذلك عبر refreshListenable(authStateChanges)؛ الدفع اليدوي يترك\n'
            'شاشة ترحيب عالقة فوق الراوتر تظهر للمستخدم بعد دخوله التالي. احذف الدفع فقط.',
          );
        }
      }
    }
  });
}
