import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/day_capacity.dart';

/// سقف المنطقة اليومي (قرار المالك 2026-09-16): يضيّق السقف العام ولا يوسّعه،
/// وتقرؤه شاشتا الحجز من استجابة الإتاحة الخادمية، ويضبطه الأدمن على المنطقة.
void main() {
  test('dayIsFull: السقف العام أولاً', () {
    expect(dayIsFull(count: 10, max: 10), isTrue);
    expect(dayIsFull(count: 9, max: 10), isFalse);
    expect(dayIsFull(count: 0, max: 0), isTrue, reason: 'سقف صفر = مغلق (كما كان)');
  });

  test('dayIsFull: سقف المنطقة يضيّق فقط', () {
    expect(dayIsFull(count: 3, max: 10, zoneCount: 2, zoneMax: 2), isTrue);
    expect(dayIsFull(count: 3, max: 10, zoneCount: 1, zoneMax: 2), isFalse);
    // منطقة بسقف واسع لا تفتح يوماً امتلأ عالمياً.
    expect(dayIsFull(count: 10, max: 10, zoneCount: 0, zoneMax: 50), isTrue);
    // بلا سقف خاص (null أو 0) → السقف العام وحده.
    expect(dayIsFull(count: 3, max: 10, zoneCount: 99, zoneMax: null), isFalse);
    expect(dayIsFull(count: 3, max: 10, zoneCount: 99, zoneMax: 0), isFalse);
  });

  test('الخادم يعيد سقف المنطقة وعدّها، وكل مستهلكي الإتاحة يستعملون dayIsFull، والأدمن يكتب الحقل',
      () {
    final fn = File('functions/index.js').readAsStringSync();
    expect(fn.contains('require("./capacity")'), isTrue);
    expect(fn.contains('zoneMaxOrdersPerDay = zoneDailyCap(zq.docs[0].data())'), isTrue);
    expect(fn.contains('zoneMaxOrdersPerDay, zoneDailyCounts,'), isTrue,
        reason: 'الاستجابة تحمل السقف الخاص وعدّ المنطقة');
    final pkg = File('functions/package.json').readAsStringSync();
    expect(pkg.contains('node test/capacity.test.js'), isTrue);

    // كل من يقرأ getHourlyAvailability ليحكم على امتلاء يوم: شاشتا الحجز
    // بالعدد، وباقات العاملات، ومنتقي الخانات، وبوابة الدفع.
    for (final f in [
      'lib/screens/hourly_details_screen.dart',
      'lib/screens/subscription_plans_screen.dart',
      'lib/screens/event_worker_packages_screen.dart',
      'lib/widgets/booking_slot_picker.dart',
      'lib/screens/payment_summary_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains("data['zoneMaxOrdersPerDay']"), isTrue, reason: f);
      expect(src.contains("data['zoneDailyCounts']"), isTrue, reason: f);
      expect(src.contains('dayIsFull('), isTrue, reason: f);
      expect(src.contains('>= _maxOrdersPerDay'), isFalse,
          reason: '$f: كل فحص امتلاء عبر dayIsFull لا مقارنة مباشرة');
      expect(src.contains('< _maxOrdersPerDay'), isFalse, reason: f);
    }
    // الشاشات التي تعرف منطقة العميل تمرّرها — بلا zoneName لا سقف خاص أصلاً.
    for (final f in [
      'lib/screens/subscription_plans_screen.dart',
      'lib/screens/event_worker_packages_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains("'zoneName': _userZoneName"), isTrue,
          reason: '$f يمرّر المنطقة للخادم كما التنظيف المنزلي');
    }
    // باقات العاملات تجلب الإتاحة عند الفتح قبل معرفة المنطقة — فتعيد الجلب
    // حين تُعرف (تلقائياً أو من الخريطة) وإلا بقي السقف الخاص بلا أثر.
    final ev = File('lib/screens/event_worker_packages_screen.dart').readAsStringSync();
    expect('_reloadAvailabilityIfZoneChanged('.allMatches(ev).length, greaterThanOrEqualTo(3),
        reason: 'تعريف + استدعاء بعد التحديد التلقائي + بعد اختيار الخريطة');

    final admin = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(admin.contains("'max_orders_per_day': int.tryParse(maxPerDayCtrl.text.trim()) ?? 0,"),
        isTrue);
    expect(admin.contains('الحدّ اليومي للطلبات في هذه المنطقة'), isTrue);
  });
}
