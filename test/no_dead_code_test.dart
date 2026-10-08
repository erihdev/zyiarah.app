// حارس دائم: **لا عضوَ ميّتاً في `lib/services/` و`lib/utils/`** — كلُّ دالّةٍ أو
// جالبٍ يُعرَّف هناك لا بدّ أن يُنادى من مكانٍ آخر في `lib/` أو `test/`.
//
// لماذا حارسٌ ثانٍ، و`test/no_dead_files_test.dart` قائم؟ لأنّ ذاك يفحص **الملفّات**
// (كلُّ ملفّ لا بدّ أن يُستورَد)، فحين تعفّنت الشيفرة هذه المرّة نزلت طابقاً: ثلاثةَ
// عشرَ ملفّاً كلُّها مُستورَدة وحيّة، وداخلها ٣٦ عضواً لا يناديه شيء — ولم يرَها
// `flutter analyze` ولا المُصرِّف ولا اختبارٌ واحد. ثلاثُ مجموعاتٍ منها كانت بقايا
// قراراتٍ نُفِّذت في الواجهة ونُسيت في الخدمة:
//
//   • سطحُ «الدخول برقم الجوال + OTP» (٦ دوالّ) — والتطبيق يُسجّل ببريدٍ حقيقيّ.
//     وفيه خللٌ نائم: `_phoneToEmail` يُسقط «966» ثمّ الصفرَ البادئ بهذا الترتيب،
//     فـ«00966…» و«0966…» يُنتجان حسابين مختلفين لنفس الرقم — بينما المُنظِّف
//     الصحيح في نفس الملفّ داخل `getUserRole`.
//   • تسعُ دوالِّ إشعارٍ من العميل هاجرت إلى Cloud Functions وبقيت أجسادُها —
//     وهي تكتب في `notification_triggers` **القابلة للكتابة من العميل**، وهو
//     السببُ المكتوب في `order_service.dart` لإزالة نظيرتها من مسار الإلغاء.
//   • `acceptOrder` ورفاقُها: «قبول/رفض السائق» أُزيل بقرار المالك من الواجهة
//     وبقي في الخدمة (ولا حارسَ لذلك القرار، خلافاً لـCOD وتابي).
//
// **ما لا يراه هذا الحارس، صراحةً:** يطابق **الأسماء**. فعضوٌ اسمُه يُشبه دالّةً في
// حزمةٍ خارجيّة يُقرأ «مستعمَلاً» وهو ميّت — وهكذا اختبأ نصفُ سطح الجوّال:
// `user.updatePassword` من FirebaseAuth، و`_auth.verifyPhoneNumber` منها أيضاً،
// و`Moyasar.verifyOTP` من حزمة الدفع. لذلك يلي الفحصَ العامَّ **قائمةُ منعٍ
// صريحة** بتلك الأسماء بالذات، على نمط `no_tabby_test.dart`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

/// يُقنّع التعليقات والسلاسل بمسافات **مع حفظ الأطوال**، كي لا يُحسَب ذِكرُ اسمٍ
/// في تعليقٍ أو نصٍّ نداءً له. (حذفُ الأسطر بدل التقنيع يُزيح الإزاحات — وهو
/// الخطأ الذي أفسد أوّل نسخة من حارس الخطوط.)
String _mask(String s) {
  final out = s.split('');
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      var j = s.indexOf('\n', i);
      if (j < 0) j = s.length;
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      var j = s.indexOf('*/', i + 2);
      j = j < 0 ? s.length : j + 2;
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else if (c == '"' || c == "'") {
      // داخل السلسلة نُقنّع النصّ **ولا نُقنّع الاستبدال** `${...}` و`$name`:
      // فيه شيفرةٌ حقيقيّة. أوّلُ نسخةٍ من هذا الحارس قنّعت السلسلة كاملةً
      // فقرأت `formatSar` ميّتةً وهي مُناداة ثلاثَ مرّات داخل "${formatSar(x)} ر.س".
      final q = c;
      var j = i + 1;
      while (j < s.length) {
        if (s[j] == r'\') {
          out[j] = ' ';
          if (j + 1 < s.length) out[j + 1] = ' ';
          j += 2;
          continue;
        }
        if (s[j] == q || s[j] == '\n') break;
        if (s[j] == r'$' && j + 1 < s.length && s[j + 1] == '{') {
          var d = 0;
          var k = j + 1;
          while (k < s.length) {
            if (s[k] == '{') d++;
            if (s[k] == '}') {
              d--;
              if (d == 0) break;
            }
            k++;
          }
          j = k + 1; // تُركت كما هي
          continue;
        }
        if (s[j] == r'$') {
          var k = j + 1;
          while (k < s.length && RegExp(r'[A-Za-z0-9_$.]').hasMatch(s[k])) {
            k++;
          }
          j = k; // تُركت كما هي
          continue;
        }
        out[j] = ' ';
        j++;
      }
      i = j + 1;
    } else {
      i++;
    }
  }
  return out.join();
}

