import { useState, useEffect, useRef } from 'react';
import { LifeBuoy, Search, MessageSquare, AlertCircle, CheckCircle2, Send, Clock } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, where, limit, Timestamp, doc, updateDoc, addDoc, serverTimestamp, getCountFromServer, type QuerySnapshot, type DocumentData, type QueryDocumentSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase.ts';

// المجموعة الصحيحة هي support_tickets (يكتبها العميل في support_screen.dart والدوال في functions/index.js).
// كانت اللوحة سابقاً مرتبطة بمجموعة وهمية 'tickets' بأسماء حقول خاطئة → صفحة الدعم فارغة دائماً
// وأي رد يُكتب في مجموعة لا يراها العميل ولا يُطلق إشعار sendNotificationOnTicketReply.
interface SupportMessage {
    id: string;
    text: string;
    senderRole?: string;
    senderId?: string;
    senderName?: string;
    sentAt?: Timestamp;
}

interface Ticket {
    id: string;
    userId?: string;
    userEmail?: string;
    subject: string;
    lastMessage?: string;
    status: string; // open | replied | resolved | closed
    createdAt?: Timestamp;
}

export default function Support() {
    const [searchTerm, setSearchTerm] = useState('');
    const [tickets, setTickets] = useState<Ticket[]>([]);
    const [messages, setMessages] = useState<SupportMessage[]>([]);
    const [loading, setLoading] = useState(true);
    const [selected, setSelected] = useState<Ticket | null>(null);
    const [reply, setReply] = useState('');
    const [sending, setSending] = useState(false);
    // فشل المستمع نهائي — حالة خطأ صريحة بزر إعادة بدل «لا توجد تذاكر» المضلّلة.
    const [loadError, setLoadError] = useState(false);
    const [retryKey, setRetryKey] = useState(0);
    // العدّادات بتجميع count() خادمي — القائمة صارت مقيّدة بأحدث 300 فلا يصلح
    // العدّ المحلي فوقها (المُغلق القديم يسقط خارج النافذة).
    const [openCount, setOpenCount] = useState<number | null>(null);
    const [inProgressCount, setInProgressCount] = useState<number | null>(null);
    const [closedCount, setClosedCount] = useState<number | null>(null);
    const messagesEndRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        // (أداء) أحدث 300 تذكرة فقط — كانت المجموعة كلها (بما فيها المحلولة منذ
        // الأزل) تُقرأ مع كل فتح للصفحة.
        const q = query(collection(db, 'support_tickets'), orderBy('createdAt', 'desc'), limit(300));
        const unsub = onSnapshot(q, (snap: QuerySnapshot<DocumentData>) => {
            const data = snap.docs.map((d: QueryDocumentSnapshot<DocumentData>) => ({ id: d.id, ...d.data() } as Ticket));
            setTickets(data);
            setLoading(false);
        }, (e) => {
            console.error('Support tickets listener error:', e);
            setLoading(false);
            setLoadError(true);
        });

        const col = collection(db, 'support_tickets');
        Promise.all([
            getCountFromServer(query(col, where('status', '==', 'open'))),
            getCountFromServer(query(col, where('status', '==', 'replied'))),
            getCountFromServer(query(col, where('status', 'in', ['resolved', 'closed']))),
        ]).then(([o, r, c]) => {
            setOpenCount(o.data().count);
            setInProgressCount(r.data().count);
            setClosedCount(c.data().count);
        }).catch((e) => {
            // فشل العدّادات وحده لا يحجب قائمةً حُمّلت بنجاح — تبقى «...» لا صفراً كاذباً.
            console.error('Support counters error:', e);
        });

        return () => unsub();
    }, [retryKey]);

    // Load messages from subcollection whenever selected ticket changes
    useEffect(() => {
        if (!selected) { setMessages([]); return; }
        const q = query(collection(db, 'support_tickets', selected.id, 'messages'), orderBy('sentAt', 'asc'));
        const unsub = onSnapshot(q, (snap: QuerySnapshot<DocumentData>) => {
            setMessages(snap.docs.map((d: QueryDocumentSnapshot<DocumentData>) => ({ id: d.id, ...d.data() } as SupportMessage)));
        }, (e) => { console.error("Support listener error:", e); });
        return () => unsub();
    }, [selected?.id]);

    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    const filteredTickets = tickets.filter(t =>
        (t.subject || '').includes(searchTerm) ||
        (t.userEmail || '').includes(searchTerm)
    );

    const isAdminMsg = (m: SupportMessage) => m.senderRole === 'admin' || m.senderId === 'admin';

    const handleSend = async () => {
        if (!reply.trim() || !selected || sending) return;
        setSending(true);
        try {
            // نكتب senderRole و senderId='admin' معاً: الأول ليتعرّف عليه تطبيق العميل،
            // والثاني ليُطلق مُشغّل sendNotificationOnTicketReply إشعار «تم الرد على تذكرتك» للعميل.
            await addDoc(collection(db, 'support_tickets', selected.id, 'messages'), {
                text: reply.trim(),
                senderRole: 'admin',
                senderId: 'admin',
                senderName: 'فريق زيارة',
                sentAt: serverTimestamp(),
            });
            await updateDoc(doc(db, 'support_tickets', selected.id), {
                status: 'replied',
                updatedAt: serverTimestamp(),
            });
            setReply('');
        } catch (e) {
            console.error('send reply failed:', e);
        } finally {
            setSending(false);
        }
    };

    const handleClose = async () => {
        if (!selected) return;
        await updateDoc(doc(db, 'support_tickets', selected.id), { status: 'resolved', updatedAt: serverTimestamp() });
        setSelected(prev => prev ? { ...prev, status: 'resolved' } : null);
    };

    const statusLabel = (s: string) => s === 'open' ? 'مفتوحة' : s === 'replied' ? 'تم الرد' : s === 'resolved' ? 'تم الحل' : s === 'closed' ? 'مغلقة' : s;
    const statusClasses = (s: string) => s === 'open' ? 'text-rose-600 bg-rose-50 border-rose-100'
        : s === 'resolved' || s === 'closed' ? 'text-emerald-600 bg-emerald-50 border-emerald-100'
        : 'text-[#660033] bg-[#FAF1F6] border-[#F2DEE9]';

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
                        <LifeBuoy className="text-[#660033]" />
                        الدعم الفني والشكاوى (حي)
                    </h2>
                    <p className="text-slate-500 font-medium text-sm mt-1">إدارة تذاكر الدعم والمنازعات لحظة بلحظة — يعرض أحدث 300 تذكرة</p>
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
                    <h3 className="text-3xl font-extrabold text-slate-800">{openCount ?? '...'}</h3>
                </div>
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex flex-col border-l-4 border-l-[#660033]">
                    <div className="flex justify-between items-start mb-4">
                        <div className="w-10 h-10 bg-[#FAF1F6] text-[#660033] rounded-xl flex items-center justify-center"><MessageSquare size={20} /></div>
                        <Clock size={16} className="text-slate-300 mt-2" />
                    </div>
                    <p className="text-sm font-bold text-slate-500 mb-1">تم الرد عليها</p>
                    <h3 className="text-3xl font-extrabold text-slate-800">{inProgressCount ?? '...'}</h3>
                </div>
                <div className="bg-white rounded-3xl p-6 border border-slate-100 shadow-[0_4px_20px_rgb(0,0,0,0.03)] flex flex-col border-l-4 border-l-emerald-500">
                    <div className="flex justify-between items-start mb-4">
                        <div className="w-10 h-10 bg-emerald-50 text-emerald-600 rounded-xl flex items-center justify-center"><CheckCircle2 size={20} /></div>
                    </div>
                    <p className="text-sm font-bold text-slate-500 mb-1">تم الحل / الإغلاق</p>
                    <h3 className="text-3xl font-extrabold text-slate-800">{closedCount ?? '...'}</h3>
                </div>
            </div>

            <div className="flex gap-6 h-[600px]">
                {/* Tickets List */}
                <div className="w-1/3 bg-white rounded-[24px] shadow-[0_4px_20px_rgb(0,0,0,0.03)] border border-slate-100/60 flex flex-col">
                    <div className="p-4 border-b border-slate-100 bg-slate-50/50">
                        <div className="relative w-full">
                            <Search className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                            <input type="text" placeholder="ابحث في التذاكر..."
                                className="w-full pl-3 pr-9 py-2 bg-white border border-slate-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-[#660033]/20 focus:border-[#660033] transition-all"
                                value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} />
                        </div>
                    </div>
                    <div className="flex-1 overflow-y-auto p-2">
                        {loading ? (
                            <div className="flex items-center justify-center h-40">
                                <div className="animate-spin rounded-full h-8 w-8 border-4 border-[#660033] border-t-transparent" />
                            </div>
                        ) : loadError ? (
                            // حالة خطأ صريحة لا «لا توجد تذاكر» — الفراغ عند الفشل مضلّل.
                            <div className="flex flex-col items-center justify-center gap-3 py-10 px-4 bg-rose-50/60 rounded-xl border border-rose-100 m-2">
                                <p className="text-rose-600 text-sm font-bold text-center">تعذّر تحميل التذاكر — تحقّق من الاتصال أو الصلاحيات</p>
                                <button
                                    type="button"
                                    onClick={() => { setLoadError(false); setLoading(true); setRetryKey(k => k + 1); }}
                                    className="px-4 py-2 bg-rose-600 text-white rounded-lg font-bold text-sm hover:bg-rose-700 transition-colors"
                                >
                                    إعادة المحاولة
                                </button>
                            </div>
                        ) : filteredTickets.length === 0 ? (
                            <p className="text-center text-slate-400 text-sm py-10 font-bold">لا توجد تذاكر دعم حالياً</p>
                        ) : filteredTickets.map((ticket) => (
                            <div key={ticket.id}
                                onClick={() => setSelected(ticket)}
                                className={`p-4 rounded-xl cursor-pointer transition-colors mb-2 ${selected?.id === ticket.id ? 'bg-[#FAF1F6] border border-[#E5C3D5]' : 'hover:bg-slate-50 border border-transparent hover:border-slate-100'}`}>
                                <div className="flex justify-between items-center mb-1">
                                    <span className="text-xs font-bold text-slate-400 font-mono">#{ticket.id.substring(0, 6).toUpperCase()}</span>
                                    {ticket.status === 'open' && <span className="w-2 h-2 rounded-full bg-rose-500 animate-pulse" />}
                                    {ticket.status === 'replied' && <span className="w-2 h-2 rounded-full bg-[#660033]" />}
                                </div>
                                <h4 className="font-bold text-slate-800 text-sm mb-1 line-clamp-2">{ticket.subject || 'مشكلة غير محددة'}</h4>
                                <div className="flex justify-between items-center text-xs text-slate-500">
                                    <span className="flex items-center gap-1 truncate max-w-[60%]">
                                        <div className="w-4 h-4 bg-slate-200 rounded-full flex items-center justify-center text-[8px] font-bold shrink-0">{(ticket.userEmail || 'U')[0]}</div>
                                        <span className="truncate">{ticket.userEmail || 'مجهول'}</span>
                                    </span>
                                    <span>{relativeTime(ticket.createdAt)}</span>
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
                                        <span className={`text-xs font-bold px-2 py-1 rounded border ${statusClasses(selected.status)}`}>
                                            {statusLabel(selected.status)}
                                        </span>
                                        <span className="text-xs font-bold text-slate-400 font-mono">#{selected.id.substring(0, 8).toUpperCase()}</span>
                                    </div>
                                    <h3 className="text-lg font-extrabold text-slate-800">{selected.subject}</h3>
                                    <p className="text-sm text-slate-500 mt-1">من: <strong>{selected.userEmail || 'عميل'}</strong></p>
                                </div>
                                {selected.status !== 'resolved' && selected.status !== 'closed' && (
                                    <button type="button" onClick={handleClose} className="px-4 py-2 bg-slate-50 text-slate-600 hover:bg-slate-100 font-bold rounded-lg border border-slate-200 text-sm transition-colors">
                                        إغلاق التذكرة ✓
                                    </button>
                                )}
                            </div>

                            <div className="flex-1 overflow-y-auto p-6 space-y-5 z-10">
                                {messages.map((msg: SupportMessage) => {
                                    const admin = isAdminMsg(msg);
                                    return (
                                    <div key={msg.id} className={`flex gap-4 max-w-2xl ${admin ? 'mr-auto flex-row-reverse' : ''}`}>
                                        <div className={`w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-sm font-bold mt-1 ${admin ? 'bg-gradient-to-br from-[#660033] to-[#660033] text-white' : 'bg-slate-100 border border-slate-200 text-slate-600'}`}>
                                            {admin ? 'Z' : (selected.userEmail || 'U')[0]}
                                        </div>
                                        <div className={admin ? 'text-left' : ''}>
                                            <div className={`rounded-2xl p-4 text-sm leading-relaxed ${admin ? 'bg-[#660033] text-white rounded-tl-sm text-right' : 'bg-slate-50 border border-slate-100 text-slate-700 rounded-tr-sm'}`}>
                                                {msg.text}
                                            </div>
                                            <span className="text-xs text-slate-400 mt-1 inline-block">
                                                {msg.sentAt instanceof Timestamp ? msg.sentAt.toDate().toLocaleTimeString('ar-EG') : ''}
                                                {admin ? ' (أنت)' : ''}
                                            </span>
                                        </div>
                                    </div>
                                    );
                                })}
                                {messages.length === 0 && (
                                    <div className="text-center py-10 text-slate-400">
                                        <MessageSquare size={40} className="mx-auto mb-3 opacity-30" />
                                        <p className="font-bold text-sm">لا توجد رسائل بعد. كن أول من يرد!</p>
                                    </div>
                                )}
                                <div ref={messagesEndRef} />
                            </div>

                            {selected.status !== 'resolved' && selected.status !== 'closed' && (
                                <div className="p-4 border-t border-slate-100 bg-white z-10">
                                    <div className="relative">
                                        <textarea
                                            rows={3}
                                            value={reply}
                                            onChange={(e) => setReply(e.target.value)}
                                            onKeyDown={(e) => { if (e.key === 'Enter' && e.ctrlKey) handleSend(); }}
                                            className="w-full bg-[#f8fafc] border border-slate-200 text-slate-700 text-sm rounded-xl px-4 py-3 outline-none focus:border-[#660033] focus:ring-2 focus:ring-[#660033]/20 transition-all resize-none block pr-14"
                                            placeholder="اكتب ردك هنا... (Ctrl+Enter للإرسال)"
                                        />
                                          <button
                                            type="button"
                                            title="إرسال رسالة"
                                            onClick={handleSend}
                                            disabled={sending || !reply.trim()}
                                            className="absolute left-3 bottom-3 w-10 h-10 bg-[#660033] disabled:bg-slate-300 text-white flex items-center justify-center rounded-lg hover:bg-[#4D0026] transition-colors shadow-sm">
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
