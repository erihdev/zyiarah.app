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
      // **النطاقُ هو نداءُ النشرِ وحدَه، لا الملفُّ كلُّه.** نصُّ رسالةِ
      // الفشلِ (خطوةُ «Surface the failure») يَشرحُ القرارَ بتسميةِ العلمِ
      // في `echo` — وهو **شفرةٌ لا تعليق**، فالتجريدُ لا يَحجبُه وسقطَ
      // الفحصُ على رسالةٍ شرحيّة. وهو الفخُّ المسجَّلُ أحدَ عشرَ مرّةً في
      // هذه الجلسة، بثوبٍ جديد: المحظورُ لم يَظهرْ في تعليقٍ بل في نصٍّ
      // يُطبَع. والعلمُ في أيِّ موضعٍ آخرَ غيرُ ضارّ؛ الضارُّ أن يكونَ في
      // النداء.
      final iDep = wf.indexOf('- name: Deploy');
      expect(iDep, greaterThan(-1), reason: 'خطوةُ النشرِ اختفت');
      final nextStep = wf.indexOf('      - name:', iDep + 10);
      final deployStep =
          wf.substring(iDep, nextStep < 0 ? wf.length : nextStep);
      expect(deployStep.contains('firebase-tools'), isTrue,
          reason: 'الاقتطاعُ لم يُصِب نداءَ النشر — فحصٌ أجوف');
      expect(deployStep.contains('--force'), isFalse,
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

    // ── فشلٌ غيرُ قابلٍ للتشخيص (2026-10-05) ─────────────────────────
    //
    // ثلاثُ دمجاتٍ متتاليةٍ فشلت عند خطوةِ `Deploy` بينما `lint` و`npm test`
    // وكتابةُ المفتاحِ خضراء — فبقيت إصلاحاتُ ذلك اليومِ الخادميّةُ
    // **مدمَجةً وغيرَ عاملة**، وهي الحفرةُ التي وُجد هذا السيرُ لسدِّها،
    // مفتوحةً بعلامةٍ حمراءَ بدلَ لا شيء. والسببُ لم يُعرَف لأنّ سجلَّ
    // التشغيلِ **لا يُقرأُ إلّا من الواجهة** (يُخدَمُ من مُضيفٍ آخر، و
    // `check-runs` تُعيدُ `output` فارغاً) — فالفشلُ كان بلا أثرٍ مقروء.
    test('وفشلُ النشرِ يَترُكُ أثراً مقروءاً — لا علامةً حمراءَ وحدَها', () {
      // **المُجرَّدُ لا الخامّ**: التعليقاتُ أدناه تُسمّي `pipefail` و`tee`
      // لتَشرحَ القرار، فالفحصُ على الخامِّ يَمرُّ على توثيقِه هو — الفخُّ
      // المسجَّلُ في رأسِ هذا الملفِّ، مقلوباً: هنا الأثرُ **إيجابيٌّ** فلا
      // يَكفي الحضورُ في تعليق.
      expect(code.contains('if: failure()'), isTrue,
          reason: 'لا خطوةَ تَنشرُ سببَ الفشل');
      expect(code.contains(r'$GITHUB_STEP_SUMMARY'), isTrue,
          reason: 'السببُ لا يَظهرُ في ملخَّصِ الوظيفة');
      expect(code.contains('::error::'), isTrue,
          reason: 'لا تنبيهات — وهي الطريقُ الوحيدُ لقراءةِ السببِ عبر الـAPI');
      expect(code.contains(r'tee "$RUNNER_TEMP/deploy.log"'), isTrue,
          reason: 'خَرْجُ النشرِ لا يُحفَظُ فلا شيءَ يُنشَر');
      // **`pipefail` حاملٌ لا زينة**: بلاهُ يَحجبُ `tee` خروجَ `firebase`
      // فيَمرُّ فشلُ النشرِ **أخضرَ** — أسوأُ من الفشلِ نفسِه.
      expect(code.contains('set -o pipefail'), isTrue,
          reason: 'بلا pipefail يُخفي tee فشلَ النشرِ فيَمرُّ أخضر');
      // والمَخرَجُ اليدويُّ مكتوبٌ حيث يُقرأُ عند الفشل.
      expect(code.contains('npm --prefix functions run deploy'), isTrue,
          reason: 'لا مَخرَجَ يدويٌّ في رسالةِ الفشل');
      // وترتيبُ الخطوات: النشرُ، فالنشرُ على الملخَّص، فمحوُ المفتاح.
      final iDeploy = wf.indexOf('- name: Deploy');
      final iSurface = wf.indexOf('- name: Surface the failure');
      final iRemove = wf.indexOf('- name: Remove key');
      expect(iDeploy, greaterThan(-1));
      expect(iSurface, greaterThan(iDeploy));
      expect(iRemove, greaterThan(iSurface),
          reason: 'محوُ المفتاحِ يَجبُ أن يَبقى الأخيرَ وبـif: always()');
    });

    // ── والقاعدةُ عامّةٌ: ثلاثةُ مساراتِ نشرٍ لا واحد ────────────────────
    //
    // النمطُ الذي تَكرّر في هذه الجلسةِ مرّاتٍ: قاعدةٌ عامّةٌ مُنفَّذةٌ في
    // سطحٍ واحد. فحينَ صارَ فشلُ نشرِ الدوالِّ مقروءاً، كان مسارا نشرِ
    // اللوحةِ والفهارسِ على العطلِ نفسِه — علامةٌ حمراءُ بلا سبب. والثلاثةُ
    // تَكتبُ في الإنتاج، فالقاعدةُ تَلزمُها جميعاً.
    test('المساراتُ الثلاثةُ كلُّها تَترُكُ أثراً مقروءاً عند الفشل', () {
      const paths = [
        '.github/workflows/functions_deploy.yml',
        '.github/workflows/admin_deploy.yml',
        '.github/workflows/firestore_indexes_deploy.yml',
      ];
      for (final f in paths) {
        // كلُّ ملفٍّ يُجرَّدُ من تعليقِه: هذه فحوصٌ **إيجابيّةٌ**، فحضورُ
        // الاسمِ في شرحٍ لا يَكفي.
        final src = File(f)
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('#'))
            .join('\n');
        expect(src.contains('if: failure()'), isTrue,
            reason: '$f: لا خطوةَ تَنشرُ سببَ الفشل');
        expect(src.contains(r'$GITHUB_STEP_SUMMARY'), isTrue,
            reason: '$f: السببُ لا يَظهرُ في ملخَّصِ الوظيفة');
        expect(src.contains('::error::'), isTrue,
            reason: '$f: لا تنبيهات — وهي طريقُ قراءةِ السببِ عبر الـAPI');
        expect(src.contains('set -o pipefail'), isTrue,
            reason: '$f: بلا pipefail يُخفي tee فشلَ النشرِ فيَمرُّ أخضر');
        expect(src.contains(r'tee "$RUNNER_TEMP/deploy.log"'), isTrue,
            reason: '$f: خَرْجُ النشرِ لا يُحفَظُ فلا شيءَ يُنشَر');
      }
      // والفهارسُ وحدَها: لا قواعدَ من الأتمتةِ بحال (حجزُ STAGE-C).
      final idx = File(paths[2]).readAsStringSync();
      expect(idx.contains('firestore:rules'), isFalse,
          reason: 'نشرُ القواعدِ من الأتمتةِ ممنوعٌ — حجزُ STAGE-C');
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