/// أرضيّةٌ **لكلِّ مجلّدٍ على حِدَة** لا عتبةٌ جامعة: `2` كانت تَكفي لـ
/// `lib/services` (عشرون) و`lib/utils` (خمسٌ وخمسون) معاً، فانحلالُ مسحِ
/// أيٍّ منهما إلى ملفَّين يَمُرّ — والعتبةُ الجامعةُ هي ما أمرَّ أخطاءً
/// مسجَّلةً في هذا المستودعِ مراراً. و`lib/providers` ملفٌّ واحدٌ اليومَ
/// (`user_provider`) بعد حذفِ `config_provider` و`order_provider`، فأرضيّتُه
/// `1` — ولو صارَ صفراً فالمجلّدُ زالَ وذاك يُراجَعُ لا يَمُرّ.
/// أيَعُدُّ ذِكرُ [name] في [masked] **استعمالاً**، أم مجرَّدَ تَصادُفِ اسم؟
///
/// الفحصُ العامُّ يُطابقُ الأسماء، فمُعرِّفٌ محلّيٌّ في ملفٍّ آخرَ يَحملُ الاسمَ
/// نفسَه كان يُقرأُ نداءً: `final orderStatus = …` في
/// `admin_order_details_screen` أحيا `ZyiarahStrings.orderStatus` وهي بلا
/// قارئٍ في المستودعِ كلِّه. فالمَواضعُ التي تُعَدُّ استعمالاً ثلاثةٌ بعينِها:
///
///   • **وصولُ عضو** — `X.name`.
///   • **نداء** — `name(` (ومعه الوسائطُ النوعيّةُ `name<T>(`).
///   • **تمريرُ الدالّةِ قيمةً** — `f(name)` أو `k: name`، وهو اصطلاحٌ دارتيٌّ
///     حقيقيٌّ (`onPressed: _save`، `.then(handleX)`) فلا يَجوزُ إسقاطُه.
///     **لكنّه لا يُقبَلُ من ملفٍّ يُعلِنُ الاسمَ لنفسِه**:
///     `_buildSummaryTable(total, activeOrders, done)` في `pdf_report_util`
///     تمريرُ **مُعامَلِه** هو لا جالبِ المُزوِّد — فبلا هذا القيدِ يُحيي
///     مُعامَلٌ مُسمّىً جالباً ميّتاً، وقد أحياه فعلاً.
///
/// وما يَبقى أعمى عنه، صراحةً: اسمٌ يُستعمَلُ قيمةً في ملفٍّ لا يُعلِنُه وهو
/// شيءٌ آخرُ تماماً. ذاك يَلزمُه تحليلُ أنواعٍ لا مُطابَقةُ نصّ.
bool mentionIsUse(String masked, String name) {
  final esc = RegExp.escape(name);
  final asMember = RegExp('${r'\.\s*'}$esc${r'\b'}');
  final asCall =
      RegExp('${r'(?<![\w.$])'}$esc${r'\s*(?:<[^>()]*>)?\s*\('}');
  // **ومُستقبِلاً كذلك** — `kJazanSw.longitude`: الاسمُ هو المُستقبِلُ لا
  // العضو، وهو استعمالٌ لا يَقلُّ صراحةً عن `X.name`. كان خارجَ الصُّوَرِ
  // الثلاثِ فقُرئَ ثابتانِ حيّانِ ميّتَين.
  final asReceiver = RegExp('${r'(?<![\w.$])'}$esc${r'\s*\.'}');
  if (asMember.hasMatch(masked) ||
      asCall.hasMatch(masked) ||
      asReceiver.hasMatch(masked)) {
    return true;
  }
  // ومعها `?` في صدرِ صورةِ القيمة: `(data?['x'] ?? kDefaultSofaSqmPrice)`
  // احتياطيٌّ مكتوبٌ بأحدَ عشَرَ موضعاً، وكان يُقرأُ ذِكراً لا استعمالاً.
  final asValue = RegExp('${r'[(,:=?]\s*'}$esc${r'\s*[,)\]};]'}');
  if (!asValue.hasMatch(masked)) return false;
  final declaresIt = RegExp(
      '${r'\b(?:final|const|var|late|required)\s+(?:[\w<>?,.]+\s+)?'}'
      '$esc'
      '${r'\b|\b[A-Za-z_]\w*(?:<[^<>]*>)?\??\s+'}'
      '$esc'
      '${r'\s*(?:=|;|,|\))'}');
  return !declaresIt.hasMatch(masked);
}

