import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (دمج من لوحة الويب — قرار المالك 2026-07-21) لوحة أدمن **التطبيق** هي الأساس.
/// دُمج من الويب إلى شاشة إعدادات التطبيق: **التحديث الإجباري** (يقرؤه app_update_service)
/// و**سياسة الخصوصية** (تُحفظ في main_settings وتُنشَر لمستند public_content/privacy
/// الذي تقرأه صفحة zyiarah.com/privacy العامة).
void main() {
  final s = File('lib/screens/admin/admin_settings_screen.dart')
      .readAsStringSync();

  test('التحديث الإجباري يُقرأ ويُكتب في system_configs/app_update', () {
    // قراءة عند فتح الشاشة.
    expect(s.contains("doc('app_update').get()"), isTrue);
    // كتابة عند الحفظ بالمفاتيح التي يقرؤها التطبيق فعلاً.
    expect(s.contains("doc('app_update').set"), isTrue);
    expect(s.contains("'enabled': _updateEnabled"), isTrue);
    expect(s.contains("'latest_build': int.tryParse"), isTrue);
    expect(s.contains("'force': _updateForce"), isTrue);
    expect(s.contains("'message': _updateMsgCtrl"), isTrue);
  });

  test('سياسة الخصوصية تُحفظ وتُنشَر للمستند العام (صفحة zyiarah.com/privacy)', () {
    expect(s.contains("'privacy_policy': _privacyPolicyCtrl"), isTrue);
    expect(s.contains("collection('public_content').doc('privacy').set"), isTrue,
        reason: 'بلا النشر العام لا تظهر السياسة على zyiarah.com/privacy');
    expect(s.contains("'content': _privacyPolicyCtrl.text.trim()"), isTrue);
  });
}
