// حارس دائم: **الفشل في مسار المال والامتثال والإشعارات لا يمرّ بلا أثر.**
//
// في الشفرة ٢٣٦ كتلة `catch`، وتصنيفها (2026-10-03) كان:
//
//   ١٠١  تُبلّغ المستخدم (setState / SnackBar)      ← ليست صامتة
//    ٤٩  debugPrint فقط                            ← صامتة في الإنتاج
//    ٣٤  فارغة تماماً
//    ٢٣  تُعيد قيمة بديلة
//    ١٩  أخرى
//     ٦  تُعيد الرمي
//     ٤  تُبلّغ Crashlytics
//
// **والفارغة ليست إهمالاً** — هذا ما ظنّه الفحص أوّلاً وكان مخطئاً. فحصُها واحدةً
// واحدةً أظهر أن معظمها **تعويضٌ متعمَّد وموثَّق**: حذفُ حسابٍ يتيم بعد فشل كتابة
// مستنده ثم `rethrow` للخطأ الأصلي (`firebase_service.dart`) — ابتلاعُ فشل
// التعويض هو الصحيح هناك، لأن الخطأ الأصلي هو ما يجب أن يراه المستخدم.
//
// والفراغ الحقيقي كان في الفئة الثانية: `debugPrint` **لا يُجمَّع ولا يُرسَل**،
// فيبدو معالجةً وهو لا شيء. ومعالج `main.dart` العامّ لا يراه أيضاً — الخطأ
// التُقط ولم يصعد. فطلبٌ مدفوع يفشل توليد فاتورته الضريبية، أو مستخدمٌ يفشل حفظ
// رمز إشعاراته فيتوقّف عن تلقّيها، كلاهما كان يمرّ بلا سطرٍ في أي لوحة.
//
// ولم تُحوَّل الـ٤٩ كلها: ١٣ منها من عائلة `fetchZones retry failed` لها إعادة
// محاولة وبديل، وإرسالها يُغرق Crashlytics فيصير بلا قيمة — وإغراقه أسوأ من
// صمته. المحوَّل هو ما يخصّ **المال أو الامتثال أو استمرار الخدمة**.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

String _read(String p) => File(p).readAsStringSync();

/// المواضع التي **يجب** أن تُبلّغ — سبباً سبباً لا عدّاً، كي يقول الفحص عند
/// سقوطه *أيُّها* فُقد لا أن رقماً نقص.
const _mustReport = <String, List<String>>{
  'lib/screens/payment_summary_screen.dart': [
    // توليد فاتورة ZATCA بعد الدفع — طلبٌ مدفوع بلا فاتورة مسألة امتثال.
    'post_order_invoice_notify_failed',
    // إسناد السائق — طلبٌ مدفوع بلا سائق.
    'auto_assign_failed',
    // التحقّق من الدفع.
    'verify_moyasar_failed',
    'verify_first_failed',
    'verify_contract_failed',
    // الذروة والوعورة: السقوط إلى «بلا رسوم» خصمٌ صامت من الإيراد.
    'surge_fetch_failed',
    'terrain_zone_fetch_failed',
    'notify_order_created_failed',
  ],
  'lib/services/notification_service.dart': [
    // بلا رمز محفوظ لا تصل الإشعارات إطلاقاً، والمستخدم لا يعلم.
    'fcm_token_save_failed',
    'fcm_role_fetch_failed',
    'notifications_init_failed',
  ],
  'lib/services/zyiarah_referral_service.dart': [
    // الإحالةُ مالٌ: 50 ر.س للمُحيل وخصمُ 10% للمُحال إليه. كان الفشلُ
    // يُبتلع في `catch` ويُطبع بـ`debugPrint` — لا يُجمَع ولا يُرسَل.
    'referral_apply_failed',
  ],
  'lib/services/zyiarah_wallet_service.dart': [
    'wallet_audit_log_failed',
  ],
  'lib/screens/offers_screen.dart': [
    // الكودُ هو **بدايةُ** برنامجِ الإحالة. وكان الجلبُ
    // `Future<String?>` بـ`.catchError((_) => null)` فيُبتلَعُ الفشلُ بلا
    // `debugPrint` حتى — والبطاقةُ تَرسمُ «…» كحالةِ التحميلِ تماماً، فلا
    // العميلةُ تَعرفُ ولا نَحنُ.
    'referral_code_fetch_failed',
  ],
  'lib/providers/user_provider.dart': [
    'get_user_role_failed',
    'user_profile_parse_failed',
    'user_profile_stream_error',
  ],
};

