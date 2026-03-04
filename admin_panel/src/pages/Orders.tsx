import { useState, useEffect } from 'react';
import { Search, Filter, MoreVertical, CheckCircle2, Clock, XCircle, Package } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp } from 'firebase/firestore';
import { db } from '../services/firebase';

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'completed':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><CheckCircle2 size={14} />مكتمل</span>;
        case 'pending':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />قيد الانتظار</span>;
        case 'in_progress':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><Package size={14} />جاري التوصيل</span>;
        case 'cancelled':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><XCircle size={14} />ملغي</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs">{status}</span>;
    }
};

export default function Orders() {
    const [searchTerm, setSearchTerm] = useState('');
    const [orders, setOrders] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'));
        const unsubscribe = onSnapshot(q, (snapshot) => {
            const fetchedOrders = snapshot.docs.map(doc => {
                const data = doc.data();
                let dateStr = "غير متاح";
                if (data.created_at && data.created_at instanceof Timestamp) {
                    dateStr = data.created_at.toDate().toLocaleDateString('ar-EG');
                }
                return {
                    id: doc.id,
                    customer: data.client_name || data.client_id || 'غير متوفر',
                    driver: data.driver_name || (data.status === 'pending' ? 'بانتظار سائق' : '-'),
                    status: data.status || 'pending',
                    amount: `${data.amount || 0} ر.س`,
                    date: dateStr,
                    type: data.service_type || 'خدمة عامة',
                    ...data
                };
            });
            setOrders(fetchedOrders);
            setLoading(false);
        }, (err) => {
            console.error("Error fetching live orders: ", err);
            setLoading(false);
        });

        return () => unsubscribe();
    }, []);

    const filteredOrders = orders.filter(order =>
        order.id.toLowerCase().includes(searchTerm.toLowerCase()) ||
        order.customer.toLowerCase().includes(searchTerm.toLowerCase()) ||
        order.type.toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة الطلبات المباشرة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">متابعة حالة الطلبات وتفاصيلها لحظة بلحظة</p>
                </div>
                <div className="flex items-center gap-3">
                    <button className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                        <Filter size={18} />
                        تصفية
                    </button>
                    <button className="px-6 py-2.5 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-xl font-bold hover:from-blue-700 hover:to-indigo-700 transition-all shadow-lg shadow-blue-500/20 hover:shadow-xl hover:-translate-y-0.5">
                        طلب جديد +
                    </button>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث برقم الطلب، اسم العميل، رقم الخدمة..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>

                    <div className="flex gap-2 text-sm">
                        <button className="px-4 py-2 bg-blue-50 text-blue-700 font-bold rounded-lg border border-blue-100">الكل ({orders.length})</button>
                        <button className="px-4 py-2 bg-white text-slate-600 font-medium hover:bg-slate-50 rounded-lg shadow-sm border border-slate-200">النشطة ({orders.filter(o => o.status !== 'completed' && o.status !== 'cancelled').length})</button>
                    </div>
                </div>

                <div className="overflow-x-auto min-h-[400px]">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64">
                            <div className="animate-spin rounded-full h-10 w-10 border-4 border-blue-500 border-t-transparent"></div>
                            <p className="text-slate-500 mt-4 font-bold">جاري جلب الطلبات الحية...</p>
                        </div>
                    ) : (
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">رقم الطلب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">العميل</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">السائق المُنَفذ</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">نوع الطلب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">البلغ الاجمالي</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الطلب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-16 text-center">الإجراءات</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filteredOrders.length === 0 ? (
                                    <tr>
                                        <td colSpan={8} className="text-center py-12 text-slate-500 font-bold">لا توجد طلبات تطابق بحثك حالياً</td>
                                    </tr>
                                ) : (
                                    filteredOrders.map((order) => (
                                        <tr key={order.id} className="hover:bg-blue-50/30 transition-colors group">
                                            <td className="px-6 py-4">
                                                <span className="font-bold text-slate-800">#{order.id.substring(0, 6).toUpperCase()}</span>
                                            </td>
                                            <td className="px-6 py-4">
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-gradient-to-br from-indigo-100 to-purple-100 flex items-center justify-center text-indigo-700 font-bold text-xs uppercase z-0 border border-indigo-200">
                                                        {order.customer.substring(0, 1)}
                                                    </div>
                                                    <span className="font-bold text-slate-700">{order.customer}</span>
                                                </div>
                                            </td>
                                            <td className="px-6 py-4">
                                                <span className={`font-medium ${order.driver === '-' || order.driver === 'بانتظار سائق' ? 'text-amber-500' : 'text-slate-600'}`}>{order.driver}</span>
                                            </td>
                                            <td className="px-6 py-4 font-medium text-slate-600">{order.type}</td>
                                            <td className="px-6 py-4 font-bold text-emerald-600">{order.amount}</td>
                                            <td className="px-6 py-4 font-medium text-slate-500 text-sm">{order.date}</td>
                                            <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                                            <td className="px-6 py-4 text-center">
                                                <button className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors">
                                                    <MoreVertical size={18} />
                                                </button>
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    )}
                </div>

                {filteredOrders.length > 0 && (
                    <div className="p-4 border-t border-slate-100 flex items-center justify-between text-sm text-slate-500 font-medium bg-slate-50/50">
                        <span>عرض آخر الطلبات المسجلة من الجوال</span>
                    </div>
                )}
            </div>
        </div>
    );
}
