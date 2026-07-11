import { useEffect, useRef } from 'react';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { db } from '../services/firebase';

/**
 * يستمع لحظيّاً لمجموعة admin_notifications ويُظهر إشعار متصفح لكل تنبيه إداري جديد
 * (طلب جديد، تذكرة دعم، فشل دفع...). حلّ بلا FCM/VAPID — يعمل ما دامت اللوحة مفتوحة،
 * وهي حالة الاستخدام الأساسية للإدارة. يتجاهل الحِمل الأولي كي لا يُغرق عند الدخول.
 */
export default function AdminNotificationsListener() {
    const initialized = useRef(false);

    useEffect(() => {
        if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
            Notification.requestPermission().catch(() => { /* ignore */ });
        }
        const q = query(
            collection(db, 'admin_notifications'),
            orderBy('createdAt', 'desc'),
            limit(20),
        );
        const unsub = onSnapshot(
            q,
            (snap) => {
                if (!initialized.current) {
                    initialized.current = true; // تجاهل اللقطة الأولى (السجل الموجود)
                    return;
                }
                snap.docChanges().forEach((chg) => {
                    if (chg.type !== 'added') return;
                    const d = chg.doc.data() as { title?: string; body?: string };
                    try {
                        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
                            new Notification(d.title || 'تنبيه إداري 🔔', {
                                body: d.body || '',
                                tag: chg.doc.id,
                            });
                        }
                    } catch { /* المتصفح لا يدعم الإشعارات */ }
                });
            },
            () => { /* صامت عند الخطأ */ },
        );
        return () => unsub();
    }, []);

    return null;
}
