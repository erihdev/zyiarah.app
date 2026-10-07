// حارسٌ دائم: **مرآةٌ مُعلَنةٌ لها فحصٌ على جهتِها.**
//
// `admin_panel/src/utils/*.ts` تُعلِنُ بعضُها أنّها **مرآةُ** ملفٍّ دارتيّ،
// و«مرآةٌ» ليست وصفاً بل عقداً: القرارُ واحدٌ والصياغةُ تَختلفُ باللغة. ولا
// شيءَ في TypeScript يَكسِرُ حين يَتغيّرُ الأصلُ الدارتيّ — فالعقدُ لا
// يَحمِيه إلّا فحص.
//
// **ومرآةٌ بلا فحصٍ على جهتِها تُترَكُ لحارسِ دارت وحدَه، وهو يَقرأُ نصّاً لا
// سلوكاً (2026-10-07).** `driverActivation.ts` كان كذلك: حارسُ المرآةِ
// يُثبّتُ **حِمْلَي الكتابةِ** حرفيّاً ولا يَمَسُّ `driverIsDisabled`. فاختبارُ
// قضمٍ ضيَّقَ القاعدةَ إلى `d.is_active === false` **فمرَّ أخضرَ**: مجموعةُ
// دارت، و`tsc`، وفحوصُ اللوحةِ (٢٣٩) — كلُّها خضراء. والعطلُ الذي وُجدت
// المرآةُ لمنعِه (سائقٌ عطَّلَه المالكُ يُقرأُ «متاح» في اللوحة) كان يَعودُ
// بسطرٍ واحد. والمقارنةُ على **الحِمْلِ لا على القدرة** هي العمى المسجَّلُ هنا
// مرّاتٍ.
//
// فالنطاقُ **مُشتَقٌّ** من المجلّد: كلُّ ملفٍّ يُعلِنُ نفسَه مرآةً يَجبُ أن
// يَكونَ له `*.test.ts` يُنادي ما يُصدِّره — ومَن لا، يُعلَّلُ بالاسم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// كلُّ `admin_panel/src/utils/*.ts` (غيرَ ملفّاتِ الفحص) يُعلِنُ نفسَه مرآة.
List<String> _declaredMirrors() {
  final out = <String>[];
  for (final f in Directory('admin_panel/src/utils')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ts') && !f.path.endsWith('.test.ts'))) {
    final src = f.readAsStringSync();
    // **الإعلانُ وحدَه هو الشرط.** أوّلُ صياغةٍ طلبت معه أن يُسمّي الملفُّ
    // مساراً دارتيّاً — فأخرجت `staffStatus.ts` (نظيرُه `firestore.rules`
    // و`user_provider`) و`couponExpiry.ts` (نظيرُه `functions/coupons.js`)
    // من المسحِ **بصمت**، فمرَّ اختبارا قضمٍ أخضرَين على ملفٍّ خارجَ النطاق.
    // أي أنّ الحارسَ ضيَّقَ نطاقَ نفسِه — وهو العطلُ الذي وُجدَ لمنعِه.
    if (src.contains('مرآة') || RegExp(r'[Mm]irror').hasMatch(src)) {
      out.add(f.path);
    }
  }
  out.sort();
  return out;
}

/// الأسماءُ التي يُصدِّرُها الملفّ.
List<String> _exports(String src) => RegExp(
        r'export\s+(?:async\s+)?(?:function|const|class)\s+(\w+)')
    .allMatches(src)
    .map((m) => m.group(1)!)
    .toList();

