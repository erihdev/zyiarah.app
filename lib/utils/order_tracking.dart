// «هل يُتتبَّع هذا الطلب؟» — سؤالٌ واحد، جوابٌ واحد، في مكانٍ واحد.
//
// وُجد بتشغيل التطبيق بحسابٍ حقيقيّ (2026-10-04): أربعُ زياراتِ اشتراكٍ مواعيدُها
// في **يوليو** ما زالت تحت «الطلبات النشطة» بحالة «مجدول»، وكلٌّ منها يعرض زرّ
// «تتبع السائق» — بينما البطاقةُ نفسُها تقول فوقه «انتهى الموعد». وضغطُه يقول
// «لم يُعيَّن سائق بعد، يُرجى الانتظار» لزيارةٍ فات موعدُها بثلاثة أشهر.
//
// والأدهى أنّ هذا العطلَ **عُولج مرّةً وبقي**: تعليقُ `orders_list_screen` يسجّل
// «كان زرّ تتبع السائق يظهر ويقول لم يُعيَّن سائق بعد للأبد»، لكنّ العلاج كُتب
// تعداداً لحالتين (`under_review`، و`in_progress` بلا سائق) بدل أن يُكتب قاعدةً.
// فحالةُ `scheduled` بلا سائق — وهي ما رأيته — ظلّت خارج التعداد.
//
// القاعدةُ هنا ليست حالةَ الطلب: التتبّعُ ممكنٌ متى **وُجد سائقٌ وموقع**، وإلّا
// فلا. وهي القاعدةُ التي كانت مكتوبةً أصلاً داخل `onPressed` — في المكان الخطأ:
// تحرس الضغطةَ بدل أن تحرس ظهورَ الزرّ.
library;

/// يُتتبَّع الطلب متى كان له سائقٌ **وموقع**. ما عدا ذلك فالزرّ وعدٌ كاذب.
bool canTrackOrder(Map<String, dynamic> order) =>
    order['driver_id'] != null && order['location'] != null;

/// موعدُ الخدمة من الطلب: `service_date` أوّلاً، ثمّ `booking_date` مع
/// `booking_time_slot`. يُعيد `null` حين لا موعدَ محدّداً.
///
/// الوسائطُ أنواعٌ عاديّة لا مستندُ Firestore، كي تُختبر بلا محاكٍ.
DateTime? orderAppointment({
  DateTime? serviceDate,
  String? bookingDate,
  String? bookingTimeSlot,
}) {
  if (serviceDate != null) return serviceDate;
  if (bookingDate == null || bookingDate.isEmpty) return null;
  final String t = (bookingTimeSlot == null || bookingTimeSlot.length != 5)
      ? '00:00'
      : bookingTimeSlot;
  try {
    return DateTime.parse('${bookingDate}T$t:00');
  } catch (_) {
    return null;
  }
}

/// هل فات الموعد؟ **بدقّة اليوم** لا الدقيقة — موعدُ اليوم في الثامنة صباحاً
/// ليس «فائتاً» في العاشرة: الكادرُ قد يكون في الطريق، والزيارةُ قائمة.
bool appointmentPassed(DateTime? appt, DateTime now) {
  if (appt == null) return false;
  final a = DateTime(appt.year, appt.month, appt.day);
  final n = DateTime(now.year, now.month, now.day);
  return a.isBefore(n);
}

/// نصُّ الشارة البديلة حين يتعذّر التتبّع — كلٌّ يقول سببَه الحقيقيّ.
String trackingUnavailableLabel({
  required String status,
  required bool passed,
}) {
  if (status == 'under_review') return 'تحت المراجعة — تصلك الإشعارات';
  if (status == 'in_progress') return 'جاري التنفيذ';
  // فات الموعد ولا سائق: «انتظري» كذبة — لم يعد هناك ما يُنتظر.
  if (passed) return 'انتهى الموعد — تواصلي مع الدعم';
  return 'لم يُعيَّن سائق بعد';
}
