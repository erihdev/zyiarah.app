import { useState } from 'react';
import { Shield, Key, Search, UserPlus, Trash2, Edit, UserCheck } from 'lucide-react';

const mockAdmins = [
    { id: 'ADM-01', name: 'المدير العام', email: 'admin@zyiarah.com', role: 'Super Admin', status: 'active', lastLogin: 'الآن' },
    { id: 'ADM-02', name: 'عبدالله السعد', email: 'finance@zyiarah.com', role: 'Accountant', status: 'active', lastLogin: 'منذ ساعتين' },
    { id: 'ADM-03', name: 'منى العتيبي', email: 'marketing@zyiarah.com', role: 'Marketer', status: 'active', lastLogin: 'بالأمس' },
    { id: 'ADM-04', name: 'فريق الدعم', email: 'support@zyiarah.com', role: 'Support', status: 'inactive', lastLogin: 'منذ شهر' },
];

const RoleBadge = ({ role }: { role: string }) => {
    switch (role) {
        case 'Super Admin':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 text-white bg-gradient-to-r from-slate-800 to-slate-900 rounded-lg text-xs font-bold shadow-md"><Key size={12} />مدير متميز (صلاحيات كاملة)</span>;
        case 'Accountant':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-emerald-50 text-emerald-700 border border-emerald-100 rounded-lg text-xs font-bold">محاسب مالية</span>;
        case 'Marketer':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-purple-50 text-purple-700 border border-purple-100 rounded-lg text-xs font-bold">مسؤول تسويق</span>;
        case 'Support':
            return <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-blue-50 text-blue-700 border border-blue-100 rounded-lg text-xs font-bold">موظف دعم فني</span>;
        default:
            return null;
    }
};

export default function Admins() {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [searchTerm, setSearchTerm] = useState('');

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
                        <Shield className="text-slate-800" />
                        إدارة المشرفين والصلاحيات
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">أضف موظفيك وخصص صلاحيات دخولهم للوحة التحكم بأمان</p>
                </div>
                <button className="flex items-center gap-2 px-6 py-3 bg-slate-900 text-white rounded-xl font-bold hover:bg-slate-800 transition-all shadow-lg shadow-slate-900/20 hover:shadow-xl hover:-translate-y-0.5">
                    <UserPlus size={20} />
                    إضافة مشرف جديد
                </button>
            </div>

            <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 overflow-hidden">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div className="relative w-full sm:w-80">
                        <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            placeholder="ابحث بالاسم أو البريد..."
                            className="w-full pl-4 pr-11 py-2.5 bg-white border border-slate-200 rounded-xl text-sm outline-none focus:ring-2 focus:ring-slate-500/20 focus:border-slate-500 transition-all text-slate-700"
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                        />
                    </div>
                </div>

                <div className="overflow-x-auto">
                    <table className="w-full text-right border-collapse">
                        <thead>
                            <tr className="bg-slate-50 border-b border-slate-100">
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">المشرف</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">البريد الإلكتروني</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الدور (الصلاحيات)</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">آخر دخول</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 text-center">إجراءات</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-50">
                            {mockAdmins.map((admin) => (
                                <tr key={admin.id} className="hover:bg-slate-50/50 transition-colors group">
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-3">
                                            <div className={`w-10 h-10 rounded-xl flex items-center justify-center font-bold border ${admin.role === 'Super Admin' ? 'bg-slate-900 text-white border-slate-800' : 'bg-slate-100 text-slate-600 border-slate-200'}`}>
                                                {admin.name.substring(0, 1)}
                                            </div>
                                            <span className="font-bold text-slate-800">{admin.name}</span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 text-slate-600 font-medium dir-ltr text-right">{admin.email}</td>
                                    <td className="px-6 py-4"><RoleBadge role={admin.role} /></td>
                                    <td className="px-6 py-4 text-sm font-medium text-slate-500">{admin.lastLogin}</td>
                                    <td className="px-6 py-4">
                                        {admin.status === 'active'
                                            ? <span className="inline-flex items-center gap-1 text-emerald-600 font-bold text-xs"><UserCheck size={14} /> نشط</span>
                                            : <span className="text-slate-400 font-bold text-xs">غير نشط</span>}
                                    </td>
                                    <td className="px-6 py-4 text-center">
                                        <div className="flex items-center justify-center gap-2">
                                            {admin.role !== 'Super Admin' && (
                                                <>
                                                    <button className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors">
                                                        <Edit size={16} />
                                                    </button>
                                                    <button className="p-2 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors">
                                                        <Trash2 size={16} />
                                                    </button>
                                                </>
                                            )}
                                            {admin.role === 'Super Admin' && (
                                                <span className="text-xs text-slate-400 font-bold bg-slate-100 px-2 py-1 rounded">حساب المالك</span>
                                            )}
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
