import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارسات الميزتين اللتين طلبهما المالك (2026-08-08):
/// 1) خدمة «عاملات للمناسبات» — العميل يختار العدد واليوم والساعة.
/// 2) مواد التنظيف داخل طلب التنظيف المنزلي — **فاتورة واحدة بطلب واحد**
///    بدل طلب متجر منفصل بفاتورة وموعد ثانيين.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// الملف بلا أسطر التعليقات — التعليق يشرح أن `hour_rate` **لا** يُقرأ، فمسحُ
  /// النصّ الخام يلتقط الشرح نفسه ويفشل بلا سبب حقيقي.
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('عاملات للمناسبات', () {
    final screen = read('lib/screens/event_workers_details_screen.dart');
    final zones = read('lib/screens/admin/admin_hourly_zones_screen.dart');
    final dash = read('lib/screens/client_dashboard.dart');
    final pricing = read('functions/pricing.js');

    test('الشاشة تُخرج العدد والساعات في service_meta', () {
      expect(screen.contains("'kind': 'event_workers'"), isTrue);
      expect(screen.contains("'workers': _workers"), isTrue);
      expect(screen.contains("'event_hours': _hours"), isTrue);
    });

    test('العميل يختار اليوم والساعة عبر منتقي الخانات المشترك', () {
      // المنتقي نفسه = يرث فحص ساعات فتح المنطقة والساعات المقفلة وتوفّر السائق.
      expect(screen.contains('ZyiarahBookingSlotPicker'), isTrue);
      expect(screen.contains('durationHours: _hours'), isTrue);
    });

    test('بلا سعر ⇒ بلا بيع', () {
      expect(screen.contains('kEventWorkerHourPriceField'), isTrue);
      expect(screen.contains('bool get _isPriced => _hourRate > 0'), isTrue);
      expect(screen.contains('_unpricedBanner'), isTrue);
    });

    test('المبلغ المُمرَّر للدفع شامل الضريبة والمعروض قبلها', () {
      expect(screen.contains('amount: grandTotal'), isTrue);
      expect(screen.contains('totalAmount * 1.15'), isTrue);
      expect(screen.contains('الإجمالي قبل الضريبة'), isTrue);
      expect(screen.contains('ضريبة القيمة المضافة (15%)'), isFalse,
          reason: 'الضريبة مكانها تفاصيل الفاتورة لا شاشة الاختيار');
    });

    test('الأدمن يسعّرها لكل منطقة وتُنسخ مع بقية الأسعار', () {
      expect(zones.contains('pEventWorkerCtrl'), isTrue);
      expect(zones.contains('kEventWorkerHourPriceField:'), isTrue,
          reason: 'تُكتب في مستند المنطقة عند الحفظ');
      expect(zones.contains('pEventWorkerCtrl.text =\n'
          '                                        n(src[kEventWorkerHourPriceField])'),
          isTrue,
          reason: '«نسخ الأسعار من منطقة سابقة» يجب أن يشملها');
      expect(zones.contains('pEventWorkerCtrl.dispose()'), isTrue);
    });

    test('لها بطاقة في واجهة العميل', () {
      expect(dash.contains('EventWorkersDetailsScreen'), isTrue);
      expect(dash.contains('عاملات للمناسبات'), isTrue);
    });

    test('التسعير الخادمي يعيد الحساب ولا يثق بسعر العميل', () {
      expect(pricing.contains('kind === "event_workers"'), isTrue);
      expect(pricing.contains('zone.eventWorkerHourPrice'), isTrue);
      expect(codeOnly('functions/pricing.js').contains('meta.hour_rate'),
          isFalse,
          reason: 'hour_rate يكتبه العميل — لا يُقرأ في الحساب إطلاقاً');
    });
  });

  group('مواد التنظيف في فاتورة واحدة', () {
    final home = read('lib/screens/hourly_details_screen.dart');
    final pricing = read('functions/pricing.js');
    final index = read('functions/index.js');

    test('المواد تدخل نفس الطلب لا طلب متجر منفصل', () {
      expect(home.contains("'materials': ["), isTrue);
      expect(home.contains("'product_id': p.id"), isTrue);
      expect(home.contains('_buildMaterialsSection'), isTrue);
    });

    test('سعر المواد يدخل أساس الطلب نفسه', () {
      expect(home.contains('_basePrice + _materialsTotal'), isTrue,
          reason: 'وإلا دفع العميل الباقة وحدها ووصلته المواد مجاناً');
    });

    test('الخادم يعيد تسعير المواد من products لا من سلة العميل', () {
      expect(pricing.contains('resolveMaterialsBase'), isTrue);
      expect(pricing.contains('collection("products")'), isTrue);
      expect(pricing.contains('materials_base_resolved'), isTrue);
      // منتج مفقود/بلا سعر ⇒ null ⇒ لا تحقّق (لا رفض بلا يقين، ولا قبول أعمى).
      expect(pricing.contains('if (!snap.exists) return null'), isTrue);
    });

    test('مسارا الدفع (المحفظة وميسر) يحقنان أساس المواد قبل المقارنة', () {
      // بدون الحقن يحسب الخادم سعر الباقة وحدها فيرى دفعةً «زائدة» بقيمة المواد
      // — ومع تفعيل Tier B قد تُصنَّف مخالفة.
      final injections = 'resolveMaterialsBase(db, od.service_meta)'
          .allMatches(index).length;
      expect(injections, greaterThanOrEqualTo(2),
          reason: 'payWithWallet و verifyMoyasarPayment كلاهما');
      expect(index.contains('materials_base_resolved: matBase'), isTrue);
    });

    test('نص «شامل الضريبة» القديم أُزيل من بطاقة الشمول', () {
      // صار السعر يُعرض قبل الضريبة، فالنص القديم يناقض ما تراه العميلة.
      expect(home.contains('السعر شامل الضريبة وأدوات التنظيف الأساسية'), isFalse);
      expect(home.contains('السعر قبل الضريبة ويشمل أدوات التنظيف الأساسية'), isTrue);
    });
  });
}
