import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-21) تدفّق إشعارات/إيميلات **متجر الشركات** (المباشر):
/// يدفع العميل ⇒ إيميل+إشعار «تحت المراجعة» له، وإيميل ببيانات الطلب+إشعار للإدارة
/// (**بعد الدفع** لا قبله) ⇒ جاري التوصيل: إيميل+إشعار ⇒ تم التسليم: إيميل+إشعار.
/// كل نقلة تغيّر الحالة في تطبيق العميل (بثّ) وتصله إيميلاً وإشعاراً.
void main() {
  final fn = File('functions/index.js').readAsStringSync();
  final service = File('lib/services/store_service.dart').readAsStringSync();
  final pay = File('lib/screens/store_payment_screen.dart').readAsStringSync();

  String fnBody(String name) {
    final i = fn.indexOf('exports.$name');
    expect(i, greaterThan(-1), reason: '$name غائبة');
    return fn.substring(i, fn.indexOf('exports.', i + 10));
  }

  test('تنبيه الإدارة بطلب المتجر يُطلق عند الدفع لا الإنشاء + ببيانات الطلب', () {
    final body = fnBody('sendNotificationToAdminsOnNewStoreOrder');
    expect(body.contains('onDocumentWritten'), isTrue,
        reason: 'onDocumentCreated كان يُطلق قبل الدفع');
    expect(body.contains('onDocumentCreated'), isFalse);
    expect(
        body.contains(
            'after.is_paid === true && (!before || before.is_paid !== true)'),
        isTrue,
        reason: 'يُطلق مرّة واحدة عند قلب is_paid');
    // بيانات الطلب في الإيميل والإشعار: العميل + المبلغ + الأصناف.
    expect(body.contains('after.items'), isTrue);
    expect(body.contains('after.total_amount'), isTrue);
    expect(body.contains('after.client_name'), isTrue);
    expect(body.contains('new_store_order_admin'), isTrue,
        reason: 'النوع ضمن wantsEmail فيصل الإدارة إيميل لبريدها');
  });

  test('العميل يصله إيميل مع كل نقلة حالة (store_update ضمن wantsEmail)', () {
    final body = fnBody('notifyClientOnStoreOrderStatus');
    expect(body.contains('clientEmail'), isTrue,
        reason: 'يمرّر بريد العميل كـ recipientEmail لـ queuePush');
    expect(body.contains('after.client_email'), isTrue,
        reason: 'بريد العميل من الطلب أولاً ثم users كاحتياط');
    // مُعالج notification_triggers يجب أن يُدرِج store_update ضمن الأنواع المُرسِلة للبريد.
    expect(fn.contains('type === "store_update"'), isTrue,
        reason: 'بدونها يصل إشعار بلا إيميل');
    // النصوص المؤنّثة لكل نقلة باقية.
    expect(body.contains('under_review:'), isTrue);
    expect(body.contains('delivering:'), isTrue);
    expect(body.contains('delivered:'), isTrue);
  });

  test('بريد العميل يُكتب على طلب المتجر عند الإنشاء', () {
    expect(service.contains("'client_email': clientEmail"), isTrue,
        reason: 'بدونه يجلبه المُشغّل من users (احتياط)، والأفضل حفظه مبكراً');
  });

  test('لا تنبيه إداري عميلي مكرّر (الخادم يتكفّل بعد الدفع)', () {
    // النداء الفعلي (نقطة + قوس) لا مجرّد ذكر الاسم في تعليق توثيقي.
    expect(pay.contains('.notifyAdminOfPayment('), isFalse,
        reason: 'المُشغّل الخادمي (paid-flip) يُشعر الإدارة بالبيانات — لا ازدواج');
  });
}
