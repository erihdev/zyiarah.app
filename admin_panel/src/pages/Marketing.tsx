import { Tag, Edit, Trash2, PlusCircle, Calendar, Percent } from 'lucide-react';

const mockCoupons = [
    { id: 'Z1', code: 'WELCOME2026', type: 'percentage', value: '20%', uses: 145, maxUses: 500, status: 'active', expiry: '2026-12-31' },
    { id: 'Z2', code: 'FREE_DELIVERY', type: 'fixed', value: '15 ر.س', uses: 890, maxUses: 1000, status: 'active', expiry: '2026-06-30' },
    { id: 'Z3', code: 'EID_MUBARAK', type: 'percentage', value: '50%', uses: 2000, maxUses: 2000, status: 'expired', expiry: '2025-05-15' },
];

export default function Marketing() {
    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة التسويق</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إنشاء ومتابعة كوبونات الخصم والعروض الترويجية</p>
                </div>
                <button className="flex items-center gap-2 px-6 py-3 bg-gradient-to-r from-purple-600 to-pink-600 text-white rounded-xl font-bold hover:from-purple-700 hover:to-pink-700 transition-all shadow-lg shadow-purple-500/20 hover:shadow-xl hover:-translate-y-0.5">
                    <PlusCircle size={20} />
                    إنشاء كوبون جديد
                </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex items-center justify-between group">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">الكوبونات النشطة</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">12</h3>
                    </div>
                    <div className="w-14 h-14 bg-purple-50 text-purple-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <Tag size={28} strokeWidth={2.5} />
                    </div>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex items-center justify-between group">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">كوبونات مستخدمة (هذا الشهر)</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">845</h3>
                    </div>
                    <div className="w-14 h-14 bg-pink-50 text-pink-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <Percent size={28} strokeWidth={2.5} />
                    </div>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50">
                    <h3 className="text-lg font-extrabold text-slate-800">سجل الكوبونات</h3>
                </div>

                <div className="overflow-x-auto">
                    <table className="w-full text-right border-collapse">
                        <thead>
                            <tr className="bg-slate-50 border-b border-slate-100">
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">كود الخصم</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">القيمة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الاستخدام</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الانتهاء</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-24 text-center">إجراءات</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-50">
                            {mockCoupons.map((coupon) => (
                                <tr key={coupon.id} className="hover:bg-purple-50/30 transition-colors group">
                                    <td className="px-6 py-4">
                                        <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-slate-100 rounded-lg border border-slate-200">
                                            <Tag size={14} className="text-slate-400" />
                                            <span className="font-mono font-bold text-slate-700 tracking-wider">{coupon.code}</span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 font-extrabold text-purple-600 text-lg">{coupon.value}</td>
                                    <td className="px-6 py-4">
                                        <div className="w-full max-w-[150px]">
                                            <div className="flex justify-between text-xs font-bold text-slate-500 mb-1 pb-1">
                                                <span>{coupon.uses}</span>
                                                <span>{coupon.maxUses}</span>
                                            </div>
                                            <div className="w-full h-1.5 bg-slate-100 rounded-full overflow-hidden">
                                                <div
                                                    className={`h-full rounded-full ${coupon.uses === coupon.maxUses ? 'bg-rose-500' : 'bg-purple-500'}`}
                                                    style={{ width: `${(coupon.uses / coupon.maxUses) * 100}%` }}
                                                ></div>
                                            </div>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-1.5 text-sm font-medium text-slate-500">
                                            <Calendar size={14} /> {coupon.expiry}
                                        </div>
                                    </td>
                                    <td className="px-6 py-4">
                                        {coupon.status === 'active'
                                            ? <span className="text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-md text-xs font-bold">نشط</span>
                                            : <span className="text-rose-600 bg-rose-50 px-2.5 py-1 rounded-md text-xs font-bold">منتهي</span>}
                                    </td>
                                    <td className="px-6 py-4 text-center">
                                        <div className="flex items-center justify-center gap-1">
                                            <button className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors">
                                                <Edit size={16} />
                                            </button>
                                            <button className="p-2 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors">
                                                <Trash2 size={16} />
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
}
