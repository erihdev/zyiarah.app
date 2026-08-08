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
