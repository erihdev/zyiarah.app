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
}
