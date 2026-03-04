import { useState } from 'react';
import { Search, Filter, ShieldCheck, MapPin, Phone, Star, ShieldAlert } from 'lucide-react';

const mockDrivers = [
    { id: '#DRV-01', name: 'محمد الخالدي', phone: '+966 50 123 4567', vehicle: 'تويوتا كامري 2023', status: 'online', rating: 4.9, rides: 1450, wallet: '850 ر.س' },
    { id: '#DRV-02', name: 'علي اليامي', phone: '+966 55 987 6543', vehicle: 'هونداي أكسنت 2022', status: 'offline', rating: 4.7, rides: 890, wallet: '120 ر.س' },
    { id: '#DRV-03', name: 'سلطان القحطاني', phone: '+966 53 456 7890', vehicle: 'ايسوزو ديماكس (نقل)', status: 'busy', rating: 4.8, rides: 2100, wallet: '3400 ر.س' },
    { id: '#DRV-04', name: 'فهد الدوسري', phone: '+966 59 111 2222', vehicle: 'فورد تورس 2024', status: 'suspended', rating: 3.5, rides: 42, wallet: '-50 ر.س' },
];

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'online':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>متاح</span>;
        case 'offline':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 text-slate-600 font-bold border border-slate-200 text-xs"><div className="w-2 h-2 rounded-full bg-slate-400"></div>غير متصل</span>;
        case 'busy':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><div className="w-2 h-2 rounded-full bg-blue-500"></div>في مشوار</span>;
        case 'suspended':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><ShieldAlert size={14} />موقوف</span>;
        default:
            return null;
    }
};

export default function Drivers() {
    const [searchTerm, setSearchTerm] = useState('');

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة السائقين</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">تتبع أداء السائقين، الحالات، وإدارة الحسابات المالية</p>
                </div>
                <div className="flex items-center gap-3">
                    <button className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                        <Filter size={18} />
                        تصفية
                    </button>
                    <button className="px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-teal-600 text-white rounded-xl font-bold hover:from-emerald-600 hover:to-teal-700 transition-all shadow-lg shadow-emerald-500/20 hover:shadow-xl hover:-translate-y-0.5">
                        إضافة سائق +
                    </button>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6 mb-8">
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-blue-200 transition-colors">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">إجمالي السائقين</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">1,248</h3>
                    </div>
                    <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <ShieldCheck size={24} />
                    </div>
                </div>
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-emerald-200 transition-colors">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">المتاحين حالياً</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">423</h3>
                    </div>
                    <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <MapPin size={24} />
                    </div>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث بالاسم، رقم الجوال، اللوحة..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6 p-6 bg-slate-50/30">
                    {mockDrivers.map((driver) => (
                        <div key={driver.id} className="bg-white rounded-2xl border border-slate-100 shadow-sm hover:shadow-md transition-shadow p-5 relative overflow-hidden group">
                            <div className="absolute top-0 right-0 w-32 h-32 bg-slate-50 rounded-bl-full -z-10 group-hover:bg-blue-50/50 transition-colors duration-500"></div>

                            <div className="flex justify-between items-start mb-4">
                                <div className="flex items-center gap-3">
                                    <div className="w-12 h-12 rounded-xl bg-slate-100 overflow-hidden border border-slate-200 flex items-center justify-center">
                                        <span className="text-slate-400 font-bold">{driver.name.substring(0, 1)}</span>
                                    </div>
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-lg">{driver.name}</h4>
                                        <span className="text-slate-400 text-xs font-bold font-mono">{driver.id}</span>
                                    </div>
                                </div>
                                <StatusBadge status={driver.status} />
                            </div>

                            <div className="space-y-3 mb-6">
                                <div className="flex items-center gap-2 text-sm text-slate-600 font-medium">
                                    <Phone size={16} className="text-slate-400" />
                                    <span dir="ltr">{driver.phone}</span>
                                </div>
                                <div className="flex items-center gap-2 text-sm text-slate-600 font-medium">
                                    <span className="text-slate-400 font-bold">المركبة:</span>
                                    <span>{driver.vehicle}</span>
                                </div>
                            </div>

                            <div className="grid grid-cols-3 gap-2 border-t border-slate-100 pt-4">
                                <div className="text-center">
                                    <span className="block text-xs font-bold text-slate-400 mb-1">التقييم</span>
                                    <div className="flex items-center justify-center gap-1 font-bold text-slate-700">
                                        {driver.rating} <Star size={14} className="text-amber-400 fill-amber-400" />
                                    </div>
                                </div>
                                <div className="text-center border-r border-slate-100">
                                    <span className="block text-xs font-bold text-slate-400 mb-1">الرحلات</span>
                                    <span className="font-bold text-slate-700">{driver.rides}</span>
                                </div>
                                <div className="text-center border-r border-slate-100">
                                    <span className="block text-xs font-bold text-slate-400 mb-1">المحفظة</span>
                                    <span className={`font-bold ${driver.wallet.includes('-') ? 'text-rose-600' : 'text-emerald-600'}`}>{driver.wallet}</span>
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
}
