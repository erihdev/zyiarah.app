import { useState } from 'react';
import { ShieldAlert, Trash2, Search, CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';

const mockRequests = [
    { id: 'REQ-01', type: 'سائق', name: 'خالد السالم', phone: '+966 50 111 2222', date: '2026-03-04', reason: 'عدم الحاجة للتطبيق', status: 'pending' },
    { id: 'REQ-02', type: 'عميل', name: 'ريم العبدالله', phone: '+966 55 999 8888', date: '2026-03-03', reason: 'الأسعار مرتفعة', status: 'deleted' },
    { id: 'REQ-03', type: 'سائق', name: 'فهد الدوسري', phone: '+966 53 777 6666', date: '2026-03-01', reason: 'مشاكل في الدعم الفني', status: 'rejected' },
];

export default function AccountDeletion() {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [searchTerm, setSearchTerm] = useState('');

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
                        <ShieldAlert className="text-rose-600" />
                        طلبات حذف الحساب <span className="text-xs bg-slate-100 text-slate-500 px-2 py-0.5 rounded-full border border-slate-200">Apple Compliance</span>
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">
                        إدارة طلبات المستخدمين لحذف بياناتهم نهائياً بناءً على شروط متجر آبل 2025 المحدثة.
                    </p>
                </div>
            </div>

            <div className="bg-amber-50 border-l-4 border-amber-500 p-4 rounded-xl flex gap-3 text-amber-800">
                <AlertTriangle size={24} className="shrink-0" />
                <div>
                    <h4 className="font-bold text-sm mb-1">تنبيه قانوني (App Store Guidelines)</h4>
                    <p className="text-xs leading-relaxed font-medium">وفقاً لاشتراطات آبل، يجب الرو على طلبات الحذف خلال 15 يوماً كحد أقصى. حذف الحساب هنا سيقوم بمسح كافة بيانات العميل/السائق من قاعدة بيانات Firebase بشكل لا يمكن استرجاعه.</p>
                </div>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div className="relative w-full sm:w-96">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث برقم الجوال أو الاسم..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-rose-500/20 focus:border-rose-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                </div>

                <div className="overflow-x-auto">
                    <table className="w-full text-right border-collapse">
                        <thead>
                            <tr className="bg-slate-50 border-b border-slate-100">
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-20">رقم الطلب</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-20">النوع</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">اسم المستخدم</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الطلب</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">سبب الحذف</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-32">الحالة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 w-32 text-center">الإجراء الفوري</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-50">
                            {mockRequests.map((req) => (
                                <tr key={req.id} className="hover:bg-rose-50/20 transition-colors group">
                                    <td className="px-6 py-4 font-mono text-xs font-bold text-slate-400">{req.id}</td>
                                    <td className="px-6 py-4">
                                        <span className={`px-2 py-1 text-xs font-bold rounded-md ${req.type === 'سائق' ? 'bg-indigo-50 text-indigo-700' : 'bg-teal-50 text-teal-700'}`}>
                                            {req.type}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="font-bold text-slate-800">{req.name}</div>
                                        <div className="text-xs text-slate-500 dir-ltr font-mono mt-0.5">{req.phone}</div>
                                    </td>
                                    <td className="px-6 py-4 text-sm font-medium text-slate-500">{req.date}</td>
                                    <td className="px-6 py-4 text-sm text-slate-600 line-clamp-1">{req.reason}</td>
                                    <td className="px-6 py-4">
                                        {req.status === 'pending' && <span className="inline-flex items-center gap-1 text-amber-600 bg-amber-50 px-2.5 py-1 rounded-full text-xs font-bold border border-amber-100"><AlertTriangle size={12} />قيد المراجعة</span>}
                                        {req.status === 'deleted' && <span className="inline-flex items-center gap-1 text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-full text-xs font-bold border border-emerald-100"><CheckCircle2 size={12} />تم الحذف النهائياً</span>}
                                        {req.status === 'rejected' && <span className="inline-flex items-center gap-1 text-slate-600 bg-slate-100 px-2.5 py-1 rounded-full text-xs font-bold border border-slate-200"><XCircle size={12} />مرفوض (عليه مستحقات)</span>}
                                    </td>
                                    <td className="px-6 py-4 text-center">
                                        {req.status === 'pending' ? (
                                            <div className="flex items-center justify-center gap-2">
                                                <button className="px-3 py-1.5 bg-rose-50 hover:bg-rose-600 hover:text-white text-rose-600 border border-rose-100 rounded-lg text-xs font-bold transition-colors flex items-center gap-1.5 group/btn" title="حذف نهائي">
                                                    <Trash2 size={14} className="group-hover/btn:animate-bounce" /> مسح البيانات
                                                </button>
                                            </div>
                                        ) : (
                                            <span className="text-xs text-slate-400 font-medium">مكتمل</span>
                                        )}
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
