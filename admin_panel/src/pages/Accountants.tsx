import { DollarSign, ArrowUpRight, ArrowDownRight, TrendingUp, Download, PieChart, Wallet } from 'lucide-react';

export default function Accountants() {
    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">الإدارة المالية والمحاسبة</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">تقارير الإيرادات، العمولات المستحقة، ومراجعة المحافظ مالیًا</p>
                </div>
                <button className="flex items-center gap-2 px-6 py-3 bg-white border border-slate-200 text-slate-800 rounded-xl font-bold hover:bg-slate-50 transition-colors shadow-sm">
                    <Download size={18} className="text-blue-600" />
                    تصدير التقرير المالي (Excel)
                </button>
            </div>

            {/* Financial Overview Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-gradient-to-l from-emerald-600 to-teal-700 rounded-3xl p-6 text-white shadow-lg shadow-emerald-500/20 relative overflow-hidden">
                    <div className="absolute right-0 top-0 w-32 h-32 bg-white/10 rounded-full blur-3xl"></div>
                    <div className="relative z-10 flex justify-between items-start mb-6">
                        <div className="p-3 bg-white/20 rounded-2xl backdrop-blur-sm">
                            <DollarSign size={24} className="text-white" strokeWidth={2.5} />
                        </div>
                        <span className="flex items-center gap-1 bg-white/20 px-2 py-1 rounded-lg text-sm font-bold backdrop-blur-sm">
                            <ArrowUpRight size={16} /> 12.5%
                        </span>
                    </div>
                    <div className="relative z-10">
                        <p className="text-emerald-50 font-medium mb-1">إجمالي الإيرادات (هذا الشهر)</p>
                        <h3 className="text-4xl font-extrabold">128,450 <span className="text-lg font-bold text-emerald-200">ر.س</span></h3>
                    </div>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] relative overflow-hidden group hover:border-blue-200 transition-colors">
                    <div className="flex justify-between items-start mb-6">
                        <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl group-hover:scale-110 transition-transform">
                            <PieChart size={24} strokeWidth={2.5} />
                        </div>
                    </div>
                    <div>
                        <p className="text-slate-500 font-medium mb-1">صافي أرباح التطبيق (العمولة)</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">18,500 <span className="text-base font-bold text-slate-400">ر.س</span></h3>
                    </div>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] relative overflow-hidden group hover:border-rose-200 transition-colors">
                    <div className="flex justify-between items-start mb-6">
                        <div className="p-3 bg-rose-50 text-rose-600 rounded-2xl group-hover:scale-110 transition-transform">
                            <Wallet size={24} strokeWidth={2.5} />
                        </div>
                        <span className="flex items-center gap-1 bg-rose-50 text-rose-600 px-2 py-1 rounded-lg text-sm font-bold">
                            <ArrowDownRight size={16} /> مستحقات
                        </span>
                    </div>
                    <div>
                        <p className="text-slate-500 font-medium mb-1">مستحقات السائقين (محافظ سالبة)</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">4,230 <span className="text-base font-bold text-slate-400">ر.س</span></h3>
                    </div>
                </div>
            </div>

            {/* Financial Details Table Placeholder */}
            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 p-8">
                <h3 className="text-lg font-extrabold text-slate-800 mb-6 border-b border-slate-100 pb-4">أحدث الحركات المالية (Transactions)</h3>
                <div className="text-center py-12">
                    <TrendingUp size={48} className="mx-auto text-slate-200 mb-4" />
                    <h4 className="text-slate-500 font-bold mb-2">جاري تحميل البيانات المالية</h4>
                    <p className="text-sm text-slate-400 max-w-sm mx-auto">سيتم عرض جميع الحركات المالية وتفاصيل مدفوعات البطاقات والدفع عند الاستلام هنا مجرد ربط قاعدة البيانات.</p>
                </div>
            </div>
        </div>
    );
}
