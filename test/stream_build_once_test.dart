// **بثُّ Firestore يُبنى مرّةً واحدةً، لا في كلِّ `build`.**
//
// كانت اثنانِ وعشرونَ موضعاً تُنشئُ سلسلةَ الاستعلامِ **داخلَ دالّةِ البناء**،
// فكلُّ `setState` — حرفٌ في حقلِ بحث، تبديلُ تبويب، فتحُ حوار، سحبٌ
// للتحديث — يُلغي مستمِعَ Firestore ويُنشئُ غيرَه. والبياناتُ لا تَختفي
// (`StreamBuilder` يَحفظُ آخرَ لقطةٍ عبرَ إعادةِ الاشتراك) فلا يُرى شيء،
// والكلفةُ حقيقيّة — **والأثرُ الأخطرُ أنّ `firstEventTimeout` تُستأنف**:
// هي تُسلِّحُ مؤقِّتاً **للحدثِ الأوّلِ وحدَه** لكلِّ اشتراك، فعلى وصلةٍ
// تَبدو قائمةً ولا تَنفُذ (بوّابةُ فندقٍ، وكيلٌ شفّاف) تُعادُ مهلةُ العشرينَ
// ثانيةً مع كلِّ حرفٍ يَكتبُه الأدمنُ في البحث — فلا يُبلَغُ فرعُ الخطأِ ولا
// زرُّ إعادتِه أبداً ما دامت أصابعُه على اللوح. وهو العطلُ بعينِه الذي وُجدت
// المهلةُ لأجلِه («نداءٌ معلّقٌ ليس خطأً»)، مُعاداً من حيثُ لا يُتوقَّع.
//
// **والقاعدةُ مقرَّرةٌ في المستودعِ ومُنفَّذةٌ في سطحٍ واحد**: ترويسةُ
// `driver_tasks_screen` تَقولُها بخطِّ كاتبِها («البثّان يُبنيان مرّةً
// واحدة، لا في كلّ `build`… وإعادةُ المحاولة كانت تعتمد على ذلك الأثر
// الجانبيّ عينِه — فصارت صريحة») — وهي النسخةُ الوحيدةُ التي طُبِّقت.
//
// **وفخُّ الإصلاحِ نفسُه**: زرُّ «إعادة المحاولة» كان `setState(() {})` في
// أحدَ عشَرَ موضعاً، وهو يَعملُ **فقط** بفضلِ ذلك الأثرِ الجانبيّ — فتثبيتُ
// البثِّ بلا تحويلِ الزرِّ يُحوّلُه إلى عدمِ عمل، أي «زرٌّ يُضغَطُ فلا يَحدثُ
// شيء» وهي عائلةٌ مسجَّلةٌ هنا. ولذلك يَشدُّ الفحصُ (٣) أنّ أيَّ ملفٍّ ثبَّتَ
// بثّاً لا يَحملُ ذلك الشكلَ إلّا بسببٍ مُعلَن.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// وسائطُ نداءٍ تَبدأُ عندَ [i] حتى فاصلةٍ على العمقِ صفر — لا شريحةَ عدِّ
/// أحرفٍ ولا `indexOf(',')`: سلسلةُ Firestore تَحملُ فواصلَ داخلَ أقواسِها.
String _arg(String s, int i) {
  var d = 0;
  var end = i;
  while (end < s.length) {
    final ch = s[end];
    if ('([{'.contains(ch)) {
      d++;
    } else if (')]}'.contains(ch)) {
      if (d == 0) break;
      d--;
    } else if (ch == ',' && d == 0) {
      break;
    }
    end++;
  }
  return s.substring(i, end);
}

