import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/catalog_number.dart';

import 'helpers/strip_comments.dart';

/// **حقلٌ رقميٌّ في محرِّرٍ إداريٍّ: الفراغُ قرارٌ، وخطأُ الكتابةِ ليس قراراً.**
///
/// كلُّ حقلٍ رقميٍّ في شاشاتِ الإدارةِ كان `tryParse(ctrl.text) ?? <افتراضي>`،
/// والحقولُ `TextField` **بلا `inputFormatters`** — فلوحةُ مفاتيحٍ عربيّةٍ
/// تُدخِلُ «٣٥٠» و`tryParse` تُعيدُ `null`، فتُخزَّنُ القيمةُ الافتراضيّةُ مع
/// «تمّ الحفظ». و**معنى الافتراضيِّ يَختلفُ بالحقل**، فالضررُ يَختلف:
///
/// * **انقلابٌ**: `max_orders_per_day` صفرٌ = «بلا سقف» (`zoneDailyCap`
///   صريحةٌ)، و`maxUses` صفرٌ = «كوبونٌ بلا حدّ» — فالحدُّ الذي يَضبطُه
///   المالكُ **يُلغى** لا يَنقُص.
/// * **اختفاءٌ**: سعرُ قطعةٍ أو كادرٍ صفرٌ = «غيرُ معروضة»، فالخدمةُ تَختفي
///   من شاشةِ العميلةِ بلا كلمة.
/// * **رقمُ مالٍ خاطئ**: راتبٌ صفرٌ يُغيّرُ ميزانيةَ الرواتبِ و«صافي الأرباح»،
///   وسعرُ منتجٍ صفرٌ يُعرَضُ «0 ر.س» ويَجعلُ السلّةَ غيرَ قابلةٍ للتسعير.
/// * **سقوطٌ إلى الافتراضيّ**: نسبةُ الذروةِ صفرٌ = «لا ذروة»، ومدّةُ باقةٍ
///   تَسقطُ إلى أربعِ ساعاتٍ فتُحجَزُ غيرُ المقصودة.
///
/// ونصفُ القطرِ ورسومُ الوعورةِ كانا مرفوضَين سلفاً في محرِّرِ المناطقِ بتعليقٍ
/// يَقولُ «لا قصّ صامت لخطأ كتابة» — فهذا **إكمالُ قرارٍ قائمٍ** لا قرارٌ جديد.
String _code(String path) => stripComments(File(path).readAsStringSync());

/// **المواضعُ المسموحُ لها بالابتلاع، ولكلٍّ سببُه.** المفتاحُ
/// `<ملف>#<ترتيب>` لا رقمُ سطرٍ (كـ`stream_timeout_sweep_test`)، فتعديلٌ أعلى
/// الملفِّ لا يُسقِطُ الحارسَ زوراً.
const Map<String, String> kAllowedSwallows = {
  // نصفُ القطرِ في **العرضِ** لا في الكتابة: معاينةُ الخريطةِ ومُنتقي الموقعِ
  // يُقرآنِ الحقلَ وهو نصفُ مكتوب، ومسارُ الحفظِ يَرفُضُ غيرَ الصالحِ صراحةً
  // (يَشدُّه الفحصُ «هـ»).
  'lib/screens/admin/admin_hourly_zones_screen.dart#0':
      'معاينةُ الخريطةِ — عرضٌ لا كتابة',
  'lib/screens/admin/admin_hourly_zones_screen.dart#1':
      'مُنتقي الموقعِ — عرضٌ لا كتابة',
  // تحذيرُ انقلابِ سعرِ الكوادرِ يَقرأُ الحقولَ **حيّاً** أثناء الكتابة،
  // فقيمةٌ نصفُ مكتوبةٍ تُقرأُ صفراً عمداً: تنبيهٌ لا كتابة.
  'lib/screens/admin/admin_hourly_zones_screen.dart#2':
      'تحذيرُ انقلابِ السعرِ — قراءةٌ حيّةٌ لتنبيهٍ لا لكتابة',
};

