import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (دمج من لوحة الويب — قرار المالك 2026-07-21) الإعلان المنبثق داخل التطبيق:
/// admin_broadcast يكتب نوع 'popup' بالحقول التي يعرضها popup_service (title/body/
/// popup_image)، ومُرتَّباً بـ sent_at (popup_service يرتّب/يفحص به) — لا created_at.
void main() {
  final b = File('lib/screens/admin/admin_broadcast_screen.dart')
      .readAsStringSync();
  final svc = File('lib/services/popup_service.dart').readAsStringSync();

  test('admin_broadcast يكتب نوع popup بالحقول الصحيحة', () {
    expect(b.contains("_notifType == 'popup'"), isTrue,
        reason: 'مبدّل النوع push/popup');
    expect(b.contains("'type': 'popup'"), isTrue);
    expect(b.contains("'popup_image'"), isTrue);
    expect(b.contains("'sent_at': FieldValue.serverTimestamp()"), isTrue,
        reason: 'بلا sent_at لا يجده popup_service');
  });

  test('popup_service يقرأ نفس الحقول (type/sent_at/popup_image)', () {
    expect(svc.contains("isEqualTo: 'popup'"), isTrue);
    expect(svc.contains("orderBy('sent_at'"), isTrue);
    expect(svc.contains("data['popup_image']"), isTrue);
  });
}
