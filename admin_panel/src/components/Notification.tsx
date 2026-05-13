import { createContext, useContext, useState, useCallback, useRef } from 'react';
import type { ReactNode } from 'react';
import { CheckCircle2, XCircle, Info, X, AlertTriangle } from 'lucide-react';

// ─── Types ────────────────────────────────────────────────────────────────────

type ToastType = 'success' | 'error' | 'info';

interface ToastItem {
    id: string;
    message: string;
    type: ToastType;
}

interface ConfirmState {
    message: string;
    resolve: (value: boolean) => void;
}

interface NotificationContextType {
    toast: {
        success: (msg: string) => void;
        error: (msg: string) => void;
        info: (msg: string) => void;
    };
    confirm: (msg: string) => Promise<boolean>;
}

// ─── Context ──────────────────────────────────────────────────────────────────

const NotificationContext = createContext<NotificationContextType>({
    toast: { success: () => {}, error: () => {}, info: () => {} },
    confirm: () => Promise.resolve(false),
});

// ─── Provider ─────────────────────────────────────────────────────────────────

export function NotificationProvider({ children }: { children: ReactNode }) {
    const [toasts, setToasts] = useState<ToastItem[]>([]);
    const [confirmState, setConfirmState] = useState<ConfirmState | null>(null);
    const idRef = useRef(0);

    const addToast = useCallback((message: string, type: ToastType) => {
        const id = String(++idRef.current);
        setToasts(prev => [...prev, { id, message, type }]);
        setTimeout(() => setToasts(prev => prev.filter(t => t.id !== id)), 4000);
    }, []);

    const dismissToast = useCallback((id: string) => {
        setToasts(prev => prev.filter(t => t.id !== id));
    }, []);

    const toast = {
        success: (msg: string) => addToast(msg, 'success'),
        error:   (msg: string) => addToast(msg, 'error'),
        info:    (msg: string) => addToast(msg, 'info'),
    };

    const confirm = useCallback((message: string): Promise<boolean> => {
        return new Promise<boolean>(resolve => {
            setConfirmState({ message, resolve });
        });
    }, []);

    const handleConfirm = (value: boolean) => {
        confirmState?.resolve(value);
        setConfirmState(null);
    };

    const toastStyles: Record<ToastType, string> = {
        success: 'bg-emerald-50 border-emerald-200 text-emerald-800',
        error:   'bg-red-50 border-red-200 text-red-800',
        info:    'bg-blue-50 border-blue-200 text-blue-800',
    };

    const ToastIcon = ({ type }: { type: ToastType }) => {
        if (type === 'success') return <CheckCircle2 size={17} className="text-emerald-600 shrink-0" />;
        if (type === 'error')   return <XCircle      size={17} className="text-red-600 shrink-0" />;
        return <Info size={17} className="text-blue-600 shrink-0" />;
    };

    return (
        <NotificationContext.Provider value={{ toast, confirm }}>
            {children}

            {/* ── Toast Stack ── */}
            <div
                className="fixed bottom-6 left-6 z-[9999] flex flex-col gap-2 w-[340px] max-w-[calc(100vw-3rem)] pointer-events-none"
                dir="rtl"
            >
                {toasts.map(t => (
                    <div
                        key={t.id}
                        className={`flex items-center gap-3 px-4 py-3 rounded-2xl shadow-xl border text-sm font-semibold pointer-events-auto animate-in slide-in-from-bottom-3 duration-300 ${toastStyles[t.type]}`}
                    >
                        <ToastIcon type={t.type} />
                        <span className="flex-1 leading-snug">{t.message}</span>
                        <button
                            type="button"
                            onClick={() => dismissToast(t.id)}
                            className="opacity-40 hover:opacity-80 transition-opacity shrink-0"
                        >
                            <X size={14} />
                        </button>
                    </div>
                ))}
            </div>

            {/* ── Confirm Dialog ── */}
            {confirmState && (
                <div
                    className="fixed inset-0 z-[9998] flex items-center justify-center bg-black/40 backdrop-blur-sm"
                    dir="rtl"
                    onClick={(e) => { if (e.target === e.currentTarget) handleConfirm(false); }}
                >
                    <div className="bg-white rounded-3xl p-8 max-w-sm w-full mx-4 shadow-2xl animate-in zoom-in-95 duration-200">
                        <div className="w-14 h-14 bg-amber-100 rounded-2xl flex items-center justify-center mx-auto mb-5">
                            <AlertTriangle size={26} className="text-amber-600" />
                        </div>
                        <h3 className="text-center font-black text-slate-800 text-lg mb-2">تأكيد العملية</h3>
                        <p className="text-center text-slate-500 font-medium mb-8 leading-relaxed text-sm">
                            {confirmState.message}
                        </p>
                        <div className="flex gap-3">
                            <button
                                type="button"
                                onClick={() => handleConfirm(false)}
                                className="flex-1 py-3 rounded-xl bg-slate-100 text-slate-700 font-bold hover:bg-slate-200 transition-colors text-sm"
                            >
                                إلغاء
                            </button>
                            <button
                                type="button"
                                onClick={() => handleConfirm(true)}
                                className="flex-1 py-3 rounded-xl bg-red-600 text-white font-bold hover:bg-red-700 transition-colors text-sm"
                            >
                                تأكيد
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </NotificationContext.Provider>
    );
}

export const useNotification = () => useContext(NotificationContext);
