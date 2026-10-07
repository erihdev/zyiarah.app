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
  final appEnvWrite = RegExp(r'>\s*\.env\s*$', multiLine: true);
  List<String> envWriters() => [
        'codemagic.yaml',
        ...Directory('.github/workflows')
            .listSync()
            .whereType<File>()
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where((f) => f.endsWith('.yml'))
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
    for (final w in envWriters().where((w) => w.startsWith('.github/'))) {
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
      ...Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((f) => f.endsWith('.yml'))
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
}
