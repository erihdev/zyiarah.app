import { Outlet, Link, useLocation } from 'react-router-dom';
import {
    LayoutDashboard,
    Users,
    CarFront,
    ClipboardList,
    Settings,
    LogOut,
    Bell
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

interface SidebarItemProps {
    icon: LucideIcon;
    label: string;
    path: string;
    active: boolean;
}

const SidebarItem = ({ icon: Icon, label, path, active }: SidebarItemProps) => (
    <Link
        to={path}
        className={`flex items-center space-x-3 space-x-reverse px-4 py-3 rounded-xl transition-all duration-200 ${active
            ? 'bg-blue-600 text-white shadow-lg shadow-blue-500/30'
            : 'text-slate-400 hover:bg-slate-800 hover:text-white'
            }`}
    >
        <Icon size={20} />
        <span className="font-medium">{label}</span>
    </Link>
);

export default function Layout() {
    const location = useLocation();

    return (
        <div className="flex h-screen bg-slate-50 font-tajawal" dir="rtl">
            {/* Sidebar */}
            <aside className="w-64 bg-slate-900 border-l border-slate-800 text-white flex flex-col">
                <div className="p-6 flex items-center justify-center border-b border-slate-800">
                    <div className="flex flex-col items-center">
                        <div className="w-12 h-12 bg-blue-600 rounded-xl flex items-center justify-center shadow-lg shadow-blue-500/30 mb-2">
                            <span className="text-2xl font-bold">Z</span>
                        </div>
                        <h1 className="text-xl font-bold tracking-tight">Zyiarah Admin</h1>
                    </div>
                </div>

                <nav className="flex-1 px-4 py-6 space-y-2">
                    <SidebarItem icon={LayoutDashboard} label="الرئيسية" path="/" active={location.pathname === '/'} />
                    <SidebarItem icon={ClipboardList} label="الطلبات" path="/orders" active={location.pathname === '/orders'} />
                    <SidebarItem icon={CarFront} label="السائقين" path="/drivers" active={location.pathname === '/drivers'} />
                    <SidebarItem icon={Users} label="العملاء" path="/users" active={location.pathname === '/users'} />
                </nav>

                <div className="p-4 border-t border-slate-800 space-y-2">
                    <SidebarItem icon={Settings} label="الإعدادات" path="/settings" active={false} />
                    <button className="w-full flex items-center space-x-3 space-x-reverse px-4 py-3 text-red-400 hover:bg-red-500/10 hover:text-red-500 rounded-xl transition-colors">
                        <LogOut size={20} />
                        <span className="font-medium">تسجيل الخروج</span>
                    </button>
                </div>
            </aside>

            {/* Main Content */}
            <main className="flex-1 flex flex-col overflow-hidden">
                {/* Top Header */}
                <header className="h-20 bg-white border-b border-slate-200 flex items-center justify-between px-8 shadow-sm">
                    <h2 className="text-2xl font-bold text-slate-800">
                        {location.pathname === '/' ? 'لوحة القيادة' :
                            location.pathname === '/orders' ? 'إدارة الطلبات' :
                                location.pathname === '/drivers' ? 'إدارة السائقين' : 'لوحة التحكم'}
                    </h2>

                    <div className="flex items-center space-x-6 space-x-reverse">
                        <button className="relative p-2 text-slate-400 hover:text-slate-600 transition-colors">
                            <Bell size={24} />
                            <span className="absolute top-1 right-1 w-2.5 h-2.5 bg-red-500 rounded-full border-2 border-white"></span>
                        </button>
                        <div className="flex items-center space-x-3 space-x-reverse border-r border-slate-200 pr-6">
                            <div className="text-left">
                                <p className="font-bold text-slate-800 leading-tight">المدير العام</p>
                                <p className="text-xs text-slate-500">admin@zyiarah.com</p>
                            </div>
                            <div className="w-10 h-10 rounded-full bg-slate-200 border-2 border-white shadow-sm flex items-center justify-center">
                                <Users size={20} className="text-slate-500" />
                            </div>
                        </div>
                    </div>
                </header>

                {/* Page Content */}
                <div className="flex-1 overflow-auto bg-slate-50/50 p-8">
                    <div className="max-w-7xl mx-auto">
                        <Outlet />
                    </div>
                </div>
            </main>
        </div>
    );
}
