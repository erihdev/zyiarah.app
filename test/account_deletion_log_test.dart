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

/// كتابةُ حالةٍ بعينِها في أيِّ لغةٍ من السطحَين (دارت `'status': 'x'`،
/// وTS `status: 'x'`).
final RegExp _deletedWrite =
    RegExp('''['"]?status['"]?\\s*:\\s*['"]deleted['"]''');

/// جدولُ حالاتٍ مشترَكٌ من ملفِّ فحصِ اللوحة، بين علامتَي `<marker>_START`
/// و`_END`. والاقتطاعُ **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**:
/// `indexOf('[')` يَلتقِطُ قوسَ تعليقِ النوعِ (`[...][]`) لا بدايةَ
/// المصفوفة — فخٌّ مسجَّلٌ في هذا المستودع.
List<dynamic> _sharedTable(String ts, String marker) {
  final String a = '${marker}_START';
  final String b = '${marker}_END';
  if (!ts.contains(a) || !ts.contains(b)) {
    throw StateError('زالت علامةُ $marker من مرآةِ اللوحة');
  }
  final String mid = ts.substring(ts.indexOf(a) + a.length, ts.indexOf(b));
  final int end = mid.lastIndexOf(']');
  if (end <= 0) throw StateError('لا مصفوفةَ في $marker');
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
  if (start < 0) throw StateError('اقتطاعٌ غيرُ مُوازَنٍ في $marker');
  String raw = mid.substring(start, end + 1);
  // مفاتيحُ TS بلا اقتباسٍ، والفاصلةُ المتدلّيةُ ليست JSON.
  raw = raw.replaceAllMapped(
      RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
      (m) => '${m.group(1)}"${m.group(2)}":');
  raw = raw.replaceAll("'", '"');
  raw = raw.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
  return jsonDecode(raw) as List<dynamic>;
}

