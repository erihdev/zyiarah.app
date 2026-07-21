import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (دمج من لوحة الويب — قرار المالك 2026-07-21) وضع الصيانة: زر في إعدادات التطبيق
/// يكتب maintenance_mode، وAuthWrapper يفرضه على **العملاء فقط** (fail-open) عبر
/// شاشة صيانة. الإدارة والسائقون لا يتأثّرون كي يديروا/يوقفوا الصيانة.
void main() {
  final settings =
      File('lib/screens/admin/admin_settings_screen.dart').readAsStringSync();
  final main = File('lib/main.dart').readAsStringSync();

  test('الإعدادات تقرأ وتكتب maintenance_mode', () {
    expect(settings.contains("'maintenance_mode': _maintenanceMode"), isTrue);
    expect(
        settings
            .contains("_maintenanceMode = data['maintenance_mode'] == true"),
        isTrue);
  });

  test('AuthWrapper يفرض الصيانة على العملاء فقط (fail-open + شاشة صيانة)', () {
    expect(main.contains('_MaintenanceScreen'), isTrue,
        reason: 'شاشة الصيانة للعميل');
    expect(main.contains("data['maintenance_mode'] == true"), isTrue);
    // fail-open: العميل يرى ClientDashboard افتراضياً؛ الصيانة فقط عند العلم.
    expect(main.contains('return const ClientDashboard();'), isTrue);
    // الإدارة قبل فرع العميل فلا تُقفل بالصيانة.
    expect(main.contains('return const AdminDashboardScreen();'), isTrue);
  });
}
