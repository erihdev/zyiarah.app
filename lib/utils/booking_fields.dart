/// حقولُ الحجزِ المشتقّةُ من موعدٍ اختارَه الأدمنُ، وأعلامُ التذكيرِ التي
/// يَلزمُ تصفيرُها معه — قاعدةٌ واحدةٌ لكلِّ سطحٍ يُحرّكُ موعداً.
///
/// **سببُ وجودِها:** `service_date` ليس وحدَه ما يُقرأُ من الموعد. ثلاثةُ
/// قُرّاءٍ خادميّينَ يَقرآنِ حقولاً **مشتقّةً** منه:
///
///   • `capacity.js` يَعُدُّ الطلبَ مشغولاً **من `booking_date` و
///     `booking_time_slot`** — لا من `service_date`. فتركُهما على اليومِ
///     القديمِ يَعني أنّ الطلبَ **يَستهلكُ سعةَ يومٍ لم يَعُدْ له** ولا
///     يَستهلكُ شيئاً من يومِه الجديد: الأوّلُ يُعرَضُ ممتلئاً بلا طلب،
///     والثاني يُباعُ أكثرَ من طاقتِه.
///   • و`booking_time_slot` هو **الساعةُ المعروضةُ** في بطاقةِ العميلةِ
///     وبطاقةِ السائقِ وفي نصِّ التذكير، فبقاؤه يُظهرُ ساعةً غيرَ الموعد.
///   • و`remindClientsUpcomingAppointments` يَتخطّى الطلبَ متى كان
///     `client_reminder_24h_sent`/`client_reminder_soon_sent` صحيحاً —
///     و`realAppointment` فيه هو `is_paid === true || driverAssigned`، أي
///     أنّ طلباً **مدفوعاً بلا سائق** يُذكَّرُ عنه ويُوسَمُ العلَم. فموعدٌ
///     يُحرَّكُ بعدَ ذلك بلا تصفيرٍ **لا تذكيرَ له أبداً**.
///
/// والقاعدةُ كانت مُنفَّذةً في اثنَين من أربعةِ كُتّاب: `rescheduleAssignedOrder`
/// خادميّاً و`admin_order_details_screen` (إنلاين)، بينما
/// `approveAndAssignOrder` يَكتبُ حقلَي الحجزِ **ولا يُصفّرُ الأعلام**، ولوحةُ
/// الويبِ تَكتبُ `service_date`/`scheduled_at` وحدَهما.
///
/// **والمُدخَلُ ساعةُ حائطٍ لا لحظةٌ مطلقة، وذاك مقصود:** الخادمُ يَشتقُّ
/// بـ`riyadhBookingFields` من لحظةٍ، لكنّ ما يَصلُه هو `scheduledIso` نصّاً
/// ساذجاً و`parseKsaIso` يَقرأُ الساذجَ **بتوقيتِ الرياض**. فالأدمنُ حين
/// يَختارُ «14:00» يَقصدُها رياضاً والخادمُ يَفهمُها رياضاً — فالاشتقاقُ من
/// مكوّناتِ ما اختارَه يُطابقُ الخادمَ بالضبطِ ولا يَتأثّرُ بمنطقةِ جهازِه.
library;

/// `booking_date` بصيغة `YYYY-MM-DD` كما يَقرؤها `capacity.js`.
String bookingDateOf(DateTime chosen) =>
    '${chosen.year.toString().padLeft(4, '0')}-'
    '${chosen.month.toString().padLeft(2, '0')}-'
    '${chosen.day.toString().padLeft(2, '0')}';

/// `booking_time_slot` بصيغة `HH:00` — ٢٤ ساعةً، وهي الصيغةُ المخزَّنةُ
/// التي يُحوّلُها `lib/utils/time_format.dart` عند العرض.
String bookingTimeSlotOf(DateTime chosen) =>
    '${chosen.hour.toString().padLeft(2, '0')}:00';

/// أعلامُ التذكيرِ التي يَلزمُ تصفيرُها مع كلِّ تحريكِ موعد.
const List<String> kReminderFlags = [
  'reminder_sent',
  'client_reminder_24h_sent',
  'client_reminder_soon_sent',
];

/// الحِمْلُ الكاملُ لتحريكِ موعدٍ: الحقلانِ المشتقّانِ + تصفيرُ الأعلام.
/// (`service_date`/`scheduled_at` يَكتبُهما المُنادي، فهما قيمتُه لا مُشتقّة.)
Map<String, dynamic> rescheduleDerivedFields(DateTime chosen) => {
      'booking_date': bookingDateOf(chosen),
      'booking_time_slot': bookingTimeSlotOf(chosen),
      for (final f in kReminderFlags) f: false,
    };
