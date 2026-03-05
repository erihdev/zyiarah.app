import { TrendingUp, Users, CarFront, CheckCircle2, Clock, Map as MapIcon, ChevronLeft, ArrowUpRight } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { collection, onSnapshot, query, where, orderBy, limit } from 'firebase/firestore';
import { db } from '../services/firebase';

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
        bg: 'bg-blue-50/80',
        text: 'text-blue-600',
        iconBg: 'bg-white',
        shadow: 'shadow-blue-500/10'
    },
    orange: {
        bg: 'bg-orange-50/80',
        text: 'text-orange-600',
        iconBg: 'bg-white',
        shadow: 'shadow-orange-500/10'
    },
    indigo: {
        bg: 'bg-indigo-50/80',
        text: 'text-indigo-600',
        iconBg: 'bg-white',
        shadow: 'shadow-indigo-500/10'
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
    const mapContainer = useRef<HTMLDivElement>(null);
    const map = useRef<mapboxgl.Map | null>(null);
    const markersRef = useRef<{ [key: string]: mapboxgl.Marker }>({});
    const [totalUsers, setTotalUsers] = useState('...');
    const [activeOrders, setActiveOrders] = useState('...');
    const [availableDrivers, setAvailableDrivers] = useState('...');
    const [totalRevenue, setTotalRevenue] = useState(0);
    const [recentOrders, setRecentOrders] = useState<any[]>([]);

    // Live stats from Firestore
    useEffect(() => {
        const unsubUsers = onSnapshot(collection(db, 'users'), (snap: any) => {
            setTotalUsers(snap.size.toString());
        });
        const unsubOrders = onSnapshot(
            query(collection(db, 'orders'), where('status', 'in', ['pending', 'in_progress'])),
            (snap: any) => setActiveOrders(snap.size.toString())
        );
        const unsubDrivers = onSnapshot(
            query(collection(db, 'drivers'), where('is_available', '==', true)),
            (snap: any) => setAvailableDrivers(snap.size.toString())
        );
        const unsubCompletedOrders = onSnapshot(
            query(collection(db, 'orders'), where('status', '==', 'completed')),
            (snap: any) => {
                let revenue = 0;
                snap.forEach((doc: any) => {
                    revenue += doc.data().amount || 0;
                });
                setTotalRevenue(revenue);
            }
        );
        const unsubRecentOrders = onSnapshot(
            query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(5)),
            (snap: any) => {
                const fetchedOrders = snap.docs.map((doc: any) => {
                    const data = doc.data();
                    const date = data.created_at?.toDate();
                    return {
                        id: `#ORD-${doc.id.substring(0, 4).toUpperCase()}`,
                        client: data.client_id ? `عميل ${data.client_id.substring(0, 4)}` : 'زائر',
                        service: data.service_type || 'خدمة غير محددة',
                        amount: data.amount?.toString() || '0',
                        status: data.status || 'pending',
                        time: date ? new Intl.DateTimeFormat('ar-SA', { month: 'short', day: 'numeric', hour: 'numeric', minute: 'numeric' }).format(date) : 'الآن',
                        avatar: data.client_id ? data.client_id.substring(0, 1).toUpperCase() : 'U'
                    };
                });
                setRecentOrders(fetchedOrders);
            }
        );
        return () => { unsubUsers(); unsubOrders(); unsubDrivers(); unsubCompletedOrders(); unsubRecentOrders(); };
    }, []);

    useEffect(() => {
        if (map.current || !mapContainer.current) return;

        mapboxgl.accessToken = import.meta.env.VITE_MAPBOX_TOKEN;
        map.current = new mapboxgl.Map({
            container: mapContainer.current,
            style: 'mapbox://styles/mapbox/dark-v11',
            center: [46.6753, 24.7136],
            zoom: 11
        });

        map.current.addControl(new mapboxgl.NavigationControl(), 'bottom-right');

        // Live Drivers Data Markers from Firestore
        const unsubDriversMap = onSnapshot(
            query(collection(db, 'drivers'), where('is_available', '==', true)),
            (snapshot: any) => {
                const currentDriverIds = new Set<string>();

                snapshot.forEach((doc: any) => {
                    const data = doc.data();
                    const id = doc.id;
                    currentDriverIds.add(id);

                    if (data.location && typeof data.location.latitude === 'number' && typeof data.location.longitude === 'number') {
                        const lng = data.location.longitude;
                        const lat = data.location.latitude;

                        if (markersRef.current[id]) {
                            markersRef.current[id].setLngLat([lng, lat]);
                        } else {
                            const marker = new mapboxgl.Marker({ color: "#10b981" })
                                .setLngLat([lng, lat])
                                .addTo(map.current!);
                            markersRef.current[id] = marker;
                        }
                    }
                });

                // Remove drivers that are no longer available or online
                Object.keys(markersRef.current).forEach(id => {
                    if (!currentDriverIds.has(id)) {
                        markersRef.current[id].remove();
                        delete markersRef.current[id];
                    }
                });
            }
        );

        return () => {
            unsubDriversMap();
            // Cleanup markers
            Object.values(markersRef.current).forEach((m: mapboxgl.Marker) => m.remove());
            markersRef.current = {};
        };
    }, []);



    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'completed': return <span className="px-3 py-1.5 rounded-xl bg-emerald-50 text-emerald-600 text-xs font-bold flex items-center w-fit border border-emerald-100"><CheckCircle2 size={14} strokeWidth={2.5} className="ml-1.5" /> مكتمل</span>;
            case 'active': return <span className="px-3 py-1.5 rounded-xl bg-blue-50 text-blue-600 text-xs font-bold flex items-center w-fit border border-blue-100"><Clock size={14} strokeWidth={2.5} className="ml-1.5" /> جاري التنفيذ</span>;
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
                <button className="bg-white border border-slate-200 text-slate-700 hover:bg-slate-50 hover:text-slate-900 font-bold py-2.5 px-5 rounded-xl transition-all shadow-sm flex items-center space-x-2 space-x-reverse text-sm">
                    <span>تصدير التقرير</span>
                    <ArrowUpRight size={18} />
                </button>
            </div>

            {/* Stats Grid - Live */}
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
                <StatCard title="إجمالي الإيرادات" value={`${totalRevenue} ر.س`} icon={TrendingUp} trend="0" trendUp={true} colorScheme="blue" />
                <StatCard title="الطلبات النشطة" value={activeOrders} icon={Clock} trend="4.2" trendUp={true} colorScheme="orange" />
                <StatCard title="السائقين المتاحين" value={availableDrivers} icon={CarFront} trend="0" trendUp={true} colorScheme="indigo" />
                <StatCard title="إجمالي المستخدمين" value={totalUsers} icon={Users} trend="0" trendUp={true} colorScheme="emerald" />
            </div>

            <div className="grid grid-cols-1 xl:grid-cols-3 gap-8">

                {/* Recent Orders List */}
                <div className="xl:col-span-2 bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden flex flex-col">
                    <div className="p-6 md:p-8 border-b border-slate-100 flex justify-between items-center bg-white/50 backdrop-blur-sm">
                        <div>
                            <h3 className="text-lg font-extrabold text-slate-800">أحدث الطلبات</h3>
                            <p className="text-sm font-medium text-slate-400 mt-1">آخر 5 طلبات مسجلة في النظام</p>
                        </div>
                        <button className="text-blue-600 bg-blue-50 hover:bg-blue-100 px-4 py-2 rounded-xl text-sm font-bold transition-colors flex items-center">
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
                                {recentOrders.map((order: any) => (
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
                                                    <p className="font-bold text-slate-800 group-hover:text-blue-600 transition-colors">{order.client}</p>
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
                </div>

                {/* Tracking Map Widget Placeholder */}
                <div className="bg-slate-900 rounded-[24px] p-8 text-white relative overflow-hidden group shadow-xl shadow-slate-900/10 flex flex-col h-full min-h-[400px]">
                    <div className="absolute inset-0 opacity-40 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-blue-500/40 via-slate-900 to-slate-900 mix-blend-overlay pointer-events-none"></div>

                    {/* Animated grid background */}
                    <div className="absolute inset-0" style={{ backgroundImage: 'linear-gradient(rgba(255, 255, 255, 0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(255, 255, 255, 0.05) 1px, transparent 1px)', backgroundSize: '20px 20px', opacity: 0.2 }}></div>

                    <div className="relative z-10 flex flex-col h-full w-full">
                        <div className="flex items-start justify-between mb-2">
                            <div>
                                <h3 className="text-xl font-extrabold tracking-tight flex items-center gap-2"><MapIcon size={20} className="text-blue-400" /> تتبع السائقين</h3>
                                <p className="text-slate-400 text-sm font-medium mt-1">خرائط Mapbox الحية</p>
                            </div>
                            <div className="bg-emerald-500/20 p-2 rounded-xl">
                                <span className="block w-2.5 h-2.5 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_12px_rgba(16,185,129,0.9)]"></span>
                            </div>
                        </div>

                        <div className="flex-1 my-6 relative rounded-2xl border border-slate-700/60 overflow-hidden bg-slate-800/50 backdrop-blur-sm transition-colors w-full h-[300px]">
                            <div ref={mapContainer} className="w-full h-full" />
                        </div>

                        <button className="w-full relative overflow-hidden bg-white text-slate-900 font-bold py-4 rounded-xl transition-all hover:shadow-[0_0_20px_rgba(255,255,255,0.3)] group/btn">
                            <span className="relative z-10 flex items-center justify-center">
                                فتح شاشة التتبع
                                <ArrowLeftIcon className="mr-2 group-hover/btn:-translate-x-1 transition-transform" />
                            </span>
                        </button>
                    </div>
                </div>

            </div>
        </div>
    );
}

const ArrowLeftIcon = ({ className }: { className?: string }) => (
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className={className}>
        <line x1="19" y1="12" x2="5" y2="12"></line>
        <polyline points="12 19 5 12 12 5"></polyline>
    </svg>
)
