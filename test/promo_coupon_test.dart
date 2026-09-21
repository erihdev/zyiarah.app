import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/promo_coupon.dart';

/// كوبونات قسم «العروض» (تصميم Stitch، 2026-09-16): ما يُعرض للعميل يجب أن
/// يجتاز شروط validateCoupon نفسها عند الدفع، ولا يُكشف كودٌ إلا بقرار
/// التسويق (show_in_offers) أو لصاحبه (target_user_id).
void main() {
  final now = DateTime(2026, 9, 16, 12);
  PromoCoupon c(
    String code, {
    String status = 'active',
    DateTime? expiry,
    int maxUses = 0,
    int uses = 0,
    bool show = true,
    String? target,
    String type = 'percentage',
    num value = 25,
  }) =>
      PromoCoupon(
        id: code.toLowerCase(),
        code: code,
        type: type,
        value: value,
        maxUses: maxUses,
        uses: uses,
        expiry: expiry,
        status: status,
        restrictedZones: const [],
        targetUserId: target,
        showInOffers: show,
        description: '',
      );

  group('PromoCoupon.fromMap', () {
    test('يقرأ مستند الإدارة كما يكتبه admin_coupons_screen', () {
      final p = PromoCoupon.fromMap('x', {
        'code': 'JAZAN25',
        'type': 'percentage',
        'value': 25,
        'maxUses': 100,
        'uses': 3,
        'expiry': Timestamp.fromDate(DateTime(2026, 12, 31)),
        'status': 'active',
        'restricted_zones': ['الداير', 'فيفاء'],
        'show_in_offers': true,
        'description': 'على أول طلب',
      });
      expect(p.code, 'JAZAN25');
      expect(p.isPercentage, isTrue);
      expect(p.headline, 'خصم 25%');
      expect(p.expiry, DateTime(2026, 12, 31));
      expect(p.restrictedZones, ['الداير', 'فيفاء']);
      expect(p.showInOffers, isTrue);
      expect(p.targetUserId, isNull);
      expect(p.description, 'على أول طلب');
    });

    test('يقرأ كوبون الإحالة كما يكتبه الخادم (target_user_id + description)', () {
      final p = PromoCoupon.fromMap('r', {
        'code': 'REF-ABC',
        'type': 'percentage',
        'value': 10,
        'maxUses': 1,
        'uses': 0,
        'status': 'active',
        'expiry': Timestamp.fromDate(DateTime(2026, 10, 16)),
        'target_user_id': 'u-referee',
        'description': 'خصم الإحالة 10% — مكافأة الانضمام',
      });
      expect(p.targetUserId, 'u-referee');
      expect(p.showInOffers, isFalse, reason: 'الغياب = مخفي');
      expect(p.isPersonalFor('u-referee'), isTrue);
      expect(p.isPersonalFor('someone'), isFalse);
    });

    test('يتسامح مع expiry نصّياً ومع القيم الغائبة، وfixed يُقرأ كريال', () {
      final p = PromoCoupon.fromMap('y', {
        'code': 'WINTER',
        'type': 'fixed',
        'value': 40.0,
        'expiry': '2026-11-01T00:00:00.000',
      });
      expect(p.expiry, DateTime(2026, 11, 1));
      expect(p.headline, 'خصم 40 ر.س');
      expect(p.maxUses, 0);
      expect(p.status, '');
      expect(p.restrictedZones, isEmpty);
      // نوع مجهول → نسبة (كما يفترض validateCoupon والدفع).
      expect(PromoCoupon.fromMap('z', {'type': 'weird', 'value': 5}).isPercentage,
          isTrue);
      expect(PromoCoupon.fromMap('z', {'value': 12.5}).headline, 'خصم 12.5%');
    });
  });

  group('isListableFor — شروط الدفع نفسها + قرار الظهور', () {
    test('يظهر: نشط، غير منتهٍ، لم يبلغ سقفه، ومعلَّم للعروض', () {
      expect(c('A', expiry: now.add(const Duration(days: 1)), maxUses: 10, uses: 9)
          .isListableFor('u1', now), isTrue);
      expect(c('B').isListableFor(null, now), isTrue,
          reason: 'كوبون عام يُعرض ولو كان القارئ زائراً');
    });

    test('يُخفى: معطّل أو منتهٍ أو مستنفَد أو بلا كود أو غير معلَّم', () {
      expect(c('A', status: 'inactive').isListableFor('u1', now), isFalse);
      expect(c('A', expiry: now.subtract(const Duration(minutes: 1)))
          .isListableFor('u1', now), isFalse);
      expect(c('A', maxUses: 5, uses: 5).isListableFor('u1', now), isFalse);
      expect(c('', ).isListableFor('u1', now), isFalse);
      expect(c('A', show: false).isListableFor('u1', now), isFalse,
          reason: 'كود قناة خاصة لا يُكشف بلا قرار التسويق');
    });

    test('الكوبون الشخصي يراه صاحبه وحده، ولو لم يُعلَّم للعروض', () {
      final personal = c('REF', show: false, target: 'u1');
      expect(personal.isListableFor('u1', now), isTrue);
      expect(personal.isListableFor('u2', now), isFalse);
      expect(personal.isListableFor(null, now), isFalse);
      // وحتى المعلَّم للعروض يبقى شخصياً.
      expect(c('REF2', show: true, target: 'u1').isListableFor('u2', now), isFalse);
    });
  });

  test('listableFor: الشخصي أولاً ثم الأقرب انتهاءً ثم بلا انتهاء', () {
    final list = PromoCoupon.listableFor([
      c('LATE', expiry: now.add(const Duration(days: 30))),
      c('NOEXP'),
      c('HIDDEN', show: false),
      c('MINE', target: 'u1', show: false, expiry: now.add(const Duration(days: 60))),
      c('SOON', expiry: now.add(const Duration(days: 2))),
      c('OTHERS', target: 'u9'),
    ], 'u1', now);
    expect(list.map((x) => x.code).toList(), ['MINE', 'SOON', 'LATE', 'NOEXP']);
  });
}
