import { useState, useEffect } from 'react';
import {
  collection,
  query,
  onSnapshot,
  updateDoc,
  doc,
  orderBy,
  limit,
  Timestamp
} from 'firebase/firestore';
import { db, auth } from '../services/firebase.ts';
// وسمُ مراجعةِ السعرِ: `_verifyStoreOrderPrice` يَسِمُ `store_orders` بنفسِ
// حقولِ `orders`، وهذه إحدى شاشتَي عرضِها — ولم تكن تَذكرُ منه شيئاً.
import {
  priceReviewOf, priceReviewApprovalPayload, priceReviewLine,
} from '../utils/priceReview.ts';
import PriceReviewBadge from '../components/PriceReviewBadge.tsx';
import { logAudit, AUDIT } from '../services/audit.ts';
import { useNotification } from '../components/notificationContext.ts';
import {
  ShoppingBag,
  CheckCircle,
  Clock,
  User,
  ChevronDown,
  ChevronUp,
  Package,
  Loader2
} from 'lucide-react';

interface OrderItem {
  id: string;
  name: string;
  quantity: number;
  price: number;
}

interface StoreOrder {
  id: string;
  client_id: string;
  client_name?: string;
  items: OrderItem[];
  total_amount: number;
  status: 'pending' | 'awaiting_payment' | 'under_review' | 'delivering' | 'approved' | 'rejected' | 'processing' | 'shipped' | 'delivered' | 'completed' | 'pending_admin_approval';
  is_paid?: boolean;
  created_at: Timestamp;
  // أعلامُ تحقّقِ السعرِ الخادميّ (Tier A — وسمٌ وتنبيهٌ لا رفض).
  price_mismatch?: boolean;
  price_unverifiable?: boolean;
  price_paid?: number;
  price_expected?: number;
  price_expected_net?: number;
  price_shadow_ratio?: number;
  coupon_rejected_reason?: string;
  price_reviewed_at?: Timestamp;
  price_reviewed_by?: string;
}

// حالة مدفوعة = العميل دفع فعلاً؛ كانت اللوحة تعرضها كـ"قيد الانتظار" وتُظهر أزرار موافقة/رفض خطأً.
const PAID_STATUSES = ['processing', 'shipped', 'delivered', 'completed'];
const STATUS_LABELS: Record<string, string> = {
  pending: 'قيد الانتظار',
  pending_admin_approval: 'بانتظار الموافقة',
  awaiting_payment: 'بانتظار الدفع',
  under_review: 'مدفوع — تحت المراجعة',
  delivering: 'جاري التوصيل',
  approved: 'مقبول',
  rejected: 'مرفوض',
  processing: 'مدفوع — قيد التجهيز',
  shipped: 'تم الشحن',
  delivered: 'تم التسليم',
  completed: 'مكتمل',
};
function statusTone(status: string): 'green' | 'red' | 'blue' | 'amber' {
  if (status === 'rejected') return 'red';
  if (status === 'approved' || status === 'delivered' || status === 'completed') return 'green';
  if (PAID_STATUSES.includes(status)) return 'blue';
  return 'amber';
}

