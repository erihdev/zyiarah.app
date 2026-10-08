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
    // اعتمادُ مبلغٍ وسَمَه تحقّقُ السعرِ الخادميّ — قرارٌ ماليٌّ بشريٌّ
    // يُبطِلُ علمَ المكنسةِ، فلا بدَّ من أثرٍ باسمِ من اتّخذَه. نظيرُه
    // `ZyiarahAuditService.actionReviewOrderPrice` في التطبيق.
    REVIEW_ORDER_PRICE: 'REVIEW_ORDER_PRICE',
    // ── كتاباتٌ إداريّةٌ كانت بلا أثرٍ في اللوحةِ وحدَها (2026-10-08) ──
    //
    // الترويسةُ أعلاه تَقولُ القاعدةَ عامّةً («لوحةُ الويبِ كانت تَكتبُ في
    // Firestore بلا أيِّ أثر… بينما تطبيقُ الأدمنِ يُسجّلُ كلَّ واحدةٍ
    // منها») — وكانت موصولةً بأربعِ صفحاتٍ من اثنتَي عشرة. وكلُّ هذه
    // الأسماءِ **لها تسميةٌ عربيّةٌ سلفاً** في `lib/utils/audit_actions.dart`،
    // فلا مفتاحَ جديداً في الخريطة: الناقصُ كان النداءَ وحدَه.
    PROCESS_ACCOUNT_DELETION: 'PROCESS_ACCOUNT_DELETION',
    APPROVE_CONTRACT: 'APPROVE_CONTRACT',
    DELETE_CONTRACT: 'DELETE_CONTRACT',
    CREATE_SUBSCRIPTION: 'CREATE_SUBSCRIPTION',
    UPDATE_SUBSCRIPTION: 'UPDATE_SUBSCRIPTION',
    DELETE_SUBSCRIPTION: 'DELETE_SUBSCRIPTION',
    CREATE_EVENT_WORKER_PACKAGE: 'CREATE_EVENT_WORKER_PACKAGE',
    UPDATE_EVENT_WORKER_PACKAGE: 'UPDATE_EVENT_WORKER_PACKAGE',
    DELETE_EVENT_WORKER_PACKAGE: 'DELETE_EVENT_WORKER_PACKAGE',
    SEND_BROADCAST: 'SEND_BROADCAST',
    CREATE_PRODUCT: 'CREATE_PRODUCT',
    UPDATE_PRODUCT: 'UPDATE_PRODUCT',
    DELETE_PRODUCT: 'DELETE_PRODUCT',
    CREATE_COUPON: 'CREATE_COUPON',
    UPDATE_COUPON: 'UPDATE_COUPON',
    DELETE_COUPON: 'DELETE_COUPON',
    BAN_USER: 'BAN_USER',
    UNBAN_USER: 'UNBAN_USER',
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
