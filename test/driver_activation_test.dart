import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/driver_activation.dart';

/// **تعطيلُ سائقٍ ثلاثةُ حقولٍ، وقد كُتبت واحداً في المفتاحِ الرئيسيّ.**
///
/// الخادمُ يَقرأُ `is_active` وحدَه للأهليّة (`isAssignableDriver`)، ولوحةُ
/// الويبِ تَبني الشارةَ والمفتاحَ على `is_suspended`، و`is_available` حالةُ
/// اتّصالِ السائق. فتعطيلٌ من مفتاحِ «السائقون» في تطبيقِ الإدارةِ كان يَكتبُ
/// `is_active` وحدَه: اللوحةُ تُظهرُه «متاح» بنقطةٍ خضراءَ نابضة، وزرُّها
/// يَعرضُ «إيقاف» فيَبدو أنّه لم يُعطَّل، وعدّادُ «السائقون المتاحون» يَعدُّه.
///
/// **وقد وُجد هذا وأُصلح مرّةً في موضعٍ واحدٍ من ثلاثة** — تعليقُ
/// `admin_compliance_screen` يَشرحُه بنفسِه — وبَقي الموضعُ الرئيسيُّ. فصارت
/// الحقولُ مصدراً واحداً لكلِّ جهة.

/// جدولُ الحالاتِ **المشترَكُ** مع فحصِ اللوحة — يُقرأُ من ملفِّه لا يُنسَخ.
///
/// والاقتطاعُ **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**: `indexOf('[')`
/// يَلتقطُ قوسَ **تعليقِ النوعِ** (`[boolean | null, …][]`) لا بدايةَ
/// المصفوفة — فخٌّ مسجَّلٌ في هذا المستودعِ أكثرَ من مرّة.
List<List<Object?>> _sharedCases() {
  final src =
      File('admin_panel/src/utils/driverActivation.test.ts').readAsStringSync();
  final a = src.indexOf('// ⟦CASES⟧');
  final b = src.indexOf('// ⟦/CASES⟧');
  if (a < 0 || b < 0 || b <= a) {
    throw StateError('علامتا كتلةِ الحالاتِ مفقودتانِ من فحصِ الـTS');
  }
  final block = src.substring(a, b);
  final end = block.lastIndexOf(']');
  if (end < 0) throw StateError('لا قوسَ إغلاقٍ في كتلةِ الحالات');
  var depth = 0;
  var start = -1;
  for (var i = end; i >= 0; i--) {
    if (block[i] == ']') depth++;
    if (block[i] == '[') {
      depth--;
      if (depth == 0) {
        start = i;
        break;
      }
    }
  }
  if (start < 0) throw StateError('تعذّرَ موازنةُ أقواسِ كتلةِ الحالات');
  var json = block.substring(start, end + 1);
  // الجدولُ يَحملُ تعليقاتٍ تَشرحُ كلَّ صنف، و`jsonDecode` لا تَقبلُها —
  // فتُحجَبُ **الأسطرُ الكاملةُ** وحدَها (لا `//` في أيِّ موضع: قيمةٌ نصّيّةٌ
  // فيها `https://` كانت ستُقطَع، وهو الفخُّ المسجَّلُ في حارسِ تمارا).
  json = json
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  json = json.replaceAll(RegExp(r'\bundefined\b'), 'null');
  json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
  return (jsonDecode(json) as List<dynamic>)
      .map((r) => (r as List<dynamic>).cast<Object?>())
      .toList();
}

