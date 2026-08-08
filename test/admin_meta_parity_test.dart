import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// تكافؤ عرض `service_meta` بين واجهتَي الإدارة.
///
/// **سبب وجوده:** التطبيق يكتب ستة أنواع من `service_meta`، وكان
/// `pkgSummary` في لوحة الويب يبدأ بـ `kind !== 'home_package' → null` — فيُسنِد
/// الأدمن من الويب سائقاً وهو لا يرى عدد المكيفات ولا مقاسات الكنب ولا مواد
/// التنظيف ولا — الأخطر — عدد عاملات المناسبة وساعاتها، وهي جوهر الحجز.
/// هذه الحارسة تمنع رجوع الفجوة: أي نوع جديد يُكتب في التطبيق يجب أن تقرأه اللوحة.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// الملف بلا أسطر التعليقات. التعليق الذي يشرح **ألا** نستعمل حقلاً يذكر اسمه،
  /// فمسحُ النصّ الخام يلتقط الشرح نفسه ويفشل بلا سبب حقيقي (تكرّر ثلاث مرات).
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  /// الأنواع الستة التي يكتبها التطبيق فعلاً على الطلبات.
  const kinds = [
    'home_package',
    'sofa_rug_sqm',
    'ac_service',
    'car_interior',
    'store_products',
    'event_workers',
  ];

  test('كل نوع يكتبه التطبيق له كاتب فعلي', () {
    // مصدر القائمة ليس افتراضاً: نتحقق أن كل نوع مكتوب في شاشة عميل ما.
    final writers = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final k in kinds) {
      expect(writers.contains("'kind': '$k'"), isTrue,
          reason: '$k غير مكتوب في أي شاشة — القائمة أصبحت قديمة');
    }
  });

  test('تطبيق الإدارة يعرض الأنواع الستة', () {
    final view = read('lib/widgets/service_meta_view.dart');
    for (final k in kinds) {
      expect(view.contains("'$k'"), isTrue, reason: '$k غير معروض في التطبيق');
    }
  });

  test('لوحة الويب تعرض الأنواع الستة أيضاً', () {
    final web = read('admin_panel/src/pages/Orders.tsx');
    for (final k in kinds) {
      expect(web.contains("'$k'"), isTrue,
          reason: '$k غير معروض في لوحة الويب — الأدمن يُسنِد سائقاً بلا تفصيل');
    }
  });

  test('الويب لا يعرض حاجز home_package القديم', () {
    final web = read('admin_panel/src/pages/Orders.tsx');
    expect(web.contains("m.kind !== 'home_package'"), isFalse,
        reason: 'الحاجز الذي كان يُرجع null لكل نوع آخر');
  });

  test('الويب لا يستعمل worker_count/hours_contracted بديلاً', () {
    // يحملهما **كل** طلب بقيم افتراضية (1 عاملة / 4 ساعات)، فعرضهما مباشرةً
    // يطبع بيانات كاذبة على طلبات لا علاقة لها بعدد العاملات.
    final web = codeOnly('admin_panel/src/pages/Orders.tsx');
    expect(web.contains('o.worker_count'), isFalse);
    expect(web.contains('o.hours_contracted'), isFalse);
  });

  test('مواد التنظيف تظهر في الواجهتين', () {
    expect(read('lib/widgets/service_meta_view.dart').contains('materials'),
        isTrue);
    final web = read('admin_panel/src/pages/Orders.tsx');
    expect(web.contains('m.materials'), isTrue);
    expect(web.contains('مادة'), isTrue, reason: 'وسم «+ N مادة» كما في التطبيق');
  });
}
