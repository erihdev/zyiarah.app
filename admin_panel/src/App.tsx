import { useEffect, useState, type ReactElement } from 'react';
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
import Contracts from './pages/Contracts.tsx';
import StoreProducts from './pages/StoreProducts.tsx';
import StoreOrders from './pages/StoreOrders.tsx';
import Services from './pages/Services.tsx';
import Payroll from './pages/Payroll.tsx';
import { canAccess } from './config/access.ts';

const ADMIN_ROLES = ['super_admin', 'admin', 'orders_manager', 'accountant_admin', 'marketing_admin'];

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [role, setRole] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      if (currentUser) {
        try {
          const snap = await getDoc(doc(db, 'users', currentUser.uid));
          // EFFECTIVE role: staff store their real sub-role in staff_role while role
          // stays the generic 'admin'. Prefer staff_role so page gating actually
          // separates staff (previously every staff = 'admin' saw every page).
          const d = snap.data();
          const r = (d?.staff_role ?? d?.role) as string | undefined;
          setRole(r ?? null);
          setIsAdmin(!!r && ADMIN_ROLES.includes(r));
        } catch {
          setRole(null);
          setIsAdmin(false);
        }
      } else {
        setRole(null);
        setIsAdmin(false);
      }
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  // Guard a route element: render it only if the role may access that path,
  // otherwise bounce to the dashboard (which every admin role can open).
  const guard = (path: string, element: ReactElement) =>
    canAccess(role, path) ? element : <Navigate to="/" replace />;

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
          element={user && isAdmin ? <Layout onLogout={handleLogout} role={role} /> : <Navigate to="/login" />}
        >
          <Route index element={<Dashboard />} />
          <Route path="orders" element={guard('/orders', <Orders />)} />
          <Route path="drivers" element={guard('/drivers', <Drivers />)} />
          <Route path="users" element={guard('/users', <Users />)} />
          <Route path="accountants" element={guard('/accountants', <Accountants />)} />
          <Route path="marketing" element={guard('/marketing', <Marketing />)} />
          <Route path="notifications" element={guard('/notifications', <Notifications />)} />
          <Route path="support" element={guard('/support', <Support />)} />
          <Route path="admins" element={guard('/admins', <Admins />)} />
          <Route path="account-deletion" element={guard('/account-deletion', <AccountDeletion />)} />
          <Route path="contracts" element={guard('/contracts', <Contracts />)} />
          <Route path="store-products" element={guard('/store-products', <StoreProducts />)} />
          <Route path="store-orders" element={guard('/store-orders', <StoreOrders />)} />
          <Route path="settings" element={guard('/settings', <Settings />)} />
          <Route path="services" element={guard('/services', <Services />)} />
          <Route path="payroll" element={guard('/payroll', <Payroll />)} />
        </Route>
      </Routes>
    </BrowserRouter>
    </NotificationProvider>
  );
}

export default App;
