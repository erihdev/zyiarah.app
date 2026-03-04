import { Save, Bell, Shield, Wallet, MapPin } from 'lucide-react';

export default function Settings() {
    return (
        <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
            <div className="flex items-center justify-between mb-8">
                <div>
                    <h2 className="text-2xl font-bold text-slate-800">إعدادات النظام</h2>
                    <p className="text-slate-500">إدارة الإعدادات العامة وتكوينات التطبيق</p>
                </div>
                <button className="flex items-center space-x-2 space-x-reverse bg-blue-600 hover:bg-blue-700 text-white px-6 py-2.5 rounded-xl font-bold transition-colors shadow-lg shadow-blue-500/30">
                    <Save size={20} />
                    <span>حفظ التغييرات</span>
                </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">

                {/* Settings Navigation */}
                <div className="col-span-1 space-y-2">
                    <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3 bg-white text-blue-600 rounded-xl font-bold shadow-sm border border-blue-100">
                        <Shield size={20} />
                        <span>عام وأمان</span>
                    </button>
                    <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3 text-slate-600 hover:bg-white rounded-xl font-medium transition-colors">
                        <Wallet size={20} />
                        <span>المدفوعات والعمولات</span>
                    </button>
                    <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3 text-slate-600 hover:bg-white rounded-xl font-medium transition-colors">
                        <Bell size={20} />
                        <span>الإشعارات الآلية</span>
                    </button>
                    <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3 text-slate-600 hover:bg-white rounded-xl font-medium transition-colors">
                        <MapPin size={20} />
                        <span>مناطق التغطية</span>
                    </button>
                </div>

                {/* Settings Content */}
                <div className="col-span-1 md:col-span-3 bg-white rounded-2xl shadow-sm border border-slate-100 p-8">

                    <h3 className="text-xl font-bold text-slate-800 mb-6 border-b border-slate-100 pb-4">إعدادات عامة وأمان</h3>

                    <div className="space-y-8">

                        {/* API Keys Placeholder */}
                        <div>
                            <label className="block text-sm font-bold text-slate-700 mb-2">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                            <input
                                type="password"
                                value="xxxxxxxxxxxxxxxxxxxxxxxxxx"
                                disabled
                                className="w-full bg-slate-50 border border-slate-200 text-slate-500 text-sm rounded-xl px-4 py-3 outline-none"
                            />
                            <p className="mt-1 text-xs text-slate-400">لأسباب أمنية لا يمكن عرض المفتاح كاملاً. لتغييره يرجى التواصل مع الدعم التقني.</p>
                        </div>

                        <div>
                            <label className="block text-sm font-bold text-slate-700 mb-2">مفتاح Firebase Admin</label>
                            <input
                                type="password"
                                value="xxxxxxxxxxxxxxxxxxxxxxxxxx"
                                disabled
                                className="w-full bg-slate-50 border border-slate-200 text-slate-500 text-sm rounded-xl px-4 py-3 outline-none"
                            />
                        </div>

                        <div className="bg-orange-50 rounded-xl p-4 border border-orange-100 flex items-start space-x-4 space-x-reverse">
                            <Shield className="text-orange-500 shrink-0 mt-1" size={24} />
                            <div>
                                <h4 className="font-bold text-orange-800">وضع الصيانة</h4>
                                <p className="text-orange-600 text-sm mt-1">عند تفعيل وضع الصيانة لن يتمكن العملاء أو السائقين من استخدام التطبيق.</p>
                                <button className="mt-3 bg-white border border-orange-200 text-orange-700 px-4 py-1.5 rounded-lg text-sm font-bold hover:bg-orange-100 transition-colors">
                                    تفعيل وضع الصيانة
                                </button>
                            </div>
                        </div>

                    </div>
                </div>
            </div>
        </div>
    );
}