export default function StoreOrders() {
  const { toast } = useNotification();
  const [orders, setOrders] = useState<StoreOrder[]>([]);
  const [loading, setLoading] = useState(true);
  // فشل المستمع نهائي — حالة خطأ صريحة بزر إعادة بدل «لا توجد طلبات» المضلّلة.
  const [loadError, setLoadError] = useState(false);
  const [retryKey, setRetryKey] = useState(0);
  const [expandedOrders, setExpandedOrders] = useState<Set<string>>(new Set());

  useEffect(() => {
    // (أداء) أحدث 300 فقط — كانت المجموعة كلها تُقرأ بلا حد مع كل فتح للصفحة.
    const q = query(collection(db, 'store_orders'), orderBy('created_at', 'desc'), limit(300));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const ords: StoreOrder[] = [];
      snapshot.forEach((doc) => {
        ords.push({ id: doc.id, ...doc.data() } as StoreOrder);
      });
      setOrders(ords);
      setLoading(false);
    }, (e: unknown) => {
      // كان معالج الخطأ يُمرَّر خطأً كوسيط ثانٍ لـ forEach (thisArg) فلا يُستدعى أبداً،
      // فيعلق الدوّار عند فشل المستمع. مكانه الصحيح الوسيط الثالث لـ onSnapshot.
      console.error("StoreOrders listener error:", e);
      setLoading(false);
      setLoadError(true);
    });
    return () => unsubscribe();
  }, [retryKey]);

  const handleStatusUpdate = async (id: string, newStatus: string) => {
    try {
      await updateDoc(doc(db, 'store_orders', id), {
        status: newStatus,
        updated_at: Timestamp.now()
      });
    } catch (error) {
      // كان `console.error` وحدَه: الأدمن يَنقرُ «جاري التوصيل» فلا يَحدثُ شيءٌ
      // ولا تُقال كلمة — والصفُّ لا يَتغيّر (لا كتابةَ ⇒ لا مستمعَ يُحدِّث)،
      // فيَظنُّ أنّه ضغطَ خطأً ويُعيد. والعميلةُ لا تُشعَر بشيء.
      console.error("Error updating order status:", error);
      toast.error(error instanceof Error ? error.message : 'تعذّر تحديث حالة الطلب');
    }
  };

  // اعتمادُ المبلغِ الموسوم — يُبطِلُ علمَي الاستعلامِ فيَخرُجُ المستندُ من
  // نافذةِ `opsHealthSweep`. بلا هذا المسارِ كان الوسمُ يَبقى للأبد.
  const handleApprovePrice = async (id: string) => {
    try {
      await updateDoc(doc(db, 'store_orders', id), {
        ...priceReviewApprovalPayload(auth.currentUser?.email ?? 'Unknown Admin'),
        price_reviewed_at: Timestamp.now(),
        updated_at: Timestamp.now()
      });
      await logAudit(AUDIT.REVIEW_ORDER_PRICE, {
        decision: 'approved', collection: 'store_orders',
      }, id);
      toast.success('تم اعتماد المبلغ');
    } catch (error) {
      console.error("Error approving store order price:", error);
      toast.error(error instanceof Error ? error.message : 'تعذّر اعتماد المبلغ');
    }
  };

  const toggleExpand = (id: string) => {
    const newExpanded = new Set(expandedOrders);
    if (newExpanded.has(id)) newExpanded.delete(id);
    else newExpanded.add(id);
    setExpandedOrders(newExpanded);
  };

  const formatDate = (at: Timestamp) => {
    if (!at) return '';
    const date = at.toDate();
    return date.toLocaleString('ar-SA');
  };

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <Loader2 className="animate-spin text-[#660033] mb-4" size={40} />
        <p className="text-slate-500 font-bold">جاري تحميل الطلبات...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-black text-slate-800">طلبات المتجر</h1>
        <p className="text-slate-500 text-sm mt-1">إدارة طلبات شراء الأدوات ومواد التنظيف — يعرض أحدث 300 طلب</p>
      </div>

      {/* Orders List */}
      <div className="space-y-4">
        {loadError ? (
          // حالة خطأ صريحة لا «لا توجد طلبات» — الفراغ عند الفشل يوهم بخلو المتجر.
          <div className="bg-rose-50 rounded-[2rem] p-12 text-center border border-rose-200">
            <p className="text-rose-600 font-bold text-lg mb-4">تعذّر تحميل طلبات المتجر — تحقّق من الاتصال أو الصلاحيات</p>
            <button
              type="button"
              onClick={() => { setLoadError(false); setLoading(true); setRetryKey(k => k + 1); }}
              className="px-6 py-3 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 transition-colors"
            >
              إعادة المحاولة
            </button>
          </div>
        ) : orders.length === 0 ? (
          <div className="bg-white rounded-[2rem] p-16 text-center border border-slate-100 shadow-sm">
            <ShoppingBag className="mx-auto text-slate-200 mb-4" size={60} />
            <p className="text-slate-500 font-bold text-lg">لا توجد طلبات متجر حالياً</p>
          </div>
        ) : (
          orders.map((order) => (
            <div key={order.id} className="bg-white rounded-3xl border border-slate-100 shadow-sm overflow-hidden hover:shadow-md transition-all duration-300">
              {/* Order Header */}
              <div 
                className="p-6 flex flex-wrap items-center justify-between gap-4 cursor-pointer"
                onClick={() => toggleExpand(order.id)}
              >
                <div className="flex items-center gap-4">
                  <div className={`p-3 rounded-2xl ${
                    statusTone(order.status) === 'green' ? 'bg-green-50 text-green-600' :
                    statusTone(order.status) === 'red' ? 'bg-red-50 text-red-600' :
                    statusTone(order.status) === 'blue' ? 'bg-[#FAF1F6] text-[#660033]' :
                    'bg-amber-50 text-amber-600'
                  }`}>
                    <Package size={24} />
                  </div>
                  <div>
                    <h3 className="font-bold text-slate-800">طلب #{order.id.slice(-6).toUpperCase()}</h3>
                    <div className="flex items-center gap-2 text-xs text-slate-400 font-semibold mt-0.5">
                      <Clock size={12} />
                      <span>{formatDate(order.created_at)}</span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <div className={`px-4 py-1.5 rounded-full text-xs font-bold uppercase ${
                    statusTone(order.status) === 'green' ? 'bg-green-100 text-green-700' :
                    statusTone(order.status) === 'red' ? 'bg-red-100 text-red-700' :
                    statusTone(order.status) === 'blue' ? 'bg-[#F2DEE9] text-[#4D0026]' :
                    'bg-amber-100 text-amber-700'
                  }`}>
                    {STATUS_LABELS[order.status] ?? order.status}
                  </div>
                  {/* في الرأسِ لا داخلَ التوسيع: الوسمُ يَجبُ أن يُرى بلا نقر. */}
                  <PriceReviewBadge r={priceReviewOf(order as unknown as Record<string, unknown>)} />
                  <div className="bg-slate-50 p-1.5 rounded-lg text-slate-400">
                    {expandedOrders.has(order.id) ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
                  </div>
                </div>
              </div>

              {/* Order Content */}
              {expandedOrders.has(order.id) && (
                <div className="px-6 pb-6 pt-2 space-y-6 animate-in slide-in-from-top-2 duration-300">
                  <hr className="border-slate-50" />
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                    {/* Items List */}
                    <div className="space-y-4">
                      <h4 className="text-sm font-bold text-slate-700 flex items-center gap-2">
                        <ShoppingBag size={16} />
                        قائمة المنتجات
                      </h4>
                      <div className="bg-slate-50/50 rounded-2xl p-4 space-y-3">
                        {(order.items ?? []).map((item, idx) => (
                          <div key={idx} className="flex items-center justify-between text-sm">
                            <span className="text-slate-600 font-medium">
                              {item.name} <span className="text-slate-400">x{item.quantity}</span>
                            </span>
                            <span className="font-bold text-slate-800">{item.price * item.quantity} ر.س</span>
                          </div>
                        ))}
                        <div className="pt-3 border-t border-slate-100 flex items-center justify-between font-black">
                          <span className="text-slate-800">الإجمالي الأساسي</span>
                          <span className="text-[#660033] text-lg">{order.total_amount} ر.س</span>
                        </div>
                      </div>
                    </div>

                    {/* Order Details & Actions */}
                    <div className="space-y-6">
                      <div className="space-y-4">
                        <h4 className="text-sm font-bold text-slate-700 flex items-center gap-2">
                          <User size={16} />
                          بيانات العميل
                        </h4>
                        <div className="bg-slate-50/50 rounded-2xl p-4">
                          <p className="font-bold text-slate-800">{order.client_name || 'عميل زيارة'}</p>
                          <p className="text-xs text-slate-400 font-medium mt-1">ID: {order.client_id}</p>
                        </div>
                      </div>

                      {/* المتجر المباشر: العميل يدفع فوراً ثم تحت المراجعة ⇒ جاري
                          التوصيل ⇒ تم التوصيل. (مسار الموافقة/الرفض القديم أُلغي في
                          تطبيق الأدمن؛ حُدّثت اللوحة لتقود نفس السلسلة.) */}
                      {(order.status === 'under_review' || order.status === 'processing') && (
                        <button
                          type="button"
                          onClick={() => handleStatusUpdate(order.id, 'delivering')}
                          className="w-full flex items-center justify-center gap-2 bg-[#660033] hover:bg-[#4D0026] text-white py-3 rounded-2xl font-bold transition-all shadow-lg shadow-[#F2DEE9]"
                        >
                          <CheckCircle size={18} />
                          <span>بدء التوصيل</span>
                        </button>
                      )}
                      {priceReviewOf(order as unknown as Record<string, unknown>).actionable && (
                        <div className="rounded-2xl border border-rose-200 bg-rose-50/60 p-4 space-y-2">
                          <p className="text-sm font-bold text-rose-700">
                            {priceReviewLine(priceReviewOf(order as unknown as Record<string, unknown>))}
                          </p>
                          <p className="text-xs text-slate-600 font-medium leading-relaxed">
                            الطلب لم يُرفض دفعُه (سياسة مقصودة) — راجع المبلغ واسترد الفارق،
                            أو اعتمده كما هو.
                          </p>
                          <button
                            type="button"
                            onClick={() => handleApprovePrice(order.id)}
                            className="w-full flex items-center justify-center gap-2 bg-rose-600 hover:bg-rose-700 text-white py-2.5 rounded-xl font-bold transition-all"
                          >
                            <CheckCircle size={16} />
                            <span>اعتماد المبلغ</span>
                          </button>
                        </div>
                      )}
                      {(order.status === 'delivering' || order.status === 'shipped') && (
                        <button
                          type="button"
                          onClick={() => handleStatusUpdate(order.id, 'delivered')}
                          className="w-full flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white py-3 rounded-2xl font-bold transition-all shadow-lg shadow-green-100"
                        >
                          <CheckCircle size={18} />
                          <span>تم التوصيل</span>
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
