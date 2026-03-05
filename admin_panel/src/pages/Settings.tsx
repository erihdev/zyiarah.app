import { useState, useEffect } from 'react';
import { Save, Bell, Shield, Wallet, MapPin, Search, Smartphone, Loader2 } from 'lucide-react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '../services/firebase';

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
            alert("تم حفظ الإعدادات بنجاح!");
        } catch (error) {
            console.error("Error saving settings:", error);
            alert("حدث خطأ أثناء حفظ الإعدادات.");
        } finally {
            setIsSaving(false);
        }
    };

    const handleChange = (key: keyof SystemSettings, value: any) => {
        setSettings(prev => ({ ...prev, [key]: value }));
    };

    if (isLoading) {
        return <div className="flex h-full items-center justify-center p-20 animate-pulse text-slate-500 font-bold">جاري تحميل الإعدادات...</div>;
    }

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex items-center justify-between mb-2">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إعدادات النظام</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إدارة الإعدادات العامة وتكوينات التطبيق</p>
                </div>
                <button
                    onClick={handleSave}
                    disabled={isSaving}
                    className="flex items-center space-x-2 space-x-reverse bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white px-6 py-3 rounded-xl font-bold transition-all shadow-lg shadow-blue-500/20 hover:shadow-xl hover:shadow-blue-500/30 hover:-translate-y-0.5 disabled:opacity-75 disabled:cursor-not-allowed"
                >
                    {isSaving ? <Loader2 size={20} className="animate-spin" /> : <Save size={20} />}
                    <span>حفظ التغييرات</span>
                </button>
            </div>

            <div className="flex flex-col xl:flex-row gap-8 items-start">

                {/* Settings Navigation Sidebar */}
                <div className="w-full xl:w-80 flex-shrink-0 space-y-2">
                    <div className="bg-white rounded-[24px] p-4 shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 sticky top-32">

                        <div className="mb-4 relative">
                            <Search size={16} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" />
                            <input
                                type="text"
                                placeholder="بحث في الإعدادات..."
                                className="w-full bg-slate-50 border border-slate-200 text-sm rounded-xl py-2.5 pr-10 pl-4 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-slate-700"
                            />
                        </div>

                        <nav className="space-y-1">
                            <button
                                onClick={() => setActiveTab('general')}
                                className={`w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 rounded-2xl font-bold transition-colors group relative overflow-hidden ${activeTab === 'general' ? 'bg-blue-50/80 text-blue-600' : 'text-slate-500 hover:text-slate-900 hover:bg-slate-50 font-medium'}`}
                            >
                                {activeTab === 'general' && <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-blue-600 rounded-l-full shadow-[0_0_10px_rgba(37,99,235,0.5)]"></div>}
                                <Shield size={20} strokeWidth={activeTab === 'general' ? 2.5 : 2} className="mr-1" />
                                <span>عام وأمان</span>
                            </button>
                            <button
                                onClick={() => setActiveTab('payments')}
                                className={`w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 rounded-2xl font-bold transition-colors group relative overflow-hidden ${activeTab === 'payments' ? 'bg-emerald-50/80 text-emerald-600' : 'text-slate-500 hover:text-slate-900 hover:bg-slate-50 font-medium'}`}
                            >
                                {activeTab === 'payments' && <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-emerald-600 rounded-l-full shadow-[0_0_10px_rgba(16,185,129,0.5)]"></div>}
                                <Wallet size={20} strokeWidth={activeTab === 'payments' ? 2.5 : 2} className="mr-1" />
                                <span>المدفوعات والعمولات</span>
                            </button>
                            <button
                                onClick={() => setActiveTab('notifications')}
                                className={`w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 rounded-2xl font-bold transition-colors group relative overflow-hidden ${activeTab === 'notifications' ? 'bg-orange-50/80 text-orange-600' : 'text-slate-500 hover:text-slate-900 hover:bg-slate-50 font-medium'}`}
                            >
                                {activeTab === 'notifications' && <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-orange-600 rounded-l-full shadow-[0_0_10px_rgba(234,88,12,0.5)]"></div>}
                                <Bell size={20} strokeWidth={activeTab === 'notifications' ? 2.5 : 2} className="mr-1" />
                                <span>الإشعارات الآلية</span>
                            </button>
                            <button
                                onClick={() => setActiveTab('coverage')}
                                className={`w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 rounded-2xl font-bold transition-colors group relative overflow-hidden ${activeTab === 'coverage' ? 'bg-indigo-50/80 text-indigo-600' : 'text-slate-500 hover:text-slate-900 hover:bg-slate-50 font-medium'}`}
                            >
                                {activeTab === 'coverage' && <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-indigo-600 rounded-l-full shadow-[0_0_10px_rgba(79,70,229,0.5)]"></div>}
                                <MapPin size={20} strokeWidth={activeTab === 'coverage' ? 2.5 : 2} className="mr-1" />
                                <span>مناطق التغطية</span>
                            </button>
                        </nav>
                    </div>
                </div>

                {/* Settings Content Area */}
                <div className="flex-1 w-full bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden min-h-[500px]">
                    {activeTab === 'general' && (
                        <>
                            <div className="px-8 py-6 border-b border-slate-100 bg-white/50 backdrop-blur-sm">
                                <h3 className="text-xl font-extrabold text-slate-800">إعدادات عامة وأمان</h3>
                                <p className="text-sm text-slate-400 font-medium mt-1">تكوين إعدادات الوصول والأمان الرئيسية للنظام</p>
                            </div>

                            <div className="p-8 space-y-8">
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                                    <div className="space-y-2 group">
                                        <label className="block text-sm font-extrabold text-slate-700">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                                        <div className="relative">
                                            <input type="password" value="xxxxxxxxxxxxxxxxxxxxxxxxxx" disabled className="w-full bg-[#f8fafc] border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-slate-300 transition-colors" />
                                            <button className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors">مراجعة</button>
                                        </div>
                                        <p className="text-xs text-slate-400 font-medium leading-relaxed">لأسباب أمنية لا يمكن عرض المفتاح كاملاً. لتغييره يرجى التواصل مع الدعم التقني.</p>
                                    </div>
                                    <div className="space-y-2 group">
                                        <label className="block text-sm font-extrabold text-slate-700">مفتاح Firebase Admin</label>
                                        <div className="relative">
                                            <input type="password" value="xxxxxxxxxxxxxxxxxxxxxxxxxx" disabled className="w-full bg-[#f8fafc] border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-slate-300 transition-colors" />
                                            <button className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors">مراجعة</button>
                                        </div>
                                        <p className="text-xs text-slate-400 font-medium leading-relaxed">مفتاح الاتصال الخاص بالخدمات السحابية وقاعدة البيانات.</p>
                                    </div>
                                </div>

                                <hr className="border-slate-100/80" />

                                <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 relative overflow-hidden">
                                    <h4 className="font-extrabold text-slate-800 text-lg mb-4 flex items-center gap-2"><Smartphone size={20} className="text-blue-600" /> توافق المتاجر وإصدارات التطبيق</h4>
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                        <div className="space-y-2 group md:col-span-2">
                                            <label className="block text-sm font-extrabold text-slate-700">إجبار المستخدمين والسائقين على التحديث (Force Update)</label>
                                            <div className="flex gap-4">
                                                <div className="flex-1">
                                                    <input
                                                        type="text"
                                                        value={settings.force_update_version}
                                                        onChange={(e) => handleChange('force_update_version', e.target.value)}
                                                        className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left font-mono"
                                                        dir="ltr"
                                                    />
                                                </div>
                                                <div className="flex items-center">
                                                    <label className="relative inline-flex items-center cursor-pointer">
                                                        <input type="checkbox" className="sr-only peer" checked={settings.force_update_enabled} onChange={(e) => handleChange('force_update_enabled', e.target.checked)} />
                                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                                                        <span className="mr-3 text-sm font-bold text-slate-700">مُفعل</span>
                                                    </label>
                                                </div>
                                            </div>
                                            <p className="text-xs text-slate-500 font-medium leading-relaxed">أدخل الحد الأدنى للإصدار المسموح به. أي مستخدم لديه إصدار أقدم سيُجبر على فتح المتجر وتحديث التطبيق.</p>
                                        </div>
                                        <div className="space-y-2 group">
                                            <label className="block text-sm font-extrabold text-slate-700">رابط الشروط والأحكام (Terms)</label>
                                            <input
                                                type="url"
                                                value={settings.terms_url}
                                                onChange={(e) => handleChange('terms_url', e.target.value)}
                                                className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left"
                                                dir="ltr"
                                            />
                                        </div>
                                        <div className="space-y-2 group">
                                            <label className="block text-sm font-extrabold text-slate-700">رابط الدعم الفني والمساعدة</label>
                                            <input
                                                type="url"
                                                value={settings.support_url}
                                                onChange={(e) => handleChange('support_url', e.target.value)}
                                                className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left"
                                                dir="ltr"
                                            />
                                        </div>
                                        <div className="space-y-2 group md:col-span-2">
                                            <label className="block text-sm font-extrabold text-slate-700">نص سياسة الخصوصية (Privacy Policy)</label>
                                            <textarea
                                                rows={5}
                                                value={settings.privacy_policy}
                                                onChange={(e) => handleChange('privacy_policy', e.target.value)}
                                                className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all resize-y leading-relaxed"
                                            />
                                        </div>
                                    </div>
                                </div>

                                <hr className="border-slate-100/80" />

                                <div className={`rounded-2xl p-6 border flex flex-col sm:flex-row sm:items-center justify-between gap-4 relative overflow-hidden transition-colors ${settings.maintenance_mode ? 'bg-gradient-to-l from-orange-50/80 to-red-50/50 border-orange-200' : 'bg-slate-50 border-slate-200'}`}>
                                    {settings.maintenance_mode && <div className="absolute right-0 top-0 w-32 h-32 bg-orange-500/10 rounded-full blur-3xl"></div>}
                                    <div className="flex items-start space-x-4 space-x-reverse relative z-10">
                                        <div className={`p-3 rounded-xl shadow-sm border ${settings.maintenance_mode ? 'bg-white border-orange-100 text-orange-600' : 'bg-slate-100 border-slate-200 text-slate-500'}`}>
                                            <Shield size={24} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h4 className={`font-extrabold text-lg ${settings.maintenance_mode ? 'text-orange-900' : 'text-slate-700'}`}>وضع الصيانة الداخلي</h4>
                                            <p className={`text-sm mt-1 max-w-lg leading-relaxed font-medium ${settings.maintenance_mode ? 'text-orange-700/80' : 'text-slate-500'}`}>عند تفعيل وضع الصيانة، سيتم إيقاف النظام مؤقتاً ولن يتمكن العملاء أو السائقين من تقديم أو استلام طلبات جديدة.</p>
                                        </div>
                                    </div>
                                    <div className="relative z-10 sm:min-w-fit">
                                        <button
                                            onClick={() => handleChange('maintenance_mode', !settings.maintenance_mode)}
                                            className={`w-full sm:w-auto font-extrabold px-6 py-3 rounded-xl transition-all shadow-sm border-2 ${settings.maintenance_mode ? 'bg-white border-orange-200 text-orange-700 hover:bg-orange-50' : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'}`}
                                        >
                                            {settings.maintenance_mode ? 'إيقاف الصيانة' : 'تفعيل الصيانة'}
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </>
                    )}

                    {activeTab === 'payments' && (
                        <>
                            <div className="px-8 py-6 border-b border-slate-100 bg-emerald-50/30 backdrop-blur-sm">
                                <h3 className="text-xl font-extrabold text-emerald-800">المدفوعات والعمولات</h3>
                                <p className="text-sm text-emerald-600/70 font-medium mt-1">إعداد عمولات التطبيق والضرائب وحدود المحفظة المالية للسائقين.</p>
                            </div>
                            <div className="p-8 space-y-8">
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                                    <div className="space-y-2 group">
                                        <label className="block text-sm font-extrabold text-slate-700">نسبة عمولة التطبيق (%)</label>
                                        <input
                                            type="number"
                                            value={settings.commission_rate}
                                            onChange={(e) => handleChange('commission_rate', Number(e.target.value))}
                                            className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all text-left"
                                            dir="ltr"
                                        />
                                        <p className="text-xs text-slate-400 font-medium">النسبة المئوية التي يستقطعها التطبيق من كل طلب مكتمل.</p>
                                    </div>
                                    <div className="space-y-2 group">
                                        <label className="block text-sm font-extrabold text-slate-700">نسبة ضريبة القيمة المضافة (VAT %)</label>
                                        <input
                                            type="number"
                                            value={settings.vat_rate}
                                            onChange={(e) => handleChange('vat_rate', Number(e.target.value))}
                                            className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all text-left"
                                            dir="ltr"
                                        />
                                        <p className="text-xs text-slate-400 font-medium">نسبة الضريبة المعمول بها في المملكة حالياً.</p>
                                    </div>
                                    <div className="space-y-2 group md:col-span-2">
                                        <label className="block text-sm font-extrabold text-slate-700">الحد الأدنى لمحفظة السائق بالسالب (ر.س)</label>
                                        <input
                                            type="number"
                                            value={settings.min_wallet_balance}
                                            onChange={(e) => handleChange('min_wallet_balance', Number(e.target.value))}
                                            className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 transition-all text-left"
                                            dir="ltr"
                                        />
                                        <p className="text-xs text-slate-400 font-medium">إذا وصل رصيد السائق إلى هذا الحد (مديونية)، سيتم إيقاف حسابه تلقائياً حتى يقوم بالسداد.</p>
                                    </div>
                                </div>
                            </div>
                        </>
                    )}

                    {activeTab === 'notifications' && (
                        <>
                            <div className="px-8 py-6 border-b border-slate-100 bg-orange-50/30 backdrop-blur-sm">
                                <h3 className="text-xl font-extrabold text-orange-800">الإشعارات الآلية</h3>
                                <p className="text-sm text-orange-600/70 font-medium mt-1">التحكم في تنبيهات ورسائل النظام التلقائية الموجهة للعملاء والسائقين.</p>
                            </div>
                            <div className="p-8 space-y-6">
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-sm">رسالة SMS لمعلومات الطلب للعميل</h4>
                                        <p className="text-xs text-slate-500 mt-1">إرسال تفاصيل الفاتورة عبر رسالة نصية بعد تأكيد الدفع.</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.sms_on_order} onChange={(e) => handleChange('sms_on_order', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-orange-500"></div>
                                    </label>
                                </div>
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-sm">تنبيه Push Notification للسائقين</h4>
                                        <p className="text-xs text-slate-500 mt-1">إرسال إشعار فوري للسائقين في النطاق عند توفر طلب جديد.</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.push_on_assign} onChange={(e) => handleChange('push_on_assign', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-orange-500"></div>
                                    </label>
                                </div>
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div>
                                        <h4 className="font-extrabold text-slate-800 text-sm">تنبيه Push Notification للعميل (اكتمال الطلب)</h4>
                                        <p className="text-xs text-slate-500 mt-1">إرسال إشعار فوري لتقييم الخدمة بعد إنهاء السائق للطلب.</p>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.push_on_completed} onChange={(e) => handleChange('push_on_completed', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-orange-500"></div>
                                    </label>
                                </div>
                            </div>
                        </>
                    )}

                    {activeTab === 'coverage' && (
                        <>
                            <div className="px-8 py-6 border-b border-slate-100 bg-indigo-50/30 backdrop-blur-sm">
                                <h3 className="text-xl font-extrabold text-indigo-800">مناطق التغطية</h3>
                                <p className="text-sm text-indigo-600/70 font-medium mt-1">تفعيل أو إيقاف المدن والمناطق المدعومة في التطبيق.</p>
                            </div>
                            <div className="p-8 space-y-6">
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div className="flex items-center gap-3">
                                        <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold">الرياض</div>
                                        <div>
                                            <h4 className="font-extrabold text-slate-800 text-sm">منطقة الرياض</h4>
                                            <p className="text-xs text-slate-500 mt-1">دعم الطلبات بكامل نطاق المنطقة الوسطى.</p>
                                        </div>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.riyadh_enabled} onChange={(e) => handleChange('riyadh_enabled', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                                    </label>
                                </div>
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div className="flex items-center gap-3">
                                        <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold">جدة</div>
                                        <div>
                                            <h4 className="font-extrabold text-slate-800 text-sm">منطقة مكة المكرمة (جدة)</h4>
                                            <p className="text-xs text-slate-500 mt-1">دعم الطلبات في نطاق المنطقة الغربية.</p>
                                        </div>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.jeddah_enabled} onChange={(e) => handleChange('jeddah_enabled', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                                    </label>
                                </div>
                                <div className="flex items-center justify-between p-4 bg-slate-50 border border-slate-100 rounded-xl">
                                    <div className="flex items-center gap-3">
                                        <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold">الشرقية</div>
                                        <div>
                                            <h4 className="font-extrabold text-slate-800 text-sm">المنطقة الشرقية (الدمام)</h4>
                                            <p className="text-xs text-slate-500 mt-1">دعم الطلبات في نطاق الدمام والخبر والظهران.</p>
                                        </div>
                                    </div>
                                    <label className="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" className="sr-only peer" checked={settings.dammam_enabled} onChange={(e) => handleChange('dammam_enabled', e.target.checked)} />
                                        <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                                    </label>
                                </div>
                            </div>
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}
