import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارس التقديم الآليّ لمراجعة App Store — 2026-09-28، أُصلحت الآلية 2026-09-30.
///
/// السياق: `submit_to_app_store: true` (قرار المالك 2026-09-21) لم يُقدّم شيئاً قطّ:
/// كل بناء كان يُنشئ النسخة ويُرفق البناء ويفتح قشرة مراجعة ثم يتوقّف لأن حقل
/// «ما الجديد» (ar-SA) فارغ — فبقيت 1.2.46 هي العامّة وكل ميزات ما بعد 31 أغسطس
/// على TestFlight فقط، بلا أي خطأ ظاهر (1.2.47 و1.2.48 قُدّمتا يدوياً).
/// علاج 09-28 — تصدير النصّ في متغيّر بيئة عبر `$CM_ENV` — لم يعمل قطّ: Codemagic
/// تنفّذ التقديم في «post-processing» بعد تحرير جهاز البناء، فلا يصلها شيء من CM_ENV،
/// وفشل التقديم هناك لا يُفشل البناء (البناء #238 «نجح» و1.2.48 بلا «ما الجديد»).
/// القناة الموثّقة عند Codemagic هي `release_notes.json` في جذر المشروع، فتولّده خطوة
/// `Write release_notes.json` من `.github/whatsnew/whatsnew-ar` (اللغة ar-SA).
/// `cancel_previous_submissions` يلغي القشور القديمة بالطريقة الصحيحة (سكربت
/// الإلغاء اليدوي في codemagic.yaml يضرب مساراً غير موجود ويُخفي فشله بـ
/// ignore_failure)، و`release_type: AFTER_APPROVAL` كي لا تنتظر النسخة ضغطة بعد
/// الموافقة (الافتراضي MANUAL).
void main() {
  String read(String p) => File(p).readAsStringSync();
  final cm = read('codemagic.yaml');
  // مسار iOS وحده: كل ما قبل تعريف مسار أندرويد.
  final ios = cm.substring(0, cm.indexOf('android-release:'));
  // الأسطر غير التعليقية وحدها — التعليقات تشرح التاريخ وقد تذكر ما لا يجوز في الكود.
  final iosCode = ios
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  test('ملف «ما الجديد» بالعربية موجود وغير فارغ', () {
    final f = File('.github/whatsnew/whatsnew-ar');
    expect(f.existsSync(), isTrue, reason: 'App Store يرفض التقديم بلا «ما الجديد»');
    expect(f.readAsStringSync().trim(), isNotEmpty);
  });

  // ── «عدّلِ الملفَّ مع كلِّ رقمِ نسخةٍ جديد» — أمرٌ بلا قارئ ────────────
  //
  // تعليقُ `codemagic.yaml` يَقولُها بالخطِّ العريضِ («**عدّل
  // .github/whatsnew/whatsnew-ar مع كل رقم نسخة جديد.**») وكذلك CLAUDE.md،
  // و**لا شيءَ كان يُقابِلُ النصَّ بالنسخة**. فالحارسُ القائمُ يَطلبُ أن
  // يكونَ الملفُّ غيرَ فارغٍ وحدَه — وهو أخضرُ على نصٍّ يَصفُ إصداراً
  // ماضياً. ورقمُ البناءِ يَتزايدُ آليّاً في CI، أمّا رقمُ **النسخةِ**
  // فيُبدّله المالكُ بيدِه، فالنسيانُ هو الحالةُ الافتراضيّة: تَصدُرُ 1.2.51
  // ومتجرُ آبل يَقولُ «ما الجديد في 1.2.50».
  //
  // وهي عائلةُ «ادّعاءٌ/أمرٌ بلا قارئ» التي تَكرّرت هنا (ترويسةُ
  // `couponProblem`، تعليقُ `PromoCoupon`، «all HMAC-verified»، مرآةُ
  // `access.ts`، بيانُ الخصوصيّة).
  test('ورقمُ النسخةِ في «ما الجديد» هو رقمُ pubspec بعينِه', () {
    final notes = File('.github/whatsnew/whatsnew-ar').readAsStringSync();
    final pv = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+',
            multiLine: true)
        .firstMatch(read('pubspec.yaml'));
    expect(pv, isNotNull, reason: 'تعذّر قراءةُ النسخةِ من pubspec.yaml');
    final version = pv!.group(1)!;
    // النصُّ يَفتتحُ بـ«ما الجديد في X:» — الرقمُ يُقرأُ منه لا يُفترَض.
    final nv = RegExp(r'([0-9]+\.[0-9]+\.[0-9]+)').firstMatch(notes);
    expect(nv, isNotNull,
        reason: 'لا رقمَ نسخةٍ في «ما الجديد» — فلا يُعرَفُ أيَّ إصدارٍ يَصف');
    expect(nv!.group(1), version,
        reason: 'نصُّ «ما الجديد» يَصفُ ${nv.group(1)} والنسخةُ $version — '
            'المتجرُ سيَعرضُ ملاحظاتَ إصدارٍ آخر');
  });

  test('ios-release يولّد release_notes.json من الملف قبل النشر — لا عبر CM_ENV', () {
    expect(iosCode.contains('release_notes.json'), isTrue,
        reason: 'Codemagic تقرأ «ما الجديد» من هذا الملف في جذر المشروع عند النشر');
    expect(iosCode.contains('"language": "ar-SA"'), isTrue,
        reason: 'لغة الأساس في App Store Connect — بدونها يُرفض التقديم');
    expect(iosCode.contains('.github/whatsnew/whatsnew-ar'), isTrue,
        reason: 'مصدر النصّ هو الملف الذي يُعدَّل مع كل إصدار');
    expect(iosCode.contains('APP_STORE_CONNECT_WHATS_NEW'), isFalse,
        reason: 'التقديم يجري في post-processing بعد تحرير الجهاز — CM_ENV لا يصله؛ '
            'هذا المسار لم يعمل قطّ فلا يُعاد');
    expect(read('.gitignore').contains('/release_notes.json'), isTrue,
        reason: 'الملف مولَّد؛ لو التُزم في الجذر لطبّقته Codemagic على نشر Play أيضاً');
  });

  test('ios-release: تقديم آليّ كامل — submit + cancel_previous + AFTER_APPROVAL', () {
    expect(ios.contains('submit_to_app_store: true'), isTrue);
    expect(ios.contains('cancel_previous_submissions: true'), isTrue,
        reason: 'قشور المراجعة المفتوحة تمنع تقديماً جديداً');
    expect(ios.contains('release_type: AFTER_APPROVAL'), isTrue,
        reason: 'الافتراضي MANUAL يوقف النسخة بعد الموافقة بانتظار ضغطة');
  });
}
