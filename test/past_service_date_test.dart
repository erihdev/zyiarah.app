// **لا موعدَ في الماضي** — حارسُ القاعدةِ في `lib/utils/order_lifecycle.dart`
// (`serviceDateAllowed` + `kPastServiceDateRefusal`) ومرآتِها
// `admin_panel/src/utils/orderDispatch.ts`، والحارسُ الحقيقيُّ خادميٌّ:
// `_assertServiceDateNotPast` في النداءَين، مشدودٌ في
// `functions/test/ksa_time.test.js` (هـ١–هـ٤).
//
// ═══ العطل ═══
//
// أربعةُ مواضعَ تَكتبُ موعدَ الخدمةِ — نداءا `approveAndAssignOrder` و
// `rescheduleAssignedOrder`، وفرعا الكتابةِ المباشرةِ في شاشةِ تفاصيلِ الطلبِ
// وفي صفحةِ طلباتِ اللوحة — وكانت الأربعةُ تَقبلُ **أيَّ** تاريخ: الفحصُ
// الخادميُّ `isNaN(parsed.getTime())` وحدَه («موعد غير صالح»)، و
// `firestore.rules` **صفرُ ذكرٍ** لـ`service_date`.
//
// والمُدخَلاتُ الثلاثةُ تُجيزُه كذلك: حقلا `datetime-local` في اللوحةِ بلا
// `min`، ومُنتقي الدارتِ بـ`firstDate: DateTime.now().subtract(const
// Duration(days: 1))` — أي **أمس** صريحاً.
//
// **والقاعدةُ مُنفَّذةٌ في السطحَين على كلِّ موعدٍ آخر**، وهذا ما يَجعلُه
// إكمالاً لا اختراعاً: الدارتُ يَحدُّ مُنتقياتِ البثِّ والكوبونِ وجدولِ
// المنطقةِ بـ`DateTime.now()`، واللوحةُ تَحدُّ موعدَ البثِّ بـ
// `min={minScheduleValue()}` في `Notifications.tsx` — فالمتخلّفُ موعدُ
// الخدمةِ وحدَه، وهو «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد» مرّةً أخرى.
//
// ═══ وما يَخرُجُ عليه موعدٌ ماضٍ، مقيساً من الشفرةِ لا مظنوناً ═══
//
//   * `sweepUnassignedPaidOrders` تَستعلمُ `service_date >= now − ١٣س` —
//     فطلبٌ مدفوعٌ بتاريخٍ أقدمَ **لا يُسنَدُ آليّاً أبداً**.
//   * ونافذةُ `autoResolveUnfulfilledPaidOrder` هي `now − ٢٤س .. now − ١س`
//     — فلا يُستردُّ أيضاً: **مالٌ مقبوضٌ، ولا خدمةَ، ولا استردادَ، ولا
//     تنبيهَ**، وهي الجملةُ التي وُجد ذلك المحرّكُ لإلغائها.
//   * و`remindClientsUpcomingAppointments` من الآنِ إلى `+٢٤س` — فلا تُذكَّرُ
//     العميلة.
//
// ═══ ونتيجتانِ سالبتانِ تُسجَّلانِ كما هما ═══
//
// السائقُ **يَراه**: بثُّ لوحتِه `whereIn` على الحالةِ بلا نافذةِ تاريخ،
// مجموعاً بـ`booking_date` — فقد تُنفَّذُ الخدمةُ فعلاً، والمكسورُ هو
// الاستعادةُ الآليّةُ لا الرؤية. و`capacity.countBookings` تَعُدُّه في
// **يومِه الماضي** (تَقرأُ حقلَي الحجز، وكلا النداءَين يَكتبُهما صحيحَين):
// عَدٌّ بلا معنًى لا عَدٌّ خاطئ، فيومٌ مضى لا يُحجَزُ أصلاً.
//
// والعميلُ لا يَبلغُ هذا المسلك: أشرطةُ الحجزِ الثلاثةُ ومُنتقي الخانةِ
// كلُّها تَبدأُ من **الغد** (`Duration(days: i + 1)`). فالتعرّضُ إداريٌّ،
// وخطأُ مُشغِّلٍ لا تلاعب: سنةٌ أو شهرٌ مُخطَأٌ في `datetime-local`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/ksa_instant.dart';
import 'package:zyiarah/utils/order_lifecycle.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// يَقتطِعُ كتلةً بين علامتَين في ملفِّ فحصِ الـTS — والاتّجاهُ هكذا بقرارٍ
/// **مُتحقَّقٍ منه**: `node:fs` بلا أنواعٍ تحتَ `tsconfig.app.json`، فقراءةُ
/// الدارتِ من الـTS تُسقطُ `npm run build` بـ`TS2591` بينما `tsc --noEmit`
/// و`vitest` و`eslint` كلُّها تَمُرّ. و`File()` في دارت تَقرأُ أيَّ مسار.
String _between(String src, String begin, String end) {
  final i = src.indexOf(begin);
  final j = src.indexOf(end, i < 0 ? 0 : i);
  if (i < 0 || j < 0) {
    throw StateError('علامةُ الجدولِ المشترَكِ «$begin» غائبةٌ — '
        'الحارسُ بلا موضوعٍ لا أخضر.');
  }
  return src.substring(i + begin.length, j);
}