/// هل الاسمُ المُصدَّرُ **قابلٌ للنداء**؟ (`function`/`class`/سهمٌ)
///
/// التمييزُ لازم: `STORE_NEEDS_ACTION_STATUSES` مجموعةٌ لا دالّة، فـ`name(`
/// لا يُطابقُها أبداً — وطلبُ النداءِ منها يَجعلُ الحارسَ يَسقطُ على شفرةٍ
/// سليمة (وقد سقط).
///
/// وأوّلُ صياغةٍ كتبت النمطَ بنصٍّ مُفلَّتٍ (`'…\\s+\$n\\b'`) فلم يُستبدَلِ
/// الاسمُ أصلاً — فكانت الدالّةُ **كاذبةً أبداً**، فيُعامَلُ كلُّ مُصدَّرٍ
/// قيمةً ويَصيرُ الفحصُ أرخى مِمّا قُصِد. والمُحلِّلُ هو مَن قالَها
/// («المتغيّرُ `n` غيرُ مستعمَل») — فالبناءُ بالضمِّ لا بالاستبدال.
bool _isCallable(String src, String name) {
  final n = RegExp.escape(name);
  return RegExp(r'export\s+(?:async\s+)?(?:function|class)\s+' + n + r'\b')
          .hasMatch(src) ||
      RegExp(r'export\s+const\s+' + n +
              r'\s*(?::[^=]*)?=\s*(?:async\s*)?\(')
          .hasMatch(src);
}


/// الأسماءُ التي تَستورِدُها **صفحاتُ اللوحةِ ومكوّناتُها** من هذه المرآة —
/// أي سطحُها المُعتمَدُ عليه فعلاً.
Set<String> _importedFrom(String mirrorPath, List<String> exported) {
  final stem = mirrorPath.split('/').last.replaceFirst('.ts', '');
  final used = <String>{};
  for (final dir in const [
    'admin_panel/src/pages',
    'admin_panel/src/components',
    'admin_panel/src/utils',
    'admin_panel/src/config',
  ]) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>().where((f) =>
        (f.path.endsWith('.ts') || f.path.endsWith('.tsx')) &&
        !f.path.endsWith('.test.ts') &&
        !f.path.endsWith('.test.tsx') &&
        !f.path.endsWith('/$stem.ts'))) {
      final src = f.readAsStringSync();
      // **المُحدِّدُ يَحملُ الامتدادَ في بعضِ المواضعِ ولا يَحملُه في غيرِها**
      // (`'../utils/staffStatus.ts'` مقابلَ `'../utils/orderActivity'`)، وأوّلُ
      // صياغةٍ طلبتِ المجرَّدَ وحدَه — فعادت مجموعةُ `staffStatus` **فارغةً**
      // وسقطَ الفحصُ إلى فرعِه الأرخى، فمرَّ اختبارُ قضمٍ أخضرَ.
      for (final m in RegExp(r"import\s*\{([^}]*)\}\s*from\s*'[^']*/" +
              stem + r"(?:\.tsx?)?'")
          .allMatches(src)) {
        for (final part in m.group(1)!.split(',')) {
          var n = part.trim().split(RegExp(r'\s+as\s+')).first.trim();
          // `import { x, type Y }` — الأنواعُ تُحذَفُ عند الترجمةِ فلا تُشغَّل.
          if (n.startsWith('type ')) continue;
          if (exported.contains(n)) used.add(n);
        }
      }
    }
  }
  return used;
}

