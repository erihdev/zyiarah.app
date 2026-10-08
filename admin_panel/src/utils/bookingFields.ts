// حقولُ الحجزِ المشتقّةُ من موعدٍ اختارَه الأدمنُ، وأعلامُ التذكيرِ التي
// يَلزمُ تصفيرُها معه — **مرآةُ `lib/utils/booking_fields.dart`**، وجدولُ
// حالاتِهما مشترَكٌ يَقرؤه `test/booking_fields_test.dart`.
//
// **سببُ وجودِها هنا:** مسارُ «تعديل الزيارة» في `Orders.tsx` بلا سائقٍ كان
// يَكتبُ `service_date`/`scheduled_at` وحدَهما — فحقلا الحجزِ يَبقَيانِ على
// اليومِ القديمِ (و`capacity.js` يَعُدُّ منهما، لا من `service_date`، فيَستهلكُ
// الطلبُ سعةَ يومٍ لم يَعُدْ له ويُباعُ يومُه الجديدُ أكثرَ من طاقتِه، وبطاقةُ
// العميلةِ تَعرضُ الساعةَ القديمة)، وأعلامُ التذكيرِ تَبقى مرفوعةً — و
// `remindClientsUpcomingAppointments` يُذكّرُ طلباً **مدفوعاً بلا سائق**
// (`realAppointment = is_paid === true || driverAssigned`) فالعلَمُ مرفوعٌ
// فعلاً، فلا تذكيرَ للموعدِ الجديدِ أبداً.
//
// والمُشتقُّ من **ساعةِ الحائطِ** التي اختارَها الأدمنُ لا من لحظةٍ مطلقة:
// `scheduledIso` يَصلُ الخادمَ نصّاً ساذجاً و`parseKsaIso` يَقرؤه بتوقيتِ
// الرياض، فالاشتقاقُ من المكوّناتِ يُطابقُ الخادمَ ولا يَتأثّرُ بمنطقةِ
// المتصفّح.

/** `booking_date` بصيغة `YYYY-MM-DD` كما يقرؤها `capacity.js`. */
export function bookingDateOf(chosen: Date): string {
    const p = (n: number, w = 2) => String(n).padStart(w, '0');
    return `${p(chosen.getFullYear(), 4)}-${p(chosen.getMonth() + 1)}-${p(chosen.getDate())}`;
}

/** `booking_time_slot` بصيغة `HH:00` — ٢٤ ساعةً، وهي الصيغة المخزَّنة. */
export function bookingTimeSlotOf(chosen: Date): string {
    return `${String(chosen.getHours()).padStart(2, '0')}:00`;
}

/** أعلام التذكير التي يلزم تصفيرها مع كل تحريك موعد. */
export const REMINDER_FLAGS = [
    'reminder_sent',
    'client_reminder_24h_sent',
    'client_reminder_soon_sent',
] as const;

/**
 * الحِمْل الكامل لتحريك موعد: الحقلان المشتقّان + تصفير الأعلام.
 * (`service_date`/`scheduled_at` يكتبهما المنادي، فهما قيمته لا مشتقّة.)
 */
export function rescheduleDerivedFields(chosen: Date): Record<string, unknown> {
    const out: Record<string, unknown> = {
        booking_date: bookingDateOf(chosen),
        booking_time_slot: bookingTimeSlotOf(chosen),
    };
    for (const f of REMINDER_FLAGS) out[f] = false;
    return out;
}
