import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «فشلُ بثٍّ يُرسَمُ لا شيء» — نظيرُ الدارت لعطلِ مستمعاتِ اللوحة.
///
/// `firstEventTimeout` حوّلَ التعليقَ الأبديَّ إلى **خطأ**، وبذلك صارت فروعُ
/// الخطأِ قابلةَ الوصولِ أصلاً — فمَن لا يَفحصُ `hasError` يَسقطُ إلى فرعِ
/// «لا بيانات»، فتُقرأُ النتيجةُ **دعوى** عن الواقع: «لا طلبَ لي»، «جاري
/// التعيين...»، «لا عمليات بث»، أو دوّارةٌ لا تَنتهي.
///
/// والفحصُ يَشتقُّ النطاقَ من المصدرِ ويُقارِنُ **مجموعةَ** الصامتِ كاملةً
/// بقائمةٍ مُعلَنةٍ لكلٍّ سببُه — فمستمعٌ جديدٌ صامتٌ يُراجَعُ بدلَ أن يَمرّ.
String _read(String p) => File(p).readAsStringSync();

/// يَحجبُ أسطرَ التعليقِ بالفراغِ مع حفظِ الإزاحات: تعليقاتُ هذا الإصلاحِ
/// تَقتبسُ `hasError` و`StreamBuilder` نفسَيهما.
String _code(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('/*') || t.startsWith('*'))
          ? ''
          : l;
    })
    .join('\n');

/// يُوازنُ من المحرفِ الفاتحِ `i` ويُعيدُ ما بعدَ مُطابِقِه.
///
/// الحدُّ بالموازنةِ لا بأوّلِ محرفٍ مُطابِق: أخذُ أوّلِ `{` بعد اسمِ دالّةٍ
/// يَلتقطُ قوسَ المعامَلاتِ المُسمّاة `{required …}` لا جسمَها — وهو الفخُّ
/// الذي أعقمَ حُرّاساً هنا مرّاتٍ، وقد أعقمَ الصياغةَ الأولى من هذا الفحصِ
/// فأعلنَت `admin_orders_screen` صامتاً وفرعُه موجودٌ في `_buildBody`.
int _balance(String s, int i, String opens, String closes) {
  var d = 0;
  while (i < s.length) {
    final c = s[i];
    if (opens.contains(c)) d++;
    if (closes.contains(c)) d--;
    i++;
    if (d == 0) return i;
  }
  return s.length;
}

const _keywords = {'if', 'for', 'while', 'switch', 'return', 'assert', 'else'};

/// كلُّ `StreamBuilder` لا يَفحصُ `hasError` — لا في جسمِه ولا في مُعاونٍ
/// يُمرَّرُ إليه الـsnapshot. المفتاحُ ملفٌّ وترتيبٌ لا رقمُ سطر.
List<String> silentStreamBuilders() {
  final out = <String>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final s = _code(f.readAsStringSync());
    var ordinal = 0;
    for (final m in RegExp(r'StreamBuilder[<\s]').allMatches(s)) {
      final op = s.indexOf('(', m.end - 1);
      if (op < 0) continue;
      ordinal++;
      final body = s.substring(op, _balance(s, op, '([{', ')]}'));
      if (body.contains('hasError')) continue;
      final bm =
          RegExp(r'builder:\s*\(\s*\w+\s*,\s*(\w+)\s*\)').firstMatch(body);
      var handled = false;
      if (bm != null) {
        final v = bm.group(1)!;
        for (final call
            in RegExp('(_?\\w+)\\s*\\([^()]*\\b$v\\b').allMatches(body)) {
          final fn = call.group(1)!;
          if (_keywords.contains(fn)) continue;
          final dm = RegExp('\\n\\s*[\\w<>,\\s]+\\s$fn\\s*\\(').firstMatch(s);
          if (dm == null) continue;
          final par = s.indexOf('(', dm.end - 1);
          final after = _balance(s, par, '(', ')');
          final j = s.indexOf('{', after);
          if (j < 0) continue;
          if (s.substring(j, _balance(s, j, '{', '}')).contains('hasError')) {
            handled = true;
            break;
          }
        }
      }
      if (!handled) out.add('${f.path}#$ordinal');
    }
  }
  return out;
}

