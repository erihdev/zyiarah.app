import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/upload_content_type.dart';
import 'helpers/sources_in.dart';

/// **مخزنُ المشروعِ كان مفتوحاً لأيِّ عميلةٍ مسجَّلة (2026-10-05).**
///
/// `storage.rules` قالت لكلِّ مسارِ رفعٍ `allow write/delete: if
/// request.auth != null` — بلا نوعِ محتوًى، وبلا تمييزِ إنشاءٍ من استبدال،
/// وبلا ملكيّة. فثلاثُ ثغراتٍ لأيِّ مسجَّل:
///
///   ١) **استضافةٌ مجّانيّةٌ لأيِّ ملفّ**: `banners/` و`products/` و
///      `worker_photos/` قراءتُها **عامّة** (`allow read: if true`)، فرفعُ
///      صفحةِ تصيّدٍ أو برمجيّةٍ خبيثةٍ يُنتجُ رابطاً على نطاقِ جوجل مربوطاً
///      بدلوِ الشركة — وكلفةُ تخزينٍ وخروجٍ على فاتورةِ المالك.
///   ٢) **تشويهُ المتجر**: المسارُ `{file=**}` بلا ملكيّة، فاستبدالُ صورةِ
///      منتجٍ أو بنرٍ قائمٍ يُعرَضُ **لكلِّ العملاء** بلا أيِّ إجراءٍ إداريّ.
///   ٣) **حذفُ كلِّ صورةِ بنرٍ ومنتجٍ** في المتجر بسطرٍ واحد.
///
/// والقواعدُ **لا تَستطيعُ قراءةَ Firestore**، فلا سبيلَ فيها إلى معرفةِ
/// الدور، والمشروعُ لا يَضبطُ «custom claims». فالمخرجُ: إنشاءٌ فقط + نوعٌ
/// محصورٌ، والحذفُ خادميٌّ بـ`deleteStorageObject` (+`_assertAdmin`) — نفسُ
/// نمطِ `deleteDriverAccount`.
///
/// **تنبيهُ نشر**: `storage.rules` ليست في أيِّ Workflow، فهي كـ
/// `firestore.rules` — نشرٌ يدويٌّ بعدَ وصولِ النسخةِ الجديدةِ من التطبيقِ
/// (الدالّةُ تُنشَرُ آليّاً على `main`، والشاشاتُ تَصلُ مع البناءِ التالي).
void main() {
  String read(String p) => File(p).readAsStringSync();
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('نوعُ المحتوى يُشتَقُّ من الامتداد', () {
    test('الأنواعُ المعروفة', () {
      expect(imageContentTypeFor('a.png'), 'image/png');
      expect(imageContentTypeFor('A.PNG'), 'image/png');
      expect(imageContentTypeFor('b.webp'), 'image/webp');
      expect(imageContentTypeFor('c.gif'), 'image/gif');
      expect(imageContentTypeFor('d.heic'), 'image/heic');
      expect(imageContentTypeFor('e.heif'), 'image/heic');
    });

    test('وما سواها jpeg — والمهمُّ أنّه `image/`', () {
      for (final n in ['x.jpg', 'x.jpeg', 'x', 'x.bin', '']) {
        expect(imageContentTypeFor(n).startsWith('image/'), isTrue,
            reason: '$n لا يُنتجُ نوعَ صورةٍ — فالقاعدةُ تَرفضُ الرفع');
      }
      expect(imageContentTypeFor('x.bin'), 'image/jpeg');
    });
  });

  group('قواعدُ المخزن', () {
    final String rules = codeOnly('storage.rules');

    /// جسمُ كتلةِ `match` بموازنةِ الأقواس.
    ///
    /// **لا `indexOf('}')`**: سطرُ العنوانِ نفسُه يَحملُ `}` داخلَ
    /// `{file=**}`، فأوّلُ قوسِ إغلاقٍ هو ذاك لا نهايةُ الكتلة — وقعت فيها
    /// أوّلُ صياغةٍ لهذا الحارس، وهو نفسُ فخِّ `indexOf('[')` المسجَّلِ هنا.
    String block(String path) {
      final int at = rules.indexOf('match /$path/{file=**}');
      expect(at, greaterThan(-1), reason: '$path اختفى من القواعد');
      final int eol = rules.indexOf('\n', at);
      final int open = rules.lastIndexOf('{', eol);
      int depth = 0;
      for (int i = open; i < rules.length; i++) {
        if (rules[i] == '{') depth++;
        if (rules[i] == '}') {
          depth--;
          if (depth == 0) return rules.substring(open, i);
        }
      }
      fail('كتلةُ $path غير مغلقة');
    }

    test('البنرات والمنتجات والعاملات: إنشاءٌ فقط ولا استبدالَ ولا حذف', () {
      for (final m in ['banners', 'products', 'worker_photos']) {
        final b = block(m);
        expect(b.contains('allow create: if request.auth != null'), isTrue,
            reason: '$m: الإنشاءُ وحدَه هو المسموح');
        expect(b.contains('allow write:'), isFalse,
            reason: '$m: `write` تَشملُ الاستبدالَ والحذفَ معاً');
        expect(b.contains('allow update, delete: if false;'), isTrue,
            reason: '$m: الاستبدالُ هو تشويهُ المتجر، والحذفُ مسحُه');
        expect(b.contains("contentType.matches('image/.*')"), isTrue,
            reason: '$m: بلا حصرِ النوعِ يَصيرُ المخزنُ استضافةً لأيِّ ملف');
      }
    });

    test('إثباتُ الإكمال: صورةٌ تُنشَأُ ولا تُستبدَلُ ولا تُحذَف', () {
      final b = block('order_feedback');
      expect(b.contains('allow create:'), isTrue);
      expect(b.contains('allow update, delete: if false;'), isTrue);
      expect(b.contains("contentType.matches('image/.*')"), isTrue);
    });

    test('الفواتير: إنشاءٌ وتحديثٌ (إعادةُ التوليد) ولا حذفَ، وPDF فقط', () {
      final b = block('invoices');
      // **`create, update` لا `write`**: `write` في قواعدِ المخزنِ تَشملُ
      // الحذفَ، وقواعدُ السماحِ تُجمَعُ بـOR — فـ`allow delete: if false`
      // بعدَها لا يَسحبُ شيئاً. (وقعت فيها أوّلُ صياغةٍ لهذا التشديد.)
      expect(b.contains('allow create, update: if request.auth != null'),
          isTrue,
          reason: 'إعادةُ توليدِ الفاتورةِ تَستبدلُ نفسَ الكائنِ عمداً');
      expect(b.contains('allow write:'), isFalse,
          reason: '`write` تُعيدُ منحَ الحذفِ فتُبطِلُ السطرَ الذي يَمنعُه');
      expect(b.contains('allow delete: if false;'), isTrue,
          reason: 'الفاتورةُ مستندٌ ضريبيّ');
      expect(b.contains("contentType == 'application/pdf'"), isTrue);
    });

    test('وما عدا المسارات المعروفة ممنوع', () {
      expect(rules.contains('match /{allPaths=**}'), isTrue);
      expect(rules.contains('allow read, write: if false;'), isTrue);
    });
  });

  group('مواضعُ الرفعِ تُصرّحُ بالنوع', () {
    // `putData` بلا بياناتٍ وصفيّةٍ يَرفعُ `application/octet-stream`
    // (بخلافِ `putFile` الذي يَستنبطُ من الامتداد) — فبلا هذا التصريحِ
    // تَرفضُ القاعدةُ الجديدةُ الرفعَ، والتشديدُ يَصيرُ عطلاً.
    test('الأربعةُ كلُّها', () {
      for (final f in [
        'lib/screens/admin/admin_banners_screen.dart',
        'lib/screens/admin/admin_store_screen.dart',
        'lib/services/firebase_service.dart',
        'lib/services/order_service.dart',
      ]) {
        final src = codeOnly(f);
        expect(src.contains('imageContentTypeFor('), isTrue,
            reason: '$f يَرفعُ بلا نوعٍ — القاعدةُ تَرفضُه');
      }
    });

    test('والفاتورةُ كانت تُصرّحُ أصلاً', () {
      expect(
          codeOnly('lib/services/zyiarah_pdf_service.dart')
              .contains("SettableMetadata(contentType: 'application/pdf')"),
          isTrue);
    });

    test('ولا رفعَ بلا بياناتٍ وصفيّةٍ في أيِّ موضعٍ تَحرسُه القاعدة', () {
      // المسحُ مُشتَقّ: أيُّ `putData(` أو `putFile(` بوسيطٍ واحدٍ فقط.
      final List<String> bare = [];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        final src = codeOnly(f.path);
        for (final m
            in RegExp(r'put(?:Data|File)\(').allMatches(src)) {
          // نوازِنُ الأقواسَ لنقرأَ الوسائطَ كاملةً (لا نمطٌ غيرُ شَرِه:
          // أسقطَ مثلُه حارسَين في هذا المستودع).
          int depth = 0;
          int end = m.end;
          for (int i = m.end - 1; i < src.length; i++) {
            if (src[i] == '(') depth++;
            if (src[i] == ')') {
              depth--;
              if (depth == 0) {
                end = i;
                break;
              }
            }
          }
          final args = src.substring(m.end, end);
          if (!args.contains('SettableMetadata')) {
            bare.add('${f.path}: $args');
          }
        }
      }
      expect(bare, isEmpty,
          reason: 'رفعٌ بلا نوعِ محتوًى — ترفضُه قاعدةُ المخزنِ بصمتٍ من '
              'منظورِ المستخدم');
    });
  });

  // ═══ كلُّ مسارِ رفعٍ مُغطّىً — نطاقٌ مُشتَقٌّ من المستودعِ كلِّه ═══
  //
  // **ترويسةُ `storage.rules` تَقولُ عن نفسِها «تغطّي كل مسارات الرفع في
  // التطبيق» — وكانت دعوى بلا قارئ، وكاذبةً.** اللوحةُ كانت تَرفعُ صورةَ
  // السائقِ إلى `drivers/{id}/photo.jpg`: مسارٌ لا يُطابِقُ أيَّ كتلةِ
  // `match`، فيَقعُ على الشاملةِ في آخرِ الملفِّ (`allow read, write: if
  // false`). فنشرُ القواعدِ — وهو إجراءٌ بشريٌّ مُعلَّقٌ — كان يَمنعُ الرفعَ
  // من اللوحةِ **من أوّلِ مرّة**، لا عند الاستبدالِ وحدَه.
  //
  // والفحوصُ أعلاه تَقرأُ الكتلَ بأسمائها المكتوبةِ بيدٍ وتَمسحُ `lib/`
  // وحدَها — فالقاعدةُ عامّةٌ والنطاقُ ضيّقٌ، وهو النمطُ المتكرّرُ هنا.
  // فالنطاقُ هذه المرّةَ **مُشتَقٌّ من الجهتَين**: مسارٌ سادسٌ يُضافُ غداً
  // في أيِّ لغةٍ يَدخلُ الفحصَ بنفسِه.
  group('كلُّ مسارِ رفعٍ مُغطّىً بكتلةٍ تُجيزُ الإنشاء', () {
    final String rulesSrc = codeOnly('storage.rules');

    /// جسمُ كتلةِ `match` المفتوحةِ عند آخرِ `{` قبلَ نهايةِ سطرِ [at] —
    /// بموازنةِ الأقواس. (`indexOf('}')` يَقعُ على `}` داخلَ `{file=**}`.)
    String bodyAt(int at) {
      final int eol = rulesSrc.indexOf('\n', at);
      final int open = rulesSrc.lastIndexOf('{', eol);
      int depth = 0;
      for (int i = open; i < rulesSrc.length; i++) {
        if (rulesSrc[i] == '{') depth++;
        if (rulesSrc[i] == '}') {
          depth--;
          if (depth == 0) return rulesSrc.substring(open, i);
        }
      }
      fail('كتلةٌ غيرُ مغلقةٍ عند $at');
    }

    /// الوسائطُ الكاملةُ لنداءٍ يَبدأُ عند [start] — بموازنةِ الأقواسِ لا
    /// بنمطٍ غيرِ شَرِه (أسقطَ مثلُه حارسَين في هذا المستودع).
    String callArgs(String src, int start) {
      final int open = src.indexOf('(', start);
      int depth = 0;
      for (int i = open; i < src.length; i++) {
        if (src[i] == '(') depth++;
        if (src[i] == ')') {
          depth--;
          if (depth == 0) return src.substring(open + 1, i);
        }
      }
      return '';
    }

    final Map<String, List<String>> sites = {};
    void addSite(String path, String file, String expr) {
      final String prefix = path.split('/').first.split('\$').first;
      sites.putIfAbsent(prefix, () => <String>[]).add('$file :: $expr');
    }

    // دارت: `.child('...')` أو `.child(ident)` بحلِّ الثابتِ المحلّيّ —
    // `admin_store_screen` يَكتبُ `final fileName = 'products/…'` ثمّ
    // `.child(fileName)`، وهو فخُّ «مفتاحٌ مكتوبٌ كثابت» المسجَّلُ هنا.
    for (final f in sourcesIn('lib', atLeast: 100)) {
      final String src = codeOnly(f.path);
      if (!src.contains('FirebaseStorage')) continue;
      for (final m in RegExp(r'\.child\(').allMatches(src)) {
        final String arg = callArgs(src, m.start).trim();
        final RegExpMatch? lit = RegExp("^'([^']*)'").firstMatch(arg);
        if (lit != null) {
          addSite(lit.group(1)!, f.path, arg);
          continue;
        }
        if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(arg)) continue;
        final RegExpMatch? decl = RegExp(
                r"\b(?:final|const|var)\s+(?:String\s+)?"
                "${RegExp.escape(arg)}"
                r"\s*=\s*'([^']*)'")
            .firstMatch(src);
        if (decl == null) {
          throw StateError('${f.path}: `.child($arg)` لم يُحَلَّ إلى مسارٍ '
              '— فالتغطيةُ غيرُ مقروءة، وتجاهلُه صمت');
        }
        addSite(decl.group(1)!, f.path, '$arg = ${decl.group(1)}');
      }
    }
    // اللوحة: ref(storage, `...`)
    for (final f in sourcesIn('admin_panel/src',
            atLeast: 20, exts: const ['.tsx', '.ts'])
        .where((f) => !f.path.contains('.test.'))) {
      final String src = f.readAsStringSync();
      for (final m in RegExp(r'ref\(\s*storage\s*,').allMatches(src)) {
        final String arg = callArgs(src, m.start);
        // أوّلُ علامةِ اقتباسٍ **بعدَ** `storage,` — لا في بدايةِ الوسائط.
        final RegExpMatch? lit =
            RegExp('[`\'"]([^`\'"]*)').firstMatch(arg);
        if (lit == null) {
          throw StateError('${f.path}: مسارُ رفعٍ غيرُ حرفيٍّ — غيرُ مقروءٍ '
              'للفحص');
        }
        addSite(lit.group(1)!, f.path, arg.trim());
      }
    }

    /// البادئاتُ التي تُجيزُ كتلتُها الإنشاء.
    final Set<String> creatable = () {
      final Set<String> out = {};
      for (final m in RegExp(r'match\s+/([^/{\s]+)/\{[^}]*\}\s*\{')
          .allMatches(rulesSrc)) {
        final String body = bodyAt(m.start);
        final bool ok = RegExp(r'allow\s+([a-z,\s]+):\s*if\s+([^;]+);')
            .allMatches(body)
            .any((a) =>
                (a.group(1)!.contains('create') ||
                    a.group(1)!.contains('write')) &&
                !a.group(2)!.contains('false'));
        if (ok) out.add(m.group(1)!);
      }
      return out;
    }();

    test('(أ) الاشتقاقُ أصابَ الجهتَين — حارسٌ عقيمٌ أسوأُ من لا حارس', () {
      expect(sites.length, greaterThanOrEqualTo(5),
          reason: 'كاشفُ مواضعِ الرفعِ انحلّ (${sites.length} بادئة)');
      expect(creatable.length, greaterThanOrEqualTo(5),
          reason: 'قارئُ كتلِ القواعدِ انحلّ ($creatable)');
      expect(sites['banners']?.join(), contains('admin_banners_screen.dart'));
      // والمِرساةُ هنا **غيرُ مرتبطةٍ ببادئةٍ بعينِها**: لو شُدَّت إلى
      // `worker_photos` لصارت تَقيسُ الإصلاحَ لا الاشتقاقَ، فتَسقطُ مع (ب)
      // على المسارِ نفسِه بدلَ أن تُميّزَ «القارئُ انحلّ» من «مسارٌ خرجَ».
      expect(sites.values.expand((v) => v).where((v) => v.contains('.tsx')),
          isNotEmpty,
          reason: 'رفعُ اللوحةِ لم يُقرَأ — فالتغطيةُ لا تَشملُ الجهةَ التي '
              'كان العطلُ فيها');
    });

    test('(ب) لا بادئةَ رفعٍ خارجَ القواعد', () {
      final List<String> uncovered = sites.keys
          .where((k) => !creatable.contains(k))
          .map((k) => '$k (${sites[k]!.join("; ")})')
          .toList()
        ..sort();
      expect(uncovered, isEmpty,
          reason: 'مسارُ رفعٍ يَقعُ على الشاملةِ `if false` — فنشرُ القواعدِ '
              'يَمنعُه من أوّلِ مرّة: ${uncovered.join(" | ")}');
    });

    test('(ج) والقارئُ يَعضّ: بادئةٌ غيرُ مُعلَنةٍ تُقرأُ غيرَ مُغطّاة', () {
      // المصدرُ نظيفٌ بعد الإصلاح، فنجاحُ (ب) وحدَه لا يُبرهِنُ أنّ القارئَ
      // يَرى شيئاً — والبادئةُ هنا هي العطلُ الذي وُجد الفحصُ له.
      expect(creatable.contains('drivers'), isFalse,
          reason: 'كتلةُ `drivers/` أُضيفت — فالتعليلُ يُراجَعُ لا يُسكَت');
      for (final k in const [
        'banners',
        'products',
        'worker_photos',
        'order_feedback',
        'invoices'
      ]) {
        expect(creatable, contains(k), reason: 'كتلةُ $k لم تُقرَأ');
      }
    });

    test('(د) واسمُ الملفِّ فريدٌ — شرطُ «إنشاءٌ بلا استبدال»', () {
      // القواعدُ تُجيزُ `create` ولا تُجيزُ `update`، فمسارٌ ثابتٌ لا
      // يُمكِنُ استبدالُه **أبداً**: تغييرُ صورةٍ يَفشلُ ولو كان المسارُ
      // مُغطّىً. ومُدخَلانِ مُعلَّلانِ لا مُتجاهَلان.
      // **والإعفاءُ بالموضعِ لا بالبادئة.** أوّلُ صياغةٍ أعفت `worker_photos`
      // كبادئةٍ — فابتلعت موضعَ اللوحةِ الواقعَ تحتَها، ومرَّ قضمٌ جعلَ
      // مسارَها ثابتاً **أخضرَ**: إعفاءٌ مفتاحُه أعمُّ من مُعلَّلِه يَأكلُ
      // القاعدةَ، وهو الدرسُ المسجَّلُ هنا.
      const Map<String, String> exempt = {
        // الفاتورةُ تَستبدلُ نفسَ الكائنِ عمداً — وكتلتُها تُجيزُ `update`.
        'lib/services/zyiarah_pdf_service.dart':
            'إعادةُ توليدِ فاتورةٍ فشلت تَكتبُ نفسَ الكائن',
        // الاسمُ يُبنى عند المُنادي (`profile_{millis}`) لا في الخدمة.
        'lib/services/firebase_service.dart':
            'الفرادةُ عند المُنادي — مشدودةٌ أدناه',
      };
      final List<String> fixed = [];
      final Set<String> usedExemptions = {};
      sites.forEach((prefix, where) {
        for (final w in where) {
          final String file = w.split(' :: ').first;
          if (exempt.containsKey(file)) {
            usedExemptions.add(file);
            continue;
          }
          if (!w.contains('millisecondsSinceEpoch') &&
              !w.contains('Date.now()')) {
            fixed.add(w);
          }
        }
      });
      // ولا إعفاءَ مَيْتاً: مُدخَلٌ لم يُطابِقْ موضعاً يُخفي اسماً زائلاً.
      expect(usedExemptions, exempt.keys.toSet(),
          reason: 'إعفاءٌ لا موضعَ له: '
              '${exempt.keys.toSet().difference(usedExemptions)}');
      expect(fixed, isEmpty,
          reason: 'مسارُ رفعٍ باسمٍ ثابتٍ — لا يُستبدَلُ أبداً تحتَ '
              '«إنشاءٌ فقط»: ${fixed.join(" | ")}');
      // وشاهدُ الإعفاءِ الثاني: المُنادي يُولّدُ اسماً فريداً فعلاً.
      expect(
          codeOnly('lib/screens/admin/admin_drivers_screen.dart')
              .contains('profile_\${DateTime.now().millisecondsSinceEpoch}'),
          isTrue,
          reason: 'اسمُ صورةِ السائقِ في تطبيقِ الإدارةِ لم يَعُدْ فريداً — '
              'فإعفاءُ `worker_photos` يُراجَع');
      // والفاتورةُ ما زالت الوحيدةَ التي تُجيزُ كتلتُها `update`.
      expect(bodyAt(rulesSrc.indexOf('match /invoices/')).contains('create, update'),
          isTrue,
          reason: 'كتلةُ الفواتيرِ لم تَعُدْ تُجيزُ الاستبدالَ — فإعفاؤها '
              'يُراجَع');
    });

    test('(هـ) ورفعُ اللوحةِ يُصرّحُ بالنوعِ ويُسوّي وعدَه عند الفشل', () {
      final String d =
          File('admin_panel/src/pages/Drivers.tsx').readAsStringSync();
      // النوعُ: نظيرُ `imageContentTypeFor` في الجهةِ الأخرى — بلاهُ تَرفضُ
      // القاعدةُ الرفعَ (`image/.*`)، و`uploadBytesResumable` بلا بياناتٍ
      // وصفيّةٍ يَتّكِلُ على `File.type` وحدَه.
      expect(d.contains('contentType: file.type'), isTrue,
          reason: 'رفعُ اللوحةِ بلا نوعِ محتوًى — ترفضُه القاعدة');
      // والتسوية: كان جسمُ الإكمالِ `async` بلا `try`، فرميُ
      // `getDownloadURL`/`updateDoc` يَترُكُ الوعدَ بلا `resolve` ولا
      // `reject` — فـ`handlePhotoChange` يَنتظرُ إلى الأبد، و`finally` لا
      // يَعملُ، ونَفْشةُ «فشل رفع الصورة» المكتوبةُ هناك **غيرُ قابلةِ
      // الوصول**.
      final int i = d.indexOf('const uploadPhoto');
      expect(i, greaterThan(0));
      final String body = d.substring(i, d.indexOf('const handlePhotoChange'));
      expect(RegExp(r'catch\s*\([^)]*\)\s*\{[^}]*reject\(').hasMatch(body),
          isTrue,
          reason: 'رفعُ اللوحةِ لا يُسوّي وعدَه عند الفشل — فالدوّارةُ لا '
              'تَنتهي والنَفْشةُ لا تُعرَضُ أبداً');
      expect(d.contains('فشل رفع الصورة'), isTrue,
          reason: 'نَفْشةُ الفشلِ زالت — فتعليلُ التسويةِ يُراجَع');
    });
  });

  group('الحذفُ خادميٌّ لا عميليّ', () {
    test('الشاشتانِ تُنادِيانِ الدالّةَ ولا تَحذفانِ مباشرةً', () {
      for (final f in [
        'lib/screens/admin/admin_banners_screen.dart',
        'lib/screens/admin/admin_store_screen.dart',
      ]) {
        final src = codeOnly(f);
        expect(src.contains("httpsCallable('deleteStorageObject')"), isTrue,
            reason: '$f لا يُنادي الدالّةَ — والقاعدةُ تَمنعُ الحذفَ العميليّ');
        expect(src.contains('refFromURL(imageUrl).delete()'), isFalse,
            reason: '$f عادَ إلى الحذفِ العميليِّ المرفوض');
      }
      // والمضادّة: الشكلُ القديمُ ما زال موثَّقاً في الخامّ.
      expect(read('storage.rules').contains('allow delete: if request.auth != null'),
          isTrue,
          reason: 'اختفى اقتباسُ القاعدةِ القديمةِ من التوثيق');
    });

    test('والفشلُ يُقال لا يُطبَعُ في debugPrint وحدَه', () {
      // كائنٌ معلّقٌ بلا أثرٍ هو عينُ «catch يَكتبُ سطراً ويَنسى».
      for (final f in [
        'lib/screens/admin/admin_banners_screen.dart',
        'lib/screens/admin/admin_store_screen.dart',
      ]) {
        final src = codeOnly(f);
        final i = src.indexOf("httpsCallable('deleteStorageObject')");
        final after = src.substring(i, i + 700);
        expect(after.contains('ScaffoldMessenger.of(context).showSnackBar'),
            isTrue, reason: '$f: فشلُ الحذفِ صامت');
      }
    });

    test('والدالّةُ مُصدَّرةٌ خادميّاً (وإلّا فالنداءُ not-found عند الضغط)', () {
      expect(read('functions/index.js')
          .contains('exports.deleteStorageObject'), isTrue);
    });
  });
}
