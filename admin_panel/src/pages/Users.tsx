import { useState, useEffect } from 'react';
import { Search, Filter, UserCheck, UserX, Mail, Phone, Users as UsersIcon } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, limit, Timestamp, doc, updateDoc, getCountFromServer, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface UserRecord {
    uid: string;
    name?: string;
    phone?: string;
    email?: string;
    role?: string;
    status?: string;
    created_at?: Timestamp;
    dateStr?: string;
}

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'active':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><UserCheck size={14} />نشط</span>;
        case 'driver':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#FAF1F6] text-[#4D0026] font-bold border border-[#F2DEE9] text-xs"><UsersIcon size={14} />سائق</span>;
        case 'inactive':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 text-slate-600 font-bold border border-slate-200 text-xs">غير نشط</span>;
        case 'banned':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><UserX size={14} />محظور</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 text-slate-600 font-bold border border-slate-200 text-xs">{status || 'عميل'}</span>;
    }
};

export default function Users() {
    const [searchTerm, setSearchTerm] = useState('');
    const [users, setUsers] = useState<UserRecord[]>([]);
    const [loading, setLoading] = useState(true);
    // إجمالي المستخدمين بتجميع count() خادمي — كان يُشتق من طول قائمةٍ تقرأ
    // المجموعة كلها، والآن القائمة مقيّدة بأحدث 300 فلا يصلح طولها كإجمالي.
    const [totalCount, setTotalCount] = useState<number | null>(null);
    // فشل المستمع نهائي (لا يُعاد الاشتراك) — نُظهر حالة خطأ بزر إعادة بدل جدول فارغ.
    const [loadError, setLoadError] = useState(false);
    const [retryKey, setRetryKey] = useState(0);
    const { confirm, toast } = useNotification();

    useEffect(() => {
        // (أداء) أحدث 300 فقط — كانت مجموعة users كلها (الأسرع نمواً) تُقرأ بلا حد.
        const q = query(collection(db, 'users'), orderBy('created_at', 'desc'), limit(300));
        const unsubscribe = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            const fetched = snapshot.docs.map((d: QueryDocumentSnapshot<DocumentData>) => {
                const data = d.data() as Partial<UserRecord>;
                let dateStr = 'غير متاح';
                if (data.created_at instanceof Timestamp) {
                    dateStr = data.created_at.toDate().toLocaleDateString('ar-EG');
                }
                return { uid: d.id, dateStr, ...data } as UserRecord;
            });
            setUsers(fetched);
            setLoading(false);
        }, (e) => {
            console.error('Users listener error:', e);
            setLoading(false);
            setLoadError(true);
        });

        getCountFromServer(collection(db, 'users'))
            .then(s => setTotalCount(s.data().count))
            .catch(e => {
                // فشل العدّاد وحده لا يحجب قائمةً حُمّلت بنجاح — يبقى «...» لا صفراً كاذباً.
                console.error('Users count error:', e);
            });

        return () => unsubscribe();
    }, [retryKey]);

    const filteredUsers = users.filter(u =>
        (u.name || '').includes(searchTerm) ||
        (u.phone || '').includes(searchTerm) ||
        (u.uid || '').toLowerCase().includes(searchTerm.toLowerCase())
    );

    const toggleBan = async (uid: string, currentStatus: string) => {
        const banning = currentStatus !== 'banned';
        // تأكيد صريح: الحظر يُسجَّل خروج المستخدم فوراً — نقرة خاطئة تحظر عميلاً حقيقياً.
        if (!await confirm(banning
            ? 'هل تريد حظر هذا المستخدم؟ سيُسجَّل خروجه فوراً ولن يستطيع استخدام التطبيق.'
            : 'هل تريد رفع الحظر عن هذا المستخدم؟')) return;
        try {
            await updateDoc(doc(db, 'users', uid), { status: banning ? 'banned' : 'active' });
            toast.success(banning ? 'تم حظر المستخدم' : 'تم رفع الحظر');
        } catch {
            toast.error('تعذّر تحديث حالة المستخدم — أعد المحاولة');
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة المستخدمين (حي)</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">قائمة حية بالمستخدمين المسجلين — يعرض أحدث 300</p>
                </div>
                <div className="flex items-center gap-3">
                    <span className="px-4 py-2 bg-[#FAF1F6] text-[#4D0026] font-bold rounded-xl border border-[#F2DEE9] text-sm">
                        إجمالي: {totalCount ?? '...'} مستخدم
                    </span>
                    <button type="button" className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                        <Filter size={18} /> تصفية
                    </button>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث بالاسم أو رقم الجوال أو ID..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#660033]/20 focus:border-[#660033] transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                </div>

                <div className="overflow-x-auto min-h-[300px]">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64">
                            <div className="animate-spin rounded-full h-10 w-10 border-4 border-[#660033] border-t-transparent" />
                            <p className="text-slate-500 mt-4 font-bold">جاري جلب بيانات المستخدمين...</p>
                        </div>
                    ) : loadError ? (
                        // حالة خطأ صريحة لا «لا يوجد مستخدمون» — الفراغ عند الفشل مضلّل.
                        <div className="flex flex-col items-center justify-center h-64 gap-4 bg-rose-50/40 m-6 rounded-2xl border border-rose-100">
                            <p className="text-rose-600 font-bold">تعذّر تحميل المستخدمين — تحقّق من الاتصال أو الصلاحيات</p>
                            <button
                                type="button"
                                onClick={() => { setLoadError(false); setLoading(true); setRetryKey(k => k + 1); }}
                                className="px-5 py-2.5 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 transition-colors"
                            >
                                إعادة المحاولة
                            </button>
                        </div>
                    ) : (
                        <table className="w-full text-right border-collapse">
                            <thead>
                                <tr className="bg-slate-50 border-b border-slate-100">
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">المستخدم</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">رقم الجوال</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">نوع الحساب</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ التسجيل</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                    <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 text-center">إجراء</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-50">
                                {filteredUsers.length === 0 ? (
                                    <tr>
                                        <td colSpan={6} className="text-center py-14 text-slate-400 font-bold">
                                            {searchTerm ? 'لا توجد نتائج لبحثك' : 'لا يوجد مستخدمون مسجلون بعد'}
                                        </td>
                                    </tr>
                                ) : filteredUsers.map((user) => (
                                    <tr key={user.uid} className="hover:bg-[#FAF1F6]/30 transition-colors">
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[#F2DEE9] to-[#F2DEE9] flex items-center justify-center text-[#4D0026] font-bold border border-[#E5C3D5] text-sm">
                                                    {(user.name || user.uid || 'U').substring(0, 1).toUpperCase()}
                                                </div>
                                                <div>
                                                    <span className="block font-bold text-slate-800">{user.name || 'مستخدم'}</span>
                                                    <span className="text-slate-400 text-xs font-mono">{user.uid.substring(0, 12)}...</span>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-2 text-sm text-slate-600 font-mono" dir="ltr">
                                                <Phone size={14} className="text-slate-400 shrink-0" />
                                                <span>{user.phone || '—'}</span>
                                            </div>
                                            {user.email && (
                                                <div className="flex items-center gap-2 text-xs text-slate-400 mt-1">
                                                    <Mail size={12} className="shrink-0" />
                                                    <span>{user.email}</span>
                                                </div>
                                            )}
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`text-xs font-bold px-2 py-1 rounded-md ${user.role === 'driver' ? 'bg-[#FAF1F6] text-[#660033]' : 'bg-violet-50 text-violet-600'}`}>
                                                {user.role === 'driver' ? '🚗 سائق' : '👤 عميل'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 font-medium text-slate-500 text-sm">{user.dateStr}</td>
                                        <td className="px-6 py-4"><StatusBadge status={user.status || 'active'} /></td>
                                        <td className="px-6 py-4 text-center">
                                            <button
                                                type="button"
                                                onClick={() => toggleBan(user.uid, user.status || 'active')}
                                                className={`p-2 rounded-lg transition-colors text-xs font-bold ${user.status === 'banned' ? 'text-emerald-600 hover:bg-emerald-50' : 'text-rose-500 hover:bg-rose-50'}`}
                                                title={user.status === 'banned' ? 'رفع الحظر' : 'حظر المستخدم'}
                                            >
                                                {user.status === 'banned' ? <UserCheck size={18} /> : <UserX size={18} />}
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>
        </div>
    );
}

