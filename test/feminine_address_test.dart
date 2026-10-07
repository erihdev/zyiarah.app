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
    // ── الموجةُ الثانية (2026-10-05) ───────────────────────────────────
    // القائمةُ الأولى كانت **مُنتقاةً بيدها**، فكلُّ فعلٍ خارجَها نجا — ومنها
    // اثنانِ أنتجا **جملةً واحدةً بجنسَين**: «محاولات كثيرة — انتظر قليلاً ثم
    // أعيدي المحاولة» و«إن كنت قد دُفعت فلا تقلق — … أو تواصلي مع الدعم».
    // فمسحٌ ثانٍ بقائمةٍ أوسعَ وجدَ ١٩ موضعاً في وجهِ العميلة.
    'انتظر': RegExp('(?<![$ar])انتظر(?= )'),
    'لا تقلق': RegExp('(?<![$ar])تقلق(?![$ar])'),
    'اكتب': RegExp('(?<![$ar])اكتب(?= )'),
    'جرّب': RegExp('(?<![$ar])جرّ?ب(?= )'),
    'انقر': RegExp('(?<![$ar])انقر(?= )'),
    'اطلب': RegExp('(?<![$ar])اطلب(?= )'),
    'ابحث': RegExp('(?<![$ar])ابحث(?= )'),
    'استخدم': RegExp('(?<![$ar])استخدم(?= )'),
    'شارك': RegExp('(?<![$ar])شارك(?= )'),
    'قيّم': RegExp('(?<![$ar])قيّم(?= )'),
    'أضف': RegExp('(?<![$ar])أضف(?= )'),
    'فعّل': RegExp('(?<![$ar])فعّل(?= )'),
    'ادفع': RegExp('(?<![$ar])ادفع(?= )'),
    // «سجل» اسمٌ في ثلاثةِ مواضعَ مشروعة («سجل الطلبات»، «سجل تجاري»، «سجل
    // آخر المعاملات») والفعلُ يُكتَبُ مُشدَّداً، فالنمطُ على الشدّةِ وحدَها
    // زائداً «سجل الدخول» صراحةً — ولا يُطابقُ الأسماءَ الثلاثة.
    'سجّل': RegExp('(?<![$ar])(?:سجّل|سجل(?= الدخول))(?= )'),
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

    test('وما يَقرؤه أكثرُ من دورٍ يَبقى بلا جنس', () {
      // ثلاثةُ نصوصٍ لا تَخصُّها وحدَها، فتأنيثُها يُخاطبُ السائقَ أو المالكَ
      // بالمؤنّث: `global_error_handler` يَعرضُه كلُّ دور، وحقلُ البحثِ في
      // `location_picker_screen` يَفتحُه `admin_hourly_zones_screen` أيضاً،
      // ومثالُ ملاحظاتِ المنزلِ موجَّهٌ إلى الفريقِ لا إليها. فالحلُّ صيغةٌ
      // بلا جنسٍ (مصدرٌ أو «يُرجى») لا تأنيث.
      // **سقطَ هذا الفحصُ بالنقلِ لا بالانحراف (2026-10-07):** الجملةُ انتقلت
      // من `global_error_handler` إلى `user_facing_error` حين سَكنَ قرارُ
      // «ماذا نَعرضُ لها» مرّةً واحدةً — فالنطاقُ **الزوجُ معاً**، ونقلٌ
      // لاحقٌ بينهما لا يُخلي الفحص. وعضَّ على أوّلِ صياغةٍ لذلك الملفِّ
      // فعلاً: كانت «تحقّقي من الشبكة» في جملةٍ يَقرؤها كلُّ دور.
      const roleAgnosticFiles = [
        'lib/utils/global_error_handler.dart',
        'lib/utils/user_facing_error.dart',
      ];
      final roleAgnostic =
          roleAgnosticFiles.map((p) => File(p).readAsStringSync()).join('\n');
      expect(roleAgnostic, contains('يُرجى المحاولة مرة أخرى'));
      // وكلُّ جملةٍ ثابتةٍ في القاعدةِ **بلا جنس**: `handleError` غيرُ مُقيَّدٍ
      // بدورٍ، فصيغةُ المؤنَّثِ فيها تُخاطبُ السائقَ والمالكَ بالمؤنّث.
      //
      // **و`patterns` أعلاه تَكشفُ المذكَّرَ لا المؤنَّث**، فاستعمالُها هنا
      // يَمُرُّ على سطرٍ مؤنَّثٍ مَرورَ الكرام — وقد مرَّ: أوّلُ صياغةٍ لهذا
      // الفحصِ استعملتها، فنجحَ اختبارُ قضمٍ وضعَ «تحقّقي من الشبكة» في
      // القاعدةِ **أخضرَ**. فالكشفُ بصيغِ المؤنَّثِ نفسِها، ولكلٍّ شاهدُ
      // استعمالٍ في شاشاتِ العميلةِ — فقائمةٌ مُختَرَعةٌ لا تَحرُسُ شيئاً.
      const feminine = [
        'اختاري', 'أدخلي', 'اضغطي', 'حاولي', 'تحقّقي',
        'تواصلي', 'أعيدي', 'انتظري', 'تقلقي', 'أنتِ',
      ];
      final screens = dartIn('lib/screens', recursive: true)
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final w in feminine) {
        expect(screens.contains(w), isTrue,
            reason: '«$w» ليست صيغةً يَستعملُها المشروعُ — فالقائمةُ تَتعفّن');
      }
      for (final p in roleAgnosticFiles) {
        for (final (ln, lit) in arabicLiterals(File(p))) {
          for (final w in feminine) {
            expect(lit.contains(w), isFalse,
                reason: '$p:$ln «$w» → $lit — يَقرؤه كلُّ دور؛ وما يَخُصُّها '
                    'وحدَها يُمرَّرُ في fallback من موضعِ النداء');
          }
        }
      }
      expect(roleAgnostic, contains('kGenericErrorMessage'));
      expect(File('lib/screens/location_picker_screen.dart').readAsStringSync(),
          contains('البحث عن شارع'));
      expect(File('lib/screens/profile_screen.dart').readAsStringSync(),
          contains('ويرجى استخدام ملمع الخشب'));
      // ونصُّ الإحالةِ تُرسلُه هي إلى **غيرِها**، ومَن يَقرؤه مجهولُ الجنس
      // («أهلك وأصدقائك») — فالجمعُ، ولا عاميّةَ («وبتحصل»).
      final prof = File('lib/screens/profile_screen.dart').readAsStringSync();
      expect(prof, contains('سجّلوا في تطبيق زيارة'));
      expect(prof, contains('وتحصلون على خصم'));
      expect(prof.contains('وبتحصل'), isFalse,
          reason: 'عاميّةٌ في نصٍّ تُرسلُه العميلةُ باسمِنا');
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
      // ومن الموجةِ الثانية: الاسمُ لا يُطابَق والفعلُ يُطابَق.
      expect(patterns['سجّل']!.hasMatch('سجل الطلبات'), isFalse);
      expect(patterns['سجّل']!.hasMatch('سجّل الدخول الآن'), isTrue);
      expect(patterns['استخدم']!.hasMatch('يرجى استخدام ملمع'), isFalse);
      expect(patterns['استخدم']!.hasMatch('استخدم 6 أحرف'), isTrue);
      expect(patterns['ادفع']!.hasMatch('أو ادفع بـ'), isTrue);
      expect(patterns['ادفع']!.hasMatch('أو ادفعي بـ'), isFalse);
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
