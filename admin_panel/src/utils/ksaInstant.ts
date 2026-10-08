// **مرآةُ `lib/utils/ksa_instant.dart`** — لحظةُ الموعدِ من ساعةِ حائطٍ
// سعوديّةٍ لا من منطقةِ المتصفّح.
//
// القرارُ واحدٌ، والتعليلُ كاملٌ في الأصلِ الدارتيّ. وخلاصتُه أنّ الموعدَ
// يُخزَّنُ مرّتَين: حقلا الحجزِ **ساعةُ حائطٍ** (يَقرؤهما `capacity.js`
// وبطاقةُ السائقِ والتذكير) و`service_date` **لحظةٌ مطلقةٌ** (تَقرؤها نوافذُ
// الخادم) — وكان الأوّلُ مستقلّاً عن المنطقةِ والثاني لا.
//
// وهذا الملفُّ يَسُدُّ الفرعَ المباشرَ في `pages/Orders.tsx`، والتعليقُ
// الموجودُ فوقَ فرعِ النداءِ الخادميِّ هناك يَشرحُ العطلَ بنصِّه:
// «toISOString كانت تفسّر الحائط بمنطقة المتصفح، فمتصفحٌ خارج السعودية يخزّن
// لحظةً مختلفة عن تطبيق الأدمن لنفس «14:00»» — فالقاعدةُ كانت مُنفَّذةً في
// فرعٍ من اثنَين داخلَ الدالّةِ الواحدة.
//
// جدولُ الحالاتِ مشترَكٌ مع فحصِ الدارت (بين العلامتَين في
// `test/ksa_instant_test.dart`).

/// إزاحةُ السعوديّةِ عن UTC بالمللي ثانية — نظيرةُ `KSA_OFFSET_MS` في
/// `functions/ksa_time.js` و`kKsaUtcOffset` في دارت، ومشدودةٌ بهما.
export const KSA_UTC_OFFSET_MS = 3 * 60 * 60 * 1000;

/// اللحظةُ التي تَقعُ فيها ساعةُ الحائطِ `wall` **بتوقيتِ الرياض**.
/// تُقرأُ مكوّناتُ `wall` لا لحظتُها، فمنطقةُ المتصفّحِ لا تَدخلُ الحساب.
export function ksaInstantOf(wall: Date): Date {
    return new Date(Date.UTC(
        wall.getFullYear(),
        wall.getMonth(),
        wall.getDate(),
        wall.getHours(),
        wall.getMinutes(),
        wall.getSeconds(),
        wall.getMilliseconds(),
    ) - KSA_UTC_OFFSET_MS);
}

/// **تاريخُ الرياضِ الحاليُّ ساعةَ حائطٍ** بصيغةِ `YYYY-MM-DD` — مرآةُ
/// `ksaTodayWall` في `lib/utils/ksa_instant.dart`، بالصيغةِ التي يَقبلُها
/// `min` في `<input type="date">`/`datetime-local` (ساعةُ حائطٍ لا لحظة).
///
/// فمتصفّحٌ خارجَ السعوديّةِ لا يُعطي «أمس»: الخادمُ يَقرأُ النصَّ الساذجَ
/// بتوقيتِ الرياضِ (`parseKsaIso`)، فالحدُّ يَجبُ أن يَكونَ بيومِ الرياض.
///
/// `nowMs` للفحصِ وحدَه؛ المواضعُ الحقيقيّةُ تَترُكُه فارغاً.
export function ksaTodayDate(nowMs?: number): string {
  const r = new Date((nowMs ?? Date.now()) + KSA_UTC_OFFSET_MS);
  const p = (n: number, w = 2) => String(n).padStart(w, '0');
  return `${p(r.getUTCFullYear(), 4)}-${p(r.getUTCMonth() + 1)}-${p(r.getUTCDate())}`;
}
