import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/order_lifecycle.dart';

/// إسنادُ السائق من شاشة تفاصيل الطلب — الخادم هو الحارس، فعلاً لا شكلاً.
///
/// ═══ ما يحرسه ═══
///
/// قاعدةُ الأهليّة (H3) تقول: لا يُسنَد طلبٌ لمستند `drivers/{id}` إلّا إن كان
/// `id` حسابَ دخولٍ حقيقياً بدور سائق في `users/{id}` — لأنّ معرّف مستند السائق
/// **قد لا يكون uid** (لوحةُ الويب كانت تُنشئه بـ`addDoc` بمعرّف عشوائي، وتلك
/// المستندات باقية). وإسنادُ طلبٍ لأحدها يُخفيه عن الجميع: القواعد وتطبيق السائق
/// يربطان الرؤية بـ`auth.uid == driver_id`. فالطلب مدفوع، ويقول للعميل «تم تعيين
/// سائق»، ولا يراه أحد أبداً.
///
/// وقائمةُ السائقين في الشاشة تعرض **كلّ سائقٍ نشط بقصد** — «القائمة للعرض،
/// والخادم هو الحارس». وهذا الشقّ الثاني هو ما كان منقوضاً:
///
///   * `approveAndAssignOrder` كان يرفض كلَّ حالةٍ غير `pending`.
///   * فطلبٌ `under_review` أو `awaiting_payment` (وكلتاهما حالتان حقيقيّتان
///     يكتبهما مسارُ المتجر والصيانة) لا يقبله الخادم.
///   * فيسقط التطبيق إلى فرعٍ متبقٍّ يكتب `driver_id`/`driver_name`/
///     `driver_phone`/`assigned_at` إلى Firestore **مباشرةً**، والقواعد تمنح
///     `isOrdersManager()` تحديثاً كاملاً فتمرّ الكتابة.
///   * فيتجاوز الإسنادُ فحصَ الأهليّة بأكمله **وفحصَ التعارض الذرّي معاً**.
///
/// ولم يكن ذلك الفرع يُسنِد في حالةٍ هامشيّة: قائمتُه `preDispatch` كانت تضمّ
/// `under_review` و`awaiting_payment` صراحةً وتُرقّيهما إلى `scheduled` — أي
/// أنّه **كان المسار المقصود** لتلك الحالات، لا سقوطاً عارضاً. وحارسُ
/// `functions/test/drivers.test.js` مرّ طوال الوقت: هو يفحص أنّ النداءات
/// الخادميّة تفرض الأهليّة، لا أنّ التطبيق يمرّ عليها.
///
/// العلاج: توسيعُ ما يقبله الخادم إلى حالات ما قبل الإسناد كلّها (بلا سائق)،
/// وحذفُ كتابة السائق المباشرة من الشاشة نهائياً. فالمسارانِ يقسمان الفضاء:
///
///   ما قبل الإسناد + بلا `driver_id`  → `approveAndAssignOrder`
///   نشطٌ + يحمل `driver_id`           → `rescheduleAssignedOrder`
String _strip(String src) {
  src = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .map((l) => l.replaceAll(RegExp(r'([^:])//.*$'), r'$1'))
      .join('\n');
}

