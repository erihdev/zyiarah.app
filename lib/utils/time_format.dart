/// عرض الوقت بنظام 12 ساعة — **عرضاً فقط، لا تخزيناً.**
///
/// **قاعدة صارمة:** `booking_time_slot` يبقى مخزَّناً بصيغة 24 ساعة (`"HH:00"`).
/// الدالة الخادمية تحلّله بـ `parseInt(slot.split(":")[0])` لتعدّ السعة وتكشف
/// التداخل الزمني — فلو خُزِّن `"3:00 م"` لقرأته **3 صباحاً**، وانهار حساب السعة
/// بصمت: سلوت المساء يُحسب على الفجر، فتُقبل حجوزات لا سائق لها.
///
/// لذلك: التخزين 24، والعرض عبر هذه الدوال وحدها.
library;

/// يحوّل ساعة (0–23) إلى نص عربي بنظام 12 ساعة: `8` → «8:00 ص»، `15` → «3:00 م».
String formatHour12(int hour24) {
  final h = hour24 % 24;
  final period = h < 12 ? 'ص' : 'م';
  // 0 و12 يُعرضان 12 لا 0: منتصف الليل «12:00 ص» والظهر «12:00 م».
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display:00 $period';
}

/// يحوّل خانة مخزَّنة (`"HH:00"` أو `"HH:mm"`) إلى نص 12 ساعة.
/// يُعيد النصّ كما هو إن تعذّر التحليل — لا يُخفي بياناً لا يفهمه.
String formatSlot12(String? slot) {
  if (slot == null || slot.isEmpty) return '';
  final parts = slot.split(':');
  final h = int.tryParse(parts.first);
  if (h == null || h < 0 || h > 23) return slot;
  final minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  if (minutes == 0) return formatHour12(h);
  final period = h < 12 ? 'ص' : 'م';
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display:${minutes.toString().padLeft(2, '0')} $period';
}

/// مدى زمني: «8:00 ص – 12:00 م».
String formatRange12(int startHour, int endHour) =>
    '${formatHour12(startHour)} – ${formatHour12(endHour)}';
