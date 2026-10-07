import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/account_block.dart';

import 'helpers/strip_comments.dart';

/// **حظرُ الحسابِ كان يُنهي الجلسةَ بصمتٍ تامّ (2026-10-07).**
///
/// `user_provider` يَرى `is_blocked` أو `status == 'banned'` فيُنادي
/// `signOut()` ويَرجع — بلا `notifyListeners` وبلا كلمةٍ في أيِّ مكان،
/// و`debugPrint` لا يُجمَع. فتَرتدُّ المستخدمةُ إلى شاشةِ الترحيبِ فتَقرأُ
/// الارتدادَ «كلمةُ مرورٍ خاطئة»، فتُعيدُ المحاولةَ ثمّ تُراسِلُ الدعم.
///
/// وهو **بعينِه** التعليلُ المسجَّلُ لبوّابةِ دخولِ لوحةِ الويب، التي تَرفضُ
/// بـ`signOut` **ورسالةٍ تُسمّي السبب** — فالقاعدةُ كانت مُنفَّذةً في اللوحةِ
/// (سطحُ الموظّفين) وغائبةً عن التطبيق (سطحُ العميلة).
///
/// والقاعدةُ كانت مكتوبةً **نسختَين** في `lib/`: المزوّدُ (المُنفِّذ) وشاشةُ
/// المستخدمينَ الإداريّة (الشارة) — فاختلافُهما يَعني شارةً تَقولُ غيرَ ما
/// يَفعلُه الخروج.
void main() {
  group('القاعدة — سلوكاً', () {
    test('العلمان كلٌّ وحدَه يَعني حظراً', () {
      expect(accountIsBlocked({'is_blocked': true}), isTrue);
      expect(accountIsBlocked({'status': 'banned'}), isTrue);
      expect(accountIsBlocked({'is_blocked': true, 'status': 'active'}), isTrue);
    });

    test('غيابُ العلمَين — أو مستندٌ غائبٌ — ليس حظراً', () {
      expect(accountIsBlocked({}), isFalse);
      expect(accountIsBlocked(null), isFalse);
      expect(accountIsBlocked({'status': 'active'}), isFalse);
      expect(accountIsBlocked({'is_blocked': false}), isFalse);
    });

    test('قيمةٌ غيرُ منطقيّةٍ لا تُقرأُ حظراً (لا `== true` ضمنيّ)', () {
      // حقلٌ نصّيٌّ تالفٌ لا يَجوزُ أن يُنهي جلسةَ عميلةٍ سليمة.
      expect(accountIsBlocked({'is_blocked': 'true'}), isFalse);
      expect(accountIsBlocked({'is_blocked': 1}), isFalse);
      expect(accountIsBlocked({'status': 'Banned'}), isFalse);
    });

    test('الجملةُ محيَّدةُ الجنسِ — ثلاثةُ أدوارٍ تَقرؤها', () {
      // الصيغةُ المؤنَّثةُ هنا خطأٌ لا إصلاح: شاشةُ الترحيبِ هي ما يَبلغُه
      // كلُّ خارجٍ من الجلسة، سائقاً كان أو إدارةً أو عميلة.
      for (final v in const ['تواصلي', 'أعيدي', 'حاولي', 'أنتِ', 'تأكّدي']) {
        expect(kAccountBlockedNotice, isNot(contains(v)),
            reason: 'الجملةُ تُؤنِّثُ الخطابَ («$v») وهي لثلاثةِ أدوار');
      }
      expect(kAccountBlockedNotice, contains('الدعم'),
          reason: 'الجملةُ لا تَدلُّ على المَخرَج');
      expect(kAccountBlockedNotice.trim(), isNotEmpty);
    });
  });

  group('الوصل — المُنفِّذُ والقارئُ والشارة', () {
    final String prov =
        File('lib/providers/user_provider.dart').readAsStringSync();
    final String provCode = stripComments(prov);
    final String main = File('lib/main.dart').readAsStringSync();
    final String mainCode = stripComments(main);
    final String admin =
        File('lib/screens/admin/admin_users_screen.dart').readAsStringSync();
    final String adminCode = stripComments(admin);

    test('المزوّدُ يُنادي القاعدةَ ولا يَقرأُ العلمَين بنفسِه', () {
      expect(provCode, contains('accountIsBlocked(data)'),
          reason: 'المزوّدُ لا يُنادي القاعدة');
      expect(provCode, isNot(contains("data['is_blocked']")),
          reason: 'نسخةٌ إنلاين باقيةٌ في المزوّد');
      expect(provCode, isNot(contains("data['status'] == 'banned'")),
          reason: 'نسخةٌ إنلاين باقيةٌ في المزوّد');
      // مضادّةٌ: الشرحُ الذي يَحكي الصيغةَ القديمةَ ما زال في الخامّ، فلا
      // يُجوِّفُ التجريدُ الفحصَ أعلاه.
      expect(prov, contains('is_blocked'),
          reason: 'شرحُ الصيغةِ القديمةِ زالَ من المزوّد');
    });

    test('السببُ يُحفَظُ **قبلَ** الخروج — وإلّا لم يَبقَ ما يُعرَض', () {
      final int iFlag = provCode.indexOf('_sessionEndedNotice = kAccountBlockedNotice');
      expect(iFlag, greaterThan(0), reason: 'المزوّدُ لا يَحفظُ سببَ الخروج');
      final int iOut = provCode.indexOf('signOut()', iFlag);
      expect(iOut, greaterThan(iFlag),
          reason: 'الخروجُ يَسبقُ حفظَ السبب — فالواجهةُ لا تَجدُ شيئاً');
      // ولا بين الاثنَين فرعٌ يَرجع.
      expect(provCode.substring(iFlag, iOut), isNot(contains('return')),
          reason: 'رجوعٌ بين الحفظِ والخروج');
    });

    test('فرعُ «خروجٌ حقيقيّ» لا يَمسحُ السببَ', () {
      // يَمسحُ `_user`/`_role`/`_profileError` — ولو مَسحَ السببَ لَضاعَ
      // قبلَ أن تُرسَمَ الشاشة، فيَعودُ الصمتُ بزينةٍ فوقَه.
      final int i = provCode.indexOf('firebaseUser == null');
      expect(i, greaterThan(0));
      final int j = provCode.indexOf('} else {', i);
      expect(j, greaterThan(i));
      expect(provCode.substring(i, j),
          isNot(contains('_sessionEndedNotice = null')),
          reason: 'فرعُ الخروجِ يَمسحُ السببَ قبلَ عرضِه');
    });

    test('جلسةٌ حيّةٌ جديدةٌ تَمسحُ السببَ (لا يَلتصقُ بالتالية)', () {
      final int i = provCode.indexOf('Future<void> refreshUser(');
      expect(i, greaterThan(0));
      final int j = provCode.indexOf('notifyListeners();', i);
      expect(j, greaterThan(i));
      expect(provCode.substring(i, j), contains('_sessionEndedNotice = null'),
          reason: 'refreshUser لا يَمسحُ السببَ — فيُعرَضُ على جلسةٍ سليمة');
    });

    test('شاشةُ الترحيبِ لا تُعرَضُ قبلَ قراءةِ السبب', () {
      final int iNotice = mainCode.indexOf('userProvider.sessionEndedNotice');
      expect(iNotice, greaterThan(0),
          reason: 'AuthWrapper لا يَقرأُ سببَ إنهاءِ الجلسة');
      final int iOnb = mainCode.indexOf('return const OnboardingScreen();');
      expect(iOnb, greaterThan(0));
      expect(iNotice, lessThan(iOnb),
          reason: 'شاشةُ الترحيبِ تَسبقُ القراءةَ — فالسببُ لا يُرى أبداً');
      expect(mainCode, contains('_SessionEndedScreen('),
          reason: 'لا شاشةَ تُسمّي السبب');
    });

    test('الشاشةُ تَعرضُ الجملةَ وتَمسحُها بزرٍّ موصول', () {
      final int i = mainCode.indexOf('class _SessionEndedScreen');
      expect(i, greaterThan(0));
      final String body = mainCode.substring(i);
      expect(body, contains('Text(\n                  notice,'),
          reason: 'الشاشةُ لا تَعرضُ النصَّ المُمرَّر');
      expect(body, contains('provider.clearSessionEndedNotice'),
          reason: 'الزرُّ لا يَمسحُ السببَ — فالشاشةُ لا تُغادَر');
    });

    test('شارةُ شاشةِ المستخدمينَ تُنادي القاعدةَ نفسَها', () {
      expect(adminCode, contains('accountIsBlocked(user)'),
          reason: 'الشارةُ لا تُنادي القاعدة');
      expect(adminCode, isNot(contains("user['status'] == 'banned' ||")),
          reason: 'نسخةٌ إنلاين باقيةٌ في شاشةِ المستخدمين');
    });

    test('لا نسخةَ ثالثةً في `lib/` — القاعدةُ تَسكنُ موضعاً واحداً', () {
      final re = RegExp(r"\['status'\]\s*==\s*'banned'|\['is_blocked'\]\s*==\s*true");
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.path.endsWith('utils/account_block.dart')) continue;
        if (re.hasMatch(stripComments(e.readAsStringSync()))) hits.add(e.path);
      }
      // الباقي المسموحُ: شاشةُ المستخدمينَ تَقرأُ `is_blocked` **وحدَه** لتُفرّق
      // «حظرٌ مثبَّتٌ بالعلمِ القديم» (رفعُه للمدير العامِّ وحدَه) من حظرِ
      // `status` — وهو سؤالٌ آخرُ غيرُ «أمحظورٌ هو؟».
      expect(hits, ['lib/screens/admin/admin_users_screen.dart'],
          reason: 'نسخةٌ جديدةٌ من قاعدةِ الحظر: $hits');
    });
  });

  // **ولا فحصَ واجهةٍ هنا بقصد.** `_SessionEndedScreen` خاصّةٌ بـ`main.dart`
  // و`ZyiarahUserProvider` يَلمسُ `FirebaseAuth.instance` في مُنشِئه، فاختبارُ
  // واجهةٍ يُركّبُ ودجةً **مُصطنَعةً** تُشبهُها لا يَفحصُ شيئاً — وفحصٌ لا
  // يَعضُّ أسوأُ من لا فحص. المشدودُ أعلاه هو ما يَحملُ القرارَ: الترتيبُ،
  // والنصُّ المُمرَّرُ لا حرفيٌّ، والزرُّ موصولٌ بالمَحو.
  group('الشاشةُ — بنيةٌ لا نسخةٌ مُصطنَعة', () {
    final String mainCode = stripComments(File('lib/main.dart').readAsStringSync());

    test('الشاشةُ RTL ولا تَكتبُ الجملةَ حرفيّاً', () {
      final int i = mainCode.indexOf('class _SessionEndedScreen');
      expect(i, greaterThan(0));
      final String body = mainCode.substring(i);
      expect(body, contains('textDirection: TextDirection.rtl'),
          reason: 'الشاشةُ ليست RTL — نصٌّ عربيٌّ بتخطيطٍ يساريّ');
      expect(body, isNot(contains('تم إيقاف هذا الحساب')),
          reason: 'الجملةُ مكتوبةٌ حرفيّاً في الشاشة — نسخةٌ ثانيةٌ تَنحرِف');
    });
  });
}