void main() {
  group('رؤية الأخطاء', () {
    test('كل موضع حرج يُبلّغ بسببه الثابت', () {
      final missing = <String>[];
      for (final entry in _mustReport.entries) {
        final src = _read(entry.key);
        for (final reason in entry.value) {
          if (!src.contains("reason: '$reason'")) {
            missing.add('${entry.key} → $reason');
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'مواضع فقدت إبلاغها. إن كان الحذف مقصوداً فاحذف سببه من هذه '
            'القائمة بقرارٍ موثَّق — لا تُسقط الفحص:\n'
            '${missing.map((m) => '  - $m').join('\n')}',
      );
    });

    test('أسباب Crashlytics ثابتة لا تحمل قيماً متغيّرة', () {
      // Crashlytics يجمّع **بالسبب**. فسببٌ فيه `$uid` أو مبلغ يُنتج مجموعةً
      // لكل قيمة، بواحدةٍ في كلٍّ منها — فتختفي الإشارة في الضجيج. وهذا ما كان
      // يفعله `_reportSilent` الخاص في user_provider قبل توحيده.
      final offenders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        for (final m in RegExp(r"reason:\s*'([^']*)'")
            .allMatches(f.readAsStringSync())) {
          final r = m.group(1)!;
          if (r.contains(r'$') || r.contains('{')) {
            offenders.add('${f.path}: "$r"');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'سبب متغيّر — مرّر القيمة في `info` لا في `reason`:\n'
            '${offenders.map((o) => '  - $o').join('\n')}',
      );
    });

    test('المساعد لا يرمي ولا يعمل على الويب', () {
      final src = _read('lib/utils/error_report.dart');
      // فشلُ الإبلاغ نفسه لا يجوز أن يكسر النداء المحيط به — وإلا صار المراقِب
      // سبباً للعطل. ويلزم أيضاً لاختبارات الوحدة: Firebase غير مُهيَّأ فيها.
      expect(src, contains('} catch (_) {'),
          reason: 'reportSilent يجب أن يبتلع فشله هو');
      // Crashlytics بلا تنفيذ على الويب — استدعاؤه هناك يرمي (كما في main.dart).
      expect(src, contains('if (kIsWeb) return;'));
      expect(src, contains('fatal: false'),
          reason: 'غير قاتل: لا يلوّث نسبة الجلسات الخالية من الانهيار');
    });

    test('لا نداء مباشر لـrecordError خارج المواضع الثلاثة المشروعة', () {
      // كان في user_provider `_reportSilent` خاصّ يفعل الشيء نفسه بسببٍ متغيّر،
      // وفي moyasar_service نداءٌ مباشر **بلا reason** فيصل Crashlytics بلا
      // تجميع. وُحِّدا. والنداء المباشر مشروع في ثلاثة مواضع فقط:
      //
      //   main.dart              المصرف العامّ (FlutterError/PlatformDispatcher)
      //   error_report.dart      المساعد نفسه
      //   global_error_handler   الاصطلاح الثاني: يُسجّل **ويُظهر** إشعاراً
      //
      // أول كتابة لي للفحص كانت تُطابق `void _report*(` فالتقطت `_reportIssue`
      // في لوحة السائق — وهو زرّ «أبلغ عن مشكلة» لا إبلاغَ أخطاء. القاعدة الآن
      // على النداء لا على الاسم.
      const allowed = {
        'lib/main.dart',
        'lib/utils/error_report.dart',
        'lib/utils/global_error_handler.dart',
      };
      final direct = <String>[];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        if (allowed.contains(f.path)) continue;
        if (RegExp(r'record(Error|FlutterFatalError)\s*\(')
            .hasMatch(f.readAsStringSync())) {
          direct.add(f.path);
        }
      }
      expect(
        direct,
        isEmpty,
        reason: 'نداء مباشر يفقد السبب الثابت — استخدم reportSilent من '
            'lib/utils/error_report.dart:\n'
            '${direct.map((d) => '  - $d').join('\n')}',
      );
    });
  });
}
