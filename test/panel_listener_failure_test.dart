import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «فشلُ المستمعِ يُرسَمُ كـ«لا شيء»» — ومنه أرقامُ مالٍ وأسطولٌ ودعاوى.
///
/// القاعدةُ مكتوبةٌ في المستودعِ بخطِّ كاتبِها: `ScheduleBoard` يَقول «لا فشل
/// صامت: بلا هذا تظهر الشاشة فارغة فيُفهم «لا مواعيد» خطأً»، و`Orders`
/// يَقولُها عن مستمعِه الرئيس — **وبجوارِه في نفسِ `useEffect` مستمعانِ
/// جسمُ مُعالِجِهما `console.error` وحدَه.** فالقاعدةُ عامّةٌ ومُنفَّذةٌ في
/// بعضِ الصفحات، وهو النمطُ المتكرّرُ هنا.
///
/// والفحصُ يَشتقُّ النطاقَ: كلُّ `onSnapshot` في `admin_panel/src`، ويُقارِنُ
/// **مجموعةَ** الصامتِ منها بقائمةٍ مُعلَنةٍ لكلِّ عنصرٍ سببُه — فمستمعٌ
/// جديدٌ صامتٌ يُراجَعُ بدلَ أن يَمرّ.
String _read(String p) => File(p).readAsStringSync();

/// يَحجبُ أسطرَ التعليقِ (`//`) بالفراغ — تعليقاتُ هذا الإصلاحِ تَقتبسُ
/// النصوصَ التي تُفحَص.
String _code(String src) => src
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