/// يقرأ عناصرَ قائمةٍ نصّية من مصدرٍ ما بين قوسَي تعريفها.
List<String> _literals(String src, String open, String close) {
  final i = src.indexOf(open);
  expect(i, greaterThanOrEqualTo(0), reason: 'لم يُوجد التعريف: $open');
  final j = src.indexOf(close, i);
  return RegExp("['\"]([a-z_]+)['\"]")
      .allMatches(src.substring(i + open.length, j))
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  final raw =
      File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();
  final scr = _strip(raw);
  final fnRaw = File('functions/index.js').readAsStringSync();
  // تُجرَّد التعليقات: الشيفرةُ تشرح ما حلّ محلّه بذكر الشرط القديم حرفياً،
  // فالفحصُ الخام يسقط على شرحِ نفسه (وقع ذلك أوّل مرّة).
  final fn = _strip(fnRaw);
  final life = File('lib/utils/order_lifecycle.dart').readAsStringSync();

  group('الشاشة لا تكتب سائقاً إلى Firestore أبداً', () {
    test('لا حقلَ سائقٍ في حمولة الكتابة المباشرة', () {
      // جوهرُ الإصلاح. أيّ واحدٍ من هذه يعني أنّ الفرع غير المحروس عاد.
      for (final f in [
        "updatePayload['driver_id']",
        "updatePayload['driver_name']",
        "updatePayload['assigned_driver']",
        "updatePayload['driver_phone']",
        "updatePayload['assigned_at']",
      ]) {
        expect(scr.contains(f), isFalse,
            reason: '$f كتابةٌ مباشرة تتجاوز فحصَ الأهليّة والتعارض معاً — '
                'ومستندُ سائقٍ بلا حساب دخول يُخفي الطلب المدفوع عن الجميع');
      }
      // ولا أيّ شكلٍ آخر: الموضعُ الوحيد المسموح لـ`'driver_id':` هو سجلّ
      // التدقيق — سجلٌّ لا كتابةٌ على الطلب. لو ظهر ثانٍ فهو حمولةُ update/set.
      final idKeys = RegExp(r"'driver_id'\s*:").allMatches(scr).toList();
      expect(idKeys.length, 1,
          reason: 'عددُ مواضع `\'driver_id\':` ${idKeys.length} — المسموح '
              'واحدٌ فقط (تفاصيل سجلّ التدقيق)');
      final auditAt = scr.indexOf('ZyiarahAuditService.actionAssignDriver');
      expect(auditAt, greaterThanOrEqualTo(0));
      expect(idKeys.first.start, greaterThan(auditAt),
          reason: 'الموضعُ الوحيد يجب أن يكون داخل نداء سجلّ التدقيق');
      expect(idKeys.first.start - auditAt, lessThan(400),
          reason: 'بعيدٌ عن نداء التدقيق — يُرجَّح أنه حمولةُ كتابة');
    });

    test('كلا مساري الإسناد نداءٌ خادميّ، لا كتابة', () {
      expect(scr.contains("httpsCallable('approveAndAssignOrder')"), isTrue);
      expect(scr.contains("httpsCallable('rescheduleAssignedOrder')"), isTrue);
    });

    test('اختيارُ سائقٍ لا يقبله أيُّ مسار يُخبِر المدير، ولا يُتجاهَل بصمت', () {
      // بلا هذا يختفي قصدُ المدير: يضغط «حفظ» فلا يُسنَد سائق ولا يُقال له شيء.
      expect(scr.contains('isNewAssignment && isOrdersDoc'), isTrue,
          reason: 'لا فحصَ للسقوط في المسار المباشر مع اختيار سائق');
      expect(raw.contains('لا يمكن إسناد سائق لطلب بحالة'), isTrue,
          reason: 'لا رسالةَ خطأ صريحة');
    });
  });

  group('القسمة على وجود سائق، لا على الحالة وحدها', () {
    test('الإسناد الابتدائي: ما قبل الإسناد **وبلا** سائق', () {
      expect(scr.contains('!hasDriverNow'), isTrue,
          reason: 'طلبٌ يحمل سائقاً شأنُ reschedule — وإلّا حُسب السائق '
              'الحاليّ تعارضاً مع نفسه');
      expect(scr.contains('kPreDispatchStatuses.contains(_currentStatus)'), isTrue);
    });

    test('إعادة الجدولة: نشطٌ **ويحمل** سائقاً', () {
      expect(scr.contains('kActiveAssignedStatuses.contains'), isTrue);
      // لا إعادةَ كتابةٍ للمجموعتين إنلاين في الشاشة.
      expect(scr.contains("'awaiting_payment'"), isFalse,
          reason: 'مجموعةُ الحالات مكتوبةٌ بيدها من جديد — موضعُها '
              'lib/utils/order_lifecycle.dart');
    });

    test('حارسُ «بلا موعد» يغطّي حالاتِ ما قبل الإسناد كلّها', () {
      // كان مقصوراً على pending، فطلبٌ under_review يُسنَد بلا service_date أصلاً.
      expect(scr.contains('isInitialAssign && effectiveSchedule == null'), isTrue);
    });
  });

  group('مرآةُ المجموعتين: دارت ↔ الخادم', () {
    test('kPreDispatchStatuses == PRE_DISPATCH_STATUSES حرفاً بحرف', () {
      final dart = _literals(life, 'kPreDispatchStatuses = {', '}');
      final js = _literals(fn, 'const PRE_DISPATCH_STATUSES = [', '];');
      expect(dart.toSet(), equals(kPreDispatchStatuses),
          reason: 'المصدر والثابت المُصدَّر اختلفا');
      expect(js.toSet(), equals(kPreDispatchStatuses),
          reason: 'نسخةُ الخادم انحرفت — حالةٌ يقبلها أحدهما ويرفضها الآخر '
              'تعني سقوطاً إلى مسارٍ غير محروس أو رفضاً لإسنادٍ مشروع');
    });

    test('kActiveAssignedStatuses == CONFLICT_STATUSES في slots.js', () {
      // كانت المجموعة مكتوبةً إنلاين في rescheduleAssignedOrder؛ صارت تعريفاً
      // واحداً في functions/slots.js (نفسُ السؤال: «هل يُحسَب السائق مشغولاً؟»).
      final slots = File('functions/slots.js').readAsStringSync();
      final js = _literals(slots, 'const CONFLICT_STATUSES = [', '];');
      expect(js.toSet(), equals(kActiveAssignedStatuses),
          reason: 'انحرافُ المجموعتين يعني حالةً يَشغل فيها الطلبُ سائقَه عند '
              'أحدهما ولا يَشغله عند الآخر');
      // والنداءُ ما زال يستعملها (قاعدةٌ صحيحة لا تُنادى = حرّاسها خضراء بلا أثر).
      final i = fn.indexOf('exports.rescheduleAssignedOrder');
      final body = fn.substring(i, fn.indexOf('exports.', i + 10));
      expect(body.contains('slots.CONFLICT_STATUSES'), isTrue);
      // و`pending` خارجَها بقصد: طلبٌ لم يُسنَد لا يَشغل أحداً.
      expect(kActiveAssignedStatuses.contains('pending'), isFalse);
    });

    test('المجموعتان تتقاسمان assigned فقط — والقسمة بوجود السائق', () {
      expect(kPreDispatchStatuses.intersection(kActiveAssignedStatuses),
          equals({'assigned'}),
          reason: 'تداخلٌ أوسع يعني أنّ حالةً واحدة تقبلها النداءتان معاً');
    });
  });

  group('الخادم يفرض القاعدة على الحالات الموسَّعة', () {
    late String body;
    setUp(() {
      final i = fn.indexOf('exports.approveAndAssignOrder');
      body = fn.substring(i, fn.indexOf('exports.', i + 10));
    });

    test('يقبل مجموعةَ ما قبل الإسناد لا pending وحدها', () {
      expect(body.contains('PRE_DISPATCH_STATUSES.includes(orderData.status)'),
          isTrue,
          reason: 'العودةُ إلى `status !== "pending"` تُعيد فتحَ الثقب: '
              'under_review/awaiting_payment يرفضهما الخادم فيسقط التطبيق');
      expect(body.contains('status !== "pending"'), isFalse,
          reason: 'الشرطُ القديم عاد إلى الشيفرة');
      // والتجريدُ لم يُفرِغ الفحص: النصُّ الخامّ ما زال يحمل العبارة (في الشرح).
      expect(fnRaw.contains('status !== "pending"'), isTrue,
          reason: 'لا شرحَ يذكر الشرط القديم — فالتجريد صار بلا موضوع ولا '
              'يثبت أنّ الفحص يرى الشيفرة');
    });

    test('يرفض طلباً يحمل سائقاً سلفاً', () {
      expect(body.contains('if (orderData.driver_id)'), isTrue);
    });

    test('الفحصُ الذرّي داخل المعاملة يستعمل القاعدة نفسها', () {
      // الفحصُ الخارجي وحده يسمح لمديرَين متزامنَين بإسناد نفس الطلب.
      expect(body.contains('PRE_DISPATCH_STATUSES.includes(fd.status)'), isTrue);
      expect(body.contains('|| fd.driver_id'), isTrue);
    });

    test('الأهليّة الكاملة ما زالت مفروضة (لا النشاط وحده)', () {
      expect(body.contains('_assertAssignableDriver(db, driverId)'), isTrue,
          reason: 'هو الفحصُ الذي يمنع مستندَ سائقٍ بلا حساب دخول');
    });
  });

  test('القائمةُ ما زالت تعرض كلَّ سائقٍ نشط — قرارُ المالك', () {
    // الإصلاحُ الخاطئ هو ترشيحُ القائمة في العميل: لا يحرس شيئاً (عميلٌ قديم
    // يكتب ما يشاء) ويُفرِّغ القائمة كما حدث قبلاً مع الحجوزات المسبقة. الحارسُ
    // خادميّ، والقائمة للعرض.
    expect(scr.contains("where('is_active', isEqualTo: true)"), isTrue,
        reason: 'ترشيحٌ أضيق في العميل ليس حرزاً — الحارس خادميّ');
    expect(raw.contains('القائمة للعرض، والخادم هو الحارس'), isTrue,
        reason: 'قرارُ المالك موثَّقٌ في الشاشة — لا يُحذَف');
  });
}
