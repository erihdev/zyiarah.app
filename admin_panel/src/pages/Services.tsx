import { useState, useEffect } from 'react';
import {
    Plus,
    Edit2,
    Trash2,
    Eye,
    EyeOff,
    Save,
    Settings,
    LayoutGrid,
    Loader2,
    Sparkles,
    Compass,
    DollarSign,
    X,
    ArrowUp10
} from 'lucide-react';
import {
    collection,
    getDocs,
    doc,
    getDoc,
    setDoc,
    addDoc,
    updateDoc,
    deleteDoc,
    query,
    orderBy
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';

interface AppService {
    id: string;
    title: string;
    subtitle: string;
    price_text: string;
    base_price: number;
    is_active: boolean;
    icon_name: string;
    image_path?: string;
    route_name: string;
    order_index: number;
}

interface SofaRugPricing {
    sofa_price_inside: number;
    sofa_price_outside: number;
    rug_price_inside: number;
    rug_price_outside: number;
    outside_deposit: number;
}

export default function Services() {
    const { toast, confirm } = useNotification();
    const [services, setServices] = useState<AppService[]>([]);
    const [pricing, setPricing] = useState<SofaRugPricing>({
        sofa_price_inside: 35,
        sofa_price_outside: 39,
        rug_price_inside: 15,
        rug_price_outside: 17,
        outside_deposit: 50
    });
    const [isLoading, setIsLoading] = useState(true);
    // يمنع حفظ الأسعار فوق الإنتاج بالقيم الافتراضية بعد قراءة فاشلة.
    const [pricingLoadFailed, setPricingLoadFailed] = useState(false);
    const [isSavingPricing, setIsSavingPricing] = useState(false);
    const [isAddingService, setIsAddingService] = useState(false);
    const [editingService, setEditingService] = useState<AppService | null>(null);

    const emptyForm = { title: '', subtitle: '', price_text: '', base_price: 0, route_name: '', icon_name: '', image_path: '', order_index: 0 };
    const [formData, setFormData] = useState(emptyForm);

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        setIsLoading(true);
        try {
            const bQuery = query(collection(db, 'services'), orderBy('order_index'));
            const bSnap = await getDocs(bQuery);
            const bList = bSnap.docs.map(doc => ({ id: doc.id, ...doc.data() } as AppService));
            setServices(bList);

            const configRef = doc(db, 'system_configs', 'main_settings');
            const configSnap = await getDoc(configRef);
            if (configSnap.exists()) {
                const data = configSnap.data();
                setPricing({
                    sofa_price_inside: data.sofa_price_inside ?? 35,
                    sofa_price_outside: data.sofa_price_outside ?? 39,
                    rug_price_inside: data.rug_price_inside ?? 15,
                    rug_price_outside: data.rug_price_outside ?? 17,
                    outside_deposit: data.outside_deposit ?? 50
                });
            }
        } catch (error) {
            console.error("Error fetching data:", error);
            setPricingLoadFailed(true);
        } finally {
            setIsLoading(false);
        }
    };

    const handleToggleService = async (service: AppService) => {
        try {
            const ref = doc(db, 'services', service.id);
            await updateDoc(ref, { is_active: !service.is_active });
            setServices(prev => prev.map(s => s.id === service.id ? { ...s, is_active: !s.is_active } : s));
            toast.success(service.is_active ? "تم إخفاء الخدمة بنجاح" : "تم تنشيط الخدمة بنجاح");
        } catch {
            toast.error("حدث خطأ أثناء تحديث الخدمة");
        }
    };

    const handleDeleteService = async (id: string) => {
        if (!await confirm("هل أنت متأكد من حذف هذه الخدمة نهائياً؟")) return;
        try {
            await deleteDoc(doc(db, 'services', id));
            setServices(prev => prev.filter(s => s.id !== id));
            toast.success("تم حذف الخدمة بنجاح");
        } catch {
            toast.error("حدث خطأ أثناء الحذف");
        }
    };

    const handleSavePricing = async () => {
        if (pricingLoadFailed) {
            toast.error('تعذّر تحميل الأسعار الحالية — لا يمكن الحفظ فوقها بقيم افتراضية. أعد تحميل الصفحة.');
            return;
        }
        setIsSavingPricing(true);
        try {
            const docRef = doc(db, 'system_configs', 'main_settings');
            await setDoc(docRef, pricing, { merge: true });
            toast.success("تم حفظ أسعار الأمتار وعربون الخارج بنجاح");
        } catch {
            toast.error("حدث خطأ أثناء الحفظ");
        } finally {
            setIsSavingPricing(false);
        }
    };

    const openAddModal = () => {
        setFormData(emptyForm);
        setEditingService(null);
        setIsAddingService(true);
    };

    const openEditModal = (service: AppService) => {
        setFormData({
            title: service.title,
            subtitle: service.subtitle,
            price_text: service.price_text,
            base_price: service.base_price,
            route_name: service.route_name,
            icon_name: service.icon_name,
            image_path: service.image_path ?? '',
            order_index: service.order_index,
        });
        setEditingService(service);
        setIsAddingService(true);
    };

    const handleSaveService = async (e: React.FormEvent) => {
        e.preventDefault();
        const data = {
            title: formData.title,
            subtitle: formData.subtitle,
            price_text: formData.price_text,
            base_price: formData.base_price,
            is_active: editingService ? editingService.is_active : true,
            icon_name: formData.icon_name,
            image_path: formData.image_path,
            route_name: formData.route_name,
            order_index: formData.order_index,
        };

        try {
            if (editingService) {
                await updateDoc(doc(db, 'services', editingService.id), data);
                toast.success("تم تحديث الخدمة بنجاح");
            } else {
                await addDoc(collection(db, 'services'), data);
                toast.success("تم إنشاء الخدمة بنجاح");
            }
            setIsAddingService(false);
            setEditingService(null);
            fetchData();
        } catch {
            toast.error("حدث خطأ أثناء حفظ الخدمة");
        }
    };

    if (isLoading) {
        return (
            <div className="flex flex-col items-center justify-center h-[60vh] space-y-4">
                <Loader2 className="animate-spin text-[#5D1B5E]" size={48} />
                <span className="text-slate-500 font-bold font-tajawal animate-pulse">جاري تحميل الخدمات والتسعير...</span>
            </div>
        );
    }

    return (
        <div className="space-y-10 animate-in fade-in duration-500 pb-20 font-tajawal rtl">
            {/* Header Card with Premium Gradient Backdrop */}
            <div className="relative overflow-hidden bg-gradient-to-r from-[#5D1B5E] via-[#7B2E7C] to-[#3a0f3b] rounded-[36px] p-8 md:p-10 text-white shadow-xl shadow-purple-950/15 border border-purple-800/20">
                <div className="absolute top-0 right-0 -mt-10 -mr-10 w-40 h-40 bg-white/5 rounded-full blur-2xl pointer-events-none" />
                <div className="absolute bottom-0 left-0 -mb-10 -ml-10 w-48 h-48 bg-purple-500/10 rounded-full blur-3xl pointer-events-none" />
                
                <div className="relative flex flex-col md:flex-row md:items-center justify-between gap-6">
                    <div className="space-y-3">
                        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white/10 backdrop-blur-md text-purple-200 text-xs font-bold border border-white/10">
                            <Sparkles size={14} className="text-yellow-400 animate-pulse" />
                            <span>بوابة لوحة التحكم الفاخرة</span>
                        </div>
                        <h2 className="text-3xl md:text-4xl font-black tracking-tight leading-tight">إدارة الخدمات والتسعير الذكي</h2>
                        <p className="text-purple-100/90 font-medium text-sm md:text-base max-w-xl leading-relaxed">
                            قم بضبط خدمات تطبيق العملاء وتخصيص تسعيرة الأمتار وعربون الخدمة الخارجية بكل سهولة وبث مباشر.
                        </p>
                    </div>
                    <button
                        type="button"
                        onClick={openAddModal}
                        className="self-start md:self-auto flex items-center justify-center gap-3 bg-white text-[#5D1B5E] hover:bg-purple-50 active:scale-95 px-7 py-4 rounded-[22px] font-black transition-all shadow-lg shadow-purple-950/20 text-base"
                    >
                        <Plus size={20} className="stroke-[3]" />
                        <span>إضافة خدمة جديدة</span>
                    </button>
                </div>
            </div>

            {/* Special Sofa & Rug Meter Pricing with Elegant Glassmorphic Container */}
            <section className="relative bg-white/80 backdrop-blur-xl rounded-[36px] p-8 shadow-xl shadow-slate-100/60 border border-slate-100/80 overflow-hidden">
                <div className="absolute top-0 right-0 w-24 h-24 bg-[#5D1B5E]/2 rounded-bl-full pointer-events-none" />
                
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-8">
                    <div className="flex items-center gap-4">
                        <div className="p-4 bg-gradient-to-tr from-[#5D1B5E]/10 to-[#7B2E7C]/5 rounded-2xl text-[#5D1B5E] border border-purple-50">
                            <Settings size={26} className="animate-spin-slow text-[#5D1B5E]" />
                        </div>
                        <div>
                            <h3 className="text-xl font-black text-slate-800">تسعير خدمات الأمتار (الكنب والزل)</h3>
                            <p className="text-sm text-slate-400 font-medium mt-0.5">تحديث تلقائي وفوري ينعكس على شاشات التطبيق لخدمات الغسيل بالمتار.</p>
                        </div>
                    </div>
                    
                    <span className="self-start sm:self-auto px-4 py-1.5 rounded-full bg-amber-50 text-amber-700 text-xs font-extrabold border border-amber-100">
                        مزامنة حية
                    </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-6">
                    <PriceInput 
                        label="كنب (داخل النطاق)" 
                        value={pricing.sofa_price_inside} 
                        onChange={v => setPricing({...pricing, sofa_price_inside: v})} 
                        subLabel="سعر المتر"
                    />
                    <PriceInput 
                        label="كنب (خارج النطاق)" 
                        value={pricing.sofa_price_outside} 
                        onChange={v => setPricing({...pricing, sofa_price_outside: v})} 
                        subLabel="سعر المتر"
                    />
                    <PriceInput 
                        label="زل (داخل النطاق)" 
                        value={pricing.rug_price_inside} 
                        onChange={v => setPricing({...pricing, rug_price_inside: v})} 
                        subLabel="سعر المتر"
                    />
                    <PriceInput 
                        label="زل (خارج النطاق)" 
                        value={pricing.rug_price_outside} 
                        onChange={v => setPricing({...pricing, rug_price_outside: v})} 
                        subLabel="سعر المتر"
                    />
                    <PriceInput 
                        label="عربون النطاق الخارجي" 
                        value={pricing.outside_deposit} 
                        onChange={v => setPricing({...pricing, outside_deposit: v})} 
                        subLabel="دفعة مقدمة"
                        highlighted
                    />
                </div>

                <div className="mt-8 pt-6 border-t border-slate-100/80 flex justify-end">
                    <button
                        type="button"
                        onClick={handleSavePricing}
                        disabled={isSavingPricing}
                        className="flex items-center gap-3 px-8 py-4 bg-[#5D1B5E] text-white rounded-2xl font-black hover:bg-[#4E144F] active:scale-95 transition-all shadow-lg shadow-purple-900/10 disabled:opacity-50"
                    >
                        {isSavingPricing ? <Loader2 className="animate-spin" size={20} /> : <Save size={20} />}
                        <span>حفظ أسعار الأمتار والعربون</span>
                    </button>
                </div>
            </section>

            {/* List of Services Header */}
            <div className="flex items-center gap-3">
                <div className="w-2.5 h-7 rounded-full bg-[#5D1B5E]" />
                <h3 className="text-2xl font-black text-slate-800">قائمة الخدمات النشطة بالتطبيق</h3>
                <span className="mr-2 px-3 py-1 rounded-full bg-purple-50 text-[#5D1B5E] text-xs font-black">
                    {services.length} خدمات
                </span>
            </div>

            {/* Premium Services Grid */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                {services.map(service => (
                    <div 
                        key={service.id} 
                        className={`group relative bg-white rounded-[32px] p-8 border transition-all duration-300 hover:shadow-2xl hover:shadow-purple-900/5 hover:-translate-y-1.5 ${
                            !service.is_active 
                                ? 'opacity-70 border-slate-100 bg-slate-50/50' 
                                : 'border-slate-100/90 shadow-md shadow-slate-100/30'
                        }`}
                    >
                        {/* Decorative glow hover */}
                        <div className="absolute inset-0 rounded-[32px] border-2 border-transparent group-hover:border-[#5D1B5E]/5 transition-colors pointer-events-none" />

                        <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-6 mb-6">
                            <div className="flex items-center gap-5">
                                <div className={`p-5 rounded-2xl transition-all duration-300 ${
                                    service.is_active 
                                        ? 'bg-purple-50 text-[#5D1B5E] group-hover:scale-110 group-hover:bg-[#5D1B5E] group-hover:text-white' 
                                        : 'bg-slate-100 text-slate-400'
                                }`}>
                                    <LayoutGrid size={32} className="stroke-[1.5]" />
                                </div>
                                <div className="space-y-1">
                                    <div className="flex items-center gap-2">
                                        <h4 className="text-2xl font-black text-slate-800">{service.title}</h4>
                                        {!service.is_active && (
                                            <span className="px-2 py-0.5 rounded-md bg-slate-200 text-slate-600 text-[10px] font-black">مخفية</span>
                                        )}
                                    </div>
                                    <p className="text-slate-400 text-sm font-medium leading-relaxed">{service.subtitle}</p>
                                </div>
                            </div>
                            
                            {/* Action Buttons with Sleek Hover Profiles */}
                            <div className="flex items-center gap-2 self-end sm:self-start">
                                <button
                                    type="button"
                                    onClick={() => handleToggleService(service)}
                                    title={service.is_active ? "إخفاء الخدمة في التطبيق" : "إظهار الخدمة في التطبيق"}
                                    aria-label={service.is_active ? "Hide service" : "Show service"}
                                    className={`p-3 rounded-xl transition-all duration-200 active:scale-90 ${
                                        service.is_active 
                                            ? 'bg-emerald-50 text-emerald-600 hover:bg-emerald-100' 
                                            : 'bg-slate-100 text-slate-400 hover:bg-slate-200'
                                    }`}
                                >
                                    {service.is_active ? <Eye size={18} /> : <EyeOff size={18} />}
                                </button>
                                <button
                                    type="button"
                                    onClick={() => openEditModal(service)}
                                    title="تعديل تفاصيل الخدمة"
                                    aria-label="Edit service"
                                    className="p-3 bg-purple-50 text-[#5D1B5E] hover:bg-purple-100 rounded-xl transition-all duration-200 active:scale-90"
                                >
                                    <Edit2 size={18} />
                                </button>
                                <button 
                                    type="button"
                                    onClick={() => handleDeleteService(service.id)}
                                    title="حذف الخدمة نهائياً"
                                    aria-label="Delete service"
                                    className="p-3 bg-rose-50 text-rose-600 hover:bg-rose-100 rounded-xl transition-all duration-200 active:scale-90"
                                >
                                    <Trash2 size={18} />
                                </button>
                            </div>
                        </div>

                        {/* Beautiful Dashboard Metadata Grid */}
                        <div className="grid grid-cols-3 gap-4 p-5 bg-slate-50/80 rounded-[22px] border border-slate-100/50">
                            <div className="space-y-1">
                                <div className="flex items-center gap-1.5 text-slate-400">
                                    <DollarSign size={13} className="text-slate-400" />
                                    <span className="block text-[11px] font-bold tracking-wide uppercase">السعر المعروض</span>
                                </div>
                                <span className="text-sm font-extrabold text-slate-700">{service.price_text}</span>
                            </div>
                            <div className="space-y-1">
                                <div className="flex items-center gap-1.5 text-slate-400">
                                    <Compass size={13} className="text-slate-400" />
                                    <span className="block text-[11px] font-bold tracking-wide uppercase">الرابط البرمجي</span>
                                </div>
                                <span className="inline-flex text-[12px] font-mono font-extrabold text-[#5D1B5E] bg-purple-50 px-2.5 py-0.5 rounded-lg border border-purple-100/30">
                                    {service.route_name}
                                </span>
                            </div>
                            <div className="space-y-1">
                                <div className="flex items-center gap-1.5 text-slate-400">
                                    <ArrowUp10 size={13} className="text-slate-400" />
                                    <span className="block text-[11px] font-bold tracking-wide uppercase">ترتيب العرض</span>
                                </div>
                                <span className="text-sm font-extrabold text-slate-700">#{service.order_index}</span>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Modal for Add/Edit using Premium Glassmorphic Overlay */}
            {isAddingService && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-purple-950/20 backdrop-blur-md animate-in fade-in duration-300">
                    <div className="relative bg-white rounded-[40px] w-full max-w-2xl shadow-2xl shadow-purple-950/20 overflow-hidden border border-slate-100 animate-in slide-in-from-bottom duration-300">
                        {/* Top Gradient Banner in Modal */}
                        <div className="bg-gradient-to-r from-[#5D1B5E] to-[#7B2E7C] p-8 text-white flex items-center justify-between">
                            <div className="space-y-1.5">
                                <h3 className="text-2xl font-black">{editingService ? 'تعديل بيانات الخدمة' : 'إنشاء خدمة جديدة'}</h3>
                                <p className="text-purple-100 text-xs font-bold">يرجى ملء البيانات التالية بدقة لتحديث التطبيق فوراً.</p>
                            </div>
                            <button 
                                type="button" 
                                onClick={() => { setIsAddingService(false); setEditingService(null); }} 
                                title="إغلاق" 
                                aria-label="Close modal" 
                                className="p-3 bg-white/10 hover:bg-white/20 active:scale-90 rounded-full transition-all text-white border border-white/10"
                            >
                                <X size={20} className="stroke-[3]" />
                            </button>
                        </div>
                        
                        <form onSubmit={handleSaveService} className="p-8 space-y-6">
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                <FormInput 
                                    label="عنوان الخدمة (مثلاً: كنس وسحب الزل)" 
                                    value={formData.title} 
                                    onChange={v => setFormData(p => ({ ...p, title: v }))} 
                                    required 
                                />
                                <FormInput 
                                    label="وصف الخدمة الفرعي" 
                                    value={formData.subtitle} 
                                    onChange={v => setFormData(p => ({ ...p, subtitle: v }))} 
                                />
                                <FormInput 
                                    label="سعر العرض البصري (مثلاً: 35 ر.س / ساعة)" 
                                    value={formData.price_text} 
                                    onChange={v => setFormData(p => ({ ...p, price_text: v }))} 
                                    required
                                />
                                <FormInput 
                                    label="السعر الرقمي الأساسي للحساب" 
                                    type="number" 
                                    value={String(formData.base_price)} 
                                    onChange={v => setFormData(p => ({ ...p, base_price: Number(v) }))} 
                                    required
                                />
                                <FormInput 
                                    label="الرابط البرمجي (Route Name)" 
                                    value={formData.route_name} 
                                    onChange={v => setFormData(p => ({ ...p, route_name: v }))} 
                                    placeholder="hourly, sofa_rug, store, maintenance" 
                                    required 
                                />
                                <FormInput 
                                    label="أيقونة فلاتر (Flutter Icon Name)" 
                                    value={formData.icon_name} 
                                    onChange={v => setFormData(p => ({ ...p, icon_name: v }))} 
                                    placeholder="access_time_filled, chair, settings" 
                                    required
                                />
                                <FormInput 
                                    label="ترتيب ظهور الخدمة بالتطبيق" 
                                    type="number" 
                                    value={String(formData.order_index)} 
                                    onChange={v => setFormData(p => ({ ...p, order_index: Number(v) }))} 
                                    required
                                />
                                <FormInput 
                                    label="مسار الصورة البصرية (اختياري)" 
                                    value={formData.image_path} 
                                    onChange={v => setFormData(p => ({ ...p, image_path: v }))} 
                                />
                            </div>
                            <div className="pt-6 border-t border-slate-100 flex gap-4">
                                <button 
                                    type="submit" 
                                    className="flex-1 bg-gradient-to-r from-[#5D1B5E] to-[#7B2E7C] text-white font-black py-4 rounded-2xl hover:opacity-95 active:scale-95 transition-all shadow-lg shadow-purple-900/10 text-base"
                                >
                                    حفظ وتحديث الخدمة
                                </button>
                                <button 
                                    type="button" 
                                    onClick={() => { setIsAddingService(false); setEditingService(null); }} 
                                    className="flex-1 bg-slate-100 text-slate-600 font-extrabold py-4 rounded-2xl hover:bg-slate-200 active:scale-95 transition-all text-base"
                                >
                                    إلغاء
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}

function PriceInput({ 
    label, 
    value, 
    onChange, 
    subLabel,
    highlighted = false
}: { 
    label: string, 
    value: number, 
    onChange: (v: number) => void,
    subLabel?: string,
    highlighted?: boolean
}) {
    return (
        <div className="space-y-2 group">
            <div className="flex items-center justify-between">
                <label className="text-xs font-black text-slate-500 tracking-wider group-focus-within:text-[#5D1B5E] transition-colors">{label}</label>
                {subLabel && <span className="text-[10px] text-slate-400 font-bold">{subLabel}</span>}
            </div>
            <div className="relative">
                <input 
                    type="number" 
                    value={value} 
                    onChange={e => onChange(Number(e.target.value))}
                    title={label}
                    className={`w-full bg-slate-50 border rounded-2xl pl-12 pr-4 py-4 font-extrabold text-slate-800 outline-none transition-all text-left ${
                        highlighted 
                            ? 'border-purple-200 focus:border-[#5D1B5E] focus:ring-4 focus:ring-[#5D1B5E]/15 bg-purple-50/20' 
                            : 'border-slate-200/80 focus:border-[#5D1B5E] focus:ring-4 focus:ring-[#5D1B5E]/10'
                    }`}
                />
                <span className="absolute left-4 top-1/2 -translate-y-1/2 font-black text-slate-400 text-xs">ر.س</span>
            </div>
        </div>
    );
}

function FormInput({ 
    label, 
    type = "text", 
    value, 
    onChange, 
    required, 
    placeholder 
}: { 
    label: string, 
    type?: string, 
    value: string, 
    onChange: (v: string) => void, 
    required?: boolean, 
    placeholder?: string 
}) {
    return (
        <div className="space-y-2 group">
            <label className="text-xs font-black text-slate-400 uppercase tracking-wider group-focus-within:text-[#5D1B5E] transition-colors">{label}</label>
            <input
                type={type}
                value={value}
                onChange={e => onChange(e.target.value)}
                required={required}
                placeholder={placeholder}
                title={label}
                className="w-full bg-slate-50 border border-slate-200/80 rounded-2xl px-5 py-4 font-bold text-slate-700 outline-none focus:border-[#5D1B5E] focus:ring-4 focus:ring-[#5D1B5E]/10 transition-all"
            />
        </div>
    );
}
