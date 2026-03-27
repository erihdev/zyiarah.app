import { useState, useEffect } from 'react';
import { Search, FileSignature, CheckCircle2, Clock, XCircle } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp, doc, updateDoc, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface ContractRecord {
    id: string;
    userId: string;
    userName?: string;
    planName: string;
    status: string;
    createdAt?: Timestamp;
}

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'active':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><CheckCircle2 size={14} />نشط وموثق</span>;
        case 'pending':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />بانتظار الاعتماد</span>;
        case 'expired':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs"><XCircle size={14} />منتهي</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs">{status}</span>;
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

    const handleApprove = async (id: string) => {
        if (!globalThis.confirm("هل أنت متأكد من رغبتك في اعتماد هذا العقد؟")) return;
        try {
            await updateDoc(doc(db, 'contracts', id), { status: 'active' });
            alert("تم اعتماد العقد بنجاح");
        } catch (error) {
            console.error(error);
            alert("حدث خطأ أثناء الاعتماد");
        }
    };

    const filtered = contracts.filter(c =>
        c.planName.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.userId.toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10" dir="rtl">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة العقود الإلكترونية</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">مراجعة وتوثيق عقود سلة العائلة الموقعة من قبل العملاء</p>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث بالباقة أو معرف العميل..."
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
                            <p className="text-slate-500 mt-4 font-bold">جاري تحميل العقود...</p>
                        </div>
                    ) : (
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">معرف العقد</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">العميل</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الباقة المختارة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ التوقيع</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-16 text-center">الإجراءات</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filtered.length === 0 ? (
                                    <tr>
                                        <td colSpan={6} className="text-center py-12 text-slate-500 font-bold">لا توجد عقود حالياً</td>
                                    </tr>
                                ) : (
                                    filtered.map((contract) => (
                                        <tr key={contract.id} className="hover:bg-blue-50/30 transition-colors group">
                                            <td className="px-6 py-4">
                                                <span className="font-bold text-slate-800">#{contract.id.substring(0, 8).toUpperCase()}</span>
                                            </td>
                                            <td className="px-6 py-4">
                                                <span className="font-bold text-slate-700">{contract.userId}</span>
                                            </td>
                                            <td className="px-6 py-4 font-bold text-blue-600">{contract.planName}</td>
                                            <td className="px-6 py-4 font-medium text-slate-500 text-sm">
                                                {contract.createdAt?.toDate().toLocaleDateString('ar-EG')}
                                            </td>
                                            <td className="px-6 py-4"><StatusBadge status={contract.status} /></td>
                                            <td className="px-6 py-4 text-center">
                                                <div className="flex items-center justify-center gap-2">
                                                    {contract.status === 'pending' && (
                                                        <button 
                                                            type="button"
                                                            onClick={() => handleApprove(contract.id)}
                                                            className="px-3 py-1 bg-emerald-600 text-white text-xs font-bold rounded-lg hover:bg-emerald-700 transition-colors shadow-sm"
                                                        >
                                                            اعتماد
                                                        </button>
                                                    )}
                                                    <button type="button" title="عرض التفاصيل" className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors">
                                                        <FileSignature size={18} />
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
