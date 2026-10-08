// مفتاحُ طريقةِ الدفعِ: سطحانِ يَكتبانِه، وشاشةُ الترحيبِ لا تَعِدُ بما يُطفئه.
//
//   • `tamara_enabled` يُخفي **خيارَ التقسيطِ كاملاً** في شاشتَي الدفعِ
//     (`payment_summary_screen`، `store_payment_screen`) وافتراضُ قراءتَيه
//     `false` — وكاتبُه الوحيدُ كان **لوحةَ الويب**. فمالكٌ يَعملُ من تطبيقِ
//     الإدارةِ لا يَستطيعُ تشغيلَ تمارا إطلاقاً، وقسمُ «إعدادات الدفع» في
//     ذلك التطبيقِ (نسبةُ الذروة، الاسمُ الضريبيّ، الرقمُ الضريبيّ، السجلُّ
//     التجاريّ) لا يَذكرُ أنّ المفتاحَ موجودٌ أصلاً — وهي عائلةُ «حقلُ قرارٍ
//     يَعرفُه مُحرِّرٌ واحد» (مفاتيحُ الإصدار، `show_in_offers`،
//     `operational`، `store_audience`، `restricted_zones`) واقعةً على
//     **طريقةِ دفع**.
//   • و**الشريحةُ الثانيةُ من ثلاثٍ** في شاشةِ الترحيبِ كانت تَقول «ادفعي بكل
//     سهولة **عبر تمارا** بنظام التقسيط المريح» — وعدٌ **غيرُ مشروطٍ** بقدرةٍ
//     **مشروطةٍ وافتراضُها مُطفأ**. وهذه الشاشةُ هي ما يَبلغُه **كلُّ غيرِ
//     مسجَّل** (`main.dart`)، أي أوّلُ ما تَقرؤه عميلةٌ جديدةٌ ومُراجِعُ أبل.
//
// ولا يُمكِنُ أن تُشرَطَ تلك الجملةُ بالعلَم: قاعدةُ `system_configs` تَشترطُ
// `isLoggedIn()` والشاشةُ تَسبقُ التسجيل — فالعلاجُ في النصِّ لا في القراءة،
// وهذا الفحصُ يَشدُّ تلك الفرضيّةَ نفسَها.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/strip_comments.dart';

int _bal(String s, int i, String open, String close) {
  var d = 0;
  for (var k = i; k < s.length; k++) {
    if (s[k] == open) {
      d++;
    } else if (s[k] == close) {
      d--;
      if (d == 0) return k;
    }
  }
  return -1;
}

