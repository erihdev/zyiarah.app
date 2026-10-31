/// إعداداتُ نقلِ العاملاتِ (مواصلات) — `system_configs/transport`.
///
/// الخادمُ يَقرأُ هذا المستندَ (`transport.normalizeConfig` في
/// `functions/transport.js`): `enabled`, `provider` (`mowasalat` |
/// `simulator`), `hq_location` (GeoPoint المقرّ)، `hq_label`,
/// `lead_minutes` (قبلَ الموعدِ بكم دقيقةً تَنطلقُ السيارة)،
/// `api_base_url`. المفتاحُ السرّيُّ وتوقيعُ الويب هوك **ليسا هنا** — في
/// Secret Manager — لأنّ المستندَ مقروءٌ لكلِّ مسجَّل.
///
/// هذه الوحدةُ هي **البوّابةُ الوحيدةُ** التي تَبني المستندَ من نصوصِ
/// المحرِّر: الفراغُ قرارٌ (مهلةٌ افتراضيّة، عنوانٌ يُترَكُ للمحاكي) وخطأُ
/// الكتابةِ ليس قراراً (إحداثيٌّ لا يَنحلُّ إلى رقمٍ يُرفَضُ باسمِه لا يُبتلَع)
/// — قاعدةُ `catalog_number.dart` على محرِّراتِ الإدارة.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/utils/catalog_number.dart';

/// مهلةُ الانطلاقِ الافتراضيّةُ — مرآةُ `DEFAULT_LEAD_MINUTES` في الخادم.
const int kTransportDefaultLeadMinutes = 45;

/// مزوّدا النقلِ اللذانِ يَعرفُهما الخادم.
const List<String> kTransportProviders = ['mowasalat', 'simulator'];

/// ناتجُ البناء: مستندٌ صالحٌ، أو خطأٌ باسمِ الحقل.
class TransportSettingsResult {
  const TransportSettingsResult._({this.payload, this.error});
  final Map<String, dynamic>? payload;
  final String? error;
  bool get ok => payload != null;
}

/// يَبني مستندَ الإعداداتِ من حقولِ المحرِّر.
///
/// - `lat`/`lng`: يُقبَلانِ عربيَّ الأرقام، وفارغانِ معاً يَعنيانِ «لا مقرَّ
///   بعد» (مقبولٌ ما دام النقلُ مُطفأً؛ وعندَ التفعيلِ مرفوض، لأنّ الخادمَ
///   سيَكتبُ `failed` على كلِّ طلبٍ بسببِ «لا موقعَ مقرٍّ»).
/// - `leadMinutes`: فارغٌ ⇒ الافتراضيّ؛ غيرُ رقمٍ أو صفرٌ ⇒ مرفوض.
/// - `baseUrl`: مع مواصلات وعندَ التفعيلِ مطلوبٌ ويَبدأُ بـ`https://`.
TransportSettingsResult transportSettingsPayload({
  required bool enabled,
  required String provider,
  required String lat,
  required String lng,
  required String label,
  required String leadMinutes,
  required String baseUrl,
}) {
  if (!kTransportProviders.contains(provider)) {
    return const TransportSettingsResult._(error: 'مزوّد النقل غير معروف');
  }
  final latT = normalizeDigits(lat);
  final lngT = normalizeDigits(lng);
  GeoPoint? hq;
  if (latT.isNotEmpty || lngT.isNotEmpty) {
    final la = double.tryParse(latT);
    final ln = double.tryParse(lngT);
    if (la == null || !la.isFinite || la < -90 || la > 90) {
      return const TransportSettingsResult._(error: 'خط عرض المقرّ غير صالح');
    }
    if (ln == null || !ln.isFinite || ln < -180 || ln > 180) {
      return const TransportSettingsResult._(error: 'خط طول المقرّ غير صالح');
    }
    hq = GeoPoint(la, ln);
  }
  if (enabled && hq == null) {
    return const TransportSettingsResult._(
        error: 'موقع المقرّ مطلوب قبل تفعيل النقل');
  }
  final lead =
      optionalInt(leadMinutes, whenEmpty: kTransportDefaultLeadMinutes);
  if (lead == null || lead <= 0) {
    return const TransportSettingsResult._(
        error: 'مهلة الانطلاق يجب أن تكون عدد دقائق أكبر من صفر');
  }
  final url = baseUrl.trim();
  if (enabled && provider == 'mowasalat' && !url.startsWith('https://')) {
    return const TransportSettingsResult._(
        error: 'عنوان واجهة مواصلات مطلوب ويبدأ بـ https://');
  }
  return TransportSettingsResult._(payload: {
    'enabled': enabled,
    'provider': provider,
    'hq_location': hq,
    'hq_label': label.trim().isEmpty ? 'مقر المؤسسة' : label.trim(),
    'lead_minutes': lead,
    'api_base_url': url,
  });
}
