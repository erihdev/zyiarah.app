import { useEffect, useState } from 'react';
import { collection, query, where, onSnapshot, Timestamp } from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { DollarSign, ArrowUpRight, TrendingUp, Download, Users, Banknote, ShoppingBag, CreditCard, Wallet } from 'lucide-react';

interface Order {
    id: string;
    amount: number;
    payment_method?: string;
    status: string;
    created_at?: Timestamp;
    client_name?: string;
    service_name?: string;
    service_type?: string;
}

interface Driver {
    monthly_salary?: number;
    name?: string;
}

interface Transaction {
    id: string;
    client_name: string;
    service_name: string;
    amount: number;
    payment_method: string;
    date: Date;
    status: string;
}

const PAYMENT_LABELS: Record<string, string> = {
    card: 'بطاقة ائتمانية',
    cash: 'دفع عند الاستلام',
    tamara: 'تمارة (تقسيط)',
    wallet: 'المحفظة',
};

const PAYMENT_COLORS: Record<string, string> = {
    card: 'bg-blue-50 text-blue-700',
    cash: 'bg-emerald-50 text-emerald-700',
    tamara: 'bg-purple-50 text-purple-700',
    wallet: 'bg-amber-50 text-amber-700',
};

function formatCurrency(value: number) {
    return value.toLocaleString('ar-SA', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

function getMonthRange() {
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), 1);
    const end = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);
    return { start, end };
}