void main() {
  final dartEditor = stripComments(
      File('lib/screens/admin/admin_settings_screen.dart').readAsStringSync());
  final panel = stripComments(
      File('admin_panel/src/pages/Settings.tsx').readAsStringSync());
  final onboarding =
      File('lib/screens/onboarding_screen.dart').readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();

  /// حقولُ حِمْلِ `main_settings` في محرِّرِ التطبيق — اقتطاعاً من `{` الحِمْلِ
  /// نفسِه بموازنةِ المعقوفةِ، لا بعَدِّ أحرف.
  Set<String> dartPayloadKeys() {
    const anchor =
        "batch.set(_db.collection('system_configs').doc('main_settings'), {";
    final i = dartEditor.indexOf(anchor);
    expect(i, greaterThan(0),
        reason: 'حِمْلُ main_settings في المحرِّرِ تغيّر');
    final b = i + anchor.length - 1;
    final e = _bal(dartEditor, b, '{', '}');
    expect(e, greaterThan(b), reason: 'اقتطاعٌ غيرُ مُوازَن');
    return RegExp(r"'([a-z_]+)':")
        .allMatches(dartEditor.substring(b, e))
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// حقولُ `SystemSettings` في اللوحة — وهي ما تَكتبُه جملةً
  /// (`batch.set(doc, settings, {merge:true})`).
  Set<String> panelKeys() {
    final i = panel.indexOf('interface SystemSettings {');
    expect(i, greaterThan(0), reason: 'واجهةُ SystemSettings تغيّرت');
    final b = panel.indexOf('{', i);
    final e = _bal(panel, b, '{', '}');
    return RegExp(r'^\s*([a-z_]+)\s*\??\s*:', multiLine: true)
        .allMatches(panel.substring(b, e))
        .map((m) => m.group(1)!)
        .toSet();
  }

  group('مفتاحُ تمارا يُكتَبُ من السطحَين', () {
    test('(أ) الاشتقاقُ أصابَ: حِمْلانِ غيرُ فارغَين', () {
      expect(dartPayloadKeys().length, greaterThanOrEqualTo(8),
          reason: 'استخراجُ حِمْلِ المحرِّرِ انحلّ');
      expect(panelKeys().length, greaterThanOrEqualTo(4),
          reason: 'استخراجُ حقولِ اللوحةِ انحلّ');
    });

    test('(ب) `tamara_enabled` في الحِمْلَين', () {
      expect(dartPayloadKeys(), contains('tamara_enabled'),
          reason:
              'محرِّرُ التطبيقِ لا يَكتبُ المفتاحَ — والتقسيطُ مخفيٌّ بلاه');
      expect(panelKeys(), contains('tamara_enabled'));
    });

    test('(ج) والمفتاحُ مَعروضٌ في المحرِّرِ لا مكتوباً بصمت', () {
      // حِمْلٌ يَحملُ المفتاحَ بلا مفتاحٍ في الواجهةِ يَكتبُ قيمةَ الحالةِ
      // الافتراضيّةَ فوقَ المحفوظ — أسوأُ من غيابِه.
      expect(dartEditor.contains('_tamaraEnabled'), isTrue);
      expect(
          RegExp(r'_buildToggle\(\s*\n?\s*"تمارا').hasMatch(dartEditor), isTrue,
          reason: 'لا مفتاحَ ظاهرٌ للتقسيطِ في «إعدادات الدفع»');
      // ويُقرَأُ من المستندِ وإلّا كُتبَ `false` فوقَ تشغيلٍ قائم.
      expect(dartEditor.contains("data['tamara_enabled'] == true"), isTrue,
          reason: 'لا يُقرَأُ المحفوظُ — الحفظُ يُطفئُ ما شغّلَته اللوحة');
    });

    test('(د) وقارئا الشاشتَين يَقرآنِه بالافتراضِ نفسِه', () {
      for (final f in const [
        'lib/screens/payment_summary_screen.dart',
        'lib/screens/store_payment_screen.dart',
      ]) {
        final src = stripComments(File(f).readAsStringSync());
        expect(src.contains("['tamara_enabled'] as bool? ?? false"), isTrue,
            reason: '$f: قراءةُ العلَمِ تغيّرت — يُراجَعُ تعليلُ الشريحة');
      }
    });

    test('(هـ) ومجموعةُ ما يَنفردُ به كلُّ محرِّرٍ مُعلَّلةٌ كاملةً', () {
      // المستندُ واحدٌ (`system_configs/main_settings`) والمحرِّرانِ يَكتبانِ
      // مجموعتَين غيرَ متساويتَين — وذاك مقبولٌ متى كان لكلِّ فارقٍ سببُه.
      // (اللوحةُ تَكتبُ `settings` جملةً و`settings` مبنيٌّ من المستندِ
      // المقروءِ، فحقولُ التطبيقِ تَمُرُّ بها بلا مساس — نتيجةٌ مُتحقَّقٌ منها
      // ومسجَّلةٌ في CLAUDE.md.)
      const panelOnly = {
        // تَستعملُه اللوحةُ نفسُها في زرِّ الدعمِ أعلى صفحتِها — ولا قارئَ له
        // في `lib/` إطلاقاً، فهو إعدادٌ محلّيٌّ للوحةِ لا قدرةٌ ناقصةٌ هنا.
        'support_url',
      };
      const dartOnly = {
        // بياناتُ البائعِ على الفاتورةِ الضريبيّةِ وجهاتُ الدعمِ ونسبةُ
        // الذروةِ وشروطُ العقد: إضافتُها للوحةِ تحسينُ اكتمالٍ لا إصلاح
        // (قرارٌ مسجَّلٌ في CLAUDE.md مع حقولِ ZATCA الثلاثة).
        'merchant_name', 'vat_number', 'cr_number', 'admin_email',
        'support_whatsapp', 'support_phone', 'surge_percent', 'contract_terms',
      };
      final d = dartPayloadKeys();
      final p = panelKeys();
      expect(p.difference(d), panelOnly,
          reason:
              'فارقٌ في اللوحةِ بلا سببٍ مُعلَن: ${p.difference(d).difference(panelOnly)}');
      expect(d.difference(p), dartOnly,
          reason:
              'فارقٌ في المحرِّرِ بلا سببٍ مُعلَن: ${d.difference(p).difference(dartOnly)}');
    });
  });

  group('شاشةُ الترحيبِ لا تَعِدُ ببوّابةٍ بعينِها', () {
    test('(و) لا اسمَ بوّابةِ دفعٍ في أيِّ شريحة', () {
      // النطاقُ هو **نصوصُ الشرائحِ** لا الملفُّ كلُّه: التعليقُ يُسمّي تمارا
      // لِيَشرحَ العطلَ (فخُّ «الحارسُ يَسقطُ على توثيقِه»)، والمضادّةُ تَحتَه.
      final code = stripComments(onboarding);
      final i = code.indexOf('_data = [');
      expect(i, greaterThan(0), reason: 'قائمةُ الشرائحِ تغيّرت');
      final b = code.indexOf('[', i);
      final e = _bal(code, b, '[', ']');
      final slides = code.substring(b, e);
      expect(slides.length, greaterThan(200),
          reason: 'اقتطاعُ الشرائحِ انحلّ — الفحصُ عقيم');
      for (final gw in const [
        'تمارا',
        'Tamara',
        'تابي',
        'Tabby',
        'ميسر',
        'Moyasar',
        'STC'
      ]) {
        expect(slides.contains(gw), isFalse,
            reason: 'شريحةُ الترحيبِ تُسمّي بوّابةً: $gw');
      }
      // وشاهدُ أنّ الشرائحَ ما زالت تَتحدّثُ عن الدفع (لا حُذفت الشريحة).
      expect(slides.contains('دفع'), isTrue);
    });

    test('(ز) المضادّة: شرحُ العطلِ ما زال في الخامّ', () {
      expect(onboarding.contains('عبر تمارا'), isTrue,
          reason: 'النصُّ القديمُ لم يَعُدْ مُقتَبَساً في شرحِ التصحيح');
      expect(onboarding.contains('tamara_enabled'), isTrue);
    });

    test('(ح) وتعليلُ «العلاجُ في النصِّ لا في القراءة» قائم', () {
      // الشاشةُ تَسبقُ التسجيل، وقراءةُ `system_configs` تَشترطُ الدخولَ —
      // فلا يُمكِنُ أن تَقرأَ العلَمَ لِتُشرِطَ الجملة. لو فُتِحت القراءةُ
      // يوماً فهذا الفحصُ هو ما يُراجَع.
      // فخُّ الحدِّ: أوّلُ `{` بعدَ الموضعِ هو قوسُ `{configId}` في سطرِ
      // `match` نفسِه لا قوسُ الكتلة — نفسُ ما أسقطَ `storage_hardening_test`.
      // فالمِرساةُ `} {` في نهايةِ السطر.
      final i = rules.indexOf('match /system_configs/{configId}');
      expect(i, greaterThan(0));
      final open = rules.indexOf('{', rules.indexOf('\n', i) - 2);
      final blk = rules.substring(i, _bal(rules, open, '{', '}'));
      expect(blk.length, greaterThan(40), reason: 'اقتطاعُ الكتلةِ انحلّ');
      expect(blk.contains('allow read: if isLoggedIn()'), isTrue,
          reason: 'قراءةُ system_configs تغيّرت — يُراجَعُ قرارُ النصّ');
      // وشاشةُ الترحيبِ هي سطحُ غيرِ المسجَّل.
      final main = stripComments(File('lib/main.dart').readAsStringSync());
      expect(main.contains('return const OnboardingScreen();'), isTrue,
          reason: 'لم تَعُدْ شاشةَ غيرِ المسجَّل — يُراجَعُ التعليل');
    });
  });
}
