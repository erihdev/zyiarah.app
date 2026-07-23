import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) توافق iPad/الشاشات الكبيرة: التطبيق مُصمَّم للهواتف،
/// وكان يتمدّد لكامل عرض الـ iPad فيبدو مشوّهاً. نحصره في عمودٍ موسّط بعرض هاتف.
void main() {
  final main = File('lib/main.dart').readAsStringSync();

  test('MaterialApp يحصر العرض في عمودٍ موسّط على الشاشات الكبيرة', () {
    expect(main.contains('builder: (context, child) {'), isTrue,
        reason: 'بلا builder يبقى التطبيق ممتدّاً لكامل عرض الـ iPad');
    expect(main.contains('const maxWidth = 600.0;'), isTrue);
    // الهواتف (عرض ≤ الحدّ) لا تتأثر إطلاقاً.
    // (#16) صار يمرّر gated (= child أو شاشة الصيانة عبر بوّابة الصيانة الشاملة) — لا
    // يضيف أيّ قيد عرض، فالهاتف يبقى بلا حصر تماماً كما كان مع child.
    expect(main.contains('if (mq.size.width <= maxWidth) return gated;'), isTrue,
        reason: 'الهاتف يجب أن يمرّ بلا حصر عرض');
  });

  test('MediaQuery يُحدَّث للعرض المحصور (منع تجاوز الشاشات)', () {
    // بلا هذا ترى الشاشة العرض الكامل بينما مساحتها الفعلية 600 فتتجاوز.
    expect(
        main.contains('data: mq.copyWith(size: Size(maxWidth, mq.size.height))'),
        isTrue,
        reason: 'أي شاشة تحسب أبعادها من MediaQuery.size ستتجاوز بدونه');
  });
}
