import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) «متجر الشركات»: قسم في الملف الشخصي بمنتجات خاصة،
/// مع إبقاء المتجر الحالي كما هو حرفياً.
///
/// التصميم: مجموعة products واحدة + حقل store_audience على المنتج — لا مجموعة
/// ثانية ولا شاشات مكررة. الغياب = 'client' فيبقى كل منتج قديم في متجر العميل.
void main() {
  final service =
      File('lib/services/store_service.dart').readAsStringSync();
  final store = File('lib/screens/store_screen.dart').readAsStringSync();
  final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
  final admin =
      File('lib/screens/admin/admin_store_screen.dart').readAsStringSync();

  test('المنتج القديم بلا حقل ⇒ متجر العميل (المتجر الحالي كما هو)', () {
    expect(service.contains("data['store_audience'] ?? 'client'"), isTrue,
        reason: 'الافتراضية client تُبقي كل المنتجات القائمة في المتجر العادي');
    expect(service.contains("this.audience = 'client'"), isTrue);
  });

  test('البثّ يصفّي بالجمهور و null يعني الكل (لورقة السلة)', () {
    expect(service.contains('streamProducts({String? audience})'), isTrue);
    expect(
        service.contains(
            "audience == null || p.audience == audience"),
        isTrue,
        reason: 'التصفية محلية — المستندات القديمة بلا الحقل');
  });

  test('شاشة المتجر تدعم وضع الشركات وتُمرّر الجمهور للبثّ', () {
    expect(store.contains('this.companies = false'), isTrue);
    expect(store.contains("widget.companies ? 'companies' : 'client'"), isTrue,
        reason: 'بلا تمرير الجمهور يعرض متجر الشركات منتجات العميل');
    expect(store.contains("widget.companies ? 'متجر الشركات'"), isTrue);
    // السلة تحلّ أسماء منتجاتها أياً كان جمهورها.
    expect(store.contains('streamProducts(audience: null)'), isTrue);
  });

  test('بند «متجر الشركات» في قائمة الملف الشخصي', () {
    expect(profile.contains("'متجر الشركات'"), isTrue);
    expect(profile.contains('ZyiarahStoreScreen(companies: true)'), isTrue,
        reason: 'البند يجب أن يفتح المتجر بوضع الشركات لا المتجر العادي');
  });

  test('الإدارة: خانة «يظهر في» تُكتب وتُقرأ وتُعرض', () {
    expect(admin.contains("'store_audience': audience,"), isTrue,
        reason: 'بلا الكتابة يبقى كل منتج جديد في متجر العميل');
    expect(admin.contains("pData?['store_audience'] ?? 'client'"), isTrue,
        reason: 'فتحُ التعديل يجب أن يسترجع الجمهور المحفوظ');
    expect(admin.contains("Text('متجر العميل')"), isTrue);
    expect(admin.contains("Text('متجر الشركات')"), isTrue);
    // شارة في قائمة الإدارة تميّز منتجات الشركات.
    expect(
        admin.contains("(data['store_audience'] ?? 'client') == 'companies'"),
        isTrue);
  });
}
