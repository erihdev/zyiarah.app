import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/deletion_log_row.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **سجلُّ حذفِ الحساب لا يُسمّي أحداً — والدَّينُ مكتوبٌ في حقلٍ لا
/// يَقرؤه سطح (2026-10-08).**
///
/// `account_deletions/{uid}` مسارُ امتثالٍ (متطلّبُ Apple) ويُعرَضُ في
/// سطحَين. وفيه ثلاثُ حالاتٍ من عائلةِ «قارئٌ بلا كاتب»:
///
/// (١) **الدَّين.** الخادمُ يَقرأُ رصيدَ المحفظةِ قبلَ حذفِ هويّةِ
/// المصادقةِ ويَكتبُه `wallet_balance_at_deletion`، وتعليقُه يَقولُ السببَ
/// نصّاً: «كي يبقى الدَّينُ مكتوباً **في مكانٍ يَقرؤه البشرُ**». وكان
/// **مكتوباً في موضعٍ ومقروءاً في صفر** — فالنصفُ الدائمُ من ذلك الإصلاحِ
/// لم يَصِلْ عيناً.
///
/// (٢) **الهويّة.** اللوحةُ تَعرِضُ `name` فوقَ `phone` — و`name` لا
/// يَكتبُه كاتبٌ قطّ، و`phone` يَكتبُه مسارُ العميلةِ من
/// `user?.phoneNumber` والمصادقةُ **بالبريدِ وحدَه** فهو `null` دائماً.
/// فكلُّ صفٍّ كان «— / —»، و`email` مكتوبٌ ولا تَقرؤه اللوحةُ إطلاقاً
/// (وشاشةُ التطبيقِ تَقرؤه صحيحاً: سطحٌ من اثنَين).
///
/// (٣) **`userId`** — شرطُ `if (req.userId)` في اللوحةِ كاذبٌ دائماً،
/// فسطرُ `deleteDoc(users/…)` ميّت؛ ولو عَمِلَ لكانَ خطأً بنصِّ تعليقِ
/// `admin_users_screen`.

/// جسمُ `processAccountDeletion` وحدَه. **فحصُ ترتيبٍ على الملفِّ كلِّه
/// يُرضيه موضعٌ آخر:** `collection("wallets")` يَرِدُ في مسارِ الدفعِ
/// بالمحفظةِ أعلى الملفِّ بآلافِ الأسطر، فمقارنةُ أوّلِ ورودٍ بـ
/// `getAuth().deleteUser(` كانت صحيحةً أبداً — ومرَّ قضمٌ ينقلُ قراءةَ
/// المحفظةِ **بعدَ** حذفِ المصادقةِ أخضرَ. (فخُّ «موضعٌ آخرُ يُرضي الفحصَ»
/// مسجَّلٌ في هذا المستودعِ ثلاثَ مرّات.)
String _deletionFnBody(String idx) {
  final String code = stripComments(idx);
  final int a = code.indexOf('async function processAccountDeletion(');
  if (a < 0) throw StateError('لم يُعثَر على processAccountDeletion');
  final int b = code.indexOf('\nexports.onAccountDeletionRequested', a);
  if (b <= a) throw StateError('اقتطاعٌ فاشلٌ لجسمِ processAccountDeletion');
  return code.substring(a, b);
}

