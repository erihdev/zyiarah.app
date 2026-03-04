import { useState, useEffect, useRef } from 'react';
import { LifeBuoy, Search, MessageSquare, AlertCircle, CheckCircle2, Send, Clock } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, Timestamp, doc, updateDoc, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '../services/firebase';

interface Ticket {
    id: string;
    sender: string;
    userType: string;
    issue: string;
    status: string;
    priority: string;
    messages?: any[];
    created_at?: Timestamp;
    uid?: string;
}

export default function Support() {
    const [searchTerm, setSearchTerm] = useState('');
    const [tickets, setTickets] = useState<Ticket[]>([]);
    const [loading, setLoading] = useState(true);
    const [selected, setSelected] = useState<Ticket | null>(null);
    const [reply, setReply] = useState('');
    const [sending, setSending] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const q = query(collection(db, 'tickets'), orderBy('created_at', 'desc'));
        const unsub = onSnapshot(q, (snap) => {
            const data = snap.docs.map(d => ({ id: d.id, ...d.data() } as Ticket));
            setTickets(data);
            if (!selected && data.length > 0) setSelected(data[0]);
            else if (selected) {
                const updated = data.find(t => t.id === selected.id);
                if (updated) setSelected(updated);
            }
            setLoading(false);
        }, () => setLoading(false));
        return () => unsub();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [selected]);

    const filteredTickets = tickets.filter(t =>
        (t.sender || '').includes(searchTerm) ||
        (t.issue || '').includes(searchTerm)
    );

    const openCount = tickets.filter(t => t.status === 'open').length;
    const inProgressCount = tickets.filter(t => t.status === 'in-progress' || t.status === 'in_progress').length;
    const closedCount = tickets.filter(t => t.status === 'closed').length;

    const handleSend = async () => {
        if (!reply.trim() || !selected) return;
        setSending(true);
        try {
            await addDoc(collection(db, 'tickets', selected.id, 'messages'), {
                text: reply.trim(),
                sender: 'admin',
                senderName: 'فريق زيارة',
                created_at: serverTimestamp(),
            });
            await updateDoc(doc(db, 'tickets', selected.id), {
                status: 'in-progress',
                last_reply: serverTimestamp(),
            });
            setReply('');
        } finally {
            setSending(false);
        }
    };

    const handleClose = async () => {
        if (!selected) return;
        await updateDoc(doc(db, 'tickets', selected.id), { status: 'closed' });
        setSelected(prev => prev ? { ...prev, status: 'closed' } : null);
    };

    const relativeTime = (ts?: Timestamp) => {
        if (!ts) return '';
        const now = Date.now();
        const diff = Math.floor((now - ts.toDate().getTime()) / 1000);
        if (diff < 60) return 'منذ لحظات';
        if (diff < 3600) return `منذ ${Math.floor(diff / 60)} دقيقة`;
        if (diff < 86400) return `منذ ${Math.floor(diff / 3600)} ساعة`;
        return `منذ ${Math.floor(diff / 86400)} يوم`;
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-10">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-6">
                <div>
                    <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
                        <LifeBuoy className="text-blue-600" />
                        الدعم الفني والشكاوى (حي)
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إدارة تذاكر الدعم والمنازعات لحظة بلحظة من الفايربيس</p>
                </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex flex-col border-l-4 border-l-rose-500">
                    <div className="flex justify-between items-start mb-4">
                        <div className="w-10 h-10 bg-rose-50 text-rose-600 rounded-xl flex items-center justify-center"><AlertCircle size={20} /></div>
                        <span className="text-xs font-bold text-rose-600 bg-rose-50 px-2 py-1 rounded-md">عالية الأهمية</span>
                    </div>
                    <p className="text-sm font-bold text-slate-500 mb-1">تذاكر مفتوحة</p>
                    <h3 className="text-3xl font-extrabold text-slate-800">{loading ? '...' : openCount}</h3>
                </div>
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex flex-col border-l-4 border-l-blue-500">
                    <div className="flex justify-between items-start mb-4">
                        <div className="w-10 h-10 bg-blue-50 text-blue-600 rounded-xl flex items-center justify-center"><MessageSquare size={20} /></div>
                        <Clock size={16} className="text-slate-300 mt-2" />
                    </div>
                    <p className="text-sm font-bold text-slate-500 mb-1">قيد المعالجة</p>
                    <h3 className="text-3xl font-extrabold text-slate-800">{loading ? '...' : inProgressCount}</h3>
                </div>
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex flex-col border-l-4 border-l-emerald-500">
                    <div className="flex justify-between items-start mb-4">
                        <div className="w-10 h-10 bg-emerald-50 text-emerald-600 rounded-xl flex items-center justify-center"><CheckCircle2 size={20} /></div>
                    </div>
                    <p className="text-sm font-bold text-slate-500 mb-1">تم الحل</p>
                    <h3 className="text-3xl font-extrabold text-slate-800">{loading ? '...' : closedCount}</h3>
                </div>
            </div>

            <div className="flex gap-6 h-[600px]">
                {/* Tickets List */}
                <div className="w-1/3 bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 flex flex-col">
                    <div className="p-4 border-b border-slate-100 bg-slate-50/50">
                        <div className="relative w-full">
                            <Search className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                            <input type="text" placeholder="ابحث في التذاكر..."
                                className="w-full pl-3 pr-9 py-2 bg-white border border-slate-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all"
                                value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} />
                        </div>
                    </div>
                    <div className="flex-1 overflow-y-auto p-2">
                        {loading ? (
                            <div className="flex items-center justify-center h-40">
                                <div className="animate-spin rounded-full h-8 w-8 border-4 border-blue-500 border-t-transparent" />
                            </div>
                        ) : filteredTickets.length === 0 ? (
                            <p className="text-center text-slate-400 text-sm py-10 font-bold">لا توجد تذاكر دعم حالياً</p>
                        ) : filteredTickets.map((ticket) => (
                            <div key={ticket.id}
                                onClick={() => setSelected(ticket)}
                                className={`p-4 rounded-xl cursor-pointer transition-colors mb-2 ${selected?.id === ticket.id ? 'bg-blue-50 border border-blue-200' : 'hover:bg-slate-50 border border-transparent hover:border-slate-100'}`}>
                                <div className="flex justify-between items-center mb-1">
                                    <span className="text-xs font-bold text-slate-400 font-mono">#{ticket.id.substring(0, 6).toUpperCase()}</span>
                                    {ticket.status === 'open' && <span className="w-2 h-2 rounded-full bg-rose-500 animate-pulse" />}
                                    {(ticket.status === 'in-progress' || ticket.status === 'in_progress') && <span className="w-2 h-2 rounded-full bg-blue-500" />}
                                </div>
                                <h4 className="font-bold text-slate-800 text-sm mb-1 line-clamp-2">{ticket.issue || 'مشكلة غير محددة'}</h4>
                                <div className="flex justify-between items-center text-xs text-slate-500">
                                    <span className="flex items-center gap-1">
                                        <div className="w-4 h-4 bg-slate-200 rounded-full flex items-center justify-center text-[8px] font-bold">{(ticket.sender || 'U')[0]}</div>
                                        {ticket.sender || 'مجهول'} <span className="text-[10px] bg-slate-100 px-1 rounded">{ticket.userType || 'عميل'}</span>
                                    </span>
                                    <span>{relativeTime(ticket.created_at)}</span>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                {/* Ticket Detail */}
                <div className="flex-1 bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 flex flex-col overflow-hidden relative">
                    {!selected ? (
                        <div className="flex flex-col items-center justify-center h-full text-slate-300">
                            <LifeBuoy size={80} />
                            <p className="mt-4 font-bold">اختر تذكرة من القائمة</p>
                        </div>
                    ) : (
                        <>
                            <div className="p-6 border-b border-slate-100 bg-white/80 backdrop-blur z-10 flex justify-between items-start">
                                <div>
                                    <div className="flex gap-2 items-center mb-2">
                                        <span className={`text-xs font-bold px-2 py-1 rounded border ${selected.status === 'open' ? 'text-rose-600 bg-rose-50 border-rose-100' : selected.status === 'closed' ? 'text-emerald-600 bg-emerald-50 border-emerald-100' : 'text-blue-600 bg-blue-50 border-blue-100'}`}>
                                            {selected.status === 'open' ? 'مفتوحة' : selected.status === 'closed' ? 'مغلقة' : 'قيد المعالجة'}
                                        </span>
                                        <span className="text-xs font-bold text-slate-400 font-mono">#{selected.id.substring(0, 8).toUpperCase()}</span>
                                    </div>
                                    <h3 className="text-lg font-extrabold text-slate-800">{selected.issue}</h3>
                                    <p className="text-sm text-slate-500 mt-1">من: <strong>{selected.sender}</strong> ({selected.userType})</p>
                                </div>
                                {selected.status !== 'closed' && (
                                    <button onClick={handleClose} className="px-4 py-2 bg-slate-50 text-slate-600 hover:bg-slate-100 font-bold rounded-lg border border-slate-200 text-sm transition-colors">
                                        إغلاق التذكرة ✓
                                    </button>
                                )}
                            </div>

                            <div className="flex-1 overflow-y-auto p-6 space-y-5 z-10">
                                {(selected.messages || []).map((msg: any, idx: number) => (
                                    <div key={idx} className={`flex gap-4 max-w-2xl ${msg.sender === 'admin' ? 'mr-auto flex-row-reverse' : ''}`}>
                                        <div className={`w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-sm font-bold mt-1 ${msg.sender === 'admin' ? 'bg-gradient-to-br from-blue-600 to-indigo-600 text-white' : 'bg-slate-100 border border-slate-200 text-slate-600'}`}>
                                            {msg.sender === 'admin' ? 'Z' : (selected.sender || 'U')[0]}
                                        </div>
                                        <div className={msg.sender === 'admin' ? 'text-left' : ''}>
                                            <div className={`rounded-2xl p-4 text-sm leading-relaxed ${msg.sender === 'admin' ? 'bg-blue-600 text-white rounded-tl-sm text-right' : 'bg-slate-50 border border-slate-100 text-slate-700 rounded-tr-sm'}`}>
                                                {msg.text}
                                            </div>
                                            <span className="text-xs text-slate-400 mt-1 inline-block">
                                                {msg.created_at instanceof Timestamp ? msg.created_at.toDate().toLocaleTimeString('ar-EG') : ''}
                                                {msg.sender === 'admin' ? ' (أنت)' : ''}
                                            </span>
                                        </div>
                                    </div>
                                ))}
                                {(!selected.messages || selected.messages.length === 0) && (
                                    <div className="text-center py-10 text-slate-400">
                                        <MessageSquare size={40} className="mx-auto mb-3 opacity-30" />
                                        <p className="font-bold text-sm">لا توجد رسائل بعد. كن أول من يرد!</p>
                                    </div>
                                )}
                                <div ref={messagesEndRef} />
                            </div>

                            {selected.status !== 'closed' && (
                                <div className="p-4 border-t border-slate-100 bg-white z-10">
                                    <div className="relative">
                                        <textarea
                                            rows={3}
                                            value={reply}
                                            onChange={(e) => setReply(e.target.value)}
                                            onKeyDown={(e) => { if (e.key === 'Enter' && e.ctrlKey) handleSend(); }}
                                            className="w-full bg-[#f8fafc] border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all resize-none block pr-14"
                                            placeholder="اكتب ردك هنا... (Ctrl+Enter للإرسال)"
                                        />
                                        <button
                                            onClick={handleSend}
                                            disabled={sending || !reply.trim()}
                                            className="absolute left-3 bottom-3 w-10 h-10 bg-blue-600 disabled:bg-slate-300 text-white flex items-center justify-center rounded-lg hover:bg-blue-700 transition-colors shadow-sm">
                                            {sending ? <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" /> : <Send size={18} />}
                                        </button>
                                    </div>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}

