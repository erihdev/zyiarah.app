// ════════════════════════════════════════════════════════════════════════
// حفظُ الإعداداتِ: التحقّقُ قبلَ أوّلِ كتابة، والكتاباتُ دفعةٌ ذرّيّة
// (2026-10-05)
//
// `admin_settings_screen._savePricing` كان يَكتبُ أربعةَ مستنداتٍ بالتتابعِ
// **وبينها فاحِصان** يَرجعانِ بـ`return`: `main_settings` ← كتابة، ثمّ فحصُ
// السعة، ثمّ `hourly_settings` و`public_content/privacy` ← كتابة، ثمّ فحصُ
// رقمِ البناء، ثمّ `app_update` ← كتابة. فخطأٌ في صندوقٍ واحدٍ يَترُكُ ما
// سبقَه مكتوباً والأدمنُ يَقرأُ رسالةً حمراءَ فيَفهمُ أنّ الحفظَ لم يَجرِ.
//
// وأثقلُها `maintenance_mode`: هو في الكتابةِ الأولى، فتفعيلُه مع صندوقِ سعةٍ
// غيرِ صالحٍ يُقفِلُ التطبيقَ على كلِّ عميلةٍ ثمّ يُقالُ للأدمنِ إنّ الحدَّ
// اليوميَّ خاطئ. وسياسةُ الخصوصيّةِ تُكتَبُ في `main_settings` قبلَ الفحصِ
// وفي `public_content/privacy` بعدَه، فتَفترِقُ النسختانِ وتَخدمُ
// `zyiarah.com/privacy` — رابطُ App Store Connect — القديمةَ.
//
// ومحرِّرُ اللوحةِ كان يَتحقّقُ قبلَ أن يَكتب (الترتيبُ صحيحٌ هناك) لكنّه
// كان `Promise.all` لا دفعةً، فانقطاعُ الشبكةِ يُنتجُ الحالةَ الجزئيّةَ
// نفسَها. فالطرفانِ مشدودانِ هنا.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يَحجبُ أسطرَ التعليقِ بمسافاتٍ **بطولِها** فتَبقى الإزاحاتُ مطابقةً —
/// الفحوصُ هنا تُقارِنُ مواضعَ (`indexOf`) لا حضوراً، فحذفُ الأسطرِ يُزحزحُ
/// كلَّ موضعٍ بعدَها. وتعليقاتي تَقتبسُ الشكلَ القديمَ («Promise.all»،
/// «`main_settings` ← كتابة») فبلا الحجبِ يَسقطُ الفحصُ على توثيقِه نفسِه.
String _mask(String src, {String line = '//'}) => src
    .split('\n')
    .map((l) => l.trimLeft().startsWith(line) ? ' ' * l.length : l)
    .join('\n');

/// جسمُ دالّةٍ بموازنةِ الأقواس — لا `indexOf('}')`، وهو الفخُّ الذي أوقعَ
/// حُرّاساً في هذا المستودعِ ستَّ مرّات.
String _body(String src, String signature) {
  final i = src.indexOf(signature);
  if (i < 0) throw StateError('التوقيعُ اختفى: $signature');
  final open = src.indexOf('{', i + signature.length - 1);
  if (open < 0) throw StateError('لا جسمَ لـ$signature');
  var depth = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, j + 1);
    }
  }
  throw StateError('قوسٌ غيرُ مُغلَقٍ في $signature');
}

