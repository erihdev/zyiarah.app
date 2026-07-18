import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zyiarah/models/car_line.dart';

/// (قرار المالك 2026-07-18) «تنظيف داخلية السيارة»: بطاقة خدمة جديدة على نمط
/// المكيفات حرفياً — مراتب وأسقف السيارة، ثلاثة أحجام (صغيرة/وسط/كبيرة)
/// تسعّرها الإدارة لكل منطقة، طلب مباشر مدفوع بإسناد تلقائي.
void main() {
  final zonesScreen =
      File('lib/screens/admin/admin_hourly_zones_screen.dart')
          .readAsStringSync();
  final carScreen =
      File('lib/screens/car_interior_details_screen.dart').readAsStringSync();
  final seed = File('lib/services/geofence_service.dart').readAsStringSync();
  final metaView =
      File('lib/widgets/service_meta_view.dart').readAsStringSync();
  final dash = File('lib/screens/client_dashboard.dart').readAsStringSync();

  group('أسماء حقول الأسعار تطابق شاشة نطاقات التغطية حرفياً', () {
    // درس المكيفات: اختلاف حرف واحد = سعر صفر = خدمة معطّلة بلا سبب ظاهر.
    for (final size in CarSize.values) {
      test(size.label, () {
        final field = carPriceField(size);
        expect(zonesScreen.contains("'$field'"), isTrue,
            reason: '$field غائب عن شاشة المناطق — الإدارة لا تملك مكاناً '
                'لتسعير هذا الحجم');
      });
    }

    test('الحقول الثلاثة في كلا الحفظَين والنسخ والبذر', () {
      for (final f in ['carSmallPrice', 'carMediumPrice', 'carLargePrice']) {
        // حفظ الحوار + تطبيق على مناطق = مرتان على الأقل.
        expect(RegExp("'$f': double.tryParse").allMatches(zonesScreen).length,
            2,
            reason: '$f يجب أن يُكتب في حفظ المنطقة وفي «تطبيق على مناطق»');
        expect(zonesScreen.contains("n(src['$f'])"), isTrue,
            reason: '$f غائب عن تعبئة «نسخ الأسعار من منطقة سابقة»');
        expect(seed.contains("'$f': 0,"), isTrue,
            reason: 'بذر التثبيت الجديد بلا $f=0 يجعل الحجم يظهر مسعّراً '
                'بقيمة قديمة أو يكسر «لا سعر ⇒ لا بيع»');
      }
    });
  });

  group('شاشة العميل — نمط المكيفات', () {
    test('بلا سعر ⇒ بلا بيع: لا افتراضيات والحجم غير المسعّر لا يُعرض', () {
      expect(carScreen.contains('as num?)?.toDouble() ?? 0'), isTrue);
      expect(carScreen.contains('if (_isEnabled(size)) _sizeRow(size)'), isTrue,
          reason: 'حجم بلا سعر يجب ألا يُرسم له صف إطلاقاً');
    });

    test('نمط المتجر: بلا موعد وبلا سائق — الإدارة تقود بعد الدفع', () {
      // قرار المالك (نفس يوم الإطلاق): «نفس طريقة المتجر — يدفع ثم للمراجعة
      // وجاري التنفيذ وتم التنفيذ». لا منتقي موعد ولا hours/serviceDate.
      expect(carScreen.contains('ZyiarahBookingSlotPicker'), isFalse,
          reason: 'عودة منتقي الموعد تعيد السيارات لمسار إسناد السائقين');
      expect(carScreen.contains('serviceDate:'), isFalse);
      expect(carScreen.contains('hours:'), isFalse);
      expect(carScreen.contains("'kind': 'car_interior'"), isTrue);
    });

    test('الخادم يرقّي المدفوع بلا موعد لتحت المراجعة والإدارة تقوده', () {
      final fn = File('functions/index.js').readAsStringSync();
      final i = fn.indexOf('exports.onOrderWritten');
      final body = fn.substring(i, fn.indexOf('exports.', i + 10));
      expect(body.contains('!afterData.service_date'), isTrue,
          reason: 'بدون فرع «بلا موعد» يبقى طلب السيارة pending صامتاً للأبد');
      expect(body.contains('status: "under_review"'), isTrue);
      final adminOrders =
          File('lib/screens/admin/admin_orders_screen.dart')
              .readAsStringSync();
      expect(adminOrders.contains('_advanceManagedOrder'), isTrue);
      expect(adminOrders.contains("'جاري التنفيذ'"), isTrue);
      expect(adminOrders.contains("'تم التنفيذ'"), isTrue);
      final notify = File('functions/index.js').readAsStringSync();
      expect(notify.contains('"under_review"'), isTrue,
          reason: 'العميل يجب أن يُشعَر لحظة دخول طلبه المراجعة');
    });

    test('التعريف الذي طلبه المالك ظاهر: مراتب وأسقف السيارة', () {
      expect(carScreen.contains('المراتب (المقاعد) وأسقف السيارة'), isTrue);
    });
  });

  group('العرض والتقارير', () {
    test('service_meta لبنود السيارة مقروء في الملخّص والجدول', () {
      expect(metaView.contains("case 'car_interior':"), isTrue,
          reason: 'بدونها بطاقات الإدارة لا تعرض تفصيل السيارات');
      expect(metaView.contains("'car_interior' => _acRows(m)"), isTrue);
      expect(metaView.contains('سيارة'), isTrue);
    });

    test('البطاقة على الرئيسية والصورة أصل حقيقي', () {
      expect(dash.contains('CarInteriorDetailsScreen()'), isTrue);
      expect(dash.contains("'assets/images/car_cleaning.png'"), isTrue);
      expect(File('assets/images/car_cleaning.png').existsSync(), isTrue,
          reason: 'البطاقة تشير لصورة غير موجودة ⇒ أيقونة بديلة باهتة');
      expect(
          File('pubspec.yaml')
              .readAsStringSync()
              .contains('assets/images/car_cleaning.png'),
          isTrue,
          reason: 'أصل غير معلن في pubspec لا يُحزم مع التطبيق');
    });
  });

  group('CarLine', () {
    test('toMap يحمل ما يحتاجه السائق والإدارة', () {
      final m = const CarLine(size: CarSize.medium, count: 2).toMap(150);
      expect(m['label'], 'سيارة وسط');
      expect(m['count'], 2);
      expect(m['unit_price'], 150);
      expect(m['line_total'], 300);
    });
  });
}
