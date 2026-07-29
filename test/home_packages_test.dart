import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/home_packages.dart';

/// نظام «باقات السكن» (بديل الساعات): يحرس هذا الملف تطابق المخطط حرفياً عبر
/// الطبقات الأربع — شاشة العميل، أدمن التطبيق، لوحة الويب، والتسعير الخادمي —
/// فأي انحراف في اسم حقلٍ يكسر البيع أو يجعل التحقق الخادمي يرفض طلبات شرعية.
void main() {
  group('منطق الباقات (zoneHomePackages)', () {
    final zone = {
      'packages': {
        'small': {
          'desc': '4 غرف + دورتا مياه',
          'durationHours': 4,
          'crews': {
            '1': {'price': 200, 'enabled': true},
            '2': {'price': 310, 'enabled': true},
            '3': {'price': 400, 'enabled': false}, // معطَّل من اللوحة
            '4': {'price': 0, 'enabled': true}, // صفر = غير مسعَّر
          },
        },
        'villa': {
          'durationHours': 8,
          'crews': {
            '2': {'price': 380, 'enabled': true},
          },
        },
        // medium غائب كلياً → غير قابل للبيع
      },
    };

    test('المفعَّل والمسعَّر فقط يُعرض — المعطَّل والصفري يُسقطان', () {
      final pkgs = zoneHomePackages(zone);
      final small = pkgs.firstWhere((p) => p.type == 'small');
      expect(small.options.map((o) => o.crews).toList(), [1, 2]);
      expect(small.options.first.basePrice, 200);
      expect(small.sellable, isTrue);
    });

    test('نوع غائب من المنطقة = غير قابل للبيع (لا يُعرض ولا يُباع)', () {
      final pkgs = zoneHomePackages(zone);
      final medium = pkgs.firstWhere((p) => p.type == 'medium');
      expect(medium.sellable, isFalse);
      expect(medium.options, isEmpty);
    });

    test('المدة والوصف يسقطان على الافتراضي عند الغياب', () {
      final pkgs = zoneHomePackages(zone);
      final villa = pkgs.firstWhere((p) => p.type == 'villa');
      expect(villa.durationHours, 8);
      expect(villa.desc, kHomeTypeDefaultDesc['villa']);
      final medium = pkgs.firstWhere((p) => p.type == 'medium');
      expect(medium.durationHours, kHomeTypeDefaultDuration['medium']);
    });

    test('السعر المعروض = الأساس × 1.15 (شامل الضريبة) بتقريب هللتين', () {
      expect(const CrewOption(2, 310).grossPrice, 356.50);
      expect(const CrewOption(1, 200).grossPrice, 230.00);
    });

    test('تسمية الكوادر بعربية سليمة', () {
      expect(crewLabel(1), 'كادر واحد');
      expect(crewLabel(2), 'كادران');
      expect(crewLabel(3), '3 كوادر');
    });

    test('منطقة بلا packages إطلاقاً = لا شيء قابل للبيع (لا انهيار)', () {
      final pkgs = zoneHomePackages({'name': 'x'});
      expect(pkgs.where((p) => p.sellable), isEmpty);
    });
  });

  group('تطابق المخطط عبر الطبقات (فحص مصدري)', () {
    test('شاشة العميل: باقات لا ساعات، وتُرسل meta الباقة وتجدول بمدتها', () {
      final s = File('lib/screens/hourly_details_screen.dart').readAsStringSync();
      expect(s.contains('zoneHomePackages'), isTrue);
      expect(s.contains("'kind': 'home_package'"), isTrue);
      expect(s.contains("'homeType'"), isTrue);
      expect(s.contains("'crewCount'"), isTrue);
      // (قرار المالك) اليوم فقط — لا اختيار وقت بدء، والموعد يُرسى على ساعة
      // فتح المنطقة. مدة الباقة تُمرَّر للجدولة الخادمية (hours: _durationHours).
      expect(s.contains('hours: _durationHours'), isTrue);
      // إتاحة اليوم = سعة يومية + سائق متاح لمدة الباقة، والموعد يُرسى على
      // أول فترة فيها سائق حرّ فعلاً (قرار المالك — لا وقت يختاره العميل).
      expect(s.contains('_firstFeasibleStart(_selectedDate)'), isTrue,
          reason: 'الموعد يُرسى على أول ساعة فيها سائق متاح لمدة الباقة');
      expect(s.contains('_dateUnavailable'), isTrue,
          reason: 'اليوم يُقفَل إن امتلأت السعة أو غاب سائقٌ متاح');
      expect(s.contains('وقت البدء:'), isFalse,
          reason: 'اختيار وقت البدء أُلغي — العميل يحدد اليوم فقط');
      expect(s.contains('_selectedStartHour'), isFalse);
      expect(s.contains('اختر عدد الساعات'), isFalse,
          reason: 'نظام الساعات أُلغي — الاختيار صار نوع السكن وعدد الكوادر');
      expect(s.contains('allowed_hours'), isFalse);
      // مراقبة التنقّل: إعادة تحديد صامتة دورية وعند العودة للتطبيق.
      expect(s.contains('silent: true'), isTrue);
      expect(s.contains('didChangeAppLifecycleState'), isTrue);
    });

    test('أدمن التطبيق يكتب packages بنفس مفاتيح القارئ', () {
      final s = File('lib/screens/admin/admin_hourly_zones_screen.dart')
          .readAsStringSync();
      expect(s.contains("'packages': buildPackages()"), isTrue);
      expect(s.contains("'durationHours'"), isTrue);
      expect(s.contains("'enabled': pkgEnabled[type]![n] == true"), isTrue);
      // النسخ للمناطق يشمل الباقات (أسعارها وتفعيلاتها).
      // حتى نهاية خريطة النسخ (قوس الإغلاق «});») — نافذة ثابتة كانت أقصر من الكتلة.
      final applyIdx = s.indexOf('_applyPricesToZones(targets');
      expect(applyIdx, greaterThan(-1));
      final applyEnd = s.indexOf('});', applyIdx);
      expect(
          s.substring(applyIdx, applyEnd > applyIdx ? applyEnd : applyIdx + 3000)
              .contains("'packages'"),
          isTrue,
          reason: 'نسخ الأسعار بين المناطق يجب أن يحمل الباقات أيضاً');
    });

    test('لوحة الويب تكتب نفس المخطط حرفياً', () {
      final s =
          File('admin_panel/src/pages/Settings.tsx').readAsStringSync();
      expect(s.contains("{ key: 'small'"), isTrue);
      expect(s.contains("{ key: 'medium'"), isTrue);
      expect(s.contains("{ key: 'villa'"), isTrue);
      // المدة مثبّتة 1..12 (خطأ إدخال سالب كان يكسر رياضيات السعة والتعارض).
      expect(
          s.contains(
              'durationHours: Math.min(12, Math.max(1, parseInt(p.dur)'),
          isTrue);
      expect(s.contains('enabled: !!c.enabled'), isTrue);
    });

    test('التسعير الخادمي يقرأ نفس المسار: packages[type].crews[count]', () {
      final s = File('functions/pricing.js').readAsStringSync();
      expect(s.contains('kind === "home_package"'), isTrue);
      expect(s.contains('zone.packages'), isTrue);
      expect(s.contains('crews[String(meta.crewCount)]'), isTrue);
      expect(s.contains('opt.enabled !== true'), isTrue,
          reason: 'خيارٌ عطّله الأدمن لمنطقته يجب ألا يقبل الخادم سعره');
    });

    test('عارض التفاصيل يعرف home_package (قوائم الإدارة والسائق)', () {
      final s = File('lib/widgets/service_meta_view.dart').readAsStringSync();
      expect(s.contains("'home_package'"), isTrue);
      expect(s.contains('homeLabel'), isTrue);
    });
  });
}
