import { useState, useEffect } from 'react';
import { Send, BellRing, Smartphone, Users, UserRound, History, Clock, CheckCircle2 } from 'lucide-react';
import { collection, onSnapshot, addDoc, serverTimestamp, query, orderBy, limit } from 'firebase/firestore';
import { db } from '../services/firebase';

export default function Notifications() {
    const [target, setTarget] = useState('all');
    const [title, setTitle] = useState('');
    const [body, setBody] = useState('');
    const [sending, setSending] = useState(false);
    const [success, setSuccess] = useState(false);
    const [history, setHistory] = useState<any[]>([]);

    useEffect(() => {
        const q = query(collection(db, 'notifications_log'), orderBy('sent_at', 'desc'), limit(10));
        const unsub = onSnapshot(q, snap => {
            setHistory(snap.docs.map(d => ({ id: d.id, ...d.data() })));
        });
        return () => unsub();
    }, []);

    const handleSend = async () => {
        if (!title.trim() || !body.trim()) return;
        setSending(true);
        try {
            // 1. Save the log to Firestore - This will trigger the consolidated Cloud Function 'onNotificationCreated'
            // which handles the FCM broadcast to topics (all_users, clients, drivers).
            await addDoc(collection(db, 'notifications_log'), {
                title: title.trim(),
                body: body.trim(),
                target,
                sent_at: serverTimestamp(),
                status: 'pending', // Will be updated by the Cloud Function once processed
            });
            setTitle('');
            setBody('');
            setSuccess(true);
            setTimeout(() => setSuccess(false), 3000);
        } finally {
            setSending(false);
        }
    };

    const targetLabel = (t: string) => {
        if (t === 'all') return 'الجميع';
        if (t === 'clients') return 'العملاء فقط';
        if (t === 'drivers') return 'السائقين فقط';
        return t;
    };

    const relativeTime = (ts: any) => {
        if (!ts?.toDate) return '';
        const diff = Math.floor((Date.now() - ts.toDate().getTime()) / 1000);
        if (diff < 60) return 'منذ لحظات';
        if (diff < 3600) return `منذ ${Math.floor(diff / 60)} دقيقة`;
        if (diff < 86400) return `منذ ${Math.floor(diff / 3600)} ساعة`;
        return `منذ ${Math.floor(diff / 86400)} يوم`;
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight">إدارة الإشعارات (Push Notifications)</h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">أرسل إشعارات فورية لجميع الأجهزة، العملاء، أو السائقين — تسجل تلقائياً في قاعدة البيانات</p>
                </div>
                {history.length > 0 && (
                    <span className="px-4 py-2 bg-indigo-50 text-indigo-700 font-bold rounded-xl border border-indigo-100 text-sm">
                        {history.length} إشعار مُرسل
                    </span>
                )}
            </div>

            {success && (
                <div className="flex items-center gap-3 px-5 py-4 bg-emerald-50 border border-emerald-200 rounded-2xl text-emerald-700 font-bold animate-in fade-in duration-300">
                    <CheckCircle2 size={20} />
                    تم تسجيل الإشعار وإرساله بنجاح! ✅
                </div>
            )}

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                {/* Form */}
                <div className="bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 p-8 space-y-8 relative overflow-hidden">
                    <div className="absolute top-0 right-0 w-40 h-40 bg-indigo-50/50 rounded-bl-full -z-10"></div>
                    <div>
                        <h3 className="text-xl font-extrabold text-slate-800 mb-6 flex items-center gap-2">
                            <BellRing className="text-indigo-600" /> رسالة جديدة
                        </h3>

                        <div className="space-y-6">
                            <div>
                                <label className="block text-sm font-extrabold text-slate-700 mb-3">حدد الشريحة المستهدفة:</label>
                                <div className="grid grid-cols-3 gap-3">
                                    {[
                                        { val: 'all', label: 'الجميع', icon: Smartphone },
                                        { val: 'clients', label: 'العملاء فقط', icon: Users },
                                        { val: 'drivers', label: 'السائقين فقط', icon: UserRound },
                                    ].map(({ val, label, icon: Icon }) => (
                                        <label key={val} className={`cursor-pointer border-2 rounded-xl p-3 flex flex-col items-center justify-center gap-2 transition-all ${target === val ? 'border-indigo-600 bg-indigo-50 text-indigo-700' : 'border-slate-100 hover:border-slate-300 text-slate-500'}`}>
                                            <input type="radio" name="target" className="hidden" checked={target === val} onChange={() => setTarget(val)} />
                                            <Icon size={22} strokeWidth={target === val ? 2.5 : 2} />
                                            <span className="text-xs font-bold">{label}</span>
                                        </label>
                                    ))}
                                </div>
                            </div>

                            <div>
                                <label className="block text-sm font-extrabold text-slate-700 mb-2">عنوان الإشعار</label>
                                <input
                                    type="text"
                                    placeholder="مثال: عرض خاص بمناسبة العيد! 🎊"
                                    className="w-full bg-[#f8fafc] border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3.5 outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20 transition-all font-bold"
                                    value={title}
                                    onChange={(e) => setTitle(e.target.value)}
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-extrabold text-slate-700 mb-2">محتوى الإشعار</label>
                                <textarea
                                    rows={4}
                                    placeholder="اكتب هنا تفاصيل الإشعار الذي سيظهر في شاشة الجوال..."
                                    className="w-full bg-[#f8fafc] border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3.5 outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20 transition-all resize-none leading-relaxed font-medium"
                                    value={body}
                                    onChange={(e) => setBody(e.target.value)}
                                />
                            </div>

                            <button
                                onClick={handleSend}
                                disabled={sending || !title.trim() || !body.trim()}
                                className="w-full flex items-center justify-center gap-2 px-6 py-4 bg-gradient-to-r from-indigo-600 to-violet-600 text-white rounded-xl font-bold hover:from-indigo-700 hover:to-violet-700 transition-all shadow-lg shadow-indigo-500/30 hover:shadow-xl hover:-translate-y-0.5 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:translate-y-0 mt-4"
                            >
                                {sending ? <div className="animate-spin rounded-full h-5 w-5 border-2 border-white border-t-transparent" /> : <Send size={20} />}
                                {sending ? 'جاري الإرسال...' : 'إرسال الإشعار الآن'}
                            </button>
                        </div>
                    </div>
                </div>

                {/* History (Live) */}
                <div className="space-y-4">
                    <h3 className="text-xl font-extrabold text-slate-800 flex items-center gap-2">
                        <History className="text-slate-400" />
                        سجل الإشعارات المُرسلة (حي)
                    </h3>

                    {history.length === 0 ? (
                        <div className="bg-white rounded-2xl border border-slate-100 p-10 text-center shadow-sm">
                            <BellRing size={40} className="mx-auto mb-3 text-slate-200" />
                            <p className="text-slate-400 font-bold text-sm">لا توجد إشعارات مُرسلة بعد</p>
                            <p className="text-slate-300 text-xs mt-1">أرسل أول إشعار وسيظهر هنا لحظياً</p>
                        </div>
                    ) : history.map((notif) => (
                        <div key={notif.id} className="bg-white rounded-2xl border border-slate-100 p-5 shadow-sm hover:shadow-md transition-shadow">
                            <div className="flex justify-between items-start mb-2">
                                <h4 className="font-bold text-slate-800 flex items-center gap-2">
                                    <BellRing size={16} className="text-indigo-500" />
                                    {notif.title}
                                </h4>
                                <span className="text-xs font-bold text-slate-400 flex items-center gap-1 shrink-0">
                                    <Clock size={12} />
                                    {relativeTime(notif.sent_at)}
                                </span>
                            </div>
                            <p className="text-sm text-slate-500 line-clamp-2 mb-3">{notif.body}</p>
                            <span className={`inline-block px-2 py-1 text-xs font-bold rounded ${notif.target === 'all' ? 'bg-slate-100 text-slate-600' : notif.target === 'drivers' ? 'bg-blue-50 text-blue-600' : 'bg-indigo-50 text-indigo-600'}`}>
                                📢 {targetLabel(notif.target)}
                            </span>
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
}
