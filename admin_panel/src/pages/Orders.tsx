import { useState, useEffect, useRef } from 'react';
import { Search, Filter, MoreVertical, CheckCircle2, Clock, XCircle, Package, UserCheck, X, Loader2 } from 'lucide-react';
import {
    collection, onSnapshot, query, orderBy, updateDoc, doc, Timestamp,
    type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface OrderRecord {
    id: string;
    customer: string;
    driver: string;
    status: string;
    amount: string;
    date: string;
    type: string;
    client_name?: string;
    client_id?: string;
    driver_id?: string;
    assigned_driver?: string;
    service_type?: string;
    created_at?: Timestamp;
    code?: string;
}

interface DriverOption { id: string; name: string; is_available: boolean; }

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'completed': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><CheckCircle2 size={14} />مكتمل</span>;
        case 'pending':   return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />بانتظار سائق</span>;
        case 'accepted':  return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><UserCheck size={14} />تم القبول</span>;
        case 'in_progress': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><Package size={14} />جاري التنفيذ</span>;
        case 'cancelled': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><XCircle size={14} />ملغي</span>;
        default: return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs">{status}</span>;
    }
};

export default function Orders() {
    const { toast, confirm } = useNotification();
    const [searchTerm, setSearchTerm] = useState('');
    const [orders, setOrders] = useState<OrderRecord[]>([]);
    const [drivers, setDrivers] = useState<DriverOption[]>([]);
    const [loading, setLoading] = useState(true);
    const [actionMenuId, setActionMenuId] = useState<string | null>(null);
    const [assignModal, setAssignModal] = useState<OrderRecord | null>(null);
    const [selectedDriverId, setSelectedDriverId] = useState('');
    const [isAssigning, setIsAssigning] = useState(false);
    const [isCancelling, setIsCancelling] = useState(false);
    const menuRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'));
        const unsub = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            setOrders(snapshot.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => {
                const d = doc.data() as Partial<OrderRecord>;
                return {
                    id: doc.id,
                    customer: d.client_name || d.client_id || 'غير متوفر',
                    driver: d.assigned_driver || (d.status === 'pending' ? 'بانتظار سائق' : '-'),
                    status: d.status || 'pending',
                    amount: `${d.amount || 0} ر.س`,
                    date: d.created_at instanceof Timestamp ? d.created_at.toDate().toLocaleDateString('ar-EG') : 'غير متاح',
                    type: d.service_type || 'خدمة عامة',
                    ...d,
                } as OrderRecord;
            }));
            setLoading(false);
        });

        const driversUnsub = onSnapshot(collection(db, 'drivers'), (snap) => {
            setDrivers(snap.docs.map(d => ({ id: d.id, name: d.data().name || 'سائق', is_available: d.data().is_available || false })));
        });

        return () => { unsub(); driversUnsub(); };
    }, []);

    useEffect(() => {
        const handler = (e: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(e.target as Node)) setActionMenuId(null);
        };
        document.addEventListener('mousedown', handler);
        return () => document.removeEventListener('mousedown', handler);
    }, []);

    const handleAssignDriver = async () => {
        if (!assignModal || !selectedDriverId) return;
        setIsAssigning(true);
        try {
            const driver = drivers.find(d => d.id === selectedDriverId);
            await updateDoc(doc(db, 'orders', assignModal.id), {
                status: 'accepted',
                driver_id: selectedDriverId,
                assigned_driver: driver?.name || 'سائق',
                accepted_at: Timestamp.now(),
            });
            await updateDoc(doc(db, 'drivers', selectedDriverId), {
                status: 'en_route',
                current_order_id: assignModal.id,
                is_available: false,
            });
            setAssignModal(null);
            setSelectedDriverId('');
        } catch (err) {
            console.error('Error assigning driver:', err);
            toast.error('حدث خطأ أثناء التعيين');
        } finally {
            setIsAssigning(false);
        }
    };

    const handleCancelOrder = async (order: OrderRecord) => {
        if (!await confirm(`هل أنت متأكد من إلغاء الطلب #${order.code || order.id.substring(0, 6).toUpperCase()}؟`)) return;
        setIsCancelling(true);
        try {
            await updateDoc(doc(db, 'orders', order.id), {
                status: 'cancelled',
                cancelled_at: Timestamp.now(),
                cancelled_by: 'admin',
                needs_refund: false,
            });
            if (order.driver_id) {
                await updateDoc(doc(db, 'drivers', order.driver_id), {
                    status: 'available',
                    current_order_id: null,
                    is_available: true,
                });
            }
        } catch (err) {
            console.error('Error cancelling order:', err);
            toast.error('حدث خطأ أثناء الإلغاء');
        } finally {
            setIsCancelling(false);
            setActionMenuId(null);
        }
    };

    const filteredOrders = orders.filter(o =>
        o.id.toLowerCase().includes(searchTerm.toLowerCase()) ||
        o.customer.toLowerCase().includes(searchTerm.toLowerCase()) ||
        o.type.toLowerCase().includes(searchTerm.toLowerCase())
    );

    const availableDrivers = drivers.filter(d => d.is_available);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة الطلبات المباشرة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">متابعة حالة الطلبات وتفاصيلها لحظة بلحظة</p>
                </div>
                <button type="button" className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                    <Filter size={18} />تصفية
                </button>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث برقم الطلب، اسم العميل..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                    <div className="flex gap-2 text-sm">
                        <button type="button" className="px-4 py-2 bg-blue-50 text-blue-700 font-bold rounded-lg border border-blue-100">الكل ({orders.length})</button>
                        <button type="button" className="px-4 py-2 bg-amber-50 text-amber-700 font-bold rounded-lg border border-amber-100">انتظار ({orders.filter(o => o.status === 'pending').length})</button>
                    </div>
                </div>

                <div className="overflow-x-auto min-h-[400px]">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64">
                            <div className="animate-spin rounded-full h-10 w-10 border-4 border-blue-500 border-t-transparent"></div>
                            <p className="text-slate-500 mt-4 font-bold">جاري جلب الطلبات...</p>
                        </div>
                    ) : (
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">رقم الطلب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">العميل</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">السائق</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">نوع الخدمة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">المبلغ</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">التاريخ</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-16 text-center">إجراءات</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filteredOrders.length === 0 ? (
                                    <tr><td colSpan={8} className="text-center py-12 text-slate-500 font-bold">لا توجد طلبات</td></tr>
                                ) : filteredOrders.map((order) => (
                                    <tr key={order.id} className="hover:bg-blue-50/30 transition-colors group">
                                        <td className="px-6 py-4"><span className="font-bold text-slate-800">#{order.code || order.id.substring(0, 6).toUpperCase()}</span></td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-indigo-100 to-purple-100 flex items-center justify-center text-indigo-700 font-bold text-xs border border-indigo-200">
                                                    {order.customer.substring(0, 1)}
                                                </div>
                                                <span className="font-bold text-slate-700">{order.customer}</span>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`font-medium ${!order.driver_id ? 'text-amber-500' : 'text-slate-600'}`}>{order.driver}</span>
                                        </td>
                                        <td className="px-6 py-4 font-medium text-slate-600">{order.type}</td>
                                        <td className="px-6 py-4 font-bold text-emerald-600">{order.amount}</td>
                                        <td className="px-6 py-4 font-medium text-slate-500 text-sm">{order.date}</td>
                                        <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                                        <td className="px-6 py-4 text-center relative">
                                            {order.status !== 'completed' && order.status !== 'cancelled' && (
                                                <button
                                                    type="button"
                                                    title="الإجراءات"
                                                    onClick={() => setActionMenuId(actionMenuId === order.id ? null : order.id)}
                                                    className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                                                >
                                                    <MoreVertical size={18} />
                                                </button>
                                            )}
                                            {actionMenuId === order.id && (
                                                <div ref={menuRef} className="absolute left-0 top-full mt-1 w-48 bg-white rounded-xl shadow-lg border border-slate-100 z-20 overflow-hidden">
                                                    {order.status === 'pending' && (
                                                        <button
                                                            type="button"
                                                            onClick={() => { setAssignModal(order); setActionMenuId(null); }}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-slate-700 hover:bg-blue-50 hover:text-blue-700 transition-colors text-right"
                                                        >
                                                            <UserCheck size={16} />تعيين سائق
                                                        </button>
                                                    )}
                                                    <button
                                                        type="button"
                                                        disabled={isCancelling}
                                                        onClick={() => handleCancelOrder(order)}
                                                        className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-rose-600 hover:bg-rose-50 transition-colors text-right disabled:opacity-50"
                                                    >
                                                        <XCircle size={16} />إلغاء الطلب
                                                    </button>
                                                </div>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>

            {/* Assign Driver Modal */}
            {assignModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md overflow-hidden">
                        <div className="flex justify-between items-center p-6 border-b border-slate-100 bg-slate-50/50">
                            <div>
                                <h3 className="text-xl font-extrabold text-slate-800">تعيين سائق</h3>
                                <p className="text-sm text-slate-500 mt-0.5">الطلب #{assignModal.code || assignModal.id.substring(0, 6).toUpperCase()} — {assignModal.customer}</p>
                            </div>
                            <button type="button" title="إغلاق" onClick={() => setAssignModal(null)} className="text-slate-400 hover:text-slate-600 p-2 rounded-xl hover:bg-slate-100 transition-colors">
                                <X size={20} />
                            </button>
                        </div>
                        <div className="p-6 space-y-4">
                            {availableDrivers.length === 0 ? (
                                <p className="text-center text-amber-600 font-bold py-4">لا يوجد سائقون متاحون حالياً</p>
                            ) : (
                                <div className="space-y-2">
                                    <label className="block text-sm font-extrabold text-slate-700">اختر سائقاً متاحاً</label>
                                    <select
                                        title="اختر سائقاً"
                                        value={selectedDriverId}
                                        onChange={e => setSelectedDriverId(e.target.value)}
                                        className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 font-medium"
                                    >
                                        <option value="">-- اختر سائقاً --</option>
                                        {availableDrivers.map(d => (
                                            <option key={d.id} value={d.id}>{d.name}</option>
                                        ))}
                                    </select>
                                </div>
                            )}
                            <div className="flex gap-3 pt-2">
                                <button type="button" onClick={() => setAssignModal(null)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button
                                    type="button"
                                    disabled={!selectedDriverId || isAssigning}
                                    onClick={handleAssignDriver}
                                    className="flex-1 px-4 py-3 bg-blue-600 text-white rounded-xl font-bold hover:bg-blue-700 transition-colors flex justify-center items-center disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    {isAssigning ? <Loader2 className="animate-spin" size={20} /> : 'تعيين السائق'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
