import { TrendingUp, Users, CarFront, CheckCircle2, Clock, ChevronLeft, ArrowUpRight } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { collection, onSnapshot, query, where, orderBy, limit, Timestamp, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface RecentOrder {
    id: string;
    client: string;
    service: string;
    amount: string;
    status: string;
    time: string;
    avatar: string;
}

interface StatCardProps {
    title: string;
    value: string;
    icon: LucideIcon;
    trend: string;
    trendUp: boolean;
    colorScheme: 'blue' | 'orange' | 'indigo' | 'emerald';
}

const colorMaps = {
    blue: {
        bg: 'bg-[#FAF1F6]/80',
        text: 'text-[#660033]',
        iconBg: 'bg-white',
        shadow: 'shadow-[#660033]/10'
    },
    orange: {
        bg: 'bg-orange-50/80',
        text: 'text-orange-600',
        iconBg: 'bg-white',
        shadow: 'shadow-orange-500/10'
    },
    indigo: {
        bg: 'bg-[#FAF1F6]/80',
        text: 'text-[#660033]',
        iconBg: 'bg-white',
        shadow: 'shadow-[#8E2B5C]/10'
    },
    emerald: {
        bg: 'bg-emerald-50/80',
        text: 'text-emerald-600',
        iconBg: 'bg-white',
        shadow: 'shadow-emerald-500/10'
    }
};

const StatCard = ({ title, value, icon: Icon, trend, trendUp, colorScheme }: StatCardProps) => {
    const scheme = colorMaps[colorScheme];

    return (
        <div className="bg-white rounded-[24px] p-7 shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 flex flex-col hover:shadow-[0_8px_30px_rgb(0,0,0,0.06)] hover:-translate-y-1 transition-all duration-300 relative overflow-hidden group">
            <div className={`absolute -right-10 -top-10 w-32 h-32 rounded-full ${scheme.bg} opacity-50 blur-2xl group-hover:scale-150 transition-transform duration-700`}></div>
            <div className="flex justify-between items-start relative z-10">
                <div>
                    <p className="text-slate-500 font-bold mb-2 text-sm">{title}</p>
                    <h3 className="text-3xl font-black text-slate-800 tracking-tight">{value}</h3>
                </div>
                <div className={`p-4 rounded-2xl ${scheme.bg} ${scheme.text} shadow-sm group-hover:scale-110 transition-transform duration-300`}>
                    <Icon size={24} strokeWidth={2.5} />
                </div>
            </div>
            <div className="mt-6 flex items-center space-x-2 space-x-reverse text-sm relative z-10 w-full bg-slate-50/50 rounded-xl p-2 px-3 border border-slate-100">
                <span className={`flex items-center justify-center font-bold px-2 py-0.5 rounded-md ${trendUp ? 'bg-emerald-100/50 text-emerald-600' : 'bg-red-100/50 text-red-600'}`}>
                    <TrendingUp size={14} className={`ml-1 ${!trendUp && 'rotate-180'} ${trendUp ? 'text-emerald-500' : 'text-red-500'}`} strokeWidth={3} />
                    <span dir="ltr">{trend}%</span>
                </span>
                <span className="text-slate-400 font-medium">مقارنة بالشهر الماضي</span>
            </div>
        </div>
    );
};

export default function Dashboard() {
    const navigate = useNavigate();
    const [totalUsers, setTotalUsers] = useState('...');
    const [activeOrders, setActiveOrders] = useState('...');
    const [availableDrivers, setAvailableDrivers] = useState('...');
    const [totalRevenue, setTotalRevenue] = useState(0);
    const [storeRevenue, setStoreRevenue] = useState(0);
    // إيراد متجر الأدوات والتنظيف صار في `orders` (طلبات مجدولة) — نجمعه منفصلاً كي
    // يُنسب لإيراد المتجر لا الخدمات. متجر الشركات يبقى في store_orders (storeRevenue).
    const [clientStoreRevenue, setClientStoreRevenue] = useState(0);
    const [pendingStoreOrders, setPendingStoreOrders] = useState('...');
    const [recentOrders, setRecentOrders] = useState<RecentOrder[]>([]);
    
    // Trend state
    const [revenueTrend, setRevenueTrend] = useState('0');
    const [ordersTrend, setOrdersTrend] = useState('0');
    const [usersTrend, setUsersTrend] = useState('0');

    // Live stats from Firestore
    useEffect(() => {
        // Date helpers for trends
        const now = new Date();
        const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
        const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const thisMonthTs = Timestamp.fromDate(thisMonthStart);
        const lastMonthTs = Timestamp.fromDate(lastMonthStart);

        const unsubUsers = onSnapshot(collection(db, 'users'), (snap: QuerySnapshot<DocumentData>) => {
            const total = snap.size;
            setTotalUsers(total.toString());
            let thisMonth = 0, lastMonth = 0;
            snap.forEach((doc: QueryDocumentSnapshot<DocumentData>) => {
                const createdAt = (doc.data() as { created_at?: Timestamp }).created_at;
                if (createdAt && createdAt >= thisMonthTs) thisMonth++;
                else if (createdAt && createdAt >= lastMonthTs) lastMonth++;
            });
            if (lastMonth > 0) {
                const pct = (((thisMonth - lastMonth) / lastMonth) * 100).toFixed(1);
                setUsersTrend(pct);
            }
        });
        const unsubOrders = onSnapshot(
            query(collection(db, 'orders'), where('status', 'in', ['pending', 'in_progress', 'accepted'])),
            (snap: QuerySnapshot<DocumentData>) => setActiveOrders(snap.size.toString())
        );
        const unsubDrivers = onSnapshot(
            query(collection(db, 'drivers'), where('is_available', '==', true)),
            (snap: QuerySnapshot<DocumentData>) => setAvailableDrivers(snap.size.toString())
        );
        const unsubCompletedOrders = onSnapshot(
            query(collection(db, 'orders'), where('status', '==', 'completed')),
            (snap: QuerySnapshot<DocumentData>) => {
                let revenue = 0, clientStoreRev = 0, thisMonthRev = 0, lastMonthRev = 0;
                let thisMonthOrders = 0, lastMonthOrders = 0;
                snap.forEach((doc: QueryDocumentSnapshot<DocumentData>) => {
                    const d = doc.data() as { amount?: number; created_at?: Timestamp; service_meta?: { kind?: string } };
                    const amt = d.amount || 0;
                    // طلبات متجر الأدوات (service_meta.kind == 'store_products') مبيعات متجر لا
                    // خدمات — تُنسب لإيراد المتجر ولا تدخل بطاقة/اتجاه إيرادات الخدمات.
                    if (d.service_meta?.kind === 'store_products') {
                        clientStoreRev += amt;
                        return;
                    }
                    revenue += amt;
                    if (d.created_at && d.created_at >= thisMonthTs) {
                        thisMonthRev += amt;
                        thisMonthOrders++;
                    } else if (d.created_at && d.created_at >= lastMonthTs) {
                        lastMonthRev += amt;
                        lastMonthOrders++;
                    }
                });
                setTotalRevenue(revenue);
                setClientStoreRevenue(clientStoreRev);
                if (lastMonthRev > 0) setRevenueTrend((((thisMonthRev - lastMonthRev) / lastMonthRev) * 100).toFixed(1));
                if (lastMonthOrders > 0) setOrdersTrend((((thisMonthOrders - lastMonthOrders) / lastMonthOrders) * 100).toFixed(1));
            }
        );
        const unsubRecentOrders = onSnapshot(
            query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(5)),
            (snap: QuerySnapshot<DocumentData>) => {
                const fetchedOrders: RecentOrder[] = snap.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => {
                    const data = doc.data() as { client_name?: string; client_id?: string; service_type?: string; amount?: number; status?: string; created_at?: Timestamp };
                    const date = data.created_at?.toDate();
                    return {
                        id: `#ORD-${doc.id.substring(0, 4).toUpperCase()}`,
                        client: data.client_name || (data.client_id ? `عميل ${data.client_id.substring(0, 4)}` : 'زائر'),
                        service: data.service_type || 'خدمة غير محددة',
                        amount: data.amount?.toString() || '0',
                        status: data.status || 'pending',
                        time: date ? new Intl.DateTimeFormat('ar-SA', { month: 'short', day: 'numeric', hour: 'numeric', minute: 'numeric' }).format(date) : 'الآن',
                        avatar: data.client_name ? data.client_name.substring(0, 1) : (data.client_id ? data.client_id.substring(0, 1).toUpperCase() : 'U')
                    };
                });
                setRecentOrders(fetchedOrders);
            }
        );

        const unsubStoreOrders = onSnapshot(collection(db, 'store_orders'), (snap: QuerySnapshot<DocumentData>) => {
            let sRev = 0;
            let pendingCount = 0;
            snap.forEach((doc: QueryDocumentSnapshot<DocumentData>) => {
                const d = doc.data() as { total_amount?: number; status?: string; is_paid?: boolean };
                // الطلب المدفوع يمرّ بـ processing/shipped/delivered — كان يُحسب approved فقط
                // فتُستبعَد إيرادات المتجر المدفوعة من اللوحة.
                if (d.is_paid === true || ['approved', 'processing', 'shipped', 'delivered', 'completed'].includes(d.status || '')) {
                    sRev += d.total_amount || 0;
                }
                if (d.status === 'pending') pendingCount++;
            });
            setStoreRevenue(sRev);
            setPendingStoreOrders(pendingCount.toString());
        });

        return () => { unsubUsers(); unsubOrders(); unsubDrivers(); unsubCompletedOrders(); unsubRecentOrders(); unsubStoreOrders(); };
    }, []);

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'completed': return <span className="px-3 py-1.5 rounded-xl bg-emerald-50 text-emerald-600 text-xs font-bold flex items-center w-fit border border-emerald-100"><CheckCircle2 size={14} strokeWidth={2.5} className="ml-1.5" /> مكتمل</span>;
            case 'active': return <span className="px-3 py-1.5 rounded-xl bg-[#FAF1F6] text-[#660033] text-xs font-bold flex items-center w-fit border border-[#F2DEE9]"><Clock size={14} strokeWidth={2.5} className="ml-1.5" /> جاري التنفيذ</span>;
            case 'pending': return <span className="px-3 py-1.5 rounded-xl bg-orange-50 text-orange-600 text-xs font-bold flex items-center w-fit border border-orange-100"><Clock size={14} strokeWidth={2.5} className="ml-1.5" /> قيد الانتظار</span>;
            default: return null;
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">

            <div className="flex justify-between items-end mb-2">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">نظرة عامة على الأداء</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إحصائيات المنصة حتى اليوم</p>
                </div>
            </div>

            {/* Services Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
                <StatCard title="إجمالي الإيرادات (الخدمات)" value={`${totalRevenue.toFixed(0)} ر.س`} icon={TrendingUp} trend={revenueTrend} trendUp={parseFloat(revenueTrend) >= 0} colorScheme="blue" />
                <StatCard title="الطلبات النشطة" value={activeOrders} icon={Clock} trend={ordersTrend} trendUp={parseFloat(ordersTrend) >= 0} colorScheme="orange" />
                <StatCard title="السائقين المتاحين" value={availableDrivers} icon={CarFront} trend="0" trendUp colorScheme="indigo" />
                <StatCard title="إجمالي المستخدمين" value={totalUsers} icon={Users} trend={usersTrend} trendUp={parseFloat(usersTrend) >= 0} colorScheme="emerald" />
            </div>

            <div className="pt-4">
                <h3 className="text-lg font-extrabold text-slate-800 mb-4 flex items-center gap-2">
                    <ArrowUpRight className="text-[#660033]" size={20} />
                    إحصائيات متجر الأدوات
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <StatCard title="إيرادات المتجر" value={`${(storeRevenue + clientStoreRevenue).toFixed(0)} ر.س`} icon={TrendingUp} trend="100" trendUp colorScheme="blue" />
                    <StatCard title="طلبات بانتظار الموافقة" value={pendingStoreOrders} icon={Clock} trend="0" trendUp colorScheme="orange" />
                    <StatCard title="إجمالي الدخل الكلي" value={`${(totalRevenue + storeRevenue + clientStoreRevenue).toFixed(0)} ر.س`} icon={TrendingUp} trend="+" trendUp colorScheme="emerald" />
                </div>
            </div>

            <div className="grid grid-cols-1 gap-8">

                {/* Recent Orders List */}
                <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden flex flex-col">
                    <div className="p-6 md:p-8 border-b border-slate-100 flex justify-between items-center bg-white/50 backdrop-blur-sm">
                        <div>
                            <h3 className="text-lg font-extrabold text-slate-800">أحدث الطلبات</h3>
                            <p className="text-sm font-medium text-slate-400 mt-1">آخر 5 طلبات مسجلة في النظام</p>
                        </div>
                        <button type="button" onClick={() => navigate('/orders')} className="text-[#660033] bg-[#FAF1F6] hover:bg-[#F2DEE9] px-4 py-2 rounded-xl text-sm font-bold transition-colors flex items-center">
                            <span>عرض الكل</span>
                            <ChevronLeft size={16} className="mr-1" />
                        </button>
                    </div>
                    <div className="overflow-x-auto flex-1">
                        <table className="w-full text-right bg-white min-w-[700px]">
                            <thead className="bg-[#f8fafc] text-slate-400 text-xs uppercase tracking-wider font-bold border-y border-slate-100">
                                <tr>
                                    <th className="px-8 py-5">رقم الطلب</th>
                                    <th className="px-8 py-5">العميل</th>
                                    <th className="px-8 py-5">الخدمة</th>
                                    <th className="px-8 py-5">المبلغ</th>
                                    <th className="px-8 py-5 w-40">الحالة</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100/80">
                                {recentOrders.map((order: RecentOrder) => (
                                    <tr key={order.id} className="hover:bg-slate-50/70 transition-colors group">
                                        <td className="px-8 py-5">
                                            <span className="font-extrabold text-slate-700">{order.id}</span>
                                        </td>
                                        <td className="px-8 py-5">
                                            <div className="flex items-center space-x-3 space-x-reverse">
                                                <div className="w-10 h-10 rounded-xl bg-slate-100 text-slate-500 flex items-center justify-center font-bold shadow-sm">
                                                    {order.avatar}
                                                </div>
                                                <div>
                                                    <p className="font-bold text-slate-800 group-hover:text-[#660033] transition-colors">{order.client}</p>
                                                    <p className="text-xs font-semibold text-slate-400 mt-0.5">{order.time}</p>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-8 py-5">
                                            <span className="font-semibold text-slate-600">{order.service}</span>
                                        </td>
                                        <td className="px-8 py-5">
                                            <span className="font-extrabold text-slate-800 bg-slate-100 px-3 py-1.5 rounded-lg">{order.amount} ر.س</span>
                                        </td>
                                        <td className="px-8 py-5">{getStatusBadge(order.status)}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>            </div>
        </div>
    );
}

