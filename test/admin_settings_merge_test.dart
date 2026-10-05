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
    //
    // وأُعيد توجيهُه ثالثةً (2026-10-05): الكتابةُ صارت **داخلَ دفعةٍ ذرّيّة**
    // لأنّ الحفظَ كان يَكتبُ أربعةَ مستنداتٍ بالتتابعِ وبينها فاحِصان، فخطأُ
    // صندوقٍ يَترُكُ ما سبقَه مكتوباً والأدمنُ يُقرأُ له «فشل». فالشكلُ
    // المُثبَّتُ هو شكلُ الدفعةِ — ورجوعٌ إلى كتابةٍ مباشرةٍ يُسقطُ هذا
    // الفحصَ أيضاً، لا حارسَ الترتيبِ وحدَه
    // (test/settings_save_atomic_test.dart).
    expect(s.contains("batch.set(_db.collection('system_configs')"
        ".doc('app_update'), {"), isTrue,
        reason: 'كتابةُ app_update ليست في الدفعةِ الذرّيّة');
    expect(s.contains("'enabled': _updateEnabled"), isTrue);
    // (كان يُثبِّت `latest_build` الموحّد — وهو المفتاح الذي **لا** تقرؤه الخدمة
    //  إلا عند غياب حقل المنصّة، فكان الحارس يحرس عطلاً. انظر app_update_keys_test.)
    //
    // وأُعيد توجيهُه ثانيةً (2026-10-05) وشُدّد: كان يُثبّتُ
    // `int.tryParse` بعينِه، وهو الشكلُ الذي **يُسقِطُ الفارغَ إلى صفر** —
    // والصفرُ يُفضَّلُ على الاحتياطيِّ الموحّدِ فيُطفئُ البوّابةَ بصمت. فصارَ
    // يُثبّتُ القيمةَ **المُتحقَّقَ منها** ويَمنعُ الإسقاطَ.
    expect(s.contains("'latest_build_ios': iosBuild"), isTrue);
    expect(s.contains("'latest_build_android': androidBuild"), isTrue);
    expect(s.contains("'latest_build_ios': int.tryParse"), isFalse,
        reason: 'الإسقاطُ إلى صفرٍ عادَ — راجِعْ test/build_gate_test.dart');
    expect(s.contains("'force': _updateForce"), isTrue);
    expect(s.contains("'message': _updateMsgCtrl"), isTrue);
  });

  test('سياسة الخصوصية تُحفظ وتُنشَر للمستند العام (صفحة zyiarah.com/privacy)', () {
    expect(s.contains("'privacy_policy': _privacyPolicyCtrl"), isTrue);
    expect(
        s.contains(
            "batch.set(_db.collection('public_content').doc('privacy'), {"),
        isTrue,
        reason: 'بلا النشر العام لا تظهر السياسة على zyiarah.com/privacy — '
            'وهو في الدفعةِ الذرّيّةِ كي لا تَفترِقَ نسختا السياسة');
    expect(s.contains("'content': _privacyPolicyCtrl.text.trim()"), isTrue);
  });
}
