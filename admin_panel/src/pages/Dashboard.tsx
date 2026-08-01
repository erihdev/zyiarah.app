import { TrendingUp, Users, CarFront, CheckCircle2, Clock, ChevronLeft, ArrowUpRight } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { collection, onSnapshot, query, where, orderBy, limit, Timestamp, getCountFromServer, getAggregateFromServer, sum, or, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
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
    // null = «لم يُحمَّل بعد»: الإيرادات كانت تبدأ بـ0 فيظهر «0 ر.س» كرقم حقيقي
    // عند فشل التحميل — لا نعرض صفراً إلا إن جاء من الخادم فعلاً.
    const [totalRevenue, setTotalRevenue] = useState<number | null>(null);
    const [storeRevenue, setStoreRevenue] = useState<number | null>(null);
    // إيراد متجر الأدوات والتنظيف صار في `orders` (طلبات مجدولة) — نجمعه منفصلاً كي
    // يُنسب لإيراد المتجر لا الخدمات. متجر الشركات يبقى في store_orders (storeRevenue).
    const [clientStoreRevenue, setClientStoreRevenue] = useState<number | null>(null);
    const [pendingStoreOrders, setPendingStoreOrders] = useState('...');
    const [recentOrders, setRecentOrders] = useState<RecentOrder[]>([]);
    // خطأ أي مستمع/تجميع يرفع لافتة خطأ بزر إعادة — كانت البطاقات تتجمد على «...»
    // للأبد بلا أي مؤشر (أخطاء مستمعي Firestore نهائية ولا يُعاد الاشتراك تلقائياً).
    const [loadError, setLoadError] = useState(false);
    const [retryKey, setRetryKey] = useState(0);

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

        // معالج خطأ موحّد: لا فشل صامت — أي مستمع/تجميع يفشل يرفع لافتة الخطأ.
        const onErr = (label: string) => (e: unknown) => {
            console.error(`Dashboard ${label} error:`, e);
            setLoadError(true);
        };

        // (أداء) كانت اللوحة تستمع لمجموعة users كاملة لمجرّد العدّ — الآن استعلامات
        // تجميع count() خادمية: قراءة فهرس واحدة لكل 1000 مستند بدل قراءة كل مستند.
        (async () => {
            try {
                const usersCol = collection(db, 'users');
                const [totalSnap, thisSnap, lastSnap] = await Promise.all([
                    getCountFromServer(usersCol),
                    getCountFromServer(query(usersCol, where('created_at', '>=', thisMonthTs))),
                    getCountFromServer(query(usersCol, where('created_at', '>=', lastMonthTs), where('created_at', '<', thisMonthTs))),
                ]);
                setTotalUsers(totalSnap.data().count.toString());
                const thisMonth = thisSnap.data().count, lastMonth = lastSnap.data().count;
                if (lastMonth > 0) {
                    setUsersTrend((((thisMonth - lastMonth) / lastMonth) * 100).toFixed(1));
                }
            } catch (e) { onErr('users count')(e); }
        })();
        const unsubOrders = onSnapshot(
            // كل الحالات غير المنتهية فعلاً — كانت [pending, in_progress, accepted] فقط،
            // فيسقط الطلب من «الطلبات النشطة» لحظةَ إسناده (scheduled) وهو أنشط ما يكون.
            query(collection(db, 'orders'), where('status', 'in', [
                'pending', 'pending_admin_approval', 'under_review', 'awaiting_payment',
                'scheduled', 'assigned', 'accepted', 'on_the_way', 'in_progress',
            ])),
            (snap: QuerySnapshot<DocumentData>) => setActiveOrders(snap.size.toString()),
            onErr('active orders')
        );
        const unsubDrivers = onSnapshot(
            query(collection(db, 'drivers'), where('is_available', '==', true)),
            (snap: QuerySnapshot<DocumentData>) => setAvailableDrivers(snap.size.toString()),
            onErr('drivers')
        );
        // (أداء) الإيراد الكلي كان يُجمَع بالاستماع لكل الطلبات المكتملة منذ الأزل
        // (قراءات تنمو للأبد مع كل فتح للوحة) — الآن تجميع sum() خادمي: استعلامان
        // بمساواة فقط (لا فهرس مركّب)، وطلبات متجر الأدوات تُطرح لتُنسب للمتجر.
        (async () => {
            try {
                const completedQ = query(collection(db, 'orders'), where('status', '==', 'completed'));
                const storeKindQ = query(
                    collection(db, 'orders'),
                    where('status', '==', 'completed'),
                    where('service_meta.kind', '==', 'store_products'),
                );
                const [allAgg, storeAgg] = await Promise.all([
                    getAggregateFromServer(completedQ, { total: sum('amount') }),
                    getAggregateFromServer(storeKindQ, { total: sum('amount') }),
                ]);
                const storeRev = storeAgg.data().total || 0;
                setClientStoreRevenue(storeRev);
                setTotalRevenue((allAgg.data().total || 0) - storeRev);
            } catch (e) { onErr('revenue aggregate')(e); }
        })();
        // اتجاهات الشهر: نافذة محدودة (شهران فقط) بدل كامل التاريخ — نطاق created_at
        // فهرس أحادي لا يحتاج فهرساً مركّباً، والفلترة تتم محلياً على النافذة الصغيرة.
        const unsubTrends = onSnapshot(
            query(collection(db, 'orders'), where('created_at', '>=', lastMonthTs)),
            (snap: QuerySnapshot<DocumentData>) => {
                let thisMonthRev = 0, lastMonthRev = 0, thisMonthOrders = 0, lastMonthOrders = 0;
                snap.forEach((doc: QueryDocumentSnapshot<DocumentData>) => {
                    const d = doc.data() as { amount?: number; status?: string; created_at?: Timestamp; service_meta?: { kind?: string } };
                    // طلبات متجر الأدوات (service_meta.kind == 'store_products') مبيعات متجر لا
                    // خدمات — لا تدخل اتجاه إيرادات الخدمات.
                    if (d.status !== 'completed' || d.service_meta?.kind === 'store_products') return;
                    const amt = d.amount || 0;
                    if (d.created_at && d.created_at >= thisMonthTs) {
                        thisMonthRev += amt;
                        thisMonthOrders++;
                    } else {
                        lastMonthRev += amt;
                        lastMonthOrders++;
                    }
                });
                if (lastMonthRev > 0) setRevenueTrend((((thisMonthRev - lastMonthRev) / lastMonthRev) * 100).toFixed(1));
                if (lastMonthOrders > 0) setOrdersTrend((((thisMonthOrders - lastMonthOrders) / lastMonthOrders) * 100).toFixed(1));
            },
            onErr('month trends')
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
            },
            onErr('recent orders')
        );

        // (أداء) store_orders: كانت المجموعة كلها تُستمَع لاشتقاق رقمين فقط — الآن
        // عدّاد المعلّق بمستمع مقيّد بالحالة (مجموعة صغيرة حيّة)، والإيراد بتجميع
        // sum() خادمي بنفس شرط «مدفوع» السابق (الطلب المدفوع يمرّ بـ
        // processing/shipped/delivered لا approved فقط).
        const unsubPendingStore = onSnapshot(
            query(collection(db, 'store_orders'), where('status', '==', 'pending')),
            (snap: QuerySnapshot<DocumentData>) => setPendingStoreOrders(snap.size.toString()),
            onErr('pending store orders')
        );
        (async () => {
            try {
                const agg = await getAggregateFromServer(
                    query(collection(db, 'store_orders'), or(
                        where('is_paid', '==', true),
                        where('status', 'in', ['approved', 'processing', 'shipped', 'delivered', 'completed']),
                    )),
                    { total: sum('total_amount') }
                );
                setStoreRevenue(agg.data().total || 0);
            } catch (e) { onErr('store revenue aggregate')(e); }
        })();

        return () => { unsubOrders(); unsubDrivers(); unsubTrends(); unsubRecentOrders(); unsubPendingStore(); };
    }, [retryKey]);

    const getStatusBadge = (status: string) => {
        // كانت تعرف 3 حالات فقط وتُعيد null لغيرها — فمعظم صفوف «أحدث الطلبات»
        // بعد السبرنت (scheduled/on_the_way/…) كانت بخانة حالة فارغة.
        const chip = (bg: string, text: string, border: string, label: string) => (
            <span className={`px-3 py-1.5 rounded-xl ${bg} ${text} text-xs font-bold flex items-center w-fit border ${border}`}>
                <Clock size={14} strokeWidth={2.5} className="ml-1.5" /> {label}
            </span>
        );
        switch (status) {
            case 'completed': return <span className="px-3 py-1.5 rounded-xl bg-emerald-50 text-emerald-600 text-xs font-bold flex items-center w-fit border border-emerald-100"><CheckCircle2 size={14} strokeWidth={2.5} className="ml-1.5" /> مكتمل</span>;
            case 'in_progress': return chip('bg-[#FAF1F6]', 'text-[#660033]', 'border-[#F2DEE9]', 'جاري التنفيذ');
            case 'on_the_way': return chip('bg-cyan-50', 'text-cyan-700', 'border-cyan-100', 'في الطريق');
            case 'scheduled':
            case 'assigned': return chip('bg-teal-50', 'text-teal-700', 'border-teal-100', 'تم تعيين السائق');
            case 'accepted': return chip('bg-[#FAF1F6]', 'text-[#660033]', 'border-[#F2DEE9]', 'تم القبول');
            case 'under_review':
            case 'pending_admin_approval': return chip('bg-orange-50', 'text-orange-600', 'border-orange-100', 'تحت المراجعة');
            case 'awaiting_payment': return chip('bg-amber-50', 'text-amber-700', 'border-amber-100', 'بانتظار الدفع');
            case 'cancelled': return chip('bg-rose-50', 'text-rose-600', 'border-rose-100', 'ملغي');
            case 'pending': return chip('bg-orange-50', 'text-orange-600', 'border-orange-100', 'قيد الانتظار');
            default: return chip('bg-slate-50', 'text-slate-600', 'border-slate-200', status);
        }
    };

    // لا نعرض «0 ر.س» قبل اكتمال التحميل أو بعد فشله — «...» حتى يصل رقم حقيقي.
    const sar = (v: number | null) => v === null ? '...' : `${v.toFixed(0)} ر.س`;

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">

            <div className="flex justify-between items-end mb-2">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">نظرة عامة على الأداء</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إحصائيات المنصة حتى اليوم</p>
                </div>
            </div>

            {loadError && (
                <div className="flex flex-col sm:flex-row items-center justify-between gap-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-2xl px-6 py-4">
                    <span className="font-bold text-sm">تعذّر تحميل بعض إحصائيات اللوحة — الأرقام المعروضة قد تكون ناقصة.</span>
                    <button
                        type="button"
                        onClick={() => { setLoadError(false); setRetryKey(k => k + 1); }}
                        className="px-5 py-2.5 bg-rose-600 text-white rounded-xl font-bold text-sm hover:bg-rose-700 transition-colors shrink-0"
                    >
                        إعادة المحاولة
                    </button>
                </div>
            )}

            {/* Services Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
                <StatCard title="إجمالي الإيرادات (الخدمات)" value={sar(totalRevenue)} icon={TrendingUp} trend={revenueTrend} trendUp={parseFloat(revenueTrend) >= 0} colorScheme="blue" />
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
                    <StatCard title="إيرادات المتجر" value={storeRevenue === null || clientStoreRevenue === null ? '...' : sar(storeRevenue + clientStoreRevenue)} icon={TrendingUp} trend="100" trendUp colorScheme="blue" />
                    <StatCard title="طلبات بانتظار الموافقة" value={pendingStoreOrders} icon={Clock} trend="0" trendUp colorScheme="orange" />
                    <StatCard title="إجمالي الدخل الكلي" value={totalRevenue === null || storeRevenue === null || clientStoreRevenue === null ? '...' : sar(totalRevenue + storeRevenue + clientStoreRevenue)} icon={TrendingUp} trend="+" trendUp colorScheme="emerald" />
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

