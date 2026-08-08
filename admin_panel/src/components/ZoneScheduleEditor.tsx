import { useState, useCallback } from 'react';
import { Plus, Trash2, CalendarX2 } from 'lucide-react';
import {
    type ZoneSchedule, type DayHours,
    DAY_NAMES, HOURS, formatHour12, scheduleFromDoc, scheduleToDoc,
} from '../utils/zoneSchedule.ts';

// محرّر جدول فتح المحافظة — **مرآة الويب** لـ
// lib/screens/admin/admin_zone_schedule_editor.dart.
//
// يبني `schedule` الذي يُخزَّن على مستند المحافظة ويحسبه الخادم مرجعيّاً
// (getHourlyAvailability). الشكل مُلزِم حرفياً:
//   { enabled, weekly:{"0":{open,start,end,closed:[]}..}, blackouts:[...],
//     windows:[{from,to,start,end}] }
//
// **الساعات تُعرَض 12 وتُخزَّن 24** — الخادم يحلّلها رقميّاً، فأي تخزين نصّي
// أو 12-ساعي يكسر حساب الإتاحة بصمت.

interface Props {
    initial?: unknown;
    /// تُستدعى عند أي تعديل **فعلي** فقط — الأب يستعملها كعلم «لُمس» فلا يُعيد
    /// كتابة جدول لم يُفتح أصلاً (نفس درس فقدان البيانات في التطبيق).
    onChange: (s: ZoneSchedule) => void;
}