/// جسمُ دالّةٍ من موضعِ إعلانِها بموازنةِ المعقوفة — **بعدَ** موازنةِ
/// قائمةِ المعامَلات. (أخذُ أوّلِ `{` بعدَ الاسمِ يَلتقِطُ قوسَ
/// المعامَلاتِ المُسمّاةِ في دارت لا الجسمَ: فخٌّ مسجَّلٌ في هذا
/// المستودعِ سبعَ مرّات.)
String _fnBody(String code, String decl) {
  final int a = code.indexOf(decl);
  if (a < 0) throw StateError('لم يُعثَر على «$decl»');
  int i = a + decl.length - 1; // عند قوسِ النداء
  int depth = 0;
  while (i < code.length) {
    if (code[i] == '(') depth++;
    if (code[i] == ')') {
      depth--;
      if (depth == 0) break;
    }
    i++;
  }
  final int b = code.indexOf('{', i);
  if (b < 0) throw StateError('لا جسمَ لـ«$decl»');
  depth = 0;
  int j = b;
  while (j < code.length) {
    if (code[j] == '{') depth++;
    if (code[j] == '}') {
      depth--;
      if (depth == 0) break;
    }
    j++;
  }
  if (depth != 0) throw StateError('اقتطاعٌ غيرُ مُوازَنٍ لـ«$decl»');
  return code.substring(b, j + 1);
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
    final List<dynamic> cases = _sharedTable(ts, 'DELETION_ROW_CASES');
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
    // كما هي (قرارُ مالكٍ 2026-07-21 يَحرُسُه `admin_ban_reject_test`:
    // «رفض الطلب بدل الحذف الإجباري»)، وهذا الفحصُ يُبقي الحقيقةَ
    // مقروءةً: لو ظهرَ كاتبٌ لـ`pending` فتلك الواجهةُ تَصيرُ حيّةً
    // ويُراجَعُ ما حولَها.
    //
    // **وما تغيّر (2026-10-08):** كان الفحصُ يَكتفي بذلك، فبقيَ **الفشلُ**
    // مُعلَّقاً على الحالةِ الميتةِ نفسِها — `failed_deletion` يَقولُ عنه
    // السطحانِ «يتطلب مراجعة» والأزرارُ محصورةٌ بـ`'pending'`، فلا زرَّ
    // ولا سببَ ولا تنبيه. فالقرارُ لم يُنقَض، وإنّما **فُصِلَ مَخرَجُ
    // الفشلِ عنه** وشُدَّ في (س) و(ع).
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
    // وزوجُ `pending` باقٍ في السطحَين كما قرَّرَ المالك — فإسقاطُه ليس
    // إصلاحاً لهذا العطل، وهذا الفحصُ يَمنعُ أن يُسقَطَ بحجّتِه.
    expect(stripComments(flutterScreen).contains("status == 'pending'"), isTrue,
        reason: 'زالَ زوجُ `pending` من شاشةِ التطبيق — وهو قرارُ مالك');
    expect(stripComments(panel).contains("req.status === 'pending'"), isTrue,
        reason: 'زالَ زوجُ `pending` من اللوحة — وهو قرارُ مالك');
  });

  // ===== فشلُ الحذفِ: يُقالُ، ويُقرأُ سببُه، ويُعادُ تشغيلُه =====

  test('(ل) حالةُ الطلبِ: `deleted` ليست «تمَّ»، و`pending` غيرُ معروفة', () {
    expect(deletionRequestState('deleted'), DeletionRequestState.inProgress);
    expect(deletionRequestState('deleted_fully_processed'),
        DeletionRequestState.completed);
    expect(deletionRequestState('failed_deletion'), DeletionRequestState.failed);
    expect(deletionRequestState('rejected'), DeletionRequestState.rejected);
    // افتراضُ السطحَين القديمُ — ولا كاتبَ له، فلا ندّعي عنه.
    expect(deletionRequestState('pending'), DeletionRequestState.unknown);
    expect(deletionRequestState(null), DeletionRequestState.unknown);
    expect(deletionRequestState(7), DeletionRequestState.unknown);
    // و«تمَّ نهائياً» تُقالُ للمكتملِ وحدَه: دمجُ `deleted` معه كان دعوى
    // إتمامٍ على حالةٍ قد تَعلَق.
    expect(deletionStateLabel(DeletionRequestState.completed),
        'تم الحذف نهائياً');
    expect(deletionStateLabel(DeletionRequestState.inProgress),
        isNot(contains('نهائياً')));
  });

  test('(م) إعادةُ المحاولة: الفشلُ دائماً، والعالقُ بعدَ المُهلة، ولا جهل',
      () {
    final DateTime now = DateTime(2026, 10, 8, 12);
    final DateTime old = now.subtract(kDeletionStuckGrace * 2);
    final DateTime fresh = now.subtract(const Duration(seconds: 5));
    bool r(DeletionRequestState s, DateTime? at) =>
        deletionRetryAllowed(state: s, requestedAt: at, now: now);
    expect(r(DeletionRequestState.failed, null), isTrue);
    expect(r(DeletionRequestState.failed, fresh), isTrue);
    expect(r(DeletionRequestState.inProgress, old), isTrue);
    // تنفيذٌ جارٍ: لا نُعيدُ تشغيلَه فوقَ نفسِه.
    expect(r(DeletionRequestState.inProgress, fresh), isFalse);
    expect(r(DeletionRequestState.inProgress, null), isFalse);
    expect(r(DeletionRequestState.completed, old), isFalse);
    expect(r(DeletionRequestState.rejected, old), isFalse);
    // الجهلُ لا يُعاد تشغيلُه: الحذفُ لا رجعةَ فيه.
    expect(r(DeletionRequestState.unknown, old), isFalse);
  });

  test('(ن) سببُ الفشلِ يُقرَأُ ويُقلَّم', () {
    expect(deletionFailureReason({'error': 'auth/internal-error'}),
        'auth/internal-error');
    expect(deletionFailureReason({'error': '  x  '}), 'x');
    expect(deletionFailureReason({'error': ''}), isNull);
    expect(deletionFailureReason({}), isNull);
    expect(deletionFailureReason(null), isNull);
  });

  test('(س) السطحانِ يُنادِيانِ القاعدةَ ويَعرِضانِ السببَ ويُعيدانِ التشغيل',
      () {
    for (final e in {'التطبيق': flutterScreen, 'اللوحة': panel}.entries) {
      final String code = stripComments(e.value);
      for (final f in const [
        'deletionRequestState',
        'deletionStateLabel',
        'deletionRetryAllowed',
        'deletionFailureReason',
      ]) {
        expect(RegExp('\\b$f\\s*\\(').hasMatch(code), isTrue,
            reason: '${e.key}: لا يُنادي $f — فالقاعدةُ في موضعٍ واحدٍ '
                'وهذا السطحُ يُعدِّدُ بنفسِه');
      }
    }
    // **والكتابةُ في مسارِ الإعادةِ بعينِه، لا في الملفّ.** صياغةٌ أولى
    // طلبت ورودَ `status: 'deleted'` في السطحِ كلِّه، فمرَّ قضمٌ بدَّلَ
    // كتابةَ زرِّ الإعادةِ **أخضرَ**: زرُّ `pending` المجاورُ يَكتبُها
    // أيضاً فأرضَى الفحصَ — «موضعٌ آخرُ يُرضي الفحصَ» للمرّةِ الخامسةِ
    // في هذا المستودع.
    expect(
        _deletedWrite.hasMatch(
            _fnBody(stripComments(flutterScreen), '_retryButton(')),
        isTrue,
        reason: 'زرُّ إعادةِ المحاولةِ في التطبيقِ لا يَكتبُ الحالةَ التي '
            'تُطلِقُ المُشغّل');
    expect(
        _deletedWrite.hasMatch(
            _fnBody(stripComments(panel), 'handleRetry = async (')),
        isTrue,
        reason: 'إعادةُ المحاولةِ في اللوحةِ لا تَكتبُ الحالةَ التي '
            'تُطلِقُ المُشغّل');
    // **والإجراءُ نفسُه مشروطٌ بالقاعدة، لا بحضورِ نداءٍ في مكانٍ آخر.**
    // اختبارُ قضمٍ أسقطَ `deletionRetryAllowed` من خليّةِ الإجراءِ في
    // اللوحةِ واستبدلَها بـ`state === 'failed'` فمرَّ **أخضرَ**: النداءُ
    // باقٍ في العدّادِ فوقَ الجدول، والصفُّ العالقُ يَفقدُ زرَّه — «موضعٌ
    // آخرُ يُرضي الفحصَ» للمرّةِ الرابعةِ في هذا المستودع.
    expect(
        RegExp(r'\bdeletionRetryAllowed\s*\(')
            .allMatches(stripComments(panel))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'اللوحةُ تُنادي القاعدةَ في موضعٍ واحدٍ — فأحدُهما '
            '(العدّادُ أو زرُّ الإجراء) يُقرّرُ بتعدادٍ من عندِه');
    expect(stripComments(flutterScreen).contains('trailing: canRetry'), isTrue,
        reason: 'إجراءُ شاشةِ التطبيقِ لم يَعُد مشروطاً بناتجِ القاعدة');
  });

  test('(ع) الخادمُ يُنبّهُ عند الفشلِ — وكان الوسمُ كلَّ ما يَحدث', () {
    final String body = _deletionFnBody(idx);
    final int iMark = body.indexOf('status: "failed_deletion"');
    expect(iMark, greaterThan(0));
    // الدفعةُ **بعدَ** الوسم: أوّلُ ما يَلزمُ أن يَثبُتَ هو الحالةُ على
    // المستند، ثمّ يُقالَ للبشر.
    final int iPush = body.indexOf('queuePush(', iMark);
    expect(iPush, greaterThan(iMark),
        reason: 'فشلُ حذفٍ يَلزمُه متطلّبُ آبل بلا تنبيه — الوسمُ وحدَه '
            'لا يَقرؤه أحدٌ إلّا بمحضِ المصادفة');
    // **وحضورُ النداءِ ليس تشغيلَه.** اختبارُ قضمٍ غلَّفَه بـ`if (false)`
    // فمرَّ **أخضرَ**: الفحصُ رَضيَ بورودِ النصِّ. فالمشدودُ أنّه جملةٌ
    // غيرُ مشروطةٍ — بلا أيِّ `if (` بين الوسمِ والدفعة — وأنّه يَبدأُ
    // سطرَه بـ`await`. («الاسمُ ليس القدرة»، وقد وقعَ على حارسِ
    // `syncRoleToPushToken` بالصيغةِ نفسِها.)
    expect(body.substring(iMark, iPush).contains('if ('), isFalse,
        reason: 'الدفعةُ مشروطةٌ — ففشلٌ قد يَقعُ بلا تنبيه');
    expect(body.contains('\n    await queuePush("ADMIN_BROADCAST", '
        '"فشلَ حذفُ حساب'), isTrue,
        reason: 'الدفعةُ لم تَعُد جملةً مستقلّةً غيرَ مشروطة');
    // والجمهورُ `super_admin` وحدَه: القاعدةُ تَحصُرُ قراءةَ المجموعةِ به.
    final int iAud = body.indexOf('["super_admin"]', iPush);
    expect(iAud, greaterThan(iPush),
        reason: 'جمهورُ تنبيهِ الفشلِ ليس `super_admin` وحدَه — '
            'والقواعدُ تَحصُرُ قراءةَ `account_deletions` به');
    // وفشلُ الدفعةِ نفسِه لا يَحجبُ الوسمَ (سابقةُ دفعةِ الرصيدِ المحجوز).
    expect(body.substring(iPush).contains('.catch('), isTrue,
        reason: 'فشلُ الدفعةِ يَرمي فوقَ خطأٍ أصليٍّ فيُخفيه');
    // ومضادّةٌ: الشرحُ الذي يَقتبسُ العطلَ ما زال في الخامّ.
    expect(idx.contains('ترِدُ في هذا'), isTrue,
        reason: 'زالَ الشرحُ الذي يُعلّلُ التنبيه');
    // وقاعدةُ الوصولِ التي يَقومُ عليها اختيارُ الجمهورِ ما زالت كما هي.
    expect(
        File('firestore.rules')
            .readAsStringSync()
            .contains('allow read, update, delete: if isSuperAdmin();'),
        isTrue,
        reason: 'تغيّرت قاعدةُ قراءةِ `account_deletions` — يُراجَعُ جمهورُ '
            'التنبيه');
  });

  test('(ف) جدولُ حالاتِ الحالةِ مشترَكٌ بين اللغتَين', () {
    final String ts =
        File('admin_panel/src/utils/deletionLogRow.test.ts').readAsStringSync();
    final List<dynamic> cases = _sharedTable(ts, 'DELETION_STATE_CASES');
    expect(cases.length, greaterThanOrEqualTo(10),
        reason: 'انحلَّ جدولُ حالاتِ الحالة');
    // الأصنافُ المُسمّاةُ لا حدٌّ عدديٌّ وحدَه.
    for (final want in const ['deleted', 'failed_deletion', 'pending']) {
      expect(cases.any((c) => c[0] == want), isTrue,
          reason: 'صنفٌ مفقودٌ من الجدول: $want');
    }
    const Map<String, DeletionRequestState> byName = {
      'inProgress': DeletionRequestState.inProgress,
      'completed': DeletionRequestState.completed,
      'failed': DeletionRequestState.failed,
      'rejected': DeletionRequestState.rejected,
      'unknown': DeletionRequestState.unknown,
    };
    for (final c in cases) {
      final DeletionRequestState got = deletionRequestState(c[0]);
      expect(got, byName[c[1]], reason: 'حالةُ ${c[0]}');
      expect(deletionStateLabel(got), c[2], reason: 'تسميةُ ${c[0]}');
    }
  });

  test('(ك) الأرضيّة: المسحُ قرأَ ملفّاتٍ فعلاً', () {
    expect(sourcesIn('lib/screens/admin', atLeast: 20).isNotEmpty, isTrue);
  });
}
