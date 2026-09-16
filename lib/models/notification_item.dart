import 'package:cloud_firestore/cloud_firestore.dart';

/// تصنيف إشعارات العميل لشرائح التصفية (تصميم Stitch «مركز التنبيهات»، 2026-09-16).
enum NotificationCategory { orders, payments, offers, other }

/// إشعار داخل التطبيق من مجموعة `notifications` كما يكتبه الخادم:
/// `type` من {order_update, order_assignment, payment_update, payment, refund,
/// referral_reward, qatrat_reward, qatrat_redeem, global_broadcast, …}،
/// و`relatedId` معرّف مستند الطلب غالباً (وفي مسار notification_triggers قد
/// يكون كود الطلب أو معرّف المشغّل)، والوقت في `sentAt` أو `created_at`.
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime? createdAt;
  final bool isRead;
  final String? relatedId;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.relatedId,
  });

  NotificationCategory get category => categoryOf(type);

  /// التصنيف من `type` بالمفردات لا بقائمة مغلقة — أنواع الخادم تتغيّر، وكانت
  /// بطاقة الإشعار تطابق أسماءً (order_assigned/promo) لا يكتبها الخادم أصلاً.
  static NotificationCategory categoryOf(String type) {
    final t = type.toLowerCase();
    if (t.contains('promo') ||
        t.contains('broadcast') ||
        t.contains('offer') ||
        t.contains('coupon')) {
      return NotificationCategory.offers;
    }
    if (t.contains('pay') ||
        t.contains('refund') ||
        t.contains('invoice') ||
        t.contains('wallet') ||
        t.contains('qatrat') ||
        t.contains('reward') ||
        t.contains('referral') ||
        t.contains('subscription') ||
        t.contains('contract')) {
      return NotificationCategory.payments;
    }
    if (t.contains('order') || t.contains('driver') || t.contains('visit')) {
      return NotificationCategory.orders;
    }
    return NotificationCategory.other;
  }

  static String labelOf(NotificationCategory c) => switch (c) {
        NotificationCategory.orders => 'الطلبات والميدان',
        NotificationCategory.payments => 'المدفوعات والمكافآت',
        NotificationCategory.offers => 'العروض والتعميمات',
        NotificationCategory.other => 'أخرى',
      };

  /// هل `relatedId` معرّف مستند طلب يصلح لمسار التتبّع `/track/:orderId`؟
  /// كود الطلب (ZY-…) أو معرّف مشغّل (trig_…) ليسا مستندَي طلب.
  bool get relatedLooksLikeOrderDoc {
    final r = relatedId;
    if (r == null || r.isEmpty) return false;
    if (r.startsWith('ZY-') || r.startsWith('trig_')) return false;
    return r.length >= 15;
  }

  factory NotificationItem.fromMap(String id, Map<String, dynamic> m) {
    final raw = m['created_at'] ?? m['sentAt'] ?? m['sent_at'];
    final related = m['relatedId'] ?? m['related_id'];
    return NotificationItem(
      id: id,
      title: (m['title'] ?? 'إشعار جديد').toString(),
      body: (m['body'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      createdAt: raw is Timestamp ? raw.toDate() : null,
      isRead: m['isRead'] == true || m['is_read'] == true,
      relatedId: related == null || related.toString().isEmpty
          ? null
          : related.toString(),
    );
  }

  factory NotificationItem.fromDoc(DocumentSnapshot d) =>
      NotificationItem.fromMap(d.id, (d.data() as Map<String, dynamic>?) ?? const {});

  /// الأحدث أولاً؛ بلا وقت آخراً.
  static int newestFirst(NotificationItem a, NotificationItem b) {
    if (a.createdAt == null && b.createdAt == null) return 0;
    if (a.createdAt == null) return 1;
    if (b.createdAt == null) return -1;
    return b.createdAt!.compareTo(a.createdAt!);
  }
}
