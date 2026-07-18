import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاس إصلاحات تدقيق التحقّق الشامل (2026-07-18): 5 ثغرات مؤكَّدة أُصلحت.
/// النمط الأبرز: لوحة الويب الإدارية (React) لم تُحدَّث لدورة حياة المتجر/السيارات
/// المباشرة، وموضعان لإشعارات العميل كانا يفقدان الوارد بلا توكن FCM.
void main() {
  final fn = File('functions/index.js').readAsStringSync();
  final ordersList = File('lib/screens/orders_list_screen.dart').readAsStringSync();
  final storeTsx = File('admin_panel/src/pages/StoreOrders.tsx').readAsStringSync();
  final ordersTsx = File('admin_panel/src/pages/Orders.tsx').readAsStringSync();

  test('إشعار انطلاق السائق للعميل عبر queuePush (وارد بلا توكن)', () {
    final i = fn.indexOf('notifyClientOnDriverDeparture');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('queuePush('), isTrue,
        reason: '_pushToUid يفقد الإشعار لعميل الويب بلا توكن بلا أثر في الوارد');
    expect(body.contains('_pushToUid('), isFalse);
  });

  test('تذكيرات موعد العميل عبر queuePush', () {
    final i = fn.indexOf('remindClientsUpcomingAppointments');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('_pushToUid('), isFalse,
        reason: 'كان يضبط علم الإرسال ثم يتخطّى بصمت العميل بلا توكن');
    expect(RegExp(r'queuePush\(').allMatches(body).length, greaterThanOrEqualTo(2));
  });

  test('بطاقة العميل: خدمة مُدارة بلا سائق لا تعرض «تتبع السائق» الميت', () {
    expect(
        ordersList.contains(
            "status == 'under_review' ||\n                  (status == 'in_progress' && order['driver_id'] == null)"),
        isTrue,
        reason: 'طلب سيارة (بلا سائق أبداً) كان يعرض تتبّعاً يقول «انتظر السائق» للأبد');
    expect(ordersList.contains('تحت المراجعة — تصلك الإشعارات'), isTrue);
  });

  test('لوحة الويب: متجر مباشر — أزرار بدء التوصيل/تم التوصيل والحالات', () {
    // كانت أزرار الموافقة/الرفض معلّقة على pending الذي لا ينتجه المسار المباشر.
    expect(storeTsx.contains("order.status === 'under_review' || order.status === 'processing'"),
        isTrue);
    expect(storeTsx.contains("handleStatusUpdate(order.id, 'delivering')"), isTrue);
    expect(storeTsx.contains("handleStatusUpdate(order.id, 'delivered')"), isTrue);
    expect(storeTsx.contains("under_review: 'مدفوع — تحت المراجعة'"), isTrue);
  });

  test('لوحة الويب: طلبات السيارة المُدارة — بدء/إتمام التنفيذ وشارات الحالة', () {
    expect(ordersTsx.contains("case 'under_review':"), isTrue);
    expect(ordersTsx.contains("handleAdvanceManaged(order, 'in_progress')"), isTrue);
    expect(ordersTsx.contains("handleAdvanceManaged(order, 'completed')"), isTrue);
    // «تم التنفيذ» يظهر فقط للمُدار بلا سائق (لا يخلط مع طلب سائق قيد التنفيذ).
    expect(ordersTsx.contains("order.status === 'in_progress' && !order.driver_id"),
        isTrue);
  });
}
