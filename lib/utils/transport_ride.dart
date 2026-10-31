/// رحلاتُ نقلِ العاملاتِ عبر «مواصلات» — قراءةُ ما يَكتبُه الخادمُ على الطلب.
///
/// الخادمُ (`functions/transport.js`) يَكتبُ على مستندِ الطلبِ خريطةً
/// `transport` فيها ساقانِ: `outbound` (من المقرِّ إلى العميلة) و`return`
/// (العودة). كلُّ ساقٍ: `state`, `gen`, `provider`, `provider_ride_id`,
/// `pickup_at`, `driver{name,phone,plate}`, `eta_minutes`, `error`.
///
/// هذه الوحدةُ **قراءةٌ صِرفة** لتلك الخريطةِ بمفرداتٍ عربيّةٍ وألوانٍ، تَشترك
/// فيها شاشةُ الإدارةِ وشاشةُ العاملة، وتُختبَرُ بلا Firebase. لا كتابةَ هنا:
/// قواعدُ Firestore تَحصرُ ما تَكتبُه العاملةُ على طلبِها في حقولِ التنفيذ
/// (`hasOnly`)، فحقولُ الرحلةِ خادميّةٌ وحدَها.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// الحالاتُ الحيّةُ — مرآةُ `LIVE_STATES` في `functions/transport.js`.
const Set<String> kTransportLiveStates = {
  'requesting',
  'requested',
  'accepted',
  'en_route',
  'arrived',
};

/// الحالاتُ النهائيّةُ — مرآةُ `FINAL_STATES` هناك.
const Set<String> kTransportFinalStates = {'completed', 'cancelled', 'failed'};

/// ساقٌ واحدةٌ من رحلةِ النقلِ كما يَعرضُها التطبيق.
class TransportLegView {
  const TransportLegView({
    required this.leg,
    required this.state,
    this.driverName,
    this.driverPhone,
    this.driverPlate,
    this.pickupAt,
    this.etaMinutes,
    this.error,
  });

  /// `outbound` أو `return`.
  final String leg;
  final String state;
  final String? driverName;
  final String? driverPhone;
  final String? driverPlate;
  final DateTime? pickupAt;
  final int? etaMinutes;
  final String? error;

  /// يَقرأُ ساقاً من خريطةِ الطلب؛ `null` إن لم تُطلَب بعد.
  static TransportLegView? fromOrder(Map<String, dynamic> order, String leg) {
    final t = order['transport'];
    if (t is! Map) return null;
    final raw = t[leg];
    if (raw is! Map) return null;
    final state = raw['state'];
    if (state is! String || state.isEmpty) return null;
    final d = raw['driver'];
    final pickup = raw['pickup_at'];
    final eta = raw['eta_minutes'];
    return TransportLegView(
      leg: leg,
      state: state,
      driverName: d is Map ? _nonEmpty(d['name']) : null,
      driverPhone: d is Map ? _nonEmpty(d['phone']) : null,
      driverPlate: d is Map ? _nonEmpty(d['plate']) : null,
      pickupAt: pickup is Timestamp ? pickup.toDate() : null,
      etaMinutes: eta is num ? eta.toInt() : null,
      error: _nonEmpty(raw['error']),
    );
  }

  static String? _nonEmpty(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  bool get isLive => kTransportLiveStates.contains(state);
  bool get isFinal => kTransportFinalStates.contains(state);

  /// هل يُعرَضُ زرُّ «إعادة الطلب» للإدارة؟ فشلٌ أو إلغاءٌ فقط — لا على
  /// رحلةٍ حيّةٍ (فالإعادةُ تُلغيها) ولا على مكتملة.
  bool get canRetry => state == 'failed' || state == 'cancelled';

  String get legLabel => leg == 'outbound' ? 'الذهاب' : 'العودة';

  /// النصُّ العربيُّ للحالة — لا حرفَ لاتينيّاً خامّاً في واجهةٍ عربيّة.
  String get stateLabel => transportStateLabel(state);

  Color get stateColor => transportStateColor(state);

  /// سطرُ السائقِ كما يُعرَض: «سالم — أ ب ج 123»، أو null إن لم يُعيَّن بعد.
  String? get driverLine {
    if (driverName == null && driverPlate == null) return null;
    return [driverName, driverPlate].whereType<String>().join(' — ');
  }
}

/// تسميةُ الحالة.
String transportStateLabel(String state) {
  return switch (state) {
    'requesting' => 'جارٍ الطلب',
    'requested' => 'بانتظار سائق',
    'accepted' => 'سائق مؤكّد',
    'en_route' => 'السائق في الطريق',
    'arrived' => 'السائق وصل',
    'completed' => 'اكتملت',
    'cancelled' => 'أُلغيت',
    'failed' => 'تعذّر الطلب',
    _ => 'غير معروفة',
  };
}

/// لونُ الحالة.
Color transportStateColor(String state) {
  return switch (state) {
    'requesting' || 'requested' => const Color(0xFFD97706),
    'accepted' || 'en_route' || 'arrived' => const Color(0xFF2563EB),
    'completed' => const Color(0xFF16A34A),
    'cancelled' => const Color(0xFF6B7280),
    'failed' => const Color(0xFFDC2626),
    _ => const Color(0xFF6B7280),
  };
}
