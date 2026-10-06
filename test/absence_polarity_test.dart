// ════════════════════════════════════════════════════════════════════════
// قُطبيّةُ غيابِ الحقل: الاستعلامُ هو الآمِر، والعرضُ يَتبعُه (2026-10-06)
//
// **مساواةُ Firestore تَستلزمُ وجودَ الحقل.** فمستندٌ لا يَحملُ العلَمَ
// يَخرُجُ من `.where('f', isEqualTo: v)` كيفما كانت `v` — ولا سبيلَ
// لاستعلامِ «غائبٌ أو يساوي» (وهذا مكتوبٌ بخطِّ المشروعِ في
// `store_service`: «التصفيةُ محليّةٌ لأنّ المستنداتِ القديمةَ بلا حقل…»).
//
// فحين يَعرضُ محرّرُ الإدارةِ الغيابَ على المعنى **المعاكس**، تَصيرُ
// الشاشةُ دعوى لا تَصحّ: المستندُ غيرُ مرئيٍّ لأيِّ عميلٍ والأدمنُ يَقرؤه
// «مفعّلاً/ظاهراً»، **بلا أيِّ علاجٍ ظاهر** — لا شارةَ ولا سببَ.
//
// ثلاثُ مجموعاتٍ وقعت فيها:
//   * `service_zones.enabled` — استعلامُ `== true`، والعرضُ `?? true`.
//   * `products.is_hidden` — استعلامُ `== false`، والعرضُ `?? false`
//     (ومنتجاتٌ قديمةٌ بلا الحقلِ **مُقَرٌّ بوجودِها** في تعليقِ الشاشةِ
//     نفسِها: «doc['is_hidden'] … يرمي StateError حين يغيب الحقل»).
//   * `promo_banners.isActive` — استعلامُ `== true`، والقائمةُ `== true`
//     (صحيحة) **وافتراضُ الحوارِ `?? true`**: تناقضٌ داخلَ شاشةٍ واحدة.
//
// والقاعدةُ المشدودةُ هنا: **لا افتراضَ عرضٍ يُخالِفُ استعلامَ القارئِ
// الآمِر**. والنطاقُ مُشتَقٌّ من الاستعلاماتِ نفسِها، فمجموعةٌ رابعةٌ تَدخلُ
// بنفسِها.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*') ||
              t.startsWith('{/*'))
          ? ''
          : l;
    })
    .join('\n');

List<String> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path)
    .where((p) => p.endsWith('.dart'))
    .toList()
  ..sort();

