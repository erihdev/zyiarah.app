import { useState, useEffect } from 'react';
import { Tag, Trash2, PlusCircle, Calendar, Percent, X, Loader2 } from 'lucide-react';
import { collection, onSnapshot, addDoc, deleteDoc, doc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '../services/firebase';

interface PromoCode {
    id: string;
    code: string;
    type: 'percentage' | 'fixed';
    value: number;
    uses: number;
    maxUses: number;
    status: 'active' | 'expired';
    expiry: string;
    createdAt?: { toDate: () => Date };
}

export default function Marketing() {
    const [coupons, setCoupons] = useState<PromoCode[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [isAddModalOpen, setIsAddModalOpen] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Form State
    const [newCode, setNewCode] = useState('');
    const [newType, setNewType] = useState<'percentage' | 'fixed'>('percentage');
    const [newValue, setNewValue] = useState<number>(0);
    const [newMaxUses, setNewMaxUses] = useState<number>(100);
    const [newExpiry, setNewExpiry] = useState('');

    useEffect(() => {
        const unsubscribe = onSnapshot(collection(db, 'promo_codes'), (snapshot) => {
            const fetchedCoupons = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            } as PromoCode));

            // Sort by creation date or expiry
            fetchedCoupons.sort((a, b) => new Date(b.expiry).getTime() - new Date(a.expiry).getTime());

            setCoupons(fetchedCoupons);
            setIsLoading(false);
        }, (error) => {
            console.error("Error fetching promo codes: ", error);
            setIsLoading(false);
        });

        return () => unsubscribe();
    }, []);

    const handleAddCoupon = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsSubmitting(true);
        try {
            await addDoc(collection(db, 'promo_codes'), {
                code: newCode.toUpperCase(),
                type: newType,
                value: newValue,
                uses: 0,
                maxUses: newMaxUses,
                status: 'active',
                expiry: newExpiry,
                createdAt: serverTimestamp(),
            });
            setIsAddModalOpen(false);
            // Reset form
            setNewCode('');
            setNewType('percentage');
            setNewValue(0);
            setNewMaxUses(100);
            setNewExpiry('');
        } catch (error) {
            console.error("Error adding promo code: ", error);
            alert("حدث خطأ أثناء إضافة الكوبون.");
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleDelete = async (id: string) => {
        if (window.confirm("هل أنت متأكد من حذف هذا الكوبون؟")) {
            try {
                await deleteDoc(doc(db, 'promo_codes', id));
            } catch (error) {
                console.error("Error deleting promo code: ", error);
                alert("حدث خطأ أثناء الحذف.");
            }
        }
    };

    const toggleStatus = async (coupon: PromoCode) => {
        try {
            const newStatus = coupon.status === 'active' ? 'expired' : 'active';
            await updateDoc(doc(db, 'promo_codes', coupon.id), {
                status: newStatus
            });
        } catch (error) {
            console.error("Error updating status: ", error);
        }
    };

    const activeCouponsCount = coupons.filter(c => c.status === 'active').length;
    const totalUsesThisMonth = coupons.reduce((sum, c) => sum + c.uses, 0); // Simplified for now, should calculate based on real usage logs later

    if (isLoading) {
        return <div className="flex h-full items-center justify-center p-20 animate-pulse text-slate-500 font-bold">جاري تحميل البيانات...</div>;
    }

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة التسويق</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إنشاء ومتابعة كوبونات الخصم والعروض الترويجية</p>
                </div>
                <button
                    onClick={() => setIsAddModalOpen(true)}
                    className="flex items-center gap-2 px-6 py-3 bg-gradient-to-r from-purple-600 to-pink-600 text-white rounded-xl font-bold hover:from-purple-700 hover:to-pink-700 transition-all shadow-lg shadow-purple-500/20 hover:shadow-xl hover:-translate-y-0.5"
                >
                    <PlusCircle size={20} />
                    إنشاء كوبون جديد
                </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex items-center justify-between group">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">الكوبونات النشطة</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">{activeCouponsCount}</h3>
                    </div>
                    <div className="w-14 h-14 bg-purple-50 text-purple-600 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform">
                        <Tag size={28} strokeWidth={2.5} />
                    </div>
                </div>

                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex items-center justify-between group">
                    <div>
                        <p className="text-sm font-bold text-slate-500 mb-1">إجمالي الاستخدام</p>
                        <h3 className="text-3xl font-extrabold text-slate-800">{totalUsesThisMonth}</h3>
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
                    <table className="w-full text-right border-collapse min-w-[800px]">
                        <thead>
                            <tr className="bg-slate-50 border-b border-slate-100">
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">كود الخصم</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">القيمة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الاستخدام</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">تاريخ الانتهاء</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4">الحالة</th>
                                <th className="font-bold text-slate-500 text-xs uppercase px-6 py-4 text-center">إجراءات</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-50">
                            {coupons.length === 0 ? (
                                <tr>
                                    <td colSpan={6} className="px-6 py-12 text-center text-slate-400 font-medium">لا توجد كوبونات خصم حالياً.</td>
                                </tr>
                            ) : coupons.map((coupon) => (
                                <tr key={coupon.id} className={`transition-colors group ${coupon.status === 'expired' ? 'bg-slate-50/50 opacity-75' : 'hover:bg-purple-50/30'}`}>
                                    <td className="px-6 py-4">
                                        <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-slate-100 rounded-lg border border-slate-200">
                                            <Tag size={14} className="text-slate-400" />
                                            <span className="font-mono font-bold text-slate-700 tracking-wider text-sm">{coupon.code}</span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 font-extrabold text-purple-600">
                                        {coupon.type === 'percentage' ? `${coupon.value}%` : `${coupon.value} ر.س`}
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="w-full max-w-[150px]">
                                            <div className="flex justify-between text-xs font-bold text-slate-500 mb-1 pb-1">
                                                <span>{coupon.uses}</span>
                                                <span>{coupon.maxUses > 9999 ? '∞' : coupon.maxUses}</span>
                                            </div>
                                            <div className="w-full h-1.5 bg-slate-100 rounded-full overflow-hidden">
                                                <div
                                                    className={`h-full rounded-full transition-all duration-500 ${coupon.uses >= coupon.maxUses ? 'bg-rose-500' : 'bg-purple-500'}`}
                                                    style={{ width: `${Math.min((coupon.uses / coupon.maxUses) * 100, 100)}%` }}
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
                                        <button
                                            type="button"
                                            title="تغيير الحالة"
                                            onClick={() => toggleStatus(coupon)}
                                            className="transition-transform hover:scale-105"
                                        >
                                            {coupon.status === 'active'
                                                ? <span className="text-emerald-600 bg-emerald-50 border border-emerald-100 px-3 py-1 rounded-full text-xs font-extrabold">نشط</span>
                                                : <span className="text-rose-600 bg-rose-50 border border-rose-100 px-3 py-1 rounded-full text-xs font-extrabold">منتهي</span>}
                                        </button>
                                    </td>
                                    <td className="px-6 py-4 text-center">
                                        <div className="flex items-center justify-center gap-1">
                                            <button
                                                type="button"
                                                title="حذف الكوبون"
                                                onClick={() => handleDelete(coupon.id)}
                                                className="p-2 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors"
                                            >
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

            {/* Add Coupon Modal */}
            {isAddModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
                    <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setIsAddModalOpen(false)}></div>
                    <div className="relative bg-white w-full max-w-md rounded-[24px] shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200">
                        <div className="p-6 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
                            <h3 className="text-xl font-extrabold text-slate-800 flex items-center gap-2">
                                <Tag size={20} className="text-purple-600" />
                                إضافة كوبون خصم
                            </h3>
                            <button type="button" title="إغلاق" onClick={() => setIsAddModalOpen(false)} className="text-slate-400 hover:text-slate-600 bg-slate-100 p-2 rounded-full transition-colors">
                                <X size={20} />
                            </button>
                        </div>

                        <form onSubmit={handleAddCoupon} className="p-6 space-y-5">
                            <div className="space-y-2">
                                <label className="block text-sm font-bold text-slate-700">رمز الكوبون (Code)</label>
                                <input
                                    type="text"
                                    required
                                    value={newCode}
                                    onChange={(e) => setNewCode(e.target.value)}
                                    className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all font-mono uppercase"
                                    placeholder="مثال: WELCOME20"
                                    dir="ltr"
                                />
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                                <div className="space-y-2">
                                    <label className="block text-sm font-bold text-slate-700">نوع الخصم</label>
                                    <select
                                        aria-label="نوع الخصم"
                                        value={newType}
                                        onChange={(e) => setNewType(e.target.value as 'percentage' | 'fixed')}
                                        className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all"
                                    >
                                        <option value="percentage">نسبة مئوية (%)</option>
                                        <option value="fixed">مبلغ ثابت (ر.س)</option>
                                    </select>
                                </div>
                                <div className="space-y-2">
                                    <label className="block text-sm font-bold text-slate-700">القيمة</label>
                                    <input
                                        type="number"
                                        aria-label="قيمة الخصم"
                                        required
                                        min="1"
                                        value={newValue}
                                        onChange={(e) => setNewValue(Number(e.target.value))}
                                        className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all text-left"
                                        dir="ltr"
                                    />
                                </div>
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                                <div className="space-y-2">
                                    <label className="block text-sm font-bold text-slate-700">تاريخ الانتهاء</label>
                                    <input
                                        type="date"
                                        aria-label="تاريخ الانتهاء"
                                        required
                                        value={newExpiry}
                                        onChange={(e) => setNewExpiry(e.target.value)}
                                        className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all cursor-pointer"
                                    />
                                </div>
                                <div className="space-y-2">
                                    <label className="block text-sm font-bold text-slate-700">الحد الأقصى للاستخدام</label>
                                    <input
                                        type="number"
                                        required
                                        min="1"
                                        value={newMaxUses}
                                        onChange={(e) => setNewMaxUses(Number(e.target.value))}
                                        className="w-full bg-white border border-slate-200 text-slate-700 font-bold text-sm rounded-xl px-4 py-3 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all text-left"
                                        dir="ltr"
                                        placeholder="1000"
                                    />
                                </div>
                            </div>

                            <div className="pt-4 border-t border-slate-100 flex gap-3">
                                <button
                                    type="button"
                                    onClick={() => setIsAddModalOpen(false)}
                                    className="flex-1 px-4 py-3.5 bg-slate-50 text-slate-600 font-extrabold rounded-xl hover:bg-slate-100 transition-colors"
                                >
                                    إلغاء
                                </button>
                                <button
                                    type="submit"
                                    disabled={isSubmitting}
                                    className="flex-[2] flex items-center justify-center gap-2 px-4 py-3.5 bg-gradient-to-r from-purple-600 to-pink-600 text-white font-extrabold rounded-xl hover:shadow-lg hover:shadow-purple-500/30 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    {isSubmitting ? <Loader2 size={20} className="animate-spin" /> : 'حفظ الكوبون'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}
