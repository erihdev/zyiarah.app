// حارسٌ دائم: **قرارُ الكتابةِ لا يُتَّخَذُ على قراءةٍ من المخزنِ المحلّيّ.**
//
// Firestore في هذا المشروعِ بـ`persistenceEnabled` ومخزنٍ **بلا حدّ**. وعلى
// مخزنٍ **بارد** (تثبيتٌ جديد، أو بعد محوِ بيانات التطبيق) والخادمُ غيرُ
// قابلِ الوصول، يُعلِنُ الـSDK «offline mode» ثمّ يُجيبُ `get()` **من
// المخزنِ فوراً وبلا خطأ** — بلقطةٍ فارغةٍ أو بمستندٍ `exists == false`.
// فلا `.timeout()` تَعضُّ ولا `catch` يَعمل، **ويَمضي القرارُ على ما لم
// نَرَه**. وهذه قاعدةُ «لا رقمَ قبل أن نعرفه» المسجَّلةُ في CLAUDE.md،
// مطبَّقةً على **كتابةٍ** لا على عرض — والفرقُ أنّ العرضَ يَكذبُ لحظةً
// والكتابةَ تَبقى.
//
// **وُجدَ بتشغيلِ التطبيقِ لا بالمراجعة (2026-10-07):** مخزنُ Firestore في
// المتصفّحِ حمَلَ `mutations (1)` و`documentOverlays (15)` تُسمّي
// `service_zones` وفيها أسماءُ المناطق — أي أنّ `GeofenceService.initialize`
// بذرَ الكتالوجَ كلَّه لأنّ قراءةً من مخزنٍ بارد عادت فارغة.
//
// الفحوصُ: الموضعانِ المُصلَحانِ بعينِهما، ثمّ **مسحٌ مُشتَقٌّ** على `lib/`
// كلِّها يُقابِلُ مجموعةَ «قراءةٌ قد تُخدَمَ من المخزنِ ⇒ قرارُ وجودٍ ⇒
// كتابة» بقائمةٍ مُعلَّلةٍ — فموضعٌ جديدٌ يُراجَعُ بدلَ أن يَكتبَ على جهل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

String _read(String p) => File(p).readAsStringSync();

/// نهايةُ قوسٍ مُوازَنٍ يَبدأُ عند [i] (حيث `s[i] == open`).
int _bal(String s, int i, [String open = '(', String close = ')']) {
  var d = 0;
  for (var k = i; k < s.length; k++) {
    if (s[k] == open) {
      d++;
    } else if (s[k] == close) {
      d--;
      if (d == 0) return k;
    }
  }
  return -1;
}

const Set<String> _ctrl = {
  'if', 'for', 'while', 'switch', 'catch', 'do', 'else'
};

/// نهايةُ **جسمِ الدالّةِ الحاويةِ** لموضعٍ [i].
///
/// النافذةُ كانت عدَّ أحرفٍ (٩٠٠ ثمّ ٧٠٠)، و«بقيّةُ الكتلةِ الحاوية» وحدَها
/// أضيقُ من اللازم: `.get()` داخلَ `if` تَنتهي كتلتُها قبلَ كتابةٍ تَليها
/// على مستوى الدالّة. فالصعودُ طبقةً طبقةً حتى كتلةٍ ترويستُها **دالّةٌ**
/// (لا `if`/`for`/`catch`) — والتمييزُ بموازنةِ قائمةِ المعامَلاتِ ثمّ
/// قراءةِ المُعرِّفِ قبلَها، وهو الشكلُ المُعتمَدُ في حُرّاسِ هذا المستودع.
int _fnBodyEnd(String s, int i) {
  var pos = i;
  while (true) {
    var close = 0, k = pos - 1, open = -1;
    while (k >= 0) {
      final c = s[k];
      if (c == '}') {
        close++;
      } else if (c == '{') {
        if (close == 0) {
          open = k;
          break;
        }
        close--;
      }
      k--;
    }
    if (open == -1) return s.length;
    var j = open - 1;
    while (j >= 0 && (s[j] == ' ' || s[j] == '\n' || s[j] == '\r' || s[j] == '\t')) {
      j--;
    }
    var isFn = false;
    if (j >= 0 && s[j] == ')') {
      // وازِنْ إلى الوراءِ حتى `(` ثمّ اقرأِ المُعرِّفَ قبلَها.
      var d = 0, q = j;
      while (q >= 0) {
        if (s[q] == ')') {
          d++;
        } else if (s[q] == '(') {
          d--;
          if (d == 0) break;
        }
        q--;
      }
      var w = q - 1;
      while (w >= 0 && (s[w] == ' ' || s[w] == '\n' || s[w] == '\t')) {
        w--;
      }
      var e = w;
      while (e >= 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(s[e])) {
        e--;
      }
      final word = s.substring(e + 1, w + 1);
      // دالّةٌ مُسمّاةٌ، أو إغلاقةٌ (`(v) {`, `(v) async {`) فاسمُها فارغ.
      isFn = !_ctrl.contains(word);
    } else if (j >= 5 && RegExp(r'async\*?$').hasMatch(s.substring(j - 5, j + 1))) {
      isFn = true;
    }
    if (isFn) {
      final e = _bal(s, open, '{', '}');
      return e < 0 ? s.length : e;
    }
    pos = open;
  }
}

