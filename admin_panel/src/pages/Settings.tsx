import { Save, Bell, Shield, Wallet, MapPin, Search, Smartphone } from 'lucide-react';

export default function Settings() {
    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex items-center justify-between mb-2">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إعدادات النظام</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إدارة الإعدادات العامة وتكوينات التطبيق</p>
                </div>
                <button className="flex items-center space-x-2 space-x-reverse bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white px-6 py-3 rounded-xl font-bold transition-all shadow-lg shadow-blue-500/20 hover:shadow-xl hover:shadow-blue-500/30 hover:-translate-y-0.5">
                    <Save size={20} />
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
                            <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 bg-blue-50/80 text-blue-600 rounded-2xl font-bold transition-colors group relative overflow-hidden">
                                <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-blue-600 rounded-l-full shadow-[0_0_10px_rgba(37,99,235,0.5)]"></div>
                                <Shield size={20} strokeWidth={2.5} className="mr-1" />
                                <span>عام وأمان</span>
                            </button>
                            <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 text-slate-500 hover:text-slate-900 hover:bg-slate-50 rounded-2xl font-medium transition-colors">
                                <Wallet size={20} className="mr-1" />
                                <span>المدفوعات والعمولات</span>
                            </button>
                            <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 text-slate-500 hover:text-slate-900 hover:bg-slate-50 rounded-2xl font-medium transition-colors">
                                <Bell size={20} className="mr-1" />
                                <span>الإشعارات الآلية</span>
                            </button>
                            <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3.5 text-slate-500 hover:text-slate-900 hover:bg-slate-50 rounded-2xl font-medium transition-colors">
                                <MapPin size={20} className="mr-1" />
                                <span>مناطق التغطية</span>
                            </button>
                        </nav>
                    </div>
                </div>

                {/* Settings Content Area */}
                <div className="flex-1 w-full bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                    <div className="px-8 py-6 border-b border-slate-100 bg-white/50 backdrop-blur-sm">
                        <h3 className="text-xl font-extrabold text-slate-800">إعدادات عامة وأمان</h3>
                        <p className="text-sm text-slate-400 font-medium mt-1">تكوين إعدادات الوصول والأمان الرئيسية للنظام</p>
                    </div>

                    <div className="p-8 space-y-8">

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                            {/* API Keys Blocks */}
                            <div className="space-y-2 group">
                                <label className="block text-sm font-extrabold text-slate-700">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                                <div className="relative">
                                    <input
                                        type="password"
                                        value="xxxxxxxxxxxxxxxxxxxxxxxxxx"
                                        disabled
                                        className="w-full bg-[#f8fafc] border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-slate-300 transition-colors"
                                    />
                                    <button className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors">مراجعة</button>
                                </div>
                                <p className="text-xs text-slate-400 font-medium leading-relaxed">لأسباب أمنية لا يمكن عرض المفتاح كاملاً. لتغييره يرجى التواصل مع الدعم التقني.</p>
                            </div>

                            <div className="space-y-2 group">
                                <label className="block text-sm font-extrabold text-slate-700">مفتاح Firebase Admin</label>
                                <div className="relative">
                                    <input
                                        type="password"
                                        value="xxxxxxxxxxxxxxxxxxxxxxxxxx"
                                        disabled
                                        className="w-full bg-[#f8fafc] border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-slate-300 transition-colors"
                                    />
                                    <button className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors">مراجعة</button>
                                </div>
                                <p className="text-xs text-slate-400 font-medium leading-relaxed">مفتاح الاتصال الخاص بالخدمات السحابية وقاعدة البيانات.</p>
                            </div>
                        </div>

                        <hr className="border-slate-100/80" />

                        {/* App Store Compliance */}
                        <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 relative overflow-hidden">
                            <h4 className="font-extrabold text-slate-800 text-lg mb-4 flex items-center gap-2"><Smartphone size={20} className="text-blue-600" /> توافق المتاجر وإصدارات التطبيق</h4>

                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                <div className="space-y-2 group md:col-span-2">
                                    <label className="block text-sm font-extrabold text-slate-700">إجبار المستخدمين والسائقين على التحديث (Force Update)</label>
                                    <div className="flex gap-4">
                                        <div className="flex-1">
                                            <input
                                                type="text"
                                                defaultValue="v2.1.0"
                                                className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left font-mono"
                                                dir="ltr"
                                            />
                                        </div>
                                        <div className="flex items-center">
                                            <label className="relative inline-flex items-center cursor-pointer">
                                                <input type="checkbox" className="sr-only peer" defaultChecked />
                                                <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                                                <span className="mr-3 text-sm font-bold text-slate-700">مُفعل</span>
                                            </label>
                                        </div>
                                    </div>
                                    <p className="text-xs text-slate-500 font-medium leading-relaxed">أدخل الحد الأدنى للإصدار المسموح به. أي مستخدم لديه إصدار أقدم سيُجبر على فتح المتجر وتحديث التطبيق.</p>
                                </div>
                                <div className="space-y-2 group">
                                    <label className="block text-sm font-extrabold text-slate-700">رابط الشروط والأحكام (Terms)</label>
                                    <div className="relative">
                                        <input
                                            type="url"
                                            defaultValue="https://zyiarah.com/terms"
                                            className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left dir-ltr"
                                            dir="ltr"
                                        />
                                    </div>
                                </div>
                                <div className="space-y-2 group">
                                    <label className="block text-sm font-extrabold text-slate-700">رابط الدعم الفني والمساعدة</label>
                                    <div className="relative">
                                        <input
                                            type="url"
                                            defaultValue="https://zyiarah.com/support"
                                            className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all text-left dir-ltr"
                                            dir="ltr"
                                        />
                                    </div>
                                </div>
                                <div className="space-y-2 group md:col-span-2">
                                    <label className="block text-sm font-extrabold text-slate-700">نص سياسة الخصوصية (Privacy Policy)</label>
                                    <div className="relative">
                                        <textarea
                                            rows={6}
                                            defaultValue="نحن في تطبيق زيارة نلتزم بحماية بياناتك الشخصية ومشاركة الموقع الجغرافي للضرورة فقط طبقا لسياسات آبل وجوجل..."
                                            className="w-full bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all resize-y leading-relaxed"
                                        />
                                    </div>
                                    <p className="text-xs text-slate-500 font-medium leading-relaxed">ستنعكس هذه السياسة فوراً داخل شاشة الإعدادات وحذف الحساب في تطبيق الجوال. وجود سياسة واضحة شرط أساسي لاجتياز مراجعة App Store.</p>
                                </div>
                            </div>
                        </div>

                        <hr className="border-slate-100/80" />

                        {/* Danger Zone / Maintenance */}
                        <div className="bg-gradient-to-l from-orange-50/80 to-red-50/50 rounded-2xl p-6 border border-orange-100/80 flex flex-col sm:flex-row sm:items-center justify-between gap-4 relative overflow-hidden">
                            <div className="absolute right-0 top-0 w-32 h-32 bg-orange-500/10 rounded-full blur-3xl"></div>
                            <div className="flex items-start space-x-4 space-x-reverse relative z-10">
                                <div className="bg-white p-3 rounded-xl shadow-sm border border-orange-100 text-orange-600">
                                    <Shield size={24} strokeWidth={2.5} />
                                </div>
                                <div>
                                    <h4 className="font-extrabold text-orange-900 text-lg">وضع الصيانة الداخلي</h4>
                                    <p className="text-orange-700/80 text-sm mt-1 max-w-lg leading-relaxed font-medium">عند تفعيل وضع الصيانة، سيتم إيقاف النظام مؤقتاً ولن يتمكن العملاء أو السائقين من تقديم أو استلام طلبات جديدة.</p>
                                </div>
                            </div>
                            <div className="relative z-10 sm:min-w-fit">
                                <button className="w-full sm:w-auto bg-white border-2 border-orange-200 text-orange-700 font-extrabold px-6 py-3 rounded-xl hover:bg-orange-50 hover:border-orange-300 transition-all shadow-sm">
                                    تفعيل الصيانة
                                </button>
                            </div>
                        </div>

                    </div>
                </div>
            </div>
        </div>
    );
}
