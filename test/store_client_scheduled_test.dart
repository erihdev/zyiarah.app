import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-21) متجر «الأدوات والتنظيف» (متجر العميل) صار طلباً
/// **مجدولاً** كبقية الخدمات: العميل يختار العنوان + التاريخ والوقت، ويُسنَد سائق
/// يوصّل المنتجات في الموعد — يمرّ بنفس خطّ الخدمات المجدولة في مجموعة `orders`
/// (فحص سعة ⇒ pending ⇒ إسناد تلقائي ⇒ scheduled)، لا مسار store_orders المباشر.
///
/// متجر **الشركات** يبقى طلباً مباشراً بلا تغيير (يغطّيه store_direct_flow_test).
void main() {
  final store = File('lib/screens/store_screen.dart').readAsStringSync();
  final schedule =
      File('lib/screens/store_schedule_screen.dart').readAsStringSync();
  final metaView =
      File('lib/widgets/service_meta_view.dart').readAsStringSync();
  final pay =
      File('lib/screens/payment_summary_screen.dart').readAsStringSync();

  test('السلة تفرّع بالجمهور: العميل ⇒ جدولة، الشركات ⇒ دفع مباشر', () {
    expect(store.contains('StoreScheduleScreen('), isTrue,
        reason: 'متجر العميل يجب أن يفتح شاشة الجدولة');
    expect(store.contains('StorePaymentScreen('), isTrue,
        reason: 'متجر الشركات يبقى على الدفع المباشر');
    expect(store.contains('if (widget.companies)'), isTrue,
        reason: 'بلا التفريع يذهب المتجران لنفس المسار');
  });

  test('متجر العميل لا يُنشئ سجلّ store_orders (يُنشأ طلب orders عند الدفع)', () {
    // مسار العميل يمرّر الأصناف والإجمالي فقط؛ createStoreOrder لمتجر الشركات وحده.
    expect(schedule.contains('createStoreOrder'), isFalse,
        reason: 'الجدولة تمرّ عبر PaymentSummaryScreen لا store_orders');
    expect(
        store.contains("widget.onSubmitted({'items': items, 'total': total})"),
        isTrue);
  });

  test('شاشة الجدولة: منتقي موعد + hours/serviceDate ⇒ إسناد تلقائي', () {
    expect(schedule.contains('ZyiarahBookingSlotPicker'), isTrue,
        reason: 'الطلب مجدول — منتقي الموعد إلزامي');
    expect(schedule.contains('serviceDate: _selectedSlot'), isTrue);
    expect(schedule.contains('hours: _deliveryHours'), isTrue,
        reason: 'بلا hours+serviceDate لا يُسنَد سائق تلقائياً');
    expect(schedule.contains("'kind': 'store_products'"), isTrue);
    expect(schedule.contains('PaymentSummaryScreen('), isTrue);
    expect(schedule.contains("serviceName: 'طلب من المتجر'"), isTrue);
    // بلا موعد (أو موقع) لا يُتاح الانتقال للدفع.
    expect(
        schedule
            .contains('_selectedLocation != null && _selectedSlot != null'),
        isTrue);
  });

  test('عرض التفصيل: store_products مقروء (ملخّص + جدول + ترويسة)', () {
    // بدونه يصل الطلب للسائق والإدارة بمبلغ مجرّد بلا بيان بالأصناف.
    expect(metaView.contains("case 'store_products':"), isTrue,
        reason: 'ملخّص السطر الواحد (بطاقات القوائم)');
    expect(metaView.contains("'store_products' => _storeRows(m)"), isTrue,
        reason: 'الجدول الكامل (تفاصيل الطلب)');
    expect(metaView.contains('List<_MetaRow> _storeRows'), isTrue);
    expect(metaView.contains('منتج'), isTrue, reason: 'ترويسة العدد');
  });

  test('ملخّص الدفع: يخفي «المدة» و«عدد العاملات» لطلب المتجر', () {
    // حقول خدمة التنظيف مضلّلة لتوصيل منتجات (عاملة واحدة/ساعتان).
    expect(pay.contains("kind'] == 'store_products'"), isTrue);
    expect(pay.contains('!_isStoreOrder'), isTrue);
    expect(pay.contains("_buildRowDetail('عدد المنتجات'"), isTrue,
        reason: 'يُعرض عدد المنتجات بدلاً من المدة/العاملات');
  });
}
