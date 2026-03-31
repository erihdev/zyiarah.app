import { useState, useEffect } from 'react';
import { 
  collection, 
  query, 
  onSnapshot, 
  updateDoc, 
  doc, 
  orderBy,
  Timestamp 
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { 
  ShoppingBag, 
  CheckCircle, 
  XCircle, 
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
  status: 'pending' | 'approved' | 'rejected';
  created_at: Timestamp;
}

export default function StoreOrders() {
  const [orders, setOrders] = useState<StoreOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedOrders, setExpandedOrders] = useState<Set<string>>(new Set());

  useEffect(() => {
    const q = query(collection(db, 'store_orders'), orderBy('created_at', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const ords: StoreOrder[] = [];
      snapshot.forEach((doc) => {
        ords.push({ id: doc.id, ...doc.data() } as StoreOrder);
      });
      setOrders(ords);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  const handleStatusUpdate = async (id: string, newStatus: 'approved' | 'rejected') => {
    try {
      await updateDoc(doc(db, 'store_orders', id), {
        status: newStatus,
        updated_at: Timestamp.now()
      });
    } catch (error) {
      console.error("Error updating order status:", error);
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
        <Loader2 className="animate-spin text-blue-600 mb-4" size={40} />
        <p className="text-slate-500 font-bold">جاري تحميل الطلبات...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-black text-slate-800">طلبات المتجر</h1>
        <p className="text-slate-500 text-sm mt-1">إدارة طلبات شراء الأدوات ومواد التنظيف</p>
      </div>

      {/* Orders List */}
      <div className="space-y-4">
        {orders.length === 0 ? (
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
                    order.status === 'approved' ? 'bg-green-50 text-green-600' :
                    order.status === 'rejected' ? 'bg-red-50 text-red-600' :
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
                    order.status === 'approved' ? 'bg-green-100 text-green-700' :
                    order.status === 'rejected' ? 'bg-red-100 text-red-700' :
                    'bg-amber-100 text-amber-700'
                  }`}>
                    {order.status === 'approved' ? 'مقبول' : 
                     order.status === 'rejected' ? 'مرفوض' : 'قيد الانتظار'}
                  </div>
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
                        {order.items.map((item, idx) => (
                          <div key={idx} className="flex items-center justify-between text-sm">
                            <span className="text-slate-600 font-medium">
                              {item.name} <span className="text-slate-400">x{item.quantity}</span>
                            </span>
                            <span className="font-bold text-slate-800">{item.price * item.quantity} ر.س</span>
                          </div>
                        ))}
                        <div className="pt-3 border-t border-slate-100 flex items-center justify-between font-black">
                          <span className="text-slate-800">الإجمالي الأساسي</span>
                          <span className="text-blue-600 text-lg">{order.total_amount} ر.س</span>
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

                      {order.status === 'pending' && (
                        <div className="flex gap-3">
                          <button 
                            type="button"
                            onClick={() => handleStatusUpdate(order.id, 'approved')}
                            className="flex-1 flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white py-3 rounded-2xl font-bold transition-all shadow-lg shadow-green-100"
                          >
                            <CheckCircle size={18} />
                            <span>موافقة على الطلب</span>
                          </button>
                          <button 
                            type="button"
                            onClick={() => handleStatusUpdate(order.id, 'rejected')}
                            className="flex-1 flex items-center justify-center gap-2 bg-white hover:bg-red-50 text-red-600 border border-red-100 py-3 rounded-2xl font-bold transition-all"
                          >
                            <XCircle size={18} />
                            <span>رفض الطلب</span>
                          </button>
                        </div>
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
