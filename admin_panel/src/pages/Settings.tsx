import { useState, useEffect } from 'react';
import { Save, Bell, Shield, Wallet, MapPin, Search, Smartphone, Loader2, CheckCircle2, ChevronLeft, CreditCard, Activity, Globe, Database, KeyRound, ArrowRight } from 'lucide-react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

interface SystemSettings {
    // General
    force_update_version: string;
    force_update_enabled: boolean;
    terms_url: string;
    support_url: string;
    privacy_policy: string;
    maintenance_mode: boolean;

    // Payments
    commission_rate: number;
    vat_rate: number;
    min_wallet_balance: number;
    cod_enabled: boolean;
    cod_hourly: boolean;
    cod_monthly: boolean;
    cod_maintenance: boolean;
    cod_contracts: boolean;

    // Notifications
    sms_on_order: boolean;
    push_on_assign: boolean;
    push_on_completed: boolean;

    // Coverage
    riyadh_enabled: boolean;
    jeddah_enabled: boolean;
    dammam_enabled: boolean;
}

const defaultSettings: SystemSettings = {
    force_update_version: "v2.1.0",
    force_update_enabled: true,
    terms_url: "https://zyiarah.com/terms",
    support_url: "https://zyiarah.com/support",
    privacy_policy: "نحن في تطبيق زيارة نلتزم بحماية بياناتك الشخصية...",
    maintenance_mode: false,
    commission_rate: 15,
    vat_rate: 15,
    min_wallet_balance: -50,
    cod_enabled: true,
    cod_hourly: true,
    cod_monthly: false,
    cod_maintenance: true,
    cod_contracts: false,
    sms_on_order: true,
    push_on_assign: true,
    push_on_completed: true,
    riyadh_enabled: true,
    jeddah_enabled: false,
    dammam_enabled: false,
};

type TabType = 'general' | 'payments' | 'notifications' | 'coverage';

