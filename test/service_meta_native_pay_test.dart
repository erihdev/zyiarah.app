import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (كشفه اختبار المالك الحيّ للطلب 223) طلب سيارة مدفوع بـ Apple Pay أُنشئ خادميّاً
/// من الـ metadata ففقد service_meta (حجم السيارة) — والإدارة/السائق لا يرونه.
/// الإصلاح: نحمل service_meta كنصّ JSON في الـ metadata ويعيد الخادم بناءه.
void main() {
  final pay = File('lib/screens/payment_summary_screen.dart').readAsStringSync();
  final fn = File('functions/index.js').readAsStringSync();

  test('العميل يحمل service_meta كنصّ JSON في بيانات الدفعة الأصلية', () {
    expect(pay.contains("import 'dart:convert';"), isTrue);
    expect(pay.contains("'service_meta_json': jsonEncode(widget.serviceMeta)"),
        isTrue,
        reason: 'بدونه يفقد طلب Apple Pay تفصيله عند إنشائه خادميّاً');
  });

  test('الخادم يعيد بناء service_meta في موضعَي الإنشاء من الـ metadata', () {
    expect(fn.contains('function _parseServiceMeta('), isTrue);
    // verifyMoyasarPayment + reconcileOrphanPayments (كلا مسارَي الإنشاء الخادمي).
    expect(
        RegExp(r'service_meta: _parseServiceMeta\(md\.service_meta_json\)')
            .allMatches(fn)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'كلا مسارَي الإنشاء الخادمي يجب أن يعيدا بناء التفصيل');
  });
}
