// حارسُ **الصلاحيّاتِ المُعلَنة**: لكلِّ صلاحيّةٍ ميزةٌ تُستعملُها، مُسمّاةً.
//
// ═══ لماذا ═══
//
// صلاحيّةٌ تُضافُ مرّةً لميزةٍ ثم تُحذَفُ الميزةُ ولا تُحذَفُ هي — ولا شيءَ
// في البناءِ ولا في `analyze` يَذكرُها. وهذا **بابُ رفضٍ لا بابُ عطل**:
// سياسةُ Play تَشترطُ أن تَخدمَ الصلاحيّةُ ميزةً ظاهرةً للمستخدم، ومُراجِعُ
// آبل **يَقرأُ نصوصَ الأسباب** ويَسألُ عن أيِّ قدرةٍ لا يَجدُ لها ميزة.
//
// وقد وقعَ: `RECORD_AUDIO` و`NSMicrophoneUsageDescription` كانا مُعلَنَين،
// و**لا استعمالَ للميكروفونِ في المستودعِ كلِّه** — لا تسجيلَ صوت، ولا
// `Permission.microphone`، ولا حزمةٌ تُعلِنُه في بيانِها. وسببُه المُعلَنُ
// كان نصّاً يَقول «**تابي** يحتاج إلى الميكروفون للتحقق من هوية المستخدم»،
// وتابي أُزيلت من العميلِ في 2026-09-30 بقرارِ المالكِ (`no_tabby_test`
// يَحرسُ ذلك: الحزمةُ والخدمةُ والمفتاحُ والتشغيلُ والاختيار). فنصُّ سببٍ
// يُسمّي طرفاً ثالثاً **ليس في التطبيق** هو أوّلُ ما يَلفتُ المُراجِع.
//
// ═══ ما لا يَحكمُ فيه هذا الحارس ═══
//
// موقعُ الخلفيّةِ على iOS (`UIBackgroundModes: location` + سلسلتا
// `...Always...`) **مُستعمَلٌ ضِمناً**: `driver_dashboard` يَفتحُ
// `Geolocator.getPositionStream`، والنمطُ المُعلَنُ هو ما يُبقيه يَبثُّ وقتَ
// تأنيبِ التطبيق — فحذفُه يُجمّدُ خريطةَ التتبُّعِ عند العميلةِ لحظةَ أن
// يُغادِرَ السائقُ الشاشة. وأندرويد **بلا** `ACCESS_BACKGROUND_LOCATION` ولا
// خدمةِ مُقدِّمة — و**هذا قرارٌ مسجَّلٌ لا سهو**: تعليقُ بيانِ أندرويد
// (2026-07-19) يَقولُ إنّ كلَّ واحدٍ منها «يُفعّل بوّابة إقرار سياسة في
// Google Play تمنع النشر»، ويُقرّرُ أنّ «التتبّع يعمل والتطبيق مفتوح فقط
// ويتوقّف عند تصغيره — مقبول للإطلاق التجريبي»، ويَكتبُ خطواتَ الاستعادة.
// فالفحصُ يُثبّتُ الطرفَين **وبقاءَ ذلك التعليقِ بعينِه**، لأنّ فقدَه يَعني
// أن يُعيدَ أحدٌ الإذنَ بلا علمٍ ببوّابةِ Play التي تَنتظرُه.
//
// وأوّلُ صياغةٍ لهذا الفحصِ سقطت على ذلك التعليقِ نفسِه (بَحثَ عن اسمِ
// الإذنِ في النصِّ الخامّ فوجدَه داخلَ شرحِ قرارِ غيابِه) — الفخُّ المسجَّلُ
// تسعَ مرّاتٍ في هذه الجلسة، وعاشرُها هنا على توثيقٍ **سابقٍ** لا على
// توثيقي: يُجرَّدُ التعليقُ، ثمّ يُؤكَّدُ بقاؤه في الخامّ.
//
// وزيادةٌ على الدرس: **التجريدُ بالبادئةِ لا يَكفي في XML**. تعليقُ
// `<!-- … -->` يَمتدُّ أسطُراً، وأسطُرُه التاليةُ نصٌّ عارٍ بلا علامة —
// فمُرشِّحُ «السطرُ يَبدأُ بـ`<!--`» أبقى السطرَ الثانيَ من ذلك الشرحِ،
// وفيه اسمُ الإذنِ بعينِه. الحجبُ بالحالةِ (`_stripXmlComments`) لا
// بالبادئة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يَحجبُ تعليقاتِ XML/plist **بالحالةِ لا بالبادئة**.
///
/// تعليقُ `<!-- … -->` يَمتدُّ أسطُراً، و**أسطُرُه التاليةُ نصٌّ عارٍ** بلا
/// أيِّ علامة — فمُرشِّحُ «السطرُ يَبدأُ بـ`<!--`» يُبقي أغلبَ التعليقِ.
/// وهو ما أسقطَ أوّلَ صياغةِ هذا الحارس: اسمُ `ACCESS_BACKGROUND_LOCATION`
/// في السطرِ **الثاني** من شرحِ قرارِ غيابِه، فقُرِئ إعلاناً.
String _stripXmlComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final open = src.indexOf('<!--', i);
    if (open < 0) {
      out.write(src.substring(i));
      break;
    }
    out.write(src.substring(i, open));
    final close = src.indexOf('-->', open + 4);
    if (close < 0) break; // تعليقٌ غيرُ مُغلَق: لا شيءَ بعدَه شفرة
    i = close + 3;
  }
  return out.toString();
}

