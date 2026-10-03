// شكل جدول فتح المحافظة ومحوّلاته — **مرآة** لـ
// lib/screens/admin/admin_zone_schedule_editor.dart.
//
// يُخزَّن على مستند المحافظة ويحسبه الخادم مرجعيّاً (getHourlyAvailability):
//   { enabled, weekly:{"0":{open,start,end,closed:[]}..}, blackouts:[...],
//     windows:[{from,to,start,end}] }
//
// **الساعات تُعرَض 12 وتُخزَّن 24** — الخادم يحلّلها رقميّاً، فأي تخزين نصّي
// أو 12-ساعي يكسر حساب الإتاحة بصمت.

export interface DayHours { open: boolean; start: number; end: number; closed: number[] }
export interface ExceptionWindow { from: string; to: string; start: number; end: number }
export interface ZoneSchedule {
    enabled: boolean;
    weekly: Record<string, DayHours>;
    blackouts: string[];
    windows: ExceptionWindow[];
}

export const DAY_NAMES = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
export const HOURS = Array.from({ length: 24 }, (_, i) => i);

/// عرض 12-ساعي مطابق لـ formatHour12 في التطبيق (lib/utils/time_format.dart).
export const formatHour12 = (h: number): string => {
    const period = h < 12 ? 'ص' : 'م';
    const hour = h % 12 === 0 ? 12 : h % 12;
    return `${hour} ${period}`;
};

/// **قيد الخادم على النطاق: `end > start` وإلّا فاليوم مغلق عنده.**
///
/// `zoneDayScheduleForDate` في `functions/index.js` يشترط
/// `Number.isInteger(s) && Number.isInteger(e) && e > s` — وإن لم يتحقّق أعاد
/// `null`، أي **مغلق كلّ اليوم**. وقائمتا الساعات هنا مستقلّتان على 0..23، فكان
/// الأدمن يحفظ «مفتوح ١٠م → ٨ص» فتُظهر اللوحة أنه حُفظ، ويقرؤه الخادم مغلقاً:
/// لا إتاحة، ولا حجز، ولا خطأ في أي مكان.
///
/// ومحرّر Flutter (`admin_zone_schedule_editor.dart`) يُقيّده في الاتجاهين —
/// تحريك البداية يدفع النهاية، وتحريك النهاية يسحب البداية — ومرآة الويب كانت
/// **بلا قيد أصلاً**. فنُقل القيد، ثمّ شُدّ: نظير Flutter يُخلّف ثغرةً في طرف
/// المدى (بداية 23 ⇒ نهاية 23 ⇒ متساويان ⇒ مغلق)، فالدالّتان أدناه تقصّان
/// البداية عند 22 والنهاية عند 1 فلا يتساويان أبداً.

/// البداية تغيّرت إلى [start]: تدفع النهاية إلى `start+1` إن لزِم.
///
/// وتقصّ البداية عند 22: لا بدايةَ في الساعة 23 — فالنهاية لا تتجاوز 23،
/// فلا تبقى ساعةٌ واحدة. ودفعُ النهاية وحده لا يكفي هناك: نظير Flutter
/// `(v + 1).clamp(1, 23)` يُعيد 23 للبداية 23، فيتساوى الطرفان ويقرؤه الخادم
/// **مغلقاً** — نفس العطل الذي جاء القيد يمنعه، باقياً في طرف المدى.
export function withStart(start: number, end: number): { start: number; end: number } {
    const s = Math.min(22, Math.max(0, start));
    return end <= s ? { start: s, end: Math.min(23, s + 1) } : { start: s, end };
}

/// النهاية تغيّرت إلى [end]: تسحب البداية إلى `end-1` إن لزِم.
///
/// وتقصّ النهاية عند 1 — للسبب المقابل: نهايةٌ في 0 لا تدع ساعةً قبلها.
export function withEnd(start: number, end: number): { start: number; end: number } {
    const e = Math.min(23, Math.max(1, end));
    return start >= e ? { start: Math.max(0, e - 1), end: e } : { start, end: e };
}

/// يقرأ مستند محافظة قائم إلى الشكل الداخلي، متسامحاً مع الحقول الناقصة
/// (محافظات أُنشئت قبل وجود الجدول) — كما يفعل initState في التطبيق.
export function scheduleFromDoc(raw: unknown): ZoneSchedule {
    const s = (raw ?? {}) as Record<string, unknown>;
    const weeklyRaw = (s.weekly ?? {}) as Record<string, Record<string, unknown>>;
    const weekly: Record<string, DayHours> = {};
    for (let d = 0; d < 7; d++) {
        const w = weeklyRaw[String(d)] ?? {};
        weekly[String(d)] = {
            open: w.open === true,
            start: Number(w.start ?? 8),
            end: Number(w.end ?? 22),
            closed: Array.isArray(w.closed) ? (w.closed as unknown[]).map(Number) : [],
        };
    }
    return {
        enabled: s.enabled === true,
        weekly,
        blackouts: Array.isArray(s.blackouts) ? (s.blackouts as unknown[]).map(String) : [],
        windows: Array.isArray(s.windows)
            ? (s.windows as Record<string, unknown>[]).map(w => ({
                from: String(w.from ?? ''), to: String(w.to ?? ''),
                start: Number(w.start ?? 9), end: Number(w.end ?? 13),
            }))
            : [],
    };
}

/// الشكل المكتوب على Firestore — الساعات المقفلة تُقصّ على النطاق الحالي كي لا
/// تبقى «أشباح» ساعات خارج حدوده بعد تضييق الدوام (نفس قاعدة _emit في التطبيق).
export function scheduleToDoc(s: ZoneSchedule): ZoneSchedule {
    return {
        enabled: s.enabled,
        weekly: Object.fromEntries(Object.entries(s.weekly).map(([d, v]) => [d, {
            open: v.open,
            start: v.start,
            end: v.end,
            closed: v.closed.filter(h => h >= v.start && h < v.end).sort((a, b) => a - b),
        }])),
        blackouts: [...s.blackouts],
        windows: s.windows.filter(w => w.from && w.to),
    };
}
