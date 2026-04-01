import { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { onAuthStateChanged } from 'firebase/auth';
import type { User } from 'firebase/auth';
import { auth } from './services/firebase.ts';
import Layout from './components/Layout.tsx';
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

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (currentUser) => {
      setUser(currentUser);
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

  const handleLogout = () => {
    auth.signOut();
  };

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={user ? <Navigate to="/" /> : <Login />}
        />

        {/* Protected Routes */}
        <Route
          path="/"
          element={user ? <Layout onLogout={handleLogout} /> : <Navigate to="/login" />}
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
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
