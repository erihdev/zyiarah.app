import { useState, useEffect } from 'react';
import { 
  collection, 
  query, 
  onSnapshot, 
  addDoc, 
  updateDoc, 
  deleteDoc, 
  doc, 
  serverTimestamp 
} from 'firebase/firestore';
import { db } from '../services/firebase.ts';
import { 
  Plus, 
  Search, 
  Edit2, 
  Trash2, 
  Eye, 
  EyeOff, 
  Package,
  X,
  Save,
  Loader2
} from 'lucide-react';

interface Product {
  id: string;
  name: string;
  price: number;
  image_url: string;
  description: string;
  is_hidden: boolean;
}

export default function StoreProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  
  // Form State
  const [formData, setFormData] = useState({
    name: '',
    price: 0,
    image_url: '',
    description: '',
    is_hidden: false
  });

  useEffect(() => {
    const q = query(collection(db, 'products'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const prods: Product[] = [];
      snapshot.forEach((doc) => {
        prods.push({ id: doc.id, ...doc.data() } as Product);
      });
      setProducts(prods);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  const handleOpenModal = (product?: Product) => {
    if (product) {
      setEditingProduct(product);
      setFormData({
        name: product.name,
        price: product.price,
        image_url: product.image_url,
        description: product.description,
        is_hidden: product.is_hidden
      });
    } else {
      setEditingProduct(null);
      setFormData({
        name: '',
        price: 0,
        image_url: '',
        description: '',
        is_hidden: false
      });
    }
    setIsModalOpen(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (editingProduct) {
        await updateDoc(doc(db, 'products', editingProduct.id), {
          ...formData,
          updated_at: serverTimestamp()
        });
      } else {
        await addDoc(collection(db, 'products'), {
          ...formData,
          created_at: serverTimestamp()
        });
      }
      setIsModalOpen(false);
    } catch (error) {
      console.error("Error saving product:", error);
    }
  };

  const handleDelete = async (id: string) => {
    if (globalThis.confirm('هل أنت متأكد من حذف هذا المنتج؟')) {
      await deleteDoc(doc(db, 'products', id));
    }
  };

  const toggleVisibility = async (product: Product) => {
    await updateDoc(doc(db, 'products', product.id), {
      is_hidden: !product.is_hidden
    });
  };

  const filteredProducts = products.filter((p: Product) => 
    p.name.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-6 animate-in fade-in duration-500">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black text-slate-800">إدارة منتجات المتجر</h1>
          <p className="text-slate-500 text-sm mt-1">أضف، عدل، أو أخف المنتجات من متجر الأدوات</p>
        </div>
        <button 
          type="button"
          onClick={() => handleOpenModal()}
          className="flex items-center justify-center space-x-2 space-x-reverse bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-2xl font-bold transition-all shadow-lg shadow-blue-200"
        >
          <Plus size={20} />
          <span>إضافة منتج جديد</span>
        </button>
      </div>

      {/* Search & Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="md:col-span-3 relative group">
          <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-blue-600 transition-colors" size={20} />
          <input 
            type="text" 
            placeholder="البحث عن منتج..."
            className="w-full bg-white border border-slate-200 rounded-2xl py-3.5 pr-12 pl-4 outline-none focus:ring-4 focus:ring-blue-50 focus:border-blue-500 transition-all font-medium"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <div className="bg-white border border-slate-200 rounded-2xl p-4 flex items-center justify-between">
          <div>
            <p className="text-xs font-bold text-slate-400 uppercase">إجمالي المنتجات</p>
            <p className="text-2xl font-black text-slate-800">{products.length}</p>
          </div>
          <div className="p-3 bg-blue-50 text-blue-600 rounded-xl">
            <Package size={24} />
          </div>
        </div>
      </div>

      {/* Products Grid */}
      {loading ? (
        <div className="flex flex-col items-center justify-center py-20">
          <Loader2 className="animate-spin text-blue-600 mb-4" size={40} />
          <p className="text-slate-500 font-bold">جاري تحميل المنتجات...</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {filteredProducts.map((product) => (
            <div key={product.id} className={`bg-white border border-slate-200 rounded-3xl overflow-hidden shadow-sm hover:shadow-xl transition-all duration-300 group flex flex-col ${product.is_hidden ? 'opacity-75' : ''}`}>
              <div className="relative h-48 bg-slate-100">
                <img 
                  src={product.image_url} 
                  alt={product.name} 
                  className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" 
                />
                <button 
                  type="button"
                  onClick={() => toggleVisibility(product)}
                  className={`absolute top-4 right-4 p-2.5 rounded-xl backdrop-blur-md shadow-lg transition-all ${product.is_hidden ? 'bg-orange-500 text-white' : 'bg-white/80 text-slate-600 hover:bg-white'}`}
                  aria-label={product.is_hidden ? 'إظهار المنتج' : 'إخفاء المنتج'}
                  title={product.is_hidden ? 'إظهار المنتج' : 'إخفاء المنتج'}
                >
                  {product.is_hidden ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              
              <div className="p-5 flex-1 flex flex-col">
                <h3 className="font-bold text-slate-800 line-clamp-2 min-h-[3rem] mb-2">{product.name}</h3>
                <p className="text-2xl font-black text-blue-600 mb-4">{product.price} <span className="text-xs font-bold text-slate-400">ر.س</span></p>
                
                <div className="mt-auto pt-4 border-t border-slate-50 flex items-center justify-between gap-3">
                  <button 
                    type="button"
                    onClick={() => handleOpenModal(product)}
                    className="flex-1 flex items-center justify-center space-x-2 space-x-reverse bg-slate-50 hover:bg-slate-100 text-slate-600 py-2.5 rounded-xl font-bold transition-all border border-slate-100"
                  >
                    <Edit2 size={16} />
                    <span>تعديل</span>
                  </button>
                  <button 
                    type="button"
                    onClick={() => handleDelete(product.id)}
                    className="p-2.5 text-red-100 hover:text-red-600 bg-red-600 hover:bg-red-50 rounded-xl transition-all"
                    aria-label="حذف المنتج"
                    title="حذف المنتج"
                  >
                    <Trash2 size={18} />
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-300">
          <div className="bg-white w-full max-w-lg rounded-[2.5rem] shadow-2xl overflow-hidden animate-in zoom-in-95 duration-300">
            <div className="p-8 border-b border-slate-50 flex items-center justify-between bg-slate-50/50">
              <h2 className="text-xl font-black text-slate-800">{editingProduct ? 'تعديل منتج' : 'إضافة منتج جديد'}</h2>
              <button 
                type="button"
                onClick={() => setIsModalOpen(false)}
                className="p-2 text-slate-400 hover:text-slate-600 hover:bg-white rounded-xl transition-all"
                aria-label="إغلاق"
                title="إغلاق"
              >
                <X size={24} />
              </button>
            </div>
            
            <form onSubmit={handleSubmit} className="p-8 space-y-5">
              <div className="space-y-2">
                <label htmlFor="prod-name" className="text-sm font-bold text-slate-600 px-1">اسم المنتج</label>
                <input 
                  id="prod-name"
                  type="text" 
                  required
                  className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3 px-4 outline-none focus:ring-4 focus:ring-blue-50 focus:border-blue-500 transition-all font-medium"
                  value={formData.name}
                  onChange={(e) => setFormData({...formData, name: e.target.value})}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label htmlFor="prod-price" className="text-sm font-bold text-slate-600 px-1">السعر (ر.س)</label>
                  <input 
                    id="prod-price"
                    type="number" 
                    step="0.01"
                    required
                    className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3 px-4 outline-none focus:ring-4 focus:ring-blue-50 focus:border-blue-500 transition-all font-medium"
                    value={formData.price}
                    onChange={(e) => setFormData({...formData, price: parseFloat(e.target.value)})}
                  />
                </div>
                <div className="space-y-2">
                  <label htmlFor="prod-image" className="text-sm font-bold text-slate-600 px-1">رابط الصورة</label>
                  <input 
                    id="prod-image"
                    type="url" 
                    required
                    className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3 px-4 outline-none focus:ring-4 focus:ring-blue-50 focus:border-blue-500 transition-all font-medium"
                    value={formData.image_url}
                    onChange={(e) => setFormData({...formData, image_url: e.target.value})}
                  />
                </div>
              </div>

              <div className="space-y-2">
                <label htmlFor="prod-desc" className="text-sm font-bold text-slate-600 px-1">وصف المنتج</label>
                <textarea 
                  id="prod-desc"
                  rows={3}
                  className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3 px-4 outline-none focus:ring-4 focus:ring-blue-50 focus:border-blue-500 transition-all font-medium resize-none"
                  value={formData.description}
                  onChange={(e) => setFormData({...formData, description: e.target.value})}
                />
              </div>

              <div className="pt-4 flex items-center justify-end gap-3">
                <button 
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-6 py-3 rounded-2xl font-bold text-slate-500 hover:bg-slate-100 transition-all"
                >
                  إلغاء
                </button>
                <button 
                  type="submit"
                  className="flex items-center space-x-2 space-x-reverse bg-blue-600 hover:bg-blue-700 text-white px-10 py-3 rounded-2xl font-bold transition-all shadow-lg shadow-blue-100"
                >
                  <Save size={20} />
                  <span>{editingProduct ? 'حفظ التعديلات' : 'نشر المنتج'}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
