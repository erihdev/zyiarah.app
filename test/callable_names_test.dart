// حارس: **كلُّ دالّةٍ سحابيّةٍ يناديها العميل موجودةٌ في `functions/index.js`.**
//
// نداءُ اسمٍ غيرِ مُصدَّر لا يفشل عند البناء ولا في التحليل ولا في أيّ اختبار:
// يفشل **عند المستخدم** بـ`not-found`. وإعادةُ تسمية دالّةٍ خادميّة — وهي
// عمليّةٌ متوقَّعة مع تقطيع `index.js` إلى وحدات — تفعل ذلك بالضبط في كلّ
// موضعِ نداءٍ نُسي.
//
// والاتجاهُ المعاكس يُرصَد لا يُمنَع: `onCall` بلا نداءٍ من عميل قد يكون
// ميّتاً (أربعٌ منها تنتظر حذفاً يدويّاً — انظر `functions_delete_once.yml`)
// وقد يكون مقصوداً. فنطبع العددَ ونثبّت المجموعةَ المعروفة بدل أن نُفشل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كلُّ النصوص المقتبسة داخل نداءٍ، بموازنةِ الأقواس — تغطّي الشكلَ المباشر
/// (`httpsCallable('x')`) والشرطيّ (`cond ? 'a' : 'b'`) معاً.
Set<String> _literalsInCalls(String src, String opener) {
  final out = <String>{};
  var i = 0;
  while (true) {
    i = src.indexOf(opener, i);
    if (i < 0) break;
    var j = i + opener.length, depth = 1;
    while (j < src.length && depth > 0) {
      if (src[j] == '(') depth++;
      if (src[j] == ')') depth--;
      j++;
    }
    for (final m in RegExp(r"""['"]([A-Za-z_][A-Za-z0-9_]{2,})['"]""")
        .allMatches(src.substring(i, j))) {
      out.add(m.group(1)!);
    }
    i = j;
  }
  return out;
}

List<File> _sources() => [
      ...Directory('lib').listSync(recursive: true).whereType<File>().where(
          (f) => f.path.endsWith('.dart')),
      ...Directory('admin_panel/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.ts') || f.path.endsWith('.tsx')),
    ];

