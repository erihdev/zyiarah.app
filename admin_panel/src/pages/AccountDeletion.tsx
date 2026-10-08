import { useState, useEffect } from 'react';
import { ShieldAlert, Trash2, Search, CheckCircle2, XCircle, AlertTriangle, Loader2 } from 'lucide-react';
import {
    collection, onSnapshot, updateDoc,
    doc, orderBy, query, limit
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/notificationContext.ts';
import {
    deletionRowIdentity, deletionStrandedBalance, deletionRequestState,
    deletionStateLabel, deletionRetryAllowed, deletionFailureReason,
} from '../utils/deletionLogRow.ts';
import { formatSar } from '../utils/money.ts';
import { logAudit, AUDIT } from '../services/audit.ts';

interface DeletionRequest {
    id: string;
    type?: string;
    name?: string;
    phone?: string;
    requested_at?: { toDate: () => Date };
    reason?: string;
    // **`email` كان مكتوباً ولا تَقرؤه اللوحةُ إطلاقاً**، و`name`/`phone`
    // لا يَكتبُهما كاتبٌ (المصادقةُ بالبريدِ وحدَه فـ`phoneNumber` فارغ) —
    // فكلُّ صفٍّ كان يُقرأُ «— / —». والقاعدةُ في `utils/deletionLogRow.ts`.
    email?: string;
    // الدَّينُ الذي يَكتبُه الخادمُ عند الحذفِ — كان بلا قارئٍ في أيِّ سطح.
    wallet_balance_at_deletion?: number;
    // الدالة onRequestAccountDeletion تكتب deleted_fully_processed عند نجاح التنظيف
    // الكامل، و failed_deletion عند فشله — كانت اللوحة تجهل هاتين الحالتين فتظهران فارغتين.
    //
    // والنوعُ `string`: التسميةُ والإجراءُ من `deletionLogRow` فتَقرأُ أيَّ
    // قيمةٍ وتَقولُ «حالة غير معروفة» لما لا تَعرفُه — بدلَ اتّحادٍ يَكذبُ
    // على مستندٍ كُتبَ بيدٍ في الكونسول.
    status?: string;
    // **سببُ الفشلِ الذي يَكتبُه الخادمُ — كان بلا قارئٍ في أيِّ سطح**،
    // فالصفُّ يَقولُ «يتطلب مراجعة» ولا يُظهرُ ما يُراجَع.
    error?: unknown;
    userId?: string;
}

const formatDate = (ts?: { toDate: () => Date }): string => {
    if (!ts) return '—';
    return ts.toDate().toLocaleDateString('ar-SA');
};

export default function AccountDeletion() {
    const { confirm, toast } = useNotification();
    const [searchTerm, setSearchTerm] = useState('');
    const [requests, setRequests] = useState<DeletionRequest[]>([]);
    const [loading, setLoading] = useState(true);
    const [processingId, setProcessingId] = useState<string | null>(null);
    // فشل المستمع نهائي — حالة خطأ صريحة بزر إعادة بدل «لا توجد طلبات» المضلّلة.
    const [loadError, setLoadError] = useState(false);
    const [retryKey, setRetryKey] = useState(0);
    // الساعةُ في الحالةِ لا في جسمِ الرسم: `Date.now()` هناك غيرُ نقيّة
    // (`react-hooks/purity`)، ونبضةُ الدقيقةِ تَجعلُ الصفَّ الذي يَعلَقُ
    // والصفحةُ مفتوحةٌ يَكشفُ زرَّه بنفسِه بدلَ أن يَنتظرَ تحديثاً.
    const [nowMs, setNowMs] = useState(() => Date.now());

    useEffect(() => {
        const t = setInterval(() => setNowMs(Date.now()), 60_000);
        return () => clearInterval(t);
    }, []);

    useEffect(() => {
        // (أداء) أحدث 300 فقط — السجلات المعالَجة تتراكم للأبد (متطلب آبل يحفظها)
        // وكانت تُقرأ كلها مع كل فتح للصفحة.
        const q = query(collection(db, 'account_deletions'), orderBy('requested_at', 'desc'), limit(300));
        const unsub = onSnapshot(q, (snap) => {
            setRequests(snap.docs.map(d => ({ id: d.id, ...d.data() } as DeletionRequest)));
            setLoading(false);
        }, (e) => {
            console.error('AccountDeletion listener error:', e);
            setLoading(false);
            setLoadError(true);
        });
        return unsub;
    }, [retryKey]);

    // **البحثُ كان ميّتاً**: يُرشِّحُ على `name`/`phone` ولا كاتبَ لهما
    // (المصادقةُ بالبريدِ وحدَه). فالمرشَّحُ هو ما يُعرَضُ فعلاً.
    const filtered = requests.filter(r =>
        !searchTerm.trim() ||
        deletionRowIdentity(r).includes(searchTerm.trim())
    );

    const handleDelete = async (req: DeletionRequest) => {
        if (!await confirm(`هل تريد مسح بيانات ${req.name ?? 'هذا المستخدم'} نهائياً؟ لا يمكن التراجع.`)) return;
        setProcessingId(req.id);
        try {
            // **لا حذفَ مباشراً لمستندِ المستخدم.** كان هنا
            // `deleteDoc(users/{req.userId})` — و`userId` حقلٌ **لا يَكتبُه
            // كاتبٌ قطّ**، فالشرطُ كاذبٌ دائماً والسطرُ ميّت. ولو عَمِلَ
            // لكانَ خطأً: تعليقُ `admin_users_screen` يَقولُه نصّاً («حذفُ
            // مستندِ users وحدَه كان يَترُكُ حسابَ Auth حيّاً»). والكتابةُ
            // أدناه هي المُشغِّلُ: `onAccountDeletionStatusChanged` يَنقلُ
            // الحالةَ إلى `deleted` فيَتولّى `processAccountDeletion` الحذفَ
            // كاملاً (Auth + users + رموز FCM + رصدُ رصيدِ المحفظة).
            await updateDoc(doc(db, 'account_deletions', req.id), {
                status: 'deleted',
                processed_at: new Date(),
            });
            // حذفُ حسابٍ لا رجعةَ فيه ويَترُكُ رصيدَ المحفظةِ دَيناً —
            // ومسارُ تطبيقِ الأدمنِ يُقيّده. نُسجّلُ الرصيدَ العالقَ معه
            // لأنّه الرقمُ الذي يُراجَعُ لاحقاً.
            await logAudit(AUDIT.PROCESS_ACCOUNT_DELETION, {
                decision: 'deleted',
                account: deletionRowIdentity(req),
                ...(deletionStrandedBalance(req) !== null
                    ? { stranded_balance: deletionStrandedBalance(req) }
                    : {}),
            }, req.id);
            toast.success('تم تنفيذ طلب الحذف');
        } catch {
            // امتثال آبل: لا تُظهر الحذف كناجح إن فشل فعلاً.
            toast.error('تعذّر تنفيذ الحذف — لم يكتمل، أعد المحاولة');
        } finally {
            setProcessingId(null);
        }
    };

    /// **مَخرَجُ الفشل.** الخادمُ يَكتبُ `failed_deletion` ويَقولُ الصفُّ
    /// «يتطلب مراجعة» بلا إجراء: الزرّانِ أدناه محصورانِ بـ`'pending'`
    /// **ولا كاتبَ لها**. وزرُّ «رفض» قرارُ مالكٍ (2026-07-21) فلم يُمَسّ.
    const handleRetry = async (req: DeletionRequest) => {
        if (!await confirm(`إعادة تشغيل حذف حساب ${deletionRowIdentity(req)} خادمياً؟ `
            + 'الحذف لا رجعة فيه: حساب الدخول ومستند المستخدم ورموز الإشعارات '
            + 'تُمسح، والرصيد المتبقّي يُسجَّل ديناً للتسوية اليدوية.')) return;
        setProcessingId(req.id);
        try {
            await updateDoc(doc(db, 'account_deletions', req.id), {
                status: 'deleted',
                processed_at: new Date(),
            });
            await logAudit(AUDIT.PROCESS_ACCOUNT_DELETION, {
                decision: 'retry',
                account: deletionRowIdentity(req),
                ...(deletionStrandedBalance(req) !== null
                    ? { stranded_balance: deletionStrandedBalance(req) }
                    : {}),
            }, req.id);
            toast.success('أُعيد تشغيل الحذف — تابع الحالة بعد ثوانٍ');
        } catch {
            // امتثال آبل: لا تُظهر الحذف كناجح إن فشل فعلاً.
            toast.error('تعذّرت إعادة المحاولة — أعد المحاولة');
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
            // ورفضُ طلبِ حذفٍ قرارُ امتثالٍ كذلك: «مَن رفضَ ومتى؟» سؤالٌ
            // بلا جواب بلا قيد — وكان صامتاً في السطحَين معاً.
            await logAudit(AUDIT.PROCESS_ACCOUNT_DELETION, {
                decision: 'rejected',
                account: deletionRowIdentity(req),
            }, req.id);
            toast.success('تم رفض الطلب');
        } catch {
            toast.error('تعذّر رفض الطلب — أعد المحاولة');
        } finally {
            setProcessingId(null);
        }
    };

    const pendingCount = requests.filter(r => r.status === 'pending').length;
    // **والرقمُ الذي يَحتاجُه المالكُ هو ما يَنتظرُ إجراءَه فعلاً** — فشلٌ،
    // أو `'deleted'` عالقٌ تجاوزَ المُهلة. وعدّادُ «معلّق» أعلاه صفرٌ
    // بنيويّاً (`'pending'` لا يَكتبُه كاتب) فيُتركُ كما هو ويُضافُ هذا.
    const needsActionCount = requests.filter(r => deletionRetryAllowed(
        deletionRequestState(r.status),
        r.requested_at ? r.requested_at.toDate().getTime() : null,
        nowMs,
    )).length;

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
                        {needsActionCount > 0 && (
                            <span className="text-xs bg-rose-100 text-rose-700 px-2 py-0.5 rounded-full font-bold">{needsActionCount} يحتاج إجراء</span>
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
                            placeholder="ابحث بالبريد أو الاسم أو رقم الجوال..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-rose-500/20 focus:border-rose-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                    <span className="text-xs text-slate-400 font-medium">{requests.length} طلب — يعرض أحدث 300</span>
                </div>

                {loading ? (
                    <div className="flex items-center justify-center py-16 text-slate-400 gap-2">
                        <Loader2 size={20} className="animate-spin" />
                        <span className="text-sm font-medium">جاري التحميل...</span>
                    </div>
                ) : loadError ? (
                    // حالة خطأ صريحة لا «لا توجد طلبات» — الفراغ عند الفشل خطير في مسار امتثال آبل.
                    <div className="flex flex-col items-center justify-center py-16 gap-4 bg-rose-50/40 m-6 rounded-2xl border border-rose-100">
                        <p className="text-rose-600 font-bold">تعذّر تحميل طلبات الحذف — تحقّق من الاتصال أو الصلاحيات</p>
                        <button
                            type="button"
                            onClick={() => { setLoadError(false); setLoading(true); setRetryKey(k => k + 1); }}
                            className="px-5 py-2.5 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 transition-colors"
                        >
                            إعادة المحاولة
                        </button>
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
                                            {/* لا كاتبَ لـ`type` في المستودع، فكلُّ صفٍّ كان يُوسَمُ
                                                «عميل» — ومنه حذفُ سائق. «لا رقمَ قبل أن نعرفه». */}
                                            {req.type ? (
                                                <span className={`px-2 py-1 text-xs font-bold rounded-md ${req.type === 'driver' || req.type === 'سائق' ? 'bg-[#FAF1F6] text-[#4D0026]' : 'bg-teal-50 text-teal-700'}`}>
                                                    {req.type === 'driver' ? 'سائق' : 'عميل'}
                                                </span>
                                            ) : (
                                                <span className="text-xs text-slate-400">—</span>
                                            )}
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="font-bold text-slate-800 dir-ltr">{deletionRowIdentity(req)}</div>
                                            {deletionStrandedBalance(req) !== null && (
                                                <div className="text-xs text-rose-600 font-bold mt-0.5">
                                                    رصيد محجوز: {formatSar(deletionStrandedBalance(req)!)} ر.س — التسوية يدوية
                                                </div>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 text-sm font-medium text-slate-500">{formatDate(req.requested_at)}</td>
                                        <td className="px-6 py-4 text-sm text-slate-600 line-clamp-1">{req.reason ?? '—'}</td>
                                        {/* **التسميةُ من القاعدةِ المشترَكة.** كان `'deleted'`
                                            يُرسَمُ «تم الحذف نهائياً» بعلامةٍ خضراءَ مع
                                            `deleted_fully_processed` — وهو «سُجِّلَ والخادمُ
                                            يَعملُ عليه»، وقد يَبقى عليها إلى الأبدِ لو ماتَ
                                            الحاوي قبلَ تحديثِ الحالة. وشاشةُ التطبيقِ تَقولُ
                                            «جاري المسح». */}
                                        <td className="px-6 py-4">
                                            {(() => {
                                                const st = deletionRequestState(req.status);
                                                const cls = st === 'completed'
                                                    ? 'text-emerald-600 bg-emerald-50 border-emerald-100'
                                                    : st === 'failed'
                                                        ? 'text-rose-600 bg-rose-50 border-rose-100'
                                                        : st === 'rejected'
                                                            ? 'text-slate-600 bg-slate-100 border-slate-200'
                                                            : 'text-amber-600 bg-amber-50 border-amber-100';
                                                const Ico = st === 'completed'
                                                    ? CheckCircle2
                                                    : st === 'rejected' ? XCircle : AlertTriangle;
                                                return (
                                                    <>
                                                        <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold border ${cls}`}>
                                                            <Ico size={12} />{deletionStateLabel(st)}
                                                        </span>
                                                        {deletionFailureReason(req) && (
                                                            <div className="text-xs text-rose-600 mt-1 dir-ltr break-all">
                                                                {deletionFailureReason(req)}
                                                            </div>
                                                        )}
                                                    </>
                                                );
                                            })()}
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
                                            ) : deletionRetryAllowed(
                                                deletionRequestState(req.status),
                                                req.requested_at ? req.requested_at.toDate().getTime() : null,
                                                nowMs,
                                            ) ? (
                                                <button
                                                    type="button"
                                                    title="إعادة تشغيل الحذف خادمياً"
                                                    onClick={() => handleRetry(req)}
                                                    disabled={processingId === req.id}
                                                    className="px-3 py-1.5 bg-rose-50 hover:bg-rose-600 hover:text-white text-rose-600 border border-rose-100 rounded-lg text-xs font-bold transition-colors inline-flex items-center gap-1.5 disabled:opacity-40"
                                                >
                                                    {processingId === req.id
                                                        ? <Loader2 size={14} className="animate-spin" />
                                                        : <Trash2 size={14} />}
                                                    إعادة المحاولة
                                                </button>
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
