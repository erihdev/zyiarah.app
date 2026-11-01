import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارس مسار المختبرين على أندرويد (Firebase App Distribution) — 2026-09-28.
///
/// السياق: منذ صار `track: production` (2026-09-21) لم يعد أيّ بناء أندرويد
/// يصل مختبراً قبل الجمهور. المسار البديل هو App Distribution، وكان
/// `distribute_android.bat` معطّلاً بثلاثة أعطاب كامنة: App ID مكتوب يدوياً
/// لتطبيق قديم (com.zyiarah.app) بينما التطبيق الفعلي com.zyiarah.zyiarah —
/// فأيّ رفع يُرفض لعدم تطابق الحزمة؛ وقراءة `testers.txt` غير الموجود؛ وتمرير
/// `--clean` الذي لا يعرفه `flutter build`.
///
/// الحارس يشتقّ App ID الصحيح من google-services.json عبر applicationId في
/// Gradle، ويُلزم به السكربت المحلّي وسير عمل Codemagic معاً — حتى لا يفترق
/// الثلاثة مرة أخرى بلا أن يحمرّ CI.
void main() {
  String read(String p) => File(p).readAsStringSync();
  String read_(String p) => read(p);

  final gradle = File('android/app/build.gradle.kts').existsSync()
      ? read('android/app/build.gradle.kts')
      : read('android/app/build.gradle');
  final packageName =
      RegExp(r'applicationId\s*=?\s*"([^"]+)"').firstMatch(gradle)!.group(1)!;

  final gs =
      jsonDecode(read('android/app/google-services.json')) as Map<String, dynamic>;
  final client = (gs['client'] as List).cast<Map<String, dynamic>>().firstWhere(
      (c) => c['client_info']['android_client_info']['package_name'] == packageName,
      orElse: () => throw StateError(
          'google-services.json لا يحوي عميلاً للحزمة $packageName'));
  final firebaseAppId = client['client_info']['mobilesdk_app_id'] as String;

  test('google-services.json يربط applicationId بتطبيق Firebase واحد محدّد', () {
    expect(packageName, 'com.zyiarah.zyiarah');
    expect(firebaseAppId, startsWith('1:275681992607:android:'));
  });

  test('distribute_android.bat: App ID الصحيح + مجموعة testers، بلا testers.txt ولا --clean',
      () {
    final bat = read('distribute_android.bat');
    expect(bat.contains('set APP_ID=$firebaseAppId'), isTrue,
        reason: 'App ID في السكربت لا يطابق تطبيق $packageName في google-services.json');
    expect(bat.contains('--groups testers'), isTrue,
        reason: 'الرفع يذهب إلى مجموعة App Distribution «testers» لا إلى ملف بريد');
    expect(bat.contains('--testers-file'), isFalse,
        reason: 'testers.txt غير موجود في المستودع — المجموعة هي المصدر الوحيد');
    expect(RegExp(r'flutter build apk[^\n]*--clean').hasMatch(bat), isFalse,
        reason: 'flutter build لا يعرف --clean؛ نظّف بـ flutter clean قبله');
  });

  test('codemagic.yaml: كل بناء أندرويد يوزّع APK بنفس versionCode إلى مجموعة testers',
      () {
    final cm = read('codemagic.yaml');
    expect(cm.contains(r'flutter build apk --release --build-number=$NEW_CODE'), isTrue,
        reason: 'APK المختبرين يحمل رقم الإصدار نفسه الذي يذهب إلى Play');
    expect(cm.contains('build/app/outputs/flutter-apk/*.apk'), isTrue,
        reason: 'الـAPK يجب أن يكون ضمن artifacts');
    expect(cm.contains(r'firebase_service_account: $GCLOUD_SERVICE_ACCOUNT_CREDENTIALS'),
        isTrue,
        reason: 'حساب خدمة Play نفسه — مُنح دور App Distribution Admin في 2026-09-28');
    expect(cm.contains('app_id: $firebaseAppId'), isTrue,
        reason: 'App ID في Codemagic لا يطابق google-services.json');
    expect(RegExp(r'groups:\s*\n\s*- testers').hasMatch(cm), isTrue,
        reason: 'مجموعة App Distribution المستهدفة هي testers');
    expect(cm.contains("artifact_type: 'apk'"), isTrue,
        reason: 'توزيع AAB يشترط ربط Firebase بـPlay وهو غير مُعدّ — APK هو المسار');
  });

  test('codemagic.yaml: أندرويد ينشر إلى المسار المغلق (alpha) حتى يُمنح الوصول إلى الإنتاج',
      () {
    // شرط Play للحساب الشخصي: ١٢ مختبراً مشتركين في الاختبار المغلق ١٤ يوماً
    // متواصلة قبل منح الإنتاج — ولا يُحتسب إلا من ثبّت من Play (لا من Firebase).
    // إعادة هذا السطر إلى production قرارُ مالكٍ بعد منح الوصول: حدّث الحارس معه عمداً.
    final cm = read('codemagic.yaml');
    expect(
        RegExp(r'google_play:\s*\n\s*credentials: \$GCLOUD_SERVICE_ACCOUNT_CREDENTIALS\s*\n\s*track: alpha')
            .hasMatch(cm),
        isTrue,
        reason: 'مسار Play يجب أن يكون alpha (المغلق) لا production حتى يُمنح الوصول إلى الإنتاج');
  });

  // ════════════════════════════════════════════════════════════════════
  // **مسارٌ ثانٍ إلى Play، ومفاتيحُ دفعٍ ناقصةٌ فيه (2026-10-05).**
  //
  // `.github/workflows/android_release.yml` يُطلَقُ على وسمِ `v*` — والوسومُ
  // موجودةٌ فعلاً (`v1.2.0` … `v1.2.2+184`) وقد عملَ ثماني مرّات — ويَبني AAB
  // **ويَنشرُه إلى Google Play** (`r0adkll/upload-google-play`, `status:
  // draft`). وهذا الملفُّ (CLAUDE.md) كان يَصفُه «يَبني AAB على وسومِ `v*`
  // **بلا نشر**» — وصفٌ خاطئ.
  //
  // وعطبانِ فيه:
  //   (أ) `echo "MAPBOX_TOKEN=…" > .env` — **مفتاحُ الخريطةِ وحدَه**، و`>`
  //       يَمسحُ ما قبلَه. و`moyasarReady` يَقرأُ `MOYASAR_PUBLISHABLE_KEY`
  //       من `.env`، وعليه مشروطٌ خيارُ **البطاقةِ** و**Apple Pay** كلاهما
  //       في `payment_summary_screen` — فحزمةُ هذا السيرِ تُبنى بلا وسيلةِ
  //       الدفعِ الأساسيّة، والبناءُ ينجحُ أخضرَ. و`ios_release.yml` نفسُه.
  //   (ب) `track: production` بينما `codemagic.yaml` نُقِلَ إلى `alpha` في
  //       2026-09-28 بقرارِ مالكٍ مسجَّل — فدفعُ وسمٍ يَتجاوزُ القرارَ من
  //       البابِ الآخر. والحارسُ القائمُ كان يُثبّتُ `alpha` في
  //       `codemagic.yaml` **وحدَه**: «حارسٌ ضيّقٌ وقاعدةٌ عامّة» مرّةً أخرى.
  //
  // فالفحوصُ التاليةُ **مُشتَقّةٌ**: كلُّ موضعٍ يَنشرُ إلى Play، وكلُّ موضعٍ
  // يَكتبُ `.env` لبناءِ تطبيق — لا قوائمُ مكتوبةٌ بيد.

  /// `.env` **التطبيقِ** بعينِه لا أيَّ `.env*`: أوّلُ صياغةٍ طابقت
  /// `'> .env'` فابتلعت `admin_deploy.yml` وهو يَكتبُ `.env.production`
  /// للوحةِ الويبِ (مفتاحُ Mapbox لـVite) — ملفٌّ آخرُ لمشروعٍ آخر.
  /// ملفّاتُ سِيَرِ GitHub — **الامتدادانِ معاً**: GitHub يَقبلُ `.yml`
  /// و`.yaml`، وأربعُ اشتقاقاتٍ في هذا الملفِّ كانت تُرشِّحُ الأوّلَ وحدَه،
  /// فسيرُ إصدارٍ باسمِ `.yaml` يَخرُجُ من ثلاثةِ حُرّاسٍ معاً (أسرارُ
  /// الكتابة، ومسارُ Play، وversionCode المُشتَقّ). ومعه فحصٌ يُثبّتُ أنّ
  /// كلَّ ملفٍّ في المجلّدِ يَحملُ أحدَهما، فلا امتدادٌ ثالثٌ يَتسلّلُ.
  List<String> workflowFiles() => Directory('.github/workflows')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
      .toList()
    ..sort();

  final appEnvWrite = RegExp(r'>\s*\.env\s*$', multiLine: true);
  List<String> envWriters() => [
        'codemagic.yaml',
        ...workflowFiles()
            .where((f) => appEnvWrite.hasMatch(File(f).readAsStringSync())),
      ]..sort();

  test('مفاتيحُ .env التي يَقرؤها التطبيقُ يَكتبُها كلُّ مَن يَبنيه', () {
    // ما يَقرؤه التطبيق — مُشتَقٌّ من `lib/` لا مكتوبٌ هنا.
    final read = <String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // القراءةُ تَمُرُّ بـ`envOrEmpty` منذ 2026-10-07: `dotenv.env` **يَرمي**
      // حين لا يَنجحُ `load()` فلا تَبلغُه `?? ''` أصلاً. والقاعدةُ المَحروسةُ
      // هنا لم تَتغيّر (كلُّ مَن يَبني يَكتبُ كلَّ مفتاحٍ يَقرؤه `lib/`)،
      // وإنّما شكلُ القراءة — وأرضيّةُ «٣ مفاتيحَ» أدناه هي ما أمسكَ ذلك.
      for (final m in RegExp(r"""(?:envOrEmpty\(|dotenv\.env\[)['"]([A-Z0-9_]+)['"]""")
          .allMatches(f.readAsStringSync())) {
        read.add(m.group(1)!);
      }
    }
    expect(read.length, greaterThanOrEqualTo(3),
        reason: 'لم تُقرأ مفاتيحُ dotenv — الاستخراجُ أخطأ');
    expect(read, contains('MOYASAR_PUBLISHABLE_KEY'),
        reason: 'مفتاحُ ميسر لم يَعُد يُقرأ — راجِعْ سببَ هذا الحارس');

    final writers = envWriters();
    expect(writers.length, greaterThanOrEqualTo(3),
        reason: 'لم تُعثَر مساراتُ البناءِ — فحصٌ أجوف: $writers');
    for (final w in writers) {
      final src = read_(w);
      for (final k in read) {
        // **كتابةٌ لا ذِكر.** أوّلُ صياغةٍ قالت `src.contains(k)` — واختبارُ
        // قضمٍ حذفَ سطرَ `printf` للمفتاح **فمرَّ أخضر**، لأنّ الاسمَ باقٍ في
        // كتلةِ `env:` وفي حارسِ الغياب. فالمطلوبُ سطرُ كتابةٍ فعليٌّ
        // (`printf 'K=…'` أو `echo "K=…"`) لا ظهورُ الاسم. وهو درسُ هذا
        // المستودعِ المتكرّر: المقارنةُ على القدرةِ لا على الأسماء.
        expect(RegExp('(printf|echo)[^\n]*\\b$k=').hasMatch(src), isTrue,
            reason: '\$w لا يَكتبُ \$k في .env — '
                'و`MOYASAR_PUBLISHABLE_KEY` غيابُه يَعني حزمةً بلا بطاقةٍ '
                'ولا Apple Pay، تُبنى خضراءَ وتُرفَعُ إلى المتجر');
      }
    }
  });

  test('وغيابُ مفتاحِ الدفعِ يُفشِلُ الوظيفةَ لا يُكتَبُ فارغاً', () {
    // كان النطاقُ `.github/` وحدَه — و`codemagic.yaml` هو ما يَرفعُ إلى
    // TestFlight وPlay فعلاً، وكان يَكتبُ `echo "K=$K"` فيُنتجُ `K=` على سرٍّ
    // غائبٍ ويَمُرُّ أخضرَ (2026-10-22). النطاقُ الآن كلُّ كاتبٍ لـ.env.
    for (final w in envWriters()) {
      final src = read_(w);
      expect(src.contains(r'if [ -z "$MOYASAR_PUBLISHABLE_KEY" ]'), isTrue,
          reason: '$w: سرٌّ غائبٌ يُكتَبُ فارغاً فتُبنى حزمةٌ بلا دفعٍ بصمت — '
              'نفسُ قرارِ admin_deploy.yml مع MAPBOX_TOKEN');
      expect(src.contains('exit 1'), isTrue, reason: '$w: لا يَفشلُ فعلاً');
    }
  });

  test('كلُّ مسارٍ يَنشرُ إلى Play يَستهدفُ alpha — لا codemagic وحدَه', () {
    final paths = <String>[
      'codemagic.yaml',
      ...workflowFiles()
          .where((f) =>
              File(f).readAsStringSync().contains('upload-google-play') ||
              File(f).readAsStringSync().contains('google_play:')),
    ]..sort();
    expect(paths.length, greaterThanOrEqualTo(2),
        reason: 'لم يُعثَر إلّا على مسارِ نشرٍ واحدٍ — وهو ما أخفى الثاني: '
            '$paths');
    for (final p in paths) {
      final src = read_(p);
      // **المسحُ السالبُ على المُجرَّدِ من التعليقات**: `codemagic.yaml`
      // يَشرحُ القرارَ بذكرِ «track: production» في تعليقِه («أعِده إلى
      // production وحدّث…»)، فأوّلُ صياغةٍ سقطت على توثيقِ المستودعِ
      // نفسِه — الحادي عشَرَ من هذا الفخِّ هنا.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(src.contains('production'), isTrue,
          reason: '\$p: زالَ شرحُ قرارِ المسارِ من التعليق — فالفحصُ '
              'السالبُ أدناه يَقرأُ فراغاً لا شفرة');
      expect(RegExp(r'track:\s*alpha').hasMatch(src), isTrue,
          reason: '$p: مسارُ Play ليس alpha — وشرطُ الـ١٢ مختبراً لم يُمنَح');
      expect(RegExp(r'track:\s*production').hasMatch(code), isFalse,
          reason: '$p: عادَ إلى production — وهو قرارُ مالكٍ بعد منحِ الوصول، '
              'يُحدَّثُ معه هذا الحارسُ عمداً');
    }
  });

  // ════════════════════════════════════════════════════════════════════
  // **versionCode يُشتَقُّ من Play في كلِّ مسارٍ يَنشرُ إليه (2026-10-22).**
  //
  // كان `android_release.yml` يَبني بـ`flutter build appbundle --release`
  // عارياً فيَأخذُ `versionCode` من `pubspec.yaml` — ورقمٌ لا يَتزايدُ يُنتجُ
  // «versionCode مستخدم مسبقاً» عند Play، بينما `codemagic.yaml` يَسألُ Play
  // عن آخرِ رقمٍ ويَزيد. القاعدةُ عامّةٌ فتُشَدُّ على **المجموعةِ المُشتَقّةِ**
  // نفسِها: كلُّ ناشرٍ يُمرّرُ `--build-number` من `get-latest-build-number`،
  // وتعذُّرُ القراءةِ يُفشِلُ (لا `|| echo <رقم>` ولا سقوطٌ صامت في سيرِ GitHub).
  test('كلُّ مسارٍ يَنشرُ إلى Play يَبني بـversionCode مُشتَقٍّ من Play', () {
    final paths = workflowFiles()
        .where((f) => File(f).readAsStringSync().contains('upload-google-play'))
        .toList()
      ..add('codemagic.yaml')
      ..sort();
    expect(paths.length, greaterThanOrEqualTo(2), reason: 'انحلَّ الاشتقاق: $paths');
    for (final p in paths) {
      final code = read_(p)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(code.contains('get-latest-build-number'), isTrue,
          reason: '$p: لا يَسألُ Play عن آخرِ versionCode');
      expect(RegExp(r'build appbundle --release --build-number=').hasMatch(code),
          isTrue,
          reason: '$p: يَبني الحزمةَ بلا --build-number — فالرقمُ من pubspec '
              'ولا يَتزايد');
      expect(RegExp(r'-le 191').hasMatch(code), isTrue,
          reason: '$p: زالَ حارسُ 191 (رُفِعَ مرّةً ولم يُنشَر)');
    }
    // سيرُ GitHub يَفشلُ مُغلَقاً عند تعذّرِ القراءة — لا رقمَ احتياطيّاً.
    final gh = read_('.github/workflows/android_release.yml')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');
    expect(RegExp(r"get-latest-build-number[^\n]*\|\|\s*echo").hasMatch(gh), isFalse,
        reason: 'سيرُ الوسمِ يَسقطُ إلى رقمٍ مكتوبٍ عند الفشل — تصادمٌ صامت');
    expect(gh.contains("''|*[!0-9]*)"), isTrue,
        reason: 'زالَ فحصُ أنّ الناتجَ رقمٌ — خَرْجٌ تالفٌ يُبنى به');
  });

  // ════════════════════════════════════════════════════════════════════
  // **سرٌّ يُكتَبُ في ملفٍّ بلا فحصِ حضور — خمسةُ مواضعَ في مسارِ الإصدارِ
  // لا يَقرؤها فحصٌ قطّ (2026-11-01).**
  //
  // القرارُ مسجَّلٌ مرّتَين في CLAUDE.md («السرُّ الغائبُ يُفشِلُ الوظيفةَ لا
  // يُكتَبُ فارغاً — نفسُ قرارِ `admin_deploy.yml`») ومُنفَّذٌ في ثلاثةِ
  // مواضعَ قبلَ هذه الشريحة: مفاتيحُ `.env` في مسارَي `codemagic.yaml` وفي
  // سيرِ الوسم (4cb72ad)، ومفتاحُ حسابِ الخدمةِ في `functions_deploy.yml`.
  // فقاعدةُ `.env` **تُغطّي `codemagic.yaml` سلفاً**، وهي النصفُ الأوّلُ من
  // الإصلاح؛ والمكشوفُ كان ما ليس مفتاحَ `.env`: مفتاحُ الشهادةِ الخاصُّ،
  // و`key.properties` بكلمتَي مرورِه، وملفُّ المفتاحِ — خمسةُ مواضعَ في
  // `codemagic.yaml` و`android_release.yml` لم يَبلغْها أيُّ فحص.
  //
  // وأثقلُها يَمَسُّ عطلاً قائماً: `echo "$CERTIFICATE_PRIVATE_KEY" >
  // /tmp/private.key` ثمّ `echo "✓ …"` — والـ✓ يُطبَعُ ولو كان المتغيّرُ
  // غائباً (الملفُّ يُنشَأُ بسطرٍ فارغٍ والخروجُ صفر). فخمسُ دمجاتٍ في 31
  // أكتوبر قرأت «Write certificate private key: OK» ثمّ فشلت عند
  // `fetch-signing-files` بعدَها بأربعِ ثوان — ونجاحُ الخطوةِ الأولى **ليس
  // دليلاً** أنّ المفتاحَ موجود. (تصحيحٌ لاستنتاجٍ سابقٍ مني: قرأتُ نجاحَها
  // دليلاً على أنّ العطلَ في تكاملِ ASC لا في الشهادة.)

  /// الكاشفُ شفرةٌ تُختبَرُ كالشفرة: بعدَ الإصلاحِ المصدرُ نظيفٌ، فنجاحُ
  /// المقارنةِ وحدَها لا يُبرهِنُ أنّه يَرى كتابةً أصلاً — فله فحصٌ على كلِّ
  /// شكلٍ أعماه. وأعمَته **عشرةُ** أشكالٍ في صياغاتٍ سابقة، كلٌّ منها مرَّ
  /// أخضرَ على قضمٍ يُعيدُ العطلَ كاملاً: `{ printf …; } > .env`، و`${{
  /// secrets.X }}` إنلاين، وتوجيهٌ على سطرِ وَصلٍ (`\` ثمّ `> f`)، و`tee`،
  /// و`dd of=`، و`install /dev/stdin`، ومُفسِّرٌ يَكتبُ مساراً، وفاصلُ
  /// heredoc غيرُ `EOF`، وتوجيهٌ **قبلَ** البيانات، وخطوةٌ بلا `name:`.
  List<Map<String, Object>> secretFileWrites(String src, {required bool wf}) {
    // **«سرٌّ» يُعرَّفُ بدقّةٍ لكلِّ سطحٍ، والسطحُ من مسارِ الملفِّ لا من
    // محتواه.** صياغتانِ سقطتا قبلَ هذه:
    //   • «كلُّ اسمٍ كبيرٍ غيرِ مُعلَنٍ» أبلغَت عن `RUNNER_TEMP` في
    //     `functions_deploy.yml` — مسارٌ يُوفّرُه المُشغّلُ في **هدفِ**
    //     التوجيه، لا سرٌّ يُكتَبُ فيه.
    //   • ثمّ «السطحُ من وجودِ صيغةِ `secrets.` في الملفّ» أبلغَت عن
    //     `PATHS`/`RUNNER_TEMP` في `deploy_drift.yml` — سيرٌ لا أسرارَ فيه
    //     أصلاً، فسقطَ إلى تعريفِ Codemagic. والمِعيارُ الصحيحُ المسار:
    //     سيرُ Actions يُعبّرُ دائماً بـ`${{ secrets.X }}`، و`codemagic.yaml`
    //     دائماً بـ`groups:`.
    // كلُّ اسمِ سرٍّ يَظهرُ في الملفِّ — **لا المربوطَ في `env:` وحدَه**.
    // أوّلُ صياغةٍ جمعَت المربوطَ فقط، فقضمةٌ أعادت الشكلَ الأصليَّ
    // (`echo "\${{ secrets.X }}" | base64 -d > f` بلا `env:` ولا فحص) مرَّت
    // **خضراء**: الكاشفُ كان أعمى عن العطلِ الذي وُجد لأجلِه. و`${{
    // secrets.X }}` سرٌّ **بالتعريف** أيّاً كان موضعُه.
    final bound = <String>{
      ...RegExp(r'\$\{\{\s*secrets\.([A-Za-z0-9_]+)')
          .allMatches(src)
          .map((m) => m.group(1)!),
      ...RegExp(
              r'^\s*([A-Z][A-Z0-9_]{3,}):\s*\$\{\{\s*secrets\.([A-Za-z0-9_]+)',
              multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1)!),
    };
    final declared = <String>{
      ...RegExp(r'^\s{6,}([A-Z][A-Z0-9_]{3,}):\s*"', multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1)!),
      ...RegExp(r'^\s*([A-Z][A-Z0-9_]{3,})=', multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1)!),
    };
    bool isSecret(String v) => wf ? bound.contains(v) : !declared.contains(v);

    // شكلانِ للسرِّ في سطرِ كتابة: `$VAR` المربوطُ في `env:`، و**`${{
    // secrets.X }}` إنلاين** — وهذا الثاني هو ما كان في `android_release.yml`
    // قبلَ هذا الإصلاح، فكاشفٌ أعمى عنه يَقرأُ عودتَه «بلا سرٍّ يُكتَب»
    // ويَمُرُّ أخضرَ فوقَ العطلِ نفسِه. وثالثٌ: اسمٌ **يُقرَأُ من البيئةِ**
    // داخلَ مُفسِّر (`os.environ['X']`) — لا `$` فيه، فسطرُ python يَكتبُ
    // المفتاحَ ولا يُرى فيه اسمٌ إطلاقاً.
    final varRe = RegExp(r'\$\{?([A-Z][A-Z0-9_]{3,})\}?');
    final inlineRe = RegExp(r'\$\{\{\s*secrets\.([A-Za-z0-9_]+)\s*\}\}');
    final envReadRe = RegExp(r"""(?:environ|ENV)\[['"]([A-Z][A-Z0-9_]{3,})['"]\]"""
        r"""|getenv\(['"]([A-Z][A-Z0-9_]{3,})['"]\)"""
        r"""|\benv\.([A-Z][A-Z0-9_]{3,})\b""");
    Set<String> varsIn(String t) => {
          ...inlineRe.allMatches(t).map((m) => m.group(1)!),
          ...varRe
              .allMatches(t.replaceAll(inlineRe, ''))
              .map((m) => m.group(1)!),
          ...envReadRe.allMatches(t).expand(
              (m) => [m.group(1), m.group(2), m.group(3)].whereType<String>()),
        };

    // **كلُّ ما يُنتجُ ملفّاً، لا التوجيهَ وحدَه.** صياغةٌ سابقةٌ عرفَت
    // `> f` فقط، فستُّ صِيَغٍ أخرى تَكتبُ السرَّ نفسَه وتَمُرُّ خضراء —
    // كلُّها مُثبَتةٌ بقضمٍ، وأوسعُها نزعَ حُرّاسَ التوقيعِ الثلاثةَ في
    // `codemagic.yaml` معاً فهبطَ العدُّ 15 ← 12 والفحصُ أخضر.
    final redirRe = RegExp(r'>>?\s*(?![&])(?!/dev/null\b)("[^"]*"|\S+)');
    final teeRe = RegExp(r'\btee\s+(?:-a\s+)?("[^"]*"|\S+)');
    final ddRe = RegExp(r'\bdd\s+[^;|&]*?\bof=("[^"]*"|\S+)');
    final installRe = RegExp(r'\binstall\b[^;|&]*?/dev/stdin\s+("[^"]*"|\S+)');
    final interpWriteRe = RegExp(r'\b(?:python3?|node|perl|ruby)\b[^\n]*?'
        r'(?:write_text|write_bytes|writeFileSync|writeFile|File\.write|'
        r'open\s*\()');
    // فاصلُ heredoc **أيُّ كلمةٍ** لا `EOF` وحدَها، و`<<<` ليست heredoc.
    final heredocRe = RegExp(r"""(?<!<)<<(?!<)-?\s*['"]?(\w+)['"]?""");

    /// يُعيدُ نصَّ **البياناتِ** المكتوبةِ إن كان الأمرُ كتابةَ ملفّ، وإلّا
    /// `null`. ويُسقِطُ **رمزَ الهدفِ وحدَه** لا ما بعدَه: فتوجيهٌ قبلَ
    /// البياناتِ (`printf '%s' > f "$SECRET"`، وهو مشروعٌ في bash) يَبقى
    /// مرئيّاً، ويَبقى اسمُ المسارِ في الهدفِ خارجَ العدّ
    /// (`> "$CM_BUILD_DIR/out"`). وصياغةُ `leftOfRedir` السابقةُ كانت
    /// تَقطعُ عندَ أوّلِ `>` فتُسقِطُ الشكلَ الأوّلَ كلَّه.
    String? writePayload(String cmd) {
      var hit = false;
      var t = cmd;
      for (final re in [redirRe, teeRe, ddRe, installRe]) {
        if (re.hasMatch(t)) {
          hit = true;
          t = t.replaceAll(re, ' ');
        }
      }
      if (interpWriteRe.hasMatch(cmd)) hit = true;
      return hit ? t : null;
    }

    /// **التعدادُ على علامةِ القائمةِ لا على `name:`.** خطوةٌ بلا اسمٍ
    /// (`- run: |` وحدَه، وهو شكلٌ عاديٌّ في Actions، وأوّلُ `steps:` هو
    /// موضعُ تهيئةِ مادّةِ التوقيعِ طبعاً) كانت تَخرُجُ من نظرِ الكاشفِ
    /// كلِّه: لا تُعَدُّ ولا تُفحَصُ ولا تُرى. والتعدادُ محصورٌ بكتلِ
    /// `steps:`/`scripts:` فلا تُقرأُ قوائمُ أخرى خطواتٍ.
    final steps = <List<String>>[];
    final srcLines = src.split('\n');
    for (var i = 0; i < srcLines.length; i++) {
      final key =
          RegExp(r'^(\s*)(?:steps|scripts):\s*$').firstMatch(srcLines[i]);
      if (key == null) continue;
      final keyInd = key.group(1)!.length;
      int? markerInd;
      final starts = <int>[];
      var j = i + 1;
      for (; j < srcLines.length; j++) {
        final l = srcLines[j];
        if (l.trim().isEmpty) continue;
        final ind = l.length - l.trimLeft().length;
        if (ind <= keyInd) break;
        if (RegExp(r'^\s*-\s').hasMatch(l)) {
          markerInd ??= ind;
          if (ind == markerInd) starts.add(j);
        }
      }
      for (var s = 0; s < starts.length; s++) {
        final from = starts[s];
        final to = s + 1 < starts.length ? starts[s + 1] : j;
        final bodyLines = srcLines.sublist(from, to);
        final nm = RegExp(r'^\s*-\s*name:\s*(.+)$').firstMatch(bodyLines.first);
        steps.add([
          nm != null ? nm.group(1)!.trim() : 'خطوةٌ بلا اسمٍ عند السطر ${from + 1}',
          bodyLines.join('\n'),
        ]);
      }
    }

    final out = <Map<String, Object>>[];
    for (final st in steps) {
      final body = st[1];
      // سطورٌ **منطقيّة**: ما ينتهي بـ`\` يُوصَلُ بتاليه قبلَ أيِّ فحص.
      // بلا هذا يَكونُ الكاشفُ سطريّاً، فـ`printf '%s' "$SECRET" \` ثمّ
      // سطرٌ فيه `> f` يُقرأُ «بلا كتابة» وهو الشكلُ الأوّلُ من عشرة.
      final lines = <String>[];
      for (final raw
          in body.split('\n').where((l) => !l.trimLeft().startsWith('#'))) {
        if (lines.isNotEmpty && lines.last.trimRight().endsWith(r'\')) {
          final prev = lines.removeLast().trimRight();
          lines.add('${prev.substring(0, prev.length - 1)} ${raw.trim()}');
        } else {
          lines.add(raw);
        }
      }
      final joined = lines.join('\n');

      // **إسنادٌ محلّيٌّ بمستوًى واحد**: `X=$SECRET` ثمّ كتابةُ `"$X"`.
      // `declared` يُخرِجُ `X` من «السرّ» فتَختفي الكتابةُ كلُّها — مُثبَتٌ
      // بقضمٍ مرَّ أخضرَ. يُحَلُّ مرّةً واحدةً كما يُحَلُّ المُعرِّفُ
      // المفردُ في `money_format_test` وحارسِ مرجعِ العقد.
      final localOf = <String, String>{};
      for (final m in RegExp(
              r'''^\s*([A-Za-z_]\w*)=["']?(?:\$\{?([A-Z][A-Z0-9_]{3,})\}?|'''
              r'''\$\{\{\s*secrets\.([A-Za-z0-9_]+)\s*\}\})["']?\s*$''',
              multiLine: true)
          .allMatches(joined)) {
        localOf[m.group(1)!] = m.group(2) ?? m.group(3)!;
      }
      String resolve(String v) => localOf[v] ?? v;

      int blockEnd(int from, String open, String close) {
        var depth = 0;
        for (var i = from; i < lines.length; i++) {
          final t = lines[i];
          depth += RegExp('(?:^|;|\\s)$open(?:\\s|\$)').allMatches(t).length;
          final c = RegExp('(?:^|;|\\s)$close(?:\\s|\$)').allMatches(t).length;
          if (c > 0) {
            depth -= c;
            if (depth <= 0) return i;
          }
        }
        return lines.length - 1;
      }

      // **البوّابةُ يَجبُ أن تَهيمِنَ على الكتابة.** صياغةٌ سابقةٌ جمعَت
      // `-z` في أيِّ موضعٍ من الخطوةِ ثمّ سألت «هل في الخطوةِ `exit 1`؟» —
      // فتحذيرٌ لا يَخرُجُ (`echo … >&2` بلا `exit`) مع `exit 1` في أمرٍ
      // مجاورٍ يُرضيها، والبناءُ يَفعلُ **ما كان يَفعلُه قبلَ الإصلاح**:
      // ✓ يُطبَعُ، ومفتاحٌ فارغٌ يُكتَب. فالخروجُ يَجبُ أن يَكونَ **داخلَ**
      // كتلةِ الفحصِ، والكتابةُ **بعدَها** — «الترتيبُ هو الإصلاح».
      final gates = <String, int>{};
      void gate(String name, int at) {
        gates[name] = at;
        gates[resolve(name)] = at;
      }
      final exitRe = RegExp(r'exit\s+[1-9]');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final ifZ =
            RegExp(r'^\s*if\s+.*?-z\s+"?\$\{?([A-Z][A-Z0-9_]{3,})\}?"?')
                .firstMatch(l);
        if (ifZ != null) {
          final end = blockEnd(i, 'if', 'fi');
          if (exitRe.hasMatch(lines.sublist(i, end + 1).join('\n'))) {
            gate(ifZ.group(1)!, end);
          }
          continue;
        }
        final short = RegExp(
                    r'-z\s+"?\$\{?([A-Z][A-Z0-9_]{3,})\}?"?[^\n]*&&[^\n]*exit\s+[1-9]')
                .firstMatch(l) ??
            RegExp(r'-n\s+"?\$\{?([A-Z][A-Z0-9_]{3,})\}?"?[^\n]*\|\|[^\n]*exit\s+[1-9]')
                .firstMatch(l);
        if (short != null) {
          gate(short.group(1)!, i);
          continue;
        }
        // حلقةُ فحصٍ غيرِ مباشرة: `for v in A B C; do eval "val=\$$v"; -z …`
        // — الجسمُ يَجبُ أن يَحملَ فحصَ فراغٍ وخروجاً **وذِكرَ متغيّرِ
        // الحلقةِ** حتى يَصدُقَ أنّه يُغطّي كلَّ اسمٍ في قائمتِها.
        final loop = RegExp(r'^\s*for\s+(\w+)\s+in\s+([A-Z0-9_ ]+);\s*do')
            .firstMatch(l);
        if (loop != null) {
          final end = blockEnd(i, 'for', 'done');
          final blk = lines.sublist(i, end + 1).join('\n');
          final lv = loop.group(1)!;
          if (RegExp(r'-z\s+"?\$\{?\w+\}?"?').hasMatch(blk) &&
              exitRe.hasMatch(blk) &&
              RegExp('\\\$\\{?$lv\\}?').hasMatch(blk)) {
            for (final v in loop.group(2)!.trim().split(RegExp(r'\s+'))) {
              gate(v, end);
            }
          }
          continue;
        }
      }

      final writes = <String, int>{};
      void addWrites(String payload, int at) {
        for (final v in varsIn(payload)) {
          writes.putIfAbsent(resolve(v), () => at);
        }
      }

      var heredocEnd = '', heredocAt = -1;
      var inBrace = false;
      final braceBuf = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (heredocEnd.isNotEmpty) {
          if (l.trim() == heredocEnd) {
            heredocEnd = '';
            continue;
          }
          addWrites(l, heredocAt);
          continue;
        }
        final hd = heredocRe.firstMatch(l);
        if (hd != null && writePayload(l) != null) {
          heredocEnd = hd.group(1)!;
          heredocAt = i;
          continue;
        }
        // مجموعةُ أقواسٍ تُعادُ توجيهاً بعدَ غلقِها: `{ … } > f` — وهي شكلُ
        // `ios_release.yml`، وقد أعمَت الصياغةَ الأولى تماماً.
        if (l.trim() == '{') {
          inBrace = true;
          braceBuf.clear();
          continue;
        }
        if (inBrace) {
          if (RegExp(r'^\s*\}').hasMatch(l)) {
            inBrace = false;
            if (writePayload(l) != null) addWrites(braceBuf.join('\n'), i);
            continue;
          }
          braceBuf.add(l);
          continue;
        }
        final p = writePayload(l);
        if (p != null) addWrites(p, i);
      }

      // سرٌّ مربوطٌ في `env:` من `secrets.X`: فحصُ أيِّ الاسمَين يَكفي.
      final alias = <String, String>{};
      for (final m in RegExp(
              r'^\s*([A-Z][A-Z0-9_]{3,}):\s*\$\{\{\s*secrets\.([A-Za-z0-9_]+)',
              multiLine: true)
          .allMatches(body)) {
        alias[m.group(1)!] = m.group(2)!;
        alias[m.group(2)!] = m.group(1)!;
      }
      bool gated(String v, int at) {
        for (final n in <String?>{v, alias[v]}.whereType<String>()) {
          final g = gates[n];
          if (g != null && g < at) return true;
        }
        return false;
      }

      final secrets = writes.keys.where(isSecret).toSet();
      if (secrets.isEmpty) continue;
      out.add({
        'step': st[0],
        'written': secrets,
        'unchecked': secrets.where((v) => !gated(v, writes[v]!)).toSet(),
      });
    }
    return out;
  }

  /// كلُّ مسارِ إصدارٍ: `codemagic.yaml` وكلُّ سيرٍ يَكتبُ سرّاً في ملفّ —
  /// مُشتَقٌّ، فسيرٌ جديدٌ يَدخلُ النطاقَ بنفسِه. و**الامتدادانِ معاً**:
  /// صياغةٌ سابقةٌ رشَّحت `.yml` وحدَه، فسيرُ إصدارٍ باسمِ `.yaml` — وGitHub
  /// يَقبلُ الاثنَين — يَخرُجُ من هذا الحارسِ ومن حارسَي Play معاً.
  List<String> releasePaths() => [
        'codemagic.yaml',
        ...workflowFiles()
            .where((f) => secretFileWrites(File(f).readAsStringSync(), wf: true)
                .isNotEmpty),
      ]..sort();

  /// مُستثنًى واحدٌ بسببِه: غيابُ معرّفِ Samsung Pay **يُخفي زرَّه**
  /// (`samsungServiceId.isEmpty || startsWith('REPLACE')` في
  /// `payment_summary_screen`) فيَتدهوَرُ ظاهراً لا صامتاً — بخلافِ مفتاحِ
  /// ميسر الذي غيابُه يُنتجُ حزمةً بلا بطاقةٍ ولا Apple Pay تُبنى خضراء.
  const quietDegrade = {'SAMSUNG_PAY_SERVICE_ID'};

  test('الكاشفُ يَرى كتابةَ سرٍّ بأشكالِها العشرةِ، ولا يَرى ما ليس كتابةً ولا سرّاً',
      () {
    Set<String> wRaw(String yaml, {bool wf = false}) {
      final r = secretFileWrites(yaml, wf: wf);
      return r.isEmpty ? <String>{} : (r.first['written'] as Set<String>);
    }

    Set<String> w(String body, {bool wf = false}) =>
        wRaw('    steps:\n$body', wf: wf);
    int stepsSeen(String body) =>
        secretFileWrites('    steps:\n$body', wf: false).length;

    // (١) الشكلُ الذي أعمى الصياغةَ الأولى: مجموعةُ أقواسٍ تُعادُ توجيهاً.
    expect(
        w('''      - name: s
        run: |
          {
            printf 'K=%s\\n' "\$SOME_SECRET"
          } > .env
'''),
        {'SOME_SECRET'},
        reason: 'كتابةٌ بمجموعةِ أقواسٍ `{ … } > f` — وهي شكلُ ios_release.yml');
    // (٢) التوجيهُ العاري.
    expect(
        w('''      - name: s
        script: |
          echo "\$PLAIN_SECRET" > /tmp/k
'''),
        {'PLAIN_SECRET'});
    // (٣) أنبوبٌ ثمّ توجيه.
    expect(
        w('''      - name: s
        script: |
          echo "\$PIPED_SECRET" | base64 --decode > f.jks
'''),
        {'PIPED_SECRET'});
    // (٤) heredoc بفاصلِ `EOF`.
    expect(
        w('''      - name: s
        run: |
          cat > f << EOF
          a=\$HEREDOC_SECRET
          EOF
'''),
        {'HEREDOC_SECRET'});
    // (٥) **فاصلُ heredoc غيرُ `EOF`**: الصياغةُ السابقةُ شرطَت `EOF`
    // حرفيّاً، فـ`<< PEM` لا تُدخِلُ heredoc أصلاً ولا يُمسَحُ جسمُها.
    expect(
        w('''      - name: s
        run: |
          cat > /tmp/private.key << PEM
          \$PEM_SECRET
          PEM
'''),
        {'PEM_SECRET'},
        reason: 'أيُّ فاصلٍ heredoc — لا `EOF` وحدَها');
    // (٦) **توجيهٌ على سطرِ وَصل**: السطرُ الحاملُ للبياناتِ بلا `>`،
    // والسطرُ الحاملُ لـ`>` بلا شيءٍ يسارَه. وهو أسهلُ الأشكالِ وقوعاً:
    // إعادةُ تنسيقِ `echo >` إلى `printf … \\` بلا تغييرِ سلوكٍ إطلاقاً.
    expect(
        w('''      - name: s
        script: |
          printf '%s' "\$CONT_SECRET" \\
            > /tmp/private.key
'''),
        {'CONT_SECRET'},
        reason: 'سطرٌ منطقيٌّ واحدٌ، لا سطرانِ ماديّان');
    // (٧) `tee` — تَكتبُ ملفّاً بلا رمزِ توجيهٍ إطلاقاً، وهي **عُرفُ هذا
    // المستودعِ نفسِه** في أربعةِ سِيَرِ نشر (`| tee "$RUNNER_TEMP/…"`).
    expect(
        w('''      - name: s
        script: |
          echo "\$TEE_SECRET" | tee /tmp/private.key >/dev/null
'''),
        {'TEE_SECRET'});
    // (٨) **توجيهٌ قبلَ البيانات** — bash يَقبلُ التوجيهَ في أيِّ موضعٍ من
    // الأمر، وقَطعُ النصِّ عندَ أوّلِ `>` كان يُسقِطُ ما بعدَه.
    expect(
        w('''      - name: s
        script: |
          printf '%s' > /tmp/private.key "\$PRE_SECRET"
'''),
        {'PRE_SECRET'});
    // (٩) `dd of=` و`install /dev/stdin`.
    expect(
        w('''      - name: s
        script: |
          printf '%s' "\$DD_SECRET" | dd of=/tmp/private.key status=none
'''),
        {'DD_SECRET'});
    expect(
        w('''      - name: s
        script: |
          install -m 600 /dev/stdin /tmp/private.key <<< "\$INST_SECRET"
'''),
        {'INST_SECRET'});
    // (١٠) مُفسِّرٌ يَكتبُ مساراً، والسرُّ يُقرَأُ من البيئةِ بلا `$`.
    expect(
        w('''      - name: s
        script: |
          python3 -c "import os,pathlib;pathlib.Path('/tmp/k').write_text(os.environ['PY_SECRET'])"
'''),
        {'PY_SECRET'},
        reason: 'اسمٌ يُقرَأُ من البيئةِ سرٌّ كـ\$VAR تماماً');
    // وخطوةٌ **بلا `name:`** — شكلٌ عاديٌّ في Actions كان يَخرُجُ من
    // التعدادِ كلِّه، فلا تُعَدُّ ولا تُفحَص.
    expect(
        stepsSeen('''      - run: |
          echo "\$NAMELESS_SECRET" > /tmp/private.key
'''),
        1,
        reason: 'التعدادُ على علامةِ القائمةِ لا على `name:`');
    expect(
        w('''      - run: |
          echo "\$NAMELESS_SECRET" > /tmp/private.key
'''),
        {'NAMELESS_SECRET'});
    // وإسنادٌ محلّيٌّ بمستوًى واحد: الكتابةُ تُنسَبُ إلى السرِّ لا إلى
    // النسخةِ المحلّيّةِ التي يُخرِجُها `declared` من «السرّ».
    expect(
        w('''      - name: s
        script: |
          LOCAL_COPY="\$INDIRECT_SECRET"
          echo "\$LOCAL_COPY" | base64 -d > f.jks
'''),
        {'INDIRECT_SECRET'},
        reason: 'مستوًى واحدٌ من الإسنادِ يُحَلّ');
    // وما ليس كتابةً في ملفّ:
    // **`writePayload` يُسقِطُ رمزَ الهدفِ وحدَه**: اسمٌ في **هدفِ**
    // التوجيه مسارٌ لا بيانات. بلا هذه الحالةِ كان الإسقاطُ عقيماً —
    // قضمةٌ تُمحي السطرَ كلَّه تَمُرُّ خضراء — لأنّ تعريفَ سرِّ Actions
    // بالاسمِ يُخرِجُ `RUNNER_TEMP` بأيِّ حال. و`CM_BUILD_DIR` من بُنى
    // Codemagic، وتعريفُ السرِّ هناك «ما ليس مُعلَناً» فيَقعُ في الفخّ.
    expect(
        w('''      - name: s
        script: |
          echo "\$WRITTEN_SECRET" > "\$CM_BUILD_DIR/out"
'''),
        {'WRITTEN_SECRET'},
        reason: 'اسمُ المسارِ في هدفِ التوجيه ليس سرّاً يُكتَب');
    // وسرٌّ إنلاين في سيرِ Actions — الشكلُ الذي أعمى الصياغةَ الأولى:
    expect(
        w('''      - name: s
        run: |
          echo "\${{ secrets.INLINE_SECRET }}" | base64 -d > f.jks
''', wf: true),
        {'INLINE_SECRET'},
        reason: '`\${{ secrets.X }}` إنلاين سرٌّ بالتعريف ولو لم يُربَط في env:');
    expect(
        w('''      - name: s
        script: |
          foo --id "\$NOT_WRITTEN" 2>/dev/null
'''),
        isEmpty,
        reason: '`2>/dev/null` ليست كتابةَ سرٍّ في ملفّ — '
            'وهي ما أنتجَ إيجابَ APP_STORE_APP_ID الكاذبَ');
    // و`<<<` ليست heredoc: لو قُرئت كذلك لَصارَ ما بعدَها جسماً يُمسَح.
    expect(
        w('''      - name: s
        script: |
          grep -q x <<< "\$NOT_WRITTEN_EITHER"
'''),
        isEmpty,
        reason: 'سلسلةٌ هنا (`<<<`) ليست heredoc ولا كتابةَ ملفّ');
    // ولا ما هو مُعلَنٌ في الملفِّ أو محلّيٌّ فيه:
    expect(
        wRaw('''    vars:
      PUBLIC_IDENT: "x"
    steps:
      - name: s
        script: |
          echo "\$PUBLIC_IDENT" > f
'''),
        isEmpty,
        reason: 'معرّفٌ مكتوبٌ في vars: ليس سرّاً — لا يَغيبُ أصلاً');
    expect(
        w('''      - name: s
        script: |
          LOCAL_THING=5
          echo "\$LOCAL_THING" > f
'''),
        isEmpty,
        reason: 'متغيّرٌ مُسنَدٌ في الكتلةِ ليس سرّاً خارجيّاً');
  });

  test('والبوّابةُ تَهيمِنُ على الكتابةِ: تحذيرٌ لا يَخرُجُ ليس فحصاً', () {
    Set<String> unchecked(String body) {
      final r = secretFileWrites('    steps:\n$body', wf: false);
      return r.isEmpty ? <String>{} : (r.first['unchecked'] as Set<String>);
    }

    // الشكلُ الصحيح: الخروجُ **داخلَ** كتلةِ الفحصِ، والكتابةُ بعدَها.
    expect(
        unchecked('''      - name: s
        script: |
          if [ -z "\$GATED_SECRET" ]; then
            echo "missing" >&2
            exit 1
          fi
          echo "\$GATED_SECRET" > /tmp/k
'''),
        isEmpty);
    // **تحذيرٌ لا يَخرُجُ، و`exit 1` في أمرٍ مجاورٍ لا علاقةَ له**: صياغةٌ
    // سابقةٌ كانت تَقرأُ هذا «مفحوصاً» — فالتقريرُ نظيفٌ والبناءُ يَفعلُ
    // ما كان يَفعلُه قبلَ الإصلاح: ✓ يُطبَعُ ومفتاحٌ فارغٌ يُكتَب.
    expect(
        unchecked('''      - name: s
        script: |
          if [ -z "\$WARNED_SECRET" ]; then
            echo "تحذير: غائب" >&2
          fi
          echo "\$WARNED_SECRET" > /tmp/k
          some-other-command || exit 1
'''),
        {'WARNED_SECRET'},
        reason: 'الخروجُ ليس داخلَ كتلةِ الفحص');
    // والترتيبُ: كتابةٌ **قبلَ** البوّابةِ لا تَحرُسُها البوّابة.
    expect(
        unchecked('''      - name: s
        script: |
          echo "\$EARLY_SECRET" > /tmp/k
          if [ -z "\$EARLY_SECRET" ]; then
            exit 1
          fi
'''),
        {'EARLY_SECRET'},
        reason: 'فحصٌ بعدَ الكتابةِ لا يَمنعُ كتابةً فارغة');
    // وحلقةُ الفحصِ غيرِ المباشرةِ — شكلُ `key.properties`.
    expect(
        unchecked('''      - name: s
        script: |
          for v in LOOP_SECRET_ONE LOOP_SECRET_TWO; do
            eval "val=\\\$\$v"
            if [ -z "\$val" ]; then
              echo "سرُّ \$v غير مضبوط" >&2
              exit 1
            fi
          done
          printf 'a=%s\\nb=%s\\n' "\$LOOP_SECRET_ONE" "\$LOOP_SECRET_TWO" > f
'''),
        isEmpty);
    // وحلقةٌ تُحذّرُ ولا تَخرُجُ: نفسُ العطلِ بشكلِ الحلقة.
    expect(
        unchecked('''      - name: s
        script: |
          for v in WARN_LOOP_SECRET; do
            eval "val=\\\$\$v"
            if [ -z "\$val" ]; then
              echo "تحذير" >&2
            fi
          done
          echo "\$WARN_LOOP_SECRET" > f
'''),
        {'WARN_LOOP_SECRET'});
    // والصيغةُ المختصرة.
    expect(
        unchecked('''      - name: s
        script: |
          [ -z "\$SHORT_SECRET" ] && exit 1
          echo "\$SHORT_SECRET" > /tmp/k
'''),
        isEmpty);
  });

  test('كلُّ سرٍّ يُكتَبُ في ملفٍّ في مسارِ إصدارٍ يُفحَصُ حضورُه ويُفشِلُ الوظيفةَ', () {
    // لا امتدادَ ثالثاً يَتسلّلُ من حولِ `workflowFiles()`.
    expect(
        Directory('.github/workflows')
            .listSync()
            .whereType<File>()
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where((f) => !f.endsWith('.yml') && !f.endsWith('.yaml'))
            .toList(),
        isEmpty,
        reason: 'ملفُّ سيرٍ بامتدادٍ لا يَراه الاشتقاقُ — خارجَ ثلاثةِ حُرّاس');

    final paths = releasePaths();
    expect(paths, contains('codemagic.yaml'),
        reason: 'مسارُ الإصدارِ الوحيدُ إلى المتجرَين خرجَ من النطاق — '
            'فحصٌ أجوف: $paths');
    // الأرضيّتانِ عندَ العددِ الحقيقيِّ (٨ مساراتٍ، ١٥ كتابةً) لا تحتَه
    // بمراتب: أرضيّةٌ رخوةٌ تُخفي انحلالَ الكاشفِ بدلَ أن تَكشفَه.
    expect(paths.length, greaterThanOrEqualTo(7),
        reason: 'مسارُ إصدارٍ خرجَ من النطاق — فحصٌ أجوف: $paths');

    var writes = 0;
    final gaps = <String>[];
    for (final p in paths) {
      final steps = secretFileWrites(read_(p), wf: p.startsWith('.github/'));
      expect(steps, isNotEmpty, reason: '$p: لم تُعَدَّ خطوةٌ واحدة — تعدادٌ انحلّ');
      for (final w in steps) {
        writes++;
        final unchecked =
            (w['unchecked'] as Set<String>).difference(quietDegrade);
        for (final v in unchecked) {
          gaps.add('$p › ${w['step']} › $v');
        }
      }
    }
    // **أرضيّةٌ عند العددِ الحقيقيِّ لا تحتَه بمراتب.** صياغةٌ سابقةٌ كانت
    // `>= 6` والعددُ الحقيقيُّ ١٥، فتسعُ وحداتٍ من الفراغِ الصامت: قضمةٌ
    // أعمَت الكاشفَ عن ثلاثِ خطواتِ توقيعٍ (15 ← 12) ومرَّت خضراء.
    expect(writes, greaterThanOrEqualTo(14),
        reason: 'عددُ كتاباتِ الأسرارِ انهار — الكاشفُ انحلَّ: $writes');
    expect(gaps, isEmpty,
        reason: 'سرٌّ يُكتَبُ فارغاً بلا فحصِ حضور. و`CERTIFICATE_PRIVATE_KEY` '
            'أخصُّها: `echo "\$VAR" > f` يَطبعُ ✓ ولو غابَ المتغيّرُ، '
            'فتُقرأُ الخطوةُ ناجحةً ويَفشلُ التوقيعُ بعدَها بلا سببٍ مقروء');
  });

  test('ومُستثنى التدهوُرِ الظاهرِ واحدٌ، ودعواهُ مُتحقَّقةٌ في lib/', () {
    // القاعدةُ انتقلَت إلى `native_pay_config.dart` (2026-10-09)، وأوّلُ
    // صياغةٍ لهذا الفحصِ قرأت الشاشةَ باحثةً عن النصِّ القديمِ فسقطت على
    // شفرةٍ **سليمة** — «حارسٌ يَسقطُ بالنقل» واقعاً على فحصٍ كتبتُه لتوّي.
    // فالمشدودُ **الطرفانِ**: القاعدةُ حيث تَسكن، والشاشةُ تُنادِيها — فلا
    // يَمُرُّ نصفٌ وحدَه.
    expect(
        RegExp(r'bool nativePayPlaceholder\(')
            .hasMatch(read('lib/utils/native_pay_config.dart')),
        isTrue,
        reason: 'قاعدةُ النائبِ زالت — فغيابُ معرّفِ Samsung لم يَعُد '
            'تدهوُراً ظاهراً، ويُراجَعُ استثناؤه لا يُسكَت');
    final screen = read('lib/screens/payment_summary_screen.dart');
    expect(
        RegExp(r'nativePayPlaceholder\(\s*samsungServiceId\s*\)')
            .hasMatch(screen),
        isTrue,
        reason: 'زرُّ Samsung Pay لم يَعُد مشروطاً بالقاعدةِ — فغيابُ السرِّ '
            'يُنتجُ زرّاً لا يَقبضُ، ويُراجَعُ استثناؤه لا يُسكَت');
    expect(quietDegrade.length, 1,
        reason: 'مُستثنًى ثانٍ يُراجَعُ بوعي: الاستثناءُ يَلزمُه حارسٌ في '
            'الواجهةِ يُخفي الميزةَ عند غيابِ سرِّها');
  });
}