void main() {
  final fn = File('functions/index.js').readAsStringSync();
  final exported = RegExp(r'^exports\.(\w+)\s*=', multiLine: true)
      .allMatches(fn)
      .map((m) => m.group(1)!)
      .toSet();

  test('الحارسُ يقرأ شيئاً فعلاً', () {
    expect(exported.length, greaterThan(50),
        reason: 'لم تُقرأ مُصدَّراتُ index.js');
    expect(_sources().length, greaterThan(100));
  });

  group('كلُّ اسمٍ يناديه العميل مُصدَّر', () {
    final called = <String, String>{};
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      for (final n in _literalsInCalls(src, 'httpsCallable(')) {
        called.putIfAbsent(n, () => f.path);
      }
      // الشكلُ غيرُ المباشر: اسمُ الدالّة يُمرَّر وسيطاً مُسمّى ثمّ يُستعمل.
      for (final m
          in RegExp(r"""functionName:\s*['"](\w+)['"]""").allMatches(src)) {
        called.putIfAbsent(m.group(1)!, () => f.path);
      }
    }

    test('وُجدت نداءات (وإلّا فالحارسُ أجوف)', () {
      expect(called.length, greaterThanOrEqualTo(12));
    });

    test('ولا اسمَ بلا مُصدَّر', () {
      // نتجاهل ما ليس اسمَ دالّة (وسائطُ نصّيّة داخل النداء نفسِه).
      // نُرشِّح ما ليس اسمَ دالّة: داخل النداء وسائطُ نصّيّة أخرى — ومنها
      // مقارنةُ طريقة الدفع `'tamara'` في الشكل الشرطيّ، وهي أوّلُ ما أوقع
      // هذا الفحصَ في إنذارٍ كاذب. كلُّ دالّةٍ سحابيّةٍ هنا camelCase فيها
      // حرفٌ كبيرٌ واحدٌ على الأقلّ؛ كلمةٌ صغيرةٌ مفردة ليست اسمَ دالّةٍ أبداً.
      final missing = called.entries
          .where((e) => !exported.contains(e.key))
          .where((e) => e.key.contains(RegExp(r'[A-Z]')))
          .map((e) => '${e.key}  ←  ${e.value}')
          .toList();
      expect(missing, isEmpty,
          reason: '\n\nاسمٌ يناديه العميل وليس مُصدَّراً — يفشل عند المستخدم '
              'بـnot-found، ولا شيءَ يكشفه قبل ذلك:\n  • ${missing.join('\n  • ')}\n');
    });
  });

  test('onCall بلا نداءٍ من عميل: المجموعةُ المعروفة وحدها', () {
    final onCalls = RegExp(r'exports\.(\w+)\s*=\s*onCall')
        .allMatches(fn)
        .map((m) => m.group(1)!)
        .toSet();
    final called = <String>{};
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      called.addAll(_literalsInCalls(src, 'httpsCallable('));
      for (final m
          in RegExp(r"""functionName:\s*['"](\w+)['"]""").allMatches(src)) {
        called.add(m.group(1)!);
      }
    }
    // الأربعُ الميّتة تنتظر حذفاً يدويّاً من الإنتاج (حذفُ دالّةٍ قرارٌ بشريّ،
    // والنشرُ بلا `--force` يفشل بدلاً من حذفها صامتاً) — `functions_delete_once.yml`.
    expect(onCalls.difference(called), {
      'checkHourlySlotAvailability',
      'findNearestDrivers',
      'generateSubscriptionVisits',
      'manualSendNotification',
    },
        reason: 'تغيّرت مجموعةُ الـonCall بلا عميل: إمّا مات نداءٌ (فالدالّةُ '
            'صارت ميتةً أيضاً) أو أُحييت واحدةٌ من الأربع');
  });
  // مُشغّلُ Firestore لا يُنادى، فلا يَراه الفحصُ أعلاه — ويَموتُ بطريقةٍ
  // أخرى: أن تَخلوَ مجموعتُه من كاتب. و`maintenance_requests` كذلك: خدمةُ
  // الصيانةِ أُزيلت من الجذور، فلا شيءَ في `lib/` ولا في اللوحةِ يُنشئ
  // مستنداً فيها (القراءةُ وحدَها باقيةٌ للطلباتِ القديمة — بحثُ الإدارةِ
  // وشاشةُ التفاصيل)، فمُشغّلاها لا يُطلَقانِ أبداً.
  //
  // **وهما خارجَ `functions_delete_once.yml`** الذي يَحذفُ أربعاً — فلو
  // شُغّل اليومَ بَقيت هاتان منشورتَين، وهو مسارٌ «لمرّةٍ واحدة» يُحذفُ
  // بعدَه. الفجوةُ مُثبَّتةٌ هنا كي لا تُنسى.
  test('مُشغّلاتُ الصيانةِ ميّتتان: لا كاتبَ لمجموعتِها', () {
    const dead = {
      'sendNotificationToAdminsOnNewMaintenance',
      'notifyClientOnMaintenanceRejected',
    };
    for (final name in dead) {
      expect(fn.contains('exports.$name'), isTrue,
          reason: '$name حُذفت من المصدر — فأزِلها من هذه المجموعة');
    }

    // كلُّ ذكرٍ للمجموعةِ يَتبعُه كاتبٌ خلال ١٢٠ حرفاً = كتابة.
    final writers = <String>[];
    for (final f in _sources()) {
      final code = f.readAsStringSync().split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      }).join('\n');
      for (final m in RegExp('maintenance_requests').allMatches(code)) {
        final tail = code.substring(
            m.end, m.end + 120 > code.length ? code.length : m.end + 120);
        for (final w in const ['.set(', '.add(', '.update(', '.delete(']) {
          if (tail.contains(w)) writers.add('${f.path}$w');
        }
      }
    }
    expect(writers, isEmpty,
        reason: 'عاد كاتبٌ لـmaintenance_requests ⇒ المُشغّلانِ حيّان: '
            'أزِلهما من هذه المجموعةِ ولا تَحذفهما من الإنتاج');
  });
}
