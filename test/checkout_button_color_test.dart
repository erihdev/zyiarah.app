import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/strip_comments.dart';

/// **لونُ زرِّ الدفعِ كان يُقرأُ من تجربةٍ لا كاتبَ لها ولا قارئَ مُجازاً.**
///
/// `ZyiarahConfigProvider` كان يُنشَأُ في `main.dart` لـ**كلِّ** جلسة، ويَفتحُ
/// مستمعاً على `config/ux_experiments` ليَقرأَ `checkout_button_color`. وفيه
/// عطبانِ، سببُهما واحد:
///
/// **١. لا كاتبَ للحقلِ في المستودعِ كلِّه** — لا مُحرِّرٌ في تطبيقِ الإدارةِ
/// ولا في اللوحة، ولا كتابةٌ خادميّة. فالقيمةُ كانت **دائماً** افتراضَ
/// المُزوِّدِ `0xFF2563EB` — أزرقُ لوحةِ الإدارة — على زرِّ «تأكيد وإتمام
/// الدفع»، أهمِّ زرٍّ في التطبيق، بينما لونُ العلامةِ في شاشاتِ العميلةِ
/// `0xFF660033` (مئةٌ وستّةٌ وثمانون موضعاً). وأصرحُ من ذلك: احتياطُ تحليلِ
/// الـhex في الخدمةِ المحذوفةِ نفسِها كان `0xFF660033` — فالمقصودُ كان لونَ
/// العلامةِ من البداية، والافتراضُ الأزرقُ سهو.
///
/// **٢. والقراءةُ مرفوضةٌ أصلاً.** قاعدةُ `config/{configId}` هي
/// `allow read, write: if isSuperAdmin()` — فمستمعُ كلِّ عميلةٍ وكلِّ سائقٍ
/// يُرَدُّ بـ`permission-denied`، و`onError` كان `debugPrint`اً وحدَه، وهو
/// **لا يُجمَع** (قاعدةُ `reportSilent` في `lib/utils/error_report.dart`).
/// فحصٌ على المُحاكي في `functions/test/rules.roles.test.js` يُثبِتُ الرفضَ.
///
/// **والإزالةُ تَتبعُ قراراً مسجَّلاً:** شقيقُه `checkoutVariantName` حُذِفَ
/// بالحجّةِ نفسِها — «اسمُ النسخةِ إنّما يُوجَدُ لِيُرفَقَ بقياسِ التحويل، ولا
/// قياسَ هنا» — وتعليقُ الحذفِ استثنى اللونَ بوصفِه «حيّاً ويُستعمَل»، وهو ما
/// يُصحِّحُه هذا الفحص: كان مُستعمَلاً، ولم يَكن حيّاً.
void main() {
  final pay = File('lib/screens/payment_summary_screen.dart');
  final main_ = File('lib/main.dart');
  final self = File('test/checkout_button_color_test.dart').readAsStringSync();

  /// جسمُ دالّةٍ بموازنةِ الأقواسِ المعقوفةِ **بعدَ** قائمةِ المعامَلات —
  /// `indexOf('{')` يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ، وهو فخٌّ مسجَّلٌ في
  /// هذا المستودعِ سِتَّ مرّات.
  String body(String src, String sig) {
    final i = src.indexOf(sig);
    expect(i, greaterThan(-1), reason: 'لم تُوجَد $sig');
    var j = src.indexOf('(', i);
    var depth = 0;
    for (; j < src.length; j++) {
      if (src[j] == '(') depth++;
      if (src[j] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    final open = src.indexOf('{', j);
    depth = 0;
    for (var k = open; k < src.length; k++) {
      if (src[k] == '{') depth++;
      if (src[k] == '}') {
        depth--;
        if (depth == 0) return src.substring(open, k + 1);
      }
    }
    fail('تعذّرَ اقتطاعُ جسمِ $sig');
  }

  test('(١) زرُّ الدفعِ بلونِ العلامةِ لا بقراءةِ مُزوِّد', () {
    final b = body(pay.readAsStringSync(), 'Widget _buildBottomButton');
    final code = stripComments(b);
    expect(code, contains('const Color(0xFF660033)'),
        reason: 'زرُّ «تأكيد وإتمام الدفع» لم يَعُد بلونِ العلامة');
    expect(code, isNot(contains('0xFF2563EB')),
        reason: 'عادَ أزرقُ لوحةِ الإدارةِ إلى زرِّ دفعِ العميلة');
    expect(code, isNot(contains('checkoutButtonColor')),
        reason: 'عادت قراءةُ لونِ التجربةِ — حقلٌ لا كاتبَ له');
  });

  test('(٢) و`_agreeToTerms` ما زال يَحكمُ الزرَّ (قرارُ المالك: لا تُمَسّ)',
      () {
    final code = stripComments(body(
        pay.readAsStringSync(), 'Widget _buildBottomButton'));
    expect(code, contains('_agreeToTerms'),
        reason: 'بوّابةُ الموافقةِ على الشروطِ سقطت من الزرّ');
    expect(code, contains('Colors.grey.shade300'));
  });

  test('(٣) لا موضعَ في `lib/` يَقرأُ تجربةَ الواجهةِ بعدَ الآن', () {
    // المسحُ مُشتَقٌّ من المجلّدِ لا مكتوبٌ بيد، ويَقرأُ النصَّ **مُجرَّداً من
    // التعليقات** لأنّ تعليقاتي أعلاه وفي `main.dart` وفي شاشةِ الدفعِ تُسمّي
    // المصطلحاتِ الثلاثةَ كلَّها — «الحارسُ يَسقطُ على توثيقِه»، والمضادّةُ
    // تَحتَه تَمنعُ أن يُفرِّغَ الحجبُ الفحصَ.
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThan(100), reason: 'المسحُ لم يَقرأ شيئاً');
    final hits = <String>[];
    for (final f in files) {
      final code = stripComments(f.readAsStringSync());
      for (final term in [
        'ux_experiments',
        'checkout_button_color',
        "collection('config')",
        'ZyiarahConfigProvider',
        'ZyiarahConfigService',
      ]) {
        if (code.contains(term)) hits.add('${f.path}  ←  $term');
      }
    }
    expect(hits, isEmpty,
        reason: '\n\nقراءةٌ عادت إلى مجموعةٍ قاعدتُها `isSuperAdmin()` '
            'وحقلٍ لا كاتبَ له:\n  • ${hits.join('\n  • ')}\n');
  });

  test('(٤) والمصطلحاتُ ما زالت في النصِّ الخامِّ — مضادَّةُ فرطِ الحجب', () {
    // بلا هذا يَمُرُّ الفحصُ (٣) على مُجرِّدٍ يَبتلعُ الملفّات.
    final raw = main_.readAsStringSync() +
        pay.readAsStringSync() +
        self;
    for (final term in [
      'ux_experiments',
      'checkout_button_color',
      'ZyiarahConfigProvider',
      '0xFF2563EB',
    ]) {
      expect(raw, contains(term),
          reason: 'زالَ شرحُ القرارِ من الشفرة — فالفحصُ (٣) لا يَحرُسُ شيئاً '
              'مفهوماً، ومَن يَقرأُ لا يَعرفُ لماذا');
    }
  });

  test('(٥) المُزوِّدُ لم يَعُد يُسجَّلُ ولا ملفّاهُ قائمَين', () {
    final code = stripComments(main_.readAsStringSync());
    expect(code, isNot(contains('ZyiarahConfigProvider')),
        reason: 'عادَ تسجيلُ مُزوِّدٍ مستمعُه مرفوضٌ لكلِّ عميلةٍ وسائق');
    expect(File('lib/providers/config_provider.dart').existsSync(), isFalse);
    expect(File('lib/services/config_service.dart').existsSync(), isFalse);
  });

  test('(٦) ولونُ العلامةِ ليس اختياراً عشوائيّاً — الأغلبُ في أسطحِ العميلة',
      () {
    // الحرفُ `0xFF660033` لم يُختَرْ بالذوق: الدعوى أنّه **أكثرُ لونٍ وروداً**
    // في شاشاتِ العميلةِ وودجاتِها، وهي دعوى تُحسَبُ لا تُقرَأ. وبهذا تَصيرُ
    // (١) قاعدةً لا تفضيلاً، ولا يُعادُ الأزرقُ غداً بحجّةِ «كلاهما لونُ
    // العلامة». والمقارنةُ بالترتيبِ لا بعتبةٍ عدديّةٍ لأنّ العتبةَ هي ما
    // أمرَّ ثمانيَ شاشاتٍ في حارسِ المخاطبةِ المؤنَّثةِ من قبل.
    final counts = <String, int>{};
    final files = [
      ...Directory('lib/screens').listSync().whereType<File>(),
      ...Directory('lib/widgets').listSync(recursive: true).whereType<File>(),
    ].where((f) => f.path.endsWith('.dart')).toList();
    expect(files.length, greaterThan(20), reason: 'المسحُ لم يَقرأ شيئاً');
    for (final f in files) {
      for (final m in RegExp(r'0x[fF]{2}[0-9a-fA-F]{6}')
          .allMatches(f.readAsStringSync())) {
        final k = m.group(0)!.toUpperCase().replaceFirst('0X', '0x');
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    expect(counts.length, greaterThan(20),
        reason: 'لم تُقرأ ألوانٌ — فالترتيبُ أجوف');
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    expect(ranked.first.key, '0xFF660033',
        reason: 'لونُ العلامةِ لم يَبقَ الأغلبَ في أسطحِ العميلة '
            '(الأغلبُ الآن ${ranked.first.key} بـ${ranked.first.value}) — '
            'فتعليلُ (١) يُراجَعُ لا يُسكَت');
  });
}