void main() {
  String read(String p) => File(p).readAsStringSync();
  String code(String p) => read(p)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('القاعدةُ نفسُها', () {
    test('التعطيلُ يَكتبُ الثلاثةَ، والتفعيلُ لا يَزعمُ الاتّصال', () {
      expect(driverActivationFields(active: false), {
        'is_active': false,
        'is_suspended': true,
        'is_available': false,
      });
      // الاتّصالُ قرارُ السائقِ لا الأدمن — فالتفعيلُ لا يَكتبُ `is_available`.
      expect(driverActivationFields(active: true),
          {'is_active': true, 'is_suspended': false});
      expect(
          driverActivationFields(active: true).containsKey('is_available'),
          isFalse);
    });

    test('«معطَّل» أيُّ الحقلَين — نفسُ قراءةِ الخادم', () {
      expect(driverIsDisabled({'is_active': false}), isTrue);
      expect(driverIsDisabled({'is_suspended': true}), isTrue);
      expect(driverIsDisabled({'is_active': true, 'is_suspended': true}), isTrue);
      // الغيابُ نشاطٌ: المستنداتُ القديمةُ بلا الحقلَين، واعتبارُها معطَّلةً
      // يُفرِغُ الأسطولَ (نفسُ قرارِ `isActiveDriverDoc`).
      expect(driverIsDisabled(const {}), isFalse);
      expect(driverIsDisabled({'is_active': true}), isFalse);
    });

    test('والخادمُ ما زال يَقرأُ الحقلَين بهذا الشكلِ عينِه', () {
      // لو تغيّرت قراءةُ الخادمِ فهذه المرآةُ تَكذب.
      final drv = read('functions/drivers.js');
      expect(drv.contains('driverData.is_active !== false'), isTrue,
          reason: 'أهليّةُ الإسنادِ تَقرأُ is_active');
      final idx = code('functions/index.js');
      expect(
          idx.contains(
              'before.is_active !== false && before.is_suspended !== true'),
          isTrue,
          reason: 'وفكُّ الإسنادِ يَقرأُ الحقلَين — ومن هنا لزمت كتابتُهما معاً');
    });
  });

  group('والمرآتانِ متطابقتان', () {
    test('مجموعةُ الحقولِ واحدةٌ في اللغتَين', () {
      final ts = read('admin_panel/src/utils/driverActivation.ts');
      for (final f in const ['is_active', 'is_suspended', 'is_available']) {
        expect(ts.contains(f), isTrue, reason: '$f غائبٌ عن مرآةِ اللوحة');
      }
      // ونفسُ القرار: التفعيلُ بلا `is_available`.
      expect(
          ts.contains('{ is_active: true, is_suspended: false }'), isTrue,
          reason: 'التفعيلُ في اللوحةِ يَزعمُ الاتّصال');
      expect(
          ts.contains(
              '{ is_active: false, is_suspended: true, is_available: false }'),
          isTrue);
    });

    test('والقاعدةُ نفسُها سلوكاً — جدولٌ واحدٌ للغتَين', () {
      // **كان هذا ناقصاً، واختبارُ قضمٍ أثبتَه (2026-10-07):** تضييقُ قاعدةِ
      // اللوحةِ إلى `d.is_active === false` مرَّ **أخضرَ** في مجموعةِ دارت
      // و`tsc` وفحوصِ اللوحةِ جميعاً — لأنّ المرآةَ كانت مشدودةً إلى
      // **حِمْلَي الكتابةِ** وحدَهما. والمقارنةُ على الحِمْلِ لا على القدرة
      // هي العمى المسجَّلُ هنا مرّاتٍ.
      final cases = _sharedCases();
      expect(cases.length, greaterThanOrEqualTo(8),
          reason: 'انهارَ قراءةُ الجدولِ المشترَك');
      // وأصنافٌ مُسمّاةٌ لا حدٌّ عدديٌّ وحدَه: حذفُ صنفٍ لا يُكتشَفُ بالعدّ.
      expect(cases.any((c) => c[0] == null && c[1] == null && c[2] == false),
          isTrue, reason: 'غيابُ الحقلَين يُقرأُ مُفعَّلاً — قرارٌ لا سهو');
      expect(cases.any((c) => c[0] == false && c[1] == null && c[2] == true),
          isTrue, reason: 'is_active وحدَه يُعطّل');
      expect(cases.any((c) => c[0] == null && c[1] == true && c[2] == true),
          isTrue, reason: 'is_suspended وحدَه يُعطّل — وهو ما ضاعَ في القضم');
      expect(cases.any((c) => c[0] == true && c[1] == true && c[2] == true),
          isTrue, reason: 'مستندٌ متناقضٌ يُقرأُ معطَّلاً (الأحوط)');
      for (final c in cases) {
        final d = <String, Object?>{};
        if (c[0] != null) d['is_active'] = c[0];
        if (c[1] != null) d['is_suspended'] = c[1];
        expect(driverIsDisabled(d), c[2],
            reason: 'القاعدتانِ افترقتا على $d — المتوقَّع ${c[2]}');
      }
    });

    test('ولمرآةِ اللوحةِ فحصٌ على جهتِها', () {
      // مرآةٌ بلا فحصٍ على جهتِها تُترَكُ لحارسِ دارت وحدَه، وهو يَقرأُ
      // **نصّاً** لا سلوكاً — فأيُّ تغييرٍ لا يَمَسُّ النصَّ المشدودَ يَمرّ.
      expect(File('admin_panel/src/utils/driverActivation.test.ts').existsSync(),
          isTrue);
      final t =
          read('admin_panel/src/utils/driverActivation.test.ts');
      expect(RegExp(r'\bdriverIsDisabled\s*\(').hasMatch(t), isTrue,
          reason: 'الجدولُ يُقرَأُ ولا يُمرَّرُ على القاعدةِ في TS');
      expect(t.contains('driverActivationFields('), isTrue);
    });
  });

  group('وكلُّ كاتبٍ يَمرُّ بالمصدرِ الواحد', () {
    test('مفتاحُ شاشةِ السائقين — وهو الموضعُ الذي كان ناقصاً', () {
      final src = code('lib/screens/admin/admin_drivers_screen.dart');
      expect(src.contains('driverActivationFields(active: val)'), isTrue);
      expect(src.contains("update({'is_active': val})"), isFalse,
          reason: 'الكتابةُ المفردةُ عادت — وهي أصلُ العطل');
      // والشرحُ باقٍ في الخامّ، فلا يُفرّغُ التجريدُ الفحص.
      expect(read('lib/screens/admin/admin_drivers_screen.dart')
          .contains("{'is_active': val}"), isTrue,
          reason: 'شرحُ ما كان مكتوباً اختفى');
    });

    test('وشاشةُ الالتزام', () {
      final src = code('lib/screens/admin/admin_compliance_screen.dart');
      expect(src.contains('driverActivationFields(active: false)'), isTrue);
      // التعليقُ الذي سجّلَ العطلَ أوّلَ مرّةٍ يَبقى — لولاه لبدا الإصلاحُ بلا سبب.
      expect(read('lib/screens/admin/admin_compliance_screen.dart')
          .contains('لوحة الويب تبني شارة الحالة'), isTrue);
    });

    test('ولوحةُ الويب — مفتاحُها وإنشاءُ السائقِ كلاهما', () {
      final src = code('admin_panel/src/pages/Drivers.tsx');
      expect(src.contains('driverActivationFields(!nowSuspended)'), isTrue);
      expect(src.contains('is_suspended: nowSuspended, is_available:'), isFalse,
          reason: 'الكتابةُ اليدويّةُ عادت');
      // ورابعُ كاتبٍ: إنشاءُ سائقٍ جديدٍ كان يَكتبُ الزوجَ بيدِه.
      expect(src.contains('...driverActivationFields(true)'), isTrue,
          reason: 'إنشاءُ السائقِ يَكتبُ الزوجَ بيدِه');
      // و`is_available: false` تَبقى صريحةً هناك: الجديدُ لم يَتّصل بعد.
      expect(
          src.contains('...driverActivationFields(true),\n                    is_available: false,'),
          isTrue,
          reason: 'السائقُ الجديدُ يَلزمُ أن يُنشأَ غيرَ متّصل');
      // ولا بقيّةَ كتابةٍ يدويّةٍ للزوج: `is_active: true` حرفيّاً اختفت.
      expect(src.contains('is_active: true,'), isFalse,
          reason: 'كتابةٌ يدويّةٌ خامسةٌ للزوج');
    });
  });

  group('واللوحةُ تَقرأُ الحالةَ بالقاعدةِ لا بحقلٍ واحد', () {
    final drv = File('admin_panel/src/pages/Drivers.tsx').readAsStringSync();
    final dash = File('admin_panel/src/pages/Dashboard.tsx').readAsStringSync();

    test('الشارةُ والزرُّ يَقرآنِ `is_active` كذلك', () {
      expect(drv.contains('driverIsDisabled({ is_active, is_suspended })'),
          isTrue, reason: 'الشارةُ كانت على is_suspended وحدَه');
      expect(drv.contains('driverIsDisabled(driver)'), isTrue,
          reason: 'وزرُّ الإيقاف/التفعيلِ كذلك');
      // وقرارُ المفتاحِ نفسُه: «إيقاف» على معطَّلٍ أصلاً كان يُعطّلُه ثانيةً.
      expect(drv.contains('const nowSuspended = !driverIsDisabled(driver);'),
          isTrue);
    });

    test('وعدّادُ «المتاحون» لا يَعدُّ المعطَّل — بتصفيةٍ محلّيّةٍ لا بفهرس', () {
      expect(dash.contains("where('is_available', '==', true)"), isTrue,
          reason: 'الاستعلامُ يَبقى مساواةً واحدةً (لا فهرسَ مركّب)');
      expect(dash.contains('!driverIsDisabled(d.data())'), isTrue,
          reason: 'التصفيةُ المحلّيّةُ هي ما يُسقطُ المعطَّل');
      expect(dash.contains('snap.size.toString()') &&
              !dash.contains('setAvailableDrivers(snap.size'), isTrue,
          reason: 'عدّادٌ آخرُ يَستعملُ snap.size بحقٍّ، وهذا لم يَعُد');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // والمالُ: راتبُ مَن تَرَكَ العملَ كان في الميزانيةِ وفي صافي الربح
  //
  // `Payroll.tsx` كان يُحمّلُ `is_active` في كلِّ صفٍّ **ولا يَقرؤه شيء**:
  // لا شارةَ ولا ترشيح. فمَن تَرَكَ العملَ يَبقى في «إجمالي ميزانية
  // الرواتب» وفي «لم يُصرف بعد»، وزرُّ «صرف للكل» يَصرفُ له وعدّادُ
  // التأكيدِ يَضمُّه — والمحاسبُ لا يَرى الحالةَ فلا يُطبّقُ أيَّ سياسة.
  // و`Accountants.tsx` يَخصمُ راتبَه من **صافي الربح** إلى الأبد.
  //
  // وحتى لو رشَّحا لكان بحقلٍ واحد: اللوحةُ تَكتبُ `is_suspended` وتطبيقُ
  // الإدارةِ كان يَكتبُ `is_active`، فمستنداتُ الإنتاجِ تَحملُ هذا أو ذاك.
  // ══════════════════════════════════════════════════════════════════════
  group('ولا راتبَ يُجمَعُ خارجَ القاعدة', () {
    /// كلُّ صفحةٍ في اللوحةِ تَجمعُ `monthly_salary` — مُشتَقّةٌ لا مكتوبة.
    List<String> salarySummingPages() {
      final out = <String>[];
      for (final f in Directory('admin_panel/src/pages')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tsx'))) {
        final c = code(f.path);
        if (RegExp(r'monthly_salary[^\n]*\)\s*,\s*0\)').hasMatch(c) ||
            RegExp(r'reduce\(\([^)]*\)\s*=>[^;]*monthly_salary').hasMatch(c)) {
          out.add(f.path);
        }
      }
      out.sort();
      return out;
    }

    test('الصفحتانِ المعروفتانِ هما الجامعتان — وثالثةٌ تُراجَع', () {
      expect(
          salarySummingPages(),
          equals(const [
            'admin_panel/src/pages/Accountants.tsx',
            'admin_panel/src/pages/Payroll.tsx',
          ]),
          reason: 'صفحةٌ ثالثةٌ تَجمعُ الرواتب — تُراجَعُ بدلَ أن تَمرّ، '
              'فجمعٌ بلا ترشيحٍ يَضمُّ مَن تَرَكَ العمل');
    });

    test('وكلٌّ منهما يَمرُّ بـdriverIsDisabled لا بحقلٍ واحد', () {
      for (final p in salarySummingPages()) {
        final c = code(p);
        expect(c.contains("from '../utils/driverActivation'"), isTrue,
            reason: '$p لا يَستورِدُ القاعدةَ المشترَكة');
        expect(c.contains('driverIsDisabled('), isTrue,
            reason: '$p يَجمعُ الرواتبَ بلا ترشيحٍ بالقاعدة');
        // ولا ترشيحَ بحقلٍ واحدٍ بديلاً عنها
        expect(RegExp(r"filter\(\s*\(?\w+\)?\s*=>\s*\w+\.is_active\b").hasMatch(c),
            isFalse,
            reason: '$p يُرشّحُ بـis_active وحدَه — واللوحةُ تَكتبُ is_suspended');
      }
    });

    test('و«صرف للكل» على النشطينَ وحدَهم، وزرُّ الصفِّ يَبقى', () {
      final pay = code('admin_panel/src/pages/Payroll.tsx');
      expect(pay.contains("const unpaid = activeRows.filter(r => r.status === 'unpaid');"),
          isTrue,
          reason: 'الصرفُ الجماعيُّ عادَ يَضمُّ الموقوفَ بصمت');
      // وهل يُستحَقُّ راتبُ موقوفٍ قرارٌ تجاريّ: لا نَمنعُه، نَمنعُ الصمت.
      expect(pay.contains('markPaid(row)'), isTrue,
          reason: 'زرُّ الصفِّ الواحدِ هو المَخرجُ المقصود — لا يُحذَف');
      expect(pay.contains('موظف نشط'), isTrue,
          reason: 'عدّادُ التأكيدِ لا يَقولُ إنّهم النشطون');
    });

    test('والشارةُ تُظهِرُ الموقوفَ في الصفّ', () {
      final pay = code('admin_panel/src/pages/Payroll.tsx');
      expect(pay.contains('driverIsDisabled(row)'), isTrue);
      expect(pay.contains('موقوف'), isTrue,
          reason: 'صفٌّ لا يُميّزُه شيءٌ هو أصلُ العطل');
      // والحقلُ المفقودُ يُحمَّلُ فعلاً، وإلّا كانت القاعدةُ تَقرأُ undefined
      expect(pay.contains('is_suspended: data.is_suspended ?? false,'), isTrue,
          reason: 'بلا تحميلِ الحقلِ تَقرأُ القاعدةُ undefined فتَمرُّ دائماً');
    });

    test('والأرقامُ تُسمّي ما تَعُدّ', () {
      final pay = code('admin_panel/src/pages/Payroll.tsx');
      final acc = code('admin_panel/src/pages/Accountants.tsx');
      expect(pay.contains('ميزانية رواتب الكوادر النشطة'), isTrue,
          reason: 'عنوانٌ يَقولُ «إجمالي» على مجموعٍ مُرشَّحٍ يُضلّل');
      expect(pay.contains('stoppedTotal'), isTrue,
          reason: 'مجموعُ الموقوفينَ يُعرَضُ لا يُخفى — الفرقُ مُفسَّر');
      expect(acc.contains('رواتب الكوادر النشطة شهرياً'), isTrue);
      expect(acc.contains('activeDrivers.length'), isTrue,
          reason: 'متوسطُ الراتبِ يُقسَمُ على نفسِ الجمهورِ الذي جُمِع');
    });

    test('والمسحُ قرأَ صفحاتٍ فعلاً — حارسٌ عقيمٌ أسوأُ من لا حارس', () {
      final pages = Directory('admin_panel/src/pages')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tsx'))
          .length;
      expect(pages, greaterThanOrEqualTo(10),
          reason: 'تعدادُ صفحاتِ اللوحةِ انهار ($pages) — الفحوصُ أعلاه فارغة');
    });
  });

  group('بوّابةُ تطبيقِ السائقِ تَقرأُ القاعدةَ لا حقلاً واحداً', () {
    final dash = File('lib/screens/driver_dashboard.dart').readAsStringSync();
    final code = dash
        .split('\n')
        .map((l) => l.trimLeft().startsWith('//') ? '' : l)
        .join('\n');

    test('(ك) البوّابةُ تُنادي `driverIsDisabled` ولا تَقرأُ `is_active` وحدَه', () {
      // سائقٌ أوقفَته لوحةُ الويبِ بـ`is_suspended` وحدَه (ومستنداتُ
      // الإنتاجِ تَحملُ هذا أو ذاك) كان يَبقى داخلَ التطبيق.
      expect(code.contains('!driverIsDisabled(data!)'), isTrue,
          reason: 'البوّابةُ لا تُنادي القاعدة');
      expect(code.contains("data!['is_active']"), isFalse,
          reason: 'عادت القراءةُ بحقلٍ واحد — وهو العطلُ بعينِه');
      expect(code.contains("package:zyiarah/utils/driver_activation.dart"),
          isTrue, reason: 'القاعدةُ غيرُ مستورَدة');
    });

    test('(ل) وتَفشلُ مُغلَقةً على مستندٍ زال — قرارٌ قائمٌ لا يُنقَض', () {
      // `driverIsDisabled({})` تُعيدُ `false` (الغيابُ = مُفعَّل)، فشرطُ
      // `exists` منفصلٌ ولازم: مستندٌ محذوفٌ = لم يَعُد سائقاً.
      expect(RegExp(r'final isActive = exists && !driverIsDisabled\(')
              .hasMatch(code),
          isTrue,
          reason: 'شرطُ الوجودِ زال — فسائقٌ حُذِفَ مستندُه يَبقى داخلاً');
      expect(code.contains('لم يعد حسابك مسجّلاً كسائق'), isTrue);
    });

    test('(م) والخادمُ يَقرأُ العلَمَين كذلك — فالثلاثةُ قاعدةٌ واحدة', () {
      final drv = File('functions/drivers.js').readAsStringSync();
      final body = RegExp(
              r'function isActiveDriverDoc\(driverData\) \{([\s\S]*?)\n\}')
          .firstMatch(drv);
      expect(body, isNotNull, reason: 'isActiveDriverDoc اختفت');
      final flags = RegExp(r'driverData\.([a-z_]+)')
          .allMatches(body!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(flags, {'is_active', 'is_suspended'},
          reason: 'أهليّةُ الإسنادِ الخادميّةُ تَقرأُ أعلاماً أضيقَ — '
              'فسائقٌ موقوفٌ تُعادُ إليه المهامُّ بالمكنسة');
    });
  });
}
