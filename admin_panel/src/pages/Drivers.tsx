import { useState, useEffect, useRef } from 'react';
import { Search, Filter, ShieldCheck, MapPin, Phone, Star, ShieldAlert, X, Loader2, ToggleLeft, ToggleRight, Pencil, Trash2, Camera, Upload } from 'lucide-react';
import { collection, onSnapshot, addDoc, updateDoc, deleteDoc, doc, serverTimestamp, query, orderBy, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { ref, uploadBytesResumable, getDownloadURL } from 'firebase/storage';
import { db, storage } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface DriverData {
    id: string;
    name: string;
    phone: string;
    vehicle: string;
    is_available: boolean;
    is_active?: boolean;
    is_suspended?: boolean;
    rating: number;
    rides: number;
    monthly_salary: number;
    photo_url?: string;
}

const StatusBadge = ({ is_available, is_suspended = false }: { is_available: boolean, is_suspended?: boolean }) => {
    if (is_suspended) return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-50 text-rose-700 font-bold border border-rose-100 text-xs"><ShieldAlert size={14} />موقوف</span>;
    if (is_available) return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-100 text-xs"><div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>متاح</span>;
    return <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 text-slate-600 font-bold border border-slate-200 text-xs"><div className="w-2 h-2 rounded-full bg-slate-400"></div>غير متصل</span>;
};

const EMPTY_EDIT = { name: '', phone: '', vehicle: '', monthly_salary: 0 };

export default function Drivers() {
    const { toast } = useNotification();
    const [searchTerm, setSearchTerm] = useState('');
    const [drivers, setDrivers] = useState<DriverData[]>([]);
    const [isAvailableCount, setIsAvailableCount] = useState(0);

    // Add
    const [isAddModalOpen, setIsAddModalOpen] = useState(false);
    const [isAdding, setIsAdding] = useState(false);
    const [newDriver, setNewDriver] = useState({ name: '', phone: '', vehicle: '', monthly_salary: 0 });

    // Edit
    const [editDriver, setEditDriver] = useState<DriverData | null>(null);
    const [editForm, setEditForm] = useState(EMPTY_EDIT);
    const [isSaving, setIsSaving] = useState(false);

    // Delete
    const [deleteTarget, setDeleteTarget] = useState<DriverData | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);

    // Photo upload
    const [uploadingPhotoFor, setUploadingPhotoFor] = useState<string | null>(null);
    const [uploadProgress, setUploadProgress] = useState(0);
    const photoInputRef = useRef<HTMLInputElement>(null);
    const addPhotoInputRef = useRef<HTMLInputElement>(null);
    const [addPhotoFile, setAddPhotoFile] = useState<File | null>(null);
    const [addPhotoPreview, setAddPhotoPreview] = useState<string | null>(null);

    // Suspension
    const [togglingId, setTogglingId] = useState<string | null>(null);

    useEffect(() => {
        const q = query(collection(db, 'drivers'), orderBy('created_at', 'desc'));
        const unsubscribe = onSnapshot(q, (snapshot: QuerySnapshot<DocumentData>) => {
            let available = 0;
            const fetched = snapshot.docs.map((d: QueryDocumentSnapshot<DocumentData>) => {
                const data = d.data();
                if (data.is_available) available++;
                return { id: d.id, name: data.name || 'غير محدد', phone: data.phone || 'غير محدد', vehicle: data.vehicle || 'غير محدد', is_available: data.is_available || false, is_suspended: data.is_suspended || false, is_active: data.is_active !== false, rating: data.rating || 5.0, rides: data.rides || 0, monthly_salary: data.monthly_salary || 0, photo_url: data.photo_url || '', ...data } as DriverData;
            });
            setDrivers(fetched);
            setIsAvailableCount(available);
        });
        return () => unsubscribe();
    }, []);

    // ── Add ──
    const handleAddDriver = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!newDriver.name || !newDriver.phone) return;
        setIsAdding(true);
        try {
            const docRef = await addDoc(collection(db, 'drivers'), {
                name: newDriver.name,
                phone: newDriver.phone,
                vehicle: newDriver.vehicle,
                is_available: false,
                is_active: true,
                is_suspended: false,
                rating: 5.0,
                rides: 0,
                monthly_salary: newDriver.monthly_salary,
                created_at: serverTimestamp(),
            });
            if (addPhotoFile) {
                await uploadPhoto(addPhotoFile, docRef.id);
            }
            toast.success('تم إضافة السائق بنجاح');
            setIsAddModalOpen(false);
            setNewDriver({ name: '', phone: '', vehicle: '', monthly_salary: 0 });
            setAddPhotoFile(null);
            setAddPhotoPreview(null);
        } catch (err) {
            console.error(err);
            toast.error('حدث خطأ أثناء إضافة السائق');
        } finally {
            setIsAdding(false);
        }
    };

    // ── Edit ──
    const openEdit = (driver: DriverData) => {
        setEditDriver(driver);
        setEditForm({ name: driver.name, phone: driver.phone, vehicle: driver.vehicle, monthly_salary: driver.monthly_salary });
    };

    const handleSaveEdit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!editDriver) return;
        setIsSaving(true);
        try {
            await updateDoc(doc(db, 'drivers', editDriver.id), {
                name: editForm.name,
                phone: editForm.phone,
                vehicle: editForm.vehicle,
                monthly_salary: editForm.monthly_salary,
            });
            toast.success('تم حفظ التعديلات');
            setEditDriver(null);
        } catch (err) {
            console.error(err);
            toast.error('حدث خطأ أثناء الحفظ');
        } finally {
            setIsSaving(false);
        }
    };

    // ── Delete ──
    const handleDelete = async () => {
        if (!deleteTarget) return;
        setIsDeleting(true);
        try {
            await deleteDoc(doc(db, 'drivers', deleteTarget.id));
            toast.success(`تم حذف السائق ${deleteTarget.name}`);
            setDeleteTarget(null);
        } catch (err) {
            console.error(err);
            toast.error('حدث خطأ أثناء الحذف');
        } finally {
            setIsDeleting(false);
        }
    };

    // ── Photo upload ──
    const uploadPhoto = (file: File, driverId: string): Promise<string> => {
        return new Promise((resolve, reject) => {
            const storageRef = ref(storage, `drivers/${driverId}/photo.jpg`);
            const task = uploadBytesResumable(storageRef, file);
            task.on('state_changed',
                (snap) => setUploadProgress(Math.round(snap.bytesTransferred / snap.totalBytes * 100)),
                reject,
                async () => {
                    const url = await getDownloadURL(task.snapshot.ref);
                    await updateDoc(doc(db, 'drivers', driverId), { photo_url: url });
                    setUploadProgress(0);
                    resolve(url);
                }
            );
        });
    };

    const handlePhotoChange = async (e: React.ChangeEvent<HTMLInputElement>, driverId: string) => {
        const file = e.target.files?.[0];
        if (!file) return;
        setUploadingPhotoFor(driverId);
        try {
            await uploadPhoto(file, driverId);
            toast.success('تم تحديث صورة السائق');
        } catch (err) {
            console.error(err);
            toast.error('فشل رفع الصورة');
        } finally {
            setUploadingPhotoFor(null);
            e.target.value = '';
        }
    };

    const handleAddPhotoSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        setAddPhotoFile(file);
        setAddPhotoPreview(URL.createObjectURL(file));
    };

    // ── Suspension ──
    const handleToggleSuspension = async (driver: DriverData) => {
        setTogglingId(driver.id);
        try {
            const nowSuspended = !driver.is_suspended;
            await updateDoc(doc(db, 'drivers', driver.id), { is_suspended: nowSuspended, is_available: nowSuspended ? false : driver.is_available, is_active: !nowSuspended });
        } catch (err) {
            console.error(err);
            toast.error('حدث خطأ أثناء تعديل حالة السائق');
        } finally {
            setTogglingId(null);
        }
    };

    const filteredDrivers = drivers.filter(d =>
        d.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        d.phone.includes(searchTerm) ||
        d.id.includes(searchTerm)
    );

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة السائقين</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">تتبع أداء السائقين، الحالات، وإدارة الحسابات المالية</p>
                </div>
                <div className="flex items-center gap-3">
                    <button type="button" className="flex items-center gap-2 px-4 py-2.5 bg-white border border-slate-200 text-slate-700 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm"><Filter size={18} />تصفية</button>
                    <button type="button" onClick={() => setIsAddModalOpen(true)} className="px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-teal-600 text-white rounded-xl font-bold hover:from-emerald-600 hover:to-teal-700 transition-all shadow-lg shadow-emerald-500/20 hover:shadow-xl hover:-translate-y-0.5">إضافة سائق +</button>
                </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6 mb-8">
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-blue-200 transition-colors">
                    <div><p className="text-sm font-bold text-slate-500 mb-1">إجمالي السائقين</p><h3 className="text-3xl font-extrabold text-slate-800">{drivers.length}</h3></div>
                    <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform"><ShieldCheck size={24} /></div>
                </div>
                <div className="bg-white p-6 rounded-[20px] shadow-sm border border-slate-100/60 flex items-center justify-between group hover:border-emerald-200 transition-colors">
                    <div><p className="text-sm font-bold text-slate-500 mb-1">المتاحين حالياً</p><h3 className="text-3xl font-extrabold text-slate-800">{isAvailableCount}</h3></div>
                    <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform"><MapPin size={24} /></div>
                </div>
            </div>

            {/* Driver cards */}
            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-50/50">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input type="text" placeholder="ابحث بالاسم، رقم الجوال..." className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all text-slate-700" value={searchTerm} onChange={e => setSearchTerm(e.target.value)} />
                    </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6 p-6 bg-slate-50/30">
                    {filteredDrivers.length === 0 ? (
                        <div className="col-span-full py-12 text-center text-slate-500 font-bold">لا يوجد سائقين مطابقين للبحث.</div>
                    ) : filteredDrivers.map(driver => (
                        <div key={driver.id} className="bg-white rounded-2xl border border-slate-100 shadow-sm hover:shadow-md transition-shadow p-5 relative overflow-hidden group">
                            <div className="absolute top-0 right-0 w-32 h-32 bg-slate-50 rounded-bl-full -z-10 group-hover:bg-blue-50/50 transition-colors duration-500"></div>

                            <div className="flex justify-between items-start mb-4">
                                {/* Photo with upload trigger */}
                                <div className="flex items-center gap-3">
                                    <div className="relative">
                                        <div className="w-12 h-12 rounded-xl bg-slate-100 overflow-hidden border border-slate-200 flex items-center justify-center">
                                            {driver.photo_url
                                                ? <img src={driver.photo_url} alt={driver.name} className="w-full h-full object-cover" />
                                                : <span className="text-slate-400 font-bold text-lg">{driver.name.substring(0, 1)}</span>
                                            }
                                        </div>
                                        <button
                                            type="button"
                                            title="تغيير الصورة"
                                            onClick={() => { setUploadingPhotoFor(driver.id); photoInputRef.current?.click(); }}
                                            className="absolute -bottom-1 -left-1 w-5 h-5 bg-emerald-500 text-white rounded-full flex items-center justify-center hover:bg-emerald-600 transition-colors shadow"
                                        >
                                            {uploadingPhotoFor === driver.id ? <Loader2 size={10} className="animate-spin" /> : <Camera size={10} />}
                                        </button>
                                    </div>
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-lg">{driver.name}</h4>
                                        <span className="text-slate-400 text-xs font-bold font-mono">#{driver.id.substring(0, 6).toUpperCase()}</span>
                                    </div>
                                </div>
                                <StatusBadge is_available={driver.is_available} is_suspended={driver.is_suspended} />
                            </div>

                            <div className="space-y-3 mb-6">
                                <div className="flex items-center gap-2 text-sm text-slate-600 font-medium"><Phone size={16} className="text-slate-400" /><span dir="ltr">{driver.phone}</span></div>
                                <div className="flex items-center gap-2 text-sm text-slate-600 font-medium"><span className="text-slate-400 font-bold">المركبة:</span><span>{driver.vehicle}</span></div>
                            </div>

                            <div className="grid grid-cols-3 gap-2 border-t border-slate-100 pt-4 mb-4">
                                <div className="text-center"><span className="block text-xs font-bold text-slate-400 mb-1">التقييم</span><div className="flex items-center justify-center gap-1 font-bold text-slate-700">{driver.rating} <Star size={14} className="text-amber-400 fill-amber-400" /></div></div>
                                <div className="text-center border-r border-slate-100"><span className="block text-xs font-bold text-slate-400 mb-1">الخدمات</span><span className="font-bold text-slate-700">{driver.rides}</span></div>
                                <div className="text-center border-r border-slate-100"><span className="block text-xs font-bold text-slate-400 mb-1">الراتب</span><span className="font-bold text-emerald-600">{driver.monthly_salary} ر.س</span></div>
                            </div>

                            {/* Action buttons */}
                            <div className="flex gap-2">
                                <button type="button" onClick={() => openEdit(driver)} className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-sm font-bold border border-blue-200 text-blue-600 hover:bg-blue-50 transition-colors"><Pencil size={14} />تعديل</button>
                                <button type="button" disabled={togglingId === driver.id} onClick={() => handleToggleSuspension(driver)} className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-sm font-bold border transition-colors disabled:opacity-50 ${driver.is_suspended ? 'border-emerald-200 text-emerald-700 hover:bg-emerald-50' : 'border-amber-200 text-amber-600 hover:bg-amber-50'}`}>
                                    {togglingId === driver.id ? <Loader2 size={14} className="animate-spin" /> : driver.is_suspended ? <><ToggleRight size={14} />تفعيل</> : <><ToggleLeft size={14} />إيقاف</>}
                                </button>
                                <button type="button" onClick={() => setDeleteTarget(driver)} className="px-3 py-2 rounded-xl border border-rose-200 text-rose-500 hover:bg-rose-50 transition-colors"><Trash2 size={14} /></button>
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {/* Hidden photo input (for existing drivers) */}
            <input
                ref={photoInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={e => {
                    if (uploadingPhotoFor) handlePhotoChange(e, uploadingPhotoFor);
                }}
            />

            {/* Upload progress bar */}
            {uploadProgress > 0 && uploadProgress < 100 && (
                <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-slate-800 text-white px-6 py-3 rounded-2xl shadow-2xl flex items-center gap-3 z-50">
                    <Upload size={16} className="animate-bounce" />
                    <span className="text-sm font-bold">جاري رفع الصورة... {uploadProgress}%</span>
                </div>
            )}

            {/* ── Add Modal ── */}
            {isAddModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md overflow-hidden animate-in zoom-in-95 duration-200 max-h-[90vh] overflow-y-auto">
                        <div className="flex justify-between items-center p-6 border-b border-slate-100 bg-slate-50/50 sticky top-0">
                            <h3 className="text-xl font-extrabold text-slate-800">إضافة سائق جديد</h3>
                            <button type="button" title="إغلاق" onClick={() => { setIsAddModalOpen(false); setAddPhotoFile(null); setAddPhotoPreview(null); }} className="text-slate-400 hover:text-slate-600 hover:bg-slate-100 p-2 rounded-xl transition-colors"><X size={20} /></button>
                        </div>
                        <form onSubmit={handleAddDriver} className="p-6 space-y-5">
                            {/* Photo picker */}
                            <div className="flex flex-col items-center gap-3">
                                <div className="w-20 h-20 rounded-2xl bg-slate-100 border-2 border-dashed border-slate-300 overflow-hidden flex items-center justify-center cursor-pointer hover:border-emerald-400 transition-colors" onClick={() => addPhotoInputRef.current?.click()}>
                                    {addPhotoPreview
                                        ? <img src={addPhotoPreview} alt="preview" className="w-full h-full object-cover" />
                                        : <Camera size={28} className="text-slate-400" />
                                    }
                                </div>
                                <button type="button" onClick={() => addPhotoInputRef.current?.click()} className="text-xs text-emerald-600 font-bold hover:underline">
                                    {addPhotoFile ? 'تغيير الصورة' : 'إضافة صورة (اختياري)'}
                                </button>
                                <input ref={addPhotoInputRef} type="file" accept="image/*" className="hidden" onChange={handleAddPhotoSelect} />
                            </div>

                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">اسم السائق الكامل</label>
                                <input type="text" required placeholder="مثال: أحمد محمد" value={newDriver.name} onChange={e => setNewDriver({ ...newDriver, name: e.target.value })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium" />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">رقم الجوال</label>
                                <div className="relative">
                                    <Phone className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                                    <input type="tel" required placeholder="+966 5X XXX XXXX" value={newDriver.phone} onChange={e => setNewDriver({ ...newDriver, phone: e.target.value })} className="w-full pl-4 pr-11 py-3 bg-slate-50 border border-slate-200 rounded-xl outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium" dir="ltr" />
                                </div>
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">بيانات المركبة (اختياري)</label>
                                <input type="text" placeholder="مثال: تويوتا كامري 2023 - أ ب ج ١٢٣٤" value={newDriver.vehicle} onChange={e => setNewDriver({ ...newDriver, vehicle: e.target.value })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium" />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">الراتب الشهري (ر.س)</label>
                                <input type="number" aria-label="الراتب الشهري" min="0" placeholder="مثال: 3000" value={newDriver.monthly_salary || ''} onChange={e => setNewDriver({ ...newDriver, monthly_salary: Number(e.target.value) })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all font-medium" dir="ltr" />
                            </div>
                            <div className="pt-2 flex gap-3">
                                <button type="button" onClick={() => { setIsAddModalOpen(false); setAddPhotoFile(null); setAddPhotoPreview(null); }} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button disabled={isAdding} type="submit" className="flex-1 px-4 py-3 bg-emerald-600 text-white rounded-xl font-bold hover:bg-emerald-700 transition-colors flex justify-center items-center disabled:opacity-70 disabled:cursor-not-allowed">
                                    {isAdding ? <Loader2 className="animate-spin" size={20} /> : 'اعتماد وإضافة'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* ── Edit Modal ── */}
            {editDriver && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md overflow-hidden animate-in zoom-in-95 duration-200">
                        <div className="flex justify-between items-center p-6 border-b border-slate-100 bg-slate-50/50">
                            <h3 className="text-xl font-extrabold text-slate-800">تعديل بيانات السائق</h3>
                            <button type="button" title="إغلاق" onClick={() => setEditDriver(null)} className="text-slate-400 hover:text-slate-600 hover:bg-slate-100 p-2 rounded-xl transition-colors"><X size={20} /></button>
                        </div>
                        <form onSubmit={handleSaveEdit} className="p-6 space-y-5">
                            {/* Photo in edit */}
                            <div className="flex flex-col items-center gap-3">
                                <div className="relative">
                                    <div className="w-20 h-20 rounded-2xl bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center">
                                        {editDriver.photo_url
                                            ? <img src={editDriver.photo_url} alt={editDriver.name} className="w-full h-full object-cover" />
                                            : <span className="text-slate-400 font-bold text-2xl">{editDriver.name.substring(0, 1)}</span>
                                        }
                                    </div>
                                    <button
                                        type="button"
                                        title="تغيير الصورة"
                                        onClick={() => { setUploadingPhotoFor(editDriver.id); photoInputRef.current?.click(); }}
                                        className="absolute -bottom-1 -left-1 w-6 h-6 bg-emerald-500 text-white rounded-full flex items-center justify-center hover:bg-emerald-600 transition-colors shadow"
                                    >
                                        {uploadingPhotoFor === editDriver.id ? <Loader2 size={12} className="animate-spin" /> : <Camera size={12} />}
                                    </button>
                                </div>
                                <span className="text-xs text-slate-400">اضغط على الكاميرا لتغيير الصورة</span>
                            </div>

                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">الاسم الكامل</label>
                                <input type="text" required value={editForm.name} onChange={e => setEditForm({ ...editForm, name: e.target.value })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all font-medium" />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">رقم الجوال</label>
                                <input type="tel" required value={editForm.phone} onChange={e => setEditForm({ ...editForm, phone: e.target.value })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all font-medium" dir="ltr" />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">بيانات المركبة</label>
                                <input type="text" value={editForm.vehicle} onChange={e => setEditForm({ ...editForm, vehicle: e.target.value })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all font-medium" />
                            </div>
                            <div className="space-y-2">
                                <label className="block text-sm font-extrabold text-slate-700">الراتب الشهري (ر.س)</label>
                                <input type="number" aria-label="الراتب الشهري" min="0" value={editForm.monthly_salary || ''} onChange={e => setEditForm({ ...editForm, monthly_salary: Number(e.target.value) })} className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all font-medium" dir="ltr" />
                            </div>
                            <div className="pt-2 flex gap-3">
                                <button type="button" onClick={() => setEditDriver(null)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                                <button disabled={isSaving} type="submit" className="flex-1 px-4 py-3 bg-blue-600 text-white rounded-xl font-bold hover:bg-blue-700 transition-colors flex justify-center items-center disabled:opacity-70">
                                    {isSaving ? <Loader2 className="animate-spin" size={20} /> : 'حفظ التعديلات'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* ── Delete Confirmation ── */}
            {deleteTarget && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-sm p-8 text-center animate-in zoom-in-95 duration-200">
                        <div className="w-16 h-16 bg-rose-100 rounded-full flex items-center justify-center mx-auto mb-5">
                            <Trash2 size={28} className="text-rose-500" />
                        </div>
                        <h3 className="text-xl font-extrabold text-slate-800 mb-2">حذف السائق</h3>
                        <p className="text-slate-500 text-sm mb-6">هل أنت متأكد من حذف <span className="font-bold text-slate-700">{deleteTarget.name}</span>؟ لا يمكن التراجع عن هذا الإجراء.</p>
                        <div className="flex gap-3">
                            <button type="button" onClick={() => setDeleteTarget(null)} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50 transition-colors">إلغاء</button>
                            <button type="button" disabled={isDeleting} onClick={handleDelete} className="flex-1 px-4 py-3 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 transition-colors flex justify-center items-center disabled:opacity-70">
                                {isDeleting ? <Loader2 className="animate-spin" size={20} /> : 'تأكيد الحذف'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
