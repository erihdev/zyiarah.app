import { useState, useEffect, useRef } from 'react';
import { formatSarAny } from '../utils/money';
import { Search, Filter, MoreVertical, CheckCircle2, Clock, XCircle, Package, UserCheck, X, Loader2, CalendarClock, Undo2 } from 'lucide-react';
import {
    collection, onSnapshot, query, orderBy, where, limit, doc, Timestamp, updateDoc, runTransaction,
    type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from '../services/firebase.ts';
import { useNotification } from '../components/notificationContext.ts';
import { cancelRefundNotice, cancelRefundAdminText } from '../utils/cancelRefundNotice.ts';
import { rescheduleDerivedFields } from '../utils/bookingFields.ts';
import ServiceMetaTable from '../components/ServiceMetaTable.tsx';
// الملخّصُ انتقلَ إلى `utils/serviceMeta.ts` بجوارِ `metaRows`/`metaHeadline`:
// هو مرآةُ الدالّةِ نفسِها في `service_meta_view.dart`، فمَوضعُه حيثُ تُختبَرُ
// المرآة — وتصديرُ دالّةٍ من ملفِّ مُكوِّنٍ يَكسرُ fast-refresh في React.
import { metaSummary } from '../utils/serviceMeta.ts';
// وسمُ مراجعةِ السعرِ: الإدارةُ تَعملُ من سطحَين، فقارئٌ في التطبيقِ وحدَه
// يَترُكُ الطلبَ عاديَّ المنظرِ لمن يَعملُ من اللوحة.
import { priceReviewOf, priceReviewApprovalPayload } from '../utils/priceReview.ts';
import PriceReviewBadge from '../components/PriceReviewBadge.tsx';
import { auth } from '../services/firebase.ts';
import { logAudit, AUDIT } from '../services/audit.ts';

// تنسيق تاريخ لحقل datetime-local (YYYY-MM-DDTHH:mm).
const toDatetimeLocal = (dt: Date) => {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${dt.getFullYear()}-${p(dt.getMonth() + 1)}-${p(dt.getDate())}T${p(dt.getHours())}:${p(dt.getMinutes())}`;
};

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
    payment_method?: string;
    is_paid?: boolean;
    // **المبلغُ الخامُّ**: `amount` أعلاه نصٌّ منسَّقٌ للعرضِ («120 ر.س»)،
    // وجملةُ «ماذا يَحدثُ لمالِها إن أُلغي» تَحتاجُ الرقم. غيابُه (أو مستندٌ
    // قديمٌ بنصّ) يُنتجُ جملةً شرطيّةً بلا رقمٍ مُلفَّق.
    amount_raw?: number;
    // استرداد التقسيط: refunded يكتبها الخادم بعد استرداد البوابة، و
    // refund_credited تعني أن المبلغ رُدّ لمحفظة العميل داخل التطبيق —
    // كلتاهما تُخفيان زر الاسترداد (الخادم يرفضه بعدها منعاً للردّ المزدوج).
    refunded?: boolean;
    refund_credited?: boolean;
    service_date?: Timestamp;
    // تفصيل الخدمة — يظهر تحت نوع الخدمة وفي نافذتي التعيين/التعديل.
    // ستة أنواع يكتبها التطبيق؛ كانت اللوحة تقرأ home_package وحده.
    service_meta?: {
        kind?: string;
        // home_package
        homeLabel?: string; crewCount?: number; durationHours?: number;
        materials?: { name?: string; quantity?: number }[];
        // ac_service / car_interior
        lines?: { label?: string; count?: number }[];
        // sofa_rug_sqm
        pieces?: { label?: string; billed_measure?: number; area_sqm?: number; uses_area?: boolean }[];
        // store_products
        items?: { name?: string; quantity?: number }[];
        // event_workers
        workers?: number; event_hours?: number;
    };
    worker_count?: number;
    hours_contracted?: number;
}

interface DriverOption { id: string; name: string; is_available: boolean; is_active: boolean; }

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'completed': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><CheckCircle2 size={14} />مكتمل</span>;
        case 'pending':   return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />بانتظار سائق</span>;
        case 'pending_admin_approval': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-orange-50 text-orange-700 font-bold border border-orange-100 text-xs"><Clock size={14} />بانتظار موافقة الإدارة</span>;
        case 'awaiting_payment': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-xs"><Clock size={14} />بانتظار الدفع</span>;
        case 'under_review': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-orange-50 text-orange-700 font-bold border border-orange-100 text-xs"><Clock size={14} />تحت المراجعة</span>;
        case 'delivering': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#FAF1F6] text-[#4D0026] font-bold border border-[#F2DEE9] text-xs"><Package size={14} />جاري التنفيذ</span>;
        case 'scheduled': case 'assigned': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-teal-50 text-teal-700 font-bold border border-teal-100 text-xs"><UserCheck size={14} />تم تعيين السائق</span>;
        case 'accepted':  return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#FAF1F6] text-[#4D0026] font-bold border border-[#F2DEE9] text-xs"><UserCheck size={14} />تم القبول</span>;
        case 'on_the_way': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-cyan-50 text-cyan-700 font-bold border border-cyan-100 text-xs"><Package size={14} />في الطريق</span>;
        case 'in_progress': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#FAF1F6] text-[#4D0026] font-bold border border-[#F2DEE9] text-xs"><Package size={14} />جاري التنفيذ</span>;
        case 'cancelled': return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><XCircle size={14} />ملغي</span>;
        default: return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-xs">{status}</span>;
    }
};

export default function Orders() {
    const { toast, confirm } = useNotification();
    const [searchTerm, setSearchTerm] = useState('');
    const [orders, setOrders] = useState<OrderRecord[]>([]);
    const [drivers, setDrivers] = useState<DriverOption[]>([]);
    // المستمعُ الرئيسُ أدناه يُظهِرُ حالةَ خطأٍ بزرِّ إعادة («لا فشل صامت»)،
    // ومستمعُ السائقينِ بجوارِه كان `console.error` وحدَه — ففشلُه يَجعلُ
    // حوارَ الإسنادِ يَطبعُ **«لا يوجد سائقون متاحون حالياً»**: دعوى عن
    // الأسطولِ تَمنعُ الأدمنَ من إسنادِ طلبٍ مدفوعٍ ولا تُخبرُه بالسبب.
    const [driversError, setDriversError] = useState(false);
    const [loading, setLoading] = useState(true);
    // فشل المستمع نهائي (Firestore لا يعيد الاشتراك) — كان الدوّار يعلق للأبد بلا
    // رسالة ولا زر إعادة؛ retryKey يعيد تشغيل الاشتراك عند طلب المستخدم.
    const [loadError, setLoadError] = useState(false);
    const [retryKey, setRetryKey] = useState(0);
    // عدّاد «انتظار» من مستمع مقيّد بالحالة — يبقى دقيقاً رغم سقف الـ300 أدناه.
    const [pendingCount, setPendingCount] = useState<number | null>(null);
    const [actionMenuId, setActionMenuId] = useState<string | null>(null);
    const [assignModal, setAssignModal] = useState<OrderRecord | null>(null);
    const [selectedDriverId, setSelectedDriverId] = useState('');
    const [scheduledAt, setScheduledAt] = useState('');
    const [isAssigning, setIsAssigning] = useState(false);
    const [isCancelling, setIsCancelling] = useState(false);
    const [isRefunding, setIsRefunding] = useState(false);
    // «تعديل الزيارة»: تغيير الموعد و/أو السائق لطلبٍ قائم.
    const [editModal, setEditModal] = useState<OrderRecord | null>(null);
    const [editScheduledAt, setEditScheduledAt] = useState('');
    // قيمة الحقل لحظة الفتح: نُرسل الموعد **فقط إن تغيّر** — إرساله دائماً كان
    // يجعل تبديل السائق وحده «إعادة جدولة» فتُصفَّر أعلام التذكير وتُعاد التذكيرات.
    const [editOriginalAt, setEditOriginalAt] = useState('');
    const [editDriverId, setEditDriverId] = useState('');
    const [isEditing, setIsEditing] = useState(false);
    const menuRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        // (أداء) أحدث 300 فقط — كانت المجموعة كلها تُقرأ وتُبقى حيّة بلا حد،
        // فتتضخم القراءات مع كل طلب جديد (تكافؤ سقف تطبيق الأدمن).
        const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(300));
        const unsub = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            setOrders(snapshot.docs.map((doc: QueryDocumentSnapshot<DocumentData>) => {
                const d = doc.data() as Partial<OrderRecord>;
                // الانتشار **أولاً** ثم الحقول المشتقة: كان ...d في الآخر فيدهس
                // amount المنسّق برقم المستند الخام — عمود المبلغ بلا «ر.س».
                return {
                    ...d,
                    id: doc.id,
                    customer: d.client_name || d.client_id || 'غير متوفر',
                    driver: d.assigned_driver || (d.status === 'pending' ? 'بانتظار سائق' : '-'),
                    status: d.status || 'pending',
                    amount: `${formatSarAny(d.amount)} ر.س`,
                    amount_raw: typeof (doc.data() as DocumentData).amount === 'number'
                        ? ((doc.data() as DocumentData).amount as number)
                        : undefined,
                    date: d.created_at instanceof Timestamp ? d.created_at.toDate().toLocaleDateString('ar-EG') : 'غير متاح',
                    type: d.service_type || 'خدمة عامة',
                } as OrderRecord;
            }));
            setLoading(false);
        }, (e) => {
            // لا فشل صامت: خطأ المستمع (صلاحيات/جلسة منتهية) يُظهر حالة خطأ بزر إعادة.
            console.error('Orders listener error:', e);
            setLoading(false);
            setLoadError(true);
        });

        const pendingUnsub = onSnapshot(
            query(collection(db, 'orders'), where('status', '==', 'pending')),
            (snap) => setPendingCount(snap.size),
            (e) => console.error('Pending count listener error:', e)
        );

        const driversUnsub = onSnapshot(collection(db, 'drivers'), (snap) => {
            setDrivers(snap.docs.map(d => ({ id: d.id, name: d.data().name || 'سائق', is_available: d.data().is_available || false, is_active: d.data().is_active !== false })));
            setDriversError(false);
        }, (e) => { console.error('Drivers listener error:', e); setDriversError(true); });

        return () => { unsub(); pendingUnsub(); driversUnsub(); };
    }, [retryKey]);

    useEffect(() => {
        const handler = (e: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(e.target as Node)) setActionMenuId(null);
        };
        document.addEventListener('mousedown', handler);
        return () => document.removeEventListener('mousedown', handler);
    }, []);

    const handleAssignDriver = async () => {
        if (!assignModal || !selectedDriverId || !scheduledAt) return;
        setIsAssigning(true);
        try {
            // نوجّه عبر approveAndAssignOrder: ذرّية، تفحص تفرّغ السائق (لا حجز
            // مزدوج)، تعتمد طلبات pending_admin_approval، وتوحّد الحالة على
            // scheduled، وتُطلق إشعار السائق خادمياً. لا كتابة مباشرة خام.
            await httpsCallable(functions, 'approveAndAssignOrder')({
                orderId: assignModal.id,
                driverId: selectedDriverId,
                // سلسلة محلية بلا منطقة: الخادم (_parseKsaIso) يفسّرها توقيت الرياض
                // دائماً — بصرف النظر عن منطقة متصفح الأدمن.
                scheduledIso: scheduledAt,
            });
            setAssignModal(null);
            setSelectedDriverId('');
            setScheduledAt('');
            toast.success('تم اعتماد الطلب وتعيين السائق');
        } catch (err: unknown) {
            console.error('Error assigning driver:', err);
            toast.error((err as { message?: string })?.message || 'حدث خطأ أثناء التعيين');
        } finally {
            setIsAssigning(false);
        }
    };

    // «تعديل الزيارة» — نفس مساري تطبيق الأدمن (admin_order_details_screen):
    // طلب مُسنَد نشط ⇒ rescheduleAssignedOrder الذرّية (تفحص تعارض السائق المستهدَف
    // داخل معاملة، وتُطلق إشعارَي العميل/السائق خادمياً، وتحرير السائق القديم عند
    // التبديل يتكفّل به freeOldDriverOnReassign)؛ وإلا (pending/مُدار بلا سائق) ⇒
    // كتابة الموعد مباشرة (لا سائق يُفحص تعارضه).
    const ACTIVE_ASSIGNED = ['scheduled', 'assigned', 'accepted', 'on_the_way', 'in_progress'];
    const handleEditVisit = async () => {
        if (!editModal) return;
        setIsEditing(true);
        try {
            if (editModal.driver_id && ACTIVE_ASSIGNED.includes(editModal.status)) {
                const payload: { orderId: string; scheduledIso?: string; newDriverId?: string } = {
                    orderId: editModal.id,
                };
                // نُرسل الموعد فقط إن **تغيّر** فعلاً (تبديل سائق وحده ≠ إعادة جدولة)،
                // وكسلسلة محلية **بلا منطقة زمنية**: _parseKsaIso الخادمية تفسّرها
                // توقيتَ الرياض دائماً — toISOString كانت تفسّر الحائط بمنطقة المتصفح،
                // فمتصفحٌ خارج السعودية يخزّن لحظةً مختلفة عن تطبيق الأدمن لنفس «14:00».
                if (editScheduledAt && editScheduledAt !== editOriginalAt) {
                    payload.scheduledIso = editScheduledAt;
                }
                if (editDriverId && editDriverId !== editModal.driver_id) payload.newDriverId = editDriverId;
                if (!payload.scheduledIso && !payload.newDriverId) {
                    toast.error('لا تغيير — عدّل الموعد أو اختر سائقاً آخر');
                    setIsEditing(false);
                    return;
                }
                await httpsCallable(functions, 'rescheduleAssignedOrder')(payload);
            } else {
                if (!editScheduledAt) {
                    toast.error('حدد الموعد الجديد');
                    setIsEditing(false);
                    return;
                }
                const chosen = new Date(editScheduledAt);
                const ts = Timestamp.fromDate(chosen);
                // الحقلان المشتقّان وتصفير أعلام التذكير — القاعدة في
                // `utils/bookingFields.ts`. كانت هذه الكتابة `service_date`/
                // `scheduled_at` وحدهما: `capacity.js` يعدّ من `booking_date`
                // و`booking_time_slot` فيستهلك الطلب سعة يومه القديم ويُباع
                // يومه الجديد أكثر من طاقته، والساعة المعروضة للعميلة تبقى
                // القديمة، والتذكير لا يُعاد إرساله للموعد الجديد.
                await updateDoc(doc(db, 'orders', editModal.id), {
                    service_date: ts,
                    scheduled_at: ts,
                    ...rescheduleDerivedFields(chosen),
                    updated_at: Timestamp.now(),
                });
            }
            toast.success('تم تعديل الزيارة بنجاح');
            setEditModal(null);
            setEditScheduledAt('');
            setEditDriverId('');
        } catch (err: unknown) {
            console.error('Error editing visit:', err);
            // رسائل الدالة الخادمية عربية أصلاً (مثل «السائق مشغول بمهمة أخرى…»).
            toast.error((err as { message?: string })?.message || 'تعذّر تعديل الزيارة');
        } finally {
            setIsEditing(false);
        }
    };

    // الخدمات المُدارة إدارياً بلا سائق (تنظيف داخلية السيارة، وأي طلب مدفوع بلا
    // موعد): تحت المراجعة ⇒ جاري التنفيذ ⇒ تم التنفيذ — نفس سلسلة تطبيق الأدمن
    // (_advanceManagedOrder). كانت اللوحة تعرض حالتها بالإنجليزية بلا زر تقدّم.
    const handleAdvanceManaged = async (order: OrderRecord, next: 'in_progress' | 'completed') => {
        try {
            // معاملة بقراءة حديثة لا كتابة عمياء: الحالة قد تتغير بين رسم القائمة
            // والضغطة — لا تقدّم لطلب اكتمل أو أُلغي في هذه النافذة.
            await runTransaction(db, async (tx) => {
                const ref = doc(db, 'orders', order.id);
                const snap = await tx.get(ref);
                if (!snap.exists()) throw new Error('الطلب لم يعد موجوداً');
                const current = (snap.data() as { status?: string }).status;
                if (current === 'completed' || current === 'cancelled') {
                    throw new Error('الطلب اكتمل أو أُلغي بالفعل — لا يمكن تحديث حالته');
                }
                tx.update(ref, {
                    status: next,
                    // onOrderRewards يشترط مميّز الخادم لحظة الإكمال — بدونه تسقط
                    // نقاط قطرات ومكافأة الإحالة بصمت (نفس إصلاح تطبيق الأدمن).
                    ...(next === 'completed'
                        ? { completed_at: Timestamp.now(), rewards_handled_by: 'server' }
                        : {}),
                    updated_at: Timestamp.now(),
                });
            });
        } catch (err) {
            console.error('Error advancing order:', err);
            toast.error(err instanceof Error ? err.message : 'تعذّر تحديث الحالة');
        } finally {
            setActionMenuId(null);
        }
    };

    // **اعتمادُ المبلغِ الموسوم.** يُبطِلُ علمَي الاستعلامِ فيَخرُجُ المستندُ
    // من نافذةِ `opsHealthSweep` — وهو التصريفُ الذي لم يكن له سبيلٌ من قبل،
    // فكانت النافذةُ تَمتلئُ بما وُسِمَ ولا يُزيلُه أحد.
    const handleApprovePrice = async (order: OrderRecord) => {
        const code = order.code || order.id.substring(0, 6).toUpperCase();
        if (!await confirm(`اعتماد المبلغ المدفوع للطلب #${code} كما هو؟ سيُرفع وسم المراجعة.`)) return;
        try {
            await updateDoc(doc(db, 'orders', order.id), {
                ...priceReviewApprovalPayload(auth.currentUser?.email ?? 'Unknown Admin'),
                price_reviewed_at: Timestamp.now(),
                updated_at: Timestamp.now(),
            });
            await logAudit(AUDIT.REVIEW_ORDER_PRICE, {
                decision: 'approved',
                order_code: code,
                collection: 'orders',
            }, order.id);
            toast.success('تم اعتماد المبلغ');
        } catch (err) {
            // console.error وحدَه كان يُبلَعُ: الصفُّ لا يَتغيّرُ (لا كتابة ⇒ لا
            // تحديثَ للمُستمِع) فيَحسبُ الأدمنُ أنّه أخطأَ النقر.
            console.error('approve price failed:', err);
            toast.error(err instanceof Error ? err.message : 'تعذّر اعتماد المبلغ');
        } finally {
            setActionMenuId(null);
        }
    };

    const handleCancelOrder = async (order: OrderRecord) => {
        // **الحوارُ كان سطراً واحداً بلا كلمةٍ عن المال.** والنتيجةُ الخادميّةُ
        // ثلاثٌ، وأخطرُها أنّ المدفوعَ بالبطاقةِ يُودَعُ **في محفظةِ زيارة لا
        // إلى البطاقة** (`creditCancelledRefund`)، ولا مسارَ سحبٍ نقديٍّ
        // للمحفظةِ في المستودعِ كلِّه. القاعدةُ واحدةٌ مع حوارِ العميلةِ
        // وحوارِ تطبيقِ الإدارة: `cancelRefundNotice`.
        const notice = cancelRefundNotice({
            isPaid: order.is_paid === true,
            paymentMethod: order.payment_method,
            amount: order.amount_raw,
        });
        const line = cancelRefundAdminText(notice,
            {bnplRefundHere: canBnplRefund(order)});
        const head = `هل أنت متأكد من إلغاء الطلب #${order.code || order.id.substring(0, 6).toUpperCase()}؟`;
        if (!await confirm(line ? `${head}\n\n${line}` : head)) return;
        setIsCancelling(true);
        try {
            // معاملة بقراءة حديثة لا كتابة عمياء: أثناء نافذة التأكيد قد يُكمل السائق
            // الطلب — الكتابة القديمة كانت تقلب completed إلى cancelled وتصرف استرداداً
            // كاملاً للمحفظة عن خدمة نُفّذت فعلاً (تكافؤ حارس order_service.dart).
            // needs_refund only for actually-paid orders; rewards_handled_by:'server'
            // lets onOrderRewards credit the wallet refund. Driver release is handled
            // server-side by freeDriverOnOrderCancel (guards on current_order_id, so it
            // won't free a driver who has since moved on to another order).
            await runTransaction(db, async (tx) => {
                const ref = doc(db, 'orders', order.id);
                const snap = await tx.get(ref);
                if (!snap.exists()) throw new Error('الطلب لم يعد موجوداً');
                const current = snap.data() as { status?: string; is_paid?: boolean };
                if (current.status === 'completed' || current.status === 'cancelled') {
                    throw new Error('لا يمكن إلغاء طلب مكتمل أو ملغي بالفعل');
                }
                tx.update(ref, {
                    status: 'cancelled',
                    cancelled_at: Timestamp.now(),
                    cancelled_by: 'admin',
                    // من اللقطة الحديثة لا من إغلاق قديم أُسر قبل نافذة التأكيد.
                    needs_refund: current.is_paid === true,
                    rewards_handled_by: 'server',
                });
            });
        } catch (err) {
            console.error('Error cancelling order:', err);
            toast.error(err instanceof Error ? err.message : 'حدث خطأ أثناء الإلغاء');
        } finally {
            setIsCancelling(false);
            setActionMenuId(null);
        }
    };

    // استرداد مدفوعات التقسيط (تمارا/تابي) — خادميّ بالكامل عبر
    // tamaraRefundPayment/tabbyRefundPayment (عقدهما snake_case: order_id).
    // الزر يظهر لطلبٍ مدفوعٍ لم يُسترد بعد؛ عند النجاح يكتب الخادم is_paid:false
    // و refunded:true فيختفي الزر تلقائياً عبر المستمع الحي — كمسار تطبيق الأدمن.
    const canBnplRefund = (o: OrderRecord) =>
        (o.payment_method === 'tamara' || o.payment_method === 'tabby') &&
        o.is_paid === true && o.refunded !== true && o.refund_credited !== true;
    // الحالات النهائية: القائمة كانت تُخفى كلياً عندها — مع زر الاسترداد صارت
    // تُفتح لها أيضاً (الاسترداد أكثر ما يلزم بعد الإلغاء/الإكمال)، فتُقصر بقية
    // الإجراءات (تعديل الزيارة/الإلغاء) على غير النهائية كما كانت.
    const isFinalStatus = (o: OrderRecord) => o.status === 'completed' || o.status === 'cancelled';
    const handleBnplRefund = async (order: OrderRecord) => {
        const provider = order.payment_method === 'tamara' ? 'تمارا' : 'تابي';
        if (!await confirm(`هل أنت متأكد من استرداد مبلغ الطلب #${order.code || order.id.substring(0, 6).toUpperCase()} عبر ${provider}؟ لا يمكن التراجع.`)) return;
        setIsRefunding(true);
        try {
            await httpsCallable(functions, order.payment_method === 'tamara' ? 'tamaraRefundPayment' : 'tabbyRefundPayment')({
                order_id: order.id,
            });
            toast.success(`تم استرداد المبلغ عبر ${provider} بنجاح`);
        } catch (err: unknown) {
            console.error('Error refunding BNPL payment:', err);
            // رسائل الدالة الخادمية عربية أصلاً (HttpsError) — نعرضها كما هي.
            toast.error((err as { message?: string })?.message || 'تعذّر استرداد المبلغ');
        } finally {
            setIsRefunding(false);
            setActionMenuId(null);
        }
    };

    const filteredOrders = orders.filter(o =>
        o.id.toLowerCase().includes(searchTerm.toLowerCase()) ||
        o.customer.toLowerCase().includes(searchTerm.toLowerCase()) ||
        o.type.toLowerCase().includes(searchTerm.toLowerCase())
    );

    // السائقون النشطون — الدالّة الخادمية تتحقّق من التفرّغ الفعلي في الفترة.
    const availableDrivers = drivers.filter(d => d.is_active);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة الطلبات المباشرة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">متابعة حالة الطلبات وتفاصيلها لحظة بلحظة — يعرض أحدث 300 طلب</p>
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
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#660033]/20 focus:border-[#660033] transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                    <div className="flex gap-2 text-sm">
                        <button type="button" className="px-4 py-2 bg-[#FAF1F6] text-[#4D0026] font-bold rounded-lg border border-[#F2DEE9]">الكل ({orders.length})</button>
                        <button type="button" className="px-4 py-2 bg-amber-50 text-amber-700 font-bold rounded-lg border border-amber-100">انتظار ({pendingCount ?? orders.filter(o => o.status === 'pending').length})</button>
                    </div>
                </div>

                <div className="overflow-x-auto min-h-[400px]">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64">
                            <div className="animate-spin rounded-full h-10 w-10 border-4 border-[#660033] border-t-transparent"></div>
                            <p className="text-slate-500 mt-4 font-bold">جاري جلب الطلبات...</p>
                        </div>
                    ) : loadError ? (
                        // حالة خطأ صريحة لا «لا توجد طلبات» — الفراغ عند الفشل يوهم بخلو النظام.
                        <div className="flex flex-col items-center justify-center h-64 gap-4 bg-rose-50/40 m-6 rounded-2xl border border-rose-100">
                            <p className="text-rose-600 font-bold">تعذّر تحميل الطلبات — تحقّق من الاتصال أو الصلاحيات</p>
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
                                    <tr key={order.id} className="hover:bg-[#FAF1F6]/30 transition-colors group">
                                        <td className="px-6 py-4"><span className="font-bold text-slate-800">#{order.code || order.id.substring(0, 6).toUpperCase()}</span></td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#F2DEE9] to-rose-100 flex items-center justify-center text-[#4D0026] font-bold text-xs border border-[#E5C3D5]">
                                                    {order.customer.substring(0, 1)}
                                                </div>
                                                <span className="font-bold text-slate-700">{order.customer}</span>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`font-medium ${!order.driver_id ? 'text-amber-500' : 'text-slate-600'}`}>{order.driver}</span>
                                        </td>
                                        <td className="px-6 py-4 font-medium text-slate-600">
                                            {order.type}
                                            {metaSummary(order.service_meta) && (
                                                <div className="text-[11px] font-bold text-[#660033] mt-0.5">{metaSummary(order.service_meta)}</div>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 font-bold text-emerald-600">
                                            {order.amount}
                                            <PriceReviewBadge r={priceReviewOf(order as unknown as Record<string, unknown>)} />
                                        </td>
                                        <td className="px-6 py-4 font-medium text-slate-500 text-sm">{order.date}</td>
                                        <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                                        <td className="px-6 py-4 text-center relative">
                                            {/* الطلبُ الموسومُ قد يكون `completed` — وشرطُ الظهورِ كان
                                                يُخفي القائمةَ عن النهائيّ، فيَصيرُ الاعتمادُ غيرَ قابلٍ للوصول. */}
                                            {(!isFinalStatus(order) || canBnplRefund(order) ||
                                              priceReviewOf(order as unknown as Record<string, unknown>).actionable) && (
                                                <button
                                                    type="button"
                                                    title="الإجراءات"
                                                    onClick={() => setActionMenuId(actionMenuId === order.id ? null : order.id)}
                                                    className="p-2 text-slate-400 hover:text-[#660033] hover:bg-[#FAF1F6] rounded-lg transition-colors"
                                                >
                                                    <MoreVertical size={18} />
                                                </button>
                                            )}
                                            {actionMenuId === order.id && (
                                                <div ref={menuRef} className="absolute left-0 top-full mt-1 w-48 bg-white rounded-xl shadow-lg border border-slate-100 z-20 overflow-hidden">
                                                    {priceReviewOf(order as unknown as Record<string, unknown>).actionable && (
                                                        <button
                                                            type="button"
                                                            onClick={() => handleApprovePrice(order)}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-rose-700 hover:bg-rose-50 transition-colors text-right"
                                                        >
                                                            <CheckCircle2 size={16} />اعتماد المبلغ
                                                        </button>
                                                    )}
                                                    {(order.status === 'pending' || order.status === 'pending_admin_approval') && (
                                                        <button
                                                            type="button"
                                                            onClick={() => {
                                                                setAssignModal(order);
                                                                const sd = (order as OrderRecord & { service_date?: Timestamp }).service_date;
                                                                setScheduledAt(sd instanceof Timestamp ? toDatetimeLocal(sd.toDate()) : toDatetimeLocal(new Date()));
                                                                setSelectedDriverId('');
                                                                setActionMenuId(null);
                                                            }}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-slate-700 hover:bg-[#FAF1F6] hover:text-[#4D0026] transition-colors text-right"
                                                        >
                                                            <UserCheck size={16} />{order.status === 'pending_admin_approval' ? 'اعتماد وتعيين' : 'تعيين سائق'}
                                                        </button>
                                                    )}
                                                    {order.status === 'under_review' && (
                                                        <button
                                                            type="button"
                                                            onClick={() => handleAdvanceManaged(order, 'in_progress')}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-slate-700 hover:bg-[#FAF1F6] hover:text-[#4D0026] transition-colors text-right"
                                                        >
                                                            <Package size={16} />بدء التنفيذ
                                                        </button>
                                                    )}
                                                    {order.status === 'in_progress' && !order.driver_id && (
                                                        <button
                                                            type="button"
                                                            onClick={() => handleAdvanceManaged(order, 'completed')}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-slate-700 hover:bg-emerald-50 hover:text-emerald-700 transition-colors text-right"
                                                        >
                                                            <CheckCircle2 size={16} />تم التنفيذ
                                                        </button>
                                                    )}
                                                    {!isFinalStatus(order) && (
                                                        <button
                                                            type="button"
                                                            onClick={() => {
                                                                setEditModal(order);
                                                                const cur = order.service_date instanceof Timestamp
                                                                    ? toDatetimeLocal(order.service_date.toDate()) : '';
                                                                setEditScheduledAt(cur);
                                                                setEditOriginalAt(cur);
                                                                setEditDriverId(order.driver_id || '');
                                                                setActionMenuId(null);
                                                            }}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-slate-700 hover:bg-[#FAF1F6] hover:text-[#4D0026] transition-colors text-right"
                                                        >
                                                            <CalendarClock size={16} />تعديل الزيارة
                                                        </button>
                                                    )}
                                                    {canBnplRefund(order) && (
                                                        <button
                                                            type="button"
                                                            disabled={isRefunding}
                                                            onClick={() => handleBnplRefund(order)}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-rose-600 hover:bg-rose-50 transition-colors text-right disabled:opacity-50"
                                                        >
                                                            <Undo2 size={16} />{order.payment_method === 'tamara' ? 'استرداد المبلغ (تمارا)' : 'استرداد المبلغ (تابي)'}
                                                        </button>
                                                    )}
                                                    {!isFinalStatus(order) && (
                                                        <button
                                                            type="button"
                                                            disabled={isCancelling}
                                                            onClick={() => handleCancelOrder(order)}
                                                            className="w-full flex items-center gap-2 px-4 py-3 text-sm font-bold text-rose-600 hover:bg-rose-50 transition-colors text-right disabled:opacity-50"
                                                        >
                                                            <XCircle size={16} />إلغاء الطلب
                                                        </button>
                                                    )}
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
                                {metaSummary(assignModal.service_meta) && (
                                    <p className="text-xs font-bold text-[#660033] mt-1">{metaSummary(assignModal.service_meta)}</p>
                                )}
                            </div>
                            <button type="button" title="إغلاق" onClick={() => setAssignModal(null)} className="text-slate-400 hover:text-slate-600 p-2 rounded-xl hover:bg-slate-100 transition-colors">
                                <X size={20} />
                            </button>
                        </div>
                        <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
                            {/* التفصيل الكامل أمام الأدمن **وهو يختار السائق**: عدد
                                المكيفات، مقاسات الكنب، مواد التنظيف التي يجب أن
                                يحملها، وعدد عاملات المناسبة وساعاتها. */}
                            <ServiceMetaTable meta={assignModal.service_meta} />
                            {driversError ? (
                                <p className="text-center text-rose-600 font-bold py-4">تعذّر تحميل قائمة السائقين — أعد تحميل الصفحة. هذه ليست «لا سائقين»: القائمة لم تُقرأ.</p>
                            ) : availableDrivers.length === 0 ? (
                                <p className="text-center text-amber-600 font-bold py-4">لا يوجد سائقون متاحون حالياً</p>
                            ) : (
                                <div className="space-y-2">
                                    <label className="block text-sm font-extrabold text-slate-700">اختر سائقاً متاحاً</label>
                                    <select
                                        title="اختر سائقاً"
                                        value={selectedDriverId}
                                        onChange={e => setSelectedDriverId(e.target.value)}
                                        className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-[#660033] focus:ring-2 focus:ring-[#660033]/20 font-medium"
                                    >
                                        <option value="">-- اختر سائقاً --</option>
                                        {availableDrivers.map(d => (
                                            <option key={d.id} value={d.id}>{d.name}</option>
                                        ))}
                                    </select>
                                </div>
                            )}
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">موعد الخدمة</label>
                                <input
                                    type="datetime-local"
                                    title="موعد الخدمة"
                                    value={scheduledAt}
                                    onChange={e => setScheduledAt(e.target.value)}
                                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-[#660033] focus:ring-2 focus:ring-[#660033]/20 font-medium"
                                />
                            </div>
                            <div className="flex gap-3 pt-2">
                                <button type="button" onClick={() => setAssignModal(null)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button
                                    type="button"
                                    disabled={!selectedDriverId || !scheduledAt || isAssigning}
                                    onClick={handleAssignDriver}
                                    className="flex-1 px-4 py-3 bg-[#660033] text-white rounded-xl font-bold hover:bg-[#4D0026] transition-colors flex justify-center items-center disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    {isAssigning ? <Loader2 className="animate-spin" size={20} /> : 'تعيين السائق'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
            {/* Edit Visit Modal — تعديل موعد الزيارة و/أو السائق */}
            {editModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md overflow-hidden">
                        <div className="flex justify-between items-center p-6 border-b border-slate-100 bg-slate-50/50">
                            <div>
                                <h3 className="text-xl font-extrabold text-slate-800">تعديل الزيارة</h3>
                                <p className="text-sm text-slate-500 mt-0.5">الطلب #{editModal.code || editModal.id.substring(0, 6).toUpperCase()} — {editModal.customer}</p>
                                {metaSummary(editModal.service_meta) && (
                                    <p className="text-xs font-bold text-[#660033] mt-1">{metaSummary(editModal.service_meta)}</p>
                                )}
                            </div>
                            <button type="button" title="إغلاق" onClick={() => setEditModal(null)} className="text-slate-400 hover:text-slate-600 p-2 rounded-xl hover:bg-slate-100 transition-colors">
                                <X size={20} />
                            </button>
                        </div>
                        <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
                            <ServiceMetaTable meta={editModal.service_meta} />
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">موعد الزيارة الجديد</label>
                                <input
                                    type="datetime-local"
                                    title="موعد الزيارة"
                                    value={editScheduledAt}
                                    onChange={e => setEditScheduledAt(e.target.value)}
                                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-[#660033] focus:ring-2 focus:ring-[#660033]/20 font-medium"
                                />
                            </div>
                            {editModal.driver_id && ACTIVE_ASSIGNED.includes(editModal.status) && (
                                <div className="space-y-2">
                                    <label className="block text-sm font-extrabold text-slate-700">السائق (اختر آخر لإعادة الإسناد)</label>
                                    <select
                                        title="السائق"
                                        value={editDriverId}
                                        onChange={e => setEditDriverId(e.target.value)}
                                        className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-[#660033] focus:ring-2 focus:ring-[#660033]/20 font-medium"
                                    >
                                        {availableDrivers.map(d => (
                                            <option key={d.id} value={d.id}>{d.name}{d.id === editModal.driver_id ? ' (الحالي)' : ''}</option>
                                        ))}
                                    </select>
                                    <p className="text-[11px] text-slate-400 font-bold">
                                        يُفحص تفرّغ السائق في الموعد خادمياً — وعند التبديل يُحرَّر السائق السابق ويُشعَر الجديد تلقائياً.
                                    </p>
                                </div>
                            )}
                            <div className="flex gap-3 pt-2">
                                <button type="button" onClick={() => setEditModal(null)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button
                                    type="button"
                                    disabled={isEditing}
                                    onClick={handleEditVisit}
                                    className="flex-1 px-4 py-3 bg-[#660033] text-white rounded-xl font-bold hover:bg-[#4D0026] transition-colors flex justify-center items-center disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    {isEditing ? <Loader2 className="animate-spin" size={20} /> : 'حفظ التعديل'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