void main() {
  /// (الحقل، القيمةُ المطلوبة) لكلِّ استعلامِ مساواةٍ على علَمٍ منطقيٍّ في
  /// مسارِ العميلِ — مُشتَقٌّ لا مكتوبٌ بيد.
  Map<String, bool> boolEqualityFilters() {
    final out = <String, bool>{};
    for (final f in [..._dartFiles('lib/services'), ..._dartFiles('lib/screens')]) {
      final src = _code(f);
      for (final m in RegExp(
              r"\.where\(\s*'([a-zA-Z_]+)'\s*,\s*isEqualTo:\s*(true|false)\s*\)")
          .allMatches(src)) {
        out[m.group(1)!] = m.group(2) == 'true';
      }
    }
    return out;
  }

  test('(أ) الاشتقاقُ أصابَ استعلاماتٍ حقيقيّة — فلا فحصَ على فراغ', () {
    final f = boolEqualityFilters();
    expect(f.length, greaterThanOrEqualTo(3),
        reason: 'الاشتقاقُ انحلَّ إلى $f — حارسٌ لا يَفحصُ أسوأُ من لا حارس');
    expect(f['enabled'], isTrue, reason: 'استعلامُ المناطقِ اختفى');
    expect(f['is_hidden'], isFalse, reason: 'استعلامُ المتجرِ اختفى');
    expect(f['isActive'], isTrue, reason: 'استعلامُ البانراتِ اختفى');
  });

  test('(ب) لا افتراضَ عرضٍ يُخالِفُ الاستعلامَ — في التطبيقِ واللوحة', () {
    // **`is_active` مُستثنىً باسمِه ولسببٍ يُتحقَّقُ منه:** سلطتُه ليست
    // استعلامَ عرضٍ بل القارئُ الخادميُّ — `isAssignableDriver` للسائقِ
    // و`staffEnabled()` في القواعدِ للموظّف — وكلاهما يَقرأُ **الغيابَ
    // مُفعَّلاً**. فمُنتقي السائقينَ يَستعلمُ `== true` «للعرضِ والخادمُ هو
    // الحارس» (قرارٌ موثَّقٌ ومشدودٌ في `admin_driver_assign_guard_test`)،
    // فعرضُ `?? true` يُوافِقُ السلطةَ لا يُخالِفُها. والفحصُ يُثبِتُ ذلك
    // بدلَ أن يَتجاهلَه.
    final drv = File('functions/drivers.js').readAsStringSync();
    expect(drv.contains('driverData.is_active !== false'), isTrue,
        reason: 'سلطةُ `is_active` للسائقِ تغيّرت — فالاستثناءُ يُراجَع');
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules.contains("getUserData().get('is_active', true) != false"), isTrue,
        reason: 'سلطةُ `is_active` للموظّفِ تغيّرت — فالاستثناءُ يُراجَع');

    final filters = boolEqualityFilters()..remove('is_active');
    final files = <String>[
      ..._dartFiles('lib/screens/admin'),
      ...Directory('admin_panel/src/pages')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.tsx')),
    ];
    final offenders = <String>[];
    for (final path in files) {
      final src = _code(path);
      for (final entry in filters.entries) {
        final field = entry.key;
        // الاستعلامُ يَطلبُ `true` ⇒ الغيابُ «غيرُ مفعَّل»، فعرضُ `?? true`
        // (أو `!== false`) دعوى معاكسة. والعكسُ للحقلِ السالبِ (`== false`).
        final badDefault = entry.value ? 'true' : 'false';
        final pats = <RegExp>[
          RegExp("\\['$field'\\]\\s*(as bool\\?\\s*)?\\?\\?\\s*$badDefault"),
          RegExp("$field\\s*!==?\\s*${badDefault == 'true' ? 'false' : 'true'}"),
        ];
        for (final p in pats) {
          for (final m in p.allMatches(src)) {
            offenders.add('$path:${src.substring(0, m.start).split('\n').length}'
                ' ($field → ${m.group(0)})');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'افتراضُ عرضٍ يُخالِفُ استعلامَ القارئِ الآمِر — '
            'المستندُ غيرُ مرئيٍّ لعميلٍ والأدمنُ يَقرؤه ظاهراً:\n'
            '${offenders.join('\n')}');
  });

  test('(ج) والقراءةُ الصحيحةُ حاضرةٌ فعلاً — لا أنّها زالت', () {
    expect(_code('lib/screens/admin/admin_hourly_zones_screen.dart')
            .contains("data['enabled'] == true"),
        isTrue, reason: 'قائمةُ المناطقِ لا تَقرأُ الحقلَ بالمساواة');
    expect(_code('lib/screens/admin/admin_store_screen.dart')
            .contains("['is_hidden'] != false"),
        isTrue, reason: 'شاشةُ المتجرِ لا تَقرأُ الغيابَ «مخفيّاً»');
    expect(_code('lib/screens/admin/admin_banners_screen.dart')
            .contains("data?['isActive'] == true"),
        isTrue, reason: 'حوارُ البانرِ لا يُطابقُ قائمتَه');
    expect(_code('admin_panel/src/pages/StoreProducts.tsx')
            .contains('is_hidden: raw.is_hidden !== false'),
        isTrue, reason: 'اللوحةُ لا تُطبّعُ الغيابَ عند القراءة');
  });

  test('(د) ولا تَطبيعَ مُناقِضاً في اللوحةِ بعدَ التطبيع', () {
    // زرُّ الإظهارِ يَكتبُ `!is_hidden`؛ فلو بقي الحقلُ خامّاً في موضعٍ
    // آخرَ لَاختلفَ ما يُعرَضُ عمّا يُكتَب.
    final panel = _code('admin_panel/src/pages/StoreProducts.tsx');
    expect(panel.contains('...doc.data() } as Product'), isFalse,
        reason: 'عادَ الانتشارُ الخامُّ — فالغيابُ يُقرأُ «ظاهراً» مرّةً أخرى');
    expect(panel.contains('is_hidden: !product.is_hidden'), isTrue,
        reason: 'زرُّ الإظهارِ لم يَعُد يَكتبُ النقيض');
  });
}