/// يَقتطِعُ المصفوفةَ الحرفيّةَ **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**،
/// لا بـ`indexOf('[')`: الأوّلُ يَلتقطُ قوسَ **تعليقِ النوع** في الـTS
/// (`[string, string, boolean][] = [`) فيَسقطُ التحليلُ — فخٌّ مسجَّلٌ في هذا
/// المستودعِ ثلاثَ مرّات. ثمّ تُسوّى الاقتباساتُ والفواصلُ المتدلّية.
String _arrayLiteral(String src) {
  final end = src.lastIndexOf(']');
  if (end < 0) throw StateError('لا مصفوفةَ في الكتلةِ المشترَكة');
  var depth = 0;
  for (var i = end; i >= 0; i--) {
    if (src[i] == ']') depth++;
    if (src[i] == '[') {
      depth--;
      if (depth == 0) {
        return src
            .substring(i, end + 1)
            .replaceAll("'", '"')
            .replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m.group(1)!);
      }
    }
  }
  throw StateError('مصفوفةٌ غيرُ متوازنةٍ في الكتلةِ المشترَكة');
}

/// جسمُ دالّةٍ دارتيّةٍ بموازنةِ الأقواس — **قائمةُ المعامَلاتِ أوّلاً**، فأخذُ
/// أوّلِ `{` بعدَ الاسمِ يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ لا الجسم (فخُّ
/// الحدِّ، مسجَّلٌ في هذا المستودعِ ثمانيَ مرّات).
String _fnBody(String src, String decl) {
  var i = src.indexOf(decl);
  if (i < 0) throw StateError('«$decl» غيرُ موجود');
  i += decl.length;
  // موازنةُ قائمةِ المعامَلات
  var depth = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) {
        i++;
        break;
      }
    }
    i++;
  }
  final open = src.indexOf('{', i);
  final arrow = src.indexOf('=>', i);
  if (arrow >= 0 && (open < 0 || arrow < open)) {
    final semi = src.indexOf(';', arrow);
    return src.substring(arrow, semi < 0 ? src.length : semi);
  }
  if (open < 0) throw StateError('«$decl» بلا جسم');
  depth = 0;
  for (var k = open; k < src.length; k++) {
    if (src[k] == '{') depth++;
    if (src[k] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, k + 1);
    }
  }
  throw StateError('«$decl» جسمٌ غيرُ متوازن');
}

