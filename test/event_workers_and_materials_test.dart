import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارسات الميزتين اللتين طلبهما المالك (2026-08-08):
/// 1) خدمة «عاملات للمناسبات» — العميل يختار العدد واليوم والساعة.
/// 2) مواد التنظيف داخل طلب التنظيف المنزلي — **فاتورة واحدة بطلب واحد**
///    بدل طلب متجر منفصل بفاتورة وموعد ثانيين.
void main() {
  String read(String p) => File(p).readAsStringSync();

  // ملاحظة (2026-08-23): استُبدل تدفّق «العميل يُدخل العدد والساعات بحرّية»
  // بتدفّق باقات جاهزة مسعّرة مسبقاً (event_worker_packages_screen.dart يقرأ
  // من مجموعة Firestore جديدة event_worker_packages). lib/screens/
  // event_workers_details_screen.dart حُذف بالكامل وهو الملف الذي كانت هذه
  // المجموعة تقرأه — أُعيدت كتابة الاختبارات هنا لتطابق التدفّق الجديد بدل
  // الانهيار عند بناء main() بمحاولة قراءة ملف لم يعد موجوداً. functions/
  // pricing.js وحقل eventWorkerHourPrice في admin_hourly_zones_screen.dart
  // بقيا خارج النطاق تماماً كما في التصميم المعتمد (معطّلان غير محذوفين).
  group('عاملات للمناسبات (باقات جاهزة)', () {
    final screen = read('lib/screens/event_worker_packages_screen.dart');
    final zones = read('lib/screens/admin/admin_hourly_zones_screen.dart');
    final dash = read('lib/screens/client_dashboard.dart');
    final pricing = read('functions/pricing.js');

    test('الشاشة تقرأ من مجموعة الباقات الجاهزة وتمرّر contract_kind/workers للعقد', () {
      expect(screen.contains("collection('event_worker_packages')"), isTrue);
      expect(screen.contains("contractKind: 'event_workers'"), isTrue);
      expect(screen.contains('workers: planWorkers'), isTrue);
    });

    test('حقل سعر الساعة القديم في مستند المنطقة محفوظ (معطّل لا محذوف)', () {
      expect(zones.contains('kEventWorkerHourPriceField'), isTrue);
    });

    test('لها بطاقة في واجهة العميل تفتح شاشة الباقات الجديدة', () {
      expect(dash.contains('EventWorkerPackagesScreen'), isTrue);
      expect(dash.contains('عاملات للمناسبات'), isTrue);
    });

    test('مسار التسعير الخادمي القديم لعاملات المناسبات يبقى كما هو (خارج النطاق)', () {
      expect(pricing.contains('kind === "event_workers"'), isTrue);
      expect(pricing.contains('zone.eventWorkerHourPrice'), isTrue);
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
