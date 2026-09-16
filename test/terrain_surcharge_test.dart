import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/terrain_surcharge.dart';

/// تسعير القرى والوعورة (قرار المالك 2026-09-16 — Stitch `_56`): رسوم % على الأساس
/// قبل الضريبة من مستند المنطقة، يحسبها الخادم وشاشة الدفع من المصدر نفسه؛
/// المحافظة الأم تجمّع القرى في قائمة الأدمن.
String _read(String p) => File(p).readAsStringSync();

void main() {
  group('terrainPercentFrom / labels', () {
    test('0..100، وغير الرقمي/السالب/الفارغ = 0', () {
      expect(terrainPercentFrom(null), 0);
      expect(terrainPercentFrom(''), 0);
      expect(terrainPercentFrom('abc'), 0);
      expect(terrainPercentFrom(-3), 0);
      expect(terrainPercentFrom(12), 12);
      expect(terrainPercentFrom('15.5'), 15.5);
      expect(terrainPercentFrom(250), 100);
    });

    test('تسميات التضاريس والنسبة', () {
      expect(terrainLabel(kTerrainMountain), 'مرتفعات جبلية');
      expect(terrainLabel(kTerrainPlain), 'سهلية منبسطة');
      expect(terrainLabel(''), 'غير محدّدة');
      expect(fmtPercent(15), '15');
      expect(fmtPercent(12.5), '12.5');
    });
  });

  group('PriceBreakdown', () {
    test('الوعورة فوق الأساس قبل الضريبة، والصفوف تُجمَع على الصافي', () {
      // 200 أساس + 15% ضريبة = 230 كما تمرّره شاشة الخدمة.
      const b = PriceBreakdown(amount: 230, terrainPercent: 15);
      expect(b.rowBase, closeTo(200, 1e-9));
      expect(b.rowTerrain, closeTo(30, 1e-9));
      expect(b.rowSurge, closeTo(0, 1e-9));
      expect(b.total, closeTo(264.5, 1e-9)); // (200 + 30) × 1.15
      expect(b.subtotal, closeTo(230, 1e-9));
      expect(b.vat, closeTo(34.5, 1e-9));
      expect(b.rowBase + b.rowTerrain + b.rowSurge - b.rowDiscount,
          closeTo(b.subtotal, 1e-6),
          reason: 'أساس + وعورة + ذروة − خصم = الصافي');
    });

    test('مع الذروة والخصم: الذروة على (الأساس + الوعورة) والخصم مقصوص', () {
      const b = PriceBreakdown(
          amount: 230, terrainPercent: 15, surgeFactor: 1.2, discount: 20);
      // 230 × 1.15 × 1.2 = 317.4 − 20 = 297.4
      expect(b.grossBeforeDiscount, closeTo(317.4, 1e-9));
      expect(b.total, closeTo(297.4, 1e-9));
      expect(b.rowSurge, closeTo(46, 1e-9)); // (200 + 30) × 0.2
      expect(b.rowDiscount, closeTo(20 / 1.15, 1e-9));
      expect(b.rowBase + b.rowTerrain + b.rowSurge - b.rowDiscount,
          closeTo(b.subtotal, 1e-6));
      // كوبون أكبر من الطلب: الإجمالي لا يهبط تحت الصفر والصف مقصوص على المشحون.
      const big = PriceBreakdown(amount: 100, discount: 500);
      expect(big.total, 0);
      expect(big.rowDiscount, closeTo(100 / 1.15, 1e-9));
    });

    test('السعر الثابت (عقد): لا وعورة ولا ذروة ولا خصم — الخادم يطابقه حرفياً', () {
      const b = PriceBreakdown(
          amount: 500,
          terrainPercent: 30,
          surgeFactor: 1.5,
          discount: 50,
          fixedPrice: true);
      expect(b.total, 500);
      expect(b.rowTerrain, 0);
      expect(b.rowSurge, 0);
      expect(b.rowDiscount, 0);
    });

    test('التقريب لخانتين', () {
      const b = PriceBreakdown(amount: 57.4999999, terrainPercent: 0);
      expect(b.total, 57.5);
    });
  });

  test('groupByGovernorate: بترتيب أول ظهور، والبلا-محافظة أخيراً', () {
    final zones = [
      {'name': 'وادي جورا', 'governorate': 'الداير'},
      {'name': 'صبيا', 'governorate': ''},
      {'name': 'الرزان', 'governorate': 'فيفاء'},
      {'name': 'الجوف', 'governorate': ' الداير '},
      {'name': 'جازان'},
    ];
    final groups =
        groupByGovernorate(zones, (z) => z['governorate']?.toString());
    expect(groups.map((g) => g.governorate), ['الداير', 'فيفاء', null]);
    expect(groups.first.zones.map((z) => z['name']), ['وادي جورا', 'الجوف']);
    expect(groups.last.zones.map((z) => z['name']), ['صبيا', 'جازان']);
    // بلا أي محافظة: مجموعة واحدة بلا اسم (القائمة تبقى مسطّحة).
    final flat = groupByGovernorate(
        [{'name': 'x'}, {'name': 'y'}], (z) => z['governorate']?.toString());
    expect(flat.length, 1);
    expect(flat.single.governorate, isNull);
  });

  test('المصدر: الخادم وشاشة الدفع وحوار الأدمن ولوحة الويب على المفتاح نفسه', () {
    // الخادم: الوعورة من مستند المنطقة فوق الأساس في مساري ميسر والمحفظة.
    final pricing = _read('functions/pricing.js');
    expect(pricing.contains('function applyTerrainSurcharge(base, zone)'), isTrue);
    expect(pricing.contains('zone.terrain_surcharge_percent'), isTrue);
    final fn = _read('functions/index.js');
    expect('applyTerrainSurcharge(base0'.allMatches(fn).length, 2,
        reason: 'مسار ميسر (price-shadow) ومسار المحفظة (payWithWallet) معاً');
    expect(fn.contains('require("./pricing")'), isTrue);

    // شاشة الدفع: الحساب عبر PriceBreakdown، والنسبة من مستند المنطقة بالاسم،
    // وصفّ الوعورة معروض، والحقلان يُكتبان على الطلب للعرض الإداري.
    final pay = _read('lib/screens/payment_summary_screen.dart');
    expect(pay.contains('PriceBreakdown('), isTrue);
    expect(pay.contains("double get totalWithVat => _breakdown.total;"), isTrue);
    expect(pay.contains(".where('name', isEqualTo: widget.zoneName)"), isTrue);
    expect(pay.contains("data()['terrain_surcharge_percent']"), isTrue);
    expect(pay.contains('رسوم الوعورة والطرق الجبلية'), isTrue);
    expect(pay.contains("'terrain_surcharge_percent': _isFixedPrice ? 0 : _terrainPct,"), isTrue);
    expect(pay.contains('_breakdown.grossBeforeDiscount * (value / 100)'), isTrue,
        reason: 'خصم النسبة على المشحون بعد الوعورة والذروة كما في الخادم');
    expect(pay.contains('widget.amount * _surgeFactor * (value / 100)'), isFalse);

    // حوار الأدمن (التطبيق) يكتب المفاتيح الثلاثة ويحرس 0..100، والقائمة تجمّع.
    final admin = _read('lib/screens/admin/admin_hourly_zones_screen.dart');
    expect(admin.contains("'governorate': governorateCtrl.text.trim(),"), isTrue);
    expect(admin.contains("'terrain': terrain,"), isTrue);
    expect(admin.contains("'terrain_surcharge_percent': pctVal,"), isTrue);
    expect(admin.contains('رسوم الوعورة يجب أن تكون بين 0 و100%'), isTrue);
    expect(admin.contains('groupByGovernorate<QueryDocumentSnapshot>('), isTrue);
    expect(admin.contains("labelText: 'رسوم الوعورة % (اختياري)'"), isTrue);

    // لوحة الويب: المفاتيح نفسها حرفياً (تكافؤ)، والحارس نفسه.
    final web = _read('admin_panel/src/pages/Settings.tsx');
    expect(web.contains('terrain_surcharge_percent: terrainPct,'), isTrue);
    expect(web.contains('governorate: newZone.governorate.trim(),'), isTrue);
    expect(web.contains("toast.error('رسوم الوعورة يجب أن تكون بين 0 و100%')"), isTrue);

    // تفاصيل الطلب الإدارية تعرض سطر الوعورة إن وُجد.
    final details = _read('lib/screens/admin/admin_order_details_screen.dart');
    expect(details.contains('منها رسوم الوعورة (قبل الضريبة)'), isTrue);
    // كوبون النسبة يُعاد حسابه حين تصل الوعورة/الذروة بعد تطبيقه.
    expect(pay.contains('_recomputePercentDiscount();'), isTrue);
    expect('_recomputePercentDiscount();'.allMatches(pay).length, 2,
        reason: 'بعد جلب الذروة وبعد جلب الوعورة');

    // الموثَّق في المخطط.
    final bp = _read('ZIYARAH_BLUEPRINT.md');
    expect(bp.contains('terrain_surcharge_percent'), isTrue);
    expect(bp.contains('governorate (string'), isTrue);
  });
}
