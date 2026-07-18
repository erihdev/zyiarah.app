import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) المتجر طلب مباشر مثل بقية الخدمات:
/// العميل يدفع فوراً (بلا موافقة مسبقة وبلا وقت/تاريخ)، وبعد تأكيد الدفع
/// تديره الإدارة نقرةً نقرة: تحت المراجعة ⇒ جاري التوصيل ⇒ تم التوصيل —
/// والعميل يرى كل نقلة حيّاً (بثّ Firestore) ويصله إشعار خادمي لحظي.
void main() {
  final service = File('lib/services/store_service.dart').readAsStringSync();
  final store = File('lib/screens/store_screen.dart').readAsStringSync();
  final pay = File('lib/screens/store_payment_screen.dart').readAsStringSync();
  final adminOrders =
      File('lib/screens/admin/admin_store_orders_screen.dart')
          .readAsStringSync();
  final list = File('lib/screens/orders_list_screen.dart').readAsStringSync();
  final fn = File('functions/index.js').readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();

  test('الإنشاء بانتظار الدفع — لا موافقة إدارية قبله', () {
    expect(service.contains("'status': 'awaiting_payment',"), isTrue);
    expect(service.contains("'payment_status': 'awaiting_payment',"), isTrue);
    expect(service.contains("'status': 'pending',"), isFalse,
        reason: 'عودة pending تعيد مسار «بانتظار الموافقة» الميت');
  });

  test('السلة تفتح شاشة الدفع فوراً لا شاشة «بانتظار الموافقة»', () {
    expect(store.contains('StorePaymentScreen('), isTrue);
    expect(store.contains('بانتظار موافقة الإدارة'), isFalse,
        reason: 'نص الموافقة القديم يجب ألا يظهر للعميل بعد الشراء');
  });

  test('بعد الدفع: under_review وعنوان التوصيل على طلب المتجر نفسه', () {
    expect(pay.contains("'status': 'under_review',"), isTrue);
    expect(pay.contains("'delivery_location': _deliveryLocation,"), isTrue,
        reason: 'أُلغي طلب التوصيل المرتبط — العنوان يجب أن يعيش هنا');
    // لا طلب توصيل مرتبط في orders (كان يُنتج بطاقتين وسجلّين).
    expect(pay.contains("collection('orders').doc().set"), isFalse);
  });

  test('أزرار الإدارة: تحت المراجعة ⇒ جاري التوصيل ⇒ تم التوصيل', () {
    expect(adminOrders.contains("'delivering')"), isTrue);
    expect(adminOrders.contains("'delivered')"), isTrue);
    expect(adminOrders.contains("case 'under_review':"), isTrue);
    expect(adminOrders.contains("case 'delivering':"), isTrue);
    // مسار الموافقة والتسعير النهائي حُذف من الجذور.
    expect(adminOrders.contains('_showApprovalDialog'), isFalse);
    expect(adminOrders.contains("'rejected')"), isFalse);
  });

  test('بطاقة العميل: زر الدفع للجديد غير المدفوع + الحالات الثلاث', () {
    expect(list.contains("status == 'awaiting_payment' || status == 'approved'"),
        isTrue);
    expect(list.contains("data['is_paid'] != true"), isTrue,
        reason: 'طلب أُكِّد دفعه خادمياً يجب ألا يعرض «ادفع الآن»');
    expect(list.contains('"تحت المراجعة"'), isTrue);
    expect(list.contains('"جاري التوصيل"'), isTrue);
  });

  test('الخادم: إشعار لحظي لكل نقلة + ترقية الدفع المؤكَّد', () {
    final i = fn.indexOf('exports.notifyClientOnStoreOrderStatus');
    expect(i, greaterThan(-1));
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('under_review:'), isTrue);
    expect(body.contains('delivering:'), isTrue);
    // مات تطبيق العميل بعد الدفع؟ الخادم يرقّي awaiting_payment ⇒ under_review.
    expect(body.contains('after.status === "awaiting_payment"'), isTrue,
        reason: 'بدونها يبقى طلب مدفوع بمظهر «بانتظار الدفع» للأبد');
    expect(body.contains('status: "under_review"'), isTrue);
  });

  test('القواعد: العميل يكتب under_review فقط بعد الدفع', () {
    expect(rules.contains("request.resource.data.status == 'under_review'"),
        isTrue);
    expect(rules.contains("request.resource.data.status == 'processing'"),
        isFalse, reason: 'حالة المسار القديم يجب ألا تبقى مسموحة للعميل');
    expect(rules.contains("'delivery_location'"), isTrue,
        reason: 'بدونها يرفض الأمن كتابة عنوان التوصيل فيفشل إنهاء الدفع');
  });
}
