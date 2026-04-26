import { useState, useEffect } from 'react';
import { Search, Filter, ShieldCheck, MapPin, Phone, Star, ShieldAlert, X, Loader2, ToggleLeft, ToggleRight } from 'lucide-react';
import { collection, onSnapshot, addDoc, updateDoc, doc, serverTimestamp, query, orderBy, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface DriverData {
    id: string;
    name: string;
    phone: string;
    vehicle: string;
    is_available: boolean;
    is_suspended?: boolean;
    rating: number;
    rides: number;
    wallet: number;
}

const StatusBadge = ({ is_available, is_suspended = false }: { is_available: boolean, is_suspended?: boolean }) => {
    if (is_suspended) {
        return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><ShieldAlert size={14} />موقوف</span>;
    }
    if (is_available) {
        return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>متاح</span>;
    }
    return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 text-slate-600 font-bold border border-slate-200 text-xs"><div className="w-2 h-2 rounded-full bg-slate-400"></div>غير متصل</span>;
};

export default function Drivers() {
    const [searchTerm, setSearchTerm] = useState('');
    const [drivers, setDrivers] = useState<DriverData[]>([]);
    const [isAvailableCount, setIsAvailableCount] = useState(0);

    const [isAddModalOpen, setIsAddModalOpen] = useState(false);
    const [isAdding, setIsAdding] = useState(false);
    const [togglingId, setTogglingId] = useState<string | null>(null);
    const [newDriver, setNewDriver] = useState({ name: '', phone: '', vehicle: '' });

    useEffect(() => {
        const q = query(collection(db, 'drivers'), orderBy('created_at', 'desc'));
        const unsubscribe = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            let available = 0;
            const fetchedDrivers = snapshot.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => {
                const data = doc.data();
                if (data.is_available) available++;
                return {
                    id: doc.id,
                    name: data.name || 'غير محدد',
                    phone: data.phone || 'غير محدد',
                    vehicle: data.vehicle || 'غير محدد',
                    is_available: data.is_available || false,
                    is_suspended: data.is_suspended || false,
                    rating: data.rating || 5.0,
                    rides: data.rides || 0,
                    wallet: data.wallet || 0,
                    ...data
                } as DriverData;
            });
            setDrivers(fetchedDrivers);
            setIsAvailableCount(available);
        });
        return () => unsubscribe();
    }, []);

    const handleAddDriver = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!newDriver.name || !newDriver.phone) return;
        setIsAdding(true);
        try {
            await addDoc(collection(db, 'drivers'), {
                name: newDriver.name,
                phone: newDriver.phone,
                vehicle: newDriver.vehicle,
                is_available: false,
                rating: 5.0,
                rides: 0,
                wallet: 0,
                created_at: serverTimestamp()
            });
            setIsAddModalOpen(false);
            setNewDriver({ name: '', phone: '', vehicle: '' });
        } catch (error) {
            console.error("Error adding driver: ", error);
            alert("حدث خطأ أثناء إضافة السائق.");
        } finally {
            setIsAdding(false);
        }
    };

    const handleToggleSuspension = async (driver: DriverData) => {
        setTogglingId(driver.id);
        try {
            const nowSuspended = !driver.is_suspended;
            await updateDoc(doc(db, 'drivers', driver.id), {
                is_suspended: nowSuspended,
                is_available: nowSuspended ? false : driver.is_available,
            });
        } catch (err) {
            console.error('Error toggling suspension:', err);
            alert('حدث خطأ');
        } finally {
            setTogglingId(null);
        }
    };

    const filteredDrivers = drivers.filter(d =>
        d.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        d.phone.includes(searchTerm) ||
        d.id.includes(searchTerm)
    );

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة السائقين</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">تتبع أداء السائقين، الحالات، وإدارة الحسابات المالية</p>
                </div>
                <div className="flex items-center gap-3">
                    <button type="button" className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                        <Filter size={18} />
                        تصفية
                    </button>
                    <button
                        type="button"
                        onClick={() => setIsAddModalOpen(true)}
                        className="px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-teal-600 text-white rounded-xl font-bold hover:from-emerald-600 hover:to-teal-700 transition-all shadow-lg shadow-emerald-500/20 hover:shadow-xl hover:-translate-y-0.5"
                    >
                        إضافة سائق +
                    </button>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6 mb-8">
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-blue-200 transition-colors">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">إجمالي السائقين</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">{drivers.length}</h3>
                    </div>
                    <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <ShieldCheck size={24} />
                    </div>
                </div>
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-emerald-200 transition-colors">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">المتاحين حالياً</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">{isAvailableCount}</h3>
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
                    {filteredDrivers.length === 0 ? (
                        <div className="col-span-full py-12 text-center text-slate-500 font-bold">
                            لا يوجد سائقين مطابقين للبحث.
                        </div>
                    ) : filteredDrivers.map((driver) => (
                        <div key={driver.id} className="bg-white rounded-2xl border border-slate-100 shadow-sm hover:shadow-md transition-shadow p-5 relative overflow-hidden group">
                            <div className="absolute top-0 right-0 w-32 h-32 bg-slate-50 rounded-bl-full -z-10 group-hover:bg-blue-50/50 transition-colors duration-500"></div>

                            <div className="flex justify-between items-start mb-4">
                                <div className="flex items-center gap-3">
                                    <div className="w-12 h-12 rounded-xl bg-slate-100 overflow-hidden border border-slate-200 flex items-center justify-center">
                                        <span className="text-slate-400 font-bold">{driver.name.substring(0, 1)}</span>
                                    </div>
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-lg">{driver.name}</h4>
                                        <span className="text-slate-400 text-xs font-bold font-mono">#{driver.id.substring(0, 6).toUpperCase()}</span>
                                    </div>
                                </div>
                                <StatusBadge is_available={driver.is_available} is_suspended={driver.is_suspended} />
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

                            <div className="grid grid-cols-3 gap-2 border-t border-slate-100 pt-4 mb-4">
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
                                    <span className={`font-bold ${driver.wallet < 0 ? 'text-rose-600' : 'text-emerald-600'}`}>{driver.wallet} ر.س</span>
                                </div>
                            </div>
                            <button
                                type="button"
                                disabled={togglingId === driver.id}
                                onClick={() => handleToggleSuspension(driver)}
                                className={`w-full flex items-center justify-center gap-2 py-2 rounded-xl text-sm font-bold transition-colors border ${
                                    driver.is_suspended
                                        ? 'border-emerald-200 text-emerald-700 hover:bg-emerald-50'
                                        : 'border-rose-200 text-rose-600 hover:bg-rose-50'
                                } disabled:opacity-50`}
                            >
                                {togglingId === driver.id
                                    ? <Loader2 size={16} className="animate-spin" />
                                    : driver.is_suspended
                                        ? <><ToggleRight size={16} />رفع الإيقاف</>
                                        : <><ToggleLeft size={16} />إيقاف الحساب</>
                                }
                            </button>
                        </div>
                    ))}
                </div>
            </div>

            {/* Add Driver Modal */}
            {isAddModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md overflow-hidden animate-in zoom-in-95 duration-200">
                        <div className="flex justify-between items-center p-6 border-b border-slate-100 bg-slate-50/50">
                            <h3 className="text-xl font-extrabold text-slate-800">إضافة سائق جديد</h3>
                            <button type="button" title="إغلاق" onClick={() => setIsAddModalOpen(false)} className="text-slate-400 hover:text-slate-600 hover:bg-slate-100 p-2 rounded-xl transition-colors">
                                <X size={20} />
                            </button>
                        </div>
                        <form onSubmit={handleAddDriver} className="p-6 space-y-5">
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">اسم السائق الكامل</label>
                                <input
                                    type="text"
                                    required
                                    placeholder="مثال: أحمد محمد"
                                    value={newDriver.name}
                                    onChange={e => setNewDriver({ ...newDriver, name: e.target.value })}
                                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium"
                                />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">رقم الجوال</label>
                                <div className="relative">
                                    <Phone className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                                    <input
                                        type="tel"
                                        required
                                        placeholder="+966 5X XXX XXXX"
                                        value={newDriver.phone}
                                        onChange={e => setNewDriver({ ...newDriver, phone: e.target.value })}
                                        className="w-full pl-4 pr-11 py-3 bg-slate-50 border border-slate-200 rounded-xl outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium"
                                        dir="ltr"
                                    />
                                </div>
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">بيانات المركبة (اختياري)</label>
                                <input
                                    type="text"
                                    placeholder="مثال: تويوتا كامري 2023 - أ ب ج ١٢٣٤"
                                    value={newDriver.vehicle}
                                    onChange={e => setNewDriver({ ...newDriver, vehicle: e.target.value })}
                                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium"
                                />
                            </div>
                            <div className="pt-4 flex gap-3">
                                <button type="button" onClick={() => setIsAddModalOpen(false)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button disabled={isAdding} type="submit" className="flex-1 px-4 py-3 bg-emerald-600 text-white rounded-xl font-bold hover:bg-emerald-700 transition-colors flex justify-center items-center disabled:opacity-70 disabled:cursor-not-allowed">
                                    {isAdding ? <Loader2 className="animate-spin" size={20} /> : "اعتماد وإضافة"}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}
