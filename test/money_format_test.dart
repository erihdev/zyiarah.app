// ════════════════════════════════════════════════════════════════════════
// «٣٥٫٠ ر.س» على رفِّ المتجر — رقمُ مالٍ يُطبَعُ خامّاً (2026-10-06)
//
// الرقمُ في Firestore قد يكون `int` أو `double` بحسبِ مَن كتبَه، ومحرّرا
// الإدارةِ يَكتبانِ `double.tryParse(...) ?? 0.0` — فسعرُ ٣٥ يُخزَّنُ `35.0`،
// و`'$v'` في دارت تَطبعُه **«35.0 ر.س»**. ولا يَظهرُ ذلك في أيِّ فحص:
// النوعُ صحيحٌ، والنصُّ قبيحٌ فحسب — على رفِّ المتجرِ وفي السلّةِ وفي
// مجموعِها، وفي بطاقاتِ الباقاتِ والعقود.
//
// والقاعدةُ موجودةٌ في المستودعِ من قبل (`formatSar`: صحيحٌ بلا كسور، وإلّا
// خانتان) وتعليقُها يَقول إنّها كُتبت لِيُعرَضَ **نفسُ الرقمِ الذي يُدفَع**؛
// وكانت مُنفَّذةً في شاشةٍ واحدة. و`formatSarAny` تُطبّقُها على قيمةٍ من
// مستندٍ (`Object?`) كي تُستعمَلَ مباشرةً على الخريطة.
//
// والقاعدةُ المشدودةُ: **كلُّ رقمٍ يُسبَقُ بـ«ر.س» في `lib/` مُنسَّق**، مع
// استثناءاتٍ مُسمّاةٍ لصِيَغٍ أخرى مقصودة.
// ════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/home_packages.dart';

/// صِيَغُ التنسيقِ المقبولةُ — كلٌّ قرارٌ قائمٌ في موضعِه.
const List<String> _formatters = <String>[
  'formatSarAny(', // القاعدةُ العامّة
  'formatSar(', // الأصلُ لقيمةٍ `double` معروفةِ النوع
  'toStringAsFixed', // خانتانِ دائماً — عمودُ مبالغِ قائمةِ الطلبات
  '_trim(', // «صحيحٌ بلا كسورٍ وإلّا `toString`» — سعرُ الوحدةِ في السوفا
  '_t(', // النسخةُ نفسُها في `service_meta_view`
  'toInt', 'round', 'NumberFormat', 'intl.',
];

/// كلُّ تعبيرٍ يُعرَضُ قبلَ «ر.س» في سطرٍ — **بموازنةِ الأقواس**.
///
/// الشكلانِ: `${...}` بأيِّ تعقيدٍ (ومنه `${...}` متداخل) و`$ident` العاري.
List<String> _sarExprs(String line) {
  final out = <String>[];
  for (final m in RegExp(r'ر\.س').allMatches(line)) {
    var i = m.start - 1;
    while (i >= 0 && line[i] == ' ') {
      i--;
    }
    if (i < 0) continue;
    if (line[i] == '}') {
      var depth = 0;
      var j = i;
      while (j >= 0) {
        if (line[j] == '}') depth++;
        if (line[j] == '{') {
          depth--;
          if (depth == 0) break;
        }
        j--;
      }
      if (j < 1 || line[j - 1] != r'$') continue;
      out.add(line.substring(j + 1, i).trim());
    } else {
      final mm = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)$')
          .firstMatch(line.substring(0, i + 1));
      if (mm != null) out.add(mm.group(1)!);
    }
  }
  return out;
}