/// **مواضعُ الابتلاع: `tryParse(<حقلُ إدخال>)` يَتبعُها `??`.**
///
/// بموازنةِ الأقواسِ لا بنمطٍ — فخُّ الحدِّ المسجَّلُ هنا ستَّ مرّات: وسيطُ
/// `tryParse` قد يَمتدُّ أسطُراً (`pkgPriceCtrls[type]![n]!\n.text\n.trim()`)
/// فـ`[^)]*` لا يَبلغُه، و`\s*` لا يَكفي لأنّ الأسطرَ تَقطعُ المُعرِّفَ نفسَه.
///
/// والشرطانِ معاً هما ما يُميّزُ العطلَ: **حقلُ إدخالٍ** (الوسيطُ يَحملُ
/// `.text`) **وقيمةٌ افتراضيّةٌ** (`??` بعدَ الغلق). فـ`tryParse` على قيمةٍ من
/// Firestore قراءةُ مستندٍ قائمٍ لا حقلُ إدخال، و`tryParse` بلا `??` تَرُدُّ
/// `null` فيَرفُضُها الكاتبُ صراحةً — وكلاهما خارجَ النطاقِ بقصد.
List<String> _swallowSites(String code) {
  final out = <String>[];
  final re = RegExp(r'(?:double|int|num)\.tryParse\(');
  for (final m in re.allMatches(code)) {
    var depth = 0;
    var j = m.end - 1; // عند `(`
    var close = -1;
    for (; j < code.length; j++) {
      if (code[j] == '(') depth++;
      if (code[j] == ')') {
        depth--;
        if (depth == 0) {
          close = j;
          break;
        }
      }
    }
    if (close < 0) continue;
    final arg = code.substring(m.end, close);
    if (!arg.contains('.text')) continue;
    var k = close + 1;
    while (k < code.length && (code[k] == ' ' || code[k] == '\n')) {
      k++;
    }
    if (!code.startsWith('??', k)) continue;
    out.add(arg.trim().replaceAll(RegExp(r'\s+'), ' '));
  }
  return out;
}

