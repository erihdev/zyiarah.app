// حارس: المكيفات طلب مباشر مسعّر، بمسار واحد فقط.
//
// كانت بلاطة «صيانة وغسيل المكيفات» تفتح شاشة طلب عرض سعر تُنشئ maintenance_requests
// بـ amount:0.0 و status:'under_review' — العميلة ترسل، تنتظر الإدارة لتسعّر، ثم تدفع.
// طلب العميل صريح: الإدارة تسعّر مسبقاً، والعميلة تختار النوع والعدد وتدفع فوراً
// ويُسنَد السائق تلقائياً.
//
// والأهم: **مسار واحد للمكيفات**. إبقاء الخيارين (مسعّر + عرض سعر) هو تكرار المرض
// الذي أنتج نظامَي تسعير للكنب.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/ac_line.dart';
import 'package:zyiarah/widgets/service_meta_view.dart';

void main() {
  _metaGuards();
  group('أسماء حقول الأسعار تطابق شاشة نطاقات التغطية حرفياً', () {
    // اختلاف حرف واحد = قراءة حقل غير موجود = سعر صفر = خدمة تبدو معطّلة بلا سبب.
    test('صيانة شباك', () {
      expect(acPriceField(AcJob.maintenance, AcUnitType.window), 'acMaintWindowPrice');
    });
    test('صيانة سبليت', () {
      expect(acPriceField(AcJob.maintenance, AcUnitType.split), 'acMaintSplitPrice');
    });
    test('غسيل شباك', () {
      expect(acPriceField(AcJob.wash, AcUnitType.window), 'acWashWindowPrice');
    });
    test('غسيل سبليت', () {
      expect(acPriceField(AcJob.wash, AcUnitType.split), 'acWashSplitPrice');
    });

    test('الحقول الأربعة موجودة فعلاً في شاشة الإدارة', () {
      final admin =
          File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
      for (final job in AcJob.values) {
        for (final type in AcUnitType.values) {
          final f = acPriceField(job, type);
          expect(admin.contains("'$f'"), isTrue,
              reason: '$f يُقرأ في تطبيق العميلة ولا تكتبه الإدارة ⇒ صفر دائماً');
        }
      }
    });
  });

  group('الحساب: سعر لكل مكيف × العدد', () {
    test('بند واحد', () {
      const l = AcLine(job: AcJob.maintenance, type: AcUnitType.split, count: 3);
      expect(l.lineTotal(150), 450.0);
    });

    test('أنواع وأعداد مختلفة في طلب واحد', () {
      const lines = [
        AcLine(job: AcJob.maintenance, type: AcUnitType.window, count: 2), // 2×100
        AcLine(job: AcJob.maintenance, type: AcUnitType.split, count: 1),  // 1×150
        AcLine(job: AcJob.wash, type: AcUnitType.window, count: 3),        // 3×80
      ];
      const prices = {
        'acMaintWindowPrice': 100.0,
        'acMaintSplitPrice': 150.0,
        'acWashWindowPrice': 80.0,
        'acWashSplitPrice': 120.0,
      };
      final total = lines.fold<double>(
          0, (acc, l) => acc + l.lineTotal(prices[acPriceField(l.job, l.type)]!));
      expect(total, 590.0);
      expect(lines.fold<int>(0, (a, l) => a + l.count), 6);
    });

    test('toMap يحمل ما يحتاجه السائق والإدارة', () {
      const l = AcLine(job: AcJob.wash, type: AcUnitType.split, count: 2);
      final m = l.toMap(120);
      expect(m['job'], 'wash');
      expect(m['type'], 'split');
      expect(m['count'], 2);
      expect(m['unit_price'], 120);
      expect(m['line_total'], 240.0);
    });
  });

  group('المدة: ساعة لكل مكيف', () {
    int duration(int units) => units.clamp(2, 8);
    test('مكيف واحد ⇒ الحد الأدنى ساعتان', () => expect(duration(1), 2));
    test('5 مكيفات ⇒ 5 ساعات', () => expect(duration(5), 5));
    test('20 مكيفاً ⇒ تُسقَّف بـ 8', () => expect(duration(20), 8));
    test('السقف يُبقي خانات بدء متاحة (8→22)', () {
      expect(22 - duration(20), greaterThan(8));
    });
  });

  group('المصدر: مسار واحد للمكيفات، مباشر ومسعّر', () {
    test('البلاطة تفتح الشاشة المباشرة لا شاشة عرض السعر', () {
      final dash = File('lib/screens/client_dashboard.dart').readAsStringSync();
      final i = dash.indexOf('صيانة وغسيل المكيفات');
      expect(i, greaterThan(-1), reason: 'بلاطة المكيفات اختفت — حدِّث الحارس');
      final card = dash.substring(i, i + 700);
      expect(card.contains('AcServiceDetailsScreen'), isTrue);
      expect(card.contains('ZyiarahMaintenanceRequestScreen'), isFalse,
          reason: 'المكيفات لم تعد تنتظر تسعير الإدارة');
    });

    test('لا مسار ثانٍ للمكيفات — شاشة عرض السعر لم تعد موجودة أصلاً', () {
      // كان هذا الحارس يتحقّق أن المكيفات خرجت من قائمة خدمات شاشة عرض السعر.
      // ثم حُذف مسار عرض السعر بالكامل بقرار المالك (لم يُنشأ له طلب أجهزة منزلية
      // واحد قط)، فصار غياب الملف ضمانةً أقوى من غياب سطر داخله.
      expect(File('lib/screens/maintenance_request_screen.dart').existsSync(), isFalse,
          reason: 'شاشة عرض السعر عادت — مساران للمكيفات هو المرض نفسه');
    });

    test('الطلب مباشر: hours + serviceDate + service_meta', () {
      final s = File('lib/screens/ac_service_details_screen.dart').readAsStringSync();
      expect(s.contains('hours: _durationHours'), isTrue,
          reason: 'بدون hours لا فحص سعة ولا إسناد تلقائي');
      expect(s.contains('serviceDate: _selectedSlot'), isTrue);
      expect(s.contains('serviceMeta: meta'), isTrue);
    });

    test('بلا سعر ⇒ بلا بيع (لا قيمة افتراضية عند غياب الحقل)', () {
      final s = File('lib/screens/ac_service_details_screen.dart').readAsStringSync();
      expect(RegExp(r'\?\?\s*kDefaultAc').hasMatch(s), isFalse,
          reason: 'قيمة افتراضية عند الغياب = بيع بسعر لم تعتمده الإدارة لهذه المنطقة');
      expect(s.contains('?? 0'), isTrue);
    });

    test('الأسعار مرئية قبل أي لمسة — شبكة مباشرة لا بنود تُضاف', () {
      // ملاحظة المالك («غيّر هذه الطريقة»): نمط «إضافة مكيف» ثم اختيار نوعه
      // بتبديلات كان يُخفي الأسعار حتى يُقلَّب بينها. الآن كل تركيبة مسعّرة صفٌّ
      // ظاهر بسعره وعدّاده من البداية.
      final s = File('lib/screens/ac_service_details_screen.dart').readAsStringSync();
      expect(s.contains('إضافة مكيف'), isFalse,
          reason: 'لا زرّ إضافة — الأنواع كلها معروضة سلفاً');
      expect(s.contains('ر.س للمكيف الواحد'), isTrue,
          reason: 'سعر كل تركيبة ظاهر قبل اختيارها');
      expect(s.contains('_comboRow'), isTrue);
      expect(s.contains('final Map<String, int> _counts'), isTrue,
          reason: 'عدّاد لكل تركيبة بدل قائمة بنود تُدار يدوياً');
    });

    test('الشاشة تستعمل منتقي الموعد المشترك لا نسخة ثانية منه', () {
      final s = File('lib/screens/ac_service_details_screen.dart').readAsStringSync();
      expect(s.contains('ZyiarahBookingSlotPicker'), isTrue);
      expect(s.contains('getHourlyAvailability'), isFalse,
          reason: 'استنساخ منطق الإتاحة في كل شاشة هو ما أنتج تناقض الأخضر/الرفض');
    });
  });
}

