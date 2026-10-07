import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **بياناتُ البائعِ على كلِّ فاتورةٍ ضريبيّةٍ كانت تُقرأُ من مستندٍ لا
/// يَكتبُه شيء.**
///
/// `ZatcaService` كان يَقرأُ `system_configs/zatca_settings` — **صفرُ كاتبٍ في
/// المستودعِ كلِّه** — ومحرّرُ الإعداداتِ في تطبيقِ الإدارةِ يَكتبُ
/// `merchant_name` و`vat_number` في `system_configs/main_settings`. فما
/// يَحفظُه المالكُ لا يَقرؤه أحد: الاسمُ والرقمُ الضريبيُّ المطبوعانِ على
/// الفاتورةِ — وداخلَ رمزِ QR منها (Tag 1 و Tag 2) — ثابتانِ في الشفرةِ لا
/// يُغيّرُهما أيُّ سطحٍ إداريّ، والشاشةُ تَعرضُهما حقلَين قابلَين للحفظ.
/// وهي عائلةُ مفاتيحِ الإصدارِ بعينِها، واقعةً على وثيقةِ ضريبة.
///
/// و`cr_number` كان **بلا محرّرٍ إطلاقاً** وهو مطبوعٌ على البطاقةِ
/// كـ«السجل التجاري (CR)».
///
/// اليومَ الافتراضاتُ مطابقةٌ للواقعِ فلا فاتورةَ خاطئةٌ بعد — والعطلُ يَصيرُ
/// حيّاً لحظةَ أن يُصحّحَ المالكُ اسماً أو رقماً. فهو كامنٌ لا حيّ، ويُقالُ
/// كذلك.
String _read(String p) => File(p).readAsStringSync();

String _code(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('///') || t.startsWith('*'))
          ? ''
          : l;
    })
    .join('\n');

/// مجموعةُ مفاتيحِ البائعِ التي يُقرأُها/يَكتبُها الطرفان.
Set<String> _keysIn(String code, RegExp re) =>
    re.allMatches(code).map((m) => m.group(1)!).toSet();

void main() {
  final svc = _read('lib/services/zatca_service.dart');
  final ed = _read('lib/screens/admin/admin_settings_screen.dart');

  group('بياناتُ البائعِ تُقرأُ من حيث تُكتَب', () {
    test('(أ) المستندُ الأوّلُ هو ما يَكتبُه المحرّر', () {
      final c = _code(svc);
      expect(c, contains("configDocs = ['main_settings', 'zatca_settings']"),
          reason: 'الترتيبُ هو الإصلاح: الكاتبُ الحيُّ أوّلاً');
      // والمحرّرُ يَكتبُ في المستندِ نفسِه.
      expect(_code(ed), contains("doc('main_settings')"));
      // مقابلةُ الخامّ: الشرحُ ما زال يَذكرُ المستندَ القديم.
      expect(svc.contains('zatca_settings'), isTrue);
    });

    test('(ب) مجموعةُ المفاتيحِ المكتوبةِ = المقروءة — لا اسمٌ ينفرد', () {
      // كـ`amounts.test.js` و`app_update_keys_test`: المقارنةُ على
      // **المجموعةِ كلِّها** فمفتاحٌ سادسٌ على جهةٍ يَسقطُ بدلَ أن يَصمتَ
      // سنةً كاملة.
      final read = _keysIn(_code(svc),
          RegExp(r"d\['(merchant_name|vat_number|cr_number)'\]"));
      final written = _keysIn(_code(ed),
          RegExp(r"'(merchant_name|vat_number|cr_number)':"));
      expect(read, {'merchant_name', 'vat_number', 'cr_number'});
      expect(written, read,
          reason: 'حقلٌ يُقرأُ ولا يُكتَبُ = ثابتٌ في الشفرةِ على وثيقةِ ضريبة؛ '
              'وحقلٌ يُكتَبُ ولا يُقرأُ = حفظٌ «ناجحٌ» بلا أثر');
      // ويُقرآنِ عند التحميلِ في المحرّرِ كذلك، وإلّا عُرِضَ الافتراضُ فوقَ
      // قيمةٍ محفوظةٍ ثمّ أُعيدت كتابتُه عليها.
      final loaded = _keysIn(_code(ed),
          RegExp(r"data\['(merchant_name|vat_number|cr_number)'\]"));
      expect(loaded, read);
    });

    test('(ج) والسجلُّ التجاريُّ له حقلٌ ظاهرٌ ويُتلَف', () {
      final c = _code(ed);
      expect(c, contains('_crNumberCtrl'));
      expect(c, contains('السجل التجاري (CR)'));
      expect(c, contains('_crNumberCtrl.dispose()'));
    });

    test('(د) التحميلُ يَجري عند الإقلاعِ قبلَ أيِّ فاتورة', () {
      // النداءُ كان في موضعَين فقط، فموضعانِ يَبنيانِ رمزَ QR بلا تحميلٍ —
      // سجلُّ الفواتيرِ الإداريُّ و`InvoiceView.qrData()` — فيُمكنُ أن
      // يَحملَ رمزٌ الافتراضاتِ بينما الـPDF يَحملُ المحفوظة: فاتورةٌ
      // واحدةٌ برمزَين، وهو ما وُجدت `invoiceQrFor` لسدِّه.
      final m = _code(_read('lib/main.dart'));
      final at = m.indexOf('ZatcaService.ensureConfigLoaded()');
      expect(at, greaterThan(-1));
      // **آخرُ** `runApp` لا أوّلُها: منذ 2026-10-07 في `main` مَخرجٌ مبكّرٌ
      // يَرسمُ شاشةَ تعذّرِ الإقلاع عند فشلِ Firebase، فأوّلُ `runApp` صارَ
      // ذاك — وهو قبلَ هذا التحميلِ بحقّ (بلا Firebase لا فاتورةَ أصلاً).
      expect(at, lessThan(m.lastIndexOf('runApp(')),
          reason: 'بعد runApp لا يَسبقُ بناءَ أيِّ فاتورة');
      // بلا انتظارٍ: قراءةٌ واحدةٌ لا تُؤخّرُ الإقلاع.
      expect(m.contains('await ZatcaService.ensureConfigLoaded()'), isFalse);
    });

    test('(ه) `invoiceQrFor` ما زالت البوّابةَ الوحيدة', () {
      var direct = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.endsWith('utils/invoice_stamp.dart') ||
            p.endsWith('services/zatca_service.dart')) {
          continue;
        }
        if (_code(f.readAsStringSync()).contains('generateZatcaQrCode(')) {
          direct++;
        }
      }
      expect(direct, 0,
          reason: 'نداءٌ مباشرٌ يَتخطّى البوّابةَ فيَعودُ «فاتورةٌ برمزَين»');
    });

    test('(و) الرقمُ الضريبيُّ الافتراضيُّ لم يُمَسّ — قرارُ المالك', () {
      expect(_code(svc), contains('vatNumber = "310885360200003"'));
      expect(_code(ed), contains('"310885360200003"'),
          reason: 'افتراضُ الحقلِ في المحرّرِ يُطابقُ افتراضَ الخدمة');
    });

    test('(ز) الفشلُ يُسجَّلُ ولا يُقالُ للمستخدمة', () {
      // الفاتورةُ تَصدرُ بالافتراضاتِ (fail-open مقصود)، لكنّ الصمتَ عنّا
      // كان يُخفي أنّ بياناتَ البائعِ لم تُقرأ.
      expect(_code(svc), contains("reason: 'zatca_config_load_failed'"));
    });
  });
}
