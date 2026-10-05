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
}
