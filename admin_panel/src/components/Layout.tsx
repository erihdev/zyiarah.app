import { useState, useEffect } from 'react';
import { Outlet, Link, useLocation } from 'react-router-dom';
import {
    LayoutDashboard, Users, CarFront, ClipboardList, Settings, LogOut,
    Bell, Search, Calculator, Megaphone, BellRing, LifeBuoy, Shield,
    ShieldAlert, Wrench, FileSignature, ShoppingBasket, ShoppingBag,
    Banknote, Menu, X
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

type ColorKey = 'blue' | 'violet' | 'orange' | 'amber' | 'teal' | 'green' | 'emerald'
    | 'indigo' | 'pink' | 'cyan' | 'rose' | 'yellow' | 'red' | 'sky' | 'slate';

interface NavItem { icon: LucideIcon; label: string; path: string; color: ColorKey; }
interface NavGroup { label: string; items: NavItem[]; }

const iconColors: Record<ColorKey, string> = {
    blue:    'bg-blue-100 text-blue-600',
    violet:  'bg-violet-100 text-violet-600',
    orange:  'bg-orange-100 text-orange-600',
    amber:   'bg-amber-100 text-amber-700',
    teal:    'bg-teal-100 text-teal-600',
    green:   'bg-green-100 text-green-600',
    emerald: 'bg-emerald-100 text-emerald-600',
    indigo:  'bg-indigo-100 text-indigo-600',
    pink:    'bg-pink-100 text-pink-600',
    cyan:    'bg-cyan-100 text-cyan-600',
    rose:    'bg-rose-100 text-rose-600',
    yellow:  'bg-yellow-100 text-yellow-700',
    red:     'bg-red-100 text-red-600',
    sky:     'bg-sky-100 text-sky-600',
    slate:   'bg-slate-100 text-slate-600',
};

const navGroups: NavGroup[] = [
    {
        label: 'الرئيسية',
        items: [
            { icon: LayoutDashboard, label: 'لوحة القيادة',         path: '/',               color: 'blue' },
            { icon: Settings,        label: 'الخدمات والتسعير',      path: '/services',       color: 'violet' },
            { icon: ClipboardList,   label: 'إدارة الطلبات',         path: '/orders',         color: 'orange' },
            { icon: Wrench,          label: 'طلبات الصيانة',          path: '/maintenance',    color: 'amber' },
            { icon: FileSignature,   label: 'العقود الإلكترونية',    path: '/contracts',      color: 'teal' },
            { icon: ShoppingBasket,  label: 'إدارة المتجر',           path: '/store-products', color: 'green' },
            { icon: ShoppingBag,     label: 'طلبات المتجر',           path: '/store-orders',   color: 'emerald' },
            { icon: CarFront,        label: 'إدارة السائقين',         path: '/drivers',        color: 'indigo' },
            { icon: Users,           label: 'إدارة العملاء',          path: '/users',          color: 'pink' },
        ],
    },
    {
        label: 'المالية والتسويق',
        items: [
            { icon: Calculator,      label: 'المحاسبة والمالية',      path: '/accountants',    color: 'emerald' },
            { icon: Banknote,        label: 'إدارة الرواتب',           path: '/payroll',        color: 'cyan' },
            { icon: Megaphone,       label: 'إدارة التسويق',           path: '/marketing',      color: 'rose' },
        ],
    },
    {
        label: 'النظام والتواصل',
        items: [
            { icon: LifeBuoy,        label: 'الدعم الفني والشكاوى',   path: '/support',        color: 'yellow' },
            { icon: ShieldAlert,     label: 'طلبات الحذف (آبل)',      path: '/account-deletion', color: 'red' },
            { icon: Shield,          label: 'المشرفون والصلاحيات',    path: '/admins',         color: 'violet' },
            { icon: BellRing,        label: 'إرسال إشعارات',          path: '/notifications',  color: 'sky' },
            { icon: Settings,        label: 'إعدادات النظام',          path: '/settings',       color: 'slate' },
        ],
    },
];

const pageTitles: Record<string, string> = {
    '/':                 'لوحة القيادة',
    '/orders':           'إدارة الطلبات',
    '/drivers':          'إدارة السائقين',
    '/users':            'إدارة العملاء',
    '/services':         'إدارة الخدمات والتسعير',
    '/maintenance':      'إدارة طلبات الصيانة',
    '/contracts':        'العقود الإلكترونية',
    '/store-products':   'إدارة منتجات المتجر',
    '/store-orders':     'طلبات المتجر',
    '/accountants':      'المحاسبة والمالية',
    '/payroll':          'إدارة الرواتب',
    '/marketing':        'إدارة التسويق',
    '/notifications':    'إرسال الإشعارات',
    '/support':          'الدعم الفني والشكاوى',
    '/account-deletion': 'طلبات حذف الحساب',
    '/admins':           'المشرفون والصلاحيات',
    '/settings':         'إعدادات النظام',
};

// ─────────────────────────────────────────────
// Sidebar inner content (shared between desktop & mobile drawer)
// ─────────────────────────────────────────────
function SidebarNav({
    currentPath,
    onClose,
    onLogout,
}: {
    currentPath: string;
    onClose?: () => void;
    onLogout?: () => void;
}) {
    return (
        <div className="flex flex-col h-full">
            {/* Logo */}
            <div className="px-5 py-5 flex items-center justify-between border-b border-slate-100 shrink-0">
                <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-blue-600 to-indigo-700 flex items-center justify-center shadow-lg shadow-blue-500/30 shrink-0">
                        <span className="text-white font-black text-xl tracking-tighter">Z</span>
                    </div>
                    <div>
                        <h1 className="text-[17px] font-black text-slate-800 leading-none tracking-tight">زيارة</h1>
                        <p className="text-[11px] font-semibold text-slate-400 mt-0.5">لوحة الإدارة</p>
                    </div>
                </div>
                {onClose && (
                    <button
                        type="button"
                        onClick={onClose}
                        className="lg:hidden p-1.5 rounded-xl text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors"
                    >
                        <X size={19} />
                    </button>
                )}
            </div>

            {/* Nav Groups */}
            <div className="flex-1 overflow-y-auto px-3 py-4 space-y-5 custom-scrollbar">
                {navGroups.map((group) => (
                    <div key={group.label}>
                        <p className="px-2 text-[10px] font-black text-slate-400 uppercase tracking-[0.12em] mb-1.5">
                            {group.label}
                        </p>
                        <nav className="space-y-0.5">
                            {group.items.map((item) => {
                                const active = currentPath === item.path;
                                const Icon = item.icon;
                                return (
                                    <Link
                                        key={item.path}
                                        to={item.path}
                                        className={`group flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all duration-200 ${
                                            active
                                                ? 'bg-gradient-to-l from-blue-600 to-indigo-600 text-white shadow-md shadow-blue-500/20'
                                                : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'
                                        }`}
                                    >
                                        <div className={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 transition-all duration-200 ${
                                            active
                                                ? 'bg-white/20 text-white'
                                                : `${iconColors[item.color]} group-hover:scale-105`
                                        }`}>
                                            <Icon size={15} strokeWidth={2.5} />
                                        </div>
                                        <span className={`text-[13px] font-semibold truncate flex-1 ${active ? 'text-white' : ''}`}>
                                            {item.label}
                                        </span>
                                        {active && (
                                            <div className="w-1.5 h-1.5 rounded-full bg-white/70 shrink-0" />
                                        )}
                                    </Link>
                                );
                            })}
                        </nav>
                    </div>
                ))}
            </div>

            {/* Logout */}
            <div className="px-3 py-3 border-t border-slate-100 shrink-0">
                <button
                    type="button"
                    onClick={onLogout}
                    className="w-full flex items-center gap-3 px-3 py-2.5 text-slate-500 hover:bg-red-50 hover:text-red-600 rounded-xl transition-all duration-200 group"
                >
                    <div className="w-7 h-7 rounded-lg bg-slate-100 group-hover:bg-red-100 flex items-center justify-center shrink-0 transition-colors">
                        <LogOut size={15} strokeWidth={2.5} />
                    </div>
                    <span className="text-[13px] font-bold">تسجيل الخروج</span>
                </button>
            </div>
        </div>
    );
}

// ─────────────────────────────────────────────
// Bottom nav items (mobile)
// ─────────────────────────────────────────────
const bottomNavItems = [
    { icon: LayoutDashboard, label: 'الرئيسية', path: '/' },
    { icon: ClipboardList,   label: 'الطلبات',  path: '/orders' },
    { icon: CarFront,        label: 'السائقين', path: '/drivers' },
    { icon: LifeBuoy,        label: 'الدعم',    path: '/support' },
];

// ─────────────────────────────────────────────
// Main Layout
// ─────────────────────────────────────────────
interface LayoutProps { onLogout?: () => void; }

export default function Layout({ onLogout }: LayoutProps) {
    const location = useLocation();
    const [sidebarOpen, setSidebarOpen] = useState(false);

    // Close drawer on navigation
    useEffect(() => { setSidebarOpen(false); }, [location.pathname]);

    // Lock body scroll when drawer is open
    useEffect(() => {
        document.body.style.overflow = sidebarOpen ? 'hidden' : '';
        return () => { document.body.style.overflow = ''; };
    }, [sidebarOpen]);

    const currentTitle = pageTitles[location.pathname] ?? 'لوحة التحكم';

    return (
        <div className="flex h-screen bg-[#f1f5f9] font-tajawal selection:bg-blue-100 selection:text-blue-900" dir="rtl">

            {/* ── Desktop Sidebar ── */}
            <aside className="hidden lg:flex w-[260px] xl:w-[272px] bg-white border-l border-slate-200/70 shadow-[1px_0_0_rgba(0,0,0,0.03)] flex-col z-20 shrink-0">
                <SidebarNav
                    currentPath={location.pathname}
                    onLogout={onLogout}
                />
            </aside>

            {/* ── Mobile: Dark Overlay ── */}
            <div
                className={`lg:hidden fixed inset-0 z-40 transition-all duration-300 ${
                    sidebarOpen ? 'bg-black/50 backdrop-blur-sm pointer-events-auto' : 'bg-transparent pointer-events-none'
                }`}
                onClick={() => setSidebarOpen(false)}
            />

            {/* ── Mobile: Slide-in Drawer ── */}
            <aside
                className={`lg:hidden fixed top-0 right-0 h-full w-[272px] bg-white shadow-2xl z-50 flex flex-col transition-transform duration-300 ease-in-out ${
                    sidebarOpen ? 'translate-x-0' : 'translate-x-full'
                }`}
            >
                <SidebarNav
                    currentPath={location.pathname}
                    onClose={() => setSidebarOpen(false)}
                    onLogout={onLogout}
                />
            </aside>

            {/* ── Main Content ── */}
            <main className="flex-1 flex flex-col overflow-hidden min-w-0">

                {/* ── Header ── */}
                <header className="h-[60px] lg:h-[72px] sticky top-0 z-30 bg-white/80 backdrop-blur-xl border-b border-slate-200/60 flex items-center justify-between px-4 lg:px-8 shrink-0">

                    {/* Right side: hamburger + title */}
                    <div className="flex items-center gap-3 min-w-0">
                        <button
                            type="button"
                            onClick={() => setSidebarOpen(true)}
                            className="lg:hidden p-2 rounded-xl text-slate-500 hover:text-slate-900 hover:bg-slate-100 transition-colors shrink-0"
                        >
                            <Menu size={20} />
                        </button>
                        <div className="min-w-0">
                            <h2 className="text-[17px] lg:text-xl font-extrabold text-slate-800 leading-tight truncate">
                                {currentTitle}
                            </h2>
                            <p className="hidden lg:block text-[11px] text-slate-400 font-medium mt-0.5">
                                منصة زيارة للخدمات المنزلية
                            </p>
                        </div>
                    </div>

                    {/* Left side: search + notifications + avatar */}
                    <div className="flex items-center gap-2 lg:gap-3 shrink-0">

                        {/* Search — desktop only */}
                        <div className="hidden lg:flex relative group">
                            <div className="absolute inset-y-0 right-0 flex items-center pr-3.5 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors">
                                <Search size={15} strokeWidth={2.5} />
                            </div>
                            <input
                                type="text"
                                className="bg-slate-50 border border-slate-200 text-sm rounded-xl focus:ring-4 focus:ring-blue-600/10 focus:border-blue-500 w-52 py-2 pr-10 pl-4 outline-none transition-all placeholder-slate-400 font-medium"
                                placeholder="بحث سريع..."
                            />
                        </div>

                        {/* Notification bell */}
                        <button
                            type="button"
                            title="الإشعارات"
                            className="relative p-2 text-slate-500 hover:text-blue-600 hover:bg-blue-50 rounded-xl transition-all"
                        >
                            <Bell size={19} strokeWidth={2.5} />
                            <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-red-500 rounded-full border-[1.5px] border-white" />
                        </button>

                        {/* User avatar */}
                        <div className="flex items-center gap-2.5 bg-slate-50 hover:bg-white border border-slate-200/80 rounded-2xl py-1.5 pl-1.5 pr-3 cursor-pointer transition-all hover:shadow-sm">
                            <div className="hidden sm:block text-left leading-none">
                                <p className="text-[13px] font-bold text-slate-700">المدير العام</p>
                                <p className="text-[10px] font-semibold text-slate-400 mt-0.5">Admin</p>
                            </div>
                            <img
                                src="https://ui-avatars.com/api/?name=Admin&background=eff6ff&color=2563eb&bold=true"
                                alt="Admin"
                                className="w-8 h-8 lg:w-9 lg:h-9 rounded-xl object-cover"
                            />
                        </div>
                    </div>
                </header>

                {/* ── Page Content ── */}
                <div className="flex-1 overflow-auto pb-20 lg:pb-0">
                    <div className="p-4 sm:p-6 lg:p-8 max-w-[1600px] mx-auto">
                        <Outlet />
                    </div>
                </div>
            </main>

            {/* ── Mobile Bottom Navigation ── */}
            <nav className="lg:hidden fixed bottom-0 inset-x-0 z-30 bg-white/95 backdrop-blur-xl border-t border-slate-200/80 shadow-[0_-8px_24px_rgba(0,0,0,0.07)]">
                <div className="flex items-stretch h-[62px] safe-area-pb">
                    {bottomNavItems.map((item) => {
                        const active = location.pathname === item.path;
                        const Icon = item.icon;
                        return (
                            <Link
                                key={item.path}
                                to={item.path}
                                className={`flex-1 flex flex-col items-center justify-center gap-1 transition-all duration-200 ${
                                    active ? 'text-blue-600' : 'text-slate-400 active:scale-95'
                                }`}
                            >
                                <div className={`relative transition-transform duration-200 ${active ? 'scale-110' : ''}`}>
                                    <Icon size={21} strokeWidth={active ? 2.5 : 2} />
                                    {active && (
                                        <span className="absolute -bottom-0.5 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-blue-600" />
                                    )}
                                </div>
                                <span className={`text-[10px] font-bold ${active ? 'text-blue-600' : 'text-slate-400'}`}>
                                    {item.label}
                                </span>
                            </Link>
                        );
                    })}

                    {/* Menu button */}
                    <button
                        type="button"
                        onClick={() => setSidebarOpen(true)}
                        className="flex-1 flex flex-col items-center justify-center gap-1 text-slate-400 active:scale-95 transition-transform"
                    >
                        <Menu size={21} strokeWidth={2} />
                        <span className="text-[10px] font-bold">القائمة</span>
                    </button>
                </div>
            </nav>
        </div>
    );
}
