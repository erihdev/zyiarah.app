import { Outlet, Link, useLocation } from 'react-router-dom';
import {
    LayoutDashboard,
    Users,
    CarFront,
    ClipboardList,
    Settings,
    LogOut,
    Bell,
    Search,
    Calculator,
    Megaphone,
    BellRing,
    LifeBuoy,
    Shield,
    ShieldAlert,
    Wrench,
    FileSignature,
    ShoppingBasket,
    ShoppingBag,
    Banknote
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
        className={`group flex items-center space-x-3 space-x-reverse px-4 py-3.5 rounded-2xl transition-all duration-300 relative overflow-hidden ${active
            ? 'text-blue-600 bg-blue-50/80 font-bold'
            : 'text-slate-500 hover:bg-slate-50 hover:text-slate-900 font-medium'
            }`}
    >
        {active && (
            <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1.5 h-8 bg-blue-600 rounded-l-full shadow-[0_0_10px_rgba(37,99,235,0.5)]"></div>
        )}
        <div className={`p-2 rounded-xl transition-colors duration-300 ${active ? 'bg-white shadow-sm text-blue-600' : 'bg-transparent text-slate-400 group-hover:bg-white group-hover:text-slate-600 group-hover:shadow-sm'}`}>
            <Icon size={20} strokeWidth={active ? 2.5 : 2} />
        </div>
        <span>{label}</span>
    </Link>
);

interface LayoutProps {
    onLogout?: () => void;
}

