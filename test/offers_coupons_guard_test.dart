import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس ميزة كوبونات «العروض» (تصميم Stitch، 2026-09-16): قرار الظهور يُكتب من
/// حوار الكوبونات الإداري، والشاشة العميلة تقرأ بالنموذج لا بنصوص مكرّرة.
void main() {
  final admin = File('lib/screens/admin/admin_coupons_screen.dart').readAsStringSync();
  final offers = File('lib/screens/offers_screen.dart').readAsStringSync();
  final blueprint = File('ZIYARAH_BLUEPRINT.md').readAsStringSync();

  test('حوار الكوبونات يكتب show_in_offers والوصف ويتلف حاسّته', () {
    expect(admin.contains("'show_in_offers': showInOffers,"), isTrue);
    expect(admin.contains("'description': descCtrl.text.trim(),"), isTrue);
    expect(admin.contains('descCtrl.dispose();'), isTrue);
    // الجديد معروض افتراضياً، والقديم مخفي حتى يُفعَّل.
    expect(admin.contains("data == null ? true : data['show_in_offers'] == true"), isTrue);
    expect(admin.contains("'في العروض'"), isTrue, reason: 'شارة في القائمة الإدارية');
  });

  test('شاشة العروض تقرأ بالنموذج وتُصفّي بقواعده', () {
    expect(offers.contains('PromoCoupon.collectionPath'), isTrue);
    expect(offers.contains("'promo_codes'"), isFalse);
    expect(offers.contains('PromoCoupon.listableFor('), isTrue);
    // **كان هذا يُثبّتُ «الاستعلامَ نفسَه الذي يبدأ به validateCoupon»** —
    // وكلاهما زال: `validateCoupon` لم تَعد تَستعلمُ المجموعةَ أصلاً (صارت
    // نداءً خادميّاً)، وهذه الشاشةُ صارت استعلامَين **يُثبِتانِ** شرطَ
    // القاعدةِ الجديدة. والسببُ أنّ القراءةَ المفتوحة (`allow read: if
    // isLoggedIn()`) كانت تَكشفُ كلَّ كودِ خصمٍ لكلِّ عميلة — ومنها ما
    // وسَمَته الإدارةُ `show_in_offers: false` كي لا يُكشَف.
    expect(offers.contains("where('show_in_offers', isEqualTo: true)"), isTrue,
        reason: 'الاستعلامُ المُعلَنُ — يُثبِتُ الفرعَ الأوّلَ من القاعدة');
    expect(offers.contains("where('target_user_id', isEqualTo: uid)"), isTrue,
        reason: 'الاستعلامُ الموجَّهُ — يُثبِتُ الفرعَ الثاني');
    expect(offers.contains("where('status', isEqualTo: 'active')"), isFalse,
        reason: 'الاستعلامُ القديمُ يَقرأُ كلَّ كوبونٍ نشط');
    // أرقام الإحالة من الخدمة لا من نصّ ثابت.
    expect(offers.contains('ZyiarahReferralService.referrerRewardSar'), isTrue);
    expect(offers.contains('ZyiarahReferralService.refereeDiscountPercent'), isTrue);
  });

  test('نموذج البيانات في المخطط يذكر الحقول الفعلية', () {
    expect(blueprint.contains('show_in_offers'), isTrue);
    expect(blueprint.contains('discount_type'), isFalse,
        reason: 'الاسم القديم لم يكن يطابق الكود (type/value/maxUses)');
  });
}
