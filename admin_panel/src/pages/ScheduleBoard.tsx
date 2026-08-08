import { useState, useEffect, useMemo } from 'react';
import { collection, onSnapshot, query, where, orderBy, limit, Timestamp, type QuerySnapshot, type DocumentData } from 'firebase/firestore';
import { CalendarDays, UserX, Clock, ChevronLeft, AlertTriangle, CalendarCheck2 } from 'lucide-react';
import { Link } from 'react-router-dom';
import { db } from '../services/firebase.ts';

/// جدول المتابعة — **مرآة الويب** لـ lib/screens/admin/admin_schedule_board_screen.dart.
/// استشرافي لا تقريري: يبدأ من اليوم ويعرض القادم مجمَّعاً يومياً. لوحة القيادة
/// تجيب «كم ربحنا»؛ هذه تجيب «ماذا أمامنا وماذا ينقصه».
/// أي تغيير في قواعد الإنذار هنا يجب أن يطابق نظيره في التطبيق.

type RangeKey = 'day' | 'week' | 'month';
const RANGES: { key: RangeKey; label: string; days: number }[] = [
    { key: 'day', label: 'اليوم', days: 1 },
    // 7 و30 يوماً **متدحرجة** من اليوم لا الشهر الميلادي — الأفق ثابت مهما كان التاريخ.
    { key: 'week', label: 'الأسبوع', days: 7 },
    { key: 'month', label: 'الشهر', days: 30 },
];

/// حدّ الجلب — حارس ضد استعلام غير محدود؛ نُنبّه صراحةً عند بلوغه بدل القصّ الصامت.
const FETCH_LIMIT = 800;

/// الحالات المنتهية لا تُعدّ ضمن «ما أمامنا».
const DEAD = new Set(['cancelled', 'rejected', 'completed']);

/// مرجع ثابت للحالة الفارغة — حرفيّ `[]` جديد في كل تصيير يُبطل التذكير.
const EMPTY: BoardOrder[] = [];

interface BoardOrder {
    id: string;
    code?: string;
    service_name?: string;
    service_type?: string;
    client_name?: string;
    client_phone?: string;
    zone_name?: string;
    driver_id?: string;
    driverId?: string;
    driver_name?: string;
    status?: string;
    amount?: number;
    is_paid?: boolean;
    contract_id?: string;
    payment_method?: string;
    service_date?: Timestamp;
}

/// الطلبات القديمة تحمل driver_id والجديدة قد تحمل driverId — نقبل الاثنين،
/// والسلسلة الفارغة «بلا سائق» (كانت تُحسب مُسنَدة فتختفي من التنبيه).
const driverIdOf = (o: BoardOrder): string | null => {
    const v = (o.driver_id ?? o.driverId ?? '').toString().trim();
    return v === '' ? null : v;
};

const isSub = (o: BoardOrder) =>
    Boolean(o.contract_id) || o.payment_method === 'subscription';

/// **متى يكون غياب السائق خللاً فعلاً؟** الإسناد التلقائي يقع لحظة قلب الطلب إلى
/// «مدفوع» (paid-flip في onOrderWritten) لا لحظة إنشائه. فالطلب غير المدفوع بلا
/// سائق سلوك صحيح، وكذلك الطلب بلا موعد الذي يُحوَّل عمداً إلى under_review
/// لتُسنده الإدارة. عدُّهما إنذاراً كاذباً يُفقد الرقم قيمته.
const needsDriver = (o: BoardOrder): boolean => {
    if (driverIdOf(o) !== null) return false;
    if (!o.service_date) return false;
    return o.is_paid === true || isSub(o);
};

const statusAr = (s?: string): string => ({
    scheduled: 'مجدول', assigned: 'مُسند', accepted: 'مقبول',
    on_the_way: 'في الطريق', in_progress: 'قيد التنفيذ',
    pending: 'قيد الانتظار', under_review: 'قيد المراجعة',
    awaiting_payment: 'بانتظار الدفع',
}[s ?? ''] ?? (s || 'بلا حالة'));

const WEEKDAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

const dayKey = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const Tag = ({ text, tone, strong = false }: { text: string; tone: string; strong?: boolean }) => (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-md text-[10px] ${strong ? 'font-black' : 'font-bold'} ${tone}`}>{text}</span>
);

export default function ScheduleBoard() {
    const [rangeKey, setRangeKey] = useState<RangeKey>('week');
    // لقطة واحدة موسومة بمداها. الحالة تُضبط **داخل ردود الاستماع فقط** — ضبطها
    // تزامنياً داخل useEffect يُطلق تصييراً متتالياً (react-hooks/set-state-in-effect).
    // ووسم المدى يجعل «التحميل» مشتقّاً: أي مدى لم تصل لقطته بعد يعرض الدوّار.
    const [snapshot, setSnapshot] = useState<{
        range: RangeKey; orders: BoardOrder[]; rawCount: number; error: string | null;
    } | null>(null);

    const range = RANGES.find(r => r.key === rangeKey)!;

    const ready = snapshot !== null && snapshot.range === rangeKey;
    // مُذكَّرة: بدونها يُنتج كل تصيير مصفوفةً جديدة فتُبطل الـuseMemo أدناه دائماً.
    const orders = useMemo(
        () => (ready ? snapshot.orders : EMPTY),
        [ready, snapshot],
    );
    const rawCount = ready ? snapshot.rawCount : 0;
    const error = ready ? snapshot.error : null;
    const loading = !ready;

    useEffect(() => {
        const now = new Date();
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const end = new Date(start.getTime() + range.days * 86400000);

        // نطاق على حقل واحد + ترتيب على الحقل نفسه ⇒ لا فهرس مركّب.
        // التصفية بالحالة محلية عمداً: whereNotIn مع الترتيب يفرض فهرساً إضافياً.
        const q = query(
            collection(db, 'orders'),
            where('service_date', '>=', Timestamp.fromDate(start)),
            where('service_date', '<', Timestamp.fromDate(end)),
            orderBy('service_date'),
            limit(FETCH_LIMIT),
        );

        const unsub = onSnapshot(q, (snap: QuerySnapshot<DocumentData>) => {
            setSnapshot({
                range: rangeKey,
                rawCount: snap.docs.length,
                orders: snap.docs
                    .map(d => ({ ...(d.data() as DocumentData), id: d.id } as BoardOrder))
                    .filter(o => !DEAD.has(o.status ?? '')),
                error: null,
            });
        }, (e: unknown) => {
            // لا فشل صامت: بلا هذا تظهر الشاشة فارغة فيُفهم «لا مواعيد» خطأً.
            console.error('ScheduleBoard listener error:', e);
            setSnapshot({
                range: rangeKey,
                rawCount: 0,
                orders: [],
                error: e instanceof Error ? e.message : String(e),
            });
        });
        return () => unsub();
    }, [rangeKey, range.days]);

    const stats = useMemo(() => {
        let unassigned = 0, unpaid = 0, subs = 0, regular = 0, revenue = 0;
        for (const o of orders) {
            if (needsDriver(o)) unassigned++;
            if (o.is_paid !== true) unpaid++;
            if (isSub(o)) subs++; else regular++;
            revenue += Number(o.amount) || 0;
        }
        return { unassigned, unpaid, subs, regular, revenue };
    }, [orders]);

    const byDay = useMemo(() => {
        const map = new Map<string, BoardOrder[]>();
        for (const o of orders) {
            const dt = o.service_date?.toDate?.();
            if (!dt) continue;
            const k = dayKey(dt);
            if (!map.has(k)) map.set(k, []);
            map.get(k)!.push(o);
        }
        return Array.from(map.entries());
    }, [orders]);

    const todayKey = dayKey(new Date());

    return (
        <div className="space-y-6">
            <div>
                <h2 className="text-2xl font-black text-slate-800">جدول المتابعة</h2>
                <p className="text-slate-500 text-sm">ما هو أمامنا — الاشتراكات والخدمات والطلبات القادمة</p>
            </div>

            <div className="flex gap-2">
                {RANGES.map(r => (
                    <button
                        key={r.key}
                        type="button"
                        onClick={() => setRangeKey(r.key)}
                        className={`flex-1 py-2.5 rounded-xl font-bold transition-all ${
                            rangeKey === r.key
                                ? 'bg-[#660033] text-white shadow-lg shadow-[#660033]/20'
                                : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-50'
                        }`}
                    >{r.label}</button>
                ))}
            </div>

            {loading ? (
                <div className="flex justify-center py-20">
                    <div className="w-10 h-10 border-4 border-[#660033] border-t-transparent rounded-full animate-spin" />
                </div>
            ) : error ? (
                <div className="bg-rose-50 border border-rose-200 rounded-2xl p-6 text-center">
                    <AlertTriangle className="mx-auto text-rose-500 mb-2" size={40} />
                    <p className="font-black text-slate-800">تعذّر تحميل الجدول</p>
                    <p className="text-xs text-slate-500 mt-1">{error}</p>
                </div>
            ) : (
                <>
                    <div className="grid grid-cols-3 gap-3">
                        <Kpi label="الطلبات" value={orders.length} icon={<CalendarDays size={18} />} tone="text-slate-700" />
                        <Kpi label="بلا سائق" value={stats.unassigned} icon={<UserX size={18} />}
                             tone={stats.unassigned > 0 ? 'text-rose-600' : 'text-emerald-600'} />
                        <Kpi label="غير مدفوعة" value={stats.unpaid} icon={<Clock size={18} />}
                             tone={stats.unpaid > 0 ? 'text-amber-600' : 'text-emerald-600'} />
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-xs">
                        <span className="inline-flex items-center gap-2 px-3 py-1.5 rounded-xl bg-violet-50 border border-violet-200 font-bold text-violet-700">
                            <span className="w-2 h-2 rounded-full bg-violet-500" />زيارات اشتراكات: {stats.subs}
                        </span>
                        <span className="inline-flex items-center gap-2 px-3 py-1.5 rounded-xl bg-cyan-50 border border-cyan-200 font-bold text-cyan-700">
                            <span className="w-2 h-2 rounded-full bg-cyan-500" />طلبات وخدمات: {stats.regular}
                        </span>
                        <span className="text-slate-500 font-bold">الإيراد المتوقع: {stats.revenue.toFixed(2)} ر.س</span>
                    </div>

                    {rawCount >= FETCH_LIMIT && (
                        <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-xs font-bold text-amber-800">
                            عُرض أول {FETCH_LIMIT} موعد فقط — ضيّق المدى لرؤية البقية.
                        </div>
                    )}

                    {byDay.length === 0 ? (
                        <div className="bg-white border border-slate-200 rounded-2xl p-12 text-center">
                            <CalendarCheck2 className="mx-auto text-slate-300 mb-3" size={52} />
                            <p className="font-black text-slate-700">لا مواعيد</p>
                            <p className="text-sm text-slate-500 mt-1">لا شيء مجدول خلال {range.label}.</p>
                        </div>
                    ) : byDay.map(([k, items]) => {
                        const d = new Date(`${k}T00:00:00`);
                        const isToday = k === todayKey;
                        const dayUnassigned = items.filter(needsDriver).length;
                        return (
                            <div key={k} className={`bg-white rounded-2xl border overflow-hidden ${isToday ? 'border-[#660033]/40' : 'border-slate-200'}`}>
                                <div className="flex items-center gap-2 px-5 py-3 border-b border-slate-100 bg-slate-50/60">
                                    <span className={`font-black ${isToday ? 'text-[#660033]' : 'text-slate-800'}`}>
                                        {WEEKDAYS[d.getDay()]} {d.getDate()} {MONTHS[d.getMonth()]}{isToday ? ' • اليوم' : ''}
                                    </span>
                                    <span className="flex-1" />
                                    {dayUnassigned > 0 && (
                                        <Tag text={`${dayUnassigned} بلا سائق`} tone="bg-rose-100 text-rose-700" strong />
                                    )}
                                    <span className="px-2.5 py-0.5 rounded-full bg-slate-100 text-slate-700 text-xs font-black">{items.length}</span>
                                </div>
                                <div className="divide-y divide-slate-50">
                                    {items.map(o => {
                                        const dt = o.service_date?.toDate?.();
                                        const drv = driverIdOf(o);
                                        return (
                                            <Link key={o.id} to="/orders"
                                                  className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50 transition-colors">
                                                <span className="w-16 shrink-0 text-xs font-black text-slate-600" dir="ltr">
                                                    {dt ? dt.toLocaleTimeString('ar-SA', { hour: 'numeric', minute: '2-digit' }) : '—'}
                                                </span>
                                                <span className={`w-1 h-9 rounded shrink-0 ${isSub(o) ? 'bg-violet-500' : 'bg-cyan-600'}`} />
                                                <div className="flex-1 min-w-0">
                                                    <div className="flex items-center gap-2">
                                                        <span className="text-[11px] font-black text-slate-400 shrink-0">
                                                            #{o.code ?? o.id.slice(0, 6)}
                                                        </span>
                                                        <span className="font-bold text-sm text-slate-800 truncate">
                                                            {o.service_name ?? o.service_type ?? 'خدمة'}
                                                        </span>
                                                    </div>
                                                    <div className="text-[11px] text-slate-500 truncate">
                                                        {o.client_name ?? '—'} • {o.zone_name ?? '—'}
                                                        {o.client_phone ? ` • ${o.client_phone}` : ''}
                                                    </div>
                                                    <div className="flex flex-wrap gap-1.5 mt-1">
                                                        <Tag text={statusAr(o.status)} tone="bg-slate-100 text-slate-700" />
                                                        {drv !== null
                                                            ? <Tag text={o.driver_name ?? 'مُسنَد'} tone="bg-emerald-50 text-emerald-700" />
                                                            : needsDriver(o)
                                                                ? <Tag text="بلا سائق" tone="bg-rose-100 text-rose-700" strong />
                                                                // غيابه هنا متوقَّع: الإسناد يقع عند الدفع — رمادي لا أحمر.
                                                                : <Tag text="يُسنَد بعد الدفع" tone="bg-slate-100 text-slate-400" />}
                                                        {o.is_paid !== true && !isSub(o) && (
                                                            <Tag text="غير مدفوع" tone="bg-amber-50 text-amber-700" />
                                                        )}
                                                    </div>
                                                </div>
                                                <div className="flex flex-col items-end shrink-0">
                                                    <span className={`text-xs font-black ${isSub(o) ? 'text-violet-600' : 'text-[#660033]'}`}>
                                                        {isSub(o) ? 'اشتراك' : `${(Number(o.amount) || 0).toFixed(2)} ر.س`}
                                                    </span>
                                                    <ChevronLeft size={16} className="text-slate-300" />
                                                </div>
                                            </Link>
                                        );
                                    })}
                                </div>
                            </div>
                        );
                    })}
                </>
            )}
        </div>
    );
}

function Kpi({ label, value, icon, tone }: { label: string; value: number; icon: React.ReactNode; tone: string }) {
    return (
        <div className="bg-white border border-slate-200 rounded-2xl p-4 flex flex-col items-center">
            <span className={tone}>{icon}</span>
            <span className={`text-2xl font-black mt-1 ${tone}`}>{value}</span>
            <span className="text-[11px] text-slate-500 font-bold mt-0.5">{label}</span>
        </div>
    );
}
