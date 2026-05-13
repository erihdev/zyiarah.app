import { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { onAuthStateChanged } from 'firebase/auth';
import type { User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './services/firebase.ts';
import Layout from './components/Layout.tsx';
import { NotificationProvider } from './components/Notification.tsx';
import Dashboard from './pages/Dashboard.tsx';
import Login from './pages/Login.tsx';
import Settings from './pages/Settings.tsx';
import Orders from './pages/Orders.tsx';
import Drivers from './pages/Drivers.tsx';
import Users from './pages/Users.tsx';
import Accountants from './pages/Accountants.tsx';
import Marketing from './pages/Marketing.tsx';
import Notifications from './pages/Notifications.tsx';
import Support from './pages/Support.tsx';
import Admins from './pages/Admins.tsx';
import AccountDeletion from './pages/AccountDeletion.tsx';
import Maintenance from './pages/Maintenance.tsx';
import Contracts from './pages/Contracts.tsx';
import StoreProducts from './pages/StoreProducts.tsx';
import StoreOrders from './pages/StoreOrders.tsx';
import Services from './pages/Services.tsx';
import Payroll from './pages/Payroll.tsx';

const ADMIN_ROLES = ['super_admin', 'admin', 'orders_manager', 'accountant_admin', 'marketing_admin'];

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      if (currentUser) {
        try {
          const snap = await getDoc(doc(db, 'users', currentUser.uid));
          const role = snap.data()?.role as string | undefined;
          setIsAdmin(!!role && ADMIN_ROLES.includes(role));
        } catch {
          setIsAdmin(false);
        }
      } else {
        setIsAdmin(false);
      }
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50" dir="rtl">
        <div className="flex flex-col items-center">
          <div className="w-12 h-12 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mb-4"></div>
          <p className="text-slate-600 font-bold">جاري التحقق من الهوية...</p>
        </div>
      </div>
    );
  }

  if (user && !isAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50" dir="rtl">
        <div className="flex flex-col items-center text-center p-8 max-w-sm">
          <div className="w-16 h-16 bg-red-100 rounded-2xl flex items-center justify-center mb-4">
            <span className="text-3xl">🚫</span>
          </div>
          <h2 className="text-xl font-black text-slate-800 mb-2">غير مصرّح لك بالدخول</h2>
          <p className="text-slate-500 font-medium mb-6">هذا الحساب لا يملك صلاحية الوصول للوحة التحكم.</p>
          <button
            type="button"
            onClick={() => auth.signOut()}
            className="px-6 py-3 bg-slate-900 text-white rounded-xl font-bold hover:bg-slate-700 transition-colors"
          >
            تسجيل الخروج
          </button>
        </div>
      </div>
    );
  }

  const handleLogout = () => {
    auth.signOut();
  };

  return (
    <NotificationProvider>
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={user && isAdmin ? <Navigate to="/" /> : <Login />}
        />

        {/* Protected Routes */}
        <Route
          path="/"
          element={user && isAdmin ? <Layout onLogout={handleLogout} /> : <Navigate to="/login" />}
        >
          <Route index element={<Dashboard />} />
          <Route path="orders" element={<Orders />} />
          <Route path="drivers" element={<Drivers />} />
          <Route path="users" element={<Users />} />
          <Route path="accountants" element={<Accountants />} />
          <Route path="marketing" element={<Marketing />} />
          <Route path="notifications" element={<Notifications />} />
          <Route path="support" element={<Support />} />
          <Route path="admins" element={<Admins />} />
          <Route path="account-deletion" element={<AccountDeletion />} />
          <Route path="maintenance" element={<Maintenance />} />
          <Route path="contracts" element={<Contracts />} />
          <Route path="store-products" element={<StoreProducts />} />
          <Route path="store-orders" element={<StoreOrders />} />
          <Route path="settings" element={<Settings />} />
          <Route path="services" element={<Services />} />
          <Route path="payroll" element={<Payroll />} />
        </Route>
      </Routes>
    </BrowserRouter>
    </NotificationProvider>
  );
}

export default App;