void main() {
  group('لا بثَّ يَفشلُ فيُقرأُ «لا شيء»', () {
    test('(أ) المسحُ يَعملُ فعلاً — ويَرى الإحالةَ إلى مُعاون', () {
      // حارسٌ عقيمٌ أسوأُ من لا حارس: نُثبِتُ أنّ المُحلِّلَ وجدَ بثوثاً،
      // وأنّه يَرى الفرعَ المُحالَ إلى مُعاونٍ (فلا يُبلِّغُ زوراً).
      final n = RegExp(r'StreamBuilder[<\s]')
          .allMatches(_code(_read('lib/screens/admin/admin_orders_screen.dart')))
          .length;
      expect(n, greaterThanOrEqualTo(1));
      final silent = silentStreamBuilders();
      expect(silent.length, lessThan(20),
          reason: 'انهيارُ المُحلِّلِ يُبلِّغُ كلَّ شيءٍ صامتاً');
      expect(silent.any((k) => k.contains('admin_orders_screen')), isFalse,
          reason: 'فرعُه في `_buildBody` — إحالةٌ يَجبُ أن تُقرأ');
      expect(silent.any((k) => k.contains('offers_screen')), isFalse,
          reason: 'فرعُه في `_content`');
    });

    test('(ب) مجموعةُ الصامتِ كاملةً = القائمةُ المُعلَنةُ بأسبابِها', () {
      const allowed = <String, String>{
        // بوّابةُ الصيانةِ **تَفشلُ مفتوحةً** بقرارٍ موثَّق: خطأُ القراءةِ
        // لا يَجوزُ أن يُقفلَ التطبيقَ على العميلة.
        'lib/main.dart#1': 'fail-open مقصودٌ وموثَّق',
        // شريطُ العروضِ التسويقيُّ: غيابُه لا يَقولُ شيئاً عن حالةِ شيء.
        'lib/screens/client_dashboard.dart#3': 'بانر تسويقيّ، لا دعوى',
        // شارةُ عددِ غيرِ المقروء: غيابُ شارةٍ ليس جملةً.
        'lib/screens/client_dashboard.dart#4': 'شارةُ عدّادٍ، لا دعوى',
        // مؤقّتاتٌ محلّيّةٌ (`elapsedSinceStream`) لا شبكةَ فيها، فلا خطأ.
        'lib/screens/driver_dashboard.dart#4': 'مؤقّتٌ محلّيٌّ لا شبكة',
        'lib/screens/order_tracking_screen.dart#2': 'مؤقّتٌ محلّيٌّ لا شبكة',
        'lib/screens/admin/admin_order_details_screen.dart#1':
            'مؤقّتٌ محلّيٌّ لا شبكة',
        // الشروطُ والخصوصيّة: الفشلُ يَسقطُ على النصِّ الثابتِ بقرارٍ
        // موثَّقٍ («المنشورُ إن وُجد، وإلّا الثابت») — وهو الصوابُ هنا.
        'lib/screens/terms_privacy_screens.dart#1': 'يَسقطُ على النصِّ الثابت',
        'lib/screens/terms_privacy_screens.dart#2': 'يَسقطُ على النصِّ الثابت',
      };
      expect(silentStreamBuilders().toSet(), allowed.keys.toSet(),
          reason: 'بثٌّ صامتٌ جديدٌ يُراجَعُ ويُعلَّل، لا يُضَمُّ بسماحٍ عامّ');
    });

    test('(ج) الخمسةُ المُصلَحةُ تَقولُ ما حدثَ، ولا تَدّعي حالة', () {
      final cases = <String, List<String>>{
        'lib/screens/map_screen.dart': [
          'هذه ليست حالة الطلب.',
        ],
        'lib/screens/admin/admin_managers_screen.dart': [
          'تعذّر البحث في قائمة المديرين',
        ],
        'lib/screens/admin/admin_broadcast_screen.dart': [
          'ليست «لا عمليات»',
        ],
        'lib/screens/client_dashboard.dart': [
          "_buildCardLoadError('طلبكِ الجاري')",
          "_buildCardLoadError('باقتكِ')",
          'لا يعني هذا أنه غير موجود.',
        ],
      };
      cases.forEach((f, needles) {
        final c = _code(_read(f));
        for (final n in needles) {
          expect(c, contains(n), reason: '$f → $n');
        }
      });
    });

    test('(د) فرعُ الخطأِ يَسبقُ فرعَ «لا بيانات» في كلِّ موضعٍ مُصلَح', () {
      // الترتيبُ هو الإصلاح: `!hasData` صحيحٌ على الخطأِ أيضاً، فلو سبقَ
      // لَأَكلَ الفرعَ الجديدَ وبقي العطلُ كما هو بزينةٍ فوقَه.
      const pairs = <String, (String, String)>{
        'lib/screens/admin/admin_managers_screen.dart': (
          'تعذّر البحث في قائمة المديرين',
          'if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());'
        ),
        'lib/screens/admin/admin_broadcast_screen.dart': (
          'تعذّر تحميل سجل البث',
          'if (!snapshot.hasData) return const SizedBox.shrink();'
        ),
        'lib/screens/map_screen.dart': (
          'هذه ليست حالة الطلب.',
          "final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};\n\n        final driverName"
        ),
      };
      pairs.forEach((f, v) {
        final c = _code(_read(f));
        expect(c.indexOf(v.$1), greaterThan(-1), reason: f);
        expect(c.indexOf(v.$2), greaterThan(-1), reason: f);
        expect(c.indexOf(v.$1), lessThan(c.indexOf(v.$2)), reason: f);
      });
    });

    test('(ه) `firstEventTimeout` هو ما يُتيحُ الخطأَ أصلاً', () {
      // بلا المهلةِ يَبقى البثُّ معلّقاً فلا يَصِلُ `hasError` قطّ، فكلُّ ما
      // أعلاه يُصيرُ زينةً. فلو زالت المهلةُ عن بثٍّ مُصلَحٍ فالقرارُ يُراجَع.
      for (final f in [
        'lib/screens/admin/admin_managers_screen.dart',
        'lib/screens/admin/admin_broadcast_screen.dart',
        'lib/screens/client_dashboard.dart',
      ]) {
        expect(_code(_read(f)), contains('.firstEventTimeout()'), reason: f);
      }
    });

    test('(و) القاعدةُ كانت مُنفَّذةً في الملفّاتِ نفسِها — فلا تُنقَض', () {
      // الحارسُ يُثبِّتُ الفروعَ **السابقةَ** في الملفَّين كذلك: هي شاهدُ
      // أنّ القاعدةَ معروفةٌ، وزوالُها يُعيدُ العطلَ من الطرفِ الآخر.
      expect(_code(_read('lib/screens/admin/admin_managers_screen.dart')),
          contains('إعادة المحاولة'));
      expect(_code(_read('lib/screens/map_screen.dart')),
          contains('تعذّر تحميل بيانات التتبع'));
      final b = _code(_read('lib/screens/admin/admin_broadcast_screen.dart'));
      expect(b, contains("code == 'permission-denied'"));
    });
  });
}