void main() {
  test('(أ) القاعدةُ سلوكاً: صحيحٌ بلا كسور، وإلّا خانتان', () {
    expect(formatSarAny(35), '35');
    expect(formatSarAny(35.0), '35');
    expect(formatSarAny(35.5), '35.50');
    expect(formatSarAny(172.456), '172.46');
    expect(formatSarAny('35.0'), '35', reason: 'نصٌّ رقميٌّ من مستندٍ قديم');
    expect(formatSarAny(null), '0');
    expect(formatSarAny('قيد التسعير'), '0',
        reason: 'غيرُ الرقميِّ يُقرأُ صفراً — فلا يُمرَّرُ نصٌّ هنا');
    expect(formatSarAny(0), '0');
    expect(formatSarAny(-5.5), '-5.50');
  });

  test('(ب) لا رقمَ خامّاً قبلَ «ر.س» في أيِّ ملفٍّ تحتَ lib/', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();
    expect(files.length, greaterThanOrEqualTo(120),
        reason: 'المسحُ لم يَقرأ شيئاً — حارسٌ أجوف');
    var withSar = 0;
    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//') || !l.contains('ر.س')) continue;
        withSar++;
        // **شكلانِ لا شكلٌ واحد:** `${...}` بأيِّ محتوى (ومنه تعبيرٌ يَبدأُ
        // بقوس) و`$ident` العاري. أوّلُ صياغةٍ شَرطت أن يَبدأَ المحتوى
        // بحرفٍ، فكان `${(a ?? b)} ر.س` **لا يُطابَقُ أصلاً** — كشفَه
        // اختبارُ قضمٍ نزعَ المُنسّقَ من تقريرِ الـPDF فمرَّ أخضر.
        // **و`[^}]*` لا يَعبُرُ `${...}` متداخلاً — الثغرةُ الثالثةُ في
        // هذا المُستخرِجِ وأُصلحت بموازنةِ الأقواس (2026-10-06).** في
        // `admin_store_orders_screen` كان المبلغُ
        // `${(double.tryParse('${item['quantity']…}') ?? 0) * (…)}` —
        // فالنمطُ يَتوقّفُ عند أوّلِ `}` (وهو إغلاقُ الـ`${` الداخليّ) فلا
        // يُطابِقُ شيئاً، والسطرُ لا يُفحَصُ أصلاً: «70.0 ر.س» في قائمةِ
        // بنودِ طلبِ المتجرِ عند الأدمن. ولم يَرَها مسحُ الـ٢٤ لأنّها
        // **حاصلُ ضربٍ** لا قراءةَ حقل.
        for (final m in _sarExprs(l)) {
          final expr = m;
          if (_formatters.any(expr.contains)) continue;
          // نصٌّ لا رقم: مُنتقي الوحدةِ (`… ? '%' : 'ر.س'`) ونظائرُه.
          //
          // **والاقتباسُ يُفحَصُ بعدَ نزعِ `[...]`:** أوّلُ صياغةٍ تَخطَّت كلَّ
          // تعبيرٍ فيه علامةُ اقتباس، و`data['amount']` فيه اقتباسانِ —
          // فأُعقِمَ الفحصُ عن **أغلبِ** المواضع، وكشفَه اختبارُ قضمٍ أعادَ
          // بريدَ الإدارةِ خامّاً فمرَّ أخضر.
          var noIndex = expr.replaceAll(RegExp(r'\[[^\]]*\]'), '');
          // **واستقراءٌ داخليٌّ (`'${...}'`) مصدرُ رقمٍ لا نصُّ تسمية.**
          // نزعُ `[...]` وحدَه كان يُبقي علامتَي اقتباسِ الاستقراء، فيُقرأُ
          // التعبيرُ «نصّاً» ويُتخطّى — وهو ما أخفى حاصلَ الضربِ في
          // `admin_store_orders_screen` **بعدَ** إصلاحِ الموازنةِ أعلاه
          // (أثبتَه اختبارُ قضمٍ: الموازنةُ وحدَها لم تَعضّ).
          var prev = '';
          while (prev != noIndex) {
            prev = noIndex;
            noIndex = noIndex.replaceAll(RegExp(r"'\$\{[^{}]*\}'"), '0');
          }
          if (noIndex.contains("'") || noIndex.contains('"')) continue;
          // **مُعرِّفٌ مفردٌ يُحَلُّ إلى تعريفِه في الملفِّ نفسِه** بدلَ
          // قائمةِ أسماءٍ تَتعفّن: `formattedAmount` و`reward` و`v` كلُّها
          // منسَّقةٌ عند الإسناد، وقائمةٌ يدويّةٌ كانت ستَقبلُ غيرَها غداً.
          final bare = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(expr);
          if (bare) {
            final def = RegExp(
                    '(?:final|var|const|double|int|num|String)[^;\n]*\\b'
                    '${RegExp.escape(expr)}\\s*=([^;]*);',
                    dotAll: true)
                .firstMatch(lines.join('\n'));
            if (def != null &&
                _formatters.any(def.group(1)!.contains)) {
              continue;
            }
            if (def == null) {
              offenders.add('$path:${i + 1}  → $expr (لا تعريفَ في الملفّ)');
              continue;
            }
          }
          offenders.add('$path:${i + 1}  → $expr');
        }
      }
    }
    expect(withSar, greaterThanOrEqualTo(60),
        reason: 'لم يُعثَر على أسطرِ «ر.س» — فالمسحُ لا يَفحصُ شيئاً');
    expect(offenders, isEmpty,
        reason: 'رقمُ مالٍ يُطبَعُ خامّاً — «35.0 ر.س»:\n'
            '${offenders.join('\n')}');
  });

  test('(ج) القاعدةُ تَسكنُ موضعاً واحداً ومعها شرحُها', () {
    final util = File('lib/utils/home_packages.dart').readAsStringSync();
    expect(RegExp(r'String formatSarAny\(').allMatches(util).length, 1,
        reason: 'نسخةٌ ثانيةٌ من القاعدةِ تَنحرِف');
    expect(util.contains('formatSar('), isTrue,
        reason: 'لم تَعُد تَستعملُ القاعدةَ الأصليّة — فالصيغتانِ تَفترقان');
    expect(util.contains('35.0'), isTrue,
        reason: 'شرحُ سببِ الوحدةِ زال، فلا يَعرفُ قارئٌ ما تَحرُسُه');
    // **ولا فحصَ «لا صيغةَ رابعة»:** جُرِّبَ بعَدِّ `roundToDouble() ?`
    // فالتقطَ مُنسّقَ النسبةِ (`fmtPercent`) ومُنسّقَ التقييمِ ومُعبّئَ
    // حقلِ نصٍّ في محرّرِ المناطق — ثلاثةٌ لا علاقةَ لها بالريال. فحصٌ لا
    // يُميّزُ المالَ من غيرِه ضجيجٌ، والحارسُ الحقيقيُّ هو (ب): كلُّ موضعِ
    // عرضٍ يُنادي صيغةً مُعتمَدة.
  });

  test('(د) ورفُّ المتجرِ والسلّةُ يُنادِيانِها — الموضعُ الذي ظهرَ فيه', () {
    final store = File('lib/screens/store_screen.dart').readAsStringSync();
    expect(RegExp(r'formatSarAny\(').allMatches(store).length,
        greaterThanOrEqualTo(4),
        reason: 'رفُّ المتجرِ والسلّةُ ومجموعُها: أربعةُ مواضعَ على الأقل');
  });

  // ══════════════════════════════════════════════════════════════════
  // واللوحةُ كانت بأربعِ صِيَغ (2026-10-06)
  // ══════════════════════════════════════════════════════════════════
  // القاعدةُ أعلاه (ب) تَمسحُ `lib/` وحدَها، والقاعدةُ عامّة — **«حارسٌ
  // ضيّقٌ وقاعدةٌ عامّة» مرّةً أخرى.** ومسحُ اللوحةِ بالقاعدةِ نفسِها أعطى
  // أربعَ صِيَغٍ للمبلغِ الواحد:
  //   • `formatCurrency` في `Accountants.tsx` وحدَها:
  //     `toLocaleString('ar-SA', {maximumFractionDigits: 0})` — **تُسقِطُ
  //     الهللاتَ** من الإيرادِ وصافي الأرباحِ والرواتب، وتَكتبُ أرقاماً
  //     عربيّةً-هنديّةً في لوحةٍ أرقامُها كلُّها لاتينيّة.
  //   • `.toLocaleString()` بلا وسائطَ في `Payroll.tsx` (سبعةُ مواضع).
  //   • و`sar()` في `serviceMeta.ts`: خانتانِ دائماً.
  //   • واثنا عشَرَ موضعاً **خامّاً** (`{product.price} ر.س`).
  // فالمبلغُ الواحدُ يُقرأُ «١٧٢٬٥٠٠» و«172.50» و«172.5».
  //
  // **وإسقاطُ الكسورِ قرارٌ سُمّي عطلاً في هذا المستودعِ من قبل:** تعليقُ
  // `formatSar` نفسُه يَقول «الرقاقةُ والملخّصُ يَعرضانِ **نفس** الرقمِ الذي
  // يُدفَع (كان تقريبُ الرقاقةِ لصفرِ كسورٍ يُظهرُ سعراً يُخالِفُ الفاتورة)».
  //
  // **وما لم يُمَسَّ، بسببِه:** `service_meta_view.dart` ↔ `serviceMeta.ts`
  // **زوجُ مرآةٍ مُختبَرٌ** (`admin_meta_parity_test` يُقارِنُ خَرْجَيهما):
  // المجاميعُ `toFixed(2)`/`toStringAsFixed(2)` وأسعارُ الوحدةِ مُقلَّمةٌ في
  // **الجهتَين معاً**. وتغييرُ جهةٍ وحدَها يَكسِرُ المرآة — جُرِّبَ فأسقطَ
  // أربعةَ فحوصٍ في اللوحة، فأُعيد؛ وتغييرُ الاثنتَين قرارُ عرضٍ على كشفٍ
  // يُشبهُ الفاتورة لا إصلاحُ عطل. ولذلك `_t(` و`_trim(` يَبقيانِ في
  // `_formatters` أعلاه كما كانا.
  group('واللوحة', () {
    /// تعبيرُ المبلغِ قبلَ «ر.س» في JSX — بموازنةِ الأقواسِ **وتخطّي الوسمِ
    /// المجاور**: الشكلُ الغالبُ هناك `{expr} <span …>ر.س</span>`، فالمحرفُ
    /// قبلَ النصِّ `>` لا `}`. وبلا التخطّي يَهبطُ عددُ المفحوصِ إلى حفنةٍ
    /// ويَبقى الفحصُ **أخضرَ** — مُثبَتٌ باختبارِ قضم، ولذلك أرضيّةُ العدِّ.
    List<String> scan(String src, List<String> seen) {
      final out = <String>[];
      for (final m in RegExp(r'ر\.س').allMatches(src)) {
        var i = m.start - 1;
        while (i >= 0) {
          while (i >= 0 && (src[i] == ' ' || src[i] == '\n')) {
            i--;
          }
          if (i >= 0 && src[i] == '>') {
            final lt = src.lastIndexOf('<', i);
            if (lt < 0) break;
            i = lt - 1;
            continue;
          }
          break;
        }
        if (i < 0 || src[i] != '}') continue;
        var depth = 0;
        var j = i;
        while (j >= 0) {
          if (src[j] == '}') depth++;
          if (src[j] == '{') {
            depth--;
            if (depth == 0) break;
          }
          j--;
        }
        if (j < 0) continue;
        final expr = src.substring(j + 1, i).trim();
        if (expr.isEmpty || expr.length > 140) continue;
        seen.add(expr);
        final ok = expr.contains('formatSar') ||
            expr.contains('toFixed') ||
            expr.contains('priceReviewLine') ||
            expr.contains("'—'") ||
            expr.contains('Math.round');
        if (!ok) out.add(expr.replaceAll(RegExp(r'\s+'), ' '));
      }
      return out;
    }

    test('(ه) لا مبلغَ خامّاً في صفحاتِ اللوحةِ ومُكوّناتِها', () {
      final files = [
        ...Directory('admin_panel/src/pages').listSync().whereType<File>(),
        ...Directory('admin_panel/src/components')
            .listSync(recursive: true)
            .whereType<File>(),
      ]
          .where((f) =>
              (f.path.endsWith('.tsx') || f.path.endsWith('.ts')) &&
              !f.path.contains('.test.'))
          .toList();
      expect(files.length, greaterThan(10), reason: 'المسحُ لم يَقرأ شيئاً');
      final seen = <String>[];
      final offenders = <String>[];
      for (final f in files) {
        for (final o in scan(f.readAsStringSync(), seen)) {
          offenders.add('${f.path}  →  $o');
        }
      }
      expect(seen.length, greaterThanOrEqualTo(25),
          reason: 'فُحِصَ ${seen.length} موضعاً فقط — تخطّي وسمِ JSX تعطّل، '
              'فالمسحُ أجوفُ لا اللوحةُ نظيفة');
      expect(offenders, isEmpty,
          reason: 'مبلغٌ يُعرَضُ بلا قاعدةِ العرضِ في اللوحة:\n'
              '${offenders.join('\n')}');
    });

    test('(و) والقاعدةُ تَسكنُ مرّةً في اللوحةِ — لا صيغةَ محلّيّة', () {
      final money = File('admin_panel/src/utils/money.ts').readAsStringSync();
      expect(money.contains('export function formatSar'), isTrue);
      expect(money.contains('export function formatSarAny'), isTrue);
      // **والمصطلحُ المحظورُ هو مِقبضُ المالِ لا `toLocaleString` نفسُها.**
      // أوّلُ صياغةٍ حظرت `toLocaleString` في اللوحةِ كلِّها، فسقطت على
      // **أربعةِ استعمالاتٍ مشروعةٍ للتواريخ** (جدولةُ الإشعارِ، تاريخُ طلبِ
      // المتجر) **وعلى تعليقي نفسِه** الذي يَقتبسُ العبارةَ ليَشرحَ الإزالة —
      // «الحارسُ يَسقطُ على توثيقِه» مرّةً أخرى. والمقبضُ `maximumFractionDigits`
      // خاصٌّ بالمالِ ولا تَستعملُه صِيَغُ التاريخ.
      for (final f in Directory('admin_panel/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              (f.path.endsWith('.tsx') || f.path.endsWith('.ts')) &&
              !f.path.contains('.test.'))) {
        final code = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('maximumFractionDigits'), isFalse,
            reason: '${f.path}: صيغةُ مالٍ محلّيّةٌ تُسقِطُ الهللاتِ — '
                'القاعدةُ في `utils/money`');
        expect(code.contains('function formatCurrency'), isFalse,
            reason: '${f.path}: عادت الصيغةُ المحلّيّةُ باسمِها');
      }
      // ومضادَّةُ فرطِ الحجب: العبارةُ ما زالت في الخامِّ تَشرحُ القرار.
      expect(File('admin_panel/src/pages/Accountants.tsx').readAsStringSync(),
          contains('maximumFractionDigits'),
          reason: 'زالَ شرحُ القرارِ، فلا يَعرفُ قارئٌ لماذا');
      expect(File('admin_panel/src/pages/Accountants.tsx').readAsStringSync(),
          contains("from '../utils/money'"));
    });

    test('(ز) وجدولُ الحالاتِ واحدٌ بين الجهتَين', () {
      // الكتلةُ تَسكنُ فحصَ اللوحةِ (`node:fs` بلا أنواعٍ تحت
      // `tsconfig.app.json`) ويَقرؤها هذا الفحصُ — نمطُ `serviceMeta` و
      // `buildGate` و`couponUses` و`couponExpiry` نفسُه.
      final src =
          File('admin_panel/src/utils/money.test.ts').readAsStringSync();
      final a = src.indexOf('// ⟦CASES⟧');
      final b = src.indexOf('// ⟦/CASES⟧');
      expect(a, greaterThan(0), reason: 'علامةُ كتلةِ الحالاتِ مفقودة');
      expect(b, greaterThan(a));
      final block = src.substring(a, b);
      // **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**: `indexOf('[')` يَلتقطُ
      // قوسَ تعليقِ النوعِ (`[number, string][]`) لا بدايةَ المصفوفة.
      final end = block.lastIndexOf(']');
      var depth = 0;
      var start = -1;
      for (var i = end; i >= 0; i--) {
        if (block[i] == ']') depth++;
        if (block[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThan(-1), reason: 'تعذّرَ اقتطاعُ كتلةِ الحالات');
      var json = block.substring(start, end + 1);
      json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
      // صفوفُ هذا الجدولِ تَحملُ نصوصاً وTypeScript تَكتبُها بعلامةٍ مفردةٍ
      // و`jsonDecode` تَرفضُها — بخلافِ الجداولِ الرقميّةِ في المرايا الأخرى.
      json = json.replaceAll("'", '"');
      final rows = (jsonDecode(json) as List<dynamic>)
          .map((r) => r as List<dynamic>)
          .toList();
      expect(rows.length, greaterThanOrEqualTo(7),
          reason: 'الجدولُ انهارَ — اقتطاعٌ فاشلٌ لا جدولٌ قصير');
      // أصنافٌ لا عدد: صحيحٌ، وخانةٌ واحدةٌ تُكمَل، وتقريبٌ، وسالب.
      expect(rows.any((r) => !'${r[1]}'.contains('.')), isTrue);
      expect(rows.any((r) => '${r[1]}' == '172.50'), isTrue,
          reason: 'لا حالةَ خانةٍ واحدةٍ تُكمَلُ إلى خانتَين');
      expect(rows.any((r) => '${r[1]}' == '1234.57'), isTrue,
          reason: 'لا حالةَ تقريب');
      expect(rows.any((r) => (r[0] as num) < 0), isTrue, reason: 'لا سالب');
      // **وهذا الفحصُ يُثبّتُ جهةَ الدارتِ على الجدول؛ وجهةُ اللوحةِ
      // تُثبّتُها `money.test.ts` نفسُها على الجدولِ عينِه** (مُثبَتٌ بقضمٍ:
      // `toFixed(3)` في TypeScript يُسقِطُ فحصَي vitest). فالمهمّتانِ في CI
      // كلتاهما، والجدولُ الواحدُ هو ما يَربِطُ الحكمَين.
      for (final r in rows) {
        expect(formatSarAny(r[0]), r[1], reason: '${r[0]}');
      }
    });
  });
}