const _dirFloor = <String, int>{
  'lib': 150,
  'test': 150,
  'lib/services': 15,
  'lib/utils': 45,
  'lib/models': 10,
  'lib/providers': 1,
};

List<File> _dartFiles(String dir) => sourcesIn(dir,
    atLeast: _dirFloor[dir] ??
        (throw StateError('مجلّدٌ بلا أرضيّةٍ مُعلَنة: $dir')));

/// **و`\$` لا يَبدأُ مُعرِّفاً هنا بقصد.** المُقنِّعُ يُبقي الاستقراءَ
/// العاريَ (`'\$_baseUrl/payments'`) كي يُعَدَّ الاسم — ولو دخلَ `\$` في
/// أوّلِ الصنفِ لَصارَ الرمزُ `\$_baseUrl` اسماً آخرَ، فيُقرأُ الحقلُ
/// المُستعمَلُ ميّتاً. وقد قرأَه فعلاً حين وُسِّعَ الكاشفُ إلى الحقول.
final _ident = RegExp(r'[A-Za-z_][A-Za-z0-9_$]*');

/// عدّادُ المُعرِّفات لكلّ ملفّ — نبنيه مرّةً ثمّ نستعلم، بدل مسحِ كلّ الملفّات
/// لكلّ عضو (١٩٠ عضواً × ٢٠٠ ملفّ).
Map<String, int> _identCounts(String masked) {
  final m = <String, int>{};
  for (final t in _ident.allMatches(masked)) {
    m[t.group(0)!] = (m[t.group(0)!] ?? 0) + 1;
  }
  return m;
}

/// تعريفُ دالّةٍ أو جالبٍ داخل صنف (إزاحة سطرين) أو على المستوى الأعلى.
/// نستثني البُناة ونوابضَ الإطار التي يناديها فلاتر لا نحن.
final _method = RegExp(
    r'^( {2})?(?:static\s+)?(?:@override\s+)?'
    r'(?:[A-Za-z_][\w<>,\s\?\[\]\.]*?)\s+'
    r'(?:get\s+)?([a-zA-Z_]\w*)\s*(?:<[^>]*>)?\s*\(');
final _getter = RegExp(
    r'^( {2})?(?:static\s+)?(?:[A-Za-z_][\w<>,\s\?\[\]\.]*?)\s+'
    r'get\s+([a-zA-Z_]\w*)\s*(?:=>|\{)');

/// **وحقلٌ جالبٌ كذلك — وهذا ما كان خارجَ النظر.** الرأسُ أعلاه يَقولُ
/// القاعدةَ عن «كلِّ دالّةٍ وجالب»، و`_method` تَشترطُ `(` بعدَ الاسمِ
/// و`_getter` تَشترطُ كلمةَ `get` — فحقلٌ ساكنٌ (`static const String
/// actionX = '…';`) أو حقلُ نسخةٍ (`final DateTime? x;`) لا تُطابِقُه
/// أيٌّ منهما، **وفي دارت الحقلُ جالبٌ بالبناء**. فأربعُ مئةٍ وخمسون
/// حقلاً في المجلّداتِ الأربعةِ كانت بلا فحص: «حارسٌ ضيّقٌ وقاعدةٌ
/// عامّة» في الكاشفِ نفسِه، كشِريحةِ عدِّ الأحرفِ في حارسِ المهلاتِ
/// ونمطِ `\$e` في حارسِ نصِّ الاستثناء.
final _field = RegExp(
    r'^( {2})?(?:static\s+)?(?:(?:late\s+)?(?:final|const)\s+)?'
    r'(?:[A-Za-z_][\w<>,\s\?\[\]\.]*?)\s+'
    r'([a-zA-Z_]\w*)\s*(?:=(?!=)[^;]*)?;\s*$');

