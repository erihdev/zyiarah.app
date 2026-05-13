import 'package:flutter/material.dart';

class ZyiarahStatus {
  // Maintenance Statuses
  static Map<String, dynamic> getMaintenanceStatus(String status) {
    switch (status) {
      case 'under_review':
        return {'text': 'تحت المراجعة', 'color': Colors.orange, 'step': 0};
      case 'waiting_payment':
      case 'waiting_payment_cod':
        return {'text': 'بانتظار الدفع', 'color': Colors.blue, 'step': 1};
      case 'approved':
      case 'paid':
      case 'in_progress':
        return {'text': 'جاري التنفيذ', 'color': Colors.indigo, 'step': 2};
      case 'completed':
        return {'text': 'مكتمل', 'color': Colors.green, 'step': 3};
      case 'rejected':
        return {'text': 'مرفوض', 'color': Colors.red, 'step': -1};
      default:
        return {'text': 'تحت المراجعة', 'color': Colors.orange, 'step': 0};
    }
  }

  // General Order Statuses
  static Map<String, dynamic> getOrderStatus(String status) {
    switch (status) {
      case 'pending':
        return {'text': 'قيد الانتظار', 'color': Colors.orange};
      case 'assigned':
        return {'text': 'تم التعيين', 'color': Colors.blue};
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
  static const Color primaryPurple = Color(0xFF5D1B5E);
  static const Color adminNavy = Color(0xFF1E293B);
}
