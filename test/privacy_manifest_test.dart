// حارسُ **بيانِ الخصوصيّة**: ما يُعلِنُه `ios/Runner/PrivacyInfo.xcprivacy`
// هو ما تَجمعُه الشفرةُ فعلاً، لكلِّ نوعٍ شاهدٌ مُسمًّى.
//
// ═══ لماذا ═══
//
// البيانُ كان يُعلِنُ **ثلاثةَ** أنواعٍ (موقعٌ دقيقٌ، اسمٌ، بياناتُ انهيار) من
// **اثنَي عشَر** تُجمَع، ويَصفُ الموقعَ الدقيقَ بأنّه «غيرُ مرتبطٍ بالهويّة»
// وهو مرتبطٌ (يُكتَبُ على مستندِ الطلبِ مع `client_id`/`driver_id`). ولا شيءَ
// كان يُقارِنُه بالشفرة: ملفٌّ يُقرأُ مرّةً عند إنشاء المشروعِ ثم لا يُفتَح،
// بينما الحقولُ تُضافُ مع كلِّ ميزة. وهو **ادّعاءٌ بلا قارئ** — العائلةُ
// نفسُها التي تَكرّرت في هذا المستودعِ (ترويسةُ `couponProblem`، تعليقُ
// `PromoCoupon`، ادّعاءُ «all HMAC-verified»، مرآةُ `access.ts`).
//
// ونقصُ الإعلانِ هو الخطأُ الأخطرُ من الزيادةِ: مراجعةُ آبل تُقارِنُ البيانَ
// بأجوبةِ «خصوصيّةُ التطبيق» في App Store Connect، والتباينُ سببُ رفضٍ
// مُراسَلٍ به (ITMS-91053 وما يَليه).
//
// ═══ وما ليس من عملِ هذا الحارس ═══
//
// أجوبةُ App Store Connect ونموذجُ «أمان البيانات» في Play **لا يُولَّدانِ**
// من هذا الملفّ — عملُ المالك. وكذلك نصُّ `privacy_policy.md`: وثيقةٌ
// قانونيّةٌ، وتصحيحُها قرارُ المالكِ لا قرارُ حارس (والتباينُ القائمُ فيها
// مرفوعٌ إليه: تَذكرُ تحقّقاً بـOTP لا وجودَ له، ولا تَذكرُ البريدَ وهو
// مفتاحُ الحساب).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _manifest = 'ios/Runner/PrivacyInfo.xcprivacy';

/// أنواعُ `NSPrivacyCollectedDataType` المُعلَنة، بحالةِ الارتباطِ لكلٍّ.
Map<String, bool> _declared(String xml) {
  final out = <String, bool>{};
  // كلُّ `<dict>` داخلَ `NSPrivacyCollectedDataTypes`: الاقتطاعُ بين المفتاحِ
  // ونهايةِ مصفوفتِه، لا بأوّلِ `</array>` في الملفّ — فخُّ الحدِّ المسجَّلُ
  // ثلاثَ مرّاتٍ في هذا المستودع.
  final k = xml.indexOf('<key>NSPrivacyCollectedDataTypes</key>');
  if (k < 0) return out;
  final end = xml.indexOf('<key>NSPrivacyAccessedAPITypes</key>', k);
  final block = xml.substring(k, end < 0 ? xml.length : end);
  for (final m in RegExp(
    r'<string>NSPrivacyCollectedDataType(\w+)</string>\s*'
    r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<(true|false)/>',
  ).allMatches(block)) {
    out[m.group(1)!] = m.group(2) == 'true';
  }
  return out;
}

