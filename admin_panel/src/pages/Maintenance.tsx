import { useState, useEffect } from 'react';
import { Search, Wrench, CheckCircle2, Clock, XCircle, AlertCircle } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp, doc, updateDoc, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface MaintenanceRecord {
    id: string;
    userId: string;
    serviceType: string;
    requestId: string;
    qty: number;
    floor: string;
    status: string;
    userName?: string;
    createdAt?: Timestamp;
}

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'under_review':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />تحت المراجعة</span>;
        case 'approved':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><AlertCircle size={14} />بانتظار الدفع</span>;
        case 'paid':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-xs"><CheckCircle2 size={14} />تم الدفع</span>;
        case 'completed':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><CheckCircle2 size={14} />تم التنفيذ</span>;
        case 'rejected':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><XCircle size={14} />مرفوض</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs">{status}</span>;
    }
};

export default function Maintenance() {
    const { toast, confirm } = useNotification();
    const [searchTerm, setSearchTerm] = useState('');
    const [requests, setRequests] = useState<MaintenanceRecord[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const q = query(collection(db, 'maintenance_requests'), orderBy('createdAt', 'desc'));
        const unsubscribe = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            const fetched = snapshot.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => ({
                id: doc.id,
                ...(doc.data() as Omit<MaintenanceRecord, 'id'>)
            }));
            setRequests(fetched);
            setLoading(false);
        });
        return () => unsubscribe();
    }, []);

    const updateStatus = async (id: string, newStatus: string) => {
        const label = newStatus === 'approved' ? 'قبول' : 'رفض';
        if (!await confirm(`هل أنت متأكد من ${label} هذا الطلب؟`)) return;
        try {
            await updateDoc(doc(db, 'maintenance_requests', id), { status: newStatus });
            toast.success("تم تحديث حالة الطلب بنجاح");
        } catch (error) {
            console.error(error);
            toast.error("حدث خطأ أثناء التحديث");
        }
    };

    const filtered = requests.filter(r =>
        r.serviceType.toLowerCase().includes(searchTerm.toLowerCase()) ||
        r.requestId.toLowerCase().includes(searchTerm.toLowerCase()) ||
        r.userId.toLowerCase().includes(searchTerm.toLowerCase()) ||
        (r.userName && r.userName.toLowerCase().includes(searchTerm.toLowerCase()))
    );

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10" dir="rtl">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة طلبات الصيانة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">متابعة طلبات صيانة التكييف والأجهزة المنزلية</p>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث برقم الطلب أو العميل..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
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
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">نوع الخدمة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">العدد / الطابق</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">التاريخ</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-32 text-center">الإجراءات</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filtered.length === 0 ? (
                                    <tr>
                                        <td colSpan={7} className="text-center py-12 text-slate-500 font-bold">لا توجد طلبات صيانة حالياً</td>
                                    </tr>
                                ) : (
                                    filtered.map((req) => (
                                        <tr key={req.id} className="hover:bg-blue-50/30 transition-colors group">
                                            <td className="px-6 py-4">
                                                <span className="font-bold text-slate-800">#{req.requestId}</span>
                                            </td>
                                            <td className="px-6 py-4">
                                                <div className="flex flex-col">
                                                    <span className="font-bold text-slate-700">{req.userName || 'عميل زيارة'}</span>
                                                    <span className="text-[10px] text-slate-400 font-mono">UID: {req.userId.substring(0, 8)}...</span>
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 font-bold text-indigo-700">{req.serviceType}</td>
                                            <td className="px-6 py-4 text-xs font-medium">العدد: {req.qty} | {req.floor}</td>
                                            <td className="px-6 py-4 font-medium text-slate-500 text-sm">
                                                {req.createdAt?.toDate().toLocaleDateString('ar-EG')}
                                            </td>
                                            <td className="px-6 py-4"><StatusBadge status={req.status} /></td>
                                            <td className="px-6 py-4 text-center">
                                                <div className="flex items-center justify-center gap-2">
                                                    {req.status === 'under_review' && (
                                                        <>
                                                            <button 
                                                                type="button"
                                                                onClick={() => updateStatus(req.id, 'approved')}
                                                                className="px-2 py-1 bg-emerald-600 text-white text-[10px] font-bold rounded hover:bg-emerald-700 transition-colors shadow-sm"
                                                            >
                                                                قبول
                                                            </button>
                                                            <button 
                                                                type="button"
                                                                onClick={() => updateStatus(req.id, 'rejected')}
                                                                className="px-2 py-1 bg-rose-600 text-white text-[10px] font-bold rounded hover:bg-rose-700 transition-colors shadow-sm"
                                                            >
                                                                رفض
                                                            </button>
                                                        </>
                                                    )}
                                                    <button type="button" title="التفاصيل" className="p-1.5 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded transition-colors">
                                                        <Wrench size={16} />
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>
        </div>
    );
}