export default function Layout({ onLogout }: LayoutProps) {
    const location = useLocation();

    return (
        <div className="flex h-screen bg-[#f8fafc] font-tajawal selection:bg-blue-100 selection:text-blue-900" dir="rtl">
            {/* Sidebar */}
            <aside className="w-72 bg-white/80 backdrop-blur-xl border-l border-slate-100/80 shadow-[0_0_40px_rgba(0,0,0,0.02)] flex flex-col z-20">
                <div className="p-8 flex items-center justify-center border-b border-slate-100/80">
                    <h1 className="text-3xl font-black bg-gradient-to-l from-blue-700 to-indigo-700 bg-clip-text text-transparent transform hover:scale-105 transition-transform cursor-pointer">
                        زيارة <span className="text-slate-200 font-light">|</span> <span className="text-xl font-bold bg-none text-slate-700">الإدارة</span>
                    </h1>
                </div>

                <div className="flex-1 overflow-y-auto px-4 py-6 px-scrollbar custom-scrollbar">
                    <div className="mb-6">
                        <p className="px-4 text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">الرئيسية</p>
                        <nav className="space-y-1">
                            <SidebarItem icon={LayoutDashboard} label="لوحة القيادة" path="/" active={location.pathname === '/'} />
                            <SidebarItem icon={Settings} label="إدارة الخدمات والتسعير" path="/services" active={location.pathname === '/services'} />
                            <SidebarItem icon={ClipboardList} label="إدارة الطلبات" path="/orders" active={location.pathname === '/orders'} />
                            <SidebarItem icon={Wrench} label="طلبات الصيانة" path="/maintenance" active={location.pathname === '/maintenance'} />
                            <SidebarItem icon={FileSignature} label="العقود الإلكترونية" path="/contracts" active={location.pathname === '/contracts'} />
                            <SidebarItem icon={ShoppingBasket} label="إدارة المتجر" path="/store-products" active={location.pathname === '/store-products'} />
                            <SidebarItem icon={ShoppingBag} label="طلبات المتجر" path="/store-orders" active={location.pathname === '/store-orders'} />
                            <SidebarItem icon={CarFront} label="إدارة السائقين" path="/drivers" active={location.pathname === '/drivers'} />
                            <SidebarItem icon={Users} label="إدارة العملاء" path="/users" active={location.pathname === '/users'} />
                        </nav>
                    </div>

                    <div className="mb-6">
                        <p className="px-4 text-xs font-bold text-slate-400 uppercase tracking-wider mb-2 mt-8">المالية والتسويق</p>
                        <nav className="space-y-1">
                            <SidebarItem icon={Calculator} label="المحاسبة والمالية" path="/accountants" active={location.pathname === '/accountants'} />
                            <SidebarItem icon={Banknote} label="إدارة الرواتب" path="/payroll" active={location.pathname === '/payroll'} />
                            <SidebarItem icon={Megaphone} label="إدارة التسويق" path="/marketing" active={location.pathname === '/marketing'} />
                        </nav>
                    </div>

                    <div className="mb-6">
                        <p className="px-4 text-xs font-bold text-slate-400 uppercase tracking-wider mb-2 mt-8">النظام والتواصل</p>
                        <nav className="space-y-1">
                            <SidebarItem icon={LifeBuoy} label="الدعم الفني والشكاوى" path="/support" active={location.pathname === '/support'} />
                            <SidebarItem icon={ShieldAlert} label="طلبات الحذف (آبل)" path="/account-deletion" active={location.pathname === '/account-deletion'} />
                            <SidebarItem icon={Shield} label="المشرفين والصلاحيات" path="/admins" active={location.pathname === '/admins'} />
                            <SidebarItem icon={BellRing} label="إرسال إشعارات" path="/notifications" active={location.pathname === '/notifications'} />
                            <SidebarItem icon={Settings} label="إعدادات النظام" path="/settings" active={location.pathname === '/settings'} />
                        </nav>
                    </div>
                </div>

                <div className="p-4 border-t border-slate-100/80">
                    <button
                        type="button"
                        onClick={onLogout}
                        className="w-full flex items-center space-x-3 space-x-reverse px-4 py-4 text-slate-500 hover:bg-red-50 hover:text-red-600 rounded-2xl transition-all duration-300 group"
                    >
                        <div className="p-2 rounded-xl bg-transparent group-hover:bg-white group-hover:shadow-sm transition-colors">
                            <LogOut size={20} strokeWidth={2} />
                        </div>
                        <span className="font-bold">تسجيل الخروج</span>
                    </button>
                </div>
            </aside>

            {/* Main Content */}
            <main className="flex-1 flex flex-col overflow-hidden relative">

                {/* Glass Header */}
                <header className="h-24 sticky top-0 z-30 bg-white/70 backdrop-blur-xl border-b border-slate-200/50 flex items-center justify-between px-10 transition-all duration-300">
                    <div className="flex items-center space-x-4 space-x-reverse">
                        <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">
                            {{
                                '/': 'لوحة القيادة',
                                '/orders': 'إدارة الطلبات',
                                '/drivers': 'إدارة السائقين',
                                '/users': 'إدارة العملاء',
                                '/services': 'إدارة الخدمات والتسعير',
                                '/maintenance': 'إدارة طلبات الصيانة',
                                '/contracts': 'العقود الإلكترونية',
                                '/store-products': 'إدارة منتجات المتجر',
                                '/store-orders': 'طلبات المتجر',
                                '/accountants': 'المحاسبة والمالية',
                                '/payroll': 'إدارة الرواتب',
                                '/marketing': 'إدارة التسويق',
                                '/notifications': 'إرسال الإشعارات',
                                '/support': 'الدعم الفني والشكاوى',
                                '/account-deletion': 'طلبات حذف الحساب',
                                '/admins': 'المشرفون والصلاحيات',
                                '/settings': 'إعدادات النظام',
                            }[location.pathname] ?? 'لوحة التحكم'}
                        </h2>
                    </div>

                    <div className="flex items-center space-x-6 space-x-reverse">
                        <div className="hidden md:flex relative group">
                            <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors">
                                <Search size={18} strokeWidth={2.5} />
                            </div>
                            <input
                                type="text"
                                className="bg-white border border-slate-200/80 text-sm rounded-2xl focus:ring-4 focus:ring-blue-600/10 focus:border-blue-500 block w-64 py-2.5 pr-11 pl-4 outline-none transition-all shadow-sm placeholder-slate-400 font-medium"
                                placeholder="بحث سريع..."
                            />
                        </div>

                        <div className="h-8 w-px bg-slate-200 dark:bg-slate-700 hidden md:block"></div>

                        <button 
                            type="button"
                            title="الإشعارات"
                            className="relative p-2.5 text-slate-500 hover:text-blue-600 hover:bg-blue-50 rounded-xl transition-all"
                        >
                            <Bell size={22} strokeWidth={2.5} />
                            <span className="absolute top-2 right-2.5 w-2.5 h-2.5 bg-red-500 rounded-full border-2 border-white"></span>
                        </button>

                        <div className="flex items-center space-x-3 space-x-reverse bg-white p-1.5 pr-4 rounded-full border border-slate-200/80 shadow-sm cursor-pointer hover:shadow-md transition-shadow">
                            <div className="text-left">
                                <p className="font-bold text-slate-700 text-sm leading-tight">المدير العام</p>
                                <p className="text-[10px] font-semibold text-slate-400">Admin</p>
                            </div>
                            <div className="w-10 h-10 rounded-full bg-gradient-to-tr from-slate-100 to-slate-200 border-2 border-white shadow-sm flex items-center justify-center overflow-hidden">
                                <img src={`https://ui-avatars.com/api/?name=Admin&background=eff6ff&color=2563eb&bold=true`} alt="Admin" className="w-full h-full object-cover" />
                            </div>
                        </div>
                    </div>
                </header>

                {/* Page Content */}
                <div className="flex-1 overflow-auto p-10 relative">
                    <div className="max-w-[1600px] mx-auto">
                        <Outlet />
                    </div>
                </div>
            </main>
        </div>
    );
}
