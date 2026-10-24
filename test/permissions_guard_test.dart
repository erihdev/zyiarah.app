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
// `...Always...`) **حُذِفَ في 2026-10-10** بعد أن رفضت أبل 1.2.50 بالبند
// 2.5.4 (لا ميزةَ تَستلزمُ موقعاً دائماً). فالتتبّعُ على iOS صارَ كأندرويد:
// يَعملُ والتطبيقُ مفتوحٌ ويَتوقّفُ عند تصغيره. وأندرويد **بلا** `ACCESS_BACKGROUND_LOCATION` ولا
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
    'WAKE_LOCK': [
      'FirebaseMessaging',
      'يَلزمُه استقبالُ الدفعةِ والجهازُ نائم'
    ],
  };

  const iosWitness = <String, List<String>>{
    'NSLocationWhenInUseUsageDescription': [
      'Geolocator',
      'تحديدُ المنطقةِ أثناء الاستعمال',
    ],
    'NSCameraUsageDescription': [
      'ImageSource.camera',
      'التصويرُ داخلَ التطبيق'
    ],
    'NSPhotoLibraryUsageDescription': [
      'ImageSource.gallery',
      'اختيارُ صورةٍ من المكتبة',
    ],
  };

  test('الاستخراجُ يَجدُ الإعلاناتِ فعلاً — وإلّا فالفحوصُ جوفاء', () {
    expect(androidPermissions().length, greaterThanOrEqualTo(5));
    // ثلاثةٌ منذ حذفِ سلسلتَي «دائماً» (2026-10-10): الموقعُ أثناء الاستعمال،
    // والكاميرا، ومكتبةُ الصور.
    expect(iosUsageKeys().length, greaterThanOrEqualTo(3));
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
    for (final needle in const [
      'Permission.microphone',
      'RecorderController',
      'startRecording',
      'AudioRecorder'
    ]) {
      expect(lib.contains(needle), isFalse,
          reason: 'ظهرَ $needle — فالميزةُ وُلدت ويَلزمُها إعلانٌ وشاهدٌ هنا');
    }
    // والمضادّة: شرحُ الحذفِ (ومنه اسمُ تابي) ما زال في الخامِّ، فالفحوصُ
    // أعلاه تَقرأُ المُجرَّدَ من التعليق — ولو أفرطَ التجريدُ لَما بقي شاهد.
    expect(File(_manifest).readAsStringSync().contains('RECORD_AUDIO'), isTrue,
        reason:
            'اختفى شرحُ الحذفِ — فتُعادُ الصلاحيّةُ بلا علمٍ بسببِ زوالِها');
    expect(File(_plist).readAsStringSync().contains('تابي'), isTrue,
        reason: 'اختفى ذكرُ السببِ القديم — وهو شاهدُ العطل');
  });

  test('ونصُّ السببِ يُسمّي ما يَحدثُ فعلاً — لا ميزةً لا وجودَ لها', () {
    // **الشواهدُ أعلاه تَشدُّ وجودَ المفتاح؛ وهذا يَشدُّ نصَّه.** نصُّ السببِ
    // يُقرأُ في **مراجعةِ أبل** وفي **نافذةِ الإذنِ** معاً، فهو دعوى — وكانت
    // دعوى كاذبةً في المفتاحَين:
    //   • الكاميرا: «مسح الـ QR Code الخاص بالفواتير أو تحديث صورة الملف
    //     الشخصي» — **ولا ماسحَ QR في المستودعِ إطلاقاً** (الـ`Barcode`
    //     الوحيدُ يُولِّدُ رمزاً في الـPDF لا يَقرؤه)، **ولا مسارَ صورةٍ
    //     شخصيّةٍ للعميلة**. والاستعمالاتُ الحقيقيّةُ أربعةٌ: إثباتٌ مع
    //     التقييمِ وثلاثُ شاشاتٍ إداريّة.
    //   • المكتبة: «حفظ صور الفواتير الضريبية» — **ولا شيءَ يَكتبُ إلى
    //     مكتبةِ الصور**؛ الفاتورةُ تُشارَكُ PDFاً.
    // وهو نظيرُ سببِ الميكروفونِ الذي كان يُسمّي «تابي» بعد إزالتِها.
    //
    // ولكلِّ دعوى محظورةٍ **شاهدُ غيابٍ** يُفحَصُ هنا، فالحظرُ مُبرهَنٌ لا
    // مزاجيّ؛ ولكلِّ مفتاحٍ كلمةٌ **مطلوبةٌ** تَربطُ النصَّ بالاستعمالِ القائم.
    const banned = <String, List<List<String>>>{
      // المفتاح: [[دعوى محظورة, شاهدُ غيابِها في lib/], …]
      'NSCameraUsageDescription': [
        ['QR', 'mobile_scanner'],
        ['مسح', 'qr_code_scanner'],
        ['الملف الشخصي', 'uploadProfilePhoto'],
      ],
      // رفضُ 1.2.50 (5.1.1(ii)): «أقرب سائق» دعوى لا ميزةَ لها — الإسنادُ
      // بالوقتِ لا بالمسافة، والنداءُ الخادميُّ الوحيدُ بالقُربِ بلا مُنادٍ.
      'NSLocationWhenInUseUsageDescription': [
        ['أقرب سائق', 'findNearestDrivers'],
      ],
      'NSPhotoLibraryUsageDescription': [
        ['حفظ', 'image_gallery_saver'],
        ['الفواتير', 'GallerySaver'],
        ['ملفك الشخصي', 'uploadProfilePhoto'],
      ],
    };
    const required = <String, List<String>>{
      // أبل تَطلبُ مثالاً محدّداً على الاستعمال، لا وصفاً عامّاً.
      'NSLocationWhenInUseUsageDescription': ['مثلاً', 'منطقة الخدمة'],
      'NSCameraUsageDescription': ['تقييم', 'الإدارة'],
      'NSPhotoLibraryUsageDescription': ['اختيار', 'الإدارة'],
    };
    final raw = File(_plist).readAsStringSync();
    for (final key in banned.keys) {
      final i = raw.indexOf('<key>$key</key>');
      expect(i, greaterThan(-1), reason: 'لم يُوجَد $key');
      final a = raw.indexOf('<string>', i);
      final b = raw.indexOf('</string>', a);
      expect(a, greaterThan(i));
      final text = raw.substring(a + '<string>'.length, b);
      for (final pair in banned[key]!) {
        // الحظرُ مُبرهَنٌ: الميزةُ المذكورةُ غائبةٌ عن `lib/` فعلاً.
        expect(lib.contains(pair[1]), isFalse,
            reason: 'ظهرَ ${pair[1]} في lib/ — فالميزةُ وُلدت، '
                'ويُراجَعُ حظرُ «${pair[0]}» لا يُطبَّق');
        expect(text.contains(pair[0]), isFalse,
            reason: '$key يَدّعي «${pair[0]}» ولا ميزةَ لها — '
                'سؤالُ مراجعةٍ، ونصٌّ كاذبٌ في نافذةِ الإذن');
      }
      for (final must in required[key]!) {
        expect(text.contains(must), isTrue,
            reason: '$key لا يُسمّي الاستعمالَ القائم («$must»)');
      }
    }
    // والمضادّة: شرحُ النصِّ القديمِ ما زال في الخامِّ حيث يُقرأ.
    expect(raw.contains('QR Code'), isTrue,
        reason: 'اختفى شرحُ الدعوى القديمةِ — فتُعادُ بلا علمٍ بسببِ زوالِها');
  });

  test(
      'لا موقعَ خلفيّةٍ على المنصّتَين: iOS بقرارِ مراجعةِ أبل وأندرويد بقرارِ Play',
      () {
    // رفضت أبل 1.2.50 بالبند 2.5.4 (2026-10-10): `UIBackgroundModes` يُعلِنُ
    // `location` ولا ميزةَ تَستلزمُ موقعاً دائماً. فحُذِفَ النمطُ وسلسلتا
    // `...Always...` (وجودُهما يَجعلُ geolocator يَطلبُ «دائماً» فتُسألُ عنه
    // المراجعةُ مرّةً أخرى). عودةُ أيٍّ منها رفضٌ ثالثٌ ما لم تُرفَقْ ميزةٌ
    // وتسجيلُ شاشةٍ في ملاحظاتِ المراجعة.
    final plistCode = plist.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    expect(plistCode.contains('<string>location</string>'), isFalse,
        reason:
            'عادَ نمطُ موقعِ الخلفيّةِ إلى Info.plist — سببُ رفضِ أبل 2.5.4');
    expect(plistCode.contains('NSLocationAlways'), isFalse,
        reason:
            'عادت سلسلةُ «دائماً» — geolocator يَطلبُ الإذنَ الدائمَ بوجودِها');
    // ومستلزمُه في الشفرة: تفعيلُ تحديثاتِ الخلفيّةِ بلا النمطِ المُعلَنِ
    // يُسقِطُ التطبيقَ على iOS.
    expect(lib.contains('allowBackgroundLocationUpdates: true'), isFalse,
        reason: 'allowBackgroundLocationUpdates: true بلا UIBackgroundModes '
            'location يُسقِطُ التطبيقَ على iOS');
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

  test('أنماطُ الخلفيّةِ على iOS = {remote-notification} — لا نمطَ بلا ميزة',
      () {
    // `fetch` كان مُعلَناً (2026-10-22) ولا BGTaskScheduler ولا حزمةَ جلبٍ
    // خلفيٍّ في المستودع. نمطٌ بلا ميزةٍ هو بندُ 2.5.4 الذي رُفضت به 1.2.50.
    // المجموعةُ كاملةً لا «لا يَحوي fetch»: نمطٌ ثالثٌ يُراجَعُ بدلَ أن يَمُرّ.
    final plistCode = plist.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    final m =
        RegExp(r'<key>UIBackgroundModes</key>\s*<array>([\s\S]*?)</array>')
            .firstMatch(plistCode);
    expect(m, isNotNull, reason: 'اختفت مصفوفةُ UIBackgroundModes');
    final modes = RegExp(r'<string>([^<]+)</string>')
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1)!)
        .toSet();
    expect(modes, {'remote-notification'},
        reason: 'نمطُ خلفيّةٍ بلا ميزةٍ تَستلزمُه — سؤالُ مُراجِعٍ مضمون');
    // والمضادّة: اسمُ النمطِ المحذوفِ ما زال في شرحِ حذفِه.
    expect(plist.contains('`fetch`'), isTrue,
        reason: 'اختفى شرحُ حذفِ fetch — فيُعادُ بلا علمٍ بسببِ زوالِه');
    // ولا جلبَ خلفيّاً دخلَ بلا أن يُراجَعَ هذا الفحص.
    for (final pkg in const ['background_fetch', 'workmanager']) {
      expect(File('pubspec.yaml').readAsStringSync().contains(pkg), isFalse,
          reason:
              'أُضيفت حزمةُ $pkg — فنمطُ fetch قد صارَ له مُستعمِلٌ: راجِع');
    }
  });

  test('لا حركةَ غيرَ مشفّرةٍ ولا معرّفَ إعلاناتٍ على أندرويد', () {
    // `usesCleartextTraffic="true"` كان مُعلَناً بلا نقطةِ http:// واحدةٍ في
    // lib/ أو functions/، ويُناقضُ جوابَ «مشفّرة أثناء النقل» في نموذجِ أمانِ
    // البيانات. و`AD_ID` يَدمجُه play-services-measurement تلقائيّاً، وإذنٌ
    // حاضرٌ في البيانِ المدمجِ وغائبٌ عن النموذجِ سببُ رفضٍ معروفٌ في Play.
    final code = _stripXmlComments(manifest);
    expect(code.contains('usesCleartextTraffic'), isFalse,
        reason: 'عادَ usesCleartextTraffic — ولا نقطةَ http:// تَستلزمُه');
    expect(
        RegExp(r'android:name="com\.google\.android\.gms\.permission\.AD_ID"\s+tools:node="remove"')
            .hasMatch(code),
        isTrue,
        reason: 'زالَ حذفُ AD_ID من الدمج — يَعودُ الإذنُ إلى البيانِ المدمج');
    expect(
        RegExp(r'android:name="google_analytics_adid_collection_enabled"\s+android:value="false"')
            .hasMatch(code),
        isTrue,
        reason: 'جمعُ معرّفِ الإعلاناتِ لم يَعُد مُطفأً');
    expect(code.contains('xmlns:tools='), isTrue,
        reason: 'tools:node="remove" بلا xmlns:tools لا يُترجَم');
    // والمضادّةُ على الخامّ: الشرحُ يُسمّي العلَمَ المحذوف.
    expect(manifest.contains('usesCleartextTraffic'), isTrue,
        reason: 'اختفى شرحُ حذفِ usesCleartextTraffic');
    // وشاهدُ التعليلِ: لا نقطةَ http:// في شفرةِ العميلِ خارجَ التعليقات.
    // مُجرَّداً من أسطرِ التعليق: `csv_export_util` يَقتبسُ `"http://…"` في
    // شرحِ حقنِ الصيغة — «الحارسُ يَسقطُ على توثيقِه».
    final libCode =
        lib.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    final httpInCode = RegExp(r'''['"]http://''').allMatches(libCode).length;
    expect(httpInCode, 0,
        reason: 'ظهرت نقطةُ http:// في lib/ — يُراجَعُ قرارُ حذفِ cleartext');
  });
}
