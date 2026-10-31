/// هل اليوم ممتلئ؟ (قرار المالك 2026-09-16)
///
/// السقف العام للنشاط كله أولاً (السائقون بلا مناطق فالسعة رقم واحد للجميع)،
/// ثم سقف المنطقة الخاص إن ضبطته الإدارة على مستند المنطقة — يضيّق فقط ولا
/// يوسّع أبداً، فلا يُحجز يومٌ فوق السعة الحقيقية مهما كان سقف المنطقة.
/// [zoneMax] غائب أو صفر = لا سقف خاص.
bool dayIsFull({
  required int count,
  required int max,
  int zoneCount = 0,
  int? zoneMax,
}) {
  if (count >= max) return true;
  if (zoneMax != null && zoneMax > 0 && zoneCount >= zoneMax) return true;
  return false;
}

/// هل في الساعة مكانٌ لطلبٍ يَحتاجُ [need] عاملة؟ (قرار المالك 2026-10-31)
///
/// السعةُ عددُ العاملاتِ المتوفّرات، والكادرُ عاملةٌ واحدة: الخادمُ يَعدُّ في
/// `slotCounts` **العاملاتِ** المحجوزاتِ في الساعة (`functions/capacity.js`)،
/// و[max] (`maxTeamsPerSlot`) عددُ العاملاتِ المسجّلات. فطلبٌ بكادرَين لا يَكفيه
/// أن تبقى عاملةٌ واحدة — كان الفحصُ `used >= max` يُعرِضُ ساعةً بعاملةٍ فارغةٍ
/// لطلبٍ يَحتاجُ ثلاثاً، فتَدفعُ العميلةُ ثمّ لا يَجدُ المُسنِدُ الفريقَ كاملاً.
/// [max] صفرٌ أو أقلّ ⇒ لا فريق، فلا مكان.
bool slotHasRoom({required int used, required int max, int need = 1}) {
  if (max <= 0) return false;
  final n = need < 1 ? 1 : need;
  return used + n <= max;
}
