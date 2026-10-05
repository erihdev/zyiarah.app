import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/widgets/service_meta_view.dart';

/// **مرآةٌ مُعلَنةٌ تُختبَرُ بالجدولِ نفسِه على الجهتَين.**
///
/// `zyiarahServiceMetaSummary` (هنا، «مصدرُ الحقيقة») و`metaSummary` في
/// `admin_panel/src/utils/serviceMeta.ts` يُجيبانِ السؤالَ نفسَه: سطرٌ واحدٌ
/// يُلخّصُ ما حَجزته العميلة. و`admin_meta_parity_test` كان يَفحصُ **بنيةً**
/// فقط — أنّ الأنواعَ الستّةَ مذكورةٌ في الجهتَين — ولم يُقارِنْ خَرْجَيهما
/// قطّ. فانحرفَتا في فرعٍ واحد: اللوحةُ تُلحقُ مدّةَ الباقةِ («4س») وهذا
/// الملفُّ لا يَحملها.
///
/// **والأثرُ على السائقِ لا على المرآةِ فقط:** بطاقتُه في `driver_dashboard`
/// تُبنى من هذا الملخّص، والمدّةُ لا تَبلغُه إلّا في جدولِ التفاصيل
/// («مدة الجدولة …») أو في المؤقّتِ **بعد** أن يَبدأ — فهو يُخطّطُ يومَه من
/// القائمةِ بلا طولِ المهمّة، بينما يَراه الأدمنُ على الويبِ في الصفّ نفسِه.
///
/// الجدولُ أدناه **واحدٌ** بين اللغتَين: الفحصُ الأخيرُ يَقرأُ كتلةَ الحالاتِ
/// من ملفِّ اختبارِ اللوحةِ ويُقارِنُها بهذه حرفاً بحرف، فلا تُضافُ حالةٌ
/// لجهةٍ دون الأخرى.
// ──── SUMMARY-CASES-BEGIN ────
const String _casesJson = r'''
[
  {"meta": {"kind": "ac_service", "lines": [{"label": "صيانة شباك", "count": 1}, {"label": "غسيل سبليت", "count": 2}]}, "want": "صيانة شباك ×1 • غسيل سبليت ×2"},
  {"meta": {"kind": "car_interior", "lines": [{"label": "سيدان", "count": 1}]}, "want": "سيدان ×1"},
  {"meta": {"kind": "ac_service", "lines": [{"label": "لا شيء", "count": 0}]}, "want": null},
  {"meta": {"kind": "ac_service"}, "want": null},
  {"meta": {"kind": "sofa_rug_sqm", "pieces": [{"label": "كنب 1", "billed_measure": 2.5, "uses_area": false}, {"label": "كنب 2", "billed_measure": 3, "uses_area": false}, {"label": "سجاد 1", "area_sqm": 6}]}, "want": "كنب ×2 (5.50 م.ط) • سجاد ×1 (6.00 م²)"},
  {"meta": {"kind": "store_products", "items": [{"name": "منظف", "quantity": 2}]}, "want": "منظف ×2"},
  {"meta": {"kind": "home_package", "homeLabel": "شقة متوسطة", "crewCount": 2, "durationHours": 4, "materials": [{}, {}]}, "want": "شقة متوسطة • كادران • 4س • + 2 مادة"},
  {"meta": {"kind": "home_package", "homeLabel": "فيلا", "crewCount": 1}, "want": "فيلا • كادر واحد"},
  {"meta": {"kind": "home_package", "homeLabel": "قصر", "crewCount": 3, "durationHours": 8}, "want": "قصر • 3 كوادر • 8س"},
  {"meta": {"kind": "home_package", "homeLabel": "", "crewCount": 2}, "want": null},
  {"meta": {"kind": "event_workers", "workers": 2, "event_hours": 2}, "want": "عاملتان • ساعتان"},
  {"meta": {"kind": "event_workers", "workers": 3, "event_hours": 5}, "want": "3 عاملات • 5 ساعات"},
  {"meta": {"kind": "event_workers", "workers": 1, "event_hours": 3}, "want": "عاملة واحدة • 3 ساعات"},
  {"meta": {"kind": "event_workers", "workers": 0, "event_hours": 5}, "want": null},
  {"meta": {"kind": "unknown_kind"}, "want": null},
  {"meta": {}, "want": null}
]
''';
// ──── SUMMARY-CASES-END ────

