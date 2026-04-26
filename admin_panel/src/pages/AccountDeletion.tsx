import { useState, useEffect } from 'react';
import { ShieldAlert, Trash2, Search, CheckCircle2, XCircle, AlertTriangle, Loader2 } from 'lucide-react';
import {
    collection, onSnapshot, updateDoc, deleteDoc,
    doc, orderBy, query
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface DeletionRequest {
    id: string;
    type?: string;
    name?: string;
    phone?: string;
    requested_at?: { toDate: () => Date };
    reason?: string;
    status: 'pending' | 'deleted' | 'rejected';
    userId?: string;
}

const formatDate = (ts?: { toDate: () => Date }): string => {
    if (!ts) return '—';
    return ts.toDate().toLocaleDateString('ar-SA');
};

export default function AccountDeletion() {
    const [searchTerm, setSearchTerm] = useState('');
    const [requests, setRequests] = useState<DeletionRequest[]>([]);
    const [loading, setLoading] = useState(true);
    const [processingId, setProcessingId] = useState<string | null>(null);

    useEffect(() => {
        const q = query(collection(db, 'account_deletions'), orderBy('requested_at', 'desc'));
        const unsub = onSnapshot(q, (snap) => {
            setRequests(snap.docs.map(d => ({ id: d.id, ...d.data() } as DeletionRequest)));
            setLoading(false);
        }, () => setLoading(false));
        return unsub;
    }, []);

    const filtered = requests.filter(r =>
        r.name?.includes(searchTerm) ||
        r.phone?.includes(searchTerm)
    );

    const handleDelete = async (req: DeletionRequest) => {
        if (!confirm(`هل تريد مسح بيانات ${req.name ?? 'هذا المستخدم'} نهائياً؟ لا يمكن التراجع.`)) return;
        setProcessingId(req.id);
        try {
            if (req.userId) {
                await deleteDoc(doc(db, 'users', req.userId));
            }
            await updateDoc(doc(db, 'account_deletions', req.id), {
                status: 'deleted',
                processed_at: new Date(),
            });
        } finally {
            setProcessingId(null);
        }
    };

    const handleReject = async (req: DeletionRequest) => {
        setProcessingId(req.id);
        try {
            await updateDoc(doc(db, 'account_deletions', req.id), {
                status: 'rejected',
                processed_at: new Date(),
            });
        } finally {
            setProcessingId(null);
        }
    };

    const pendingCount = requests.filter(r => r.status === 'pending').length;

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
                        <ShieldAlert className="text-rose-600" />
                        طلبات حذف الحساب
                        <span className="text-xs bg-slate-100 text-slate-500 px-2 py-0.5 rounded-full border border-slate-200">Apple Compliance</span>
                        {pendingCount > 0 && (
                            <span className="text-xs bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full font-bold">{pendingCount} معلّق</span>
                        )}
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">
                        إدارة طلبات المستخدمين لحذف بياناتهم نهائياً بناءً على شروط متجر آبل 2025 المحدثة.
                    </p>
                </div>
            </div>

            <div className="bg-amber-50 border-l-4 border-amber-500 p-4 rounded-xl flex gap-3 text-amber-800">
                <AlertTriangle size={24} className="shrink-0" />
                <div>
                    <h4 className="font-bold text-sm mb-1">تنبيه قانوني (App Store Guidelines)</h4>
                    <p className="text-xs leading-relaxed font-medium">وفقاً لاشتراطات آبل، يجب الرد على طلبات الحذف خلال 15 يوماً كحد أقصى. حذف الحساب هنا سيقوم بمسح كافة بيانات العميل/السائق من قاعدة بيانات Firebase بشكل لا يمكن استرجاعه.</p>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث برقم الجوال أو الاسم..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-rose-500/20 focus:border-rose-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                    <span className="text-xs text-slate-400 font-medium">{requests.length} طلب</span>
                </div>

                {loading ? (
                    <div className="flex items-center justify-center py-16 text-slate-400 gap-2">
                        <Loader2 size={20} className="animate-spin" />
                        <span className="text-sm font-medium">جاري التحميل...</span>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-20">النوع</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">اسم المستخدم</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الطلب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">سبب الحذف</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-36">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-44 text-center">الإجراء الفوري</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filtered.length === 0 && (
                                    <tr><td colSpan={6} className="px-6 py-12 text-center text-slate-400 text-sm">لا توجد طلبات</td></tr>
                                )}
                                {filtered.map((req) => (
                                    <tr key={req.id} className="hover:bg-rose-50/20 transition-colors group">
                                        <td className="px-6 py-4">
                                            <span className={`px-2 py-1 text-xs font-bold rounded-md ${req.type === 'driver' || req.type === 'سائق' ? 'bg-indigo-50 text-indigo-700' : 'bg-teal-50 text-teal-700'}`}>
                                                {req.type === 'driver' ? 'سائق' : 'عميل'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="font-bold text-slate-800">{req.name ?? '—'}</div>
                                            <div className="text-xs text-slate-500 dir-ltr font-mono mt-0.5">{req.phone ?? '—'}</div>
                                        </td>
                                        <td className="px-6 py-4 text-sm font-medium text-slate-500">{formatDate(req.requested_at)}</td>
                                        <td className="px-6 py-4 text-sm text-slate-600 line-clamp-1">{req.reason ?? '—'}</td>
                                        <td className="px-6 py-4">
                                            {req.status === 'pending' && <span className="inline-flex items-center gap-1 text-amber-600 bg-amber-50 px-2.5 py-1 rounded-full text-xs font-bold border border-amber-100"><AlertTriangle size={12} />قيد المراجعة</span>}
                                            {req.status === 'deleted' && <span className="inline-flex items-center gap-1 text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-full text-xs font-bold border border-emerald-100"><CheckCircle2 size={12} />تم الحذف نهائياً</span>}
                                            {req.status === 'rejected' && <span className="inline-flex items-center gap-1 text-slate-600 bg-slate-100 px-2.5 py-1 rounded-full text-xs font-bold border border-slate-200"><XCircle size={12} />مرفوض</span>}
                                        </td>
                                        <td className="px-6 py-4 text-center">
                                            {req.status === 'pending' ? (
                                                <div className="flex items-center justify-center gap-2">
                                                    <button
                                                        type="button"
                                                        title="مسح البيانات نهائياً"
                                                        onClick={() => handleDelete(req)}
                                                        disabled={processingId === req.id}
                                                        className="px-3 py-1.5 bg-rose-50 hover:bg-rose-600 hover:text-white text-rose-600 border border-rose-100 rounded-lg text-xs font-bold transition-colors flex items-center gap-1.5 disabled:opacity-40"
                                                    >
                                                        {processingId === req.id
                                                            ? <Loader2 size={14} className="animate-spin" />
                                                            : <Trash2 size={14} />}
                                                        مسح البيانات
                                                    </button>
                                                    <button
                                                        type="button"
                                                        title="رفض الطلب"
                                                        onClick={() => handleReject(req)}
                                                        disabled={processingId === req.id}
                                                        className="px-3 py-1.5 bg-slate-50 hover:bg-slate-200 text-slate-600 border border-slate-200 rounded-lg text-xs font-bold transition-colors flex items-center gap-1.5 disabled:opacity-40"
                                                    >
                                                        <XCircle size={14} /> رفض
                                                    </button>
                                                </div>
                                            ) : (
                                                <span className="text-xs text-slate-400 font-medium">مكتمل</span>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}