void main() {
  group('الحقولُ الرقميّةُ في محرِّراتِ الإدارة', () {
    test('(أ) القاعدةُ: الفراغُ يَمُرُّ وغيرُ الصالحِ يُرفَض', () {
      expect(optionalNum('', whenEmpty: 7), 7);
      expect(optionalNum('   ', whenEmpty: 7), 7);
      expect(optionalNum('0', whenEmpty: 7), 0);
      expect(optionalNum('٣٥٠', whenEmpty: 7), 350);
      expect(optionalNum('abc', whenEmpty: 7), isNull);
      expect(optionalNum('-5', whenEmpty: 7), isNull);
      expect(optionalInt('', whenEmpty: 4), 4);
      expect(optionalInt('٨', whenEmpty: 4), 8);
      expect(optionalInt('2.5', whenEmpty: 4), isNull);
      expect(optionalInt('abc', whenEmpty: 4), isNull);
    });

    test('(ب) أوّلُ حقلٍ مُخطِئٍ يُسمّى بالاسمِ لا برسالةٍ عامّة', () {
      expect(firstInvalidNumber({'أ': '10', 'ب': '', 'ج': '٢٠'}), isNull);
      expect(firstInvalidNumber({'أ': '10', 'ب': 'س', 'ج': 'ص'}), 'ب');
      expect(firstInvalidNumber({'أ': '-1'}), 'أ');
    });

    test('(ج) لا ابتلاعَ باقٍ في شاشاتِ الإدارة — نطاقٌ مُشتَقّ', () {
      final found = <String, String>{};
      final files = Directory('lib/screens/admin')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(15),
          reason: 'المسحُ لم يَقرأ شاشاتِ الإدارةِ — نطاقٌ منهار');
      for (final f in files) {
        final code = _code(f.path);
        var ord = 0;
        for (final m in _swallowSites(code)) {
          found['${f.path}#$ord'] = m;
          ord++;
        }
      }
      expect(found.keys.toSet(), kAllowedSwallows.keys.toSet(),
          reason: 'ابتلاعٌ جديدٌ لحقلٍ رقميٍّ إداريّ، أو موضعٌ مسموحٌ زالَ — '
              'يُراجَعُ بسببٍ مكتوبٍ بدلَ أن يَمرّ');
    });

    test('(د) الحقولُ الحسّاسةُ تَمُرُّ بالقاعدةِ ولا تُبتلَع', () {
      final sites = <String, List<String>>{
        'lib/screens/admin/admin_coupons_screen.dart': [
          r'optionalInt\(\s*maxUsesCtrl\.text',
          r'positiveNum\(valueCtrl\.text\)',
        ],
        'lib/screens/admin/admin_hourly_zones_screen.dart': [
          r'optionalInt\(maxPerDayCtrl\.text',
          r'optionalNum\(pSofaSqmCtrl\.text',
          r'optionalNum\(pkgPriceCtrls\[type\]!\[n\]!\.text',
          r'optionalInt\(pkgDurCtrls\[type\]!\.text',
          r'numericFieldsError\(\)',
        ],
        'lib/screens/admin/admin_drivers_screen.dart': [
          r'optionalNum\(salaryCtrl\.text',
        ],
        'lib/screens/admin/admin_settings_screen.dart': [
          r'optionalNum\(_surgePercentCtrl\.text',
        ],
        'lib/screens/admin/admin_store_screen.dart': [
          r'positiveNum\(priceCtrl\.text\)',
        ],
      };
      sites.forEach((path, pats) {
        final code = _code(path);
        for (final p in pats) {
          expect(RegExp(p).hasMatch(code), isTrue,
              reason: '$path: «$p» غائبٌ — الحقلُ لا يَمُرُّ بالقاعدة');
        }
      });
      // بوّابةُ محرِّرِ المناطقِ تُنادى في **المسارَين** (حفظُ المنطقةِ ونسخُ
      // الأسعارِ إلى مناطقَ) — بوّابةٌ في أحدِهما تَترُكُ الآخرَ مفتوحاً.
      final zone = _code('lib/screens/admin/admin_hourly_zones_screen.dart');
      expect(RegExp(r'numericFieldsError\(\)').allMatches(zone).length,
          greaterThanOrEqualTo(3),
          reason: 'البوّابةُ تُعرَّفُ وتُنادى مرّتَين على الأقلّ (المسارانِ)');
    });

    test('(هـ) شواهدُ التعليلِ قائمةٌ في الخادمِ والمستهلِكين', () {
      expect(_code('functions/capacity.js'),
          contains('Number.isFinite(n) && n > 0 ? Math.floor(n) : null'),
          reason: 'معنى صفرِ `max_orders_per_day` تغيّرَ — يُراجَعُ التعليل');
      expect(_code('functions/coupons.js'),
          contains('if (maxUses > 0 && uses >= maxUses)'),
          reason: 'معنى صفرِ `maxUses` تغيّرَ');
      expect(_code('functions/pricing.js'),
          contains('if (!price || isNaN(price) || price <= 0) return null;'),
          reason: 'سعرُ منتجٍ صفرٌ لم يَعُد يُعدِمُ تسعيرَ السلّة');
      // القرارُ المرجعيُّ في الملفِّ نفسِه: نصفُ القطرِ ورسومُ الوعورةِ
      // مرفوضانِ صراحةً — وهذا الإصلاحُ إكمالٌ له.
      final zoneRaw =
          File('lib/screens/admin/admin_hourly_zones_screen.dart')
              .readAsStringSync();
      expect(zoneRaw, contains('لا قصّ صامت لخطأ كتابة'),
          reason: 'التعليقُ الذي يَحملُ القرارَ المرجعيَّ زالَ');
      expect(_code('lib/screens/admin/admin_hourly_zones_screen.dart'),
          contains('radiusVal == null || radiusVal < 1 || radiusVal > 100'),
          reason: 'رفضُ نصفِ القطرِ زالَ — فالاتّساقُ المُدَّعى غيرُ قائم');
    });

    test('(و) حقولُ الرقمِ ما زالت بلا مُنسِّقاتِ إدخالٍ', () {
      // التطبيعُ هو ما يُغني عنها ويَقبلُ «٣٥٠»؛ فلو أُضيفَ مُنسِّقٌ حاصرٌ
      // فالقرارُ يُراجَعُ لا يُكرَّر.
      for (final f in Directory('lib/screens/admin')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(_code(f.path).contains('inputFormatters'), isFalse,
            reason: '${f.path}: أُضيفَ مُنسِّقُ إدخالٍ — يُراجَعُ التطبيعُ معه');
      }
    });
  });
}
