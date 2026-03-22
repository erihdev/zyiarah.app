import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { KeyRound, Mail, ArrowRight, ShieldCheck, AlertCircle } from 'lucide-react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '../services/firebase';

export default function Login() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(false);
    const navigate = useNavigate();

    const handleLogin = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsLoading(true);
        setError(null);

        try {
            await signInWithEmailAndPassword(auth, email, password);
            navigate('/');
        } catch (err: any) {
            console.error("Login error:", err);
            let errorMessage = "حدث خطأ أثناء تسجيل الدخول. يرجى التأكد من البيانات.";
            if (err.code === 'auth/user-not-found' || err.code === 'auth/wrong-password') {
                errorMessage = "البريد الإلكتروني أو كلمة المرور غير صحيحة.";
            } else if (err.code === 'auth/invalid-email') {
                errorMessage = "البريد الإلكتروني المدخل غير صالح.";
            }
            setError(errorMessage);
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center font-tajawal relative bg-slate-50" dir="rtl">
            {/* Background elements */}
            <div className="absolute inset-0 overflow-hidden pointer-events-none">
                <div className="absolute -top-[20%] -right-[10%] w-[70%] h-[70%] rounded-full bg-gradient-to-br from-blue-100 to-indigo-50 blur-3xl opacity-70"></div>
                <div className="absolute top-[40%] -left-[10%] w-[50%] h-[50%] rounded-full bg-gradient-to-tr from-emerald-50 to-teal-50 blur-3xl opacity-60"></div>
                <div className="absolute -bottom-[20%] left-[20%] w-[60%] h-[60%] rounded-full bg-gradient-to-t from-slate-100 to-transparent blur-3xl opacity-80"></div>
            </div>

            <div className="relative w-full max-w-[420px] px-6">
                <div className="bg-white/90 backdrop-blur-2xl rounded-3xl p-10 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/60">

                    <div className="text-center mb-10">
                        <div className="mx-auto w-20 h-20 bg-gradient-to-tr from-blue-600 to-indigo-600 rounded-2xl flex items-center justify-center shadow-lg shadow-blue-500/20 transform -rotate-3 hover:rotate-0 transition-transform duration-500 mb-6">
                            <span className="text-5xl font-black text-white tracking-tighter">Z</span>
                        </div>
                        <h1 className="text-3xl font-extrabold text-slate-800 mb-2 tracking-tight">زيارة أدمن</h1>
                        <p className="text-slate-500 font-medium text-sm">أدخل بيانات الاعتماد للوصول للوحة التحكم</p>
                    </div>

                    {error && (
                        <div className="mb-6 p-4 bg-red-50 border border-red-100 rounded-2xl flex items-start gap-3 text-red-700 text-sm animate-in fade-in slide-in-from-top-2">
                            <AlertCircle size={18} className="shrink-0 mt-0.5" />
                            <p className="font-bold">{error}</p>
                        </div>
                    )}

                    <form onSubmit={handleLogin} className="space-y-6">
                        <div className="space-y-5">
                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors duration-300">
                                    <Mail size={20} strokeWidth={2.5} />
                                </div>
                                <input
                                    type="email"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="w-full bg-slate-50 border border-slate-200 text-slate-800 text-sm rounded-2xl focus:ring-4 focus:ring-blue-600/10 focus:border-blue-600 block py-4 pr-12 pl-4 transition-all duration-300 outline-none font-medium placeholder-slate-400"
                                    placeholder="البريد الإلكتروني"
                                    required
                                />
                            </div>

                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none text-slate-400 group-focus-within:text-blue-600 transition-colors duration-300">
                                    <KeyRound size={20} strokeWidth={2.5} />
                                </div>
                                <input
                                    type="password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="w-full bg-slate-50 border border-slate-200 text-slate-800 text-sm rounded-2xl focus:ring-4 focus:ring-blue-600/10 focus:border-blue-600 block py-4 pr-12 pl-4 transition-all duration-300 outline-none font-medium placeholder-slate-400"
                                    placeholder="كلمة المرور"
                                    required
                                />
                            </div>
                        </div>

                        <div className="flex items-center justify-between text-sm mt-6 mb-8">
                            <label className="flex items-center text-slate-600 cursor-pointer group">
                                <div className="relative flex items-center justify-center w-5 h-5 ml-2">
                                    <input type="checkbox" className="peer w-5 h-5 opacity-0 absolute cursor-pointer" />
                                    <div className="w-5 h-5 rounded-md border-2 border-slate-300 peer-checked:bg-blue-600 peer-checked:border-blue-600 transition-colors flex items-center justify-center">
                                        <ShieldCheck size={14} className="text-white opacity-0 peer-checked:opacity-100 transition-opacity" />
                                    </div>
                                </div>
                                <span className="font-medium group-hover:text-slate-800 transition-colors">تذكرني</span>
                            </label>
                            <a href="#" className="font-bold text-blue-600 hover:text-blue-800 transition-colors">نسيت كلمة المرور؟</a>
                        </div>

                        <button
                            type="submit"
                            disabled={isLoading}
                            className="w-full relative flex items-center justify-center space-x-2 space-x-reverse text-white bg-slate-900 overflow-hidden font-bold rounded-2xl text-lg px-5 py-4 text-center transition-all duration-300 disabled:opacity-70 group hover:shadow-xl hover:shadow-slate-900/20"
                        >
                            <div className="absolute inset-0 bg-gradient-to-r from-blue-600 to-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>
                            {isLoading ? (
                                <div className="w-6 h-6 border-2 border-white/30 border-t-white rounded-full animate-spin relative z-10" />
                            ) : (
                                <div className="flex items-center space-x-2 space-x-reverse relative z-10">
                                    <span>تسجيل الدخول</span>
                                    <ArrowRight size={20} className="transform group-hover:-translate-x-1 transition-transform" />
                                </div>
                            )}
                        </button>
                    </form>

                    <div className="mt-8 text-center">
                        <p className="text-xs text-slate-400 font-medium tracking-wide">نظام الإدارة الآمن مشفر بالكامل</p>
                    </div>
                </div>
            </div>
        </div>
    );
}
