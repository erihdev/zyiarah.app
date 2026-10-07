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
      final tail = src.substring(end + 1,
          end + 1 + 900 > src.length ? src.length : end + 1 + 900);
      final dec = RegExp(r'\.(isEmpty|exists)\b|!\s*\w+\.exists').firstMatch(tail);
      if (dec == null) continue;
      final after = tail.substring(dec.end,
          dec.end + 700 > tail.length ? tail.length : dec.end + 700);
      if (!_write.hasMatch(after)) continue;
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
        // المعامَلاتُ خارجَ الخطرِ **بالبناء**: Firestore لا تُنفّذُ معامَلةً
        // بلا شبكة، فقراءتُها خادميّةٌ دائماً.
        'lib/services/order_service.dart#1':
            'transaction.get داخلَ معامَلةِ الإلغاء',
        'lib/services/order_service.dart#2':
            'يَرجعُ `false` عند الجهلِ فلا يَكتبُ — فشلٌ مُغلَق',
        'lib/services/counter_service.dart#1':
            'tx.get داخلَ معامَلة — ولو خُدِمَ من مخزنٍ لأُعيدَ عدّادُ الطلبات',
        'lib/services/store_service.dart#1':
            'transaction.get داخلَ معامَلةِ تسعيرِ السلّة',
        'lib/screens/payment_summary_screen.dart#1':
            'transaction.get — و`exists` تَمنعُ الكتابةَ لا تُسبّبُها',
        // وقراءةٌ لا قرارَ كتابةٍ خلفَها.
        'lib/services/zyiarah_messaging_service.dart#1':
            'قراءةُ `admin_email` للعرضِ باحتياطيّ — لا كتابةَ تَتبعُها',
        'lib/screens/admin/admin_ticket_details_screen.dart#1':
            'مالكُ التذكرةِ للعرضِ وحدَه (أيُّ جهةٍ تُرسَمُ الرسالة)، والكتابةُ '
                'في دالّةٍ أخرى لا تَقرؤه — ونافذةُ الكاشفِ هي ما جمعَتهما',
        // ورتبةُ العنصرِ التالي: مخزنٌ فارغٌ يُنتجُ رتبةً مكرَّرةً لا أكثر —
        // ترتيبٌ لا مال، وكتابةُ الأدمنِ نفسُها تَنتظرُ الشبكة.
        'lib/screens/admin/admin_subscriptions_screen.dart#1': 'رتبةٌ تالية',
        'lib/screens/admin/admin_event_worker_packages_screen.dart#1':
            'رتبةٌ تالية',
        'lib/screens/admin/admin_hourly_zones_screen.dart#1': 'رتبةٌ تالية',
        // والمُصلَحُ: القراءةُ ما زالت بالمصدرِ الافتراضيِّ **عمداً** (مخزنٌ
        // دافئٌ يُجيبُ بالدورِ الصحيحِ بلا ضجيجِ تقارير)، والقرارُ مشروطٌ
        // بـ`isFromCache` — ويَشدُّ الآليّةَ الفحصُ (ب).
        'lib/services/notification_service.dart#1':
            'الدورُ لا يُكتَبُ إلّا متى عُرِف — `isFromCache` هي المِقصَلة',
      };
      final found = _cacheDecidedWrites();
      expect(found.length, greaterThanOrEqualTo(6),
          reason: 'انهارَ المسح: ${found.length} موضعاً');
      expect(found.toSet(), allowed.keys.toSet(),
          reason: 'موضعٌ يُقرّرُ كتابةً على قراءةٍ قد تُخدَمَ من المخزنِ '
              'المحلّيّ. إمّا `Source.server` (فتَرمي عند الجهل) أو معامَلةٌ '
              'أو فشلٌ مُغلَق — ولا يُضافُ إلى القائمةِ إلّا بسببٍ مكتوب.');
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
