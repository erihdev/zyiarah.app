import { useEffect, useState, lazy, Suspense, type ReactElement } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { onAuthStateChanged } from 'firebase/auth';
import type { User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './services/firebase.ts';
import Layout from './components/Layout.tsx';
import { NotificationProvider } from './components/Notification.tsx';
import { canAccess } from './config/access.ts';

// ── تقسيم الحِزمة على المسارات ──────────────────────────────────────────
//
// كانت الصفحات السبعَ عشرة كلها مستورَدةً ثابتاً، فيُبنى ملفٌ واحد 3.0 ميغا
// (841ك مضغوطاً) يُنزّله **كل** أدمن قبل أن يرى أول شاشة.
//
// وأثقل تبعية (mapbox-gl) يستوردها **ملفٌ واحد**: Settings — فمحاسبٌ أو
// مسؤول تسويق لا يفتح الإعدادات قط كان ينزّل محرّك الخرائط كاملاً.
//
// Dashboard وLogin يبقيان ثابتَين: الأول صفحة الهبوط بعد الدخول والثاني أول
// ما يُرى قبله، فتأجيلهما يزيد زمن أول رسم لا ينقصه.
//
// **وبوّابة الأدوار صارت بوّابة تنزيل أيضاً:** `guard` تُعيد `<Navigate>` بدل
// العنصر حين يُمنع الدور، فالعنصر المؤجَّل لا يُصيَّر أصلاً — ولا تُجلب قطعته.
// فلا ينزّل أحدٌ شفرة صفحةٍ لا يملكها.
const Settings = lazy(() => import('./pages/Settings.tsx'));
const Orders = lazy(() => import('./pages/Orders.tsx'));
const ScheduleBoard = lazy(() => import('./pages/ScheduleBoard.tsx'));
const Drivers = lazy(() => import('./pages/Drivers.tsx'));
const Users = lazy(() => import('./pages/Users.tsx'));
const Accountants = lazy(() => import('./pages/Accountants.tsx'));
const Marketing = lazy(() => import('./pages/Marketing.tsx'));
const Notifications = lazy(() => import('./pages/Notifications.tsx'));
const Support = lazy(() => import('./pages/Support.tsx'));
const Admins = lazy(() => import('./pages/Admins.tsx'));
const AccountDeletion = lazy(() => import('./pages/AccountDeletion.tsx'));
const Contracts = lazy(() => import('./pages/Contracts.tsx'));
const StoreProducts = lazy(() => import('./pages/StoreProducts.tsx'));
const StoreOrders = lazy(() => import('./pages/StoreOrders.tsx'));
const Payroll = lazy(() => import('./pages/Payroll.tsx'));

// غير مؤجَّلتين بقصد — انظر أعلاه.
import Dashboard from './pages/Dashboard.tsx';
import Login from './pages/Login.tsx';

const ADMIN_ROLES = ['super_admin', 'admin', 'orders_manager', 'accountant_admin', 'marketing_admin'];

/// مؤشّر انتظار قطعة الصفحة — بنفس هيئة مؤشّر التحقّق من الهوية كي لا يبدو
/// التنقّل عطلاً. يملأ منطقة المحتوى لا الصفحة، فالإطار يبقى ظاهراً.
function PageSpinner() {
    return (
        <div className="flex items-center justify-center py-24" dir="rtl">
            <div className="w-10 h-10 border-4 border-[#660033] border-t-transparent rounded-full animate-spin"></div>
        </div>
    );
}

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
  //
  // ويلفّ العنصرَ المؤجَّل بحدّ Suspense **لكلّ مسار على حدة** لا حدّاً واحداً
  // حول الـRoutes: حدٌّ واحد يُفرِغ الإطار (الشريط الجانبي والترويسة) أثناء
  // جلب القطعة، فيرى الأدمن شاشةً بيضاء عند كل تنقّل. وبالحدّ لكل مسار يبقى
  // الإطار ثابتاً ويدور المؤشّر في منطقة المحتوى وحدها.
  const guard = (path: string, element: ReactElement) =>
    canAccess(role, path)
      ? <Suspense fallback={<PageSpinner />}>{element}</Suspense>
      : <Navigate to="/" replace />;

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50" dir="rtl">
        <div className="flex flex-col items-center">
          <div className="w-12 h-12 border-4 border-[#660033] border-t-transparent rounded-full animate-spin mb-4"></div>
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
          <Route path="schedule" element={guard('/schedule', <ScheduleBoard />)} />
          <Route path="drivers" element={guard('/drivers', <Drivers />)} />
          <Route path="users" element={guard('/users', <Users />)} />
          <Route path="accountants" element={guard('/accountants', <Accountants />)} />
          <Route path="marketing" element={guard('/marketing', <Marketing />)} />
          <Route path="notifications" element={guard('/notifications', <Notifications />)} />
          <Route path="support" element={guard('/support', <Support />)} />
          <Route path="admins" element={guard('/admins', <Admins />)} />
          <Route path="account-deletion" element={guard('/account-deletion', <AccountDeletion />)} />
          <Route path="contracts" element={guard('/contracts', <Contracts role={role} />)} />
          <Route path="store-products" element={guard('/store-products', <StoreProducts />)} />
          <Route path="store-orders" element={guard('/store-orders', <StoreOrders />)} />
          <Route path="settings" element={guard('/settings', <Settings role={role} />)} />
          <Route path="payroll" element={guard('/payroll', <Payroll />)} />
        </Route>
      </Routes>
    </BrowserRouter>
    </NotificationProvider>
  );
}

export default App;
