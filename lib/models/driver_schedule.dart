import 'package:cloud_firestore/cloud_firestore.dart';

/// مهمّة سائق كما تُقرأ من وثيقة الطلب لجدول المناوبات.
///
/// اليوم من `service_date` (وإلا `created_at`)، والساعة من `booking_time_slot`
/// («09:00») حين تكتبه شاشة الحجز، وإلا من ساعة `service_date` إن لم تكن
/// منتصف الليل.
class DriverTask {
  final String id;
  final String code;
  final String serviceName;
  final String clientName;
  final String zoneName;
  final String status;
  final DateTime when;
  final String? timeSlot;

  const DriverTask({
    required this.id,
    required this.code,
    required this.serviceName,
    required this.clientName,
    required this.zoneName,
    required this.status,
    required this.when,
    required this.timeSlot,
  });

  factory DriverTask.fromMap(String id, Map<String, dynamic> m,
      {DateTime? fallback}) {
    final sd = m['service_date'];
    final ca = m['created_at'];
    final when = sd is Timestamp
        ? sd.toDate()
        : (ca is Timestamp ? ca.toDate() : (fallback ?? DateTime.now()));
    final slot = m['booking_time_slot'];
    return DriverTask(
      id: id,
      code: (m['code'] ?? '-').toString(),
      serviceName:
          (m['service_type'] ?? m['service_name'] ?? 'خدمة زيارة').toString(),
      clientName: (m['client_name'] ?? 'عميل').toString(),
      zoneName: (m['zone_name'] ?? '').toString(),
      status: (m['status'] ?? 'pending').toString(),
      when: when,
      timeSlot: slot is String && slot.trim().isNotEmpty ? slot.trim() : null,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => DriverSchedule.activeStatuses.contains(status);

  /// «09:30 ص» أو 'غير محدد'.
  String get timeLabel {
    int? h;
    int? min;
    final slot = timeSlot;
    if (slot != null) {
      final parts = slot.split(':');
      if (parts.length >= 2) {
        h = int.tryParse(parts[0].trim());
        min = int.tryParse(parts[1].trim().split(' ').first);
        if (slot.contains('م') && h != null && h < 12) h += 12;
      }
    }
    if (h == null) {
      if (when.hour == 0 && when.minute == 0) return 'غير محدد';
      h = when.hour;
      min = when.minute;
    }
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final period = h < 12 ? 'ص' : 'م';
    return '${h12.toString().padLeft(2, '0')}:${(min ?? 0).toString().padLeft(2, '0')} $period';
  }
}

/// حسابات جدول المناوبات (تصميم Stitch «جدول المهام والمناوبات»، 2026-09-16):
/// أسبوع سعودي يبدأ السبت، شبكة شهرية، تجميع بالأيام، ومؤشرات الفترة.
class DriverSchedule {
  static const List<String> activeStatuses = [
    'assigned', 'scheduled', 'accepted', 'on_the_way', 'in_progress',
  ];
  static const List<String> historyStatuses = ['completed', 'cancelled'];

  static const List<String> dayNames = [
    'السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة',
  ];
  static const List<String> monthNames = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  static DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 0 للسبت … 6 للجمعة.
  static int daysSinceSaturday(DateTime d) =>
      (d.weekday - DateTime.saturday + 7) % 7;

  static DateTime weekStart(DateTime d) =>
      dayKey(d).subtract(Duration(days: daysSinceSaturday(d)));

  static List<DateTime> weekDays(DateTime anchor) {
    final start = weekStart(anchor);
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

  /// شبكة الشهر من سبت أسبوعه الأول إلى جمعة أسبوعه الأخير (مضاعفات 7).
  static List<DateTime> monthGrid(DateTime anchor) {
    final start = weekStart(monthStart(anchor));
    final end = weekStart(monthEnd(anchor)).add(const Duration(days: 6));
    final days = end.difference(start).inDays + 1;
    return List.generate(days, (i) => start.add(Duration(days: i)));
  }

  static String dayName(DateTime d) => dayNames[daysSinceSaturday(d)];
  static String monthName(DateTime d) => monthNames[d.month - 1];
  static String dateLabel(DateTime d) => '${dayName(d)} ${d.day} ${monthName(d)}';
  static String weekLabel(DateTime anchor) {
    final days = weekDays(anchor);
    final a = days.first;
    final b = days.last;
    return a.month == b.month
        ? 'أسبوع ${a.day} - ${b.day} ${monthName(a)}'
        : 'أسبوع ${a.day} ${monthName(a)} - ${b.day} ${monthName(b)}';
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// دمج بثّي النشط والسجل بلا تكرار (الأول يغلب).
  static List<DriverTask> merge(Iterable<DriverTask> a, Iterable<DriverTask> b) {
    final seen = <String>{};
    return [
      for (final t in a)
        if (seen.add(t.id)) t,
      for (final t in b)
        if (seen.add(t.id)) t,
    ];
  }

  static List<DriverTask> inRange(
      Iterable<DriverTask> tasks, DateTime start, DateTime endInclusive) {
    final s = dayKey(start);
    final e = dayKey(endInclusive).add(const Duration(days: 1));
    return tasks
        .where((t) => !t.when.isBefore(s) && t.when.isBefore(e))
        .toList();
  }

  static Map<DateTime, List<DriverTask>> bucket(Iterable<DriverTask> tasks) {
    final out = <DateTime, List<DriverTask>>{};
    for (final t in tasks) {
      out.putIfAbsent(dayKey(t.when), () => []).add(t);
    }
    for (final list in out.values) {
      list.sort(byTime);
    }
    return out;
  }

  static int byTime(DriverTask a, DriverTask b) {
    final c = a.when.compareTo(b.when);
    if (c != 0) return c;
    return (a.timeSlot ?? '').compareTo(b.timeSlot ?? '');
  }

  /// المجدولة = كل ما ليس ملغى؛ المنجزة = المكتملة؛ المتبقية = الفرق.
  static ({int scheduled, int done, int remaining}) kpis(
      Iterable<DriverTask> tasks) {
    var scheduled = 0;
    var done = 0;
    for (final t in tasks) {
      if (t.isCancelled) continue;
      scheduled++;
      if (t.isCompleted) done++;
    }
    return (scheduled: scheduled, done: done, remaining: scheduled - done);
  }
}
