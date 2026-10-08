import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **ضغطةٌ تَنتهي بـ`return;` عارٍ ولا كلمةَ تُقال — في اللوحةِ هذه المرّة.**
///
/// القاعدةُ مقرَّرةٌ في `test/silent_return_test.dart` ونصُّها عامّ: «ليست
/// القاعدةُ «لا رجوعَ عارياً» — فمن اثنَي عشَرَ موضعاً في `lib/screens/**`
/// تسعةٌ صحيحةٌ (حوارٌ أُلغي، ودجةٌ زائلة، حقلٌ فارغ، مشاركةٌ جارية). القاعدةُ
/// أنّ هذه كانت **نهايةَ ضغطةٍ قصدَها المستخدم**». ونطاقُه `lib/screens/**`
/// وحدَه — واللوحةُ سطحٌ ثانٍ لم يَكن له حارس: «حارسٌ ضيّقٌ وقاعدةٌ عامّة»
/// للمرّةِ الثامنةَ عشَرَ في هذا المستودع.
///
/// والمسحُ أعطى أربعةَ عشَرَ رجوعاً عارياً في مُعالِجاتِ اللوحة، **عشرةٌ
/// صحيحةٌ** وأربعةٌ تُنهي ضغطةً حقيقيّةً بلا كلمة — وفي كلٍّ منها **الاصطلاحُ
/// قائمٌ في الملفِّ نفسِه، وفي ثلاثةٍ منها في الدالّةِ نفسِها**:
///
///   • **`Notifications.handleSend`** — `!title.trim() || !body.trim()`.
///     الملفُّ بلا `<form>` وبلا `required`، فهذا الفحصُ هو كلُّ ما يَمنع؛
///     وفحصُ موعدِ الجدولةِ **ثمانيةَ أسطرٍ أسفلَه في الدالّةِ نفسِها**
///     يُنبّه. والمكتوبُ بثٌّ يَصِلُ كلَّ عميلة.
///   • **`Orders.handleAssignDriver`** — `!selectedDriverId || !scheduledAt`.
///     الملفُّ بلا `<form>`/`required`، وفحصُ «لا موعدَ في الماضي»
///     **على السطرِ التالي** يُنبّه. والمضغوطُ تعيينُ سائقٍ لطلبٍ مدفوع.
///   • **`Support.handleSend`** — `!reply.trim()`. و`catch` في الدالّةِ نفسِها
///     يُنبّه بنصٍّ مكتوبٍ بعناية.
///   • **`Settings.handleCopyPricesFrom`** — `!snap.exists()` (المنطقةُ
///     المصدرُ زالت بين تحميلِ القائمةِ والنسخ). والدالّةُ تُنبّهُ في
///     **النجاحِ وفي `catch`** كليهما، فالفرعُ الأوسطُ وحدَه كان يُنتجُ
///     لا شيء: النموذجُ كما هو، والأدمنُ يَحسبُ النسخَ تمَّ فيَضغطُ «حفظ».
///
/// والنطاقُ هنا **مُشتَقٌّ** من `pages/` و`components/`: كلُّ
/// `const <اسم> = async (…) => {` و`async function <اسم>(`، ومعها المُعالِجُ
/// المتزامنُ **باسمِه** (`handle…`/`on[A-Z]…`) — والاسمُ شرطٌ هناك بقصد: سهمٌ
/// متزامنٌ بلا اسمِ مُعالِجٍ هو في الغالبِ مُساعِدُ رسمٍ أو رَماءُ `map`،
/// والرجوعُ المبكّرُ فيه تحكّمٌ عاديٌّ لا نهايةُ ضغطة.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();

  // ───────────────────────── الكاشف ─────────────────────────

  /// من موضعِ `o` إلى موضعِ `c` المقابلِ (أو -1).
  int closeOf(String s, int i, String o, String c) {
    var d = 0;
    for (var j = i; j < s.length; j++) {
      if (s[j] == o) {
        d++;
      } else if (s[j] == c) {
        d--;
        if (d == 0) return j;
      }
    }
    return -1;
  }

  /// من موضعِ `c` إلى موضعِ `o` المقابلِ (إلى الوراء).
  int openOf(String s, int i, String o, String c) {
    var d = 0;
    for (var j = i; j >= 0; j--) {
      if (s[j] == c) {
        d++;
      } else if (s[j] == o) {
        d--;
        if (d == 0) return j;
      }
    }
    return -1;
  }

  final handlerDecl = RegExp(
      r'(?:const\s+(\w+)\s*=\s*async\s*(?:function\s*)?\(' // سهمٌ غيرُ متزامن
      r'|async\s+function\s+(\w+)\s*\(' // دالّةٌ مُسمّاة
      r'|const\s+(handle\w+|on[A-Z]\w*)\s*=\s*\()'); // مُعالِجٌ متزامنٌ باسمِه

  /// أجسامُ المُعالِجاتِ في مصدرٍ **مُجرَّدٍ من التعليقات**.
  Map<String, String> handlers(String code) {
    final out = <String, String>{};
    for (final m in handlerDecl.allMatches(code)) {
      final name = m.group(1) ?? m.group(2) ?? m.group(3)!;
      final pc = closeOf(code, m.end - 1, '(', ')');
      if (pc < 0) continue;
      final br = code.indexOf('{', pc);
      if (br < 0) continue;
      // السهمُ المتزامنُ يُشترَطُ أن يَكونَ سهماً فعلاً، لا نداءً بوسيطٍ كائن.
      if (m.group(3) != null && !code.substring(pc, br + 1).contains('=>')) {
        continue;
      }
      final end = closeOf(code, br, '{', '}');
      if (end < 0) continue;
      out[name] = code.substring(br, end + 1);
    }
    return out;
  }

  final speaks = RegExp(r'\b(toast|confirm|setError|alert)\b');

  /// الرجوعاتُ العاريةُ **الصامتةُ** في جسمِ مُعالِج، مرتَّبةً، كلٌّ بشُذرتِه.
  ///
  /// والتصنيفُ **بشكلِ الجملةِ** لا بنافذةٍ قبلَ الرجوع: نافذةٌ تَقرأُ
  /// «توستٌ في أيِّ موضعٍ سابقٍ من الجسم» تَرضى بتوستٍ لا علاقةَ له
  /// بالفرع — «موضعٌ آخرُ يُرضي الفحصَ»، وهو فخٌّ سُجِّلَ في هذا المستودعِ
  /// خمسَ مرّات. فالصيغتان:
  ///   • **أ** — `if (<شرط>) return;` فالمدى هو **الشرطُ** وحدَه (وفيه
  ///     يَقعُ `confirm(` المُلغى، وهو كلمةٌ بحقّ).
  ///   • **ب** — `… { … return; }` فالمدى هو **الكتلةُ الحاويةُ** وحدَها.
  List<List<String>> silentReturns(String body) {
    final out = <List<String>>[];
    for (final rm in RegExp(r'\breturn\s*;').allMatches(body)) {
      var k = rm.start - 1;
      while (k >= 0 && ' \t\n\r'.contains(body[k])) {
        k--;
      }
      String? scope;
      var form = 'ب';
      if (k >= 0 && body[k] == ')') {
        final op = openOf(body, k, '(', ')');
        if (op > 0 && body.substring(0, op).trimRight().endsWith('if')) {
          scope = body.substring(op, k + 1);
          form = 'أ';
        }
      }
      if (scope == null) {
        var d = 0;
        var j = rm.start - 1;
        while (j >= 0) {
          if (body[j] == '}') {
            d++;
          } else if (body[j] == '{') {
            if (d == 0) break;
            d--;
          }
          j--;
        }
        scope = j >= 0 ? body.substring(j + 1, rm.start) : body.substring(0, rm.start);
      }
      if (speaks.hasMatch(scope)) continue;
      // الشُذرةُ **ذيلُ المدى** لا «ما بعدَ آخرِ فاصلةٍ منقوطة»: في الصيغةِ ب
      // يَنتهي المدى بفاصلةٍ منقوطةٍ فيَعودُ الذيلُ فارغاً — والشُذرةُ الفارغةُ
      // تُقرأُ في رسالةِ الفشلِ «رجوعٌ بلا سبب» وهي ما يَقرؤه مَن يُراجِع.
      final flat = scope.replaceAll(RegExp(r'\s+'), ' ').trim();
      out.add([
        form,
        flat.length > 70 ? '…${flat.substring(flat.length - 70)}' : flat,
      ]);
    }
    return out;
  }

  // ───────────────────────── النطاقُ المُشتَقّ ─────────────────────────

  final panelFiles = <String, String>{};
  for (final dir in ['admin_panel/src/pages', 'admin_panel/src/components']) {
    for (final f in sourcesIn('$repo/$dir',
        atLeast: dir.endsWith('pages') ? 14 : 5, exts: ['.tsx', '.ts'])) {
      if (f.path.contains('.test.')) continue;
      panelFiles[f.path.substring(repo.length + 1)] = stripComments(f.readAsStringSync());
    }
  }

  final silent = <String, String>{}; // 'ملف#مُعالِج#ترتيب' → شُذرة
  var handlerCount = 0;
  panelFiles.forEach((rel, code) {
    final base = rel.split('/').last;
    handlers(code).forEach((name, body) {
      handlerCount++;
      final rows = silentReturns(body);
      for (var i = 0; i < rows.length; i++) {
        silent['$base#$name#$i'] = '[${rows[i][0]}] ${rows[i][1]}';
      }
    });
  });

  /// **الصامتُ المسموحُ، كلٌّ بسببِه** — مقارنةُ المجموعةِ كاملةً، فموضعٌ
  /// جديدٌ يُراجَعُ ومُدخَلٌ تَعفَّنَ يَسقطُ كذلك. والمفتاحُ **ملفٌّ ومُعالِجٌ
  /// وترتيبٌ** لا رقمُ سطر، فتعديلٌ أعلى الملفِّ لا يُسقِطُ الحارسَ زوراً.
  const allowed = <String, String>{
    // النموذجُ نفسُه يَمنعُ الإرسالَ: `<form onSubmit>` و`required` على
    // الحقولِ الثلاثةِ وزرٌّ `type="submit"` — فالمتصفّحُ يَتكلّمُ قبلَ أن
    // يَبلغَ الفحصُ. (مشدودٌ في «شواهدِ التعليل» أدناه.)
    'Drivers.tsx#handleAddDriver#0': 'النموذجُ يَمنعُ الإرسالَ بـrequired',
    // دفاعيٌّ: الزرُّ لا يُرسَمُ إلّا والحالةُ مضبوطة.
    'Drivers.tsx#handleSaveEdit#0': 'دفاعيّ: !editDriver',
    'Drivers.tsx#handleDelete#0': 'دفاعيّ: !deleteTarget',
    'Orders.tsx#handleAssignDriver#0': 'دفاعيّ: !assignModal',
    'Orders.tsx#handleEditVisit#0': 'دفاعيّ: !editModal',
    'Settings.tsx#handleConfirmDeleteZone#0': 'دفاعيّ: !zone',
    'Support.tsx#handleClose#0': 'دفاعيّ: !selected',
    // مُنتقي الملفِّ أُلغي — لا ضغطةَ انتهت، بل اختيارٌ لم يُتَّخَذ.
    'Drivers.tsx#handlePhotoChange#0': 'مُنتقي الملفِّ أُلغي',
    'Drivers.tsx#handleAddPhotoSelect#0': 'مُنتقي الملفِّ أُلغي',
    // خيارُ «اختر منطقة» النائبُ في القائمةِ المنسدلة: لا شيءَ اختيرَ بعد.
    'Settings.tsx#handleCopyPricesFrom#0': 'الخيارُ النائبُ في القائمة',
    // حرسُ ضغطةٍ مزدوجة — الكلامُ عنه ضجيجٌ على عملٍ جارٍ أصلاً
    // (نفسُ «مشاركةٌ جاريةٌ» في حارسِ دارت).
    'StoreProducts.tsx#handleSubmit#0': 'ضغطةٌ مزدوجة: isSaving',
    'Support.tsx#handleSend#0': 'ضغطةٌ مزدوجة: sending (ومعه !selected الدفاعيّ)',
  };

  group('(أ) الأربعةُ تَتكلّمُ — والنصُّ يَسمّي ما يَنقُص', () {
    /// كتلةُ الحِراسةِ التي تَلي شرطاً بنصِّه — لا «توستٌ في الملفّ».
    String guardBlock(String body, String cond) {
      final i = body.indexOf(cond);
      expect(i, greaterThan(0), reason: 'الشرطُ «$cond» لم يُعَدْ في الشفرة');
      final br = body.indexOf('{', i);
      expect(br, greaterThan(0));
      final end = closeOf(body, br, '{', '}');
      expect(end, greaterThan(br));
      return body.substring(br, end + 1);
    }

    void speaksIn(String rel, String fn, String cond, String msg) {
      final body = handlers(panelFiles[rel]!)[fn];
      expect(body, isNotNull, reason: '$rel: المُعالِجُ «$fn» لم يُعَدْ مُشتَقّاً');
      expect(guardBlock(body!, cond), contains("toast.error('$msg')"),
          reason: '$rel#$fn: فرعُ «$cond» بلا كلمة');
    }

    test('بثٌّ بلا عنوانٍ أو محتوى', () {
      speaksIn('admin_panel/src/pages/Notifications.tsx', 'handleSend',
          '!title.trim() || !body.trim()', 'العنوان والمحتوى مطلوبان قبل الإرسال');
    });

    test('تعيينٌ بلا سائقٍ أو موعد — فرعانِ لا فرعٌ واحد', () {
      speaksIn('admin_panel/src/pages/Orders.tsx', 'handleAssignDriver',
          '!selectedDriverId', 'اختر سائقاً متاحاً قبل التعيين');
      speaksIn('admin_panel/src/pages/Orders.tsx', 'handleAssignDriver',
          '!scheduledAt', 'حدّد موعد الخدمة قبل التعيين');
    });

    test('ردٌّ بلا نصّ', () {
      speaksIn('admin_panel/src/pages/Support.tsx', 'handleSend',
          '!reply.trim()', 'اكتب نص الرد قبل الإرسال');
    });

    test('نسخُ أسعارٍ من منطقةٍ زالت', () {
      speaksIn('admin_panel/src/pages/Settings.tsx', 'handleCopyPricesFrom',
          '!snap.exists()',
          'تعذّر قراءة أسعار المنطقة المصدر — حدّث الصفحة وأعد المحاولة');
    });
  });

  group('(ب) مجموعةُ الصامتِ كاملةً = القائمةُ المُعلَنةُ بأسبابِها', () {
    test('لا موضعَ صامتٍ خارجَ القائمة، ولا مُدخَلَ تَعفَّن', () {
      final extra = silent.keys.where((k) => !allowed.containsKey(k)).toList()
        ..sort();
      final stale = allowed.keys.where((k) => !silent.containsKey(k)).toList()
        ..sort();
      expect(extra, isEmpty,
          reason: 'رجوعٌ عارٍ صامتٌ جديد — أهو نهايةُ ضغطةٍ قصدَها الأدمن؟\n'
              '${extra.map((k) => '  $k  ${silent[k]}').join('\n')}');
      expect(stale, isEmpty,
          reason: 'مُدخَلٌ في القائمةِ لم يَعُدْ موجوداً — يُرفَعُ لا يُترَك:\n'
              '  ${stale.join('\n  ')}');
    });
  });

  group('(ج) الكاشفُ يَعضُّ — والمسحُ لم يَنحلّ', () {
    test('أرضيّةُ المسح', () {
      expect(panelFiles.length, greaterThanOrEqualTo(20),
          reason: 'مسحُ اللوحةِ انحلَّ — الحارسُ بلا موضوع');
      expect(handlerCount, greaterThanOrEqualTo(40),
          reason: 'اشتقاقُ المُعالِجاتِ انحلَّ — صفرُ مُعالِجٍ يُقرأُ «نظيف»');
    });

    test('الصيغتانِ تُميَّزانِ على شكلٍ مُصطنَع', () {
      // المصدرُ بعدَ الإصلاحِ نظيفٌ، فنجاحُ (ب) وحدَه لا يُبرهِنُ أنّ
      // الكاشفَ يَرى شيئاً — فيُجرَّبُ على الأشكالِ التي يُفرّقُ بينها.
      const probe = '''
const h = async () => {
  if (!x) return;
  if (!await confirm('ك')) return;
  if (!y) { toast.error('ك'); return; }
  if (!z) { setBusy(false); return; }
  try { await f(); } catch (e) { toast.error('ك'); return; }
};
''';
      final body = handlers(stripComments(probe))['h'];
      expect(body, isNotNull, reason: 'اشتقاقُ المُعالِجِ نفسُه انحلّ');
      final rows = silentReturns(body!);
      expect(rows.length, 2,
          reason: 'المتوقَّعُ صامتانِ (!x و!z) — الخَرْج: $rows');
      expect(rows[0][0], 'أ');
      expect(rows[0][1], contains('!x'));
      expect(rows[1][0], 'ب');
      expect(rows[1][1], contains('setBusy'));
    });

    test('ولا يَرضى بتوستٍ في موضعٍ آخرَ من الجسم', () {
      // الفخُّ بعينِه: نافذةٌ «قبلَ الرجوع» كانت ستَقرأُ هذا «يَتكلّم».
      const probe = '''
const h = async () => {
  if (!a) { toast.error('ك'); return; }
  if (!b) return;
};
''';
      final rows = silentReturns(handlers(stripComments(probe))['h']!);
      expect(rows.length, 1, reason: 'الخَرْج: $rows');
      expect(rows[0][1], contains('!b'));
    });
  });

  group('(د) شواهدُ التعليل', () {
    test('نموذجُ إضافةِ السائقِ هو ما يَمنعُ الإرسالَ فعلاً', () {
      final code = panelFiles['admin_panel/src/pages/Drivers.tsx']!;
      final i = code.indexOf('<form onSubmit={handleAddDriver}');
      expect(i, greaterThan(0),
          reason: 'زالَ `<form onSubmit>` — فالفحصُ الصامتُ صارَ كلَّ الحماية '
              'ويُراجَعُ مُدخَلُه في القائمةِ لا يُسكَت');
      final end = code.indexOf('</form>', i);
      expect(end, greaterThan(i));
      final form = code.substring(i, end);
      expect(RegExp(r'\brequired\b').allMatches(form).length,
          greaterThanOrEqualTo(3),
          reason: 'الحقولُ الثلاثةُ (اسم/جوال/بريد) هي ما يُثبّتُه المتصفّح');
      expect(form, contains('type="submit"'),
          reason: 'بلا زرِّ إرسالٍ لا يُنفّذُ المتصفّحُ required أصلاً');
    });

    test('والأربعةُ الأخرى بلا نموذجٍ يَمنع', () {
      for (final f in [
        'Notifications.tsx',
        'Orders.tsx',
        'Support.tsx',
        'Settings.tsx',
      ]) {
        final rel = 'admin_panel/src/pages/$f';
        expect(panelFiles[rel], isNot(contains('<form')),
            reason: '$f: ظهرَ `<form>` — إن صارَ يَمنعُ بـrequired فالتعليلُ '
                'يُراجَعُ لا يُسكَت');
      }
      // مضادّةٌ: الحجبُ هو ما يُخرِجُ العبارةَ من الشفرة، لا زوالُها من الملفّ
      // — وشرحي في الثلاثةِ الأُولى يَقتبسُها، فبلا الحجبِ يَسقطُ الفحصُ على
      // توثيقِه (الفخُّ المسجَّلُ ثلاثةَ عشَرَ مرّة).
      for (final f in ['Notifications.tsx', 'Orders.tsx', 'Support.tsx']) {
        expect(read('admin_panel/src/pages/$f'), contains('`<form>`'),
            reason: '$f: زالَ شرحُ سببِ غيابِ النموذج');
      }
    });

    test('ونسخُ الأسعارِ يُنبّهُ في النجاحِ وفي catch — فالفرعُ الأوسطُ شاذّ', () {
      final body = handlers(panelFiles['admin_panel/src/pages/Settings.tsx']!)[
          'handleCopyPricesFrom']!;
      expect(body, contains('toast.success('),
          reason: 'لولا توستِ النجاحِ لَما كان الصمتُ مميَّزاً');
      expect(body, contains("toast.error('تعذّر نسخ الأسعار')"));
    });

    test('والنصفُ الآخرُ من القاعدةِ قائمٌ في دارت بمواضعِه الثلاثة', () {
      // `contains('lib/screens')` وحدَه كان يُرضيه أيٌّ من ثمانيةِ وُرودٍ في
      // ذلك الملفّ — «موضعٌ آخرُ يُرضي الفحصَ». فالمشدودُ المواضعُ الثلاثةُ
      // التي كُتبَ لها: زرُّ نسخِ كودِ الإحالة، و«تم الإنجاز» عند السائق،
      // و«فتح PDF»/«مشاركة» في سجلِّ الفواتير.
      //
      // ونطاقُ ذلك الحارسِ **قائمةُ ملفّاتٍ مكتوبةٌ بيدٍ لا مسحٌ مُشتَقّ**:
      // مُسجَّلٌ لا مُعالَجٌ هنا (قرارٌ واحدٌ لكلِّ شريحة)، والمُصنِّفُ أعلاه
      // هو ما يَصلحُ لتوسيعِه حين يُفرَدُ له دور.
      final dart = read('test/silent_return_test.dart');
      for (final site in const [
        'lib/screens/driver_dashboard.dart',
        'lib/screens/admin/admin_invoices_screen.dart',
        'lib/screens/profile_screen.dart',
      ]) {
        expect(dart, contains(site),
            reason: 'حارسُ العميلِ فقدَ «$site» — النصفُ الأوّلُ من القاعدةِ '
                'يَتجوّفُ فتَعودُ إلى سطحٍ واحد');
      }
    });
  });
}