void main() {
  final String xml = File(_manifest).readAsStringSync();
  final Map<String, bool> declared = _declared(xml);

  /// لكلِّ نوعٍ: هل يُرتبَطُ بالهويّة، والشاهدُ عليه — نصٌّ يَجبُ أن يُوجَدَ
  /// في الملفِّ المذكور. فنوعٌ يُحذَفُ من البيانِ يَسقطُ، وشاهدٌ يَختفي من
  /// الشفرةِ (أي زالَ الجمعُ) يُراجَعُ بدلَ أن يَبقى الإعلانُ زائداً.
  const evidence = <String, List<String>>{
    'Name': ['true', 'lib/services/firebase_service.dart', "'name': name"],
    'EmailAddress': ['true', 'lib/services/firebase_service.dart', "'email': email"],
    'PhoneNumber': ['true', 'lib/services/firebase_service.dart', "'phone': phone"],
    'UserID': ['true', 'lib/screens/payment_summary_screen.dart', "'client_id'"],
    'PurchaseHistory': [
      'true', 'lib/screens/payment_summary_screen.dart', "'amount'",
    ],
    // الموقعُ الدقيقُ يُكتَبُ في موضعَين: موقعُ السائقِ على مستندِ الطلبِ
    // (تتبُّعٌ حيّ)، وموقعُ التوصيلِ على طلبِ المتجر. والشاهدُ هو الأوّلُ
    // لأنّه الأكثرُ ارتباطاً بالهويّة (`driver_id` على المستندِ نفسِه).
    'PreciseLocation': [
      'true', 'lib/services/order_service.dart', "'driver_location': location",
    ],
    'DeviceID': ['true', 'lib/services/notification_service.dart', "'fcmToken'"],
    'PaymentInfo': ['false', 'pubspec.yaml', 'moyasar:'],
    'CoarseLocation': ['false', 'pubspec.yaml', 'firebase_analytics:'],
    'ProductInteraction': ['false', 'pubspec.yaml', 'firebase_analytics:'],
    'OtherUsageData': ['false', 'pubspec.yaml', 'firebase_analytics:'],
    'CrashData': ['false', 'pubspec.yaml', 'firebase_crashlytics:'],
  };

  test('الاقتطاعُ يَجدُ الأنواعَ فعلاً — وإلّا فالفحوصُ أدناه جوفاء', () {
    expect(declared.length, greaterThanOrEqualTo(10),
        reason: 'لم تُقرأ الأنواعُ من البيان — راجِعْ الاقتطاع لا البيان');
  });

  test('كلُّ نوعٍ مُعلَنٍ له شاهدٌ مُسمًّى في الشفرة', () {
    for (final e in evidence.entries) {
      final witness = File(e.value[1]).readAsStringSync();
      expect(witness.contains(e.value[2]), isTrue,
          reason: 'شاهدُ ${e.key} (${e.value[2]}) اختفى من ${e.value[1]} — '
              'إن زالَ الجمعُ فاحذِفِ النوعَ من البيان، لا الشاهدَ من الحارس');
    }
  });

  test('ومجموعةُ الأنواعِ المُعلَنةِ = مجموعةُ ما له شاهد', () {
    // مقارنةُ المجموعةِ كاملةً (كما في `amounts.test.js` و`app_update_keys`):
    // حقلُ تعريفٍ جديدٌ تَجمعُه ميزةٌ قادمةٌ بلا إعلانٍ يَسقطُ هنا، وإعلانٌ
    // بلا جمعٍ يَسقطُ كذلك — وكلاهما خطأٌ أمامَ مراجعةِ آبل.
    expect(declared.keys.toSet(), evidence.keys.toSet(),
        reason: 'البيانُ والشفرةُ افترقا');
  });

  test('وحالةُ الارتباطِ صحيحةٌ لكلِّ نوع', () {
    for (final e in evidence.entries) {
      expect(declared[e.key], e.value[0] == 'true',
          reason: '${e.key}: حالةُ الارتباطِ تُخالِفُ الواقع — '
              'الموقعُ الدقيقُ كان «غيرَ مرتبط» وهو يُكتَبُ على مستندِ طلبٍ '
              'يَحملُ client_id');
    }
  });

  test('ولا تَتبُّعَ: لا IDFA ولا نطاقَ تتبُّع', () {
    expect(
        RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(xml), isTrue,
        reason: 'صارَ التطبيقُ يُعلِنُ التتبُّع — يَستلزمُ ATT وموافقةً صريحة');
    expect(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array/>')
        .hasMatch(xml), isTrue);
    // ولا `setUserIdentifier` في المستودع، فعدمُ ارتباطِ بياناتِ الانهيارِ صحيح.
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(libFiles.any((f) => f.readAsStringSync().contains('setUserIdentifier')),
        isFalse,
        reason: 'ظهرَ setUserIdentifier — فبياناتُ الانهيارِ صارت مرتبطةً '
            'بالهويّةِ ويَلزمُ تعديلُ البيان');
  });

  test('وأسبابُ الواجهاتِ الأربعُ باقيةٌ — نقصُها رفضٌ مُراسَلٌ به', () {
    for (final cat in const [
      'UserDefaults', 'FileTimestamp', 'SystemBootTime', 'DiskSpace',
    ]) {
      expect(xml.contains('NSPrivacyAccessedAPICategory$cat'), isTrue,
          reason: '$cat سقطت — آبل تَرفضُ الرفعَ برسالةٍ تُسمّيها');
    }
  });
}