const String _manifest = 'android/app/src/main/AndroidManifest.xml';
const String _plist = 'ios/Runner/Info.plist';

/// نصُّ كلِّ ملفّات Dart في `lib/` مُجمَّعاً — شاهدُ الاستعمال.
String _libSource() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n');

void main() {
  final String manifest = File(_manifest).readAsStringSync();
  final String plist = File(_plist).readAsStringSync();
  final String lib = _libSource();

  /// الصلاحيّاتُ المُعلَنةُ على أندرويد — **من غيرِ أسطرِ التعليق**، لأنّ
  /// التعليقَ يُسمّي المحذوفَ ليَشرحَ حذفَه (الفخُّ الذي أسقطَ تسعةَ حُرّاسٍ
  /// في هذه الجلسةِ على توثيقِها).
  Set<String> androidPermissions() {
    final code = _stripXmlComments(manifest);
    return RegExp(r'android\.permission\.([A-Z_]+)')
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// مفاتيحُ أسبابِ الاستعمالِ على iOS — من غيرِ التعليق، للسببِ نفسِه.
  Set<String> iosUsageKeys() {
    final code = _stripXmlComments(plist);
    return RegExp(r'<key>(NS\w*UsageDescription)</key>')
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// لكلِّ صلاحيّةٍ: شاهدُ استعمالٍ في `lib/` وسببُ إدراجِها.
  const androidWitness = <String, List<String>>{
    'INTERNET': ['FirebaseFirestore', 'كلُّ نداءٍ شبكيّ'],
    'ACCESS_FINE_LOCATION': ['Geolocator', 'تحديدُ المنطقةِ وتتبُّعُ السائق'],
    'ACCESS_COARSE_LOCATION': ['Geolocator', 'بديلٌ أخفُّ لنفسِ الميزة'],
    'CAMERA': ['ImageSource.camera', 'صورةُ إثباتِ الإنجازِ وصورةُ العاملة'],
    'POST_NOTIFICATIONS': ['FirebaseMessaging', 'دفعاتُ الطلبِ والدفع'],
    'WAKE_LOCK': ['FirebaseMessaging', 'يَلزمُه استقبالُ الدفعةِ والجهازُ نائم'],
  };

  const iosWitness = <String, List<String>>{
    'NSLocationWhenInUseUsageDescription': [
      'Geolocator', 'تحديدُ المنطقةِ أثناء الاستعمال',
    ],
    'NSLocationAlwaysAndWhenInUseUsageDescription': [
      'getPositionStream', 'بثُّ موقعِ السائقِ ووقتَ تأنيبِ التطبيق',
    ],
    'NSLocationAlwaysUsageDescription': [
      'getPositionStream', 'نظيرُها لنسخِ iOS الأقدم',
    ],
    'NSCameraUsageDescription': ['ImageSource.camera', 'التصويرُ داخلَ التطبيق'],
    'NSPhotoLibraryUsageDescription': [
      'ImageSource.gallery', 'اختيارُ صورةٍ من المكتبة',
    ],
  };

  test('الاستخراجُ يَجدُ الإعلاناتِ فعلاً — وإلّا فالفحوصُ جوفاء', () {
    expect(androidPermissions().length, greaterThanOrEqualTo(5));
    expect(iosUsageKeys().length, greaterThanOrEqualTo(4));
  });

  test('مجموعةُ صلاحيّاتِ أندرويد = مجموعةُ ما له شاهد', () {
    // مقارنةُ المجموعةِ كاملةً: صلاحيّةٌ تُضافُ بلا شاهدٍ تَسقطُ هنا،
    // وشاهدٌ لصلاحيّةٍ أُزيلت يَسقطُ كذلك — فلا تَتعفّنُ القائمةُ.
    expect(androidPermissions(), androidWitness.keys.toSet(),
        reason: 'الصلاحيّاتُ والشواهدُ افترقت — صلاحيّةٌ بلا ميزةٍ هي سؤالُ '
            'مُراجِعٍ مضمون، وسياسةُ Play تَشترطُ ميزةً ظاهرة');
  });

  test('ومجموعةُ أسبابِ iOS = مجموعةُ ما له شاهد', () {
    expect(iosUsageKeys(), iosWitness.keys.toSet(),
        reason: 'أسبابُ الاستعمالِ والشواهدُ افترقت');
  });

  test('ولكلِّ شاهدٍ وجودٌ في lib/ — لا قائمةً تُصدّقُ نفسَها', () {
    for (final e in {...androidWitness, ...iosWitness}.entries) {
      expect(lib.contains(e.value[0]), isTrue,
          reason: 'شاهدُ ${e.key} (${e.value[0]}) اختفى من lib/ — '
              'إن زالت الميزةُ فاحذِفِ الصلاحيّةَ، لا الشاهدَ من الحارس');
    }
  });

  test('الميكروفونُ لا يعود — ولا تابي سبباً لصلاحيّة', () {
    expect(androidPermissions().contains('RECORD_AUDIO'), isFalse,
        reason: 'عادَ RECORD_AUDIO — ولا ميزةَ صوتٍ في المستودعِ كلِّه');
    expect(iosUsageKeys().contains('NSMicrophoneUsageDescription'), isFalse,
        reason: 'عادَ سببُ الميكروفون — ولا طالبَ له');
    // ولا استعمالَ حقيقيّاً يُبرّرُ عودتَهما.
    for (final needle in const ['Permission.microphone', 'RecorderController',
      'startRecording', 'AudioRecorder']) {
      expect(lib.contains(needle), isFalse,
          reason: 'ظهرَ $needle — فالميزةُ وُلدت ويَلزمُها إعلانٌ وشاهدٌ هنا');
    }
    // والمضادّة: شرحُ الحذفِ (ومنه اسمُ تابي) ما زال في الخامِّ، فالفحوصُ
    // أعلاه تَقرأُ المُجرَّدَ من التعليق — ولو أفرطَ التجريدُ لَما بقي شاهد.
    expect(File(_manifest).readAsStringSync().contains('RECORD_AUDIO'), isTrue,
        reason: 'اختفى شرحُ الحذفِ — فتُعادُ الصلاحيّةُ بلا علمٍ بسببِ زوالِها');
    expect(File(_plist).readAsStringSync().contains('تابي'), isTrue,
        reason: 'اختفى ذكرُ السببِ القديم — وهو شاهدُ العطل');
  });

  test('التباينُ المُعلَن: موقعُ الخلفيّةِ على iOS ولا نظيرَ له في أندرويد', () {
    // ليس حُكماً — تثبيتُ الحالةِ القائمةِ كي يُراجَعَ أيُّ تغيُّرٍ فيها
    // بوعيٍ بنموذجِ إقرارِ Play الذي يَستلزمُه الطرفُ الآخر.
    expect(plist.contains('<string>location</string>'), isTrue,
        reason: 'زالَ نمطُ الخلفيّةِ — فبثُّ موقعِ السائقِ يَتوقّفُ عند '
            'تأنيبِ التطبيقِ وتَجمدُ خريطةُ العميلة');
    // **مُجرَّداً من التعليق**: الإذنُ غائبٌ عن الشفرةِ وحاضرٌ في شرحِ
    // غيابِه، فالبحثُ في الخامِّ يَقرأُ الشرحَ إعلاناً (وهو ما حدث).
    final manifestCode = _stripXmlComments(manifest);
    expect(manifestCode.contains('ACCESS_BACKGROUND_LOCATION'), isFalse,
        reason: 'أُضيف موقعُ الخلفيّةِ لأندرويد — يَستلزمُ خدمةَ مُقدِّمةٍ '
            'ونموذجَ إقرارِ Play ومراجعتَه: قرارُ المالك');
    expect(manifestCode.contains('FOREGROUND_SERVICE'), isFalse,
        reason: 'أُضيفت خدمةُ المُقدِّمة — نفسُ بوّابةِ الإقرار');
    // والمضادّة: قرارُ 2026-07-19 ما زال مكتوباً حيث يُقرأ.
    expect(manifest.contains('بوّابة إقرار سياسة في Google Play'), isTrue,
        reason: 'اختفى نصُّ القرارِ — فيُعادُ الإذنُ بلا علمٍ ببوّابةِ Play');
    expect(manifest.contains('foregroundNotificationConfig'), isTrue,
        reason: 'اختفت خطواتُ الاستعادةِ من التعليق');
    expect(lib.contains('getPositionStream'), isTrue,
        reason: 'زالَ بثُّ الموقعِ — فنمطُ الخلفيّةِ صارَ بلا مُستعمِل');
  });
}
