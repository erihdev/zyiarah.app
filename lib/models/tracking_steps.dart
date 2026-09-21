import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// مراحل تنفيذ الزيارة في شاشة التتبّع (تصميم Stitch «Live Dispatch Tracker»،
/// 2026-09-16): خمس مراحل تبدأ بـ«تم استلام وتأكيد الطلب» (كانت الأولى «تم
/// تعيين السائق» فلا يرى العميل شيئاً قبل الإسناد)، ولكل مرحلة طابعها الزمني
/// من الحقول التي يكتبها ZyiarahOrderService.updateOrderStatus والخادم.
class TrackingStep {
  final String label;
  final IconData icon;
  final List<String> timeFields;
  const TrackingStep(this.label, this.icon, this.timeFields);
}

class TrackingSteps {
  static const List<TrackingStep> steps = [
    TrackingStep('تم استلام وتأكيد الطلب', Icons.receipt_long_rounded,
        ['paid_at', 'created_at']),
    TrackingStep('تم تعيين السائق', Icons.assignment_ind,
        ['assigned_at', 'accepted_at']),
    TrackingStep('السائق في الطريق', Icons.directions_car, ['on_the_way_at']),
    TrackingStep('وصل السائق وبدأ الخدمة', Icons.cleaning_services,
        ['arrived_at', 'start_time']),
    TrackingStep('تمت المهمة بنجاح', Icons.verified, ['end_time']),
  ];

  /// فهرس المرحلة الحالية من حالة الطلب (بلهجة الإسناد المباشر واللهجة القديمة).
  static int indexFor(String status) {
    switch (status) {
      case 'pending':
      case 'under_review':
        return 0;
      case 'scheduled':
      case 'assigned':
        return 1;
      case 'accepted': // legacy: driver en route
      case 'on_the_way':
        return 2;
      case 'in_progress':
        return 3;
      case 'completed':
        return 4;
      default:
        return -1;
    }
  }

  /// طابع المرحلة من وثيقة الطلب: أول حقل موجود من حقولها.
  static DateTime? timeFor(int index, Map<String, dynamic> data) {
    if (index < 0 || index >= steps.length) return null;
    for (final f in steps[index].timeFields) {
      final v = data[f];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }

  /// «الساعة 02:15 م» لليوم نفسه، وبالتاريخ لغيره.
  static String timeLabel(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour < 12 ? 'ص' : 'م';
    String two(int x) => x.toString().padLeft(2, '0');
    final clock = '${two(h12)}:${two(t.minute)} $period';
    final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
    return sameDay ? 'الساعة $clock' : '${t.year}/${two(t.month)}/${two(t.day)} $clock';
  }
}
