import { useState, useEffect } from 'react';
import { Search, FileSignature, CheckCircle2, Clock, XCircle, AlertCircle, Calendar, CreditCard, Trash2, Info } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp, doc, updateDoc, deleteDoc, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface ContractRecord {
    id: string;
    userId: string;
    userName?: string;
    clientName?: string;
    planName: string;
    planPrice?: number;
    planVisits?: number;
    status: string;
    createdAt?: Timestamp;
}

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'active':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-[10px]"><CheckCircle2 size={12} />نشط</span>;
        case 'approved_waiting_payment':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-50 text-blue-700 font-bold border border-blue-100 text-[10px]"><CreditCard size={12} />بانتظار الدفع</span>;
        case 'pending':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-[10px]"><Clock size={12} />قيد المراجعة</span>;
        case 'rejected':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-red-50 text-red-700 font-bold border border-red-100 text-[10px]"><XCircle size={12} />مرفوض</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-[10px]">{status}</span>;
    }
};

export default function Contracts() {
    const [searchTerm, setSearchTerm] = useState('');
    const [contracts, setContracts] = useState<ContractRecord[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const q = query(collection(db, 'contracts'), orderBy('createdAt', 'desc'));
        const unsubscribe = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            const fetched = snapshot.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => ({
                id: doc.id,
                ...(doc.data() as Omit<ContractRecord, 'id'>)
            }));
            setContracts(fetched);
            setLoading(false);
        });
        return () => unsubscribe();
    }, []);

    const handleApprove = async (id: string, planName: string) => {
        if (!globalThis.confirm(`هل أنت متأكد من رغبتك في اعتماد عقد (${planName})؟`)) return;
        try {
            await updateDoc(doc(db, 'contracts', id), { 
                status: 'approved_waiting_payment',
                adminApprovedAt: Timestamp.now()
            });
            alert("تم اعتماد العقد بنجاح وبانتظار دفع العميل");
        } catch (error) {
            console.error(error);
            alert("حدث خطأ أثناء الاعتماد");
        }
    };

    const handleDelete = async (id: string) => {
        if (!globalThis.confirm("هل أنت متأكد من حذف هذا العقد نهائياً؟")) return;
        try {
            await deleteDoc(doc(db, 'contracts', id));
        } catch (error) {
            console.error(error);
        }
    };

    const filtered = contracts.filter(c =>
        (c.planName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
        (c.userName || c.clientName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.id.toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10" dir="rtl">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="flex items-center gap-4">
                    <div className="p-3 bg-blue-600 text-white rounded-2xl shadow-lg shadow-blue-200">
                        <FileSignature size={28} />
                    </div>
                    <div>
                        <h2 className="text-2xl font-black text-slate-800 tracking-tight">مركز العقود الرقمية</h2>
                        <p className="text-slate-500 font-medium text-sm">إدارة واعتماد عقود الإشتراكات والخدمات المنزلية</p>
                    </div>
                </div>
            </div>

            <div className="relative group">
                <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-blue-500 transition-colors" size={20} />
                <input
                    type="text"
                    placeholder="ابحث باسم العميل، الباقة، أو رقم العقد..."
                    className="w-full pl-6 pr-12 py-4 bg-white border-2 border-slate-100 rounded-[20px] text-base outline-none focus:ring-4 focus:ring-blue-500/10 focus:border-blue-500 transition-all font-bold text-slate-700 shadow-sm"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                />
            </div>

            {loading ? (
                <div className="flex flex-col items-center justify-center h-64 bg-white rounded-[32px] border-2 border-dashed border-slate-100">
                    <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent shadow-md"></div>
                    <p className="text-slate-500 mt-6 font-black text-lg">جاري جرد العقود...</p>
                </div>
            ) : filtered.length === 0 ? (
                <div className="flex flex-col items-center justify-center p-20 bg-white rounded-[32px] border-2 border-dashed border-slate-100">
                    <div className="p-6 bg-slate-50 rounded-full mb-6">
                        <AlertCircle size={60} className="text-slate-200" />
                    </div>
                    <h3 className="text-xl font-bold text-slate-800">لا توجد سجلات مطابقة</h3>
                    <p className="text-slate-400 mt-2 font-medium">حاول البحث بكلمات أخرى أو تأكد من فلترة الحسابات</p>
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {filtered.map((contract) => (
                        <div key={contract.id} className="group bg-white rounded-[28px] border-2 border-slate-50 overflow-hidden hover:border-blue-100/50 hover:shadow-2xl hover:shadow-blue-50 transition-all duration-500">
                            <div className="p-6">
                                <div className="flex items-center justify-between mb-6">
                                    <StatusBadge status={contract.status} />
                                    <div className="flex items-center gap-2 text-slate-400 text-[10px] font-bold">
                                        <Calendar size={12} />
                                        {contract.createdAt ? contract.createdAt.toDate().toLocaleDateString('ar-EG-u-nu-latn') : 'غير متوفر'}
                                    </div>
                                </div>

                                <div className="flex items-start gap-4 mb-6">
                                    <div className="p-4 bg-slate-50 text-slate-400 rounded-2xl group-hover:bg-blue-600 group-hover:text-white transition-all duration-500">
                                        <FileSignature size={24} />
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <h4 className="text-lg font-black text-slate-800 truncate leading-tight">
                                            {contract.planName || 'باقة غير محددة'}
                                        </h4>
                                        <p className="text-sm font-bold text-slate-400 truncate mt-1">#{(contract.id || '').split('-')[1]?.toUpperCase() || contract.id.substring(0, 8).toUpperCase()}</p>
                                    </div>
                                </div>

                                <div className="space-y-3 mb-8">
                                    <div className="flex items-center justify-between p-3 bg-slate-50 rounded-xl border border-slate-100/50">
                                        <span className="text-[11px] font-bold text-slate-400">العميل لمسجل</span>
                                        <span className="text-sm font-black text-slate-700">{contract.userName || contract.clientName || 'عميل زيارة'}</span>
                                    </div>
                                    <div className="flex items-center justify-between p-3 bg-slate-50 rounded-xl border border-slate-100/50">
                                        <span className="text-[11px] font-bold text-slate-400">قيمة التعاقد</span>
                                        <span className="text-sm font-black text-blue-600">{contract.planPrice || 0} ر.س</span>
                                    </div>
                                </div>

                                <div className="flex items-center gap-3">
                                    {contract.status === 'pending' && (
                                        <button 
                                            type="button"
                                            onClick={() => handleApprove(contract.id, contract.planName)}
                                            className="flex-1 py-3.5 bg-blue-600 text-white text-sm font-black rounded-2xl hover:bg-blue-700 transition-all shadow-lg shadow-blue-100 active:scale-95"
                                        >
                                            اعتماد الباقة
                                        </button>
                                    )}
                                    <button 
                                        type="button" 
                                        className="p-3.5 bg-slate-50 text-slate-400 hover:bg-slate-100 hover:text-slate-600 rounded-2xl transition-all"
                                        title="المزيد من التفاصيل"
                                    >
                                        <Info size={20} />
                                    </button>
                                    <button 
                                        type="button" 
                                        onClick={() => handleDelete(contract.id)}
                                        className="p-3.5 bg-red-50 text-red-500 hover:bg-red-100 rounded-2xl transition-all active:scale-95"
                                        title="حذف السجل"
                                    >
                                        <Trash2 size={20} />
                                    </button>
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
