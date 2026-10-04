import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نشرُ الدوالّ آليّاً — `.github/workflows/functions_deploy.yml`.
///
/// **السبب:** لا شيء كان ينشر الدوالّ. تسعُ دمجاتٍ في يومٍ واحد، سبعٌ منها
/// خادميّة — منها دفنُ طلبٍ مدفوع تعذّر استردادُه، وتجاوزٌ صامتٌ لطلبٍ وافقت
/// عليه تمارا، وعطلُ الإلغاء في ميسر — بقيت **مدمَجةً وغيرَ عاملة**، لأنّ
/// `firebase deploy` لم يكن إلّا أمراً يكتبه المالكُ بيده في طرفيّته.
///
/// ما يحرسه هذا الملفّ ليس وجودَ الملفّ بل القراراتِ التي فيه.
void main() {
  final String wf =
      File('.github/workflows/functions_deploy.yml').readAsStringSync();

  /// الملفُّ بلا أسطر التعليق. الملفُّ يشرح قرارَه بذكر `--force` في رأسه،
  /// فأوّلُ نسخةٍ من هذا الحارس سقطت على **توثيقه هو**. والتجريدُ وحده يكفي
  /// لتفريغ الحارس، فيتبعه فحصٌ يثبت أنّ الاسم ما يزال في النصّ الخام.
  final String code = wf
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  group('نشرُ الدوالّ آليّاً', () {
    test('يعمل عند الدمج إلى main، ومحصورٌ بما يمسّ الدوالّ', () {
      expect(wf.contains('branches: [main]'), isTrue);
      expect(wf.contains("- 'functions/**'"), isTrue,
          reason: 'دمجةٌ لا تمسّ الدوالّ لا تستحقّ نشراً');
      expect(wf.contains("- 'firebase.json'"), isTrue,
          reason: 'إعدادُ الدوالّ نفسه يُغيّر ما يُنشَر');
      expect(wf.contains('workflow_dispatch:'), isTrue,
          reason: 'لا بدّ من مخرجٍ يدويّ حين يفشل النشر الآلي');
    });

    test('لا يُنشَر ما لم يُختبَر — في هذا المسار نفسه', () {
      final int lint = wf.indexOf('run: npm run lint');
      final int unit = wf.indexOf('run: npm test');
      final int deploy = wf.indexOf('firebase-tools@15 deploy');
      expect(lint, greaterThan(0), reason: 'بلا lint');
      expect(unit, greaterThan(0), reason: 'بلا اختبارات');
      expect(deploy, greaterThan(0), reason: 'بلا نشر');
      expect(unit, lessThan(deploy),
          reason: 'الاختباراتُ قبل النشر لا بعده — وإلّا نُشر ما يفشل');
      expect(lint, lessThan(deploy));
    });

    test('بلا --force: حذفُ دالّةٍ قرارٌ بشريّ لا أثرٌ جانبيّ', () {
      expect(wf.contains('--non-interactive'), isTrue,
          reason: 'سؤالٌ تفاعليٌّ في CI يعني تعليقاً حتى المهلة');
      expect(code.contains('--force'), isFalse,
          reason: '`--force` يوافق تلقائياً على **حذف** دوالّ غابت عن الشيفرة '
              '— فمسحُ ملفٍّ سهواً يمحوها من الإنتاج بلا سؤال');
      expect(wf.contains('--force'), isTrue,
          reason: 'القرارُ موثَّقٌ في رأس الملفّ؛ غيابُه من النصّ الخام يعني '
              'أنّ التجريد ابتلع أكثر ممّا يجب وأنّ الفحصَ أعلاه أجوف');
      expect(wf.contains('--only functions'), isTrue,
          reason: 'لا تُنشَر القواعدُ ولا الاستضافةُ من هذا المسار');
      expect(wf.contains('--project zyiarah-app'), isTrue,
          reason: 'المشروعُ صريحٌ — لا يُستنتج من بيئةٍ قد تتغيّر');
    });

    test('المفتاحُ من سرِّ المستودع، لا من الشيفرة، ويُمحى بعدها', () {
      expect(wf.contains(r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'), isTrue);
      expect(wf.contains('GOOGLE_APPLICATION_CREDENTIALS='), isTrue);
      expect(wf.contains('if: always()'), isTrue,
          reason: 'المفتاحُ يُمحى حتى إن فشل النشر');
      expect(wf.contains('rm -f'), isTrue);
      // سرٌّ ناقصٌ يجب أن يفشل برسالةٍ مفهومة، لا أن يصل إلى firebase فيقول
      // «Failed to authenticate» بعد دقائق من التثبيت والاختبار.
      expect(wf.contains('::error::'), isTrue,
          reason: 'سرٌّ ناقصٌ يفشل مبكراً برسالةٍ واضحة');
    });

    test('نشرتان لا تتزاحمان', () {
      expect(wf.contains('concurrency:'), isTrue);
      expect(wf.contains('cancel-in-progress: false'), isTrue,
          reason: 'إلغاءُ نشرٍ في منتصفه يترك الدوالّ نصفَ منشورة');
    });

    test('Node 22 — نفسُ ما تُشغَّل عليه الدوالّ', () {
      expect(wf.contains("node-version: '22'"), isTrue);
      final String pkg = File('functions/package.json').readAsStringSync();
      expect(pkg.contains('"node": "22"'), isTrue,
          reason: 'إن تغيّر محرّكُ الدوالّ فليتغيّر معه محرّكُ النشر');
    });

    test('لا مفتاحَ مكتوبٌ في المستودع', () {
      expect(wf.contains('BEGIN PRIVATE KEY'), isFalse);
      expect(wf.contains('"private_key"'), isFalse);
      final List<String> keys = Directory('.')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) =>
              p.contains('adminsdk') ||
              p.contains('service-account') ||
              p.endsWith('.p8'))
          .toList();
      expect(keys, isEmpty,
          reason: 'مفتاحُ خدمةٍ في جذر المستودع: ${keys.join(", ")}');
    });
  });
}
