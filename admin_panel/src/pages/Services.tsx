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
    Loader2
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
    const [services, setServices] = useState<AppService[]>([]);
    const [pricing, setPricing] = useState<SofaRugPricing>({
        sofa_price_inside: 35,
        sofa_price_outside: 39,
        rug_price_inside: 15,
        rug_price_outside: 17,
        outside_deposit: 50
    });
    const [isLoading, setIsLoading] = useState(true);
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
        } finally {
            setIsLoading(false);
        }
    };

    const handleToggleService = async (service: AppService) => {
        try {
            const ref = doc(db, 'services', service.id);
            await updateDoc(ref, { is_active: !service.is_active });
            setServices(prev => prev.map(s => s.id === service.id ? { ...s, is_active: !s.is_active } : s));
        } catch {
            alert("حدث خطأ أثناء التحديث");
        }
    };

    const handleDeleteService = async (id: string) => {
        if (!globalThis.confirm("هل أنت متأكد من حذف هذه الخدمة؟")) return;
        try {
            await deleteDoc(doc(db, 'services', id));
            setServices(prev => prev.filter(s => s.id !== id));
        } catch {
            alert("حدث خطأ أثناء الحذف");
        }
    };

    const handleSavePricing = async () => {
        setIsSavingPricing(true);
        try {
            const docRef = doc(db, 'system_configs', 'main_settings');
            await setDoc(docRef, pricing, { merge: true });
            alert("تم حفظ أسعار الأمتار بنجاح!");
        } catch {
            alert("حدث خطأ أثناء الحفظ");
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
            } else {
                await addDoc(collection(db, 'services'), data);
            }
            setIsAddingService(false);
            setEditingService(null);
            fetchData();
        } catch {
            alert("حدث خطأ أثناء الحفظ");
        }
    };

    if (isLoading) return <div className="flex items-center justify-center h-full"><Loader2 className="animate-spin text-blue-600" size={40} /></div>;

    return (
        <div className="space-y-8 animate-in fade-in duration-500 pb-20 font-tajawal">
            {/* Header */}
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                    <h2 className="text-3xl font-black text-slate-800 tracking-tight">إدارة الخدمات والتسعير</h2>
                    <p className="text-slate-500 font-medium mt-1">تحكم كامل في خدمات التطبيق، ظهورها، وتسعيرها المباشر.</p>
                </div>
                <button
                    type="button"
                    onClick={openAddModal}
                    className="flex items-center justify-center space-x-2 space-x-reverse bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-2xl font-bold transition-all shadow-lg shadow-blue-200"
                >
                    <Plus size={20} />
                    <span>إضافة خدمة جديدة</span>
                </button>
            </div>

            {/* Sofa & Rug Special Pricing */}
            <section className="bg-white rounded-[32px] p-8 shadow-sm border border-slate-100">
                <div className="flex items-center gap-3 mb-8">
                    <div className="p-3 bg-purple-50 rounded-2xl text-purple-600">
                        <Settings size={24} />
                    </div>
                    <div>
                        <h3 className="text-xl font-bold text-slate-800">تسعير خدمة الكنب والزل (بالأمتار)</h3>
                        <p className="text-sm text-slate-400">هذه الأسعار تنعكس على شاشة تفاصيل الكنب والزل تلقائياً.</p>
                    </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6">
                    <PriceInput label="كنب (داخل) - ر.س" value={pricing.sofa_price_inside} onChange={v => setPricing({...pricing, sofa_price_inside: v})} />
                    <PriceInput label="كنب (خارج) - ر.س" value={pricing.sofa_price_outside} onChange={v => setPricing({...pricing, sofa_price_outside: v})} />
                    <PriceInput label="زل (داخل) - ر.س" value={pricing.rug_price_inside} onChange={v => setPricing({...pricing, rug_price_inside: v})} />
                    <PriceInput label="زل (خارج) - ر.س" value={pricing.rug_price_outside} onChange={v => setPricing({...pricing, rug_price_outside: v})} />
                    <PriceInput label="عربون الخارج - ر.س" value={pricing.outside_deposit} onChange={v => setPricing({...pricing, outside_deposit: v})} />
                </div>

                <div className="mt-8 flex justify-end">
                    <button
                        type="button"
                        onClick={handleSavePricing}
                        disabled={isSavingPricing}
                        className="flex items-center px-8 py-3 bg-slate-900 text-white rounded-xl font-bold hover:bg-slate-800 transition-all disabled:opacity-50"
                    >
                        {isSavingPricing ? <Loader2 className="animate-spin ml-2" size={18} /> : <Save className="ml-2" size={18} />}
                        حفظ تسعيرة الأمتار
                    </button>
                </div>
            </section>

            {/* Services List */}
            <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                {services.map(service => (
                    <div key={service.id} className={`group bg-white rounded-[32px] p-6 border transition-all hover:shadow-xl hover:shadow-slate-200/50 ${!service.is_active ? 'opacity-75 border-slate-100 bg-slate-50/50' : 'border-slate-100'}`}>
                        <div className="flex items-start justify-between mb-4">
                            <div className="flex items-center gap-4">
                                <div className={`p-4 rounded-2xl ${service.is_active ? 'bg-blue-50 text-blue-600' : 'bg-slate-100 text-slate-400'}`}>
                                    <LayoutGrid size={28} />
                                </div>
                                <div>
                                    <h4 className="text-xl font-black text-slate-800">{service.title}</h4>
                                    <p className="text-slate-400 text-sm font-medium">{service.subtitle}</p>
                                </div>
                            </div>
                            <div className="flex items-center gap-2">
                                <button
                                    type="button"
                                    onClick={() => handleToggleService(service)}
                                    title={service.is_active ? "إخفاء من التطبيق" : "إظهار في التطبيق"}
                                    aria-label={service.is_active ? "Hide service" : "Show service"}
                                    className={`p-2.5 rounded-xl transition-all ${service.is_active ? 'bg-emerald-50 text-emerald-600 hover:bg-emerald-100' : 'bg-slate-100 text-slate-400 hover:bg-slate-200'}`}
                                >
                                    {service.is_active ? <Eye size={20} /> : <EyeOff size={20} />}
                                </button>
                                <button
                                    type="button"
                                    onClick={() => openEditModal(service)}
                                    title="تعديل الخدمة"
                                    aria-label="Edit service"
                                    className="p-2.5 bg-slate-50 text-slate-600 rounded-xl hover:bg-slate-100"
                                >
                                    <Edit2 size={20} />
                                </button>
                                <button 
                                    type="button"
                                    onClick={() => handleDeleteService(service.id)}
                                    title="حذف الخدمة"
                                    aria-label="Delete service"
                                    className="p-2.5 bg-red-50 text-red-600 rounded-xl hover:bg-red-100"
                                >
                                    <Trash2 size={20} />
                                </button>
                            </div>
                        </div>

                        <div className="grid grid-cols-3 gap-4 mt-6 p-4 bg-slate-50 rounded-2xl border border-slate-100/50">
                            <div>
                                <span className="block text-[10px] font-bold text-slate-400 uppercase mb-1">السعر المعروض</span>
                                <span className="text-sm font-bold text-slate-700">{service.price_text}</span>
                            </div>
                            <div>
                                <span className="block text-[10px] font-bold text-slate-400 uppercase mb-1">الرابط البرمجي</span>
                                <span className="text-sm font-mono font-bold text-blue-600 bg-blue-50 px-2 py-0.5 rounded">{service.route_name}</span>
                            </div>
                            <div>
                                <span className="block text-[10px] font-bold text-slate-400 uppercase mb-1">الترتيب</span>
                                <span className="text-sm font-bold text-slate-700">#{service.order_index}</span>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Modal for Add/Edit */}
            {isAddingService && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-sm animate-in fade-in duration-200">
                    <div className="bg-white rounded-[32px] w-full max-w-2xl shadow-2xl overflow-hidden border border-slate-100">
                        <div className="p-8 border-b border-slate-50 flex items-center justify-between">
                            <h3 className="text-2xl font-black text-slate-800">{editingService ? 'تعديل الخدمة' : 'إضافة خدمة جديدة'}</h3>
                            <button type="button" onClick={() => { setIsAddingService(false); setEditingService(null); }} title="إغلاق" aria-label="Close modal" className="p-2 hover:bg-slate-100 rounded-full transition-colors"><Trash2 className="text-slate-400" size={24} /></button>
                        </div>
                        <form onSubmit={handleSaveService} className="p-8 space-y-6">
                            <div className="grid grid-cols-2 gap-6">
                                <FormInput label="عنوان الخدمة (مثلاً: تنظيف كنب)" value={formData.title} onChange={v => setFormData(p => ({ ...p, title: v }))} required />
                                <FormInput label="وصف قصير (مثلاً: تنظيف عميق)" value={formData.subtitle} onChange={v => setFormData(p => ({ ...p, subtitle: v }))} />
                                <FormInput label="السعر للعرض (مثلاً: من 50 ر.س)" value={formData.price_text} onChange={v => setFormData(p => ({ ...p, price_text: v }))} />
                                <FormInput label="السعر الرقمي (للحساب)" type="number" value={String(formData.base_price)} onChange={v => setFormData(p => ({ ...p, base_price: Number(v) }))} />
                                <FormInput label="الرابط البرمجي (عند الحجز)" value={formData.route_name} onChange={v => setFormData(p => ({ ...p, route_name: v }))} placeholder="hourly, sofa_rug, store, maintenance" required />
                                <FormInput label="اسم الأيقونة (flutter icon)" value={formData.icon_name} onChange={v => setFormData(p => ({ ...p, icon_name: v }))} placeholder="access_time_filled, chair" />
                                <FormInput label="ترتيب العرض" type="number" value={String(formData.order_index)} onChange={v => setFormData(p => ({ ...p, order_index: Number(v) }))} />
                                <FormInput label="رابط الصورة (اختياري)" value={formData.image_path} onChange={v => setFormData(p => ({ ...p, image_path: v }))} />
                            </div>
                            <div className="pt-4 flex gap-4">
                                <button type="submit" className="flex-1 bg-blue-600 text-white font-bold py-4 rounded-2xl hover:bg-blue-700 transition-all shadow-lg shadow-blue-100">حفظ الخدمة</button>
                                <button type="button" onClick={() => { setIsAddingService(false); setEditingService(null); }} className="flex-1 bg-slate-100 text-slate-600 font-bold py-4 rounded-2xl hover:bg-slate-200 transition-all">إلغاء</button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}

function PriceInput({ label, value, onChange }: { label: string, value: number, onChange: (v: number) => void }) {
    return (
        <div className="space-y-2">
            <label className="text-sm font-bold text-slate-600">{label}</label>
            <input 
                type="number" 
                value={value} 
                onChange={e => onChange(Number(e.target.value))}
                title={label}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-purple-400 focus:ring-4 focus:ring-purple-400/10 transition-all"
            />
        </div>
    );
}

function FormInput({ label, type = "text", value, onChange, required, placeholder }: { label: string, type?: string, value: string, onChange: (v: string) => void, required?: boolean, placeholder?: string }) {
    return (
        <div className="space-y-2">
            <label className="text-xs font-black text-slate-400 uppercase tracking-wider">{label}</label>
            <input
                type={type}
                value={value}
                onChange={e => onChange(e.target.value)}
                required={required}
                placeholder={placeholder}
                title={label}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-5 py-3.5 font-bold text-slate-700 outline-none focus:border-blue-600 focus:ring-4 focus:ring-blue-600/10 transition-all"
            />
        </div>
    );
}
