import { useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import Login from './pages/Login';
import Settings from './pages/Settings';
import Orders from './pages/Orders';
import Drivers from './pages/Drivers';
import Users from './pages/Users';
import Accountants from './pages/Accountants';
import Marketing from './pages/Marketing';
import Notifications from './pages/Notifications';
import Support from './pages/Support';
import Admins from './pages/Admins';
import AccountDeletion from './pages/AccountDeletion';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  const handleLogin = () => {
    setIsAuthenticated(true);
  };

  const handleLogout = () => {
    setIsAuthenticated(false);
  };

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={isAuthenticated ? <Navigate to="/" /> : <Login onLogin={handleLogin} />}
        />

        {/* Protected Routes */}
        <Route
          path="/"
          element={isAuthenticated ? <Layout onLogout={handleLogout} /> : <Navigate to="/login" />}
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
          <Route path="settings" element={<Settings />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
