import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/upload_content_type.dart';

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
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
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
