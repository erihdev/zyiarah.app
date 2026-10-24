import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/store_order_flow.dart';

/// **دورةُ المتجرِ الواحدة (قرار المالك 2026-10-24)** — للمتجرَين معاً.
///
/// العميلةُ تختارُ من المتجرِ وموقعُها محدَّدٌ تلقائياً وتَدفع، فيَصلُ الطلبُ
/// «طلبات المتجر» مدفوعاً. الإدارةُ: بدء التجهيز ⇒ جاهز للتوصيل ⇒ تختارُ
/// السائق ⇒ السائقُ يُسلِّم ⇒ تم التسليم. والعميلةُ يَصلُها إشعارٌ بكلِّ نقلة.
///
/// كان متجرُ الأدواتِ طلباً مجدولاً (يومٌ ووقتٌ وسائقٌ تلقائيّ — 2026-07-21)
/// ومتجرُ الشركاتِ مباشراً تُديرُه الإدارةُ بلا سائق، والطلبُ غيرُ المدفوعِ
/// يَظهرُ للإدارةِ «جديد (بانتظار الموافقة)».
void main() {
  final service = File('lib/services/store_service.dart').readAsStringSync();
  final store = File('lib/screens/store_screen.dart').readAsStringSync();
  final pay = File('lib/screens/store_payment_screen.dart').readAsStringSync();
  final adminOrders =
      File('lib/screens/admin/admin_store_orders_screen.dart').readAsStringSync();
  final list = File('lib/screens/orders_list_screen.dart').readAsStringSync();
  final driver = File('lib/screens/driver_dashboard.dart').readAsStringSync();
  final deliveries =
      File('lib/widgets/driver_store_deliveries.dart').readAsStringSync();
  final fn = File('functions/index.js').readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();

  group('سلوكاً', () {
    test('خطواتُ الإدارةِ بالترتيب، و«مع السائق» ليست خطوتَها', () {
      expect(storeAdminNextStep('under_review'), StoreAdminStep.startPreparing);
      expect(storeAdminNextStep('preparing'), StoreAdminStep.markReady);
      expect(storeAdminNextStep('ready'), StoreAdminStep.assignDriver);
      expect(storeAdminNextStep('with_driver'), isNull,
          reason: 'السائقُ يُسلِّمُ لا الإدارة');
      expect(storeAdminNextStep('delivered'), isNull);
      expect(storeAdminNextStep('awaiting_payment'), isNull,
          reason: 'لا خطوةَ لطلبٍ لم يُدفَع');
      // إرثُ المسارِ القديمِ لا يَعلق.
      expect(storeAdminNextStep('processing'), StoreAdminStep.markReady);
      expect(storeAdminNextStep('delivering'), StoreAdminStep.markDelivered);
      for (final s in StoreAdminStep.values) {
        expect(s.label.trim(), isNotEmpty);
      }
      expect(StoreAdminStep.assignDriver.nextStatus, kStoreWithDriver);
    });

    test('الإدارةُ لا ترى ما لم يُدفَع', () {
      expect(storeOrderVisibleToAdmin({'status': 'awaiting_payment'}), isFalse);
      expect(storeOrderVisibleToAdmin({'status': 'pending'}), isFalse);
      expect(storeOrderVisibleToAdmin({'status': 'approved', 'is_paid': false}),
          isFalse);
      expect(storeOrderVisibleToAdmin({'status': 'under_review', 'is_paid': true}),
          isTrue);
      // المدفوعُ يَظهرُ ولو بقيت حالتُه قبلَ الدفع (مات التطبيقُ قبلَ الترقية).
      expect(storeOrderVisibleToAdmin({'status': 'awaiting_payment', 'is_paid': true}),
          isTrue);
      // ومستندٌ قديمٌ أداره أحدٌ يَبقى ظاهراً.
      expect(storeOrderVisibleToAdmin({'status': 'delivered'}), isTrue);
    });

    test('لكلِّ حالةٍ اسمٌ عربيّ، وللعميلةِ صياغتُها', () {
      for (final s in [
        'awaiting_payment', 'under_review', 'preparing', 'ready',
        'with_driver', 'delivering', 'delivered', 'cancelled',
      ]) {
        expect(storeStatusLabel(s).trim(), isNotEmpty, reason: s);
        expect(RegExp('[A-Za-z]').hasMatch(storeStatusLabel(s)), isFalse,
            reason: '$s: اسمٌ لاتينيّ يَصِلُ الشاشة');
      }
      expect(storeStatusLabel('under_review', forClient: true), 'تم استلام طلبكِ');
      expect(storeStatusLabel('with_driver'), 'مع السائق');
    });
  });

  group('مصدراً', () {
    test('المتجرانِ إلى الدفعِ مباشرةً — لا جدولةَ ولا فرع', () {
      expect(File('lib/screens/store_schedule_screen.dart').existsSync(), isFalse);
      expect(store.contains('StoreScheduleScreen('), isFalse);
      expect(store.contains('StorePaymentScreen('), isTrue);
      expect(store.contains('createStoreOrder('), isTrue);
      expect(store.contains('if (widget.companies) {\n        // متجر الشركات'),
          isFalse, reason: 'عاد التفريعُ بين المتجرَين');
      expect(store.contains("'متابعة لتحديد الموعد'"), isFalse);
    });

    test('الإنشاءُ بانتظار الدفع — لا موافقةَ إداريّةَ قبله', () {
      expect(service.contains("'status': 'awaiting_payment',"), isTrue);
      expect(service.contains("'payment_status': 'awaiting_payment',"), isTrue);
      expect(service.contains("'status': 'pending',"), isFalse);
    });

    test('العنوانُ موقعُ العميلةِ المحدَّدُ تلقائياً', () {
      expect(pay.contains('ClientLocation.instance.result'), isTrue,
          reason: 'العنوانُ لا يَبدأ بموقعِ الرأس');
      expect(pay.contains("'delivery_location': _deliveryLocation,"), isTrue);
      expect(pay.contains("'status': 'under_review',"), isTrue);
    });

    test('شاشةُ الإدارة: المدفوعُ وحدَه، والخطواتُ من القاعدة، والسائقُ تختارُه', () {
      expect(adminOrders.contains('storeOrderVisibleToAdmin('), isTrue);
      expect(adminOrders.contains('storeAdminNextStep(status)'), isTrue);
      expect(adminOrders.contains('_assignDriver(context, orderDoc.id, order)'),
          isTrue);
      expect(adminOrders.contains("'status': kStoreWithDriver,"), isTrue);
      expect(adminOrders.contains("'driver_id': picked['id'],"), isTrue);
      expect(adminOrders.contains("'جديد (بانتظار الموافقة)'"), isFalse);
      expect(adminOrders.contains('String _translateStatus('), isFalse,
          reason: 'نسخةُ أسماءٍ ثانيةٌ عادت');
    });

    test('لوحةُ السائق: توصيلاتُه ثمّ «تم التسليم»', () {
      expect(driver.contains('DriverStoreDeliveries(driverId:'), isTrue);
      expect(deliveries.contains(".where('driver_id', isEqualTo: widget.driverId)"),
          isTrue);
      expect(deliveries.contains(".where('status', isEqualTo: kStoreWithDriver)"),
          isTrue);
      expect(deliveries.contains("'status': kStoreDelivered,"), isTrue);
      expect(deliveries.contains("'delivered_at': FieldValue.serverTimestamp(),"),
          isTrue, reason: 'القواعدُ تَشترطُ لحظةَ الخادم');
    });

    test('«طلباتي»: الأسماءُ من القاعدة، وزرُّ الدفعِ لغيرِ المدفوع', () {
      expect(list.contains('storeStatusLabel(status, forClient: true)'), isTrue);
      expect(list.contains("status == 'awaiting_payment' || status == 'approved'"),
          isTrue);
      expect(list.contains("data['is_paid'] != true"), isTrue);
    });

    test('الخادم: إشعارٌ لكلِّ نقلةٍ وللسائقِ عند إسناده', () {
      final i = fn.indexOf('exports.notifyClientOnStoreOrderStatus');
      expect(i, greaterThan(-1));
      final body = fn.substring(i, fn.indexOf('exports.', i + 10));
      for (final s in ['under_review:', 'preparing:', 'ready:', 'with_driver:',
        'delivered:']) {
        expect(body.contains(s), isTrue, reason: 'لا إشعارَ للعميلة عند $s');
      }
      expect(body.contains('after.driver_id !== before.driver_id'), isTrue,
          reason: 'السائقُ لا يُشعَرُ بإسناده');
      expect(body.contains('"store_delivery_assigned"'), isTrue);
      // مات تطبيقُ العميلةِ بعد الدفع؟ الخادمُ يُرقّي awaiting_payment ⇒ under_review.
      expect(body.contains('after.status === "awaiting_payment"'), isTrue);
      expect(body.contains('status: "under_review"'), isTrue);
    });

    test('القواعد: العميلةُ تكتبُ under_review بعد الدفع، والسائقُ يُسلِّمُ وحدَه', () {
      expect(rules.contains("request.resource.data.status == 'under_review'"), isTrue);
      expect(rules.contains("'delivery_location'"), isTrue);
      expect(rules.contains("request.auth.uid == resource.data.get('driver_id', '')"),
          isTrue, reason: 'السائقُ لا يَقرأُ ما أُسنِدَ إليه');
      expect(rules.contains("resource.data.get('status', '') == 'with_driver'"), isTrue);
      expect(rules.contains(".hasOnly(['status', 'delivered_at'])"), isTrue);
      expect(rules.contains('request.resource.data.delivered_at == request.time'),
          isTrue);
    });
  });
}
