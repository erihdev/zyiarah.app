import 'package:flutter/material.dart';

class ZyiarahStatus {
  // General Order Statuses
  static Map<String, dynamic> getOrderStatus(String status) {
    switch (status) {
      case 'pending':
        return {'text': 'قيد الانتظار', 'color': Colors.orange};
      case 'awaiting_payment':
        return {'text': 'بانتظار الدفع', 'color': Colors.amber};
      case 'under_review':
        return {'text': 'تحت المراجعة', 'color': Colors.deepOrange};
      case 'assigned':
        return {'text': 'تم التعيين', 'color': Colors.blue};
      case 'scheduled':
        return {'text': 'مجدول', 'color': Colors.teal};
      case 'on_the_way':
        return {'text': 'في الطريق', 'color': Colors.cyan};
      case 'accepted':
      case 'in_progress':
        return {'text': 'جاري التنفيذ', 'color': Colors.purple};
      case 'completed':
        return {'text': 'مكتمل', 'color': Colors.green};
      case 'cancelled':
        return {'text': 'ملغي', 'color': Colors.red};
      default:
        return {'text': status, 'color': Colors.grey};
    }
  }

  // Consistent Colors
  static const Color primaryPurple = Color(0xFF660033);
  static const Color adminNavy = Color(0xFF1E293B);
}