/// كلماتٌ مفتاحيّةٌ تَبدأُ بها جملةٌ تَنتهي بفاصلةٍ منقوطةٍ فتُقرَأُ
/// «تعريفَ حقلٍ» زوراً (`return x;`، `await f();`، `part of '…';`).
///
/// **وهي ليست حاملةً للمجموعةِ الميّتة، بل لِصدقِ العدّاد — قِيسَ الفرقُ.**
/// جملةٌ تَذكرُ اسمَها بنفسِها، فـ`own` لها ≥ ٢ ويَتخطّاها تسامحُ
/// «مرّةٌ واحدةٌ = سطرُ التعريفِ وحدَه» — فاختبارُ قضمٍ نزعَ المُرشِّحَ
/// ومرَّ **أخضرَ**. لكنّ `fieldsSeen` يَقفزُ من ٤٢٠ إلى ٤٤٠ بلاه، أي أنّ
/// عشرينَ جملةً تُعَدُّ حقولاً فتُرخي أرضيّةَ الحقولِ — والأرضيّةُ هي ما
/// يَكشفُ انحلالَ الكاشفِ أصلاً. فيَبقى بسببٍ مكتوبٍ لا بدعوى أنّه يَعضّ.
const _statementStarters = {
  'return', 'throw', 'rethrow', 'await', 'yield', 'assert', 'import',
  'export', 'part', 'library', 'break', 'continue', 'case', 'default',
  'else', 'do', 'new', 'super', 'this', 'typedef', 'show', 'hide', 'if',
  'for', 'while', 'switch', 'try', 'catch', 'finally',
  // و`set` **ليست** فيها بقصد: `set x(v)` مُحدِّدٌ كان `_method` يَراه
  // (النوعُ `set` والاسمُ `x` ثمّ `(`)، فإقصاؤه هنا يُنقِصُ تغطيةً قائمة.
};

const _frameworkMembers = {
  'build', 'initState', 'dispose', 'createState', 'didUpdateWidget',
  'didChangeDependencies', 'toString', 'noSuchMethod', 'operator', 'if',
  'for', 'while', 'switch', 'catch', 'return', 'assert', 'super', 'this',
};