export default function Accountants() {
    const [orders, setOrders] = useState<Order[]>([]);
    const [drivers, setDrivers] = useState<Driver[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const { start, end } = getMonthRange();

        const ordersQ = query(
            collection(db, 'orders'),
            where('status', '==', 'completed'),
            where('created_at', '>=', Timestamp.fromDate(start)),
            where('created_at', '<=', Timestamp.fromDate(end))
        );

        const unsubOrders = onSnapshot(ordersQ, (snap) => {
            setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() } as Order)));
            setLoading(false);
        });

        const unsubDrivers = onSnapshot(collection(db, 'drivers'), (snap) => {
            setDrivers(snap.docs.map(d => d.data() as Driver));
        });

        return () => { unsubOrders(); unsubDrivers(); };
    }, []);

    const totalRevenue = orders.reduce((sum, o) => sum + (o.amount || 0), 0);
    const totalPayroll = drivers.reduce((sum, d) => sum + (d.monthly_salary || 0), 0);
    const netProfit = totalRevenue - totalPayroll;

    const paymentBreakdown: Record<string, number> = {};
    orders.forEach(o => {
        const method = o.payment_method || 'cash';
        paymentBreakdown[method] = (paymentBreakdown[method] || 0) + (o.amount || 0);
    });

    const transactions: Transaction[] = orders
        .filter(o => o.created_at)
        .sort((a, b) => (b.created_at?.seconds ?? 0) - (a.created_at?.seconds ?? 0))
        .slice(0, 20)
        .map(o => ({
            id: o.id,
            client_name: o.client_name || 'عميل',
            service_name: o.service_name || o.service_type || 'خدمة تنظيف',
            amount: o.amount || 0,
            payment_method: o.payment_method || 'cash',
            date: o.created_at!.toDate(),
            status: o.status,
        }));

    const now = new Date();
    const monthName = now.toLocaleDateString('ar-SA', { month: 'long', year: 'numeric' });

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">الإدارة المالية والمحاسبة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إيرادات وتكاليف شهر {monthName} — بيانات حية من قاعدة البيانات</p>
                </div>
                <button type="button" className="flex items-center gap-2 px-6 py-3 bg-white border border-slate-200 text-slate-800 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                    <Download size={18} className="text-blue-600" />
                    تصدير التقرير (Excel)
                </button>
            </div>

            {/* KPI Cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5">
                {/* Total Revenue */}
                <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-3xl p-6 text-white shadow-lg shadow-emerald-500/20 relative overflow-hidden col-span-1 md:col-span-2 lg:col-span-1">
                    <div className="absolute -left-4 -top-4 w-32 h-32 bg-white/10 rounded-full blur-2xl"></div>
                    <div className="relative z-10 flex justify-between items-start mb-4">
                        <div className="p-3 bg-white/20 rounded-2xl backdrop-blur-sm">
                            <DollarSign size={22} className="text-white" strokeWidth={2.5} />
                        </div>
                        <span className="flex items-center gap-1 bg-white/20 px-2 py-1 rounded-lg text-xs font-bold">
                            <ArrowUpRight size={14} /> هذا الشهر
                        </span>
                    </div>
                    <div className="relative z-10">
                        <p className="text-emerald-100 text-sm font-medium mb-1">إجمالي الإيرادات</p>
                        {loading ? (
                            <div className="h-8 w-32 bg-white/20 rounded-lg animate-pulse"></div>
                        ) : (
                            <h3 className="text-3xl font-extrabold">{formatCurrency(totalRevenue)} <span className="text-base font-bold text-emerald-200">ر.س</span></h3>
                        )}
                    </div>
                </div>

                {/* Net Profit */}
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-blue-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl group-hover:scale-110 transition-transform">
                            <TrendingUp size={22} strokeWidth={2.5} />
                        </div>
                    </div>
                    <p className="text-slate-500 text-sm font-medium mb-1">صافي الأرباح (بعد الرواتب)</p>
                    {loading ? (
                        <div className="h-7 w-28 bg-slate-100 rounded-lg animate-pulse"></div>
                    ) : (
                        <h3 className={`text-2xl font-extrabold ${netProfit >= 0 ? 'text-slate-800' : 'text-rose-600'}`}>
                            {formatCurrency(netProfit)} <span className="text-sm font-bold text-slate-400">ر.س</span>
                        </h3>
                    )}
                </div>

                {/* Total Payroll */}
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-amber-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-amber-50 text-amber-600 rounded-2xl group-hover:scale-110 transition-transform">
                            <Banknote size={22} strokeWidth={2.5} />
                        </div>
                    </div>
                    <p className="text-slate-500 text-sm font-medium mb-1">إجمالي الرواتب الشهرية</p>
                    {loading ? (
                        <div className="h-7 w-28 bg-slate-100 rounded-lg animate-pulse"></div>
                    ) : (
                        <h3 className="text-2xl font-extrabold text-slate-800">{formatCurrency(totalPayroll)} <span className="text-sm font-bold text-slate-400">ر.س</span></h3>
                    )}
                    <p className="text-xs text-slate-400 mt-1">{drivers.length} موظف</p>
                </div>

                {/* Order Count */}
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm relative overflow-hidden group hover:border-purple-200 transition-colors">
                    <div className="flex justify-between items-start mb-4">
                        <div className="p-3 bg-purple-50 text-purple-600 rounded-2xl group-hover:scale-110 transition-transform">
                            <ShoppingBag size={22} strokeWidth={2.5} />
                        </div>
                    </div>
                    <p className="text-slate-500 text-sm font-medium mb-1">الطلبات المكتملة</p>
                    {loading ? (
                        <div className="h-7 w-16 bg-slate-100 rounded-lg animate-pulse"></div>
                    ) : (
                        <h3 className="text-2xl font-extrabold text-slate-800">{orders.length} <span className="text-sm font-bold text-slate-400">طلب</span></h3>
                    )}
                    <p className="text-xs text-slate-400 mt-1">
                        متوسط {orders.length > 0 ? formatCurrency(totalRevenue / orders.length) : 0} ر.س / طلب
                    </p>
                </div>
            </div>

            {/* Payment Method Breakdown */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-sm lg:col-span-1">
                    <h3 className="text-base font-extrabold text-slate-800 mb-5 flex items-center gap-2">
                        <CreditCard size={18} className="text-blue-600" /> توزيع طرق الدفع
                    </h3>
                    {loading ? (
                        <div className="space-y-3">
                            {[1,2,3].map(i => <div key={i} className="h-14 bg-slate-50 rounded-2xl animate-pulse"></div>)}
                        </div>
                    ) : Object.keys(paymentBreakdown).length === 0 ? (
                        <div className="text-center py-8 text-slate-400 text-sm">لا توجد إيرادات هذا الشهر</div>
                    ) : (
                        <div className="space-y-3">
                            {Object.entries(paymentBreakdown).map(([method, amount]) => {
                                const pct = totalRevenue > 0 ? Math.round((amount / totalRevenue) * 100) : 0;
                                return (
                                    <div key={method} className="flex items-center gap-3">
                                        <div className="flex-1">
                                            <div className="flex justify-between items-center mb-1">
                                                <span className={`text-xs font-bold px-2 py-0.5 rounded-lg ${PAYMENT_COLORS[method] || 'bg-slate-50 text-slate-700'}`}>
                                                    {PAYMENT_LABELS[method] || method}
                                                </span>
                                                <span className="text-xs font-bold text-slate-500">{pct}%</span>
                                            </div>
                                            <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                                                {/* dynamic width requires inline style — Tailwind cannot purge arbitrary runtime values */}
                                                {/* eslint-disable-next-line */}
                                                <div className="h-full bg-gradient-to-r from-emerald-500 to-teal-500 rounded-full transition-all duration-500" style={{ width: `${pct}%` }}></div>
                                            </div>
                                            <p className="text-xs text-slate-400 mt-0.5 text-left">{formatCurrency(amount)} ر.س</p>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}

                    {/* Driver count summary */}
                    <div className="mt-6 pt-5 border-t border-slate-100">
                        <div className="flex items-center gap-2 text-sm text-slate-600 font-bold mb-3">
                            <Users size={16} className="text-slate-400" /> ملخص الموظفين
                        </div>
                        <div className="flex items-center justify-between">
                            <span className="text-sm text-slate-500">عدد السائقين</span>
                            <span className="font-extrabold text-slate-800">{drivers.length}</span>
                        </div>
                        <div className="flex items-center justify-between mt-1">
                            <span className="text-sm text-slate-500">متوسط الراتب</span>
                            <span className="font-bold text-slate-700">
                                {drivers.length > 0 ? formatCurrency(totalPayroll / drivers.length) : 0} ر.س
                            </span>
                        </div>
                    </div>
                </div>

                {/* Recent Transactions */}
                <div className="bg-white rounded-3xl border border-slate-100 shadow-sm lg:col-span-2 overflow-hidden">
                    <div className="p-6 border-b border-slate-100">
                        <h3 className="text-base font-extrabold text-slate-800 flex items-center gap-2">
                            <Wallet size={18} className="text-emerald-600" /> أحدث الحركات المالية
                        </h3>
                        <p className="text-xs text-slate-400 mt-1">آخر {transactions.length} طلب مكتمل هذا الشهر</p>
                    </div>

                    {loading ? (
                        <div className="p-6 space-y-3">
                            {[1,2,3,4,5].map(i => <div key={i} className="h-12 bg-slate-50 rounded-2xl animate-pulse"></div>)}
                        </div>
                    ) : transactions.length === 0 ? (
                        <div className="flex flex-col items-center justify-center py-16 text-slate-400">
                            <TrendingUp size={40} className="text-slate-200 mb-3" />
                            <p className="font-bold text-sm">لا توجد معاملات مكتملة هذا الشهر</p>
                        </div>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead>
                                    <tr className="text-xs text-slate-400 font-bold border-b border-slate-50">
                                        <th className="text-right px-6 py-3">العميل</th>
                                        <th className="text-right px-4 py-3">الخدمة</th>
                                        <th className="text-right px-4 py-3">طريقة الدفع</th>
                                        <th className="text-right px-4 py-3">المبلغ</th>
                                        <th className="text-right px-6 py-3">التاريخ</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-slate-50">
                                    {transactions.map(tx => (
                                        <tr key={tx.id} className="hover:bg-slate-50/60 transition-colors">
                                            <td className="px-6 py-3.5 font-bold text-slate-800">{tx.client_name}</td>
                                            <td className="px-4 py-3.5 text-slate-500">{tx.service_name}</td>
                                            <td className="px-4 py-3.5">
                                                <span className={`text-xs font-bold px-2.5 py-1 rounded-lg ${PAYMENT_COLORS[tx.payment_method] || 'bg-slate-50 text-slate-600'}`}>
                                                    {PAYMENT_LABELS[tx.payment_method] || tx.payment_method}
                                                </span>
                                            </td>
                                            <td className="px-4 py-3.5 font-extrabold text-emerald-600">{formatCurrency(tx.amount)} ر.س</td>
                                            <td className="px-6 py-3.5 text-slate-400 text-xs">
                                                {tx.date.toLocaleDateString('ar-SA', { day: 'numeric', month: 'short' })}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