void main() {
  final cases = (jsonDecode(_casesJson) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  group('ملخّصُ تفصيلِ الخدمةِ — الجدولُ المشترك', () {
    test('الجدولُ غيرُ فارغٍ ويُغطّي الأنواعَ الستّة', () {
      expect(cases.length, greaterThanOrEqualTo(14));
      final kinds = cases
          .map((c) => (c['meta'] as Map)['kind'])
          .whereType<String>()
          .toSet();
      for (final k in const [
        'ac_service',
        'car_interior',
        'sofa_rug_sqm',
        'store_products',
        'home_package',
        'event_workers',
      ]) {
        expect(kinds, contains(k), reason: '$k ليس في الجدول');
      }
    });

    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final kind = (c['meta'] as Map)['kind'] ?? '(بلا نوع)';
      test('[$i] $kind', () {
        expect(zyiarahServiceMetaSummary(c['meta']), c['want']);
      });
    }

    test('ولا مُدخَلَ غيرَ خريطةٍ يُسقطُ الدالّة', () {
      expect(zyiarahServiceMetaSummary(null), isNull);
      expect(zyiarahServiceMetaSummary('garbage'), isNull);
      expect(zyiarahServiceMetaSummary(7), isNull);
    });
  });

  group('الجدولُ نفسُه على جهةِ اللوحة', () {
    /// يَقتطعُ ما بين العلامتَين — الكتلةُ الواحدةُ المشتركة.
    String block(String src) {
      const b = '// ──── SUMMARY-CASES-BEGIN ────';
      const e = '// ──── SUMMARY-CASES-END ────';
      final i = src.indexOf(b);
      final j = src.indexOf(e);
      expect(i, greaterThan(-1), reason: 'علامةُ البداية مفقودة');
      expect(j, greaterThan(i), reason: 'علامةُ النهاية مفقودة');
      final inner = src.substring(i + b.length, j);
      // **من الآخرِ إلى الأوّلِ بموازنةِ الأقواس.** `indexOf('[')` يَلتقطُ
      // القوسَ الذي في تعليقِ النوعِ على جهةِ TypeScript
      // (`{ meta: unknown; want: string | null }[]`) لا بدايةَ المصفوفة.
      final t = inner.lastIndexOf(']');
      expect(t, greaterThan(-1), reason: 'لا مصفوفةَ حالاتٍ بين العلامتَين');
      var depth = 0;
      var s = -1;
      for (var k = t; k >= 0; k--) {
        if (inner[k] == ']') depth++;
        if (inner[k] == '[') {
          depth--;
          if (depth == 0) {
            s = k;
            break;
          }
        }
      }
      expect(s, greaterThan(-1), reason: 'قوسُ البدايةِ المُطابقُ مفقود');
      return inner.substring(s, t + 1);
    }

    test('الحالاتُ متطابقةٌ بين اللغتَين — لا حالةَ لجهةٍ دون الأخرى', () {
      final web = File('admin_panel/src/utils/serviceMeta.test.ts')
          .readAsStringSync();
      final mine = File('test/service_meta_summary_test.dart').readAsStringSync();
      final a = jsonDecode(block(mine));
      final b = jsonDecode(block(web));
      expect(jsonEncode(b), equals(jsonEncode(a)),
          reason: 'جدولا الحالاتِ افترقا — أضِفْها للجهتَين أو احذفْها منهما');
    });

    test('ومُستهلِكو الملخّصِ ثلاثةٌ: شاشتا الإدارةِ والسائق، وصفُّ اللوحة', () {
      expect(
          File('lib/screens/admin/admin_orders_screen.dart')
              .readAsStringSync()
              .contains("zyiarahServiceMetaSummary(data['service_meta'])"),
          isTrue);
      expect(
          File('lib/screens/driver_dashboard.dart')
              .readAsStringSync()
              .contains("zyiarahServiceMetaSummary(data['service_meta'])"),
          isTrue);
      // واللوحةُ تُنادي الدالّةَ من `utils/` لا نسخةً محلّيّةً في الصفحة:
      // تصديرُ دالّةٍ من ملفِّ مُكوِّنٍ يَكسرُ fast-refresh، والأهمُّ أنّ
      // المرآةَ تُختبَرُ حيثُ تَسكن.
      final orders = File('admin_panel/src/pages/Orders.tsx').readAsStringSync();
      expect(orders.contains("import { metaSummary } from '../utils/serviceMeta.ts'"),
          isTrue);
      expect(orders.contains('const pkgSummary'), isFalse,
          reason: 'عادت النسخةُ المحلّيّةُ إلى الصفحة');
      expect(orders.contains('metaSummary(order.service_meta)'), isTrue);
    });
  });
}
