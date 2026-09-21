import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس تثبيت Firebase iOS SDK في ios/Podfile.
///
/// كل podspec في FlutterFire يبدأ بـ:
///
///     if defined?($FirebaseSDKVersion)
///       firebase_sdk_version = $FirebaseSDKVersion   # ← المتغيّر العام يفوز
///     else
///       firebase_sdk_version = firebase_sdk_version! # ← ما يعلنه firebase_core
///
/// أي أن تثبيتاً في Podfile **يتجاوز** ما تعلنه الحزم. وهذا فخّ صامت: شجرة
/// Dart تتقدّم مع كل ترقية، والتثبيت يبقى يشدّ SDK إلى الخلف، فتنادي مصادر
/// Objective-C في الإضافات selectors غير موجودة في النسخة المثبَّتة. ولا يظهر
/// شيء من ذلك في flutter analyze ولا في flutter test ولا في تصريف Dart
/// الكامل — لا يُكشف إلا عند تصريف Objective-C في بناء iOS حقيقي.
///
/// وقع هذا فعلاً (2026-09-13، البناء ٢١٠): تثبيتٌ على 12.13.0 وُضع لأجل
/// cloud_firestore 6.4.x بقي بعد الترقية إلى 6.9.0، فسقط البناء بـ
/// «No visible @interface ... declares the selector
/// initWithRef:firestore:forceIndex:» — والصيغة معرَّفة في 12.17.0 فأعلى،
/// وfirebase_core كان يعلن 12.18.0.
///
/// القاعدة: لا تثبيت أصلاً هو الأسلم. وإن لزم يوماً لضرورة، فيجب ألّا يكون
/// أدنى مما يعلنه firebase_core.

/// يقارن نسخاً على صيغة x.y.z عددياً لا نصّياً ('12.9.0' > '12.18.0' نصّياً).
int _compare(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

void main() {
  test('تثبيت Firebase iOS SDK لا يسبق ما يعلنه firebase_core', () {
    // ما يعلنه firebase_core — يُقرأ من مسار الحزمة الفعلي في package_config،
    // لا من مسار مكتوب بخطّ اليد.
    final cfgFile = File('.dart_tool/package_config.json');
    expect(cfgFile.existsSync(), isTrue,
        reason: 'شغّل flutter pub get أولاً — بلا package_config الفحص وهم');

    final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
    final pkgs = (cfg['packages'] as List).cast<Map<String, dynamic>>();
    final core = pkgs.where((p) => p['name'] == 'firebase_core');
    expect(core, isNotEmpty, reason: 'firebase_core غير محلول في هذا المشروع');

    final root = Uri.parse(core.first['rootUri'] as String).toFilePath();
    final verFile = File('$root/ios/firebase_sdk_version.rb');
    expect(verFile.existsSync(), isTrue,
        reason: 'firebase_sdk_version.rb مفقود في ${verFile.path} — '
            'غيّرت FlutterFire بنيتها؟ حدّث هذا الحارس، لا تحذفه');

    final declared = RegExp(r"'(\d+\.\d+\.\d+)'")
        .firstMatch(verFile.readAsStringSync())
        ?.group(1);
    expect(declared, isNotNull,
        reason: 'تعذّر استخراج النسخة من ${verFile.path}');

    // التثبيت في Podfile — مع تجاهل الأسطر المعلَّقة (الشرح يذكر الاسم عمداً).
    final podfile = File('ios/Podfile');
    expect(podfile.existsSync(), isTrue);
    final active = podfile
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');

    final pin = RegExp(r"\$FirebaseSDKVersion\s*=\s*'(\d+\.\d+\.\d+)'")
        .firstMatch(active)
        ?.group(1);

    if (pin == null) return; // لا تثبيت — الحالة المقصودة.

    expect(_compare(pin, declared!), greaterThanOrEqualTo(0),
        reason: 'ios/Podfile يثبّت Firebase iOS SDK عند $pin بينما '
            'firebase_core يعلن $declared. التثبيت يتجاوز المُعلَن، فستنادي '
            'مصادر الإضافات selectors غير موجودة في $pin ويسقط تصريف '
            'Objective-C في بناء iOS — ولن يكشفه analyze ولا test ولا تصريف '
            'Dart الكامل. ارفع التثبيت أو احذفه.');
  });
}
