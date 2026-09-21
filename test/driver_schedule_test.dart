import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/driver_schedule.dart';

/// حسابات جدول مناوبات السائق (تصميم Stitch، 2026-09-16): أسبوع يبدأ السبت،
/// شبكة شهرية بمضاعفات سبعة، تجميع بالأيام، ومؤشرات الفترة.
void main() {
  DriverTask t(String id, DateTime when, {String status = 'scheduled', String? slot}) =>
      DriverTask(
        id: id, code: id, serviceName: 's', clientName: 'c', zoneName: 'z',
        status: status, when: when, timeSlot: slot,
      );

  test('daysSinceSaturday / weekStart لكل أيام الأسبوع', () {
    // 2026-09-12 سبت.
    final sat = DateTime(2026, 9, 12);
    for (var i = 0; i < 7; i++) {
      final d = sat.add(Duration(days: i, hours: 13));
      expect(DriverSchedule.daysSinceSaturday(d), i, reason: 'اليوم $i');
      expect(DriverSchedule.weekStart(d), sat, reason: 'اليوم $i');
    }
    expect(DriverSchedule.dayName(sat), 'السبت');
    expect(DriverSchedule.dayName(sat.add(const Duration(days: 6))), 'الجمعة');
    expect(DriverSchedule.weekDays(DateTime(2026, 9, 16)).first, sat);
    expect(DriverSchedule.weekDays(DateTime(2026, 9, 16)).last, DateTime(2026, 9, 18));
  });

  test('monthGrid: من سبت الأسبوع الأول إلى جمعة الأخير، ومضاعف سبعة', () {
    final grid = DriverSchedule.monthGrid(DateTime(2026, 9, 16));
    expect(grid.length % 7, 0);
    expect(grid.first, DateTime(2026, 8, 29), reason: 'سبت الأسبوع الذي فيه 1 سبتمبر');
    expect(grid.last, DateTime(2026, 10, 2), reason: 'جمعة الأسبوع الذي فيه 30 سبتمبر');
    expect(DriverSchedule.monthEnd(DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    expect(DriverSchedule.monthEnd(DateTime(2026, 12, 10)), DateTime(2026, 12, 31));
  });

  test('التسميات العربية', () {
    expect(DriverSchedule.dateLabel(DateTime(2026, 9, 16)), 'الأربعاء 16 سبتمبر');
    expect(DriverSchedule.weekLabel(DateTime(2026, 9, 16)), 'أسبوع 12 - 18 سبتمبر');
    expect(DriverSchedule.weekLabel(DateTime(2026, 10, 1)), 'أسبوع 26 سبتمبر - 2 أكتوبر');
  });

  test('fromMap: اليوم من service_date وإلا created_at، والوقت من booking_time_slot', () {
    final sd = Timestamp.fromDate(DateTime(2026, 9, 20));
    final ca = Timestamp.fromDate(DateTime(2026, 9, 1, 10, 30));
    final a = DriverTask.fromMap('a', {'service_date': sd, 'created_at': ca, 'booking_time_slot': '09:30'});
    expect(a.when, DateTime(2026, 9, 20));
    expect(a.timeLabel, '09:30 ص');
    final b = DriverTask.fromMap('b', {'created_at': ca});
    expect(b.when, DateTime(2026, 9, 1, 10, 30));
    expect(b.timeLabel, '10:30 ص', reason: 'ساعة created_at حين لا خانة');
    final c = DriverTask.fromMap('c', {'service_date': sd});
    expect(c.timeLabel, 'غير محدد', reason: 'منتصف الليل بلا خانة = يوم فقط');
    expect(DriverTask.fromMap('d', {'booking_time_slot': '14:00', 'service_date': sd}).timeLabel, '02:00 م');
    expect(DriverTask.fromMap('e', const {}, fallback: DateTime(2026, 1, 1)).when, DateTime(2026, 1, 1));
    expect(c.serviceName, 'خدمة زيارة');
    expect(c.status, 'pending');
  });

  test('merge بلا تكرار، وinRange شامل لليوم الأخير، وbucket مرتّب بالوقت', () {
    final x = t('x', DateTime(2026, 9, 16, 9));
    final merged = DriverSchedule.merge([x], [t('x', DateTime(2000)), t('y', DateTime(2026, 9, 18, 23, 59))]);
    expect(merged.map((e) => e.id).toList(), ['x', 'y']);
    expect(merged.first.when.year, 2026, reason: 'الأول يغلب');

    final inRange = DriverSchedule.inRange(merged, DateTime(2026, 9, 12), DateTime(2026, 9, 18));
    expect(inRange.length, 2);
    expect(DriverSchedule.inRange(merged, DateTime(2026, 9, 12), DateTime(2026, 9, 17)).length, 1);

    final byDay = DriverSchedule.bucket([
      t('late', DateTime(2026, 9, 16, 16)),
      t('early', DateTime(2026, 9, 16, 8)),
      t('other', DateTime(2026, 9, 17)),
    ]);
    expect(byDay[DateTime(2026, 9, 16)]!.map((e) => e.id).toList(), ['early', 'late']);
    expect(byDay[DateTime(2026, 9, 17)]!.length, 1);
    expect(byDay[DateTime(2026, 9, 18)], isNull);
  });

  test('kpis: المجدولة بلا الملغاة، المنجزة المكتملة، المتبقية الفرق', () {
    final k = DriverSchedule.kpis([
      t('1', DateTime(2026, 9, 16), status: 'completed'),
      t('2', DateTime(2026, 9, 16), status: 'scheduled'),
      t('3', DateTime(2026, 9, 16), status: 'in_progress'),
      t('4', DateTime(2026, 9, 16), status: 'cancelled'),
    ]);
    expect(k.scheduled, 3);
    expect(k.done, 1);
    expect(k.remaining, 2);
  });
}
