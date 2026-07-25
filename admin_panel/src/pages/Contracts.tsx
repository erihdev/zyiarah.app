import { useState, useEffect } from 'react';
import { Search, FileSignature, CheckCircle2, Clock, XCircle, AlertCircle, Calendar, CreditCard, Trash2, Info, Package, Plus, Pencil, Star, Loader2 } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp, doc, updateDoc, deleteDoc, addDoc, serverTimestamp, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

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

// (تكافؤ مع تطبيق الأدمن — admin_subscriptions_screen.dart) نفس مجموعة
// subscription_packages ونفس الحقول حرفياً: title/subtitle/price/visits/hours/
// features/isPremium/rank. كانت اللوحة تعرض العقود فقط بلا أي إدارة للباقات.
interface PackageRecord {
    id: string;
    title: string;
    subtitle?: string;
    price: number;
    visits?: number;
    hours?: number;
    features?: string[];
    isPremium?: boolean;
    rank?: number;
}

const emptyPkgForm = {
    title: '', subtitle: '', price: '', visits: '', hours: '4',
    features: '', isPremium: false,
};

const pkgInputCls = 'w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all';

function PackagesSection() {
    const { toast, confirm } = useNotification();
    const [packages, setPackages] = useState<PackageRecord[]>([]);
    const [loading, setLoading] = useState(true);
    const [showForm, setShowForm] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState(emptyPkgForm);
    const [saving, setSaving] = useState(false);

    useEffect(() => {
        const q = query(collection(db, 'subscription_packages'), orderBy('rank'));
        const unsub = onSnapshot(q, (snap: QuerySnapshot<DocumentData>) => {
            setPackages(snap.docs.map((d: QueryDocumentSnapshot<DocumentData>) => ({
                id: d.id, ...(d.data() as Omit<PackageRecord, 'id'>),
            })));
            setLoading(false);
        }, (e) => { console.error('subscription_packages listener error:', e); setLoading(false); });
        return () => unsub();
    }, []);

    const openForm = (pkg?: PackageRecord) => {
        if (pkg) {
            setEditingId(pkg.id);
            setForm({
                title: pkg.title || '', subtitle: pkg.subtitle || '',
                price: String(pkg.price ?? ''), visits: String(pkg.visits ?? ''),
                hours: String(pkg.hours ?? 4),
                features: (pkg.features || []).join('\n'),
                isPremium: pkg.isPremium === true,
            });
        } else {
            setEditingId(null);
            setForm(emptyPkgForm);
        }
        setShowForm(true);
    };

    const handleSave = async () => {
        // نفس شرط التطبيق: الاسم والسعر إلزاميان.
        if (!form.title.trim() || !form.price.trim()) {
            toast.error('يرجى إكمال البيانات الأساسية (اسم الباقة والسعر)');
            return;
        }
        setSaving(true);
        try {
            const payload = {
                title: form.title.trim(),
                subtitle: form.subtitle.trim(),
                price: parseFloat(form.price) || 0,
                visits: parseInt(form.visits) || 0,
                hours: parseInt(form.hours) || 4,
                features: form.features.split('\n').map(s => s.trim()).filter(Boolean),
                isPremium: form.isPremium,
                // نُبقي رتبة الباقة عند التعديل؛ الجديدة تُلحق بآخر الترتيب.
                rank: editingId ? (packages.find(p => p.id === editingId)?.rank ?? 0) : packages.length,
                updated_at: serverTimestamp(),
            };
            if (editingId) await updateDoc(doc(db, 'subscription_packages', editingId), payload);
            else await addDoc(collection(db, 'subscription_packages'), payload);
            toast.success(editingId ? 'تم تحديث الباقة بنجاح' : 'تمت إضافة الباقة بنجاح');
            setShowForm(false); setEditingId(null); setForm(emptyPkgForm);
        } catch (e) {
            console.error(e);
            toast.error('تعذّر حفظ الباقة — تحقق من الاتصال والصلاحيات');
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (pkg: PackageRecord) => {
        // نفس تحذير التطبيق: الحذف لا يلغي اشتراكات المشتركين الحاليين.
        if (!await confirm(`حذف باقة "${pkg.title}"؟ لن تظهر للعملاء الجدد، ولكن قد تظل نشطة للمشتركين الحاليين.`)) return;
        try {
            await deleteDoc(doc(db, 'subscription_packages', pkg.id));
            toast.success('تم حذف الباقة');
        } catch (e) {
            console.error(e);
            toast.error('حدث خطأ أثناء الحذف');
        }
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <p className="text-slate-500 font-bold text-sm">{packages.length} باقة — التطبيق يعرض هذه الباقات للعملاء مباشرةً</p>
                <button
                    type="button"
                    onClick={() => { if (showForm) { setShowForm(false); setEditingId(null); } else openForm(); }}
                    className="flex items-center gap-2 px-5 py-3 bg-rose-600 hover:bg-rose-700 text-white font-bold rounded-xl transition-all"
                >
                    <Plus size={16} />
                    {showForm ? 'إغلاق النموذج' : 'إضافة باقة'}
                </button>
            </div>

            {showForm && (
                <div className="bg-rose-50 border-2 border-rose-200 rounded-[2rem] p-6 space-y-4">
                    <h4 className="font-black text-slate-800 text-lg">{editingId ? 'تعديل الباقة' : 'بيانات الباقة الجديدة'}</h4>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div>
                            <label className="block text-xs font-bold text-slate-600 mb-1">اسم الباقة الرئيسية *</label>
                            <input type="text" dir="rtl" value={form.title}
                                onChange={e => setForm(p => ({ ...p, title: e.target.value }))}
                                placeholder="مثال: باقة النظافة الشهرية" className={pkgInputCls} />
                        </div>
                        <div>
                            <label className="block text-xs font-bold text-slate-600 mb-1">العنوان الفرعي / الوصف القصير</label>
                            <input type="text" dir="rtl" value={form.subtitle}
                                onChange={e => setForm(p => ({ ...p, subtitle: e.target.value }))}
                                placeholder="مثال: 4 زيارات شهرياً بسعر مخفّض" className={pkgInputCls} />
                        </div>
                        <div>
                            <label className="block text-xs font-bold text-slate-600 mb-1">السعر الإجمالي (ر.س) *</label>
                            <input type="number" dir="ltr" min="0" step="0.5" value={form.price}
                                onChange={e => setForm(p => ({ ...p, price: e.target.value }))}
                                className={pkgInputCls} />
                        </div>
                        <div>
                            <label className="block text-xs font-bold text-slate-600 mb-1">عدد الزيارات المشمولة</label>
                            <input type="number" dir="ltr" min="0" value={form.visits}
                                onChange={e => setForm(p => ({ ...p, visits: e.target.value }))}
                                className={pkgInputCls} />
                        </div>
                        <div>
                            <label className="block text-xs font-bold text-slate-600 mb-1">عدد الساعات لكل زيارة</label>
                            <input type="number" dir="ltr" min="1" max="8" value={form.hours}
                                onChange={e => setForm(p => ({ ...p, hours: e.target.value }))}
                                className={pkgInputCls} />
                        </div>
                        <div className="flex items-end">
                            <button
                                type="button"
                                onClick={() => setForm(p => ({ ...p, isPremium: !p.isPremium }))}
                                className={`flex items-center gap-2 px-4 py-3 rounded-xl font-bold border-2 transition-all w-full justify-center ${form.isPremium ? 'bg-amber-50 border-amber-400 text-amber-700' : 'bg-white border-slate-200 text-slate-400'}`}
                            >
                                <Star size={16} fill={form.isPremium ? 'currentColor' : 'none'} />
                                {form.isPremium ? 'باقة مميزة (Golden)' : 'باقة عادية — اضغط لتمييزها'}
                            </button>
                        </div>
                    </div>
                    <div>
                        <label className="block text-xs font-bold text-slate-600 mb-1">الميزات (كل ميزة في سطر منفصل)</label>
                        <textarea dir="rtl" rows={4} value={form.features}
                            onChange={e => setForm(p => ({ ...p, features: e.target.value }))}
                            placeholder={'زيارة أسبوعية\nتوفير 20%\nدعم فني'}
                            className={pkgInputCls} />
                    </div>
                    <div className="flex gap-3">
                        <button
                            type="button"
                            onClick={handleSave}
                            disabled={saving}
                            className="flex items-center gap-2 px-6 py-3 bg-rose-600 hover:bg-rose-700 disabled:opacity-60 text-white font-bold rounded-xl transition-all"
                        >
                            {saving ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
                            {editingId ? 'حفظ التعديلات' : 'حفظ الباقة'}
                        </button>
                        <button
                            type="button"
                            onClick={() => { setShowForm(false); setEditingId(null); }}
                            className="px-6 py-3 bg-white border border-slate-200 text-slate-600 font-bold rounded-xl hover:bg-slate-50 transition-all"
                        >
                            إلغاء
                        </button>
                    </div>
                </div>
            )}

            {loading ? (
                <div className="flex flex-col items-center justify-center h-48 bg-white rounded-[32px] border-2 border-dashed border-slate-100">
                    <div className="animate-spin rounded-full h-10 w-10 border-4 border-[#660033] border-t-transparent"></div>
                    <p className="text-slate-500 mt-4 font-black">جاري تحميل الباقات...</p>
                </div>
            ) : packages.length === 0 ? (
                <div className="flex flex-col items-center justify-center p-16 bg-white rounded-[32px] border-2 border-dashed border-slate-100">
                    <Package size={56} className="text-slate-200 mb-4" />
                    <h3 className="text-lg font-bold text-slate-800">لا توجد باقات متاحة حالياً</h3>
                    <p className="text-slate-400 mt-1 font-medium text-sm">أضف أول باقة ليراها العملاء في التطبيق</p>
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {packages.map(pkg => (
                        <div key={pkg.id}
                            className={`bg-white rounded-[28px] border-2 overflow-hidden transition-all duration-300 hover:shadow-xl ${pkg.isPremium ? 'border-amber-300' : 'border-slate-100'}`}>
                            <div className="p-6 space-y-4">
                                <div className="flex items-start justify-between gap-2">
                                    <div className="min-w-0">
                                        <h4 className="text-lg font-black text-[#660033] truncate flex items-center gap-2">
                                            {pkg.isPremium && <Star size={16} className="text-amber-400 shrink-0" fill="currentColor" />}
                                            {pkg.title}
                                        </h4>
                                        {pkg.subtitle && <p className="text-xs font-bold text-slate-400 mt-1">{pkg.subtitle}</p>}
                                    </div>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => openForm(pkg)}
                                            className="p-2.5 bg-slate-50 text-rose-500 hover:bg-rose-50 rounded-xl transition-all" title="تعديل">
                                            <Pencil size={16} />
                                        </button>
                                        <button type="button" onClick={() => handleDelete(pkg)}
                                            className="p-2.5 bg-red-50 text-red-500 hover:bg-red-100 rounded-xl transition-all" title="حذف">
                                            <Trash2 size={16} />
                                        </button>
                                    </div>
                                </div>
                                <div className="flex items-center justify-between">
                                    <span className="text-2xl font-black text-slate-800">{pkg.price} <span className="text-sm">ر.س</span></span>
                                    <div className="flex gap-2">
                                        <span className="px-3 py-1 bg-[#660033]/10 text-[#660033] text-[11px] font-bold rounded-lg">{pkg.visits || 0} زيارة</span>
                                        <span className="px-3 py-1 bg-[#660033]/10 text-[#660033] text-[11px] font-bold rounded-lg">{pkg.hours || 4} ساعات/زيارة</span>
                                    </div>
                                </div>
                                {(pkg.features || []).length > 0 && (
                                    <div className="border-t border-slate-100 pt-3 space-y-1.5">
                                        {(pkg.features || []).map((f, i) => (
                                            <div key={i} className="flex items-center gap-2 text-xs font-bold text-slate-600">
                                                <CheckCircle2 size={14} className={pkg.isPremium ? 'text-amber-400' : 'text-[#660033]'} />
                                                {f}
                                            </div>
                                        ))}
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}

const StatusBadge = ({ status }: { status: string }) => {
    switch (status) {
        case 'active':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-[10px]"><CheckCircle2 size={12} />نشط</span>;
        case 'approved_waiting_payment':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#FAF1F6] text-[#4D0026] font-bold border border-[#F2DEE9] text-[10px]"><CreditCard size={12} />بانتظار الدفع</span>;
        case 'pending':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-50 text-amber-700 font-bold border border-amber-100 text-[10px]"><Clock size={12} />قيد المراجعة</span>;
        case 'rejected':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-red-50 text-red-700 font-bold border border-red-100 text-[10px]"><XCircle size={12} />مرفوض</span>;
        default:
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-50 text-slate-700 font-bold border border-slate-200 text-[10px]">{status}</span>;
    }
};

export default function Contracts() {
    const { toast, confirm } = useNotification();
    const [activeTab, setActiveTab] = useState<'contracts' | 'packages'>('contracts');
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
        }, (e) => { console.error("Contracts listener error:", e); setLoading(false); });
        return () => unsubscribe();
    }, []);

    const handleApprove = async (id: string, planName: string, userId?: string) => {
        if (!await confirm(`هل أنت متأكد من رغبتك في اعتماد عقد (${planName})؟`)) return;
        try {
            await updateDoc(doc(db, 'contracts', id), {
                status: 'approved_waiting_payment',
                adminApprovedAt: Timestamp.now()
            });
            // إشعار العميل بإتمام الدفع — مسار تطبيق الأدمن يستدعي notifyContractApproved،
            // أما لوحة الويب فكانت تعتمد العقد بصمت ولا يصل العميل أي تنبيه. نكتب هنا في
            // نفس طابور notification_triggers (نوع غير بريدي = دفع + سجل داخل التطبيق فقط).
            if (userId) {
                await addDoc(collection(db, 'notification_triggers'), {
                    toUid: userId,
                    title: 'تمت الموافقة على طلبك بنجاح! 📄',
                    body: `تم اعتماد عقد باقة (${planName}) من قبل الإدارة. يرجى إتمام الدفع لتفعيل الباقة.`,
                    type: 'contract_approved',
                    data: { planName, deepLink: 'zyiarah://app/contracts' },
                    createdAt: serverTimestamp(),
                    processed: false,
                });
            }
            toast.success("تم اعتماد العقد بنجاح وبانتظار دفع العميل");
        } catch (error) {
            console.error(error);
            toast.error("حدث خطأ أثناء الاعتماد");
        }
    };

    const handleDelete = async (id: string) => {
        if (!await confirm("هل أنت متأكد من حذف هذا العقد نهائياً؟")) return;
        try {
            await deleteDoc(doc(db, 'contracts', id));
            toast.success("تم حذف العقد");
        } catch (error) {
            console.error(error);
            toast.error("حدث خطأ أثناء الحذف");
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
                    <div className="p-3 bg-[#660033] text-white rounded-2xl shadow-lg shadow-[#E5C3D5]">
                        <FileSignature size={28} />
                    </div>
                    <div>
                        <h2 className="text-2xl font-black text-slate-800 tracking-tight">مركز العقود الرقمية</h2>
                        <p className="text-slate-500 font-medium text-sm">إدارة واعتماد عقود الإشتراكات والخدمات المنزلية</p>
                    </div>
                </div>
            </div>

            {/* تبويب: العقود | باقات الاشتراك (إدارة الباقات كانت في التطبيق فقط) */}
            <div className="flex gap-2 bg-white p-1.5 rounded-2xl border-2 border-slate-100 w-fit">
                <button
                    type="button"
                    onClick={() => setActiveTab('contracts')}
                    className={`flex items-center gap-2 px-5 py-2.5 rounded-xl font-bold text-sm transition-all ${activeTab === 'contracts' ? 'bg-[#660033] text-white shadow-lg' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                    <FileSignature size={16} />
                    العقود
                </button>
                <button
                    type="button"
                    onClick={() => setActiveTab('packages')}
                    className={`flex items-center gap-2 px-5 py-2.5 rounded-xl font-bold text-sm transition-all ${activeTab === 'packages' ? 'bg-[#660033] text-white shadow-lg' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                    <Package size={16} />
                    باقات الاشتراك
                </button>
            </div>

            {activeTab === 'packages' && <PackagesSection />}

            {activeTab === 'contracts' && (<>
            <div className="relative group">
                <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-[#660033] transition-colors" size={20} />
                <input
                    type="text"
                    placeholder="ابحث باسم العميل، الباقة، أو رقم العقد..."
                    className="w-full pl-6 pr-12 py-4 bg-white border-2 border-slate-100 rounded-[20px] text-base outline-none focus:ring-4 focus:ring-[#660033]/10 focus:border-[#660033] transition-all font-bold text-slate-700 shadow-sm"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                />
            </div>

            {loading ? (
                <div className="flex flex-col items-center justify-center h-64 bg-white rounded-[32px] border-2 border-dashed border-slate-100">
                    <div className="animate-spin rounded-full h-12 w-12 border-4 border-[#660033] border-t-transparent shadow-md"></div>
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
                        <div key={contract.id} className="group bg-white rounded-[28px] border-2 border-slate-50 overflow-hidden hover:border-[#F2DEE9]/50 hover:shadow-2xl hover:shadow-[#FAF1F6] transition-all duration-500">
                            <div className="p-6">
                                <div className="flex items-center justify-between mb-6">
                                    <StatusBadge status={contract.status} />
                                    <div className="flex items-center gap-2 text-slate-400 text-[10px] font-bold">
                                        <Calendar size={12} />
                                        {contract.createdAt ? contract.createdAt.toDate().toLocaleDateString('ar-EG-u-nu-latn') : 'غير متوفر'}
                                    </div>
                                </div>

                                <div className="flex items-start gap-4 mb-6">
                                    <div className="p-4 bg-slate-50 text-slate-400 rounded-2xl group-hover:bg-[#660033] group-hover:text-white transition-all duration-500">
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
                                        <span className="text-sm font-black text-[#660033]">{contract.planPrice || 0} ر.س</span>
                                    </div>
                                </div>

                                <div className="flex items-center gap-3">
                                    {contract.status === 'pending' && (
                                        <button 
                                            type="button"
                                            onClick={() => handleApprove(contract.id, contract.planName, contract.userId)}
                                            className="flex-1 py-3.5 bg-[#660033] text-white text-sm font-black rounded-2xl hover:bg-[#4D0026] transition-all shadow-lg shadow-[#F2DEE9] active:scale-95"
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
            </>)}
        </div>
    );
}
