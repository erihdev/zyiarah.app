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
}
