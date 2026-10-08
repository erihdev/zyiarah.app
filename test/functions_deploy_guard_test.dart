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
/// مساراتُ النشرِ في المستودعِ — مُشتَقّةٌ لا مكتوبة. قائمةٌ يدويّةٌ
/// تَتخلّفُ عن هدفٍ جديدٍ بصمت، وهو ما جرى لهدفِ `web` (صفحةُ الهبوط).
List<String> _deployWorkflowFiles() => Directory('.github/workflows')
    .listSync()
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('_deploy.yml'))
    .toList()
  ..sort();

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

  /// جسمُ خطوةٍ **بلا تعليقات**. حدُّ الخطوةِ هو سطرُ اسمِ التاليةِ،
  /// وتعليقاتُ YAML للتاليةِ تَسكنُ **فوقَ** ذلك السطرِ — فتَقعُ في شريحةِ
  /// السابقة. وهذا الملفُّ يَشرحُ قراراتَه بذكرِ `--force` و`functions:list`
  /// في تلك التعليقاتِ بعينِها، فكلُّ فحصٍ موجَبٍ هنا كان يُرضيه **شرحٌ** لا
  /// شفرة: يَمُرُّ أخضرَ على نداءٍ زالَ منه العلَم. (الفحصُ الجديدُ في
  /// `firestore_indexes_guard_test` هو ما كشفَ الحدَّ، لأنّ دعواهُ سالبة.)
  String stepCode(String name) {
    final int i = wf.indexOf('      - name: $name');
    if (i < 0) return '';
    final int next = wf.indexOf('      - name:', i + 10);
    return wf
        .substring(i, next < 0 ? wf.length : next)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');
  }

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

    test('«لا حذفَ صامتاً» حارسٌ صريحٌ يَسبقُ النشرَ، لا غيابُ علَم', () {
      expect(wf.contains('--non-interactive'), isTrue,
          reason: 'سؤالٌ تفاعليٌّ في CI يعني تعليقاً حتى المهلة');
      // **القرارُ نفسُه لم يَتغيّر؛ ما تغيّرَ هو مَن يُنفّذُه.** كان يُنفَّذُ
      // بغيابِ `--force` — وهي حمايةٌ بالمصادفة: أثرٌ جانبيٌّ لعدمِ التفاعل.
      // ثم تَبيّنَ أنّ `--non-interactive` تَرفضُ كذلك **سياسةَ إعادةِ
      // المحاولةِ** (`retry: true` على مُعالِجَي طابورَي الإشعارات، وهي
      // مقصودة) إلّا بـ`--force`، فتَوقّفَ النشرُ كلُّه: كلُّ تشغيلٍ منذ
      // دمجِ الطابورِ المنفصلِ فشلَ برسالةٍ واحدة، وبقيت الإصلاحاتُ
      // الخادميّةُ مدمَجةً وغيرَ عاملة — وهي الحفرةُ التي كُتب هذا السيرُ
      // لسدِّها. فالحمايةُ صارت خطوةً تَقولُ ما تَحرُس، وتَسبقُ النشر.
      final iGuard = wf.indexOf('- name: Refuse a silent deletion');
      final iDep = wf.indexOf('- name: Deploy');
      expect(iGuard, greaterThan(-1),
          reason: 'حارسُ الحذفِ اختفى — و`--force` بلاهُ يَحذفُ صامتاً');
      expect(iDep, greaterThan(-1), reason: 'خطوةُ النشرِ اختفت');
      expect(iGuard, lessThan(iDep),
          reason: 'الحارسُ **بعدَ** النشرِ لا يَحرُسُ شيئاً');

      final deployStep = stepCode('Deploy');
      expect(deployStep.contains('firebase-tools'), isTrue,
          reason: 'الاقتطاعُ لم يُصِب نداءَ النشر — فحصٌ أجوف');
      // و`--force` مشروطٌ لا مباح: مسموحٌ **لأنّ** الحارسَ أعلاه أثبتَ أنّ لا
      // حذفَ معلَّقاً. فلو زالَ الحارسُ سقطَ الفحصُ أعلاه.
      expect(deployStep.contains('--force'), isTrue,
          reason: 'بلا `--force` يَرفضُ النشرُ سياسةَ إعادةِ المحاولةِ فيَتوقّفُ '
              'كلُّ نشرٍ — وهو العطلُ الذي عطّلَ سبعةَ تشغيلاتٍ متتالية');
      expect(deployStep.contains('--only functions'), isTrue,
          reason: 'لا تُنشَر القواعدُ ولا الاستضافةُ من هذا المسار');
      expect(deployStep.contains('--project zyiarah-app'), isTrue,
          reason: 'المشروعُ صريحٌ — لا يُستنتج من بيئةٍ قد تتغيّر');
    });

    test('والحارسُ يَقرأُ المنشورَ فعلاً، ويَفشلُ مُغلَقاً', () {
      final step = stepCode('Refuse a silent deletion');
      expect(step.contains('functions:list'), isTrue,
          reason: 'الحارسُ لا يَقرأُ ما هو منشورٌ فعلاً — فلا يَعرفُ ما يُحذَف');
      expect(step.contains('--json'), isTrue,
          reason: 'صيغةٌ غيرُ مستقرّةٍ تُحلَّلُ خطأً فتُقرأُ «لا شيءَ يُحذَف»');
      expect(step.contains('.github/scripts/refuse_deletion.py'), isTrue,
          reason: 'المُحلِّلُ في ملفٍّ لا heredoc — التداخلُ أفسدَ YAML من قبل');

      // والمُحلِّلُ نفسُه: قدرةٌ لا وجودٌ. **حارسٌ مجوَّفٌ هو ما لم يَقضم في
      // كاشفِ الانحراف** حين كان الفحصُ `existsSync` وحدَه.
      final g = File('.github/scripts/refuse_deletion.py').readAsStringSync();
      expect(g.contains('def deployed_ids('), isTrue);
      expect(g.contains('def source_exports('), isTrue);
      expect(g.contains(r"r'^exports\.([A-Za-z_][A-Za-z0-9_]*)\s*='") ||
              g.contains(r'exports\.([A-Za-z_][A-Za-z0-9_]*)'), isTrue,
          reason: 'لا يَستخرجُ تصديراتِ المصدر — فالمقارنةُ بلا طرف');
      expect(g.contains('n.lower() not in src_lc'), isTrue,
          reason: 'الاتّجاهُ مهمّ: المنشورُ ناقصاً المصدرَ هو الحذفُ المعلَّق');
      // **والمقارنةُ بحروفٍ صغيرةٍ لازمة، لا تجميل.** دوالُّ الجيلِ الثاني
      // تَسكنُ خدماتَ Cloud Run وأسماؤها هناك صغيرة، فاختلافُ حالةِ حرفٍ
      // يَجعلُ كلَّ دالّةٍ تُقرأُ «منشورةٌ وغائبةٌ عن المصدر» فيُحجَبُ النشرُ
      // كلُّه — عطلٌ أسوأُ من الذي يُصلِحُه الحارسُ نفسُه.
      expect(g.contains('src_lc = {n.lower(): n for n in src_names}'), isTrue,
          reason: 'زالت المقارنةُ غيرُ الحسّاسةِ للحالة — تَحجبُ كلَّ نشر');
      // ولو فشلَ، يُطبَعُ الطرفانِ كاملَين فيُشخَّصُ من التنبيهِ بلا دورةٍ أخرى.
      expect(g.contains('المنشورةُ كما قرأناها'), isTrue,
          reason: 'فشلٌ بلا الطرفَين يَلزمُه دورةٌ أخرى لِيُشخَّص');
      // يَفشلُ مُغلَقاً، و**كلُّ فرعٍ مُسمّى بنصِّه**. اختبارُ قضمٍ لم يَقضم
      // كشفَ أنّ عبارةً مشترَكةً وعتبةَ عَدٍّ لا تَكفيان: حذفُ فرعِ «تعذّرَ
      // التحليل» وحدَه مرَّ أخضرَ لأنّ العبارةَ ترِدُ مرّتَين و`return 1`
      // بَقيَ فوقَ العتبة. فالفروعُ تُسمّى واحداً واحداً.
      const closedBranches = {
        'تعذّر قراءةُ مُدخلِ الحارس': 'تعذّرُ قراءةِ المُدخل',
        'تعذّر تحليلُ قائمةِ الدوالِّ المنشورة': 'قائمةٌ غيرُ مقروءة',
        'لم يُعثَرْ على أيِّ `exports.` في المصدر': 'مصدرٌ بلا تصدير',
        'النشرُ سيَحذفُ من الإنتاج': 'حذفٌ معلَّق',
      };
      for (final e in closedBranches.entries) {
        expect(g.contains(e.key), isTrue,
            reason: 'فرعُ الفشلِ «${e.value}» زال — فالحارسُ يَفشلُ مفتوحاً '
                'في تلك الحالة، أي يُجيزُ `--force` بلا علمٍ بما يُحذَف');
      }
      expect(RegExp(r'return 1').allMatches(g).length,
          greaterThanOrEqualTo(closedBranches.length + 1),
          reason: 'مَخارجُ الفشلِ أقلُّ من الفروعِ المُسمّاةِ + فحصِ الوسائط');
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

    // ── والقاعدةُ عامّةٌ: كلُّ مسارِ نشرٍ لا واحد ─────────────────────────
    //
    // النمطُ الذي تَكرّر في هذه الجلسةِ مرّاتٍ: قاعدةٌ عامّةٌ مُنفَّذةٌ في
    // سطحٍ واحد. فحينَ صارَ فشلُ نشرِ الدوالِّ مقروءاً، كان مسارا نشرِ
    // اللوحةِ والفهارسِ على العطلِ نفسِه — علامةٌ حمراءُ بلا سبب. وكلُّها
    // تَكتبُ في الإنتاج، فالقاعدةُ تَلزمُها جميعاً.
    //
    // **والقائمةُ مُشتَقّةٌ لا مكتوبة**، وذلك ليس تجميلاً: كانت ثلاثةَ أسماءٍ
    // مكتوبةٍ بيدٍ، وهدفُ `web` (صفحةُ الهبوط) رابعٌ — فلو أُضيفَ سيرُه بلا
    // تعديلِ هذه القائمةِ لَمَرَّ بلا أثرٍ مقروءٍ عند الفشل، وهو العطلُ
    // نفسُه الذي يَحرُسُه هذا الفحص.
    test('كلُّ مساراتِ النشرِ تَترُكُ أثراً مقروءاً عند الفشل', () {
      final paths = _deployWorkflowFiles();
      expect(paths.length, greaterThanOrEqualTo(4),
          reason: 'مساراتُ النشرِ ${paths.length} — زالَ هدفٌ، وزوالُه قرارٌ '
              'يُراجَعُ لا يَمُرُّ صمتاً');
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
      // تُسمَّى بملفِّها لا بموضعِها في القائمة، فالقائمةُ صارت مُشتَقّةً.
      const idxFile = '.github/workflows/firestore_indexes_deploy.yml';
      expect(paths, contains(idxFile),
          reason: 'سيرُ الفهارسِ اختفى — ومعه الفحصُ الذي يَمنعُ نشرَ القواعد');
      final idx = File(idxFile).readAsStringSync();
      expect(idx.contains('firestore:rules'), isFalse,
          reason: 'نشرُ القواعدِ من الأتمتةِ ممنوعٌ — حجزُ STAGE-C');
      // ولا هدفَ آخرَ يَنشرُ القواعدَ من الباب الخلفيّ.
      for (final f in paths) {
        final src = File(f).readAsStringSync();
        expect(src.contains('firestore:rules'), isFalse,
            reason: '$f: نشرُ القواعدِ من الأتمتةِ ممنوعٌ — حجزُ STAGE-C');
        expect(RegExp(r'--only\s+firestore\s').hasMatch(src), isFalse,
            reason: '$f: `--only firestore` العاريةُ تَشملُ القواعد');
      }
    });

    // ── كاشفُ الانحراف: الالتزامُ بالتشغيلِ اليدويِّ صارَ فحصاً ────────
    //
    // علامةُ `[skip ci]` مفتاحٌ واحدٌ فوقَ شيئَين: تَمنعُ بناءَ Codemagic —
    // وهو استعمالُها المقصودُ أحياناً (دفعةٌ أثناء مراجعةِ آبل تُعيدُ
    // المراجعةَ من الصفر) — **وتَمنعُ كذلك مساراتِ النشرِ الثلاثة**. وفي
    // 2026-10-05 حمَلَ ثلاثةَ عشَرَ دمجاً العلامةَ عن قصد، فلم يَجرِ لها
    // نشرٌ قطّ؛ وثلاثةٌ نظيفةٌ جرى لها النشرُ وفشل. فبلغَ المتروكُ **ستّةً
    // وعشرينَ التزاماً** تَمسُّ `functions/**` مدمَجةً غيرَ منشورة.
    //
    // والالتزامُ بتشغيلِ المساراتِ يدويّاً بعدَ دمجٍ بعلامةٍ كان **مكتوباً
    // في CLAUDE.md ويَعتمدُ على الذاكرةِ وحدَها** — وهو ما سقط. فصارَ فحصاً
    // مجدولاً: `schedule` و`workflow_dispatch` **لا تَكبِتُهما العلامة**.
    test('كاشفُ الانحرافِ يَشتقُّ أهدافَه كلَّها ولا يَنشرُ بنفسِه', () {
      const drift = '.github/workflows/deploy_drift.yml';
      expect(File(drift).existsSync(), isTrue,
          reason: 'كاشفُ الانحرافِ اختفى — فالالتزامُ عادَ إلى الذاكرة');
      final d = File(drift).readAsStringSync();
      final dCode = d
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');

      // (أ) يُغطّي **كلَّ** مسارِ نشرٍ في المستودع — **باشتقاقٍ لا بقائمة**.
      //     كانت قائمةَ ثلاثةِ أسماءٍ مكتوبةٍ في حلقةِ الشِّل، فتَخلّفت عن
      //     هدفِ `web` (صفحةُ الهبوط) الذي لم يَكن له سيرٌ أصلاً: هدفٌ
      //     بلا نشرٍ آليٍّ وبلا كاشفٍ يَراه. فالحلقةُ تَدورُ على
      //     `*_deploy.yml` وتَفشلُ على عددٍ أقلَّ من الحدّ.
      final deployWorkflows = _deployWorkflowFiles()
          .map((p) => p.split('/').last.replaceAll('.yml', ''))
          .toSet();
      expect(deployWorkflows.length, greaterThanOrEqualTo(4),
          reason: 'لم تُعثَر مساراتُ النشر — فحصٌ أجوف');
      expect(dCode.contains('.github/workflows/*_deploy.yml'), isTrue,
          reason: 'الكاشفُ لا يَشتقُّ أهدافَه — فهدفٌ جديدٌ يَبقى خارجَه بصمت');
      expect(dCode.contains(r'basename "$f" .yml'), isTrue,
          reason: 'الكاشفُ لا يَستخرِجُ اسمَ السيرِ من ملفِّه');
      expect(RegExp(r'-lt 3').hasMatch(dCode), isTrue,
          reason: 'الكاشفُ بلا حدٍّ أدنى — فقائمةٌ فارغةٌ تُقرأُ «لا انحراف»');
      // ولا اسمَ هدفٍ مكتوبٌ في شفرتِه: نسخةٌ ثانيةٌ تَنحرِف. (على المُجرَّدِ
      // لأنّ تعليقَه يُسمّي `functions_deploy.yml` وهو يَحكي سببَه.)
      for (final w in deployWorkflows) {
        expect(dCode.contains(w), isFalse,
            reason: 'اسمُ $w مكتوبٌ في شفرةِ الكاشفِ — والقائمةُ المكتوبةُ '
                'هي ما تَخلّفَ عن هدفِ web');
      }
      // والفحصُ أعلاه سالبٌ، فيَلزمُه إثباتُ أنّ المُجرَّدَ شفرةٌ لا فراغ —
      // وإلّا كان «لا اسمَ فيه» صحيحاً عن ملفٍّ خالٍ. (أوّلُ صياغةٍ أسندَته
      // إلى تعليقٍ يُسمّي `functions_deploy.yml` وهو تعليقٌ **ليس في
      // الملفّ** — ادّعاءٌ عن توثيقٍ لم أقرأه، فأُسنِدَ إلى شفرةٍ حقيقيّة.)
      expect(dCode.contains(r'gh api "repos/$REPO/actions/workflows/'), isTrue,
          reason: 'المُجرَّدُ لا يَحملُ نداءَ الـAPI — فالتجريدُ أكلَ الشفرةَ '
              'والفحصُ السالبُ أعلاه يَقرأُ فراغاً');
      expect(dCode.contains('for f in'), isTrue,
          reason: 'المُجرَّدُ بلا حلقةٍ — الفحصُ السالبُ أجوف');

      // (ب) ولا يَنشرُ بنفسِه: الحجبُ قد يكونُ مقصوداً (مراجعةُ آبل،
      //     حجزُ STAGE-C) فالقرارُ بشريّ.
      expect(dCode.contains('firebase'), isFalse,
          reason: 'الكاشفُ صارَ يَنشر — وذاك يَتجاوزُ حجباً قد يكونُ مقصوداً');
      expect(dCode.contains('exit 1'), isTrue,
          reason: 'لا يَفشلُ عند الانحراف — فلا يَصلُ بريدُ إشعارٍ لأحد');

      // (ج) ومُحرِّكُه لا تَكبِتُه العلامة: لا `push` فيه بحال.
      expect(dCode.contains('schedule:'), isTrue);
      expect(dCode.contains('workflow_dispatch:'), isTrue);
      expect(RegExp(r'^\s+push:', multiLine: true).hasMatch(dCode), isFalse,
          reason: 'مُحرِّكُ push تَكبِتُه العلامةُ نفسُها — فالكاشفُ يَصمتُ '
              'في الحالةِ التي وُجد لها بعينِها');

      // (د) ومساراتُ كلِّ هدفٍ تُقرأُ من ملفِّ سيرِه لا تُكتَبُ ثانيةً.
      // **قدرةٌ لا وجود**: أوّلُ صياغةٍ قالت `existsSync()` وحدَها،
      // واختبارُ قضمٍ أجوَفَ الملفَّ إلى سطرٍ واحدٍ **فمرَّ أخضر** — وهو
      // درسُ هذه الجلسةِ بعينِه (المقارنةُ على الأسماءِ لا على القدرة).
      final reader = File('.github/scripts/deploy_paths.py');
      expect(reader.existsSync(), isTrue, reason: 'قارئُ المساراتِ اختفى');
      final r = reader.readAsStringSync();
      expect(r.contains('def push_paths('), isTrue,
          reason: 'القارئُ بلا دالّةِ الاستخراج — الكاشفُ أعمى عن كلِّ هدف');
      expect(r.contains('paths:'), isTrue,
          reason: 'لا يَقرأُ كتلةَ paths أصلاً');
      expect(r.contains('sys.exit(1)'), isTrue,
          reason: 'لا يَفشلُ على قائمةٍ فارغة — فيَقرأُ الكاشفُ «لا انحراف» '
              'عن هدفٍ لم يَستخرِجْ مساراتَه');
      expect(dCode.contains('deploy_paths.py'), isTrue,
          reason: 'الكاشفُ يَحملُ نسخةً ثانيةً من المسارات — وهي تَنحرِف');
      // ولكلِّ هدفٍ كتلةُ `paths:` فيها مدخلٌ واحدٌ على الأقلّ، وإلّا
      // أعادَ القارئُ فراغاً وصارَ الكاشفُ أعمى عنه.
      for (final w in deployWorkflows) {
        final src = File('.github/workflows/$w.yml').readAsStringSync();
        final i = src.indexOf('paths:');
        expect(i, greaterThan(-1), reason: '$w: لا كتلةَ paths');
        expect(RegExp(r"\n\s+- '[^']+'").hasMatch(src.substring(i)), isTrue,
            reason: '$w: كتلةُ paths بلا مدخلٍ مُقتبَس — القارئُ يُعيدُ فراغاً');
      }
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
