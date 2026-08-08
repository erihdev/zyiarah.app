import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from './firebase.ts';

// سجل التدقيق الإداري — نظير lib/services/audit_service.dart.
//
// **سبب وجوده:** لوحة الويب كانت تكتب في Firestore بلا أي أثر: إضافة كادر،
// تعديل بياناته، إيقافه، تعديل منطقة أو سعرها — كلها تمرّ بلا قيد. فمَن غيّر
// السعر ومتى؟ سؤالٌ بلا جواب متى تمّ التغيير من المتصفح، بينما تطبيق الأدمن
// يسجّل كل واحدة منها.
//
// **المخطط مُلزِم**: شاشة السجل في التطبيق تُرتّب على `timestamp` — وFirestore
// يستبعد المستندات التي لا تحمل حقل الترتيب — وتُطابق أسماء الإجراءات بأحرف
// **كبيرة**. أي انحراف هنا = قيود لا تظهر في الشاشة إطلاقاً.
export const AUDIT = {
    REGISTER_DRIVER: 'REGISTER_DRIVER',
    UPDATE_DRIVER: 'UPDATE_DRIVER',
    TOGGLE_DRIVER_STATUS: 'TOGGLE_DRIVER_STATUS',
    CREATE_ZONE: 'CREATE_ZONE',
    UPDATE_ZONE: 'UPDATE_ZONE',
    DELETE_ZONE: 'DELETE_ZONE',
    TOGGLE_SERVICE_STATUS: 'TOGGLE_SERVICE_STATUS',
    APPLY_PRICES_TO_ZONES: 'APPLY_PRICES_TO_ZONES',
    UPDATE_SETTINGS: 'UPDATE_SETTINGS',
} as const;

export type AuditAction = typeof AUDIT[keyof typeof AUDIT];

/// أفضل-جهد: لا يُسقط العملية الأصلية أبداً. فشل القيد يُسجَّل في الوحدة فقط —
/// إخفاق التدقيق يجب ألا يمنع الأدمن من إتمام عمله.
export async function logAudit(
    action: AuditAction,
    details: Record<string, unknown>,
    targetId?: string,
): Promise<void> {
    try {
        await addDoc(collection(db, 'audit_logs'), {
            admin_email: auth.currentUser?.email ?? 'Unknown Admin',
            action,
            details,
            target_id: targetId ?? null,
            timestamp: serverTimestamp(),
            platform: 'Admin Dashboard (Web)',
        });
    } catch (e) {
        console.error('audit log failed:', action, e);
    }
}