/// الوسيطُ الأخيرُ من نداءٍ بموازنةِ الأقواس — لا بقطعٍ عند أوّلِ `)`، وهو
/// الفخُّ الذي أعقمَ حُرّاساً هنا أربعَ مرّات.
List<String> _args(String src, int openParen) {
  var i = openParen + 1;
  var depth = 1;
  final parts = <String>[];
  final cur = StringBuffer();
  while (i < src.length && depth > 0) {
    final ch = src[i];
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') depth--;
    if (depth == 0) break;
    if (ch == ',' && depth == 1) {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
    i++;
  }
  parts.add(cur.toString());
  // فاصلةٌ متدلّيةٌ تُنتجُ وسيطاً أخيرَ فارغاً — فيُقرأُ مُعالِجُ خطأٍ
  // «صامتٌ» حيث لا مُعالِجَ أصلاً. الحذفُ يَجعلُ الاستخراجَ صادقاً.
  while (parts.length > 1 && parts.last.trim().isEmpty) {
    parts.removeLast();
  }
  return parts;
}

/// كلُّ مستمعٍ: الملفُّ، ترتيبُه داخلَه، نصُّ مُعالِجِ الخطأ، ونصُّ مُعالِجِ
/// النجاح.
List<(String, int, String, String)> _listeners() {
  final out = <(String, int, String, String)>[];
  for (final f in Directory('admin_panel/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          (f.path.endsWith('.ts') || f.path.endsWith('.tsx')) &&
          !f.path.contains('.test.'))) {
    final src = f.readAsStringSync();
    var ordinal = 0;
    for (final m in RegExp(r'onSnapshot\s*\(').allMatches(src)) {
      final parts = _args(src, m.end - 1);
      final rel = f.path.replaceFirst('admin_panel/', '');
      ordinal++;
      out.add((rel, ordinal, parts.last, parts.length > 1 ? parts[1] : ''));
    }
  }
  out.sort((a, b) => '${a.$1}#${a.$2}'.compareTo('${b.$1}#${b.$2}'));
  return out;
}

/// مُعالِجٌ «ناطق»: يُغيّرُ حالةً تُرى، أو يُنبّه، أو يَرفعُ الأمرَ لمُعالِجٍ
/// مشترك. مجرّدُ `console.error` ليس ناطقاً — وهو جوهرُ هذا الفحص.
bool _speaks(String handler) =>
    RegExp(r'set[A-Z]\w*\(').hasMatch(handler) ||
    handler.contains('toast(') ||
    handler.contains('toast.') ||
    handler.contains('onErr(');

void main() {
  group('لا فشلَ صامتاً في مستمعاتِ اللوحة', () {
    test('(أ) المسحُ يَجدُ المستمعاتِ فعلاً (حارسٌ عقيمٌ أسوأُ من لا حارس)',
        () {
      final all = _listeners();
      expect(all.length, greaterThanOrEqualTo(25),
          reason: 'انهيارُ العدِّ يَعني مُحلِّلاً معطوباً لا شفرةً نظيفة');
      // وأنّ الاقتطاعَ أصابَ مُعالِجاً حقيقيّاً في موضعٍ معروف.
      final orders = all.where((l) => l.$1.contains('Orders.tsx')).toList();
      expect(orders.length, greaterThanOrEqualTo(3));
      expect(orders.any((l) => l.$3.contains('setLoadError')), isTrue);
      // والاستخراجُ يُصيبُ المُعالِجَ الصامتَ عن قصدٍ بنصِّه — فعُقمُ
      // الاستخراجِ لا يَتنكّرُ في صورةِ «صامتٌ مسموحٌ به».
      final deliberate = all.firstWhere(
          (l) => l.$1.contains('AdminNotificationsListener'),
          orElse: () => ('', 0, '', ''));
      expect(deliberate.$3, contains('صامت عند الخطأ'),
          reason: 'وسيطٌ فارغٌ يَعني فاصلةً متدلّيةً لم تُسقَط');
    });

    test('(ب) مجموعةُ الصامتِ كاملةً = القائمةُ المُعلَنةُ بأسبابِها', () {
      // كلُّ عنصرٍ هنا صامتٌ **عن قصد**، ومعه سببُه:
      const allowed = <String, String>{
        // العدُّ يَسقطُ إلى حسابٍ محلّيٍّ صحيحٍ من المستمعِ الرئيس
        // (`pendingCount ?? orders.filter(...).length`) — فالفشلُ لا يُنتجُ
        // رقماً خاطئاً ولا دعوى، بل الرقمَ نفسَه من مصدرٍ آخر.
        'src/pages/Orders.tsx#2': 'يَسقطُ إلى عدٍّ محلّيٍّ صحيح',
        // مستمعُ تنبيهاتِ المتصفّح: فشلُه يَعني «لا تنبيهَ فوريّ»، ولا رقمَ
        // ولا دعوى في أيِّ شاشة — وصفحةُ الإشعاراتِ نفسُها لها حالةُ خطأ.
        'src/components/AdminNotificationsListener.tsx#1':
            'إشعارٌ فوريٌّ فقط، لا شاشةَ ولا رقم',
        // مُراقَبةُ مستندِ الموظّفِ نفسِه لسحبِ الصلاحيةِ حيّاً: فشلُ قراءةٍ
        // عابرٌ لا يَجوزُ أن يُخرِجَ المالكَ من لوحتِه، والقرارُ الأوّلُ
        // أُخِذ من `getDoc` قبلَها — فالصمتُ هنا هو **الفرعُ المحافظ**، لا
        // دعوى ولا رقم. (ويَشدُّه `staff_status_panel_test` بسببِه نصّاً.)
        'src/App.tsx#1': 'سحبُ صلاحيةٍ حيّ — الصمتُ هو الفرعُ المحافظ',
      };
      final silent = <String>[];
      for (final (file, ordinal, handler, _) in _listeners()) {
        if (!_speaks(handler)) silent.add('$file#$ordinal');
      }
      expect(silent.toSet(), allowed.keys.toSet(),
          reason: 'مستمعٌ صامتٌ جديدٌ يُراجَعُ ويُعلَّلُ، لا يُضَمُّ بسماحٍ عامّ');
    });

    test('(ج) الأربعةُ المُصلَحةُ تَقولُ ما حدثَ في الشاشةِ لا في console', () {
      // لكلٍّ: العَلَمُ يُضبَطُ في المُعالِجِ **ويُقرأُ** في الرسم.
      final cases = <String, (String, List<String>)>{
        'src/pages/Drivers.tsx': ('setLoadError(true)', [
          "loadError ? '—' : isAvailableCount",
          'تعذّر تحميل قائمة السائقين',
          'إعادة المحاولة',
        ]),
        'src/pages/Orders.tsx': ('setDriversError(true)', [
          'driversError ?',
          'تعذّر تحميل قائمة السائقين',
        ]),
        'src/pages/Accountants.tsx': ('setDriversError(true)', [
          "driversError ? '—' : formatCurrency(totalPayroll)",
          "driversError ? '—' : formatCurrency(netProfit)",
        ]),
        'src/pages/Support.tsx': ('setMsgError(true)', [
          'msgError ?',
          'تعذّر تحميل رسائل التذكرة',
        ]),
      };
      cases.forEach((f, v) {
        final src = _read('admin_panel/$f');
        expect(src, contains(v.$1), reason: f);
        for (final needle in v.$2) {
          expect(src, contains(needle), reason: '$f → $needle');
        }
      });
    });

    test('(د) الدعوى القديمةُ لا تُقالُ قبلَ استبعادِ الفشل', () {
      // «لا يوجد سائقون متاحون حالياً» و«لا توجد رسائل بعد» دعويانِ صحيحتانِ
      // في مكانِهما — بشرطِ أن يَسبقَهما فرعُ الفشل. الترتيبُ هو الإصلاح.
      //
      // والتعليقاتُ تُحجَبُ أوّلاً: الشرحُ أعلى كلِّ صفحةٍ **يَقتبسُ الدعوى
      // نفسَها** ليُبيّنَ العطلَ، فاقتباسُه يَسبقُ الفرعَ ويَقلبُ الترتيبَ —
      // وهو فخُّ «الحارسُ يَسقطُ على توثيقِه» في ثوبِ فحصِ ترتيبٍ لا مسحِ
      // مصطلح. ثمّ يُقابَلُ الخامُّ كي لا يُجوّفَ الحجبُ الفحصَ.
      final cases = <String, (String, String)>{
        'src/pages/Orders.tsx': ('driversError ?', 'لا يوجد سائقون متاحون حالياً'),
        'src/pages/Support.tsx': ('msgError ?', 'لا توجد رسائل بعد'),
        'src/pages/Drivers.tsx': ('loadError ? (', 'لا يوجد سائقين مطابقين للبحث'),
      };
      cases.forEach((f, v) {
        final raw = _read('admin_panel/$f');
        final c = _code(raw);
        expect(c.indexOf(v.$1), greaterThan(-1), reason: f);
        expect(c.indexOf(v.$2), greaterThan(-1), reason: f);
        expect(c.indexOf(v.$1), lessThan(c.indexOf(v.$2)), reason: f);
        expect(raw, contains(v.$2), reason: '$f — الحجبُ لم يُفرِغ الفحص');
      });
    });

    test('(ه) الإطفاءُ في مُعالِجِ النجاحِ نفسِه، لا في زرِّ الإعادة', () {
      // بلا هذا تَبقى حالةُ الخطأِ بعد عودةِ الاتصالِ ويُقرأُ الأسطولُ
      // معطوباً وهو سليم. والفحصُ **مشدودٌ إلى مُعالِجِ النجاحِ بعينِه**:
      // صياغتُه الأولى طلبَت العَلَمَ في أيِّ موضعٍ من الملفِّ، فأرضاه
      // `onClick` زرِّ الإعادةِ — ومرَّ اختبارُ قضمٍ أزالَ الإطفاءَ من
      // مسارِ النجاحِ أخضرَ.
      const flags = <String, String>{
        'src/pages/Drivers.tsx': 'setLoadError(false)',
        'src/pages/Orders.tsx': 'setDriversError(false)',
        'src/pages/Accountants.tsx': 'setDriversError(false)',
        'src/pages/Support.tsx': 'setMsgError(false)',
      };
      flags.forEach((f, flag) {
        final mine = _listeners()
            .where((l) => l.$1 == f && l.$3.contains(flag.replaceAll('false', 'true')))
            .toList();
        expect(mine, isNotEmpty, reason: '$f — لم يُعثَر على المستمعِ المُصلَح');
        expect(mine.any((l) => l.$4.contains(flag)), isTrue,
            reason: '$f — $flag غائبٌ عن مُعالِجِ النجاح');
      });
    });

    test('(و) الرواتبُ ما زالت تُجمَعُ على النشطينَ وحدَهم', () {
      // الرقمُ الذي يُخفى عند الجهلِ هو هذا بعينِه؛ لو تغيّرَ مصدرُه
      // فالإخفاءُ يُراجَعُ لا يُسكَت.
      final a = _read('admin_panel/src/pages/Accountants.tsx');
      expect(a, contains('const activeDrivers = drivers.filter((d) => !driverIsDisabled(d));'.replaceAll('(d) =>', 'd =>')));
      expect(a, contains('const netProfit = netRevenue - totalPayroll;'));
    });
  });
}