void main() {
  group('كلُّ مرآةٍ لها فحصٌ على جهتِها', () {
    test('(أ) المسحُ يَجدُ المرايا فعلاً', () {
      final mirrors = _declaredMirrors();
      expect(mirrors.length, greaterThanOrEqualTo(12),
          reason: 'انهارَ المسح: ${mirrors.length} مرآة — '
              'حارسٌ لا يَجدُ شيئاً أسوأُ من لا حارس');
      // ومرجعٌ حقيقيٌّ: مرآةٌ معروفةٌ يَجبُ أن تَكونَ في النتيجة.
      expect(mirrors, contains('admin_panel/src/utils/driverActivation.ts'));
      expect(mirrors, contains('admin_panel/src/utils/serviceMeta.ts'));
    });

    test('(ب) ولكلٍّ فحصٌ يُنادي ما تُصدِّره', () {
      // مُعلَّلٌ واحداً واحداً — ولا يُضافُ إلّا بسببٍ مكتوب.
      // **القائمةُ فارغةٌ عمداً، وقد عضَّ الحارسُ عليها في أوّلِ تشغيل:**
      // أدرجتُ `couponExpiry.ts` مُستثنىً وله فحصٌ على جهتِه فعلاً، فسقطَ
      // الفحصُ على استثناءٍ **بائت**. ومقارنةُ المجموعةِ كاملةً هي ما يَمنعُ
      // قائمةً تَتعفّنُ: استثناءٌ لم يَعُدْ لازماً يُسقِطُ الحارسَ كما يُسقِطُه
      // نقصٌ جديد.
      const exempt = <String, String>{};
      final missing = <String>[];
      for (final m in _declaredMirrors()) {
        final t = m.replaceFirst('.ts', '.test.ts');
        if (!File(t).existsSync()) {
          missing.add(m);
          continue;
        }
        // **سطرُ الاستيرادِ في الفحصِ نفسِه يُرضي أيَّ فحصِ إشارةٍ** — فيُحجَبُ
        // قبلَ المسح، وإلّا كان وجودُ الاسمِ في `import {…}` «استعمالاً».
        // (قضمٌ عطّلَ `_isCallable` فصارَ كلُّ مُصدَّرٍ قيمةً، ومرَّ أخضرَ
        // على سطرِ الاستيرادِ وحدَه.)
        final src = _read(t)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('import '))
            .join('\n');
        final names = _exports(_read(m));
        expect(names, isNotEmpty, reason: '$m بلا تصدير — انهارَ الاستخراج');
        // **قدرةٌ لا وجود، و«أيُّ اسمٍ» ليست قدرة:** أوّلُ صياغةٍ طلبت أن
        // يُناديَ الفحصُ **اسماً واحداً** من المُصدَّر، فمرَّ اختبارُ قضمٍ
        // أعادَ تسميةَ ما يُنادِيه فحصُ `staffStatus` **أخضرَ** لأنّ اسماً
        // ثالثاً بقيَ منادىً. فالمشدودُ الآن **ما تَعتمدُ عليه اللوحةُ فعلاً**:
        // كلُّ اسمٍ تَستورِدُه الصفحاتُ أو المكوّناتُ من هذه المرآةِ يَجبُ أن
        // يُشغَّلَ في فحصِها — فما تُبنى عليه الواجهةُ مُختبَرٌ، ولا عتبةَ
        // عدديّةً (والعتباتُ لا تَعضُّ، درسٌ مسجَّلٌ هنا مرّاتٍ).
        final mirrorSrc = _read(m);
        final used = _importedFrom(m, names);
        for (final n in used) {
          final callable = _isCallable(mirrorSrc, n);
          final pat = callable
              ? RegExp(r'\b' + RegExp.escape(n) + r'\s*\(')
              : RegExp(r'\b' + RegExp.escape(n) + r'\b');
          expect(pat.hasMatch(src), isTrue,
              reason: '$t لا ${callable ? "يُشغّلُ" : "يَقرأُ"} `$n` '
                  'واللوحةُ تَستورِدُه — ملفُّ فحصٍ لا يُشغّلُ ما يُعتمَدُ '
                  'عليه حارسٌ أجوف');
        }
        // ومرآةٌ لا تَستورِدُها اللوحةُ بعدُ: يَكفي أن يُشغّلَ فحصُها اسماً.
        if (used.isEmpty) {
          expect(
              names.any((n) => RegExp(r'\b' + RegExp.escape(n) + r'\s*\(')
                  .hasMatch(src)),
              isTrue,
              reason: '$t لا يُنادي أيّاً من ${names.join(", ")}');
        }
      }
      expect(missing.toSet(), exempt.keys.toSet(),
          reason: 'مرآةٌ مُعلَنةٌ بلا فحصٍ على جهتِها: حارسُ دارت يَقرأُ '
              'نصَّها لا سلوكَها، فتضييقُ قاعدتِها يَمُرُّ أخضرَ — وقد مرَّ. '
              'أضِفْ `*.test.ts` يُنادي القاعدةَ، أو عَلِّلْ الاستثناء.');
    });

    test('(ج) ومُصنِّفُ «قابلٌ للنداء» يَعضُّ — فحصٌ على الحارسِ نفسِه', () {
      // **لازمٌ لأنّ خللَه لا يُرى في أيِّ فحصٍ آخر:** لو عادَ `false`
      // أبداً لعُومِلَ كلُّ مُصدَّرٍ **قيمةً**، فيُطلَبُ ذكرُ الاسمِ لا
      // نداؤه — وذاك أرخى، ويُرضيه نداءٌ قائمٌ أصلاً. فمرَّ اختبارُ قضمٍ
      // عطَّلَه **أخضرَ**: الحارسُ يُضعَفُ بلا أن يَسقط. والعلاجُ فحصُ
      // المُصنِّفِ على حالتَين معروفتَين — الحارسُ شفرةٌ تُختبَرُ كالشفرة.
      final zs = _read('admin_panel/src/utils/zoneSchedule.ts');
      expect(_isCallable(zs, 'DAY_NAMES'), isFalse,
          reason: 'مجموعةٌ لا دالّة — طلبُ النداءِ منها يُسقِطُ شفرةً سليمة');
      expect(_isCallable(zs, 'formatHour12'), isTrue,
          reason: 'سهمٌ مُصدَّرٌ — نداءٌ لا إشارة');
      final ch = _read('admin_panel/src/utils/contractHealth.ts');
      expect(_isCallable(ch, 'contractHealthReason'), isTrue,
          reason: '`export function` — نداءٌ لا إشارة');
      final oa = _read('admin_panel/src/utils/orderActivity.ts');
      expect(_isCallable(oa, 'STORE_NEEDS_ACTION_STATUSES'), isFalse);
    });

    test('(د) وكلُّ مرآةٍ تُسمّي نظيرَها — فالدعوى قابلةُ التحقّق', () {
      // «مرآةٌ» بلا نظيرٍ مُسمّىً دعوى لا تُفحَص. والنظيرُ ليس دارتيّاً
      // بالضرورة: `staffStatus` يُقابلُ `firestore.rules` و`user_provider`،
      // و`couponExpiry` يُقابلُ `functions/coupons.js`.
      final anchor = RegExp(r'lib/[\w/]+\.dart|functions/[\w/]+\.js|'
          r'firestore\.rules|[a-z_]+\.dart\b');
      for (final m in _declaredMirrors()) {
        expect(anchor.hasMatch(_read(m)), isTrue,
            reason: '$m يُعلِنُ نفسَه مرآةً ولا يُسمّي نظيرَه');
      }
    });

    test('(ه) ومرآةُ تعطيلِ السائقِ تُشغّلُ قاعدتَها بجدولٍ مشترَك', () {
      // الموضعُ الذي أثبتَ القضمُ أنّه كان مكشوفاً — فيُشَدُّ صريحاً لا
      // بالاشتقاقِ وحدَه.
      final t = _read('admin_panel/src/utils/driverActivation.test.ts');
      expect(t.contains('// ⟦CASES⟧'), isTrue);
      expect(t.contains('// ⟦/CASES⟧'), isTrue);
      expect(RegExp(r'\bdriverIsDisabled\s*\(').hasMatch(t), isTrue);
      // والجدولُ يُقرَأُ من جهةِ دارت كذلك — وإلّا فهو جدولانِ لا جدول.
      expect(_read('test/driver_activation_test.dart'),
          contains('driverActivation.test.ts'));
    });
  });
}
