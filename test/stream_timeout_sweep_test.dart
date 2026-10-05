// حارس المسح: **كلُّ بثِّ Firestore في التطبيق محكومٌ بمهلةِ أوّلِ حدث.**
//
// العطلُ المرئيّ كان واحداً — دوّارُ «كوبونات الخصم المعتمدة» الذي لا ينتهي —
// لكنّ سببَه عامّ: مع `persistenceEnabled` وذاكرةٍ باردة، `snapshots()` لا
// يُصدر من المخزَّن (فارغ) ولا يرمي حين يتعذّر بلوغُ الخادم: **ينتظر**. فكلُّ
// `StreamBuilder` في المشروع كان عرضةً للشيء نفسه — شاشةُ المتجر هياكلَ
// تحميلٍ بلا نهاية، و`UserProvider.isLoading` عالقاً على `true`، وشاشةُ
// الشروط دوّاراً بدل النصِّ الاحتياطيّ.
//
// وهذا هو المسحُ المكافئُ لـ`net_timeout_guard` على جانب البثوث: ذاك غطّى
// `get()` و`httpsCallable` و`signIn`، وبقي `snapshots()` خارجه.
//
// القاعدةُ بسيطةٌ عمداً كي لا تحتاج اجتهاداً: **أيُّ `.snapshots()` تحت `lib/`
// يجب أن تُتبَع — في السلسلة نفسِها — بـ`.firstEventTimeout()`.** الاستثناءُ
// الوحيد هو ملفُّ القاعدة نفسُه.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يحجب التعليقاتِ دون إزاحةِ المواضع — نحتاج المواضعَ لنقرأ ما بعد كلِّ نداء.
String _maskComments(String src) {
  final b = StringBuffer();
  var i = 0;
  var inStr = false;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    if (inStr) {
      b.write(c);
      if (c == r'\' && i + 1 < src.length) {
        b.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) inStr = false;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      inStr = true;
      quote = c;
      b.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        b.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        b.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      b.write('  ');
      i += 2;
      continue;
    }
    b.write(c);
    i++;
  }
  return b.toString();
}

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('utils/net_timeout.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('المسحُ يقرأ ملفّاتٍ فعلاً (حارسٌ أجوفُ أسوأُ من لا حارس)', () {
    expect(files.length, greaterThan(100));
  });

  /// نصُّ العبارةِ من موضعٍ حتى أوّلِ `;` أو `,` على عمقِ أقواسٍ صفر.
  String statementAfter(String code, int from) {
    final after = code.substring(from);
    var depth = 0;
    var end = after.length;
    for (var i = 0; i < after.length; i++) {
      final c = after[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) {
          end = i;
          break;
        }
        depth--;
      }
      if (depth == 0 && (c == ';' || c == ',')) {
        end = i;
        break;
      }
    }
    return after.substring(0, end);
  }

  /// **الاستثناءُ الوحيدُ المعلَّل: بثٌّ يُسلَّمُ إلى دامجٍ مؤقَّتِ المَخرَج.**
  ///
  /// تضييقُ قراءةِ `promo_codes` جعلَ شاشةَ العروضِ استعلامَين (المُعلَنُ،
  /// والموجَّهُ إلى العميلة) يُدمَجانِ بـ`combineLatestById`. والمهلةُ على
  /// **المَخرَجِ** لا على كلِّ مصدرٍ عن قصد: مهلتانِ متسابقتانِ تَجعلانِ
  /// تعذُّرَ أحدِ الاستعلامَين خطأً يَحجبُ القسمَ كلَّه، بينما المطلوبُ أن
  /// يُعرَضَ ما وصلَ أو يُعرَضَ خطأ. فالموضعُ يُعفى **فقط** إن كان ملفُّه
  /// يَستعملُ الدامجَ وكلُّ نداءٍ للدامجِ فيه مؤقَّت — فدامجٌ جديدٌ بلا مهلةٍ
  /// لا يُعفي شيئاً.
  bool combinatorTimed(String code) {
    var i = code.indexOf('combineLatestById');
    if (i < 0) return false;
    while (i >= 0) {
      if (!statementAfter(code, i).contains('.firstEventTimeout()')) {
        return false;
      }
      i = code.indexOf('combineLatestById', i + 1);
    }
    return true;
  }

  group('كلُّ snapshots() محكومةٌ بمهلة', () {
    var total = 0;
    var exempt = 0;
    for (final f in files) {
      final code = _maskComments(f.readAsStringSync());
      if (!code.contains('.snapshots()')) continue;
      final rel = f.path;
      var idx = 0;
      var n = 0;
      while (true) {
        idx = code.indexOf('.snapshots()', idx);
        if (idx < 0) break;
        n++;
        total++;
        final m = n;
        // **الموضعُ يُلتقط قبل التسجيل**: إغلاقُ `test` يُنفَّذ لاحقاً، وقراءةُ
        // `idx` المتحوّلة حينها تقرأ آخرَ قيمةٍ لها فيفشل كلُّ فحصٍ بلا سبب.
        final at = idx;
        final inStatement =
            statementAfter(code, at + '.snapshots()'.length)
                .contains('.firstEventTimeout()');
        final viaCombinator = !inStatement && combinatorTimed(code);
        if (viaCombinator) exempt++;
        test('$rel — النداء $m', () {
          // يكفي أن تظهر `.firstEventTimeout()` بعدها وقبل نهايةِ العبارة
          // (أوّلُ `;` أو `,` على مستوى عمقٍ صفرٍ من الأقواس بعد النداء)،
          // أو أن يُسلَّمَ البثُّ إلى دامجٍ مَخرَجُه مؤقَّت (انظر أعلاه).
          expect(inStatement || viaCombinator, isTrue,
              reason: 'بثٌّ بلا مهلةِ أوّلِ حدث في $rel — مع ذاكرةٍ باردةٍ '
                  'وخادمٍ بعيدٍ ينتظر إلى الأبد، فيبقى الدوّار/الهيكل ولا '
                  'يُعرض خطأٌ أبداً');
        });
        idx += 1;
      }
    }

    test('العددُ المحروس كما هو تقريباً (نقصٌ مفاجئ = نداءٌ اختفى من المسح)', () {
      expect(total, greaterThanOrEqualTo(50),
          reason: 'كانت 53 عند كتابة الحارس (21 شاشةَ عميلٍ وسائق، 26 شاشةَ '
              'إدارة، 2 في main، 4 في الخدمات/المزوّدات/الودجات)؛ هبوطٌ حادٌّ '
              'يعني أنّ الحجبَ أكل الشيفرةَ لا أنّ البثوثَ اختفت');
    });

    test('والمُعفى بالدامجِ اثنان بالضبط — ثالثٌ يُراجَع', () {
      // استعلاما شاشةِ العروضِ وحدَهما: المُعلَنُ، والموجَّهُ إلى العميلة.
      // عدٌّ لا «أكثرُ من صفر»: استثناءٌ مفتوحٌ يَصيرُ بابَ تسلُّلٍ لكلِّ
      // بثٍّ بلا مهلةٍ في ملفٍّ يَستعملُ الدامجَ لسببٍ آخر.
      expect(exempt, 2,
          reason: 'عددُ البثوثِ المُعفاةِ بالدامجِ تغيّر — راجِعْ أيُّها '
              'وهل مَخرَجُه مؤقَّتٌ فعلاً');
    });
  });

  test('الامتدادُ والثابتُ ما زالا موجودَين', () {
    final src = File('lib/utils/net_timeout.dart').readAsStringSync();
    expect(src.contains('extension ZyiarahStreamFirstEventTimeout<T> on Stream<T>'),
        isTrue);
    expect(src.contains('const Duration kStreamFirstEventTimeout'), isTrue);
    // المهلةُ لأوّل حدثٍ وحده — لا تتحوّل إلى `Stream.timeout` العاديّة التي
    // تُوقِّت كلَّ فجوة، فتكسر مستمِعاً سليماً يسكت حين لا يتغيّر شيء.
    expect(src.contains('arrived = true'), isTrue);
  });
}