void main() {
  final files = sourcesIn('lib', atLeast: 150);

  /// كلُّ موضعٍ يُنشئُ سلسلةَ Firestore **داخلَ** وسيطِ `stream:`/`future:`.
  final inline = <String>[];
  var hoists = 0;
  final hoisted = <String>[];
  final chainsMissingTimeout = <String>[];
  for (final f in files) {
    final code = stripComments(f.readAsStringSync());
    final rel = f.path.replaceAll(r'\', '/');
    var n = 0;
    for (final m in RegExp(r'\b(?:stream|future):\s*').allMatches(code)) {
      final expr = _arg(code, m.end);
      if (!expr.contains('snapshots()') && !expr.contains('.get()')) continue;
      inline.add('$rel#$n');
      n++;
    }
    // والمُثبَّتُ: `_x ??= …snapshots()` أو `.get()` في جالبٍ أو دالّة.
    for (final m in RegExp(r'\w+\s*\?\?=\s*').allMatches(code)) {
      final tail = code.substring(m.end, (m.end + 600).clamp(0, code.length));
      final stop = tail.indexOf(';');
      final body = stop < 0 ? tail : tail.substring(0, stop);
      if (!body.contains('snapshots()')) continue;
      hoists++;
      if (!hoisted.contains(rel)) hoisted.add(rel);
      if (!body.contains('firstEventTimeout')) {
        chainsMissingTimeout.add('$rel: ${body.trim().split('\n').first}');
      }
    }
  }

  test('(١) لا بثَّ يُنشَأُ داخلَ البناءِ إلّا بمفتاحٍ مُعلَن', () {
    // **القائمةُ بالسبب**: كلُّ باقٍ استعلامُه يَتبعُ قيمةً تَتغيّرُ (مُرشِّح،
    // تبويب، صفحة، معرّفُ عنصر) فإعادةُ فتحِه **مقصودة**، أو ودجةٌ لا تُعيدُ
    // بناءَ نفسِها أبداً فلا يَقعُ عليها الأثر.
    const declared = <String, String>{
      // الاستعلامُ يَتبعُ `seesAll` (دورُ المستخدم، يَصِلُ لاحقاً) فيُبنى معه.
      'lib/screens/admin/admin_broadcast_screen.dart#0': 'query يَتبعُ الدور',
      // `_pageSize` يَنمو بزرِّ «المزيد» — فإعادةُ الفتحِ هي الميزةُ نفسُها.
      'lib/screens/admin/admin_orders_screen.dart#0': '_pageSize يَنمو',
      'lib/screens/client_notifications_screen.dart#0': '_pageSize يَنمو',
      // `q` يَتبعُ اليومَ المختارَ في لوحِ المواعيد.
      'lib/screens/admin/admin_schedule_board_screen.dart#0': 'q يَتبعُ اليوم',
      // `statuses` وسيطُ التبويبِ (مفتوحة/مُسوّاة) — بثٌّ لكلِّ تبويب.
      'lib/screens/admin/admin_support_screen.dart#0': 'statuses تبويب',
      'lib/screens/support_screen.dart#0': 'statuses تبويب (ومعه _reloadKey)',
      // ورسائلُ تذكرةٍ بعينِها: البثُّ لكلِّ `ticketId`.
      'lib/screens/support_screen.dart#1': 'ticketId لكلِّ عنصر',
      // ودجاتٌ بلا حالةٍ ولا `setState` في ملفِّها: لا تُعيدُ بناءَ نفسِها،
      // وهي مساراتٌ مدفوعةٌ (route) لا تُعيدُ آباؤها البناءَ تحتَها.
      'lib/screens/contracts_list_screen.dart#0': 'StatelessWidget بلا setState',
      'lib/screens/driver_notifications_screen.dart#0':
          'StatelessWidget بلا setState',
      'lib/screens/driver_profile_screen.dart#0': 'بلا setState في الملفّ',
      // وداخلَ ورقةٍ سفليّةٍ يَبنيها `StatefulBuilder`: البثُّ يُفتَحُ عند
      // فتحِ الورقة، و`setSheetState` هو زرُّ الإعادةِ ولا شيءَ غيرُه يُعيدُ
      // بناءَها.
      'lib/widgets/support_fab.dart#0': 'ورقةٌ سفليّةٌ + StatefulBuilder',
    };
    expect(files.length, greaterThanOrEqualTo(150));
    expect(hoists, greaterThanOrEqualTo(20),
        reason: 'كاشفُ المُثبَّتِ انحلّ — فمقارنةُ الباقي بلا معنى');
    final unexpected =
        inline.where((k) => !declared.containsKey(k)).toList()..sort();
    expect(unexpected, isEmpty,
        reason: 'بثٌّ يُنشَأُ في البناءِ بلا سببٍ مُعلَن: $unexpected');
    final stale =
        declared.keys.where((k) => !inline.contains(k)).toList()..sort();
    expect(stale, isEmpty, reason: 'مُدخَلٌ مُعلَنٌ لم يَعُدْ قائماً: $stale');
  });

  test('(٢) وكلُّ بثٍّ مُثبَّتٍ يَحفظُ مهلةَ الحدثِ الأوّل', () {
    // بلا المهلةِ يَصيرُ التثبيتُ تحسينَ كلفةٍ فحسب، ويَعودُ التعليقُ الأعلى
    // كذباً — وأسوأُ: بثٌّ مُثبَّتٌ بلا مهلةٍ يَنتظرُ إلى الأبدِ ولا يُعيدُه
    // أثرٌ جانبيٌّ بعدَ الآن.
    expect(chainsMissingTimeout, isEmpty,
        reason: 'بثٌّ مُثبَّتٌ بلا `firstEventTimeout`: $chainsMissingTimeout');
  });

  test('(٣) ولا زرَّ إعادةٍ صارَ عدمَ عملٍ بعدَ التثبيت', () {
    // `setState(() {})` كان يُعيدُ فتحَ المستمِعِ **بالأثرِ الجانبيِّ** — وفي
    // ملفٍّ ثبَّتَ بثَّه لم يَعُدْ يَفعلُ شيئاً. والمسحُ على المُجرَّدِ من
    // التعليقات، فشرحُ القرارِ في كلِّ ملفٍّ يَذكرُ الصيغةَ بالنصّ.
    // **إعفاءٌ حاملٌ لا مُعلَّقٌ**: الملفُّ يَجبُ أن يَكونَ قد ثبَّتَ بثّاً
    // **و**أبقى آخرَ إنلاين — وإلّا فالمُدخَلُ لا يَحرُسُ شيئاً. أوّلُ
    // صياغةٍ أدرجَت ثلاثةً، واثنانِ منها لا يُثبِّتانِ شيئاً أصلاً فلا
    // يَبلغُهما الفحصُ: قضمةٌ حذفَت أحدَهما فمرَّت خضراء.
    const keepsInlineToo = {
      'lib/screens/admin/admin_broadcast_screen.dart',
    };
    final offenders = <String>[];
    for (final f in files) {
      final rel = f.path.replaceAll(r'\', '/');
      if (!hoisted.contains(rel) || keepsInlineToo.contains(rel)) continue;
      final code = stripComments(f.readAsStringSync());
      // **زرٌّ** بعينِه، لا أيُّ `setState(() {})`: إعادةُ بناءٍ واحدةٌ بعدَ
      // تحميلِ إعداداتٍ (`order_success_screen`) أو نبضةُ مؤقِّتٍ ليست زرَّ
      // إعادةٍ ولا تَعتمدُ على إعادةِ فتحِ البثّ — ومسحُها كان إبلاغاً
      // خاطئاً أمسكَه هذا الفحصُ على نفسِه.
      for (final m in RegExp(r'onPressed:\s*').allMatches(code)) {
        if (_arg(code, m.end).contains('setState(() {})')) {
          offenders.add(rel);
          break;
        }
      }
    }
    expect(hoisted.length, greaterThanOrEqualTo(15),
        reason: 'قائمةُ الملفّاتِ المُثبَّتةِ انحلّت');
    expect(offenders, isEmpty,
        reason: 'زرُّ إعادةٍ بلا أثرٍ في ملفٍّ مُثبَّت: $offenders');
    for (final k in keepsInlineToo) {
      expect(inline.any((e) => e.startsWith('$k#')), isTrue,
          reason: 'إعفاءٌ لملفٍّ لم يَعُدْ يُبقي بثّاً إنلاين: $k');
      expect(hoisted, contains(k),
          reason: 'إعفاءٌ لملفٍّ لا يُثبِّتُ شيئاً — فالفحصُ لا يَبلغُه '
              'أصلاً والمُدخَلُ مُعلَّق: $k');
    }
    // **ونفيُ إيجابيّةٍ كاذبة**: `order_success_screen` يُثبِّتُ بثَّه
    // **ويَحملُ** `setState(() {})` — لكنّه إعادةُ بناءٍ واحدةٌ بعدَ تحميلِ
    // إعداداتِ المنشأةِ (`ensureConfigLoaded`)، لا زرَّ إعادة. فلو ضاقَ
    // الفحصُ على «أيِّ `setState(() {})`» لَأبلغَ عنه زوراً، وقد أبلغ.
    const fp = 'lib/screens/order_success_screen.dart';
    expect(hoisted, contains(fp));
    expect(
        stripComments(File(fp).readAsStringSync()), contains('setState(() {})'),
        reason: 'زالَ الشاهدُ — فنفيُ الإيجابيّةِ الكاذبةِ لا يَحرُسُ شيئاً');
    expect(offenders, isNot(contains(fp)));
  });

  test('(٤) وشاهدا التعليل: السابقةُ قائمةٌ والمهلةُ للحدثِ الأوّلِ وحدَه', () {
    // لولا أنّ المهلةَ **للحدثِ الأوّل** لَما كانت إعادةُ الاشتراكِ تُعيدُها،
    // ولولا سابقةُ `driver_tasks_screen` لَكانَ هذا قراراً جديداً لا إكمالاً.
    final tasks =
        File('lib/screens/driver_tasks_screen.dart').readAsStringSync();
    expect(tasks, contains('البثّان يُبنيان **مرّةً واحدة**'),
        reason: 'زالت السابقةُ المكتوبةُ — فالقاعدةُ تُراجَعُ لا تُسكَت');
    expect(tasks, contains('_openStreams'),
        reason: 'زالَ تثبيتُ بثوثِ شاشةِ المهامّ');
    final net = File('lib/utils/net_timeout.dart').readAsStringSync();
    expect(net, contains('firstEventTimeout'));
    expect(net, contains('مهلةٌ لأوّل حدثٍ وحده، لا لكلِّ فجوةٍ بين الأحداث'),
        reason: 'لم تَعُدْ المهلةُ مقصورةً على الحدثِ الأوّل — فتعليلُ '
            'استئنافِها بإعادةِ الاشتراكِ يُراجَع');
    expect(net, contains('بعد أوّلِ حدثٍ تُلغى المؤقّتة ولا تعود'),
        reason: 'زالَ ما يَجعلُ إعادةَ الاشتراكِ تُعيدُ المهلةَ');
  });
}
