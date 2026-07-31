import { useState, useEffect, useRef } from 'react';
import { Search, Filter, MoreVertical, CheckCircle2, Clock, XCircle, Package, UserCheck, X, Loader2, CalendarClock } from 'lucide-react';
import {
    collection, onSnapshot, query, orderBy, doc, Timestamp, updateDoc,
    type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

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
    service_date?: Timestamp;
    // (باقات السكن) تفصيل الباقة — يظهر تحت نوع الخدمة وفي نافذتي التعيين/التعديل.
    service_meta?: { kind?: string; homeLabel?: string; crewCount?: number; durationHours?: number };
    worker_count?: number;
    hours_contracted?: number;
}

// «شقة متوسطة • كادران • 6س» — يعرفها الأدمن قبل اختيار السائق والموعد.
const pkgSummary = (o: OrderRecord): string | null => {
    const m = o.service_meta;
    if (!m || m.kind !== 'home_package' || !m.homeLabel) return null;
    const crews = Number(m.crewCount) || 0;
    const crewsLabel = crews === 1 ? 'كادر واحد' : crews === 2 ? 'كادران' : `${crews} كوادر`;
    const dur = Number(m.durationHours) || 0;
    return `${m.homeLabel} • ${crewsLabel}${dur > 0 ? ` • ${dur}س` : ''}`;
};

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
    const [loading, setLoading] = useState(true);
    const [actionMenuId, setActionMenuId] = useState<string | null>(null);
    const [assignModal, setAssignModal] = useState<OrderRecord | null>(null);
    const [selectedDriverId, setSelectedDriverId] = useState('');
    const [scheduledAt, setScheduledAt] = useState('');
    const [isAssigning, setIsAssigning] = useState(false);
    const [isCancelling, setIsCancelling] = useState(false);
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
        const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'));
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
                    amount: `${d.amount || 0} ر.س`,
                    date: d.created_at instanceof Timestamp ? d.created_at.toDate().toLocaleDateString('ar-EG') : 'غير متاح',
                    type: d.service_type || 'خدمة عامة',
                } as OrderRecord;
            }));
            setLoading(false);
        });

        const driversUnsub = onSnapshot(collection(db, 'drivers'), (snap) => {
            setDrivers(snap.docs.map(d => ({ id: d.id, name: d.data().name || 'سائق', is_available: d.data().is_available || false, is_active: d.data().is_active !== false })));
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
                const ts = Timestamp.fromDate(new Date(editScheduledAt));
                await updateDoc(doc(db, 'orders', editModal.id), {
                    service_date: ts,
                    scheduled_at: ts,
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
            await updateDoc(doc(db, 'orders', order.id), {
                status: next,
                ...(next === 'completed' ? { completed_at: Timestamp.now() } : {}),
                updated_at: Timestamp.now(),
            });
        } catch (err) {
            console.error('Error advancing order:', err);
            toast.error('تعذّر تحديث الحالة');
        } finally {
            setActionMenuId(null);
        }
    };

    const handleCancelOrder = async (order: OrderRecord) => {
        if (!await confirm(`هل أنت متأكد من إلغاء الطلب #${order.code || order.id.substring(0, 6).toUpperCase()}؟`)) return;
        setIsCancelling(true);
        try {
            // needs_refund only for actually-paid orders; rewards_handled_by:'server'
            // lets onOrderRewards credit the wallet refund. Driver release is handled
            // server-side by freeDriverOnOrderCancel (guards on current_order_id, so it
            // won't free a driver who has since moved on to another order).
            await updateDoc(doc(db, 'orders', order.id), {
                status: 'cancelled',
                cancelled_at: Timestamp.now(),
                cancelled_by: 'admin',
                needs_refund: order.is_paid === true,
                rewards_handled_by: 'server',
            });
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

    // السائقون النشطون — الدالّة الخادمية تتحقّق من التفرّغ الفعلي في الفترة.
    const availableDrivers = drivers.filter(d => d.is_active);

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
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#660033]/20 focus:border-[#660033] transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                    <div className="flex gap-2 text-sm">
                        <button type="button" className="px-4 py-2 bg-[#FAF1F6] text-[#4D0026] font-bold rounded-lg border border-[#F2DEE9]">الكل ({orders.length})</button>
                        <button type="button" className="px-4 py-2 bg-amber-50 text-amber-700 font-bold rounded-lg border border-amber-100">انتظار ({orders.filter(o => o.status === 'pending').length})</button>
                    </div>
                </div>

                <div className="overflow-x-auto min-h-[400px]">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64">
                            <div className="animate-spin rounded-full h-10 w-10 border-4 border-[#660033] border-t-transparent"></div>
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
                                            {pkgSummary(order) && (
                                                <div className="text-[11px] font-bold text-[#660033] mt-0.5">{pkgSummary(order)}</div>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 font-bold text-emerald-600">{order.amount}</td>
                                        <td className="px-6 py-4 font-medium text-slate-500 text-sm">{order.date}</td>
                                        <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                                        <td className="px-6 py-4 text-center relative">
                                            {order.status !== 'completed' && order.status !== 'cancelled' && (
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
                                {pkgSummary(assignModal) && (
                                    <p className="text-xs font-bold text-[#660033] mt-1">{pkgSummary(assignModal)}</p>
                                )}
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
                                {pkgSummary(editModal) && (
                                    <p className="text-xs font-bold text-[#660033] mt-1">{pkgSummary(editModal)}</p>
                                )}
                            </div>
                            <button type="button" title="إغلاق" onClick={() => setEditModal(null)} className="text-slate-400 hover:text-slate-600 p-2 rounded-xl hover:bg-slate-100 transition-colors">
                                <X size={20} />
                            </button>
                        </div>
                        <div className="p-6 space-y-4">
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
