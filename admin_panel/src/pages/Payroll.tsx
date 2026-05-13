import { useState, useEffect } from 'react';
import { Banknote, CheckCircle2, Clock, Users, ChevronRight, ChevronLeft, Loader2, BadgeCheck, Wallet } from 'lucide-react';
import { collection, onSnapshot, query, doc, setDoc, serverTimestamp, where } from 'firebase/firestore';
import { db, auth } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface Driver {
    id: string;
    name: string;
    type: string;
    monthly_salary: number;
    is_active: boolean;
}

interface PayrollRecord {
    driver_id: string;
    driver_name: string;
    driver_type: string;
    salary: number;
    month: string;
    status: 'paid' | 'unpaid';
    paid_at?: { toDate: () => Date } | null;
}

interface DriverPayrollRow extends Driver {
    status: 'paid' | 'unpaid';
    paid_at?: { toDate: () => Date } | null;
    recordId: string;
}

const ARABIC_MONTHS = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];

function getMonthKey(date: Date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function monthLabel(key: string) {
    const [y, m] = key.split('-');
    return `${ARABIC_MONTHS[parseInt(m) - 1]} ${y}`;
}

function prevMonth(key: string) {
    const [y, m] = key.split('-').map(Number);
    const d = new Date(y, m - 2, 1);
    return getMonthKey(d);
}

function nextMonth(key: string) {
    const [y, m] = key.split('-').map(Number);
    const d = new Date(y, m, 1);
    return getMonthKey(d);
}

export default function Payroll() {
    const { confirm } = useNotification();
    const [currentMonth, setCurrentMonth] = useState(() => getMonthKey(new Date()));
    const [drivers, setDrivers] = useState<Driver[]>([]);
    const [payrollRecords, setPayrollRecords] = useState<Record<string, PayrollRecord>>({});
    const [loadingDrivers, setLoadingDrivers] = useState(true);
    const [loadingRecords, setLoadingRecords] = useState(true);
    const [payingId, setPayingId] = useState<string | null>(null);
    const [payingAll, setPayingAll] = useState(false);

    useEffect(() => {
        const unsub = onSnapshot(collection(db, 'drivers'), snap => {
            setDrivers(snap.docs.map(d => {
                const data = d.data();
                return {
                    id: d.id,
                    name: data.name || '—',
                    type: data.type || 'driver',
                    monthly_salary: data.monthly_salary || 0,
                    is_active: data.is_active ?? true,
                };
            }));
            setLoadingDrivers(false);
        });
        return unsub;
    }, []);

    useEffect(() => {
        setLoadingRecords(true);
        const q = query(collection(db, 'payroll_records'), where('month', '==', currentMonth));
        const unsub = onSnapshot(q, snap => {
            const map: Record<string, PayrollRecord> = {};
            snap.docs.forEach(d => {
                const data = d.data() as PayrollRecord;
                map[data.driver_id] = data;
            });
            setPayrollRecords(map);
            setLoadingRecords(false);
        });
        return unsub;
    }, [currentMonth]);

    const rows: DriverPayrollRow[] = drivers.map(d => {
        const rec = payrollRecords[d.id];
        return {
            ...d,
            status: rec?.status ?? 'unpaid',
            paid_at: rec?.paid_at ?? null,
            recordId: `${d.id}_${currentMonth}`,
        };
    });

    const totalBudget = drivers.reduce((s, d) => s + d.monthly_salary, 0);
    const paidTotal = rows.filter(r => r.status === 'paid').reduce((s, r) => s + r.monthly_salary, 0);
    const unpaidTotal = rows.filter(r => r.status === 'unpaid').reduce((s, r) => s + r.monthly_salary, 0);
    const paidCount = rows.filter(r => r.status === 'paid').length;
    const unpaidCount = rows.filter(r => r.status === 'unpaid').length;

    const markPaid = async (row: DriverPayrollRow) => {
        setPayingId(row.id);
        try {
            await setDoc(doc(db, 'payroll_records', row.recordId), {
                driver_id: row.id,
                driver_name: row.name,
                driver_type: row.type,
                salary: row.monthly_salary,
                month: currentMonth,
                status: 'paid',
                paid_at: serverTimestamp(),
                paid_by: auth.currentUser?.email ?? 'admin',
            });
        } finally {
            setPayingId(null);
        }
    };

    const markAllPaid = async () => {
        const unpaid = rows.filter(r => r.status === 'unpaid');
        if (!unpaid.length) return;
        if (!await confirm(`هل تريد تأكيد صرف رواتب ${unpaid.length} موظف؟`)) return;
        setPayingAll(true);
        try {
            await Promise.all(unpaid.map(r =>
                setDoc(doc(db, 'payroll_records', r.recordId), {
                    driver_id: r.id,
                    driver_name: r.name,
                    driver_type: r.type,
                    salary: r.monthly_salary,
                    month: currentMonth,
                    status: 'paid',
                    paid_at: serverTimestamp(),
                    paid_by: auth.currentUser?.email ?? 'admin',
                })
            ));
        } finally {
            setPayingAll(false);
        }
    };

    const isCurrentMonth = currentMonth === getMonthKey(new Date());
    const loading = loadingDrivers || loadingRecords;

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">

            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
                        <Banknote className="text-emerald-600" size={28} />
                        إدارة الرواتب الشهرية
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">صرف وتتبع رواتب الكوادر والسائقين شهرياً</p>
                </div>

                {/* Month Selector */}
                <div className="flex items-center gap-2 bg-white border border-slate-200 rounded-2xl px-4 py-2 shadow-sm">
                    <button type="button" title="الشهر السابق" onClick={() => setCurrentMonth(prevMonth(currentMonth))}
                        className="p-1.5 hover:bg-slate-100 rounded-xl transition-colors text-slate-500">
                        <ChevronRight size={18} />
                    </button>
                    <span className="font-extrabold text-slate-800 min-w-[140px] text-center text-sm">{monthLabel(currentMonth)}</span>
                    <button type="button" title="الشهر التالي"
                        onClick={() => setCurrentMonth(nextMonth(currentMonth))}
                        disabled={isCurrentMonth}
                        className="p-1.5 hover:bg-slate-100 rounded-xl transition-colors text-slate-500 disabled:opacity-30 disabled:cursor-not-allowed">
                        <ChevronLeft size={18} />
                    </button>
                </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-5">
                <div className="bg-gradient-to-bl from-emerald-500 to-teal-600 rounded-3xl p-6 text-white shadow-lg shadow-emerald-500/20 relative overflow-hidden col-span-2 lg:col-span-1">
                    <div className="absolute -left-4 -top-4 w-24 h-24 bg-white/10 rounded-full blur-2xl"></div>
                    <div className="p-3 bg-white/20 rounded-2xl w-fit mb-4"><Wallet size={22} /></div>
                    <p className="text-emerald-100 text-xs font-bold mb-1">إجمالي ميزانية الرواتب</p>
                    <h3 className="text-3xl font-black">{totalBudget.toLocaleString()} <span className="text-lg font-bold text-emerald-200">ر.س</span></h3>
                    <p className="text-emerald-200 text-xs mt-2 font-medium">{drivers.length} موظف مسجل</p>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-emerald-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-emerald-50 text-emerald-600 rounded-2xl"><CheckCircle2 size={22} /></div>
                        <span className="text-xs font-bold bg-emerald-50 text-emerald-700 px-2 py-1 rounded-lg">{paidCount} موظف</span>
                    </div>
                    <p className="text-slate-500 text-xs font-bold mb-1">تم الصرف</p>
                    <h3 className="text-2xl font-extrabold text-slate-800">{paidTotal.toLocaleString()} <span className="text-sm font-bold text-slate-400">ر.س</span></h3>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-amber-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-amber-50 text-amber-600 rounded-2xl"><Clock size={22} /></div>
                        <span className="text-xs font-bold bg-amber-50 text-amber-700 px-2 py-1 rounded-lg">{unpaidCount} موظف</span>
                    </div>
                    <p className="text-slate-500 text-xs font-bold mb-1">لم يُصرف بعد</p>
                    <h3 className="text-2xl font-extrabold text-slate-800">{unpaidTotal.toLocaleString()} <span className="text-sm font-bold text-slate-400">ر.س</span></h3>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-blue-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl"><Users size={22} /></div>
                    </div>
                    <p className="text-slate-500 text-xs font-bold mb-1">نسبة الإنجاز</p>
                    <h3 className="text-2xl font-extrabold text-slate-800">
                        {drivers.length ? Math.round((paidCount / drivers.length) * 100) : 0}<span className="text-sm font-bold text-slate-400">%</span>
                    </h3>
                    <div className="mt-2 h-1.5 bg-slate-100 rounded-full overflow-hidden">
                        <div className="h-full bg-gradient-to-l from-blue-500 to-indigo-500 rounded-full transition-all duration-700"
                            style={{ width: `${drivers.length ? (paidCount / drivers.length) * 100 : 0}%` }}></div>
                    </div>
                </div>
            </div>

            {/* Payroll Table */}
            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div>
                        <h3 className="font-extrabold text-slate-800">كشف رواتب {monthLabel(currentMonth)}</h3>
                        <p className="text-xs text-slate-400 font-medium mt-0.5">{rows.length} موظف في هذا الشهر</p>
                    </div>
                    {unpaidCount > 0 && (
                        <button
                            type="button"
                            onClick={markAllPaid}
                            disabled={payingAll}
                            className="flex items-center gap-2 px-5 py-2.5 bg-gradient-to-l from-emerald-500 to-teal-600 text-white rounded-xl font-bold text-sm hover:opacity-90 transition-all shadow-lg shadow-emerald-500/20 disabled:opacity-60"
                        >
                            {payingAll ? <Loader2 size={16} className="animate-spin" /> : <BadgeCheck size={16} />}
                            صرف جميع الرواتب ({unpaidCount})
                        </button>
                    )}
                    {unpaidCount === 0 && paidCount > 0 && (
                        <span className="flex items-center gap-2 text-emerald-600 font-bold text-sm bg-emerald-50 px-4 py-2 rounded-xl border border-emerald-100">
                            <CheckCircle2 size={16} /> تم صرف جميع الرواتب
                        </span>
                    )}
                </div>

                {loading ? (
                    <div className="flex items-center justify-center py-20 text-slate-400 gap-2">
                        <Loader2 size={22} className="animate-spin" />
                        <span className="text-sm font-medium">جاري التحميل...</span>
                    </div>
                ) : rows.length === 0 ? (
                    <div className="py-20 text-center text-slate-400">
                        <Users size={40} className="mx-auto mb-3 opacity-30" />
                        <p className="font-bold">لا يوجد موظفون مسجلون</p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الموظف</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">التصنيف</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الراتب الشهري</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">حالة الصرف</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الصرف</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 text-center">إجراء</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {rows.map(row => (
                                    <tr key={row.id} className={`transition-colors group ${row.status === 'paid' ? 'bg-emerald-50/30' : 'hover:bg-slate-50/50'}`}>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className={`w-10 h-10 rounded-xl flex items-center justify-center font-bold border text-sm
                                                    ${row.status === 'paid' ? 'bg-emerald-100 text-emerald-700 border-emerald-200' : 'bg-slate-100 text-slate-600 border-slate-200'}`}>
                                                    {row.name.charAt(0)}
                                                </div>
                                                <div>
                                                    <p className="font-bold text-slate-800 text-sm">{row.name}</p>
                                                    <p className="text-xs text-slate-400 font-mono">#{row.id.substring(0, 6).toUpperCase()}</p>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`px-2.5 py-1 text-xs font-bold rounded-lg
                                                ${row.type === 'worker' ? 'bg-pink-50 text-pink-700 border border-pink-100' : 'bg-orange-50 text-orange-700 border border-orange-100'}`}>
                                                {row.type === 'worker' ? 'كادر تنظيف' : 'سائق توصيل'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className="font-extrabold text-slate-800 text-base">{row.monthly_salary.toLocaleString()}</span>
                                            <span className="text-slate-400 text-xs font-bold mr-1">ر.س</span>
                                        </td>
                                        <td className="px-6 py-4">
                                            {row.status === 'paid'
                                                ? <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold text-xs border border-emerald-100"><CheckCircle2 size={12} />تم الصرف</span>
                                                : <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold text-xs border border-amber-100"><Clock size={12} />لم يُصرف</span>
                                            }
                                        </td>
                                        <td className="px-6 py-4 text-sm font-medium text-slate-500">
                                            {row.paid_at ? row.paid_at.toDate().toLocaleDateString('ar-SA') : '—'}
                                        </td>
                                        <td className="px-6 py-4 text-center">
                                            {row.status === 'unpaid' ? (
                                                <button
                                                    type="button"
                                                    onClick={() => markPaid(row)}
                                                    disabled={payingId === row.id || payingAll}
                                                    className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-bold transition-colors flex items-center gap-1.5 mx-auto disabled:opacity-50"
                                                >
                                                    {payingId === row.id ? <Loader2 size={12} className="animate-spin" /> : <BadgeCheck size={12} />}
                                                    صرف الراتب
                                                </button>
                                            ) : (
                                                <span className="text-xs text-slate-400 font-medium">مكتمل</span>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                            <tfoot>
                                <tr className="bg-slate-50 border-t-2 border-slate-200">
                                    <td colSpan={2} className="px-6 py-4 font-extrabold text-slate-700">الإجمالي</td>
                                    <td className="px-6 py-4 font-extrabold text-slate-800 text-base">{totalBudget.toLocaleString()} ر.س</td>
                                    <td className="px-6 py-4">
                                        <span className="text-xs font-bold text-emerald-600">{paidTotal.toLocaleString()} ر.س مصروفة</span>
                                    </td>
                                    <td colSpan={2}></td>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}
