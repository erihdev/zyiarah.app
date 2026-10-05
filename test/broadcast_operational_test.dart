import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **بثٌّ تشغيليٌّ لا سبيلَ إلى إرساله من لوحةِ الويب.**
///
/// `notify_prefs.isMarketingBroadcast(data)` = `data.operational !== true` —
/// فكلُّ بثٍّ **تسويقيٌّ افتراضياً**، و`_deliverBroadcast` يُسقط عنه كلَّ من
/// أوقف «العروض والتسويق» (بوشاً وصندوقاً داخل التطبيق معاً).
///
/// ومحرّرُ Flutter (`admin_broadcast_screen`) يَملكُ مُبدِّلاً صريحاً لهذا
/// («إشعار تشغيلي — يصل حتى لمن أوقف العروض») ويَكتبُ `operational`.
/// ولوحةُ الويبِ (`Notifications.tsx`) **لم تَكُن تَكتبُ الحقلَ إطلاقاً**.
///
/// فإشعارُ صيانةٍ أو انقطاعٍ أو تغييرِ مواعيدَ يُرسَل من اللوحةِ كان يُحجَب
/// عن كلِّ عميلةٍ أوقفت التسويق — واللوحةُ تُظهرُ «أُرسل بنجاح» وصفُّ السجلِّ
/// يبدو عاديّاً. لا خطأ، لا تحذير، ولا أثرَ في أيِّ مكان.
///
/// وهي الشكلُ الثالثُ نفسُه في هذا المستودع: محرّران لمستندٍ واحدٍ وأحدُهما
/// يُغفل حقلَ قرار (مفاتيحُ الإصدارِ الإجباريّ، ثمّ `show_in_offers` في
/// الكوبونات). فالحارسُ هنا يُقارن **مجموعةَ حقولِ القرار** لا وجودَ حقلٍ بعينه.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  final dartEditor = read('lib/screens/admin/admin_broadcast_screen.dart');
  final webEditor = read('admin_panel/src/pages/Notifications.tsx');
  final prefs = read('functions/notify_prefs.js');
  final idx = read('functions/index.js');

  group('القاعدةُ الخادميّة', () {
    test('كلُّ بثٍّ تسويقيٌّ إلّا ما وُسم operational', () {
      expect(stripLineComments(prefs), contains('data.operational !== true'),
          reason: 'القاعدةُ تغيّرت — أعِد تقييمَ المحرّرَين معها');
    });

    test('والتسويقيُّ يُسقط من أوقف العروض — بوشاً وصندوقاً', () {
      final code = stripLineComments(idx);
      expect(code, contains('isMarketingBroadcast(data)'));
      // الإسقاطُ في المسارَين: رموزُ الأجهزة، ومستندُ الصندوق لكلِّ مستخدم.
      expect('excludeOptedOut('.allMatches(code).length, greaterThanOrEqualTo(2),
          reason: 'الإسقاطُ في مسارٍ واحدٍ فقط — فالحجبُ غيرُ متّسق');
    });
  });

  group('المحرّران يَملكان القرارَ نفسَه', () {
    test('محرّرُ Flutter يَكتبُ operational ويَعرضُ مُبدِّله', () {
      expect(dartEditor, contains("'operational': _operational"));
      expect(dartEditor, contains('إشعار تشغيلي'));
    });

    test('ولوحةُ الويبِ كذلك — وهذا ما كان ناقصاً', () {
      final web = stripLineComments(webEditor);
      expect(web, contains('operational: isOperational'),
          reason: 'اللوحةُ لا تَكتبُ الحقل: كلُّ إشعارٍ منها يُحجَب عمّن '
              'أوقف التسويق، ولو كان إشعارَ انقطاعِ خدمة');
      expect(web, contains('aria-label="إشعار تشغيلي"'),
          reason: 'حقلٌ يُكتب بلا مُبدِّلٍ يَراه الأدمن = قرارٌ لا يستطيع اتّخاذه');
      expect(web, contains('setIsOperational(false)'),
          reason: 'لا يُعاد ضبطُه بعد الإرسال — فيَلتصقُ «تشغيلي» بالبثِّ التالي');
    });

    test('ونصُّ المُبدِّلَين واحدٌ: الفرقُ قرارٌ لا ذوق', () {
      for (final line in [
        'إشعار تشغيلي (يصل حتى لمن أوقف العروض)',
        'صيانة أو انقطاع أو تنبيه مواعيد — يصل كل المستهدفين',
      ]) {
        expect(dartEditor, contains(line), reason: 'Flutter: $line');
        expect(webEditor, contains(line), reason: 'الويب: $line');
      }
    });

    test('ولا محرّرَ ثالثٌ يَكتبُ notifications_log بلا القرار', () {
      // المقارنةُ على المجموعةِ كلِّها (كما في amounts.test.js): كاتبٌ ثالثٌ
      // يَسقطُ هنا بدل أن يُغفل الحقلَ بصمتٍ سنةً كاملة.
      final writers = <String>[];
      for (final f in [
        ...Directory('$repo/lib').listSync(recursive: true).whereType<File>(),
        ...Directory('$repo/admin_panel/src').listSync(recursive: true).whereType<File>(),
      ]) {
        if (!f.path.endsWith('.dart') && !f.path.endsWith('.tsx')) continue;
        if (f.path.contains('.test.')) continue;
        final src = stripLineComments(f.readAsStringSync());
        final writes = src.contains("collection('notifications_log').add(") ||
            src.contains("collection(db, 'notifications_log')") &&
                src.contains('addDoc(');
        if (writes) writers.add(f.path.substring(repo.length + 1));
      }
      expect(writers..sort(), [
        'admin_panel/src/pages/Notifications.tsx',
        'lib/screens/admin/admin_broadcast_screen.dart',
        // الجدولةُ من تطبيقِ الإدارةِ تَمرُّ بالخدمة، وهي تُمرّر `operational`
        // من الشاشةِ لا من افتراضٍ — فالكاتبُ الثالثُ ليس ثغرةً.
        'lib/services/zyiarah_messaging_service.dart',
      ], reason: 'كاتبٌ جديدٌ لـnotifications_log — هل يَكتبُ operational؟');

      // وكلُّ كاتبٍ منها يَكتبُ الحقلَ فعلاً — المجموعةُ وحدَها لا تَكفي.
      for (final w in writers) {
        expect(stripLineComments(read(w)), contains('operational'),
            reason: '$w يَكتبُ بثّاً بلا قرارِ تشغيليٍّ/تسويقيّ');
      }
      // والخدمةُ لا تُجبر مُستدعِيها على افتراضٍ: الشاشةُ تُمرّره صريحاً.
      expect(dartEditor, contains('operational: _operational'),
          reason: 'الشاشةُ تَتركُ الافتراضَ (false) فيُحجَب بثٌّ تشغيليٌّ مجدول');
    });
  });
}