void main() {
  final tsTest = File('admin_panel/src/utils/orderDispatch.test.ts')
      .readAsStringSync();
  final tsRule =
      File('admin_panel/src/utils/orderDispatch.ts').readAsStringSync();
  final panel = File('admin_panel/src/pages/Orders.tsx').readAsStringSync();
  final screen =
      File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();
  final idx = File('functions/index.js').readAsStringSync();
  final rule = File('lib/utils/order_lifecycle.dart').readAsStringSync();

  // «الآن» المثبّتُ في الجدولِ المشترَك — فلا يَتعلّقُ الفحصُ بساعةِ التشغيل.
  final nowSrc = _between(tsTest, '// NOW_BEGIN', '// NOW_END');
  final nm = RegExp(r'Date\.UTC\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)')
      .firstMatch(nowSrc);
  if (nm == null) throw StateError('`NOW_MS` غيرُ مقروء: $nowSrc');
  // شهرُ جافاسكربت صفريٌّ وشهرُ دارتَ واحديّ.
  final now = DateTime.utc(int.parse(nm.group(1)!), int.parse(nm.group(2)!) + 1,
      int.parse(nm.group(3)!), int.parse(nm.group(4)!), int.parse(nm.group(5)!));

  // الجدولُ المشترَك: `[وسم, ساعةُ حائطٍ, مسموح]`.
  final raw = _between(tsTest, '// DATE_CASES_BEGIN', '// DATE_CASES_END');
  final cases = (jsonDecode(_arrayLiteral(raw)) as List).cast<List>();

  group('قاعدةُ «لا موعدَ في الماضي»', () {
    test('(أ) سلوكاً على جدولِ الحالاتِ المشترَكِ بين اللغتَين', () {
      expect(cases.length, greaterThanOrEqualTo(11),
          reason: 'الجدولُ المشترَكُ انحلّ');
      var checked = 0;
      var skipped = 0;
      for (final row in cases) {
        final tag = row[0] as String;
        final wall = row[1] as String;
        final allowed = row[2] as bool;
        final chosen = DateTime.tryParse(wall);
        if (chosen == null || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}')
            .hasMatch(wall)) {
          // **مُستثنىً بسببٍ مُعلَن**: ساعةُ حائطٍ غيرُ قابلةٍ للفكِّ لا
          // يُنتجُها مُنتقي الدارتِ أصلاً (يُعيدُ `DateTime` أو `null`)؛
          // النصُّ الحرُّ مَدخَلُ اللوحةِ وحدَها، فتَفحصُه مرآتُها.
          skipped++;
          continue;
        }
        checked++;
        expect(serviceDateAllowed(chosen, now: now), allowed, reason: tag);
      }
      expect(checked, greaterThanOrEqualTo(8),
          reason: 'أغلبُ الجدولِ تُخطّي — القارئُ انحلّ');
      expect(skipped, 3,
          reason: 'عددُ صفوفِ النصِّ الحرِّ تغيّر — يُراجَعُ الاستثناءُ لا يُسكَت');
    });

    test('(ب) والحدُّ **بدايةُ يومِ الرياضِ** لا «ليس قبلَ الآن»', () {
      // `now` = 00:30Z = 03:30 بالرياض. فساعةٌ مضت من اليومِ نفسِه مسموحةٌ
      // **بقصد**: موعدٌ مشروعٌ لزيارةٍ تأخّرَ إدخالُها، وداخلَ نافذةِ الـ١٣
      // ساعةً فقابلٌ للاستعادة. وآخرُ لحظةٍ من أمسَ مرفوضة.
      expect(serviceDateAllowed(DateTime(2026, 10, 8, 1), now: now), isTrue);
      expect(serviceDateAllowed(DateTime(2026, 10, 7, 23, 59), now: now), isFalse);
      // ومنتصفُ ليلِ اليومِ نفسِه هو الحدُّ بعينِه — لا قبلَه ولا بعدَه.
      expect(serviceDateAllowed(DateTime(2026, 10, 8), now: now), isTrue);
    });

    test('(ج) ويومُ الرياضِ لا يومُ الجهاز', () {
      // 21:30Z من السابعِ = 00:30 بالرياضِ من **الثامن**. فلو قُرئت مكوّناتُ
      // UTC لكانَ «اليوم» السابعَ فمرَّ موعدٌ ماضٍ بالرياض.
      final crossing = DateTime.utc(2026, 10, 7, 21, 30);
      expect(serviceDateAllowed(DateTime(2026, 10, 8), now: crossing), isTrue);
      expect(serviceDateAllowed(DateTime(2026, 10, 7, 23), now: crossing), isFalse);
      // و`ksaTodayWall` هي ما يُنتجُ ذلك — ومكوّناتُها رياضيّةٌ لا محلّيّة.
      final t = ksaTodayWall(crossing);
      expect([t.year, t.month, t.day, t.hour, t.minute], [2026, 10, 8, 0, 0]);
      // والمرآةُ تَقيسُ بيومِ الرياضِ كذلك لا بيومِ المتصفّح — وهي تُقارِنُ
      // **نصّاً** (`YYYY-MM-DD` مُعجميّاً = زمنيّاً) فلا تَدخلُ المنطقةُ أصلاً.
      expect(tsRule.contains('ksaTodayDate(nowMs)'), isTrue,
          reason: 'مرآةُ اللوحةِ لم تَعُدْ تَقيسُ بيومِ الرياض');
      expect(RegExp(r'new Date\(\)\s*\.get(FullYear|Month|Date)')
          .hasMatch(tsRule),
          isFalse,
          reason: 'المرآةُ تَقرأُ يومَ المتصفّحِ — عطلُ المنطقةِ من جديد');
    });

    test('(د) والرياضيّةُ غيرُ قابلةٍ للنسيانِ في موضعِ النداء', () {
      // لا موضعَ نداءٍ يُمرّرُ `now`: القاعدةُ تَحسبُ يومَ الرياضِ بنفسِها،
      // فلا يَستطيعُ مُنادٍ أن يُمرّرَ يومَ الجهازِ فيُعيدَ عطلَ المنطقة.
      final body = _fnBody(rule, 'bool serviceDateAllowed');
      expect(body.contains('ksaTodayWall(now)'), isTrue,
          reason: 'القاعدةُ لم تَعُدْ تَقيسُ بيومِ الرياض');
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final c = stripComments(f.readAsStringSync());
        // `(?<!bool )` يُخرِجُ **الإعلانَ** نفسَه: وسيطُه المُسمّى يَحملُ
        // فاصلةً بالضرورة، فبلاه يَسقطُ الفحصُ على موضعِ القاعدةِ — وإعفاءُ
        // الملفِّ كلِّه كان سيُعمي الفحصَ عن نداءٍ داخلَه.
        expect(RegExp(r'(?<!bool )serviceDateAllowed\([^)]*,').hasMatch(c),
            isFalse,
            reason: '${f.path}: يُمرّرُ «الآن» — الوسيطُ للفحصِ وحدَه');
      }
    });
  });

  group('كلُّ سطحٍ يَقبلُ موعداً يَمُرُّ بالقاعدة', () {
    test('(هـ) النطاقُ مُشتَقٌّ: كلُّ مُرسِلٍ لـ`scheduledIso` أو كاتبٍ '
        'لـ`service_date` يُنادي القاعدةَ', () {
      final gates = <String>{};
      final senders = <String>{};
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final c = stripComments(f.readAsStringSync());
        if (c.contains("'scheduledIso'") ||
            RegExp(r"\['service_date'\]\s*=(?!=)").hasMatch(c)) {
          senders.add(f.uri.pathSegments.last);
        }
        if (RegExp(r'serviceDateAllowed\s*\(').hasMatch(c)) {
          gates.add(f.uri.pathSegments.last);
        }
      }
      expect(senders, isNotEmpty, reason: 'المسحُ انحلَّ — لا مُرسِلَ');
      expect(senders.difference(gates), isEmpty,
          reason: 'سطحٌ يُرسِلُ موعداً بلا بوّابة: '
              '${senders.difference(gates)}');
      // واللوحةُ السطحُ الثاني — المُرسِلُ والكاتبُ المباشرُ في ملفٍّ واحد.
      final p = stripComments(panel);
      expect(p.contains('scheduledIso'), isTrue, reason: 'المسحُ انحلّ');
      expect(RegExp(r'serviceDateAllowed\s*\(').allMatches(p).length, 2,
          reason: 'موضعا الفحصِ في اللوحةِ (الإسنادُ والتعديل)');
    });

    test('(و) والفحصُ **قبلَ** الكتابةِ وقبلَ النداءِ في الفرعَين', () {
      // فحصٌ بعدَ الكتابةِ لا يَمنعُ شيئاً — والترتيبُ هو الإصلاح.
      final s = stripComments(screen);
      final iGate = s.indexOf('serviceDateAllowed(');
      final iCall = s.indexOf("httpsCallable('rescheduleAssignedOrder')");
      final iWrite = s.indexOf("updatePayload['service_date']");
      expect(iGate, greaterThan(0), reason: 'الشاشةُ بلا بوّابة');
      expect(iCall, greaterThan(iGate), reason: 'النداءُ قبلَ البوّابة');
      expect(iWrite, greaterThan(iGate), reason: 'الكتابةُ قبلَ البوّابة');

      final p = stripComments(panel);
      final gates = RegExp(r'serviceDateAllowed\s*\(')
          .allMatches(p)
          .map((m) => m.start)
          .toList();
      final pCall =
          p.indexOf("httpsCallable(functions, 'approveAndAssignOrder')");
      final pWrite = p.indexOf('service_date: ts');
      expect(gates.first, lessThan(pCall), reason: 'الإسنادُ قبلَ بوّابتِه');
      expect(gates.last, lessThan(pWrite), reason: 'الكتابةُ قبلَ بوّابتِها');
    });

    test('(ز) والمُدخَلاتُ الثلاثةُ محدودةٌ — والحدُّ بيومِ الرياض', () {
      // مُنتقي الدارت: الشكلُ القديمُ (`subtract(days: 1)`) زالَ من الشفرةِ،
      // ومضادَّةٌ تُثبِتُ أنّ شرحَه ما زال في الخامِّ فلا يُفرَّغُ الفحص.
      final s = stripComments(screen);
      expect(s.contains('firstDate: ksaTodayWall()'), isTrue,
          reason: 'مُنتقي الموعدِ غيرُ محدودٍ بيومِ الرياض');
      expect(RegExp(r'firstDate:\s*DateTime\.now\(\)\s*\.?\s*$|'
              r'firstDate:\s*DateTime\.now\(\)\.subtract')
          .hasMatch(s),
          isFalse,
          reason: 'الحدُّ القديمُ عاد');
      expect(screen.contains('subtract(const Duration(days: 1))'), isTrue,
          reason: 'شرحُ الحدِّ القديمِ زالَ من التعليق — المضادَّةُ بلا موضوع');

      // حقلا اللوحة: `min` على كلٍّ، بيومِ الرياضِ لا بيومِ المتصفّح.
      final mins = RegExp(r'min=\{`\$\{ksaTodayDate\(\)\}T00:00`\}')
          .allMatches(panel)
          .length;
      expect(mins, 2, reason: 'حقلا `datetime-local` بلا `min` رياضيّ');
      expect(RegExp(r'type="datetime-local"').allMatches(panel).length, 2,
          reason: 'حقلُ موعدٍ ثالثٌ — يُراجَعُ حدُّه');
    });
  });

  group('شواهدُ التعليل', () {
    test('(ح) النوافذُ الثلاثُ التي يَخرُجُ عليها موعدٌ ماضٍ قائمة', () {
      // زوالُ أيٍّ منها يُراجِعُ القاعدةَ لا يُسكِتُها.
      final i = stripComments(idx);
      expect(i.contains('13 * 60 * 60 * 1000'), isTrue,
          reason: 'نافذةُ مكنسةِ الطلبِ المدفوعِ بلا سائق (−١٣س) زالت');
      expect(i.contains('24 * 60 * 60 * 1000'), isTrue,
          reason: 'نافذةُ الاستردادِ الآليِّ (−٢٤س) زالت');
      expect(RegExp(r'"service_date",\s*">="').hasMatch(i), isTrue,
          reason: 'لا نافذةَ سفليّةً على الموعدِ — يُراجَعُ التعليل');
    });

    test('(ط) والعميلُ لا يَبلغُ المسلكَ: أشرطةُ الحجزِ تَبدأُ من الغد', () {
      var strips = 0;
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final c = stripComments(f.readAsStringSync());
        strips += RegExp(r'Duration\(days:\s*i \+ 1\)').allMatches(c).length;
      }
      expect(strips, greaterThanOrEqualTo(5),
          reason: 'شريطُ حجزٍ صارَ يَبدأُ من اليومِ — التعرّضُ لم يَبقَ إداريّاً');
    });

    test('(ي) والقاعدةُ مُنفَّذةٌ في السطحَين على كلِّ موعدٍ آخر — السابقةُ', () {
      // لو زالت فالقاعدةُ ليست إكمالاً بل قراراً جديداً، ويُراجَعُ تعليلُها.
      var bounded = 0;
      for (final f in sourcesIn('lib/screens/admin', atLeast: 10)) {
        final c = stripComments(f.readAsStringSync());
        // لا `\b` بعدَ `)`: الحدُّ بين `)` و`,` ليس حدَّ كلمةٍ (كلاهما غيرُ
        // حرفيّ)، فالصياغةُ الأولى لم تُطابِقْ `DateTime.now(),` إطلاقاً
        // وأعطت ٢ من ٥ — أمسكَتها الأرضيّةُ لا المقارنة.
        bounded += RegExp(r'firstDate:\s*(?:DateTime\.now\(\)|now\b)')
            .allMatches(c)
            .length;
      }
      expect(bounded, greaterThanOrEqualTo(4),
          reason: 'مُنتقياتُ الدارتِ الأخرى لم تَعُدْ محدودةً بـ«الآن»');
      final notif =
          File('admin_panel/src/pages/Notifications.tsx').readAsStringSync();
      expect(notif.contains('min={minScheduleValue()}'), isTrue,
          reason: 'سابقةُ `min` في اللوحةِ زالت');
    });

    test('(ك) والحارسُ الحقيقيُّ خادميٌّ: النداءانِ يَرفضان', () {
      final i = stripComments(idx);
      expect(RegExp(r'_assertServiceDateNotPast\s*\(').allMatches(i).length, 3,
          reason: 'تعريفٌ + موضعا نداء');
      expect(i.contains('riyadhDayStartMs(Date.now())'), isTrue,
          reason: 'الحدُّ الخادميُّ ليس بدايةَ يومِ الرياض');
    });
  });
}