void main() {
  // **النطاقُ وُسِّع (2026-10-05):** كان `services` و`utils` وحدَهما، والقاعدةُ
  // عامّة — فوجّهتُه إلى `models` و`providers` فوَجدَ ثلاثةَ جالباتٍ ميّتة،
  // أحدُها `UserProvider.profileError` الموثَّقُ بأنّ «الواجهةَ تَعرضُه» ولم
  // تَكن. (الشاشاتُ خارجَ النطاقِ بقصد: فيها تجاوزاتُ `build`/`initState`
  // ونداءاتٌ من الشجرةِ لا من الشفرة، فتَحتاجُ تصفيةً أخرى.)
  final scope = [
    ..._dartFiles('lib/services'),
    ..._dartFiles('lib/utils'),
    ..._dartFiles('lib/models'),
    ..._dartFiles('lib/providers'),
  ]..sort((a, b) => a.path.compareTo(b.path));

  final all = [..._dartFiles('lib'), ..._dartFiles('test')];
  final counts = <String, Map<String, int>>{};
  for (final f in all) {
    counts[f.path.replaceAll(r'\', '/')] = _identCounts(_mask(f.readAsStringSync()));
  }

  test('لا دالّة ولا جالب ميّتاً في services/utils/models/providers', () {
    final dead = <String>[];
    var fieldsSeen = 0;

    for (final f in scope) {
      final rel = f.path.replaceAll(r'\', '/');
      final masked = _mask(f.readAsStringSync());
      final lines = masked.split('\n');
      // اسمُ الصنف يُستثنى: البُناة تحمل اسمَه.
      final classNames = RegExp(r'^(?:abstract\s+)?class\s+(\w+)')
          .allMatches(masked)
          .map((m) => m.group(1)!)
          .toSet();

      final declared = <String>{};
      for (final l in lines) {
        final first = RegExp(r'^\s*([a-zA-Z_]\w*)').firstMatch(l)?.group(1);
        if (first != null && _statementStarters.contains(first)) continue;
        final m = _getter.firstMatch(l) ?? _method.firstMatch(l);
        final fm = m == null ? _field.firstMatch(l) : null;
        if (m == null && fm == null) continue;
        if (fm != null) fieldsSeen++;
        final name = (m ?? fm)!.group(2)!;
        if (_frameworkMembers.contains(name)) continue;
        if (classNames.contains(name)) continue;
        if (name.startsWith('_') && classNames.contains(name.substring(1))) continue;
        declared.add(name);
      }

      for (final name in declared) {
        // داخل ملفّه: مرّةٌ واحدة = سطرُ التعريف وحده.
        final own = counts[rel]?[name] ?? 0;
        if (own > 1) continue;
        // خارج ملفّه: أيُّ ذكرٍ في lib/ أو test/ يكفي.
        final elsewhere = counts.entries
            .where((e) => e.key != rel)
            .any((e) => (e.value[name] ?? 0) > 0);
        if (!elsewhere) {
          dead.add('$rel  ←  $name');
          continue;
        }
        // **وذِكرٌ ليس استعمالاً.** الفحصُ يُطابقُ الأسماءَ، فمُعرِّفٌ محلّيٌّ
        // في ملفٍّ آخرَ يَحملُ الاسمَ نفسَه يُقرأُ نداءً: `orderStatus` في
        // `admin_order_details_screen` متغيّرٌ محلّيٌّ، وكان يُحيي
        // `ZyiarahStrings.orderStatus` وهي بلا قارئ. فالمَواضعُ التي تُعَدُّ
        // استعمالاً ثلاثةٌ بعينِها: وصولُ عضوٍ (`.name`)، ونداءٌ
        // (`name(`)، وتمريرُ الدالّةِ قيمةً (`f(name)`/`k: name`).
        final hits = counts.entries
            .where((e) => e.key != rel && (e.value[name] ?? 0) > 0)
            .map((e) => e.key);
        final used = hits.any(
            (q) => mentionIsUse(_mask(File(q).readAsStringSync()), name));
        if (!used) dead.add('$rel  ←  $name  (ذِكرٌ لا استعمال)');
      }
    }

    // **أرضيّةٌ للحقولِ وحدَها.** الكاشفُ الجديدُ لو انحلَّ (نمطٌ يَضيق،
    // أو مُرشِّحُ كلماتٍ يَتّسع) لَمَرَّ الفحصُ أخضرَ على لا شيءٍ من الحقولِ
    // بينما تَبقى الدوالُّ مفحوصةً — فلا يُلاحَظ. والعددُ اليومَ ٤٢٠.
    expect(fieldsSeen, greaterThanOrEqualTo(300),
        reason: 'كاشفُ الحقولِ أعطى $fieldsSeen حقلاً — انحلَّ، '
            'والقاعدةُ عن «كلِّ دالّةٍ وجالب» بلا نصفِها.');

    expect(
      dead,
      isEmpty,
      reason: '\n\nأعضاءٌ لا يناديها شيء — لا شاشة، ولا خدمة، ولا اختبار.\n'
          'السؤال في كلٍّ منها واحد: أنُسِي توصيلُها، أم كُتبت ولم تُستعمل قطّ؟\n'
          '  • ${dead.join('\n  • ')}\n',
    );
  });

  test('«ذِكرٌ» ليس «استعمالاً» — القاعدةُ تُختبَرُ على الأشكالِ التي أعمَتها',
      () {
    // الحارسُ شفرةٌ تُختبَرُ كالشفرة، لا نيّةٌ تُقرَأ. والمصدرُ بعدَ الإصلاحِ
    // نظيفٌ (العضوانِ الميّتانِ حُذِفا)، فنجاحُ الفحصِ العامِّ أعلاه لا
    // يُبرهِنُ أنّ هذا التمييزَ يَعملُ — فيُجرَّبُ على الأشكالِ بعينِها.
    //
    // الحالةُ الحيّةُ التي كُتبَ لها: `ZyiarahStrings.orderStatus` كان يَبقى
    // حيّاً لأنّ `admin_order_details_screen` يُعلِنُ متغيّراً محلّيّاً
    // بالاسمِ نفسِه ويُقارِنُه.
    expect(
        mentionIsUse(
            "final orderStatus = (data['status'] ?? '').toString();\n"
            "if (orderStatus == 'in_progress') {}",
            'orderStatus'),
        isFalse,
        reason: 'مُعرِّفٌ محلّيٌّ يُقارَنُ ليس نداءً للجالبِ المُسمّى مثلَه');
    // ووصولُ العضوِ استعمالٌ.
    expect(mentionIsUse('Text(ZyiarahStrings.orderStatus)', 'orderStatus'),
        isTrue);
    // والنداءُ، ومعه الوسائطُ النوعيّة.
    expect(mentionIsUse(r'"${formatSar(x)} ر.س"', 'formatSar'), isTrue);
    expect(mentionIsUse('combineLatestById<PromoCoupon>(a, b)',
            'combineLatestById'),
        isTrue);
    // وتمريرُ الدالّةِ قيمةً استعمالٌ — وإلّا سَقطَ كلُّ `onPressed: _save`.
    expect(mentionIsUse('list.map(formatSar).toList()', 'formatSar'), isTrue);
    expect(mentionIsUse('ElevatedButton(onPressed: _save)', '_save'), isTrue);
    // **لكن لا من ملفٍّ يُعلِنُ الاسمَ لنفسِه** — وهي الحالةُ الثانيةُ التي
    // أحيَت `activeOrders`: مُعامَلٌ في `pdf_report_util` يُمرَّرُ قيمةً.
    expect(
        mentionIsUse('required int activeOrders,\n'
            '_buildSummaryTable(totalRevenue, activeOrders, completedOrders)',
            'activeOrders'),
        isFalse,
        reason: 'مُعامَلٌ مُسمّىً مِثلَ الجالبِ لا يُحييه');
    // ولا اسمٌ مُركَّبٌ يَحوي الاسمَ بادئةً: `nameX` ليس `name`.
    expect(mentionIsUse('ZyiarahStrings.orderStatusLabel', 'orderStatus'),
        isFalse,
        reason: 'الاحتواءُ ليس تطابُقاً — فخُّ `packageFormErrorX`');
    // **ومُستقبِلاً** — الصورةُ الرابعةُ، أضافَها توسيعُ الكاشفِ إلى الحقول:
    // `kJazanSw.longitude` كان يُقرأُ «ذِكراً لا استعمالاً» وهو استعمالٌ
    // صريحٌ في موضعَين.
    expect(mentionIsUse(r'bbox=${kJazanSw.longitude},', 'kJazanSw'), isTrue,
        reason: 'الاسمُ مُستقبِلٌ لعضوٍ — استعمال');
    // وقيمةً بعدَ `??` — أحدَ عشَرَ احتياطيّاً في محرّرِ المناطق.
    expect(
        mentionIsUse(
            "text: (data?['sofaSqmPrice'] ?? kDefaultSofaSqmPrice).toString()",
            'kDefaultSofaSqmPrice'),
        isTrue);
  });

  test('كاشفُ الحقولِ يَعضُّ — والأشكالُ التي تُشبهُه ولا تُطابِقُه', () {
    // الحارسُ شفرةٌ تُختبَرُ كالشفرة. والمصدرُ بعدَ الحذفِ نظيفٌ، فنجاحُ
    // الفحصِ العامِّ لا يُبرهِنُ أنّ هذا الكاشفَ يَرى حقلاً أصلاً.
    String? seen(String line) => _field.firstMatch(line)?.group(2);

    // ثابتٌ ساكنٌ، وحقلُ نسخةٍ، وحقلٌ عُلويٌّ — ثلاثتُها حقول.
    expect(seen("  static const String actionX = 'X';"), 'actionX');
    expect(seen('  final DateTime? subscriptionExpiry;'), 'subscriptionExpiry');
    expect(seen('const double kDefaultSofaSqmPrice = 35.0;'),
        'kDefaultSofaSqmPrice');
    expect(seen('  static const Color adminNavy = Color(0xFF1E293B);'),
        'adminNavy');

    // وما يَنتهي بفاصلةٍ منقوطةٍ وليس حقلاً: جملةٌ، ونداءٌ، واستيراد.
    // (الجملةُ يُمسِكُها مُرشِّحُ الكلماتِ لا النمطُ — فالاثنانِ شرطٌ واحد.)
    expect(_statementStarters.contains('return'), isTrue);
    expect(_statementStarters.contains('await'), isTrue);
    expect(seen('  await foo();'), isNull);
    expect(seen('  obj.method();'), isNull);
    expect(seen('  library;'), isNull);
    // ودالّةٌ ذاتُ سهمٍ ليست حقلاً (النمطُ يُسقِطُ ما بعدَه قوسٌ).
    expect(seen('  int plus(int a) => a + 1;'), isNull);
    // **و`set` ليست في المُرشِّح**: `_method` تَراها، فإقصاؤها نقصُ تغطية.
    expect(_statementStarters.contains('set'), isFalse);
  });

  test('الاستقراءُ العاريُّ يُعَدُّ ذِكراً للاسمِ لا لرمزٍ آخر', () {
    // `_mask` يُبقي الاستقراءَ العاريَ كي يُعَدَّ الاسم. ولو بدأَ صنفُ
    // المُعرِّفِ بعلامةِ الدولارِ لَصارَ الاستقراءُ رمزاً مستقلّاً، فيُقرأُ
    // الحقلُ المُستعمَلُ ميّتاً — وقد قُرئَ فعلاً عند أوّلِ توسيعٍ للحقول
    // (`moyasar_service._baseUrl`، وهو في `'DOLLAR_baseUrl/payments'`).
    final toks = _ident
        .allMatches(_mask(r"      Uri.parse('$_baseUrl/payments'),"))
        .map((m) => m.group(0)!)
        .toSet();
    expect(toks, contains('_baseUrl'));
    expect(toks.any((t) => t.startsWith(r'$')), isFalse);
  });

  test('سطحُ الدخول برقم الجوال و OTP لا يعود — الفحص العامّ أعمى عنه', () {
    // هذه الأسماء تُشبه دوالَّ حزمٍ خارجيّة، فالفحصُ العامُّ أعلاه يقرأها
    // «مستعمَلة» لو عادت. القائمةُ الصريحة هي ما يَعَضّ هنا.
    const banned = {
      '_phoneToEmail': 'تحويلُ الجوّال إلى بريدٍ وهميّ — وفيه خللُ ترتيبِ «966» والصفر',
      'signUpWithPhoneAndPassword': 'التسجيلُ بالجوّال — التطبيق يُسجّل ببريدٍ حقيقيّ',
      'signInWithPhoneAndPassword': 'الدخولُ بالجوّال — شاشةُ الدخول حقلُها البريد',
      'verifyPhoneNumber': 'إرسالُ OTP — يُشبه FirebaseAuth.verifyPhoneNumber',
      'verifyOTP': 'تأكيدُ OTP — يُشبه Moyasar.verifyOTP',
    };
    final src = _mask(File('lib/services/firebase_service.dart').readAsStringSync());
    final back = <String>[];
    banned.forEach((name, why) {
      if (RegExp('\\b$name\\b').hasMatch(src)) back.add('$name — $why');
    });
    expect(back, isEmpty,
        reason: '\n\nعاد سطحُ الدخول برقم الجوال إلى firebase_service.dart.\n'
            'إن كان الجوّال مطلوباً حقّاً فالقرارُ قرارُ المالك، وتوحيدُ تنظيف\n'
            'الرقم شرطٌ له: المُنظِّف الصحيح داخل getUserRole في نفس الملفّ.\n'
            '  • ${back.join('\n  • ')}\n');
  });

  test('إشعاراتُ الطلب خادميّة — لا تعود دوالُّ الإشعار من العميل', () {
    // `notification_triggers` قابلةٌ للكتابة من العميل، ولهذا نُقلت هذه
    // الإشعارات إلى Cloud Functions. بقاءُ أجسادها في الخدمة يُغري بإحيائها.
    const banned = [
      'notifyDriverOfAssignment',
      'notifyContractActivated',
      'notifyAdminOfNewContractRequest',
      'notifyAdminOfNewMaintenanceRequest',
      'notifyClientStoreOrderApproved',
    ];
    final src = _mask(
        File('lib/services/zyiarah_messaging_service.dart').readAsStringSync());
    final back = banned.where((n) => RegExp('\\b$n\\b').hasMatch(src)).toList();
    expect(back, isEmpty,
        reason: 'لها نظائرُ خادميّة في functions/index.js '
            '(notifyDriverOnAssignment، sendNotificationToAdminsOnNewMaintenance): $back');
  });

  test('قبول/رفض السائق لا يعود — قرارُ المالك', () {
    // «Do not reintroduce … driver accept/reject» في CLAUDE.md. أُزيل من
    // الواجهة وبقي acceptOrder حيّاً في الخدمة حتى اليوم بلا حارس.
    final src = _mask(File('lib/services/order_service.dart').readAsStringSync());
    expect(RegExp(r'\bacceptOrder\b').hasMatch(src), isFalse,
        reason: 'عاد acceptOrder — الإسنادُ مباشرٌ ولا يقبله السائق ولا يرفضه.');
  });

  // ── عمًى «اسمٌ يُشبهُ حزمةً خارجيّة»: نداءُ الحزمةِ ليس استعمالاً ───────
  //
  // الفحصُ العامُّ أعلاه يَتخطّى أيَّ عضوٍ يُذكَرُ **مرّتَين داخلَ ملفِّه**
  // (`own > 1`)، لأنّ الذكرَ الثانيَ يُفترَضُ أنّه نداءٌ حقيقيّ. وهذا يَنكسِرُ
  // حين يَكون للعضوِ اسمٌ **تَحملُه حزمةٌ خارجيّةٌ أيضاً**: فجسمُ العضوِ
  // يُنادي دالّةَ الحزمةِ بالاسمِ نفسِه، فيَصيرُ العدُّ اثنَين و«مستعمَلاً»
  // وهو ميّت. أربعةٌ سُجّلت هكذا من قبل (`updatePassword`،
  // `verifyPhoneNumber`، `verifyOTP`، `checkHourlySlotAvailability`)
  // و**عُلِّقت الحلُّ على «قوائمَ صريحةٍ»** — وهي القوائمُ أعلاه، لكنّها
  // قوائمُ **منعِ عودة** لا قوائمُ أعضاءٍ حيّةٍ تَحملُ أسماءَ حزم.
  //
  // فجاء خامسٌ: `ZyiarahCoreService.logEvent` — عدُّه داخلَ ملفِّه اثنانِ
  // (سطرُ التعريفِ + `_analytics.logEvent(` من `firebase_analytics`) وصفرٌ
  // في كلِّ المستودعِ خارجَه. حُذِف، وهذا الفحصُ هو ما يَمنعُ السادس:
  // **عضوٌ اسمُه اسمُ دالّةٍ في حزمةٍ نَستوردُها يَلزمُه نداءٌ من خارجِ
  // ملفِّ تعريفِه** — فنداءُ الحزمةِ لا يُعَدُّ استعمالاً له.
  test('اسمٌ يُشبهُ حزمةً خارجيّة: يَلزمُه نداءٌ من خارجِ ملفِّه', () {
    // لكلٍّ: الملفُّ المُعرِّف، وسببُ إدراجِه.
    const collide = <String, List<String>>{
      'logEvent': [
        'lib/services/zyiarah_core_services.dart',
        'firebase_analytics.logEvent — حُذِف 2026-10-05 بلا نداءٍ واحد',
      ],
    };
    final others = [..._dartFiles('lib'), ..._dartFiles('test')];
    for (final e in collide.entries) {
      final name = e.key;
      final owner = e.value[0];
      final why = e.value[1];
      // إمّا أن يَكون العضوُ قد حُذِف (فلا تعريفَ له)، أو له نداءٌ خارجيّ.
      final ownerSrc = File(owner).existsSync()
          ? _mask(File(owner).readAsStringSync())
          : '';
      final declared = RegExp('(?:Future<[^>]*>|void|[A-Z]\\w*|bool|int|'
              'double|String)\\s+$name\\s*\\(')
          .hasMatch(ownerSrc);
      if (!declared) continue; // محذوفٌ — لا شيءَ يُفحَص
      final used = others.any((f) {
        final rel = f.path.replaceAll(r'\', '/');
        if (rel == owner) return false;
        return RegExp('\\b$name\\s*\\(').hasMatch(_mask(f.readAsStringSync()));
      });
      expect(used, isTrue,
          reason: '$name مُعرَّفٌ في $owner بلا نداءٍ خارجيّ — '
              'والفحصُ العامُّ أعمى عنه ($why)');
    }
  });

  test('ولا عودةَ للعضوِ المحذوفِ ولا لاستيرادِه بلا مُستعمِل', () {
    final src = _mask(
        File('lib/services/zyiarah_core_services.dart').readAsStringSync());
    expect(src.contains('FirebaseAnalytics'), isFalse,
        reason: 'عادَ حقلُ التحليلاتِ بلا نداءٍ — أو وُصِّل فحدِّثِ الحارس');
    // والمضادّة: شرحُ القرارِ (والاعتمادُ الباقي) ما زال في الخامّ، لئلّا
    // يُحذَفَ الاعتمادُ لاحقاً على أنّه بلا مُستعمِل — وهو يَجمعُ تلقائيّاً.
    final raw = File('lib/services/zyiarah_core_services.dart').readAsStringSync();
    expect(raw.contains('firebase_analytics'), isTrue,
        reason: 'اختفى شرحُ بقاءِ الاعتمادِ — فيُحذَفُ بلا علمٍ بأنّه يَجمع');
    expect(File('pubspec.yaml').readAsStringSync().contains('firebase_analytics'),
        isTrue,
        reason: 'أُسقِطَ الاعتماد — قرارٌ تجاريٌّ يُغيّرُ ما يُجمَع، '
            'ويَستلزمُ تحديثَ PrivacyInfo.xcprivacy معه');
  });
}
