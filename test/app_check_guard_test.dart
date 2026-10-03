// حارس دائم: **App Check يُرسل الرموز ولا يُلزم بها — بعد.**
//
// مفاتيح Firebase في firebase_options.dart عامّة بالتصميم، فالحارس الوحيد قبل
// هذه الدفعة كان قواعد Firestore والمصادقة: أي سكربت يسجّل حساباً ثم يمارس كل
// صلاحيات العميل وينادي الدوال الـ٢١ من خارج التطبيق بلا جهاز ولا تطبيق.
//
// **الفخّ الذي يحرسه هذا الملف:** الإلزام تغييرٌ بسطر واحد (enforceAppCheck في
// دالة، أو مفتاح في لوحة Firebase) وأثره انقطاع خدمة كامل: النسخة العامّة 1.2.46
// بلا هذه الحزمة إطلاقاً، فكل طلب من كل مستخدم حاليّ يُرفض. ولا يصحّ الإلزام إلا
// بعد انتشار نسخة تحملها وبلوغ نسبة الطلبات المُوثَّقة ~١٠٠٪ في لوحة Firebase.
//
// فالفحوص أدناه تثبّت أمرين معاً: أن الإرسال **قائم** (وإلا لا يبدأ العدّاد
// أصلاً)، وأن الإلزام **غير مُفعَّل في الشفرة** — وسقوط الفحص الأخير ليس خطأً
// يُصلَح بتعطيله، بل سؤال: هل تحقّق شرط الانتشار؟ إن تحقّق فعلاً فحدِّث الحارس
// والوثيقة معاً بقرار موثَّق.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// يزيل التعليقات: تعليقات main.dart وindex.js **تشرح** الإلزام وشرطه، ففحص
/// المصدر الخام يسقط الحارس على شرحه هو — إنذار كاذب يدفع لتعطيله.
String _code(String path) => _read(path)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('App Check: الإرسال قائم', () {
    test('الحزمة مُعلَنة في pubspec', () {
      expect(_read('pubspec.yaml'), contains('firebase_app_check:'));
    });

    test('main.dart يُقلع App Check فعلاً', () {
      final code = _code('lib/main.dart');
      expect(code, contains('FirebaseAppCheck.instance'));
      expect(code, contains('.activate('));
      expect(
        code,
        contains('AndroidPlayIntegrityProvider()'),
        reason: 'أندرويد المنصّة التي يعمل فيها التوثيق من Dart وحده — '
            'إسقاطها يُفرغ الدفعة من مضمونها.',
      );
    });

    test('الإقلاع لا يُسقط التطبيق عند فشل التوثيق', () {
      final code = _code('lib/main.dart');
      final at = code.indexOf('FirebaseAppCheck.instance');
      expect(at, greaterThan(-1));

      // نافذة النداء: من `try {` السابق له إلى `catch` التالي. القطع عند أوّل
      // `}` خطأ — ذلك القوس هو بعينه الذي يسبق catch، فيستثني ما نبحث عنه.
      final before = code.substring(0, at);
      final after = code.substring(at);

      expect(
        after.substring(0, after.indexOf(';') + 1),
        contains('.timeout('),
        reason: 'activate يُنتظَر قبل runApp. بلا مهلة، انقطاع شبكة لحظة الفتح '
            'يمنع إقلاع التطبيق كلّه — درسُ تابي (#264).',
      );
      expect(
        RegExp(r'try\s*\{\s*await\s*$').hasMatch(before),
        isTrue,
        reason: 'النداء يجب أن يكون أوّل ما في كتلة try (await وحده بينهما)، '
            'بلا شيء يرمي قبل أن يُحمى.',
      );
      expect(
        RegExp(r'\}\s*catch\s*\(').hasMatch(after),
        isTrue,
        reason: 'الفشل يجب أن يُلتقط بلا رمي: غياب رمز موثَّق بلا أثر ما دام '
            'الإلزام مُطفأً، أما الرمي فيمنع الإقلاع.',
      );
    });

    test('الويب مستثنى — لا مفتاح reCAPTCHA ولوحة الإدارة بلا App Check', () {
      final code = _code('lib/main.dart');
      final i = code.indexOf('FirebaseAppCheck.instance');
      expect(
        code.substring(0, i).contains('if (!kIsWeb)'),
        isTrue,
        reason: 'إقلاعه على الويب بلا مفتاح موقع يفشل بلا فائدة.',
      );
    });
  });

  group('App Check: الإلزام غير مُفعَّل بعد', () {
    test('لا enforceAppCheck في أي دالة خادمية', () {
      final fns = _code('functions/index.js');
      expect(
        fns.contains('enforceAppCheck'),
        isFalse,
        reason: 'تفعيله يرفض كل طلب من النسخة العامّة 1.2.46 التي لا تحمل '
            'الحزمة — انقطاع خدمة لا تحسين أمني. الشرط: انتشار نسخة تحمل '
            'App Check وبلوغ الطلبات المُوثَّقة ~١٠٠٪ في لوحة Firebase. '
            'إن تحقّق فحدِّث هذا الحارس وCLAUDE.md معاً، لا تُعطّله.',
      );
    });

    test('الشرط موثَّق حيث يُقرأ — لا في رسالة التزام تُنسى', () {
      expect(_read('CLAUDE.md'), contains('App Check'));
      expect(_read('production_deployment_guide.md'), contains('App Check'));
    });
  });
}
