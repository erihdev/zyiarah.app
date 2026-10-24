// «حفظ التعديلات» لا يَكتبُ فوقَ حالةٍ لم يَرَها المدير (تجربة 2026-10-24).
//
// شاشةُ تفاصيلِ الطلبِ تَقرأُ مرّةً عند فتحِها. أكملَ السائقُ الطلبَ والصفحةُ
// مفتوحة: الشاشةُ «مجدول»، والطلبُ «مكتمل». والمسارُ المباشرُ كان يَكتبُ
// `{'status': _currentStatus}` دائماً — فحفظٌ بلا أيِّ تعديلٍ يُعيدُ المكتملَ
// إلى مهامِّ السائق، والملغى أو المُسترَدَّ إلى النشاط. والقواعدُ تَمنحُ
// isOrdersManager() تحديثاً كاملاً، فلا حارسَ بعدَ الشاشة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();

  String saveBody() {
    final start = src.indexOf("setState(() => _isLoading = true);\n    try {");
    expect(start, greaterThan(-1), reason: 'بدايةُ الحفظِ تغيّرت — حدِّث الحارس');
    return src.substring(start, start + 30000);
  }

  test('قراءةٌ طازجةٌ قبلَ أيِّ كتابة، وتغيّرٌ من جهةٍ أخرى يُعيدُ التحميل', () {
    final body = saveBody();
    final freshAt = body.indexOf('final fresh = await _db');
    expect(freshAt, greaterThan(-1), reason: 'الحفظُ بلا قراءةٍ طازجة');
    for (final w in [
      '_orderService.cancelOrder(',
      "_orderService.updateOrderStatus(",
      "httpsCallable('approveAndAssignOrder')",
      "httpsCallable('rescheduleAssignedOrder')",
      '.update(updatePayload)',
    ]) {
      final at = body.indexOf(w);
      expect(at, greaterThan(freshAt), reason: 'كتابةٌ قبلَ القراءةِ الطازجة: $w');
    }
    expect(body.contains("freshData['status'] != _orderData?['status']"), isTrue,
        reason: 'الحالةُ الطازجةُ لا تُقارَن');
    expect(body.contains("freshData['driver_id'] != _orderData?['driver_id']"),
        isTrue, reason: 'السائقُ الطازجُ لا يُقارَن');
    final guard = body.substring(freshAt, body.indexOf('final bool isNewAssignment'));
    expect(guard.contains('await _fetchOrder();'), isTrue);
    expect(guard.contains('return;'), isTrue, reason: 'يَمضي إلى الكتابةِ بعدَ الكشف');
  });

  test('الحالةُ تُكتَبُ حين غيّرها المدير وحدَه', () {
    final body = saveBody();
    expect(body.contains("updatePayload = {'status': _currentStatus}"), isFalse,
        reason: 'عادت كتابةُ الحالةِ بلا شرط — حفظٌ بلا تعديلٍ يُعيدُ القديم');
    // وفرعُ إعادةِ الجدولةِ يَكتبُ الحالةَ مشروطةً بتغيّرِها أصلاً.
    final at = body.indexOf(".update({'status': _currentStatus})");
    if (at > -1) {
      final before = body.substring(at - 300, at);
      expect(before.contains("_currentStatus != (_orderData?['status']"), isTrue,
          reason: 'كتابةُ حالةٍ غيرُ مشروطةٍ في فرعِ إعادةِ الجدولة');
    }
    expect(body.contains("if (_currentStatus != oldStatus) 'status': _currentStatus"),
        isTrue);
    expect(body.contains('if (updatePayload.isNotEmpty)'), isTrue,
        reason: 'كتابةٌ فارغةٌ تُطلِقُ مُشغّلاتِ الطلبِ بلا سبب');
  });
}