final RegExp _write = RegExp(
    r'\.(set|update|add|delete|commit)\s*\(|batch\.(set|update|delete)\s*\(');

/// كلُّ موضعٍ فيه `.get(` بلا `Source.server`، يَتبعُه قرارُ وجودٍ
/// (`isEmpty`/`exists`) ثمّ كتابةٌ — أي «قرارُ كتابةٍ قد يُتَّخَذُ على مخزن».
List<String> _cacheDecidedWrites() {
  final out = <String>[];
  final hitsPerFile = <String, int>{};
  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final src = stripComments(f.readAsStringSync());
    for (final m in RegExp(r'\.get\(').allMatches(src)) {
      final end = _bal(src, m.end - 1);
      if (end < 0) continue;
      final args = src.substring(m.end, end);
      // قراءةٌ مُثبَّتةٌ على الخادمِ لا تُخدَمُ من مخزنٍ أصلاً.
      if (args.contains('Source.server')) continue;
      // **النافذةُ جسمُ الدالّةِ الحاوية، لا عدَّ أحرف.** كانت ٩٠٠ ثمّ
      // ٧٠٠ محرفاً، وكشفَها أنّ جمعَ نسختَي حِملِ الطلبِ في
      // `payment_summary_screen` (2026-10-08) قرَّبَ الكتابةَ من القرارِ
      // فدخلَ الموضعُ المدى: فخُّ الحدِّ الثابتِ في كاشفٍ كُتبَ بالأمس،
      // وهو الحادي عشَرَ من نوعِه في هذا المستودع.
      final tail = src.substring(end + 1, _fnBodyEnd(src, end + 1));
      final dec = RegExp(r'\.(isEmpty|exists)\b|!\s*\w+\.exists').firstMatch(tail);
      if (dec == null) continue;
      if (!_write.hasMatch(tail.substring(dec.end))) continue;
      // **المفتاحُ ملفٌّ وترتيبٌ لا رقمُ سطر** — فتعديلٌ أعلى الملفِّ لا
      // يُسقِطُ الحارسَ زوراً (قاعدةٌ مسجَّلةٌ هنا من `stream_timeout_sweep_test`).
      hitsPerFile[f.path] = (hitsPerFile[f.path] ?? 0) + 1;
      out.add('${f.path}#${hitsPerFile[f.path]}');
    }
  }
  out.sort();
  return out;
}