export default function Settings() {
    const [activeTab, setActiveTab] = useState<TabType>('general');
    const [settings, setSettings] = useState<SystemSettings>(defaultSettings);
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [saveSuccess, setSaveSuccess] = useState(false);

    useEffect(() => {
        const fetchSettings = async () => {
            try {
                const docRef = doc(db, 'system_configs', 'main_settings');
                const docSnap = await getDoc(docRef);
                if (docSnap.exists()) {
                    setSettings({ ...defaultSettings, ...docSnap.data() } as SystemSettings);
                }
            } catch (error) {
                console.error("Error fetching settings:", error);
            } finally {
                setIsLoading(false);
            }
        };
        fetchSettings();
    }, []);

    const handleSave = async () => {
        setIsSaving(true);
        try {
            const docRef = doc(db, 'system_configs', 'main_settings');
            await setDoc(docRef, settings, { merge: true });
            
            // Show brief success indication
            setSaveSuccess(true);
            setTimeout(() => setSaveSuccess(false), 3000);
        } catch (error) {
            console.error("Error saving settings:", error);
            alert("حدث خطأ أثناء حفظ الإعدادات.");
        } finally {
            setIsSaving(false);
        }
    };

    const handleChange = <K extends keyof SystemSettings>(key: K, value: SystemSettings[K]) => {
        setSettings(prev => ({ ...prev, [key]: value }));
    };

    if (isLoading) {
        return (
            <div className="flex flex-col h-[70vh] items-center justify-center space-y-4">
                <div className="relative w-20 h-20">
                    <div className="absolute inset-0 rounded-full border-t-4 border-indigo-600 animate-spin"></div>
                    <div className="absolute inset-2 rounded-full border-t-4 border-fuchsia-500 animate-spin opacity-50 animation-delay-150"></div>
                </div>
                <div className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 to-fuchsia-600 animate-pulse">
                    تهيئة الإعدادات...
                </div>
            </div>
        );
    }

    const tabs = [
        { id: 'general', label: 'عام وأمان', icon: Shield, color: 'from-blue-600 to-indigo-600', bg: 'bg-blue-50/50', border: 'border-blue-100', text: 'text-blue-700' },
        { id: 'payments', label: 'المدفوعات', icon: Wallet, color: 'from-emerald-500 to-green-600', bg: 'bg-emerald-50/50', border: 'border-emerald-100', text: 'text-emerald-700' },
        { id: 'notifications', label: 'الإشعارات', icon: Bell, color: 'from-orange-500 to-amber-600', bg: 'bg-orange-50/50', border: 'border-orange-100', text: 'text-orange-700' },
        { id: 'coverage', label: 'التغطية', icon: MapPin, color: 'from-purple-500 to-fuchsia-600', bg: 'bg-purple-50/50', border: 'border-purple-100', text: 'text-purple-700' },
    ] as const;

    const currentTabColor = tabs.find(t => t.id === activeTab)?.color || tabs[0].color;

    return (
        <div className="space-y-8 pb-12 animate-in fade-in slide-in-from-bottom-8 duration-700 max-w-7xl mx-auto">
            {/* Header Section */}
            <div className="relative p-8 rounded-[2rem] bg-white border border-slate-100 shadow-[0_8px_30px_rgb(0,0,0,0.04)] overflow-hidden flex flex-col md:flex-row items-center justify-between gap-6 isolation-auto z-0">
                {/* Decorative background blurs */}
                <div className={`absolute top-0 right-0 w-64 h-64 bg-gradient-to-bl ${currentTabColor} rounded-full opacity-[0.05] blur-3xl -translate-y-1/2 translate-x-1/2 transition-colors duration-500`}></div>
                <div className={`absolute bottom-0 left-0 w-80 h-80 bg-gradient-to-tr ${currentTabColor} rounded-full opacity-[0.03] blur-3xl translate-y-1/3 -translate-x-1/3 transition-colors duration-500`}></div>
                
                <div className="relative z-10 flex items-center gap-6">
                    <div className={`w-16 h-16 rounded-2xl bg-gradient-to-br ${currentTabColor} p-0.5 shadow-lg shadow-indigo-500/20 transition-colors duration-500`}>
                        <div className="w-full h-full bg-white rounded-[14px] flex items-center justify-center">
                            <SettingsIcon activeTab={activeTab} />
                        </div>
                    </div>
                    <div>
                        <h2 className="text-3xl font-black text-slate-900 tracking-tight mb-2">إعدادات النظام</h2>
                        <p className="text-slate-500 font-medium flex items-center gap-2">
                            <Activity size={16} className="text-emerald-500" />
                            إدارة شاملة لتكوينات التطبيق وقواعد العمل
                        </p>
                    </div>
                </div>

                <div className="relative z-10 flex w-full md:w-auto">
                    <button
                        type="button"
                        onClick={handleSave}
                        disabled={isSaving}
                        className={`w-full md:w-auto relative group overflow-hidden flex items-center justify-center gap-3 px-8 py-4 rounded-2xl font-bold text-white transition-all duration-300 disabled:opacity-70 disabled:cursor-not-allowed disabled:transform-none shadow-xl
                            ${saveSuccess 
                                ? 'bg-emerald-500 shadow-emerald-500/30' 
                                : `bg-gradient-to-r ${currentTabColor} shadow-indigo-500/25 hover:shadow-indigo-500/40 hover:-translate-y-1 hover:scale-[1.02]`
                            }`}
                    >
                        <div className="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform duration-300 ease-out"></div>
                        <span className="relative z-10 flex items-center gap-3">
                            {isSaving ? (
                                <><Loader2 size={22} className="animate-spin" /> جاري الحفظ...</>
                            ) : saveSuccess ? (
                                <><CheckCircle2 size={24} className="text-white" /> تم الحفظ بنجاح!</>
                            ) : (
                                <><Save size={22} className="group-hover:scale-110 transition-transform" /> حفظ التغييرات</>
                            )}
                        </span>
                    </button>
                </div>
            </div>

            <div className="flex flex-col lg:flex-row gap-8 items-start">
                {/* Advanced Modern Navigation Sidebar */}
                <div className="w-full lg:w-[320px] flex-shrink-0 space-y-4">
                    <div className="bg-white rounded-[2rem] p-3 shadow-[0_8px_30px_rgb(0,0,0,0.03)] border border-slate-100 relative z-20">
                        {/* Search Input */}
                        <div className="p-2 mb-2">
                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none">
                                    <Search size={18} className="text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                                </div>
                                <input
                                    type="text"
                                    placeholder="بحث سريع..."
                                    className="w-full bg-slate-50/50 border border-slate-200 text-sm rounded-xl py-3 pr-11 pl-4 outline-none focus:bg-white focus:border-indigo-300 focus:ring-4 focus:ring-indigo-500/10 transition-all text-slate-700 font-medium placeholder-slate-400"
                                />
                            </div>
                        </div>

                        <div className="h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent mb-4 mx-4"></div>

                        <nav className="space-y-1">
                            {tabs.map((tab) => {
                                const isActive = activeTab === tab.id;
                                const Icon = tab.icon;
                                return (
                                    <button
                                        key={tab.id}
                                        type="button"
                                        onClick={() => setActiveTab(tab.id as TabType)}
                                        className={`w-full relative flex items-center justify-between px-5 py-4 rounded-xl font-bold transition-all duration-300 group overflow-hidden ${
                                            isActive ? 'bg-slate-50' : 'hover:bg-slate-50/50 text-slate-500 hover:text-slate-800'
                                        }`}
                                    >
                                        {/* Active State Background Gradient Effect */}
                                        <div className={`absolute inset-0 opacity-0 transition-opacity duration-300 ${isActive ? 'opacity-100' : 'group-hover:opacity-100'}`}>
                                            <div className={`absolute right-0 top-0 bottom-0 w-1.5 rounded-l-full bg-gradient-to-b ${tab.color} transform origin-right transition-transform duration-300 ${isActive ? 'scale-x-100' : 'scale-x-0 group-hover:scale-x-100 opacity-50'}`}></div>
                                            {isActive && <div className={`absolute inset-0 bg-gradient-to-l ${tab.color} opacity-[0.03]`}></div>}
                                        </div>

                                        <div className="relative z-10 flex items-center gap-4">
                                            <div className={`flex items-center justify-center w-10 h-10 rounded-xl transition-all duration-300 ${
                                                isActive 
                                                    ? `bg-gradient-to-br ${tab.color} shadow-lg shadow-${tab.color.split('-')[1]}/30 text-white scale-110` 
                                                    : `bg-slate-100 text-slate-400 group-hover:text-slate-600 group-hover:scale-105`
                                            }`}>
                                                <Icon size={20} strokeWidth={isActive ? 2.5 : 2} />
                                            </div>
                                            <span className={`text-[15px] tracking-wide ${isActive ? 'text-slate-800' : ''}`}>{tab.label}</span>
                                        </div>
                                        
                                        <ChevronLeft size={18} className={`relative z-10 transition-transform duration-300 ${isActive ? `text-${tab.color.split('-')[1]}-500 -translate-x-1` : 'text-slate-200 group-hover:-translate-x-1'}`} />
                                    </button>
                                );
                            })}
                        </nav>
                    </div>
                    
                    {/* Compact Help Box */}
                    <div className="bg-gradient-to-br from-indigo-600 to-blue-700 rounded-[2rem] p-6 text-white shadow-xl shadow-indigo-600/20 relative overflow-hidden hidden lg:block">
                        <div className="absolute -right-8 -top-8 w-32 h-32 bg-white opacity-10 rounded-full blur-2xl"></div>
                        <div className="relative z-10">
                            <h3 className="font-bold text-lg mb-2">هل تحتاج مساعدة؟</h3>
                            <p className="text-blue-100 text-sm mb-4 leading-relaxed font-medium">وثائق النظام تحتوي على تفاصيل كاملة لجميع الإعدادات المبينة هنا.</p>
                            <a href={settings.support_url || 'https://zyiarah.com/support'} target="_blank" rel="noopener noreferrer" className="bg-white/10 hover:bg-white/20 backdrop-blur-md border border-white/20 text-white text-sm font-bold py-2.5 px-4 rounded-xl transition-colors inline-flex items-center gap-2">
                                تصفح الدليل <ArrowRight size={16} />
                            </a>
                        </div>
                    </div>
                </div>

                {/* Main Content Area - Glassmorphism & Animations */}
                <div className="flex-1 w-full bg-white rounded-[2.5rem] shadow-[0_8px_40px_rgb(0,0,0,0.04)] border border-slate-100 relative overflow-hidden min-h-[600px] z-10 isolate transition-all duration-500">
                    {/* Animated Tab Content Container */}
                    <div key={activeTab} className="h-full animate-in fade-in zoom-in-95 slide-in-from-left-4 duration-500 fill-mode-both">
                        
                        {activeTab === 'general' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-slate-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl">
                                            <Shield size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">عام وأمان</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">تكوين إعدادات الوصول وتفضيلات الأمان الرئيسية للنظام</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="p-10 space-y-10 overflow-y-auto">
                                    
                                    {/* API Keys Section */}
                                    <section>
                                        <h4 className="flex items-center gap-2 text-lg font-bold text-slate-800 mb-6">
                                            <KeyRound size={20} className="text-blue-500" /> المفاتيح الأمنية السحابية
                                        </h4>
                                        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-blue-200 group">
                                                <label htmlFor="zatca-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                                                <div className="relative">
                                                    <input id="zatca-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-blue-300 transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => alert('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح الزكاة والدخل من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-600 hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-blue-200 group">
                                                <label htmlFor="firebase-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح Firebase Admin</label>
                                                <div className="relative">
                                                    <input id="firebase-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-blue-300 transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => alert('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح Firebase من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-600 hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                        </div>
                                    </section>

                                    <div className="w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>

                                    {/* App Versioning & Legal */}
                                    <section>
                                        <h4 className="flex items-center gap-2 text-lg font-bold text-slate-800 mb-6">
                                            <Smartphone size={20} className="text-indigo-500" /> توافق المتاجر والنصوص القانونية
                                        </h4>
                                        <div className="bg-white border border-slate-200 shadow-sm rounded-[2rem] p-8 relative overflow-hidden">
                                            <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-50 rounded-full blur-3xl -translate-y-10 translate-x-10 pointer-events-none"></div>
                                            
                                            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 relative z-10">
                                                <div className="md:col-span-2 flex flex-col md:flex-row gap-6 items-center p-5 bg-indigo-50/50 border border-indigo-100/50 rounded-2xl">
                                                    <div className="flex-1 w-full">
                                                        <label htmlFor="min-version" className="block text-sm font-bold text-slate-800 mb-2">الإصدار الإلزامي (Force Update Version)</label>
                                                        <p className="text-xs text-slate-500 font-medium mb-3">سيُجبر أي مستخدم لديه إصدار أقدم على التحديث فوراً.</p>
                                                        <input
                                                            id="min-version"
                                                            type="text"
                                                            value={settings.force_update_version}
                                                            onChange={(e) => handleChange('force_update_version', e.target.value)}
                                                            className="w-full md:w-64 bg-white border border-slate-300 focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/20 text-slate-800 font-bold text-sm rounded-xl px-5 py-3.5 outline-none transition-all shadow-sm text-left font-mono"
                                                            dir="ltr"
                                                            placeholder="v1.0.0"
                                                        />
                                                    </div>
                                                    <div className="flex items-center bg-white border border-slate-200 p-2 pl-4 pr-2 rounded-2xl shadow-sm self-start md:self-auto">
                                                        <span className="ml-4 text-sm font-bold text-slate-700">تفعيل الإجبار</span>
                                                        <label className="relative inline-flex items-center cursor-pointer">
                                                            <input type="checkbox" aria-label="تفعيل الإجبار على التحديث" className="sr-only peer" checked={settings.force_update_enabled} onChange={(e) => handleChange('force_update_enabled', e.target.checked)} />
                                                            <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-indigo-600"></div>
                                                        </label>
                                                    </div>
                                                </div>

                                                <div className="space-y-2">
                                                    <label htmlFor="terms-url" className="block text-sm font-bold text-slate-700">رابط الشروط والأحكام</label>
                                                    <input
                                                        id="terms-url" type="url" value={settings.terms_url} onChange={(e) => handleChange('terms_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/terms"
                                                    />
                                                </div>
                                                <div className="space-y-2">
                                                    <label htmlFor="support-url" className="block text-sm font-bold text-slate-700">رابط الدعم الفني</label>
                                                    <input
                                                        id="support-url" type="url" value={settings.support_url} onChange={(e) => handleChange('support_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/support"
                                                    />
                                                </div>
                                                <div className="md:col-span-2 space-y-2">
                                                    <label htmlFor="privacy-policy" className="block text-sm font-bold text-slate-700">نص سياسة الخصوصية داخل التطبيق</label>
                                                    <textarea
                                                        id="privacy-policy" rows={4} value={settings.privacy_policy} onChange={(e) => handleChange('privacy_policy', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-4 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/10 transition-all resize-y leading-loose"
                                                        placeholder="اكتب سياسة الخصوصية هنا..."
                                                    />
                                                </div>
                                            </div>
                                        </div>
                                    </section>

                                    {/* Danger Zone: Maintenance Mode */}
                                    <section className="pt-4">
                                        <div className={`relative overflow-hidden rounded-[2rem] border transition-all duration-500 ${
                                            settings.maintenance_mode 
                                            ? 'bg-gradient-to-r from-red-50 to-orange-50 border-red-200 shadow-[0_0_40px_rgba(239,68,68,0.15)] ring-1 ring-red-500/20' 
                                            : 'bg-white border-slate-200 hover:border-slate-300'
                                        }`}>
                                            {settings.maintenance_mode && (
                                                <div className="absolute top-0 right-0 w-full h-full bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-red-500/10 via-transparent to-transparent pointer-events-none"></div>
                                            )}
                                            <div className="p-8 flex flex-col md:flex-row gap-6 items-center justify-between relative z-10">
                                                <div className="flex items-center gap-5">
                                                    <div className={`p-4 rounded-2xl border flex-shrink-0 transition-colors duration-500 ${
                                                        settings.maintenance_mode ? 'bg-red-500 border-red-600 text-white shadow-lg shadow-red-500/30 animate-pulse' : 'bg-slate-100 border-slate-200 text-slate-400'
                                                    }`}>
                                                        <Database size={32} strokeWidth={2} />
                                                    </div>
                                                    <div>
                                                        <h4 className={`text-xl font-black mb-1 transition-colors ${settings.maintenance_mode ? 'text-red-700' : 'text-slate-800'}`}>وضع الصيانة الداخلي (Maintenance)</h4>
                                                        <p className={`text-sm font-medium max-w-xl leading-relaxed ${settings.maintenance_mode ? 'text-red-600/80' : 'text-slate-500'}`}>عند تفعيل وضع الصيانة، سيتم قفل التطبيق للمستخدمين الخارجيين مع عرض رسالة صيانة مؤقتة ولن يتم استقبال طلبات جديدة.</p>
                                                    </div>
                                                </div>
                                                <button
                                                    type="button"
                                                    onClick={() => handleChange('maintenance_mode', !settings.maintenance_mode)}
                                                    className={`px-8 py-4 rounded-xl font-bold transition-all duration-300 w-full md:w-auto flex items-center justify-center gap-2 whitespace-nowrap border-2 ${
                                                        settings.maintenance_mode 
                                                        ? 'bg-white border-red-200 text-red-600 hover:bg-red-50 hover:border-red-300 shadow-sm' 
                                                        : 'bg-white border-slate-200 text-slate-700 hover:border-slate-300 hover:bg-slate-50 shadow-sm'
                                                    }`}
                                                >
                                                    {settings.maintenance_mode ? 'إيقاف الصيانة وفتح التطبيق' : 'تفعيل الصيانة وإغلاق التطبيق'}
                                                </button>
                                            </div>
                                        </div>
                                    </section>
                                </div>
                            </div>
                        )}

                        {activeTab === 'payments' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-emerald-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-emerald-50 text-emerald-600 rounded-2xl">
                                            <Wallet size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">المدفوعات والعمولات</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">إعداد وهيكلة الضرائب، العمولات، وسياسات الدفع النقدي.</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="p-10 space-y-8 overflow-y-auto">
                                    
                                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                                        <div className="bg-white border border-slate-200 p-8 rounded-[2rem] shadow-sm relative overflow-hidden group hover:border-emerald-200 hover:shadow-md transition-all">
                                            <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity"><Activity size={64} /></div>
                                            <label htmlFor="vat-rate" className="block text-sm font-bold text-slate-800 mb-2 relative z-10">ضريبة القيمة المضافة (VAT)</label>
                                            <p className="text-xs text-slate-500 font-medium mb-4 h-8 relative z-10">تضاف على تكلفة الخدمة كرسوم إضافية.</p>
                                            <div className="relative z-10 flex items-center">
                                                <input
                                                    id="vat-rate"
                                                    type="number" value={settings.vat_rate} onChange={(e) => handleChange('vat_rate', Number(e.target.value))}
                                                    className="w-full bg-slate-50 border border-slate-200 text-slate-800 font-black text-2xl rounded-xl px-5 py-4 outline-none focus:bg-white focus:border-emerald-500 focus:ring-4 focus:ring-emerald-500/10 transition-all text-center"
                                                    dir="ltr"
                                                />
                                                <span className="absolute left-6 text-slate-400 font-black text-xl pointer-events-none">%</span>
                                            </div>
                                        </div>

                                        <div className="bg-white border border-blue-100 p-8 rounded-[2rem] shadow-sm relative overflow-hidden group hover:border-blue-300 hover:shadow-md transition-all">
                                            <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity"><Activity size={64} /></div>
                                            <label htmlFor="commission-rate" className="block text-sm font-bold text-slate-800 mb-2 relative z-10">نسبة عمولة المنصة</label>
                                            <p className="text-xs text-slate-500 font-medium mb-4 h-8 relative z-10">النسبة التي تأخذها المنصة من كل طلب مكتمل.</p>
                                            <div className="relative z-10 flex items-center">
                                                <input
                                                    id="commission-rate"
                                                    type="number" value={settings.commission_rate} onChange={(e) => handleChange('commission_rate', Number(e.target.value))}
                                                    className="w-full bg-slate-50 border border-slate-200 text-slate-800 font-black text-2xl rounded-xl px-5 py-4 outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/10 transition-all text-center"
                                                    dir="ltr"
                                                />
                                                <span className="absolute left-6 text-slate-400 font-black text-xl pointer-events-none">%</span>
                                            </div>
                                        </div>

                                        <div className="bg-white border border-red-100 p-8 rounded-[2rem] shadow-sm relative overflow-hidden group hover:border-red-300 hover:shadow-md transition-all">
                                            <div className="absolute top-0 right-0 p-4 text-red-500 opacity-5 group-hover:opacity-10 transition-opacity"><ArrowRight size={64} className="rotate-90" /></div>
                                            <label htmlFor="min-wallet" className="block text-sm font-bold text-slate-800 mb-2 relative z-10">الحد الأدنى للمحفظة</label>
                                            <p className="text-xs text-slate-500 font-medium mb-4 h-8 relative z-10">حد المديونية الذي يتم عنده إيقاف السائق.</p>
                                            <div className="relative z-10 flex items-center">
                                                <input
                                                    id="min-wallet"
                                                    type="number" value={settings.min_wallet_balance} onChange={(e) => handleChange('min_wallet_balance', Number(e.target.value))}
                                                    className="w-full bg-red-50 border border-red-200 text-red-700 font-black text-2xl rounded-xl px-5 py-4 outline-none focus:bg-white focus:border-red-500 focus:ring-4 focus:ring-red-500/10 transition-all text-center"
                                                    dir="ltr"
                                                />
                                                <span className="absolute left-6 text-red-400 font-bold text-sm pointer-events-none">SAR</span>
                                            </div>
                                        </div>
                                    </div>

                                    {/* COD Section */}
                                    <div className="bg-slate-50/50 border border-slate-200 rounded-[2.5rem] p-8 mt-10">
                                        <div className="flex flex-col md:flex-row items-start md:items-center justify-between mb-8 pb-6 border-b border-slate-200/80">
                                            <div>
                                                <h4 className="text-xl font-black text-slate-800 flex items-center gap-3">
                                                    <CreditCard className="text-emerald-500" />
                                                    الدفع السائل / عند الاستلام (COD)
                                                </h4>
                                                <p className="text-slate-500 font-medium mt-2">السماح بتشكيل طرق الدفع النقدي في الخدمات والمتاجر المختارة.</p>
                                            </div>
                                            <div className="mt-4 md:mt-0 bg-white p-2 rounded-2xl shadow-sm border border-slate-100 flex items-center">
                                                <span className="px-4 font-bold text-slate-700 text-sm">الحالة العامة</span>
                                                <label className="relative inline-flex items-center cursor-pointer mr-2">
                                                    <input type="checkbox" aria-label="تفعيل الدفع النقدي" className="sr-only peer" checked={settings.cod_enabled} onChange={(e) => handleChange('cod_enabled', e.target.checked)} />
                                                    <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-emerald-500"></div>
                                                </label>
                                            </div>
                                        </div>

                                        <div className={`transition-all duration-500 ${settings.cod_enabled ? 'opacity-100' : 'opacity-40 pointer-events-none grayscale'}`}>
                                            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                                                {[
                                                    { id: 'cod_hourly', label: 'التنظيف بالساعة', color: 'blue' },
                                                    { id: 'cod_monthly', label: 'التنظيف الشهري', color: 'indigo' },
                                                    { id: 'cod_maintenance', label: 'قسم الصيانة', color: 'orange' },
                                                    { id: 'cod_contracts', label: 'العقود الإلكترونية', color: 'purple' },
                                                ].map((item) => (
                                                    <label key={item.id} className={`group cursor-pointer flex flex-col items-center p-6 bg-white border-2 rounded-3xl transition-all duration-300 hover:-translate-y-1 hover:shadow-lg ${settings[item.id as keyof SystemSettings] ? `border-${item.color}-500 shadow-md shadow-${item.color}-500/10` : 'border-slate-100 hover:border-slate-300'}`}>
                                                        <span className={`text-[15px] font-bold mb-4 ${settings[item.id as keyof SystemSettings] ? 'text-slate-800' : 'text-slate-500'}`}>{item.label}</span>
                                                        <div className="relative inline-flex items-center mt-auto">
                                                            <input type="checkbox" className="sr-only peer" checked={settings[item.id as keyof SystemSettings] as boolean} onChange={(e) => handleChange(item.id as keyof SystemSettings, e.target.checked)} />
                                                            <div className={`w-12 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-${item.color}-500`}></div>
                                                        </div>
                                                    </label>
                                                ))}
                                            </div>
                                        </div>
                                    </div>

                                </div>
                            </div>
                        )}

                        {activeTab === 'notifications' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-orange-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-orange-50 text-orange-600 rounded-2xl">
                                            <Bell size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">توجيه الرسائل والإشعارات</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">التحكم في تنبيهات النظام المعززة لتحسين تواصل العملاء والسائقين.</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="p-10">
                                    <div className="space-y-4 max-w-4xl mx-auto">
                                        <NotificationRow 
                                            title="رسالة نصية SMS للمستفيد بالفاتورة"
                                            desc="تفعيل إرسال رسالة SMS للعميل تتضمن رابط الفاتورة وحالة الطلب."
                                            checked={settings.sms_on_order}
                                            onChange={(val) => handleChange('sms_on_order', val)}
                                            icon={<Smartphone className="text-blue-500" />}
                                            colorTheme="blue"
                                        />
                                        <NotificationRow 
                                            title="إشعار Push للسائقين بالطلبات القريبة"
                                            desc="إرسال تنبيه في الوقت الفعلي للسائقين المتاحين في نفس المنطقة."
                                            checked={settings.push_on_assign}
                                            onChange={(val) => handleChange('push_on_assign', val)}
                                            icon={<Globe className="text-emerald-500" />}
                                            colorTheme="emerald"
                                        />
                                        <NotificationRow 
                                            title="تنبيه Push للعميل للإفادة بالانتهاء"
                                            desc="تحفيز العميل لتقييم الخدمة فور انتهاء السائق من تنفيذها."
                                            checked={settings.push_on_completed}
                                            onChange={(val) => handleChange('push_on_completed', val)}
                                            icon={<CheckCircle2 className="text-orange-500" />}
                                            colorTheme="orange"
                                        />
                                    </div>
                                </div>
                            </div>
                        )}

                        {activeTab === 'coverage' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-purple-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-purple-50 text-purple-600 rounded-2xl">
                                            <MapPin size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">مناطق التغطية التشغيلية</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">تحديد المدن والمناطق التي يعمل بها تطبيق زيارة حالياً.</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="p-10">
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
                                        <CoverageCard 
                                            city="الرياض"
                                            region="المنطقة الوسطى"
                                            checked={settings.riyadh_enabled}
                                            onChange={(val) => handleChange('riyadh_enabled', val)}
                                            bgImage="linear-gradient(to bottom right, #f8fafc, #ebf4ff)"
                                        />
                                        <CoverageCard 
                                            city="جدة"
                                            region="منطقة مكة المكرمة"
                                            checked={settings.jeddah_enabled}
                                            onChange={(val) => handleChange('jeddah_enabled', val)}
                                            bgImage="linear-gradient(to bottom right, #f8fafc, #f0fdf4)"
                                        />
                                        <CoverageCard 
                                            city="الدمام والخبر"
                                            region="المنطقة الشرقية"
                                            checked={settings.dammam_enabled}
                                            onChange={(val) => handleChange('dammam_enabled', val)}
                                            bgImage="linear-gradient(to bottom right, #f8fafc, #fff7ed)"
                                        />
                                    </div>
                                </div>
                            </div>
                        )}
                        
                    </div>
                </div>
            </div>
        </div>
    );
}

// Helper Components
function SettingsIcon({ activeTab }: { activeTab: TabType }) {
    switch (activeTab) {
        case 'general': return <Shield size={32} className="text-blue-600" strokeWidth={2} />;
        case 'payments': return <Wallet size={32} className="text-emerald-500" strokeWidth={2} />;
        case 'notifications': return <Bell size={32} className="text-orange-500" strokeWidth={2} />;
        case 'coverage': return <MapPin size={32} className="text-purple-600" strokeWidth={2} />;
        default: return <Shield size={32} className="text-blue-600" strokeWidth={2} />;
    }
}

function NotificationRow({ title, desc, checked, onChange, icon, colorTheme }: { title: string, desc: string, checked: boolean, onChange: (val: boolean) => void, icon: React.ReactNode, colorTheme: string }) {
    return (
        <div className={`flex flex-col sm:flex-row items-start sm:items-center justify-between p-6 bg-white border-2 rounded-3xl transition-all duration-300 ${checked ? `border-${colorTheme}-200 shadow-lg shadow-${colorTheme}-500/5` : 'border-slate-100 hover:border-slate-200'} group`}>
            <div className="flex items-center gap-5 pr-2">
                <div className={`p-4 rounded-2xl bg-slate-50 border border-slate-100 group-hover:bg-white group-hover:shadow-sm transition-all`}>
                    {icon}
                </div>
                <div>
                    <h4 className="text-lg font-bold text-slate-800 mb-1">{title}</h4>
                    <p className="text-sm font-medium text-slate-500 leading-relaxed max-w-lg">{desc}</p>
                </div>
            </div>
            <div className="mt-4 sm:mt-0 mr-14 sm:mr-0 pl-2">
                <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" aria-label={title} className="sr-only peer" checked={checked} onChange={(e) => onChange(e.target.checked)} />
                    <div className={`w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-${colorTheme}-500`}></div>
                </label>
            </div>
        </div>
    );
}

function CoverageCard({ city, region, checked, onChange, bgImage }: { city: string, region: string, checked: boolean, onChange: (val: boolean) => void, bgImage: string }) {
    return (
        <div 
            className={`relative overflow-hidden p-6 rounded-[2rem] border-2 transition-all duration-300 flex items-center justify-between group ${
                checked ? 'border-purple-300 shadow-md shadow-purple-500/10' : 'border-slate-200 filter grayscale-[40%] hover:grayscale-0'
            }`}
            style={{ background: bgImage }}
        >
            <div className="relative z-10 flex items-center gap-4">
                <div className={`w-14 h-14 rounded-2xl flex items-center justify-center font-black text-xl shadow-sm ${checked ? 'bg-white text-purple-600' : 'bg-slate-100 text-slate-400'}`}>
                    {city.charAt(0)}
                </div>
                <div>
                    <h4 className={`text-xl font-black mb-1 ${checked ? 'text-slate-800' : 'text-slate-600'}`}>{city}</h4>
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest">{region}</p>
                </div>
            </div>
            <div className="relative z-10">
                <label className="relative inline-flex items-center cursor-pointer scale-110">
                    <input type="checkbox" aria-label={city} className="sr-only peer" checked={checked} onChange={(e) => onChange(e.target.checked)} />
                    <div className="w-12 h-6 bg-slate-300/60 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-purple-600"></div>
                </label>
            </div>
        </div>
    );
}
