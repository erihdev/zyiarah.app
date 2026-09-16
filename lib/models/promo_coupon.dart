import 'package:cloud_firestore/cloud_firestore.dart';

/// كوبون خصم من مجموعة `promo_codes` كما يراه العميل في قسم «العروض».
///
/// (تصميم Stitch، 2026-09-16) الكوبونات كانت تُدخَل يدوياً عند الدفع فقط؛
/// لم يكن للعميل مكان يراها فيه. الشرطان هنا يطابقان ما يفحصه
/// ZyiarahOrderService.validateCoupon (الحالة، الانتهاء، سقف الاستخدام،
/// المستخدم المستهدَف) كي لا يُعرض للعميل كودٌ سيُرفض عند الدفع — مع فارق
/// واحد: قيد المناطق يُعرض شريحةً لا يُخفي البند، فالمنطقة تُحسم عند الحجز.
class PromoCoupon {
  final String id;
  final String code;

  /// 'percentage' أو 'fixed' (ريال).
  final String type;
  final num value;
  final int maxUses;
  final int uses;
  final DateTime? expiry;
  final String status;
  final List<String> restrictedZones;

  /// كوبون موجَّه لمستخدم بعينه (إحالة/هدية) — يراه هو وحده.
  final String? targetUserId;

  /// قرار التسويق: يظهر في قسم العروض. الغياب = لا، كي لا يُكشف كود قناةٍ
  /// خاصة (شريك/مؤثّر) لعموم العملاء بمجرّد ترقية التطبيق.
  final bool showInOffers;
  final String description;

  const PromoCoupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.maxUses,
    required this.uses,
    required this.expiry,
    required this.status,
    required this.restrictedZones,
    required this.targetUserId,
    required this.showInOffers,
    required this.description,
  });

  static const String collectionPath = 'promo_codes';

  factory PromoCoupon.fromMap(String id, Map<String, dynamic> m) {
    final rawExpiry = m['expiry'];
    DateTime? expiry;
    if (rawExpiry is Timestamp) {
      expiry = rawExpiry.toDate();
    } else if (rawExpiry is String) {
      expiry = DateTime.tryParse(rawExpiry);
    }
    final rawZones = m['restricted_zones'];
    final target = m['target_user_id'];
    return PromoCoupon(
      id: id,
      code: (m['code'] ?? '').toString(),
      type: m['type'] == 'fixed' ? 'fixed' : 'percentage',
      value: m['value'] is num ? m['value'] as num : 0,
      maxUses: (m['maxUses'] as num?)?.toInt() ?? 0,
      uses: (m['uses'] as num?)?.toInt() ?? 0,
      expiry: expiry,
      status: (m['status'] ?? '').toString(),
      restrictedZones: rawZones is List
          ? rawZones.map((z) => z.toString()).toList()
          : const [],
      targetUserId: target is String && target.isNotEmpty ? target : null,
      showInOffers: m['show_in_offers'] == true,
      description: (m['description'] ?? '').toString(),
    );
  }

  factory PromoCoupon.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      PromoCoupon.fromMap(d.id, d.data() ?? const {});

  static List<PromoCoupon> fromQuery(QuerySnapshot<Map<String, dynamic>> q) =>
      q.docs.map(PromoCoupon.fromDoc).toList();

  bool get isPercentage => type == 'percentage';

  /// «خصم 25%» أو «خصم 40 ر.س» — بلا كسور عشرية زائدة.
  String get headline {
    final v = value == value.truncate() ? value.toInt().toString() : value.toString();
    return isPercentage ? 'خصم $v%' : 'خصم $v ر.س';
  }

  bool get isActive => status == 'active';
  bool get isExhausted => maxUses > 0 && uses >= maxUses;
  bool isExpiredAt(DateTime now) => expiry != null && expiry!.isBefore(now);
  bool isPersonalFor(String? uid) => targetUserId != null && targetUserId == uid;

  /// هل يُعرض لهذا المستخدم في قسم العروض؟
  bool isListableFor(String? uid, DateTime now) {
    if (!isActive || isExpiredAt(now) || isExhausted || code.isEmpty) {
      return false;
    }
    if (targetUserId != null) return isPersonalFor(uid);
    return showInOffers;
  }

  /// القائمة المعروضة: الشخصي أولاً، ثم الأقرب انتهاءً (بلا انتهاء آخراً).
  static List<PromoCoupon> listableFor(
      Iterable<PromoCoupon> all, String? uid, DateTime now) {
    final list = all.where((c) => c.isListableFor(uid, now)).toList()
      ..sort((a, b) {
        final pa = a.isPersonalFor(uid) ? 0 : 1;
        final pb = b.isPersonalFor(uid) ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        if (a.expiry == null && b.expiry == null) return a.code.compareTo(b.code);
        if (a.expiry == null) return 1;
        if (b.expiry == null) return -1;
        return a.expiry!.compareTo(b.expiry!);
      });
    return list;
  }
}