// ملحق: service_meta لا يجوز أن يبقى بلا قارئ.
// كتابة بيانات لا يقرؤها أحد هي المرض نفسه الذي أنتج حقول تسعير تكتبها الإدارة ولا
// تصل العميلة. إن كُتب التفصيل فيجب أن يراه من يحتاجه: الإدارة (للتدقيق) والسائق
// (ليعرف ما يحمل).
void _metaGuards() {
  group('الملخّص المختصر لبطاقات القوائم', () {
    // كانت قوائم الإدارة تعرض اسم الخدمة والمبلغ فقط — نوع المكيف وعدد الوحدات
    // خلف نقرة تفاصيل لكل طلب (ملاحظة المالك: «أضف خانات مثل نوع المكيف وكم وحدة»).
    test('مكيفات: النوع والعدد في سطر واحد', () {
      final meta = {
        'kind': 'ac_service',
        'lines': [
          {'label': 'صيانة شباك', 'count': 1},
          {'label': 'غسيل سبليت', 'count': 2},
        ],
      };
      expect(zyiarahServiceMetaSummary(meta), 'صيانة شباك ×1 • غسيل سبليت ×2');
    });

    test('كنب وسجاد: عدد القطع ومساحتها مجمّعة بالنوع', () {
      final meta = {
        'kind': 'sofa_rug_sqm',
        'pieces': [
          {'label': 'كنب 1', 'area_sqm': 3.0},
          {'label': 'كنب 2', 'area_sqm': 1.5},
          {'label': 'سجاد 1', 'area_sqm': 6.0},
        ],
      };
      expect(zyiarahServiceMetaSummary(meta),
          'كنب ×2 (4.50 م²) • سجاد ×1 (6.00 م²)');
    });

    test('طلب قديم بلا service_meta ⇒ null فلا يُرسم السطر', () {
      expect(zyiarahServiceMetaSummary(null), isNull);
      expect(zyiarahServiceMetaSummary('garbage'), isNull);
      expect(zyiarahServiceMetaSummary({'kind': 'unknown'}), isNull);
      expect(zyiarahServiceMetaSummary({'kind': 'ac_service'}), isNull);
    });

    test('قوائم الإدارة تعرض الملخّص فعلاً (لا دالة بلا قارئ)', () {
      for (final p in [
        'lib/screens/admin/admin_orders_screen.dart',
        'lib/screens/admin/admin_approval_screen.dart',
      ]) {
        expect(File(p).readAsStringSync().contains('zyiarahServiceMetaSummary'),
            isTrue, reason: '$p — الملخّص يُعرض في البطاقة لا خلف نقرة');
      }
    });
  });


  group('service_meta مقروء لا مكتوب فقط', () {
    test('الإدارة تعرض التفصيل', () {
      final s = File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();
      expect(s.contains('ZyiarahServiceMetaView'), isTrue,
          reason: 'الإدارة تحتاجه لتدقيق المبلغ إن اعترضت العميلة');
      expect(s.contains("data['service_meta']"), isTrue);
    });

    test('السائق يعرض التفصيل', () {
      final s = File('lib/screens/driver_dashboard.dart').readAsStringSync();
      expect(s.contains('ZyiarahServiceMetaView'), isTrue,
          reason: 'السائق يصل ولا يعرف كم قطعة/مكيفاً يخدم');
      expect(s.contains("data['service_meta']"), isTrue);
    });

    test('العرض يحتمل الطلبات القديمة والبيانات التالفة', () {
      final s = File('lib/widgets/service_meta_view.dart').readAsStringSync();
      expect(s.contains('if (m is! Map) return const SizedBox.shrink()'), isTrue,
          reason: 'الطلبات قبل هذه الميزة بلا service_meta — يجب ألا تُسقط الشاشة');
    });
  });
}