void main() {
  final dartRaw =
      File('lib/screens/admin/admin_settings_screen.dart').readAsStringSync();
  final dart = _mask(dartRaw);
  final panelRaw = File('admin_panel/src/pages/Settings.tsx').readAsStringSync();
  final panel = _mask(panelRaw);

  // الاقتطاعُ **داخلَ** كلِّ فحصٍ لا في جسمِ المجموعة: اسمٌ تغيّرَ يَرمي
  // `StateError` عند الجمعِ فيَقتلُ الملفَّ كلَّه برسالةٍ مدفونةٍ تُقرأُ «عطلُ
  // بيئةٍ» لا «حارسٌ عضَّ» — وهو ما كشفَه اختبارُ قضمٍ أعادَ تسميةَ الدالّة.
  String saveBody() => _body(dart, 'Future<void> _savePricing() async ');
  String panelSaveBody() => _body(panel, 'const handleSave = async () =>');

  group('محرِّرُ التطبيق: التحقّقُ قبلَ الكتابة', () {

    test('(أ) الاقتطاعُ أصابَ الدالّةَ فعلاً — فلا فحصَ على فراغ', () {
      expect(saveBody().length, greaterThan(800));
      for (final k in [
        'main_settings',
        'hourly_settings',
        'app_update',
        'privacy',
        'maintenance_mode',
      ]) {
        expect(saveBody().contains(k), isTrue, reason: 'الجسمُ لا يَحملُ $k');
      }
    });

    test('(ب) كلُّ `return` فاحِصٍ يَسبقُ أوّلَ كتابة', () {
      final save = saveBody();
      final firstWrite = save.indexOf('batch.set(');
      expect(firstWrite, greaterThan(0), reason: 'لا كتابةَ في الدفعة');
      // آخرُ `return;` في الجسمِ هو آخرُ فاحِصٍ — فلا `return` بعد الكتابة.
      final lastReturn = saveBody().lastIndexOf('return;');
      expect(lastReturn, greaterThan(0), reason: 'الفاحِصانِ اختفَيا');
      expect(lastReturn, lessThan(firstWrite),
          reason: 'فاحِصٌ يَرجعُ **بعد** كتابةٍ — وهو العطلُ بعينِه');
    });

    test('(ج) الفاحِصانِ المُسمّيانِ ما زالا قائمَين', () {
      expect(saveBody().contains('capacity == null || capacity < 1'), isTrue,
          reason: 'فحصُ السعةِ زال');
      expect(saveBody().contains('iosBuild == null || androidBuild == null'), isTrue,
          reason: 'فحصُ رقمِ البناءِ زال');
    });

    test('(د) الكتاباتُ الأربعُ دفعةٌ واحدةٌ بـcommit واحد', () {
      final save = saveBody();
      expect(RegExp(r'batch\.set\(').allMatches(save).length, 4,
          reason: 'عددُ الكتاباتِ في الدفعةِ ليس أربعاً');
      expect(RegExp(r'batch\.commit\(\)').allMatches(save).length, 1,
          reason: 'commit ليس واحداً — فالذرّيّةُ تَنكسِر');
      // ولا كتابةً مباشرةً خارجَ الدفعة: تلك هي الحالةُ الجزئيّةُ عائدةً.
      expect(RegExp(r"doc\('[a-z_]+'\)\s*\.set\(").hasMatch(save), isFalse,
          reason: 'كتابةٌ مباشرةٌ خارجَ الدفعةِ عادت');
    });

    test('(هـ) `maintenance_mode` و`privacy` في الدفعةِ نفسِها', () {
      // سببُ الذرّيّة: القفلُ ونشرُ السياسةِ لا يَجوزُ أن يَنفُذَ أحدُهما وحدَه.
      final iMaint = saveBody().indexOf('maintenance_mode');
      final iPriv = saveBody().indexOf("doc('privacy')");
      final iCommit = saveBody().indexOf('batch.commit()');
      expect(iMaint, greaterThan(0));
      expect(iPriv, greaterThan(0));
      expect(iMaint, lessThan(iCommit));
      expect(iPriv, lessThan(iCommit));
    });

    test('(و) المضادّة: الشكلُ القديمُ ما زال موثَّقاً في الخامّ', () {
      // حجبُ التعليقاتِ هو ما يُجعلُ (ب) و(هـ) ممكنَين، فيَلزمُ إثباتُ أنّ
      // المحجوبَ تعليقٌ لا شفرةٌ أُزيلت.
      expect(dartRaw.contains('← كتابة'), isTrue,
          reason: 'شرحُ الترتيبِ القديمِ زال — فلا يَعرفُ قارئٌ ما يَحرُسُه هذا');
    });
  });

  group('لوحةُ الويب: الترتيبُ كان صحيحاً والذرّيّةُ أُضيفت', () {

    test('(ز) الاقتطاعُ أصابَ الدالّةَ، والفاحِصانِ قبلَ الكتابة', () {
      expect(panelSaveBody().contains('loadFailed'), isTrue);
      expect(panelSaveBody().contains('publishedBuild('), isTrue);
      final save = panelSaveBody();
      final firstWrite = save.indexOf('batch.set(');
      expect(firstWrite, greaterThan(0), reason: 'لا كتابةَ في الدفعة');
      expect(panelSaveBody().lastIndexOf('return;'), lessThan(firstWrite),
          reason: 'فاحِصٌ يَرجعُ بعد كتابة');
    });

    test('(ح) دفعةٌ ذرّيّةٌ لا `Promise.all`', () {
      final save = panelSaveBody();
      expect(save.contains('writeBatch(db)'), isTrue,
          reason: 'الحفظُ ليس دفعةً');
      expect(RegExp(r'batch\.commit\(\)').allMatches(save).length, 1);
      expect(save.contains('Promise.all'), isFalse,
          reason: 'عادَ `Promise.all` — فانقطاعُ الشبكةِ يُنتجُ حالةً جزئيّة');
      expect(RegExp(r'batch\.set\(').allMatches(save).length, 3,
          reason: 'عددُ كتاباتِ اللوحةِ ليس ثلاثاً');
    });

    test('(ط) وختمُ الزمنِ خادميٌّ في الطرفَين — مرآةٌ لا ساعةُ متصفّح', () {
      expect(panelSaveBody().contains('serverTimestamp()'), isTrue,
          reason: 'عادت ساعةُ المتصفّحِ (`new Date()`) على مستندٍ عامّ');
      expect(panelSaveBody().contains('new Date()'), isFalse);
    });

    test('(ي) المضادّة: الشكلُ القديمُ ما زال موثَّقاً في الخامّ', () {
      expect(panelRaw.contains('Promise.all'), isTrue,
          reason: 'شرحُ سببِ الدفعةِ زال من التعليق');
    });
  });

  group('التقسيمُ بين السطحَين مُعلَنٌ لا منحرف', () {
    test('(ك) السعةُ اليوميّةُ في دفعةِ التطبيقِ وبزرٍّ مستقلٍّ في اللوحة', () {
      // فرقُ تقسيمٍ في الواجهةِ لا فرقُ قرار — ولو دخلت دفعةَ اللوحةِ يوماً
      // فهذا الفحصُ هو ما يُراجَع، لا يُسكَت.
      expect(saveBody()
          .contains('max_orders_per_day'), isTrue);
      expect(panelSaveBody()
          .contains('max_orders_per_day'), isFalse);
      expect(panel.contains('max_orders_per_day'), isTrue,
          reason: 'اللوحةُ لا تَحفظُ السعةَ إطلاقاً — وهذا عطلٌ آخر');
    });
  });
}