void main() {
  group('لا كتابةَ على قراءةٍ من المخزن', () {
    test('(أ) بذرُ المناطقِ يَقرأُ من الخادمِ — وإلّا لا يَبذُر', () {
      final g = stripComments(_read('lib/services/geofence_service.dart'));
      // الشكلُ الذي كان يَبذُرُ على مخزنٍ بارد.
      expect(
        RegExp(r"collection\('service_zones'\)[\s\S]{0,200}?\.get\(\s*\)")
            .hasMatch(g),
        isFalse,
        reason: 'قراءةٌ بالمصدرِ الافتراضيِّ تُخدَمُ من مخزنٍ بارد فارغةً، '
            'فيَكتبُ البذرُ ١٥ مستنداً على مجموعةٍ لم يَقرأْها أحد',
      );
      expect(g, contains('GetOptions(source: Source.server)'));
      // وحزامٌ ثانٍ: لو عادت `isFromCache` صحيحةً يوماً يُترَكُ القرار.
      expect(g, contains('snapshot.metadata.isFromCache'));
      // والقرارُ ما زال قائماً (لا بذرَ إلّا على فراغ) — فالفحصُ يَحرُسُ
      // بذراً حقيقيّاً لا تعليقاً.
      expect(g, contains('if (snapshot.docs.isEmpty)'));
      expect(g, contains('_seedDefaultZones(db)'));
    });

    test('(ب) ولا يُكتَبُ دورٌ لم يُقرَأ على رمزِ الدفع', () {
      final n = stripComments(_read('lib/services/notification_service.dart'));
      // الافتراضُ الذي كان يَدّعي الدورَ.
      expect(n.contains("String role = 'client';"), isFalse,
          reason: 'كان يَكتبُ `client` فوقَ دورٍ محفوظٍ صحيحٍ على مخزنٍ بارد');
      // **قدرةٌ لا اسم:** الحقلانِ مشروطانِ في الحِمْلِ نفسِه.
      expect(n, contains("if (roleKnown) 'role': role,"));
      expect(n, contains("if (roleKnown) 'staff_role': staffRole,"));
      // و«غائبٌ من الخادم» ≠ «غائبٌ من المخزن»: الأوّلُ حسابٌ جديدٌ
      // فـ`client` صحيحٌ فيه، والثاني جهلٌ فيُترَك.
      expect(n, contains('!userDoc.metadata.isFromCache'));
      // و`merge` هو ما يَجعلُ الصمتَ صحيحاً — بلاهُ يُمحى الحقل.
      expect(n, contains('SetOptions(merge: true)'));
    });

    test('(ج) وشاهدا التعليلِ الخادميّان قائمان', () {
      final idx = stripComments(_read('functions/index.js'));
      // توجيهُ تنبيهاتِ الإدارةِ يَستعلمُ الدورَ على الرمز — فوسمٌ خاطئٌ
      // يُخرِجُ الجهازَ من التنبيهاتِ كلِّها.
      expect(idx, contains('.where("role", "in", ["admin", "super_admin"])'));
      // ونافذةُ المصالحةِ تَقرأُ الموسومَ **إداريّاً سلفاً**، فلا تَرى
      // الموسومَ `client` — وهو سببُ أنّ الإصلاحَ عميليٌّ لا خادميّ.
      expect(idx, contains('STAFF_TOKEN_ROLES = ["admin", "super_admin"]'));
      // وقاعدةُ `service_zones` تُجيزُ الكتابةَ لمديرِ الطلبات، فبذرُ
      // المالكِ يَنفُذُ فعلاً إلى الإنتاج.
      final rules = stripComments(_read('firestore.rules'));
      final i = rules.indexOf('match /service_zones/');
      expect(i, greaterThan(-1));
      expect(rules.substring(i, i + 200), contains('isOrdersManager()'));
    });

    test('(د) ولا موضعَ ثالثٌ يَكتبُ على قرارٍ قد يَأتيَ من مخزن', () {
      // مُعلَّلٌ واحداً واحداً. المعامَلاتُ (`transaction.get`/`tx.get`) خارجَ
      // الخطرِ بالبناء: Firestore لا تُنفّذُ معامَلةً بلا شبكة، فقراءتُها
      // خادميّةٌ دائماً.
      const allowed = <String, String>{
        // ══ معامَلاتٌ: خارجَ الخطرِ **بالبناء** ══
        // Firestore لا تُنفّذُ معامَلةً بلا شبكة، فقراءتُها خادميّةٌ دائماً.
        'lib/screens/payment_summary_screen.dart#1':
            'transaction.get — و`exists` تَمنعُ الكتابةَ لا تُسبّبُها',
        'lib/services/counter_service.dart#1':
            'tx.get داخلَ معامَلة — ولو خُدِمَ من مخزنٍ لأُعيدَ عدّادُ الطلبات',
        'lib/services/order_service.dart#1':
            'transaction.get داخلَ معامَلةِ الإلغاء',
        'lib/services/order_service.dart#2':
            'transaction.get داخلَ معامَلةِ تحديثِ الحالة',
        'lib/services/order_service.dart#4':
            'transaction.get داخلَ معامَلةِ الإكمال — ويَرجعُ `false` عند الجهل',
        'lib/services/store_service.dart#2':
            'transaction.get داخلَ معامَلةِ تسعيرِ السلّة',

        // ══ فشلٌ مُغلَق: الجهلُ يَمنعُ الكتابةَ لا يُسبّبُها ══
        'lib/services/order_service.dart#3':
            'التقييم: `!exists` ⇒ `return` بلا كتابة',
        'lib/screens/admin/admin_hourly_zones_screen.dart#1':
            'مصدرُ قائمةِ «نسخ الأسعار من» — فراغُها يَترُكُ `copiedFromId` '
                'فارغاً فلا نسخَ إطلاقاً',

        // ══ رتبةُ العنصرِ التالي: مخزنٌ فارغٌ يُنتجُ رتبةً مكرَّرةً لا أكثر ══
        // ترتيبٌ لا مال، وكتابةُ الأدمنِ نفسُها تَنتظرُ الشبكة.
        'lib/screens/admin/admin_subscriptions_screen.dart#1': 'رتبةٌ تالية',
        'lib/screens/admin/admin_event_worker_packages_screen.dart#1':
            'رتبةٌ تالية',
        'lib/screens/admin/admin_hourly_zones_screen.dart#2': 'رتبةٌ تالية',

        // ══ قراءةُ عرضٍ باحتياطيٍّ حاضر: لا قرارَ كتابةٍ خلفَها ══
        'lib/services/store_service.dart#1':
            'الاسمُ والهاتفُ والبريدُ باحتياطيِّ `user.email` وقيَمٍ افتراضيّة',

        // ══ وثلاثةٌ لها سببُها الخاصّ ══
        // ظهرَ في 2026-10-08 بجمعِ نسختَي حِملِ الطلب: الحِملُ كان خمسينَ
        // سطراً بين القرارِ والكتابةِ فدفعَ `transaction.set` خارجَ نافذةِ
        // الكاشفِ الثابتةِ آنذاك. وهو مسموحٌ لأنّه يُبلَغُ **بعدَ أن
        // يَتحرّكَ المال**، فالفشلُ المُغلَقُ يَترُكُ دفعةً مدفوعةً بلا
        // مستندِ طلبٍ — وهو أسوأ؛ وشبكةُ الأمانِ خادميّةٌ ومكتوبةٌ في
        // موضعِها (`verifyMoyasarPayment` و`reconcileOrphanPayments`
        // يُنشئانِ الطلبَ من metadata الدفعة).
        'lib/screens/payment_summary_screen.dart#2':
            'بعدَ تحرّكِ المال: الفشلُ المُغلَقُ يَترُكُ دفعةً بلا طلب، '
                'والمُصالِحُ الخادميُّ هو الشبكة',
        // والمِقصَلةُ الحقيقيّةُ هنا **معامَلةٌ**: `ensureOrder` تُنادي
        // `_createUnpaidServiceOrder` وهي تَقرأُ `transaction.get` ثمّ
        // تُعيدُ كودَ المستندِ القائمِ إن وُجد — فقراءةٌ باردةٌ هنا لا
        // تُنتجُ مستنداً مكرَّراً.
        'lib/screens/checkout_screen.dart#1':
            'القرارُ يَنتهي إلى معامَلةٍ تُعيدُ القراءةَ خادميّاً',
        // صورةٌ يتيمةٌ في التخزينِ لا كتابةٌ خاطئة: `exists` الكاذبةُ
        // تُسقِطُ نداءَ `deleteStorageObject` وحدَه، وحذفُ المستندِ يَجري
        // على أيِّ حال.
        'lib/screens/admin/admin_banners_screen.dart#1':
            'الجهلُ يَترُكُ صورةً يتيمةً في التخزينِ لا سجلاًّ خاطئاً',

        // ══ والمُصلَحُ في شريحةِ 2026-10-07 ══
        // القراءةُ بالمصدرِ الافتراضيِّ **عمداً** (مخزنٌ دافئٌ يُجيبُ
        // بالدورِ الصحيحِ بلا ضجيجِ تقارير)، والقرارُ مشروطٌ بـ`isFromCache`
        // — ويَشدُّ الآليّةَ الفحصُ (ب).
        'lib/services/notification_service.dart#1':
            'الدورُ لا يُكتَبُ إلّا متى عُرِف — `isFromCache` هي المِقصَلة',
      };
      final found = _cacheDecidedWrites();
      expect(found.length, greaterThanOrEqualTo(11),
          reason: 'انهارَ المسح: ${found.length} موضعاً');
      expect(found.toSet(), allowed.keys.toSet(),
          reason: 'موضعٌ يُقرّرُ كتابةً على قراءةٍ قد تُخدَمَ من المخزنِ '
              'المحلّيّ. إمّا `Source.server` (فتَرمي عند الجهل) أو معامَلةٌ '
              'أو فشلٌ مُغلَق — ولا يُضافُ إلى القائمةِ إلّا بسببٍ مكتوب.');
    });

    test('(و) والنافذةُ جسمُ الدالّةِ — لا عدَّ أحرفٍ ولا كتلةٌ وحدَها', () {
      // الحارسُ سالبٌ ومصدرُ المستودعِ نظيفٌ بعد التصنيف، فنجاحُه وحدَه لا
      // يُبرهِنُ أنّ الحدَّ صحيح. فيُقاسُ `_fnBodyEnd` على شكلَين بعينِهما،
      // ومَوضعُ البدءِ فيهما **داخلَ كتلةٍ متداخلة** — وهناك وحدَها
      // يَفترِقُ «جسمُ الدالّة» عن «بقيّةِ الكتلة».
      //
      // (١) `.get()` داخلَ `if` والكتابةُ بعدَه على مستوى الدالّة: حدٌّ
      //     يَقفُ عند `}` الكتلةِ لا يَراها، وكذلك حدٌّ يَحسبُ ترويسةَ
      //     `if` دالّةً (فهي تَنتهي بـ`)` كترويسةِ الدالّة).
      const nested = '''
void f() {
  if (x) {
    final s = await ref.get();
    if (s.exists) { n = 1; }
  }
  ref.set({});
}
''';
      final at1 = nested.indexOf('s.exists');
      expect(nested.substring(at1, _fnBodyEnd(nested, at1)), contains('ref.set('),
          reason: 'الحدُّ أضيقُ من جسمِ الدالّة — كتابةٌ بعدَ الكتلةِ تَختفي، '
              'أو أنّ ترويسةَ `if` حُسِبت دالّةً');
      // (٢) ولا يَعبُرُ إلى دالّةٍ **أخرى**: كتابةٌ في التاليةِ ليست قراراً
      //     على هذه القراءة — وهو الإيجابُ الكاذبُ الذي أسقطَته هذه النافذةُ
      //     (مالكُ التذكرةِ للعرضِ، والكتابةُ في دالّةٍ أخرى).
      const nextFn = '''
void g() {
  if (x) {
    final s = await ref.get();
    if (s.exists) { n = 1; }
  }
}
void h() {
  ref.set({});
}
''';
      final at2 = nextFn.indexOf('s.exists');
      expect(nextFn.substring(at2, _fnBodyEnd(nextFn, at2)),
          isNot(contains('ref.set(')),
          reason: 'الحدُّ يَعبُرُ إلى دالّةٍ أخرى — إيجابٌ كاذب');
      // ولا عودةَ إلى عدِّ الأحرفِ في الكاشفِ نفسِه.
      final self = stripComments(_read('test/cache_decided_write_test.dart'));
      expect(RegExp(r'\+\s*(?:700|900)\b').hasMatch(self), isFalse,
          reason: 'عادت نافذةُ عدِّ الأحرفِ — وهي ما أخفى مواضعَ حتى 2026-10-08');
    });

    test('(ه) والمُجرِّدُ حاملٌ، والنصُّ الممنوعُ ما زال في الخامّ', () {
      // كلُّ شكلٍ ممنوعٍ أعلاه مُقتبَسٌ في تعليقٍ يَشرحُ زوالَه — فبلا الحجبِ
      // يَسقطُ الحارسُ على توثيقِه.
      expect(_read('lib/services/notification_service.dart'),
          contains("String role = 'client';"),
          reason: 'شرحُ العطلِ يَذكرُ الافتراضَ القديم بنصِّه');
      expect(
          stripComments(_read('lib/services/notification_service.dart'))
              .contains("String role = 'client';"),
          isFalse);
      expect(_read('lib/services/geofence_service.dart'), contains('isFromCache'));
    });
  });
}
