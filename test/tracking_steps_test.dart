import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/tracking_steps.dart';
import 'package:zyiarah/utils/phone_format.dart';

/// شاشة التتبّع بعد تصميم Stitch (2026-09-16): خمس مراحل تبدأ باستلام الطلب،
/// طابع زمني لكل مرحلة من حقول الطلب، خطّ المسار، وزرّ واتساب بصيغة wa.me.
void main() {
  test('خمس مراحل تبدأ بـ«تم استلام وتأكيد الطلب»', () {
    expect(TrackingSteps.steps.length, 5);
    expect(TrackingSteps.steps.first.label, 'تم استلام وتأكيد الطلب');
    expect(TrackingSteps.steps.last.label, 'تمت المهمة بنجاح');
  });

  test('indexFor: لهجة الإسناد المباشر واللهجة القديمة معاً', () {
    expect(TrackingSteps.indexFor('pending'), 0);
    expect(TrackingSteps.indexFor('scheduled'), 1);
    expect(TrackingSteps.indexFor('assigned'), 1);
    expect(TrackingSteps.indexFor('accepted'), 2);
    expect(TrackingSteps.indexFor('on_the_way'), 2);
    expect(TrackingSteps.indexFor('in_progress'), 3);
    expect(TrackingSteps.indexFor('completed'), 4);
    expect(TrackingSteps.indexFor('cancelled'), -1);
  });

  test('timeFor: أول حقل موجود من حقول المرحلة، وTimestamp فقط', () {
    final t1 = Timestamp.fromDate(DateTime(2026, 9, 16, 14, 15));
    final t2 = Timestamp.fromDate(DateTime(2026, 9, 16, 14, 22));
    final data = {
      'created_at': t1,
      'accepted_at': t2,
      'on_the_way_at': 'not a timestamp',
      'start_time': Timestamp.fromDate(DateTime(2026, 9, 16, 15)),
    };
    expect(TrackingSteps.timeFor(0, data), DateTime(2026, 9, 16, 14, 15));
    expect(TrackingSteps.timeFor(1, data), DateTime(2026, 9, 16, 14, 22));
    expect(TrackingSteps.timeFor(2, data), isNull);
    expect(TrackingSteps.timeFor(3, data), DateTime(2026, 9, 16, 15),
        reason: 'arrived_at غائب → start_time');
    expect(TrackingSteps.timeFor(4, data), isNull);
    expect(TrackingSteps.timeFor(9, data), isNull);
    // paid_at يسبق created_at لمرحلة الاستلام.
    expect(
        TrackingSteps.timeFor(0, {'created_at': t1, 'paid_at': t2}),
        DateTime(2026, 9, 16, 14, 22));
  });

  test('timeLabel: 12 ساعة بالعربية، وبالتاريخ لغير اليوم', () {
    final now = DateTime(2026, 9, 16, 18);
    expect(TrackingSteps.timeLabel(DateTime(2026, 9, 16, 14, 15), now: now),
        'الساعة 02:15 م');
    expect(TrackingSteps.timeLabel(DateTime(2026, 9, 16, 0, 5), now: now),
        'الساعة 12:05 ص');
    expect(TrackingSteps.timeLabel(DateTime(2026, 9, 15, 9, 0), now: now),
        '2026/09/15 09:00 ص');
  });

  test('whatsappNumber: صيغة دولية عارية، والمحلي السعودي يُلحق بـ966', () {
    expect(whatsappNumber('0530489016'), '966530489016');
    expect(whatsappNumber('530489016'), '966530489016');
    expect(whatsappNumber('+966 53 048 9016'), '966530489016');
    expect(whatsappNumber('00966530489016'), '966530489016');
    expect(whatsappNumber('${String.fromCharCode(0x202D)}+966 53 048 9016${String.fromCharCode(0x202C)}'), '966530489016');
    expect(whatsappNumber(''), '');
    expect(whatsappNumber(null), '');
    expect(whatsappNumber('abc'), '');
  });

  test('شاشة التتبّع: خطّ المسار، وزرّ واتساب، والمراحل من النموذج', () {
    final src = File('lib/screens/order_tracking_screen.dart').readAsStringSync();
    expect(src.contains('PolylineLayer('), isTrue);
    expect(src.contains("points: [driverLatLng, clientLatLng]"), isTrue);
    expect(src.contains("Uri.parse('https://wa.me/\$number')"), isTrue);
    expect(src.contains('whatsappNumber(phone)'), isTrue);
    expect(src.contains('TrackingSteps.indexFor(currentStatus)'), isTrue);
    expect(src.contains('TrackingSteps.timeFor(index, data)'), isTrue);
    expect(src.contains("'تم تعيين السائق', 'icon'"), isFalse,
        reason: 'القائمة القديمة المكرّرة حُذفت');
  });
}