void main() {
  final String flutterScreen =
      File('lib/screens/admin/admin_deletions_screen.dart').readAsStringSync();
  final String adminWriter =
      File('lib/screens/admin/admin_users_screen.dart').readAsStringSync();
  final String clientWriter =
      File('lib/screens/profile_screen.dart').readAsStringSync();
  final String panel =
      File('admin_panel/src/pages/AccountDeletion.tsx').readAsStringSync();
  final String idx = File('functions/index.js').readAsStringSync();

  // ===== سلوكُ القاعدة =====

  test('(أ) الهويّةُ: البريدُ ثمّ الاسمُ ثمّ الجوّال، ولا ادّعاءَ بلا شيء', () {
    expect(deletionRowIdentity({'email': 'a@b.com', 'name': 'نورة'}), 'a@b.com');
    expect(deletionRowIdentity({'name': 'نورة'}), 'نورة');
    expect(deletionRowIdentity({'phone': '0500000000'}), '0500000000');
    expect(deletionRowIdentity({}), 'حساب مجهول');
    expect(deletionRowIdentity(null), 'حساب مجهول');
    expect(deletionRowIdentity({'email': '   '}), 'حساب مجهول');
  });

  test('(ب) الدَّين: صفرٌ ليس دَيناً، وغيابُ الحقلِ ليس صفراً', () {
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': 172.5}), 172.5);
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': 0}), isNull);
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': -5}), isNull);
    expect(deletionStrandedBalance({}), isNull);
    expect(deletionStrandedBalance(null), isNull);
    // مستندٌ كُتبَ بيدٍ قد يَحملُ نصّاً.
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': '172.5'}), 172.5);
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': 'abc'}), isNull);
    // `Number(true) == 1` فخٌّ مسجَّل — لا يُقرأُ ريالاً.
    expect(deletionStrandedBalance({'wallet_balance_at_deletion': true}), isNull);
  });

  test('(ج) سطرُ الدَّينِ يُسمّي المبلغَ ويَغيبُ متى لا دَين', () {
    expect(deletionStrandedNotice({'wallet_balance_at_deletion': 172.5}),
        contains('172.50'));
    expect(deletionStrandedNotice({'wallet_balance_at_deletion': 172.5}),
        contains('يدوية'));
    expect(deletionStrandedNotice({}), isNull);
  });

  // ===== جدولُ الحالاتِ واحدٌ بين اللغتَين =====

  test('(د) جدولُ الحالاتِ مشترَكٌ مع مرآةِ اللوحة', () {
    final String ts =
        File('admin_panel/src/utils/deletionLogRow.test.ts').readAsStringSync();
    const a = 'DELETION_ROW_CASES_START';
    const b = 'DELETION_ROW_CASES_END';
    expect(ts.contains(a) && ts.contains(b), isTrue,
        reason: 'زالت علامةُ جدولِ الحالاتِ من مرآةِ اللوحة');
    final String mid = ts.substring(ts.indexOf(a) + a.length, ts.indexOf(b));
    // الاقتطاعُ من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس: `indexOf('[')`
    // يَلتقِطُ قوسَ تعليقِ النوعِ (`[...][]`) لا بدايةَ المصفوفة.
    final int end = mid.lastIndexOf(']');
    expect(end, greaterThan(0));
    int depth = 0;
    int start = -1;
    for (int i = end; i >= 0; i--) {
      if (mid[i] == ']') depth++;
      if (mid[i] == '[') {
        depth--;
        if (depth == 0) {
          start = i;
          break;
        }
      }
    }
    expect(start, greaterThanOrEqualTo(0), reason: 'اقتطاعٌ غيرُ مُوازَن');
    String raw = mid.substring(start, end + 1);
    // مفاتيحُ TS بلا اقتباسٍ، و`undefined` ليست JSON — ولا نُستعملُها.
    raw = raw.replaceAllMapped(
        RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'), (m) =>
            '${m.group(1)}"${m.group(2)}":');
    raw = raw.replaceAll("'", '"');
    raw = raw.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
    final List<dynamic> cases = jsonDecode(raw) as List<dynamic>;
    expect(cases.length, greaterThanOrEqualTo(12),
        reason: 'انحلَّ جدولُ الحالات');
    for (final c in cases) {
      final Map<String, dynamic>? d =
          c[0] == null ? null : Map<String, dynamic>.from(c[0] as Map);
      expect(deletionRowIdentity(d), c[1], reason: 'هويّةُ $d');
      final Object? want = c[2];
      final double? got = deletionStrandedBalance(d);
      if (want == null) {
        expect(got, isNull, reason: 'دَينُ $d');
      } else {
        expect(got, (want as num).toDouble(), reason: 'دَينُ $d');
      }
    }
  });

  // ===== السطحانِ يُنادِيانِ القاعدةَ ويَعرِضانِ الدَّين =====

  test('(هـ) شاشةُ التطبيقِ تُنادي القاعدةَ وتَعرِضُ سطرَ الدَّين', () {
    final String code = stripComments(flutterScreen);
    expect(RegExp(r'\bdeletionRowIdentity\s*\(').hasMatch(code), isTrue);
    expect(RegExp(r'\bdeletionStrandedNotice\s*\(').hasMatch(code), isTrue,
        reason: 'الدَّينُ ما زال بلا قارئٍ في شاشةِ التطبيق');
    expect(code.contains("req['email'] ?? req['phone']"), isFalse,
        reason: 'عادت نسخةٌ إنلاين من سلسلةِ الهويّة');
  });

  test('(و) لوحةُ الويبِ تُنادي القاعدةَ وتَعرِضُ الدَّينَ ولا تَحذفُ users',
      () {
    final String code = stripComments(panel);
    expect(RegExp(r'\bdeletionRowIdentity\s*\(').hasMatch(code), isTrue);
    expect(RegExp(r'\bdeletionStrandedBalance\s*\(').hasMatch(code), isTrue,
        reason: 'الدَّينُ ما زال بلا قارئٍ في اللوحة');
    expect(code.contains("req.name ?? '—'"), isFalse,
        reason: 'عادت قراءةُ `name` التي لا كاتبَ لها');
    expect(RegExp(r'deleteDoc\s*\(').hasMatch(code), isFalse,
        reason: 'عادَ حذفُ `users` المباشرُ — وهو ما يَفعلُه الخادمُ وحدَه');
    expect(code.contains('req.userId'), isFalse,
        reason: 'عادت قراءةُ `userId` التي لا كاتبَ لها');
    // البحثُ يُرشِّحُ ما يُعرَضُ فعلاً لا حقلاً غائباً.
    expect(code.contains('r.name?.includes'), isFalse,
        reason: 'البحثُ عادَ إلى حقلٍ لا كاتبَ له فصارَ ميّتاً');
  });

  test('(ز) `type` لا يُدَّعى متى لم يُكتَب', () {
    final String code = stripComments(panel);
    expect(code.contains('{req.type ?'), isTrue,
        reason: 'كلُّ صفٍّ يُوسَمُ «عميل» وإن كان حذفَ سائق');
  });

  // ===== الكاتبانِ والخادمُ: كلُّ حقلٍ يُعرَضُ له كاتب =====

  test('(ح) كلُّ حقلٍ يَقرؤه السطحانِ للعرضِ له كاتبٌ في المستودع', () {
    final Set<String> written = {};
    for (final src in [adminWriter, clientWriter, idx]) {
      final String code = stripComments(src);
      for (final m
          in RegExp(r"account_deletions").allMatches(code)) {
        // حِملُ الكتابةِ يَبدأُ بأقربِ `{` بعدَ الموضع، بموازنةِ المعقوفة.
        final int b = code.indexOf('{', m.end);
        if (b < 0) continue;
        int depth = 0;
        int j = b;
        while (j < code.length) {
          if (code[j] == '{') depth++;
          if (code[j] == '}') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        if (j - b > 1200) continue; // ليست كتابةً بل استعلامٌ أو تعليق
        final String body = code.substring(b, j + 1);
        for (final f in RegExp(r"""['"]?([a-z_][a-z0-9_]*)['"]?\s*:""")
            .allMatches(body)) {
          written.add(f.group(1)!);
        }
      }
    }
    expect(written.length, greaterThanOrEqualTo(8),
        reason: 'انحلَّ استخراجُ الحقولِ المكتوبة — اشتقاقٌ فاشلٌ لا مستودعٌ أصغر');
    // كلُّ حقلٍ تَقرؤه القاعدةُ للعرضِ لا بدّ أن يَكتبَه كاتب.
    for (final f in const [
      'email',
      'name',
      'phone',
      'wallet_balance_at_deletion',
      'status',
      'requested_at',
    ]) {
      expect(written.contains(f), isTrue,
          reason: 'الحقلُ «$f» يُعرَضُ ولا كاتبَ له');
    }
    // `userId` و`type` لا كاتبَ لهما — فلا يُقرآنِ قراراً.
    expect(written.contains('userId'), isFalse,
        reason: 'ظهرَ كاتبٌ لـ`userId` — يُراجَعُ قرارُ إسقاطِ قراءتِه');
  });

  test('(ط) تعليلُ الدَّينِ خادميٌّ قائم: الرصيدُ يُقرأُ قبلَ حذفِ المصادقة',
      () {
    final String body = _deletionFnBody(idx);
    final int iWallet = body.indexOf('collection("wallets")');
    final int iAuth = body.indexOf('getAuth().deleteUser(');
    expect(iWallet, greaterThan(0), reason: 'لا قراءةَ للمحفظةِ في الدالّة');
    expect(iAuth, greaterThan(0));
    expect(iWallet, lessThan(iAuth),
        reason: 'قراءةُ المحفظةِ بعدَ حذفِ المصادقةِ لا تَمنعُ شيئاً');
    expect(body.contains('wallet_balance_at_deletion'), isTrue);
    // ومضادّةٌ: الشرحُ الذي يَقتبسُ السببَ ما زال في الخامّ.
    expect(idx.contains('يَقرؤه البشرُ'), isTrue,
        reason: 'زالَ الشرحُ الذي يُعلّلُ كتابةَ الدَّينِ على الطلب');
  });

  test('(ي) لا كاتبَ يُنشئُ الطلبَ بحالةِ `pending` — فسطحا المراجعةِ سجلّان',
      () {
    // الكاتبانِ كلاهما `status: 'deleted'`، فالمُشغّلُ يَعمَلُ فوراً
    // والحذفُ كاملٌ خادميّاً. فواجهةُ «قبول/رفض» لا تُعرَضُ قطّ — تُركت
    // كما هي (قرارُ «لا تُلمَسْ شفرةٌ سليمة»)، وهذا الفحصُ يُبقي الحقيقةَ
    // مقروءةً: لو ظهرَ كاتبٌ لـ`pending` فتلك الواجهةُ تَصيرُ حيّةً
    // ويُراجَعُ ما حولَها.
    for (final src in [adminWriter, clientWriter]) {
      expect(stripComments(src).contains("'status': 'pending'"), isFalse);
    }
    // والخادمُ لا يُنشئُ المستندَ أصلاً: كتابتاه `update` وحالتاهما
    // `deleted_fully_processed` و`failed_deletion`. والنطاقُ جسمُ الدالّةِ
    // وحدَه — `status: "pending"` يَرِدُ في `index.js` لمجموعاتٍ أخرى
    // (طلبات، عقود) فمسحُ الملفِّ كلِّه إيجابيّةٌ كاذبة.
    final String body = _deletionFnBody(idx);
    expect(body.contains('status: "pending"'), isFalse);
    expect(body.contains('status: "deleted_fully_processed"'), isTrue);
    expect(body.contains('.update('), isTrue);
    expect(body.contains('.set('), isFalse,
        reason: 'الخادمُ صارَ يُنشئُ الطلبَ — يُراجَعُ التعليل');
  });

  test('(ك) الأرضيّة: المسحُ قرأَ ملفّاتٍ فعلاً', () {
    expect(sourcesIn('lib/screens/admin', atLeast: 20).isNotEmpty, isTrue);
  });
}
