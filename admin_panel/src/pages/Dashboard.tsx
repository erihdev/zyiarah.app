import { TrendingUp, Users, CarFront, CheckCircle2, Clock } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

interface StatCardProps {
    title: string;
    value: string;
    icon: LucideIcon;
    trend: string;
    trendUp: boolean;
    color: string;
}

const StatCard = ({ title, value, icon: Icon, trend, trendUp, color }: StatCardProps) => (
    <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 flex flex-col hover:shadow-md transition-shadow">
        <div className="flex justify-between items-start">
            <div>
                <p className="text-slate-500 font-medium mb-1">{title}</p>
                <h3 className="text-3xl font-bold text-slate-800">{value}</h3>
            </div>
            <div className={`p-3 rounded-xl bg-${color}-50 text-${color}-600`}>
                <Icon size={24} strokeWidth={2.5} />
            </div>
        </div>
        <div className="mt-4 flex items-center space-x-2 space-x-reverse text-sm">
            <span className={`flex items-center font-bold ${trendUp ? 'text-emerald-500' : 'text-red-500'}`}>
                {trendUp ? '+' : '-'}{trend}%
                <TrendingUp size={14} className={`ml-1 ${!trendUp && 'rotate-180'}`} />
            </span>
            <span className="text-slate-400">مقارنة بالشهر الماضي</span>
        </div>
    </div>
);

export default function Dashboard() {
    const recentOrders = [
        { id: 'ORD-8943', client: 'محمد عبدالله', service: 'نظافة منزلية', amount: '150', status: 'pending', time: 'منذ 10 دقائق' },
        { id: 'ORD-8942', client: 'سارة أحمد', service: 'رعاية أطفال', amount: '200', status: 'active', time: 'منذ ساعتين' },
        { id: 'ORD-8941', client: 'خالد الفهد', service: 'صيانة خفيفة', amount: '100', status: 'completed', time: 'اليوم 10:30 ص' },
        { id: 'ORD-8940', client: 'نورة السعيد', service: 'كي وغسيل', amount: '50', status: 'completed', time: 'أمس 04:15 م' },
    ];

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'completed': return <span className="px-3 py-1 rounded-full bg-emerald-100 text-emerald-700 text-xs font-bold flex items-center w-fit"><CheckCircle2 size={12} className="ml-1" /> مكتمل</span>;
            case 'active': return <span className="px-3 py-1 rounded-full bg-blue-100 text-blue-700 text-xs font-bold flex items-center w-fit"><Clock size={12} className="ml-1" /> قيد التنفيذ</span>;
            case 'pending': return <span className="px-3 py-1 rounded-full bg-orange-100 text-orange-700 text-xs font-bold flex items-center w-fit"><Clock size={12} className="ml-1" /> قيد الانتظار</span>;
            default: return null;
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">

            {/* Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <StatCard title="إجمالي الإيرادات" value="124,500 ر.س" icon={TrendingUp} trend="12.5" trendUp={true} color="blue" />
                <StatCard title="الطلبات النشطة" value="34" icon={Clock} trend="4.2" trendUp={true} color="orange" />
                <StatCard title="السائقين المتاحين" value="18" icon={CarFront} trend="2.1" trendUp={false} color="indigo" />
                <StatCard title="العملاء الجدد" value="142" icon={Users} trend="8.4" trendUp={true} color="emerald" />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

                {/* Recent Orders List */}
                <div className="lg:col-span-2 bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
                    <div className="p-6 border-b border-slate-100 flex justify-between items-center">
                        <h3 className="text-lg font-bold text-slate-800">أحدث الطلبات</h3>
                        <button className="text-blue-600 text-sm font-bold hover:text-blue-700">عرض الكل</button>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="w-full text-right bg-white">
                            <thead className="bg-slate-50 text-slate-500 text-sm">
                                <tr>
                                    <th className="px-6 py-4 font-medium">رقم الطلب</th>
                                    <th className="px-6 py-4 font-medium">العميل</th>
                                    <th className="px-6 py-4 font-medium">الخدمة</th>
                                    <th className="px-6 py-4 font-medium">المبلغ</th>
                                    <th className="px-6 py-4 font-medium">الحالة</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                                {recentOrders.map((order) => (
                                    <tr key={order.id} className="hover:bg-slate-50/50 transition-colors">
                                        <td className="px-6 py-4 font-bold text-slate-700">{order.id}</td>
                                        <td className="px-6 py-4">
                                            <p className="font-bold text-slate-800">{order.client}</p>
                                            <p className="text-xs text-slate-400">{order.time}</p>
                                        </td>
                                        <td className="px-6 py-4 text-slate-600">{order.service}</td>
                                        <td className="px-6 py-4 font-bold text-emerald-600">{order.amount} ر.س</td>
                                        <td className="px-6 py-4">{getStatusBadge(order.status)}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Driver Map Widget Placeholder */}
                <div className="bg-slate-900 rounded-2xl p-6 text-white relative overflow-hidden group">
                    <div className="absolute inset-0 opacity-20 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-blue-400 via-slate-900 to-slate-900 mix-blend-overlay"></div>
                    <div className="relative z-10 flex flex-col h-full justify-between">
                        <div>
                            <div className="flex items-center justify-between mb-2">
                                <h3 className="text-lg font-bold">تتبع السائقين الحي</h3>
                                <span className="w-3 h-3 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_10px_rgba(16,185,129,0.8)]"></span>
                            </div>
                            <p className="text-slate-400 text-sm">جميع الشركاء متصلين بالنظام</p>
                        </div>

                        <div className="my-8 flex-1 border-2 border-slate-700/50 border-dashed rounded-xl flex items-center justify-center bg-slate-800/30">
                            <div className="text-center">
                                <CarFront size={48} className="mx-auto mb-3 text-slate-500 group-hover:text-blue-400 transition-colors" />
                                <p className="text-slate-400 font-medium text-sm">أكمل ربط Firebase Web Map<br />لعرض الحركة المباشرة</p>
                            </div>
                        </div>

                        <button className="w-full bg-blue-600 hover:bg-blue-500 text-white font-bold py-3 rounded-xl transition-colors shadow-lg shadow-blue-500/20">
                            فتح الخريطة الكاملة
                        </button>
                    </div>
                </div>

            </div>
        </div>
    );
}
