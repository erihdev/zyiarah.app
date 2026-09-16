import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/screens/admin/admin_policies_screen.dart';

/// حارس ميزة «شروط وضوابط الخدمة» (تصميم Stitch، 2026-09-16): الشاشة الإدارية
/// والقائمة والقواعد وسلسلة فحوص المحاكي يجب أن تبقى متّسقة — الكتابة للسوبر
/// وحده في القواعد، فالقائمة لا تعرضها لدور آخر، والشاشة تكتب حقول النموذج فقط.
void main() {
  final admin =
      File('lib/screens/admin/admin_policies_screen.dart').readAsStringSync();
  final menu = File('lib/screens/admin/admin_more_screen.dart').readAsStringSync();
  final terms = File('lib/screens/terms_privacy_screens.dart').readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();
  final pkg = File('functions/package.json').readAsStringSync();

  test('الشاشة الإدارية تُترجم ضمن الفحوص (لا تعتمد على البناء الكامل وحده)', () {
    // الاستيراد هنا يجبر flutter test على ترجمة الملف كل مرة؛ بدونه لا يستورده
    // أي فحص، وflutter analyze لا يرى أخطاء الحزم الداخلية.
    expect(const AdminPoliciesScreen(), isA<StatefulWidget>());
  });

  test('القواعد: قراءة عامّة وكتابة super_admin فقط، والفحص في سلسلة المحاكي', () {
    final block = RegExp(
      r'match /service_policies/\{policyId\} \{\s*allow read: if true;\s*allow write: if isSuperAdmin\(\);\s*\}',
    );
    expect(block.hasMatch(rules), isTrue,
        reason: 'الشاشة تُفتح قبل الدخول فالقراءة عامّة؛ والكتابة للسوبر وحده');
    expect(pkg.contains('node test/rules.policies.test.js'), isTrue);
    expect(File('functions/test/rules.policies.test.js').existsSync(), isTrue);
  });

  test('القائمة الإدارية تعرض الشاشة للسوبر وحده (يطابق القواعد)', () {
    final entry = RegExp(
      r"'page': const AdminPoliciesScreen\(\),\s*'roles': \['super_admin'\],",
    );
    expect(entry.hasMatch(menu), isTrue,
        reason: 'دور يعجز عن الكتابة لا يجب أن يرى الشاشة أصلاً');
  });

  test('الشاشة الإدارية تكتب حقول النموذج + طابع الخادم، وتدقّق كل عملية', () {
    expect(admin.contains('.toMap()'), isTrue);
    expect(admin.contains("['updated_at'] = FieldValue.serverTimestamp()"), isTrue);
    expect(admin.contains('ServicePolicy.collectionPath'), isTrue);
    expect(admin.contains("'service_policies'"), isFalse,
        reason: 'اسم المجموعة من النموذج لا نصّاً مكرّراً');
    for (final action in [
      'CREATE_POLICY',
      'UPDATE_POLICY',
      'DELETE_POLICY',
      'ENABLE_POLICY',
      'DISABLE_POLICY',
    ]) {
      expect(admin.contains("'$action'"), isTrue, reason: action);
    }
    // الفشل ظاهر لا صامت (درس البانرات).
    expect(admin.contains('فشل الحفظ'), isTrue);
    expect(admin.contains('فشل تحديث البند'), isTrue);
    expect(admin.contains('خطأ أثناء الحذف'), isTrue);
  });

  test('شاشة العميل تقرأ المجموعة نفسها وتحتفظ بالنصّ القديم احتياطاً', () {
    expect(terms.contains('ServicePolicy.collectionPath'), isTrue);
    expect(terms.contains("'service_policies'"), isFalse);
    expect(terms.contains('class _LegacyTerms'), isTrue);
    expect(terms.contains('ServicePolicy.visibleSorted'), isTrue);
    // الخصوصية تعرض ما تنشره الإدارة إلى public_content/privacy (الموقع نفسه).
    expect(terms.contains("collection('public_content')"), isTrue);
    expect(terms.contains(".doc('privacy')"), isTrue);
  });
}
