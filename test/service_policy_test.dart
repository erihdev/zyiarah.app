import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/service_policy.dart';

/// نموذج بنود «شروط وضوابط الخدمة» (تصميم Stitch، 2026-09-16): القراءة متسامحة
/// مع المستندات الناقصة أو المكتوبة يدوياً من الكونسول، والكتابة تُخرج الحقول
/// الستة نفسها التي تقرؤها القواعد والشاشات — لا أكثر ولا أقل.
void main() {
  ServicePolicy p(String id, String cat, {bool enabled = true, int order = 0}) =>
      ServicePolicy(
        id: id,
        title: 't$id',
        body: 'b',
        category: cat,
        enabled: enabled,
        mandatoryBeforeBooking: false,
        order: order,
      );

  group('ServicePolicy.fromMap', () {
    test('مستند كامل يُقرأ كما هو', () {
      final ts = Timestamp.fromDate(DateTime(2026, 9, 16, 11, 20));
      final m = ServicePolicy.fromMap('p1', {
        'title': 'اشتراطات السلامة',
        'body': 'يشترط...',
        'category': 'privacy_safety',
        'enabled': true,
        'mandatory_before_booking': true,
        'order': 3,
        'updated_at': ts,
      });
      expect(m.id, 'p1');
      expect(m.title, 'اشتراطات السلامة');
      expect(m.category, 'privacy_safety');
      expect(m.enabled, isTrue);
      expect(m.mandatoryBeforeBooking, isTrue);
      expect(m.order, 3);
      expect(m.updatedAt, DateTime(2026, 9, 16, 11, 20));
    });

    test('تصنيف مجهول أو غائب → التصنيف الافتراضي، والأعلام لا تُفعَّل إلا بـ true',
        () {
      final unknown = ServicePolicy.fromMap('x', {'category': 'legacy_stuff'});
      expect(unknown.category, ServicePolicy.defaultCategory);
      final missing = ServicePolicy.fromMap('y', const {});
      expect(missing.category, ServicePolicy.defaultCategory);
      expect(missing.title, '');
      expect(missing.enabled, isFalse,
          reason: 'بند بلا enabled لا يظهر للعميل حتى يفعّله الأدمن صراحةً');
      expect(missing.mandatoryBeforeBooking, isFalse);
      expect(missing.updatedAt, isNull);
      // 'true' نصّاً أو 1 رقماً ليسا تفعيلاً.
      expect(ServicePolicy.fromMap('z', {'enabled': 'true'}).enabled, isFalse);
      expect(ServicePolicy.fromMap('z', {'enabled': 1}).enabled, isFalse);
    });

    test('order يقبل int أو double، وغير ذلك 0', () {
      expect(ServicePolicy.fromMap('a', {'order': 2}).order, 2);
      expect(ServicePolicy.fromMap('a', {'order': 2.0}).order, 2);
      expect(ServicePolicy.fromMap('a', {'order': '2'}).order, 0);
      expect(ServicePolicy.fromMap('a', {'order': null}).order, 0);
    });
  });

  test('toMap يكتب الحقول الستة فقط (بلا id ولا updated_at)', () {
    final m = ServicePolicy(
      id: 'p1',
      title: 'T',
      body: 'B',
      category: 'mountain_routes',
      enabled: false,
      mandatoryBeforeBooking: true,
      order: 7,
      updatedAt: DateTime(2026),
    ).toMap();
    expect(m, {
      'title': 'T',
      'body': 'B',
      'category': 'mountain_routes',
      'enabled': false,
      'mandatory_before_booking': true,
      'order': 7,
    });
    // ذهاباً وإياباً بلا فقد.
    final back = ServicePolicy.fromMap('p1', m);
    expect(back.toMap(), m);
  });

  test('visibleSorted: المفعّل فقط، بترتيب التصنيفات ثم order', () {
    final sorted = ServicePolicy.visibleSorted([
      p('a', 'mountain_routes', order: 0),
      p('b', 'contracts', order: 5),
      p('c', 'privacy_safety', order: 1, enabled: false),
      p('d', 'contracts', order: 2),
      p('e', 'cancellation_scheduling', order: 9),
    ]);
    expect(sorted.map((x) => x.id).toList(), ['d', 'b', 'e', 'a']);
    expect(sorted.any((x) => x.id == 'c'), isFalse);
  });

  test('التصنيفات الأربعة من تصميم Stitch، وكل تصنيف له وصف نطاق', () {
    expect(ServicePolicy.categoryLabels.keys.toList(), [
      'contracts',
      'privacy_safety',
      'cancellation_scheduling',
      'mountain_routes',
    ]);
    expect(ServicePolicy.categoryScopes.keys.toSet(),
        ServicePolicy.categoryLabels.keys.toSet());
    expect(ServicePolicy.categoryLabels.containsKey(ServicePolicy.defaultCategory),
        isTrue);
    expect(ServicePolicy.labelOf('privacy_safety'), 'الخصوصية والسلامة');
    expect(ServicePolicy.labelOf('weird'), 'weird');
  });
}
