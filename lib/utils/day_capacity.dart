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