/// ملاحظة للأب: مرّر `key` يتغيّر مع المحافظة المعروضة كي يُعاد تركيب المحرّر
/// بحالة نظيفة — أنظف من إعادة الضبط داخل useEffect (تُطلق تصييراً متتالياً).
export default function ZoneScheduleEditor({ initial, onChange }: Props) {
    const [sched, setSched] = useState<ZoneSchedule>(() => scheduleFromDoc(initial));

    // onChange تُستدعى من المُعدِّل مباشرةً لا من useEffect: الأخير يجعل الإبلاغ
    // أثراً جانبياً للتصيير ويُطلق تحذير التصيير المتتالي.
    const mutate = useCallback((fn: (d: ZoneSchedule) => ZoneSchedule) => {
        setSched(prev => {
            const next = fn(structuredClone(prev));
            onChange(scheduleToDoc(next));
            return next;
        });
    }, [onChange]);

    const setDay = (d: number, patch: Partial<DayHours>) =>
        mutate(s => { s.weekly[String(d)] = { ...s.weekly[String(d)], ...patch }; return s; });

    const toggleHour = (d: number, h: number) =>
        mutate(s => {
            const day = s.weekly[String(d)];
            day.closed = day.closed.includes(h)
                ? day.closed.filter(x => x !== h)
                : [...day.closed, h];
            return s;
        });

    const inputCls = 'bg-white border border-slate-200 rounded-lg px-2 py-1.5 text-sm font-bold text-slate-700 outline-none focus:border-rose-500';

    return (
        <div className="border-t border-slate-100 pt-5 space-y-4">
            <label className="flex items-start gap-3 cursor-pointer">
                <input
                    type="checkbox"
                    checked={sched.enabled}
                    onChange={e => mutate(s => ({ ...s, enabled: e.target.checked }))}
                    className="w-5 h-5 mt-0.5 accent-rose-600"
                />
                <span>
                    <span className="block font-black text-slate-800 text-sm">جدول فتح مخصّص</span>
                    <span className="block text-xs text-slate-400">بدونه تُعامَل المحافظة مفتوحةً بالجدول الافتراضي للنظام.</span>
                </span>
            </label>

            {sched.enabled && (
                <>
                    <div className="space-y-2">
                        {DAY_NAMES.map((name, d) => {
                            const day = sched.weekly[String(d)];
                            return (
                                <div key={d} className="bg-slate-50 border border-slate-100 rounded-xl p-3">
                                    <div className="flex items-center gap-3 flex-wrap">
                                        <label className="flex items-center gap-2 cursor-pointer min-w-[110px]">
                                            <input type="checkbox" checked={day.open}
                                                   onChange={e => setDay(d, { open: e.target.checked })}
                                                   className="w-4 h-4 accent-rose-600" />
                                            <span className="font-bold text-slate-700 text-sm">{name}</span>
                                        </label>
                                        {day.open ? (
                                            <div className="flex items-center gap-2">
                                                <span className="text-xs text-slate-400">من</span>
                                                <select aria-label={`بداية ${name}`} value={day.start} className={inputCls}
                                                        onChange={e => setDay(d, { start: Number(e.target.value) })}>
                                                    {HOURS.map(h => <option key={h} value={h}>{formatHour12(h)}</option>)}
                                                </select>
                                                <span className="text-xs text-slate-400">إلى</span>
                                                <select aria-label={`نهاية ${name}`} value={day.end} className={inputCls}
                                                        onChange={e => setDay(d, { end: Number(e.target.value) })}>
                                                    {HOURS.map(h => <option key={h} value={h}>{formatHour12(h)}</option>)}
                                                </select>
                                            </div>
                                        ) : (
                                            <span className="text-xs text-slate-400 font-bold">مغلق</span>
                                        )}
                                    </div>

                                    {/* تحكّم ساعة-بساعة داخل النطاق: نقرة تُقفل الساعة أو تفتحها. */}
                                    {day.open && day.end > day.start && (
                                        <div className="flex flex-wrap gap-1.5 mt-2.5 pr-1">
                                            {Array.from({ length: day.end - day.start }, (_, i) => day.start + i).map(h => {
                                                const isClosed = day.closed.includes(h);
                                                return (
                                                    <button
                                                        key={h}
                                                        type="button"
                                                        onClick={() => toggleHour(d, h)}
                                                        title={isClosed ? 'مقفلة — اضغط للفتح' : 'مفتوحة — اضغط للإقفال'}
                                                        className={`px-2 py-1 rounded-md text-[11px] font-bold border transition-colors ${
                                                            isClosed
                                                                ? 'bg-rose-100 text-rose-700 border-rose-200 line-through'
                                                                : 'bg-white text-slate-600 border-slate-200 hover:border-rose-300'
                                                        }`}
                                                    >{formatHour12(h)}</button>
                                                );
                                            })}
                                        </div>
                                    )}
                                </div>
                            );
                        })}
                    </div>

                    {/* فترات فتح استثنائية — تتجاوز الجدول الأسبوعي في مدى تواريخ. */}
                    <div className="space-y-2">
                        <div className="flex items-center justify-between">
                            <span className="font-black text-slate-800 text-sm">فترات فتح استثنائية</span>
                            <button type="button" className="text-xs font-bold text-rose-700 flex items-center gap-1 hover:underline"
                                    onClick={() => mutate(s => ({ ...s, windows: [...s.windows, { from: '', to: '', start: 9, end: 13 }] }))}>
                                <Plus size={14} />إضافة فترة
                            </button>
                        </div>
                        {sched.windows.map((w, i) => (
                            <div key={i} className="flex items-center gap-2 flex-wrap bg-slate-50 border border-slate-100 rounded-xl p-3">
                                <input type="date" aria-label="من تاريخ" value={w.from} className={inputCls} dir="ltr"
                                       onChange={e => mutate(s => { s.windows[i].from = e.target.value; return s; })} />
                                <input type="date" aria-label="إلى تاريخ" value={w.to} className={inputCls} dir="ltr"
                                       onChange={e => mutate(s => { s.windows[i].to = e.target.value; return s; })} />
                                <select aria-label="ساعة البدء" value={w.start} className={inputCls}
                                        onChange={e => mutate(s => { s.windows[i].start = Number(e.target.value); return s; })}>
                                    {HOURS.map(h => <option key={h} value={h}>{formatHour12(h)}</option>)}
                                </select>
                                <select aria-label="ساعة الانتهاء" value={w.end} className={inputCls}
                                        onChange={e => mutate(s => { s.windows[i].end = Number(e.target.value); return s; })}>
                                    {HOURS.map(h => <option key={h} value={h}>{formatHour12(h)}</option>)}
                                </select>
                                <button type="button" title="حذف الفترة" className="p-1.5 text-rose-500 hover:bg-rose-50 rounded-lg"
                                        onClick={() => mutate(s => ({ ...s, windows: s.windows.filter((_, j) => j !== i) }))}>
                                    <Trash2 size={15} />
                                </button>
                            </div>
                        ))}
                        {sched.windows.length === 0 && (
                            <p className="text-xs text-slate-400">لا فترات استثنائية — يُطبَّق الجدول الأسبوعي وحده.</p>
                        )}
                    </div>

                    {/* أيام إغلاق كامل — تتجاوز كل ما سبق. */}
                    <div className="space-y-2">
                        <div className="flex items-center justify-between">
                            <span className="font-black text-slate-800 text-sm flex items-center gap-1.5">
                                <CalendarX2 size={15} className="text-rose-600" />أيام إغلاق كامل
                            </span>
                        </div>
                        <div className="flex items-center gap-2 flex-wrap">
                            {sched.blackouts.map(b => (
                                <span key={b} className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-xs font-bold">
                                    <span dir="ltr">{b}</span>
                                    <button type="button" title="إزالة" onClick={() => mutate(s => ({ ...s, blackouts: s.blackouts.filter(x => x !== b) }))}>
                                        <Trash2 size={12} />
                                    </button>
                                </span>
                            ))}
                            <input
                                type="date"
                                aria-label="إضافة يوم إغلاق"
                                className={inputCls}
                                dir="ltr"
                                onChange={e => {
                                    const v = e.target.value;
                                    if (!v) return;
                                    mutate(s => s.blackouts.includes(v) ? s : { ...s, blackouts: [...s.blackouts, v] });
                                    e.target.value = '';
                                }}
                            />
                        </div>
                    </div>
                </>
            )}
        </div>
    );
}
