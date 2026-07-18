import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (كشفه اختبار المالك الحيّ — الطلب WKN-224) تنبيه الإدارة «طلب خدمات جديد»
/// كان يُطلق لحظة إنشاء الطلب، وطلبات البطاقة تُنشأ is_paid=false قبل الدفع —
/// فتصل الإدارة تنبيهات لطلبات لم تُدفع (وقد تُهجَر). يجب أن يُطلق عند تأكيد الدفع.
void main() {
  final fn = File('functions/index.js').readAsStringSync();

  test('تنبيه الإدارة بالطلب الجديد يُطلق عند قلب is_paid لا عند الإنشاء', () {
    final i = fn.indexOf('exports.sendNotificationToAdminsOnNewOrder');
    expect(i, greaterThan(-1));
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    // مشغّل الكتابة (لا الإنشاء) كي نلتقط قلب is_paid.
    expect(body.contains('onDocumentWritten'), isTrue,
        reason: 'onDocumentCreated يُطلق قبل الدفع لطلبات البطاقة');
    expect(body.contains('onDocumentCreated'), isFalse);
    // الشرط: صار مدفوعاً (لم يكن مدفوعاً قبلُ) — مرّة واحدة.
    expect(
        body.contains(
            'after.is_paid === true && (!before || before.is_paid !== true)'),
        isTrue,
        reason: 'بلا هذا الشرط يتكرّر التنبيه أو يصل قبل الدفع');
    // زيارات الاشتراك تبقى مكتومة (إشعار العقد يكفي).
    expect(body.contains('after.contract_id'), isTrue);
  });
}
