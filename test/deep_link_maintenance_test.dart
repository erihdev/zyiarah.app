import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/notification_target.dart';

/// **فرعٌ فارغٌ يَقرأ كفرعٍ مُعالَج.**
///
/// `_handleUri` في `deep_link_service` كان يَنتهي بـ:
///
///     } else if (resource == 'maintenance') {
///        // For now, let's keep it safe.
///     }
///
/// فنقرةُ إشعارٍ يَحمل `requestId` — و`handleNotificationTap` يُحوّله إلى
/// `zyiarah://app/maintenance/<id>` — **لا تَفعلُ شيئاً ولا تَقولُ شيئاً**.
/// وهو نفسُ شكلِ «زرٌّ يُضغط فلا يحدث شيء»، إلّا أنّه يَقرأ كفرعٍ مقصود.
///
/// ═══ وما الذي يُولّد ذلك الإشعارَ فعلاً؟ لا شيءَ عمليّاً ═══
///
/// صيانةُ الأجهزةِ **أُرشِفت** بقرارِ المالك: `firestore.rules` تقول
/// `allow create, update: if false`، ولا موضعَ في المستودعِ يُنشئ مستنداً في
/// `maintenance_requests` — فحصتُ كلَّ ذكرٍ لها. فالدالّتان الخادميّتان
/// الباقيتان لا تَفعلان شيئاً عمليّاً:
///
///   * `sendNotificationToAdminsOnNewMaintenance` (على الإنشاء) — ولا إنشاء.
///   * `notifyClientOnMaintenanceRejected` — مقصورةٌ على
///     `after.status === "rejected"` صراحةً، ولا موضعَ يَكتب `rejected`
///     (المُزامِنُ الوحيدُ، `syncOrderLinkedRecords`، يَكتب
///     `in_progress`/`completed` فقط). مكتوبةٌ بحقٍّ ولا تُطلَق.
///
/// **حذفُ دالّةٍ خادميّةٍ قرارٌ بشريٌّ يُنفَّذ باليد** (النشرُ بلا `--force`
/// يَفشل بدلاً من الحذفِ الصامت)، فالاثنتان مُبلَّغتان للمالكِ ولم تُحذفا هنا.
///
/// ═══ والإصلاحُ ليس حذفاً ═══
///
/// شاشةُ الأرشيفِ **قائمةٌ وتَعمل**: `AdminOrderDetailsScreen` تَكشف المجموعةَ
/// بنفسِها وتُفتَح من شاشةِ البحثِ فعلاً. فالأدمنُ يَذهب إليها، والعميلةُ لا:
/// القراءةُ من `maintenance_requests` محصورةٌ بـ`isAdmin()` في القواعد، فأيُّ
/// دفعٍ لشاشةٍ عميليّةٍ ينتهي بخطأِ صلاحيّات. البقاءُ في مكانِها صوابٌ —
/// **مكتوباً لا مسكوتاً عنه**.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  final svc = read('lib/services/deep_link_service.dart');
  final code = stripLineComments(svc);

  test('فرعُ الصيانةِ لم يَبقَ فارغاً', () {
    final i = code.indexOf("resource == 'maintenance'");
    expect(i, greaterThan(0), reason: 'الفرعُ اختفى — أين يَذهبُ requestId الآن؟');
    final body = code.substring(i, code.indexOf('\n    }', i));
    expect(body, contains('AdminOrderDetailsScreen(orderId: id)'),
        reason: 'الأدمنُ لا يَصلُ شاشةَ الأرشيفِ القائمة');
    expect(body, contains('if (isAdmin)'),
        reason: 'بلا شرطِ الدور: دفعُ شاشةٍ إداريّةٍ للعميلةِ ينتهي بخطأِ صلاحيّات');
    // على المصدرِ **بعد** تجريدِ التعليقات: التعليقُ الجديدُ يَقتبسُ العبارةَ
    // ليَشرحَ ما كان، وأوّلُ صياغةٍ لهذا الفحصِ سقطت على توثيقِ نفسِها (رابعُ
    // مرّةٍ في هذه الجلسة). ثمّ نؤكّد أنّها في الخامِّ كي لا يُفرِغَ التجريد.
    expect(code.contains("For now, let's keep it safe"), isFalse,
        reason: 'الفرعُ الفارغُ عاد');
    expect(svc.contains("For now, let's keep it safe"), isTrue,
        reason: 'التعليقُ الذي يَحملُ السببَ حُذف — فالفحصُ بلا موضوع');
  });

  test('وtap الإشعارِ ما زال يُحوّل requestId إلى مسارٍ', () {
    // **أُعيدَ توجيهُ هذا الفحصِ لا إرخاؤه (2026-10-05).** كان يَشدُّ
    // `resource = 'maintenance'` و`data['requestId']` حرفيّاً في هذه الخدمة؛
    // والقرارُ انتقلَ إلى `lib/utils/notification_target.dart` لأنّه كان
    // مكتوباً ثلاثَ مرّاتٍ لا تَتّفق (المسارُ، ونصُّ الزرِّ، ونقرُ FCM) —
    // فإشعارُ العقدِ كان يَذهبُ إلى `/track/<معرّفِ الطابور>` تحتَ زرٍّ يَقول
    // «عرض الطلب والفاتورة». فيُفحَصُ **سلوكاً** الآن لا نصّاً، وهو أشدّ.
    final t = notifTargetFromData({'requestId': 'r1'});
    expect(t.kind, NotifDest.maintenance,
        reason: 'requestId لم يَعُد يُنتجُ وجهةَ الصيانة');
    expect(t.id, 'r1');
    // وطلبٌ بعينِه يَسبقُ، كما كان ترتيبُ التعدادِ القديمِ بعينِه.
    expect(notifTargetFromData({'orderId': 'o1', 'requestId': 'r1'}).kind,
        NotifDest.order,
        reason: 'ترتيبُ التحديدِ انقلبَ — إشعارُ طلبٍ صار يَفتحُ أرشيفَ صيانة');
    // والخدمةُ ما زالت تُترجمُ الوجهةَ إلى الموردِ نفسِه.
    expect(code, contains("NotifDest.maintenance => 'maintenance'"),
        reason: 'الخدمةُ لم تَعُد تُترجمُ وجهةَ الصيانةِ إلى موردٍ');
    // وبلا معرّفٍ يَبقى في مكانِه (لا تنقّلٌ أعمى) — في الموضعَين.
    expect(code, contains('if (id == null) return;'));
    expect(
        code, contains('if (resource == null || id == null || id.isEmpty) return;'),
        reason: 'حِملٌ بلا معرّفٍ صارَ يُنتجُ رابطاً ناقصاً');
  });

  test('وحارسُ الدور: المسارُ كلُّه بعد المصادقةِ والدور', () {
    final i = code.indexOf('Future<void> _handleUri(');
    final body = code.substring(i);
    expect(body.indexOf('currentUser'),
        lessThan(body.indexOf("resource == 'order'")),
        reason: 'التوجيهُ قبل التحقّقِ من الدخول');
    expect(body, contains('getUserRole(user.uid)'));
    expect(body, contains("uri.scheme != 'zyiarah' || uri.host != 'app'"),
        reason: 'حارسُ المخطَّطِ والمضيفِ سقط — رابطٌ أجنبيٌّ يَصلُ التوجيه');
  });

  group('الدالّتان الخادميّتان ما زالتا بلا مُطلِق', () {
    final idx = stripLineComments(read('functions/index.js'));
    final rules = read('firestore.rules');

    test('القواعدُ ما زالت تَمنع الإنشاءَ والتعديل', () {
      final i = rules.indexOf('match /maintenance_requests/');
      expect(i, greaterThan(0));
      // بعد `{` الكتلةِ لا `}` مسارِ المطابقةِ نفسِه (`{requestId}`) — أوّلُ
      // صياغةٍ اقتطعت سطراً واحداً.
      final open = rules.indexOf('{', rules.indexOf('{requestId}', i) + 11);
      final block = rules.substring(open, rules.indexOf('}', open));
      expect(block, contains('allow create, update: if false;'),
          reason: 'لو فُتح الإنشاءُ عادت الدالّتان حيّتَين — وهذا يَستحقّ مراجعة');
    });

    test('والرفضُ مقصورٌ على rejected، ولا موضعَ يَكتبها', () {
      expect(idx, contains('after.status !== "rejected"'),
          reason: 'لو وُسِّع الشرطُ لأصبح إكمالُ طلبٍ مرتبطٍ يُرسل «رفضاً»');
      // المُزامِنُ الوحيدُ يَكتب هاتين فقط.
      expect(idx, contains('status: "in_progress",'));
      expect(idx, contains('status: "completed",'));
      expect(idx.contains('status: "rejected",'), isFalse,
          reason: 'موضعٌ صار يَكتب rejected — الدالّةُ صارت حيّةً فراجِعها');
    });
  });
}
