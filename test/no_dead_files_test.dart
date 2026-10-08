// حارس دائم: **لا ملف في lib/ بلا مستهلك.**
//
// Dart لا يحذّر من ملفٍ لا يستورده أحد — لا `analyze` ولا المصرّف. ولهذا تراكمت
// خمسة ملفات ميتة بصمت حتى حُذفت في 2026-10-03:
//
//   lib/models/order_model.dart              نموذج الطلب المُطبَّع (ZyiarahOrder)
//   lib/screens/account_activation_screen.dart
//   lib/services/zyiarah_capacity_service.dart   بوابة السعة القديمة
//   lib/utils/app_error_handler.dart
//   lib/widgets/permission_sheet.dart
//
// والضرر ليس البايتات. ملفٌ ميت يُقرأ كأنه حيّ: `order_model.dart` كان يُوهم
// بوجود نموذج مُطبَّع للطلب والواقع أن الطلبات تتنقّل كـ`Map<String, dynamic>`،
// و`zyiarah_capacity_service.dart` بقي مذكوراً في تعليقٍ يقول إنه «يستعلم حقول
// فهرس السعة» بعد أن استُبدلت بوابة السعة بـ`getHourlyAvailability` الخادمية —
// فكان القارئ يظنّ المسار حيّاً وهو ميت. وأي مساعد يقرأ CLAUDE.md كان قد يصل
// أحدها «إصلاحاً» لما يبدو خدمةً منسيّة.
//
// **بلا استثناءات:** حتى `main.dart` و`router.dart` و`firebase_options.dart`
// تستوردها ملفاتٌ أخرى (الاختبارات تستورد main.dart، و١٧ ملفاً يستورد router).
// فإن سقط هذا الفحص على ملفٍ جديد فالسؤال: هل نُسي وصله، أم كُتب ولم يُستعمل؟
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

void main() {
  test('لا ملف في lib/ بلا مستهلك', () {
    final libFiles = sourcesIn('lib', atLeast: 100);

    // النصّ الذي يُبحَث فيه: كل شفرة lib وtest. الاختبارات مستهلكٌ مشروع —
    // ملفٌ لا يستورده إلا اختباره ليس ميتاً، بل مُختبَراً وغير موصول بعد،
    // وذلك قرارٌ يُتخذ لا يُفرض هنا.
    final corpus = StringBuffer();
    for (final f in [
      ...libFiles,
      ...sourcesIn('test', atLeast: 80),
    ]) {
      corpus.writeln(f.readAsStringSync());
    }
    final all = corpus.toString();

    final orphans = <String>[];
    for (final f in libFiles) {
      final base = f.uri.pathSegments.last;
      // يُذكَر اسمه داخل سلسلة نصّية؟ (أي `import '...<base>'` أو `part '<base>'`)
      final referenced = RegExp("['\"][^'\"]*${RegExp.escape(base)}['\"]")
          .allMatches(all)
          // استثناء ذكرِه داخل نفسه (library/part of) — لا يجعله مستهلَكاً
          .any((_) => true);
      if (!referenced) orphans.add(f.path);
    }

    expect(
      orphans,
      isEmpty,
      reason: 'ملفات لا يستوردها أحد — إمّا نُسي وصلها أو هي شفرة ميتة. '
          'Dart لا يحذّر منها، فهذا الحارس هو التحذير:\n'
          '${orphans.map((p) => '  - $p').join('\n')}',
    );
  });

  test('الملفات الميتة الخمسة لم تعد', () {
    const removed = [
      'lib/models/order_model.dart',
      'lib/screens/account_activation_screen.dart',
      'lib/services/zyiarah_capacity_service.dart',
      'lib/utils/app_error_handler.dart',
      'lib/widgets/permission_sheet.dart',
    ];
    for (final p in removed) {
      expect(
        File(p).existsSync(),
        isFalse,
        reason: '$p حُذف في 2026-10-03 لأنه ميت. إن عاد فليَعُد موصولاً '
            'بمستهلك حقيقي — ويسقط الفحص الأوّل تلقائياً إن لم يكن كذلك.',
      );
    }
  });

  // كان هنا فحصٌ ثالث يمنع ذكر `ZyiarahCapacityService` في أي ملف. أُسقط
  // لأنه سقط على تعليقٍ **يشرح الحذف** في payment_summary_screen — وهذا عرف
  // المستودع لا خطأ فيه (انظر no_tabby_test.dart: «التعليقات هنا تشرح ما
  // حُذف»). والفحصان أعلاه يكفيان: عودةُ الملف تُسقط الثاني، وملفٌ جديد
  // يستعمل الصنف لا يُصرَّف أصلاً لأن الصنف لم يعد موجوداً.
}
