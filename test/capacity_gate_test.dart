// حارس انحدار: بوابة السعة يجب أن تفشل **مغلقة**، ولا تُستعلَم من العميل مباشرةً.
//
// العطل الذي يمنعه (كان حيّاً في الإنتاج ولم تمنع البوابة حجزاً واحداً منذ كُتبت):
//   _checkHourlyCapacity كان يستعلم `orders` من جهاز العميل بلا قيد client_id.
//   قاعدة القراءة الوحيدة للطلبات تسمح للعميل بطلباته هو فقط، والقواعد ليست مُرشِّحات
//   ⇒ Firestore يرفض الاستعلام كاملاً بـ permission-denied ⇒ يبتلعه `catch (_) {}`
//   ⇒ وجملتا `return '<رسالة>'` داخل الـ try تُتخطّيان ⇒ الدالة تُرجع null = «متاح».
//   النتيجة: العميل يدفع ليومٍ ممتلئ ولا يجد سائقاً.
//
// درسان مثبَّتان هنا:
//   1. لا تستعلم `orders` من العميل لأغراض السعة — استخدم getHourlyAvailability.
//   2. فشل التحقق ≠ سماح. الافتراض عند الجهل هو المنع لا التمرير.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نموذج مصغّر لمنطق البوابة بعد الإصلاح — يعكس lib/screens/payment_summary_screen.dart.
String? capacityVerdict({
  required bool checkSucceeded,
  required int ordersThatDay,
  required int maxOrdersPerDay,
  required int driversInZone,
  required Map<String, int> slotCounts,
  required String bookingDate,
  required int startHour,
  required int hours,
}) {
  if (!checkSucceeded) {
    return 'تعذّر التحقق من توفّر الموعد. تحقّق من اتصالك وأعد المحاولة.';
  }
  if (driversInZone <= 0) {
    return 'لا يوجد سائق متاح في منطقتك حالياً. تواصل معنا لتحديد موعد.';
  }
  if (ordersThatDay >= maxOrdersPerDay) {
    return 'نعتذر، هذا اليوم محجوز بالكامل حالياً. يرجى اختيار تاريخ آخر.';
  }
  for (int h = startHour; h < startHour + hours; h++) {
    final key = '${bookingDate}_${h.toString().padLeft(2, '0')}:00';
    if ((slotCounts[key] ?? 0) >= driversInZone) {
      return 'نعتذر، هذا الوقت محجوز بالكامل حالياً. يرجى اختيار وقت بدء آخر.';
    }
  }
  return null;
}

void main() {
  const date = '2026-08-01';

  group('البوابة تفشل مغلقة — الجهل يمنع ولا يمرّر', () {
    test('تعذّر التحقق ⇒ يُمنع الدفع (كان يمرّر صامتاً)', () {
      final v = capacityVerdict(
        checkSucceeded: false, // permission-denied / انقطاع شبكة / تعطّل الدالة
        ordersThatDay: 0, maxOrdersPerDay: 10, driversInZone: 5,
        slotCounts: const {}, bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, isNotNull,
          reason: 'الفشل القديم كان يُرجع null = «متاح» فيُدفع طلب لا سائق له');
    });

    test('لا سائق مؤهّل في المنطقة ⇒ يُمنع الدفع', () {
      final v = capacityVerdict(
        checkSucceeded: true,
        ordersThatDay: 0, maxOrdersPerDay: 10, driversInZone: 0,
        slotCounts: const {}, bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, contains('لا يوجد سائق'));
    });
  });

  group('السعة الحقيقية', () {
    test('اليوم ممتلئ ⇒ رسالة اليوم', () {
      final v = capacityVerdict(
        checkSucceeded: true,
        ordersThatDay: 10, maxOrdersPerDay: 10, driversInZone: 5,
        slotCounts: const {}, bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, contains('هذا اليوم محجوز'));
    });

    test('ساعة داخل المدة ممتلئة ⇒ يُمنع، ولو كانت ساعة البدء متاحة', () {
      // الطلب 9→13. الساعة 11 مشغولة بكل السائقين. الفحص القديم كان ينظر لساعة البدء
      // فقط فيمرّر الحجز، فيصل السائق ولا يستطيع إكمال المدة.
      final v = capacityVerdict(
        checkSucceeded: true,
        ordersThatDay: 2, maxOrdersPerDay: 10, driversInZone: 3,
        slotCounts: {'${date}_11:00': 3},
        bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, contains('هذا الوقت محجوز'));
    });

    test('كل الساعات دون السقف ⇒ يُسمح', () {
      final v = capacityVerdict(
        checkSucceeded: true,
        ordersThatDay: 2, maxOrdersPerDay: 10, driversInZone: 3,
        slotCounts: {'${date}_09:00': 2, '${date}_10:00': 1},
        bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, isNull);
    });

    test('ساعة خارج المدة ممتلئة ⇒ لا تمنع', () {
      final v = capacityVerdict(
        checkSucceeded: true,
        ordersThatDay: 2, maxOrdersPerDay: 10, driversInZone: 3,
        slotCounts: {'${date}_15:00': 3}, // خارج 9→13
        bookingDate: date, startHour: 9, hours: 4,
      );
      expect(v, isNull);
    });
  });

  test('المصدر: البوابة لا تستعلم orders من العميل ولا تبتلع الفشل', () {
    final src = File('lib/screens/payment_summary_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<String?> _checkHourlyCapacity()');
    expect(start, greaterThan(-1), reason: '_checkHourlyCapacity اختفت — حدِّث الحارس');
    // نهاية الدالة: أول `\n  }` بعد بدايتها.
    final end = src.indexOf('\n  }', start);
    final body = src.substring(start, end);

    expect(
      body.contains("collection('orders')"),
      isFalse,
      reason: 'استعلام orders من العميل يُرفض بـ permission-denied (القواعد ليست مُرشِّحات).\n'
          'استخدم getHourlyAvailability — الدالة الخادمية الموجودة أصلاً لهذا الغرض.',
    );
    expect(
      body.contains('getHourlyAvailability'),
      isTrue,
      reason: 'السعة تُحسب خادمياً من عدد السائقين المؤهّلين في المنطقة.',
    );
    expect(
      RegExp(r'catch\s*\(\s*_\s*\)\s*\{\s*\}').hasMatch(body),
      isFalse,
      reason: 'ابتلاع صامت داخل البوابة = عودة العطل نفسه. الفشل يجب أن يُرجع رسالة مانعة.',
    );
  });
}
