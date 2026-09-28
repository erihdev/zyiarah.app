import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارس التقديم الآليّ لمراجعة App Store — 2026-09-28.
///
/// السياق: `submit_to_app_store: true` (قرار المالك 2026-09-21) لم يُقدّم شيئاً قطّ:
/// كل بناء كان يُنشئ النسخة ويُرفق البناء ويفتح قشرة مراجعة ثم يتوقّف لأن حقل
/// «ما الجديد» (ar-SA) فارغ — فبقيت 1.2.46 هي العامّة وكل ميزات ما بعد 31 أغسطس
/// على TestFlight فقط، بلا أي خطأ ظاهر. الأداة التي تلفّها Codemagic
/// (`app-store-connect publish`) تقرأ النصّ من المتغيّر `APP_STORE_CONNECT_WHATS_NEW`
/// إن لم يُمرَّر — فيُصدَّر من `.github/whatsnew/whatsnew-ar` عبر `$CM_ENV` قبل النشر.
/// `cancel_previous_submissions` يلغي القشور القديمة بالطريقة الصحيحة (سكربت
/// الإلغاء اليدوي أعلاه في codemagic.yaml يضرب مساراً غير موجود ويُخفي فشله بـ
/// ignore_failure)، و`release_type: AFTER_APPROVAL` كي لا تنتظر النسخة ضغطة بعد
/// الموافقة (الافتراضي MANUAL).
void main() {
  String read(String p) => File(p).readAsStringSync();
  final cm = read('codemagic.yaml');
  // مسار iOS وحده: كل ما قبل تعريف مسار أندرويد.
  final ios = cm.substring(0, cm.indexOf('android-release:'));

  test('ملف «ما الجديد» بالعربية موجود وغير فارغ', () {
    final f = File('.github/whatsnew/whatsnew-ar');
    expect(f.existsSync(), isTrue, reason: 'App Store يرفض التقديم بلا «ما الجديد»');
    expect(f.readAsStringSync().trim(), isNotEmpty);
  });

  test('ios-release يصدّر APP_STORE_CONNECT_WHATS_NEW من الملف عبر CM_ENV قبل النشر', () {
    expect(ios.contains('APP_STORE_CONNECT_WHATS_NEW'), isTrue,
        reason: 'الأداة تقرأ «ما الجديد» من هذا المتغيّر — بدونه يتوقّف التقديم صامتاً');
    expect(ios.contains('.github/whatsnew/whatsnew-ar'), isTrue,
        reason: 'مصدر النصّ هو الملف الذي يُعدَّل مع كل إصدار');
    expect(ios.contains(r'>> $CM_ENV'), isTrue,
        reason: 'المتغيّر يجب أن يُكتب إلى CM_ENV ليصل مرحلة النشر');
  });

  test('ios-release: تقديم آليّ كامل — submit + cancel_previous + AFTER_APPROVAL', () {
    expect(ios.contains('submit_to_app_store: true'), isTrue);
    expect(ios.contains('cancel_previous_submissions: true'), isTrue,
        reason: 'قشور المراجعة المفتوحة تمنع تقديماً جديداً');
    expect(ios.contains('release_type: AFTER_APPROVAL'), isTrue,
        reason: 'الافتراضي MANUAL يوقف النسخة بعد الموافقة بانتظار ضغطة');
  });
}
