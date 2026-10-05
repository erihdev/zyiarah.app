import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **منتجٌ أُنشئ من لوحةِ الويبِ يَهبطُ في متجرِ العميلِ بصمت.**
///
/// (قرارُ المالك) متجرٌ واحدٌ والمنتجُ يَختارُ جمهورَه:
/// `products.store_audience` ∈ {`client`, `companies`}، والغيابُ = `client`
/// توافقاً مع المستندات القديمة (`store_service.dart`:
/// `audience: data['store_audience'] ?? 'client'`) — وهو **افتراضٌ مقصودٌ
/// للقديم، لا لمنتجٍ يُنشَأ اليوم**.
///
/// ومحرّرُ Flutter (`admin_store_screen`) يَملكُ مُنتقياً («متجر العميل» /
/// «متجر الشركات») وشارةً على الصفّ. ولوحةُ الويبِ (`StoreProducts.tsx`)
/// كانت تَكتبُ `{...formData}` و`formData` **بلا الحقلِ إطلاقاً**:
///
///   * منتجٌ جديدٌ من اللوحةِ ⇒ بلا حقل ⇒ متجرُ العميلِ دائماً، ولا سبيلَ
///     إلى وضعِه في متجرِ الشركات.
///   * منتجُ شركاتٍ يُحرَّر من اللوحةِ ⇒ `updateDoc` لا يَمسُّ ما لم يُمرَّر
///     فيَبقى الحقلُ (لا يُفقَد) — لكنّ الأدمنَ لا يَرى إلى أيِّ متجرٍ ينتمي
///     ولا يستطيع نقلَه.
///
/// والشكلُ الرابعُ نفسُه: محرّران لمستندٍ واحدٍ وأحدُهما يُغفل حقلَ قرارٍ
/// غيابُه صامت — مفاتيحُ الإصدارِ الإجباريّ، `show_in_offers`، `operational`،
/// والآن `store_audience`.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  final dartEditor = read('lib/screens/admin/admin_store_screen.dart');
  final webEditor = read('admin_panel/src/pages/StoreProducts.tsx');
  final service = read('lib/services/store_service.dart');

  test('القاعدةُ: الغيابُ = متجرُ العميل (توافقُ القديم)', () {
    expect(stripLineComments(service),
        contains("data['store_audience'] ?? 'client'"),
        reason: 'القاعدةُ تغيّرت — أعِد تقييمَ المحرّرَين معها');
  });

  test('محرّرُ Flutter يَكتبُ الحقلَ ويَعرضُ مُنتقيَه وشارتَه', () {
    expect(dartEditor, contains("'store_audience': audience"));
    expect(dartEditor, contains("Text('متجر العميل')"));
    expect(dartEditor, contains("Text('متجر الشركات')"));
    expect(dartEditor, contains("(data['store_audience'] ?? 'client') == 'companies'"),
        reason: 'شارةُ الصفِّ اختفت');
  });

  test('ولوحةُ الويبِ كذلك — وهذا ما كان ناقصاً', () {
    final web = stripLineComments(webEditor);
    expect(web, contains('store_audience'),
        reason: 'اللوحةُ لا تَكتبُ الحقل: كلُّ منتجٍ منها في متجرِ العميلِ '
            'بصمت، ولا سبيلَ إلى متجرِ الشركات');
    expect(web, contains('aria-label="يظهر في"'),
        reason: 'حقلٌ يُكتب بلا مُنتقٍ يَراه الأدمن = قرارٌ لا يستطيع اتّخاذه');
    expect(web, contains('متجر الشركات'),
        reason: 'لا شارةَ على الصفّ — فلا يَعرفُ الأدمنُ إلى أيِّ متجرٍ ينتمي');
    // والافتراضُ هو افتراضُ القاعدةِ نفسِه لا شيءٌ آخر.
    expect(web, contains("store_audience: 'client'"));
  });

  test('ومجموعةُ حقولِ المحرّرَين واحدة', () {
    // المقارنةُ على المجموعةِ كلِّها (كما في app_update_keys_test): حقلٌ في
    // أحدِهما دون الآخرِ يَسقطُ هنا بدل أن يَفترقا بصمت.
    String block(String src, String start, String end) {
      final i = src.indexOf(start);
      expect(i, greaterThan(0), reason: 'لم يُوجد $start');
      final j = src.indexOf(end, i);
      expect(j, greaterThan(i), reason: 'لم يُوجد $end');
      return src.substring(i, j);
    }

    final dartKeys = RegExp(r"^\s*'([a-z_]+)':", multiLine: true)
        .allMatches(stripLineComments(
            block(dartEditor, 'final data = {', '};')))
        .map((m) => m.group(1)!)
        .toSet();
    final webKeys = RegExp(r'^\s*([a-z_]+):', multiLine: true)
        .allMatches(stripLineComments(
            block(webEditor, 'const [formData, setFormData] = useState({', '});')))
        .map((m) => m.group(1)!)
        .toSet();

    // الطابعُ الزمنيُّ يُضاف خارجَ الكتلةِ في الويب (created/updated_at) —
    // فنستثنيه من الجهةِ الواحدةِ التي تَحملُه داخل كتلتِها.
    final dartDecisions = dartKeys.difference({'updated_at', 'created_at'});
    expect(dartDecisions, equals(webKeys),
        reason: 'المحرّران افترقا — في Flutter فقط: '
            '${dartDecisions.difference(webKeys)}، '
            'وفي الويب فقط: ${webKeys.difference(dartDecisions)}');
    expect(dartDecisions.length, greaterThanOrEqualTo(5),
        reason: 'الاستخراجُ فارغٌ تقريباً — فالمقارنةُ بلا موضوع');
  });
}
