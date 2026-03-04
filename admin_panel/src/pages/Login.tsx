import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { KeyRound, Mail, ArrowRight } from 'lucide-react';

export default function Login() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const navigate = useNavigate();

    const handleLogin = (e: React.FormEvent) => {
        e.preventDefault();
        setIsLoading(true);

        // Simulate login
        setTimeout(() => {
            setIsLoading(false);
            navigate('/');
        }, 1500);
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-slate-50 font-tajawal" dir="rtl">

            {/* Decorative Background */}
            <div className="absolute inset-0 overflow-hidden pointer-events-none">
                <div className="absolute -top-40 -right-40 w-96 h-96 bg-blue-600 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob"></div>
                <div className="absolute top-40 -left-20 w-72 h-72 bg-emerald-500 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob animation-delay-2000"></div>
                <div className="absolute -bottom-40 left-40 w-80 h-80 bg-orange-500 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob animation-delay-4000"></div>
            </div>

            <div className="relative w-full max-w-md p-8">
                <div className="bg-white/80 backdrop-blur-xl rounded-3xl p-8 shadow-2xl border border-white/50">

                    <div className="text-center mb-10">
                        <div className="w-16 h-16 bg-gradient-to-br from-blue-600 to-indigo-700 rounded-2xl flex items-center justify-center shadow-lg shadow-blue-500/30 mx-auto mb-6 transform -rotate-6 hover:rotate-0 transition-transform duration-300">
                            <span className="text-4xl font-black text-white">Z</span>
                        </div>
                        <h1 className="text-3xl font-bold text-slate-800 mb-2 tracking-tight">لوحة الإدارة</h1>
                        <p className="text-slate-500 font-medium">مرحباً بعودتك، سجل الدخول للمتابعة</p>
                    </div>

                    <form onSubmit={handleLogin} className="space-y-6">
                        <div className="space-y-4">
                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors">
                                    <Mail size={20} />
                                </div>
                                <input
                                    type="email"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="w-full bg-slate-50/50 border border-slate-200 text-slate-900 text-sm rounded-xl focus:ring-2 focus:ring-blue-600 focus:border-transparent block py-4 pr-12 pl-4 transition-all duration-200 outline-none"
                                    placeholder="البريد الإلكتروني"
                                    required
                                />
                            </div>

                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors">
                                    <KeyRound size={20} />
                                </div>
                                <input
                                    type="password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="w-full bg-slate-50/50 border border-slate-200 text-slate-900 text-sm rounded-xl focus:ring-2 focus:ring-blue-600 focus:border-transparent block py-4 pr-12 pl-4 transition-all duration-200 outline-none"
                                    placeholder="كلمة المرور"
                                    required
                                />
                            </div>
                        </div>

                        <div className="flex items-center justify-between text-sm">
                            <label className="flex items-center text-slate-600 cursor-pointer">
                                <input type="checkbox" className="w-4 h-4 rounded text-blue-600 focus:ring-blue-600 ml-2" />
                                تذكرني
                            </label>
                            <a href="#" className="font-bold text-blue-600 hover:text-blue-700 transition-colors">نسيت كلمة المرور؟</a>
                        </div>

                        <button
                            type="submit"
                            disabled={isLoading}
                            className="w-full flex items-center justify-center space-x-2 space-x-reverse text-white bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-xl text-lg px-5 py-4 text-center shadow-lg shadow-blue-500/30 transition-all duration-300 disabled:opacity-70"
                        >
                            {isLoading ? (
                                <div className="w-6 h-6 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                            ) : (
                                <>
                                    <span>تسجيل الدخول</span>
                                    <ArrowRight size={20} />
                                </>
                            )}
                        </button>
                    </form>

                </div>
            </div>
        </div>
    );
}
