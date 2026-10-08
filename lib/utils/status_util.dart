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

  // **لا لونَ هنا.** كانت `primaryPurple = 0xFF660033` و
  // `adminNavy = 0xFF1E293B` معلَّقتَين تحتَ «Consistent Colors» **بلا
  // قارئٍ واحد**، ولونُ العلامةِ له موضعُه (`ZyiarahTheme.brand`) — فنسخةٌ
  // ثالثةٌ في وحدةِ تسمياتِ الحالاتِ ليست من شأنِها، ولا تُورِثُ اتّساقاً
  // لا يَقرؤه أحد. (2026-10-08، حين وُسِّعَ `no_dead_code_test` إلى الحقول.)
}
