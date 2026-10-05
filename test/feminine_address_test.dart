import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **العميلةُ تُخاطَبُ بالمؤنّث** — والمذكَّرُ قطعاً هو الأفعالُ والأوصاف.
///
/// النصوصُ الخادميّةُ في `functions/index.js` مؤنّثةٌ منذ البداية («دفعتكِ
/// مؤكّدة»، «طلبكِ»، «نتمنى لكِ تجربةً سعيدة»)، وشاشاتُ العميلةِ كانت
/// تُخاطبُها بالمذكَّرِ في **٧٠ سطراً**: «اختر»، «أدخل»، «اضغط»، «حاول»،
/// «تحقّق»، «تواصل»، «أعد المحاولة»، «هل أنت متأكد».
///
/// **والتمييزُ مقصودٌ ويُقال:** الضمائرُ المتّصلةُ غيرُ المشكولةِ («طلبك»،
/// «حسابك»، «رصيدك») تَقرؤها المؤنّثةُ والمذكَّرُ سواءً في الكتابةِ العربيّة،
/// فليست خطأً — ولم تُمَسّ. ما لا يَقبلُ قراءةً مؤنّثةً أصلاً هو الفعلُ
/// («اختر» لا تَصحُّ لمؤنّثٍ بحال) والوصفُ («متأكد»). فالمسحُ على الأفعالِ
/// والأوصافِ وحدَها، لا على كلِّ ما يَنتهي بكاف.
///
/// **والسائقُ والأدمنُ مُستثنيانِ بقصد:** السائقُ مذكَّرٌ («سائق»، ١٤ موضعاً
/// في شاشاتِه)، والأدمنُ هو المالكُ (٤٥ موضعاً). تأنيثُهما خطأٌ لا إصلاح.
void main() {
  // أفعالٌ وأوصافٌ مذكَّرةٌ لا تَقبلُ قراءةً مؤنّثة. الحدودُ صريحةٌ: «التحقق»
  // مصدرٌ معرَّفٌ لا فعلٌ، فلا يُطابَق.
  const ar = r'ء-ي';
  final patterns = <String, RegExp>{
    'هل أنت متأكد': RegExp('(?<![$ar])هل أنت متأكد'),
    'اختر': RegExp('(?<![$ar])اختر(?=[ ـ])'),
    'أدخل': RegExp('(?<![$ar])أدخل(?= )'),
    'اضغط': RegExp('(?<![$ar])اضغط(?= )'),
    'حاول': RegExp('(?<![$ar])(?:و)?حاول(?= )'),
    'تحقّق من': RegExp('(?<![$ar])تحقّ?ق(?= من)'),
    'تواصل مع': RegExp('(?<![$ar])تواصل(?= مع)'),
    'أعد المحاولة': RegExp('(?<![$ar])(?:و)?أعد(?= المحاولة)'),
    'تأكد من': RegExp('(?<![$ar])تأكد(?= من)'),
  };

  /// النصوصُ الحرفيّةُ العربيّةُ في ملفٍّ، بلا أسطرِ التعليق.
  Iterable<(int, String)> arabicLiterals(File f) {
    final out = <(int, String)>[];
    final lines = f.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trimLeft();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      for (final m in RegExp(r"""(['"])((?:\\.|(?!\1)[^\\])*)\1""")
          .allMatches(lines[i])) {
        final lit = m.group(2)!;
        if (RegExp('[$ar]').hasMatch(lit)) out.add((i + 1, lit));
      }
    }
    return out;
  }

  List<File> dartIn(String dir, {bool recursive = false}) => Directory(dir)
      .listSync(recursive: recursive)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  bool isDriver(File f) => f.path.split('/').last.startsWith('driver_');

  group('شاشاتُ العميلةِ تُخاطبُها بالمؤنّث', () {
    test('لا فعلَ مذكَّراً في شاشاتِ العميلة', () {
      final bad = <String>[];
      for (final f in dartIn('lib/screens').where((f) => !isDriver(f))) {
        for (final (ln, lit) in arabicLiterals(f)) {
          for (final e in patterns.entries) {
            if (e.value.hasMatch(lit)) {
              bad.add('${f.path}:$ln «${e.key}» → $lit');
            }
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('ولا في المشتركِ الذي لا تَقرؤه إلّا هي', () {
      // `support_fab` و`rating_dialog` من لوحةِ العميلةِ وحدَها،
      // و`tapToTrackMap`/`tapToViewDetails`/`selectReasonHint` لا قارئَ لها
      // غيرُها، و`order_service`/`moyasar_service` تَرمي نصَّها إلى شاشتِها.
      final bad = <String>[];
      for (final p in const [
        'lib/widgets/support_fab.dart',
        'lib/widgets/rating_dialog.dart',
        'lib/utils/zyiarah_strings.dart',
        'lib/services/order_service.dart',
        'lib/services/moyasar_service.dart',
      ]) {
        for (final (ln, lit) in arabicLiterals(File(p))) {
          for (final e in patterns.entries) {
            if (e.value.hasMatch(lit)) bad.add('$p:$ln «${e.key}» → $lit');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('والحارسُ يَقرأ نصوصاً فعلاً — وإلّا فهو أجوف', () {
      final n = dartIn('lib/screens')
          .where((f) => !isDriver(f))
          .expand(arabicLiterals)
          .length;
      expect(n, greaterThan(300), reason: 'عدَّ $n نصّاً عربيّاً فقط');
      // والنمطُ يَعضُّ على مثالٍ مُصطنَع.
      expect(patterns['اختر']!.hasMatch('اختر اليوم'), isTrue);
      expect(patterns['اختر']!.hasMatch('اختاري اليوم'), isFalse);
      // «التحقق» مصدرٌ لا فعل — لا يُطابَق (وقد طابقَته أوّلُ صياغة).
      expect(patterns['تحقّق من']!.hasMatch('جاري التحقق من التوفر'), isFalse);
      expect(patterns['تحقّق من']!.hasMatch('تحقّق من اتصالك'), isTrue);
    });
  });

  group('والمذكَّرُ في موضعِه يَبقى', () {
    // **عتبةُ عدٍّ لا تَعضّ**: أوّلُ صياغةٍ طلبت «أكثر من ٥» في شاشاتِ
    // السائقِ، وفيها ١٤ — فتأنيثُ ثمانيةٍ منها بالخطأ مرَّ أخضر (وقد جرّبتُه
    // فمرّ). فالتثبيتُ على **نصوصٍ بعينِها**: جملةٌ يَعرفُها أيُّ قارئٍ
    // ويَفتقدُها أيُّ تأنيثٍ شامل.
    test('نصوصُ السائقِ المذكَّرةُ بعينِها باقية', () {
      final dash = File('lib/screens/driver_dashboard.dart').readAsStringSync();
      for (final t in const [
        'اضغط مطولاً — أنا في الطريق',
        'اضغط مطولاً — وصلت، بدء الخدمة',
        'اضغط مطولاً — إتمام المهمة',
        'اضغط للتفعيل',
      ]) {
        expect(dash.contains(t), isTrue,
            reason: 'أُنّث نصُّ السائق «$t» — السائقُ مذكَّرٌ في هذا النشاط');
      }
      final prof =
          File('lib/screens/driver_profile_screen.dart').readAsStringSync();
      expect(prof.contains('تأكد من تثبيته'), isTrue);
    });

    test('ونصوصُ الأدمنِ كذلك', () {
      final del =
          File('lib/screens/admin/admin_deletions_screen.dart').readAsStringSync();
      expect(del.contains('هل أنت متأكد'), isTrue,
          reason: 'الأدمنُ هو المالك — تأنيثُ خطابِه خطأٌ لا إصلاح');
      final con =
          File('lib/screens/admin/admin_contracts_screen.dart').readAsStringSync();
      expect(con.contains('هل أنت متأكد'), isTrue);
      expect(con.contains('أعد المحاولة'), isTrue);
    });
  });
}
