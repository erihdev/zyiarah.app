import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاس إصلاحات تدقيق التحقّق الشامل (2026-07-18): 5 ثغرات مؤكَّدة أُصلحت.
/// النمط الأبرز: لوحة الويب الإدارية (React) لم تُحدَّث لدورة حياة المتجر/السيارات
/// المباشرة، وموضعان لإشعارات العميل كانا يفقدان الوارد بلا توكن FCM.
void main() {
  final fn = File('functions/index.js').readAsStringSync();
  final ordersList = File('lib/screens/orders_list_screen.dart').readAsStringSync();
  // نصوصُ «لا تتبّع» انتقلت إلى القاعدة المشتركة مع إصلاح 2026-10-04.
  final tracking = File('lib/utils/order_tracking.dart').readAsStringSync();
  final storeTsx = File('admin_panel/src/pages/StoreOrders.tsx').readAsStringSync();
  final ordersTsx = File('admin_panel/src/pages/Orders.tsx').readAsStringSync();

  test('إشعار انطلاق السائق للعميل عبر queuePush (وارد بلا توكن)', () {
    // المِرساةُ `exports.` لا الاسمُ العاري: تعليقٌ في دالّةٍ أخرى يَذكرُ
    // الاسمَ يُزحزِحُ الشريحةَ إلى غيرِ موضعِها — وقد وقعَ ذلك فعلاً في
    // الفحصِ التالي (2026-10-08).
    final i = fn.indexOf('exports.notifyClientOnDriverDeparture');
    expect(i, greaterThan(0), reason: 'التصديرُ غائب');
    final body = fn.substring(i, fn.indexOf('\nexports.', i + 10));
    expect(body.contains('queuePush('), isTrue,
        reason: '_pushToUid يفقد الإشعار لعميل الويب بلا توكن بلا أثر في الوارد');
    expect(body.contains('_pushToUid('), isFalse);
  });

  test('تذكيرات موعد العميل عبر queuePush', () {
    final i = fn.indexOf('exports.remindClientsUpcomingAppointments');
    expect(i, greaterThan(0), reason: 'التصديرُ غائب');
    final body = fn.substring(i, fn.indexOf('\nexports.', i + 10));
    expect(body.contains('_pushToUid('), isFalse,
        reason: 'كان يضبط علم الإرسال ثم يتخطّى بصمت العميل بلا توكن');
    expect(RegExp(r'queuePush\(').allMatches(body).length, greaterThanOrEqualTo(2));
  });

  test('بطاقة العميل: خدمة مُدارة بلا سائق لا تعرض «تتبع السائق» الميت', () {
    // كان هذا يُثبِّت **تعداد حالتين** حرفيّاً: `under_review` و`in_progress`
    // بلا سائق. والقرارُ سليم، لكنّ التعداد تركَ `scheduled` بلا سائق خارجه —
    // وهي الحالةُ التي شوهدت حيّةً (2026-10-04): زياراتُ اشتراكٍ من يوليو تعرض
    // «تتبع السائق» والبطاقةُ فوقه تقول «انتهى الموعد». فأُعيد توجيهُ الحارس
    // إلى **القاعدة** بدل القائمة، وصار أشدّ: يمنع عودةَ التعداد أصلاً.
    //
    // ثمّ اتّسعت القاعدةُ نفسُها: «سائقٌ وموقع» كانت ناقصةً — الزياراتُ ذاتُها
    // لها سائقٌ وموقع، فظلّ الزرُّ ظاهراً. فأُضيف شرطُ الموعد، وأُعيد توجيهُ
    // هذا الفحص معه إلى الصيغة الكاملة (التفصيلُ في `order_tracking_test`).
    expect(
        ordersList.contains(
            'else if (!canTrackOrder(order, passed: _apptPassed(order)))'),
        isTrue,
        reason: 'طلب سيارة (بلا سائق أبداً) كان يعرض تتبّعاً يقول «انتظر السائق» للأبد');
    expect(ordersList.contains("status == 'under_review' ||"), isFalse,
        reason: 'عاد تعدادُ الحالات — وهو ما أبقى العطل في الحالة التي يغفلها');
    expect(tracking.contains('تحت المراجعة — تصلك الإشعارات'), isTrue);
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
