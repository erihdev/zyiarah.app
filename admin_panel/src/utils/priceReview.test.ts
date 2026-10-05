import { describe, it, expect } from 'vitest';
import {
    priceReviewOf, priceReviewApprovalPayload, priceReviewLine,
    PRICE_REVIEW_QUERY_FLAGS, PRICE_REVIEW_EVIDENCE_FIELDS, COUPON_REJECT_REASONS,
} from './priceReview.ts';

// مرآةُ `lib/utils/price_review.dart`، ومعها سببُ وجودِ الاثنين:
// وسمُ مراجعةِ السعرِ لم يكن له قارئٌ في أيِّ واجهة — صفرُ ورودٍ في `lib/`
// وصفرُ ورودٍ في `admin_panel/src/` — فالإدارةُ تَتلقّى دفعةً بأكوادِ طلباتٍ
// ثمّ تَفتحُ الطلبَ فتَراه عاديّاً تماماً، ولا سبيلَ إلى اعتمادِه. ونافذةُ
// `opsHealthSweep` لا تُصرَّفُ أبداً نتيجةً لذلك.

describe('priceReviewOf — الحالاتُ الثلاث', () => {
    it('لا وسم ⇒ لا بطاقة', () => {
        const r = priceReviewOf({ amount: 300, is_paid: true });
        expect(r.kind).toBe('none');
        expect(r.needsCard).toBe(false);
        expect(r.actionable).toBe(false);
    });

    it('price_mismatch ⇒ underpaid، بأرقامِ الخادم', () => {
        const r = priceReviewOf({
            price_mismatch: true, price_paid: 120,
            price_expected: 300, price_expected_net: 300,
            price_shadow_ratio: 0.4,
        });
        expect(r.kind).toBe('underpaid');
        expect(r.paid).toBe(120);
        expect(r.expected).toBe(300);
        expect(r.ratio).toBe(0.4);
        expect(r.shortfall).toBe(180);
        expect(r.actionable).toBe(true);
    });

    it('price_unverifiable ⇒ unverifiable — جهلٌ لا نقصٌ في الدفع', () => {
        const r = priceReviewOf({ price_unverifiable: true, price_paid: 300 });
        expect(r.kind).toBe('unverifiable');
        expect(r.shortfall).toBeNull();
        expect(r.actionable).toBe(true);
    });

    it('الوسمانِ معاً ⇒ الأولويّةُ للرقمِ على الجهل', () => {
        const r = priceReviewOf({ price_mismatch: true, price_unverifiable: true });
        expect(r.kind).toBe('underpaid');
    });
});

describe('الصافي قبلَ الإجمالي — وإلّا ضُخّم الفارق', () => {
    // مسارُ ميسر يَكتبُ `price_expected` **قبلَ** الخصمِ الموثوقِ
    // و`price_expected_net` بعدَه، والمقارنةُ التي أنتجت الوسمَ على الصافي.
    // فعرضُ الأوّلِ وحدَه يَجعلُ الفارقَ أكبرَ بقيمةِ الكوبون — فتَستردُّ
    // الإدارةُ مالاً لا تَملكُه.
    it('يُقدَّمُ price_expected_net على price_expected', () => {
        const r = priceReviewOf({
            price_mismatch: true, price_paid: 100,
            price_expected: 300, price_expected_net: 150,
        });
        expect(r.expected).toBe(150);
        expect(r.shortfall).toBe(50);
    });

    it('وعند غيابِ الصافي يُقرأُ الإجماليُّ (مسارُ المحفظةِ يَكتبُه وحدَه)', () => {
        const r = priceReviewOf({
            price_mismatch: true, price_paid: 100, price_expected: 200,
        });
        expect(r.expected).toBe(200);
    });
});

describe('الصفرُ قرارٌ لا غياب', () => {
    // خصمٌ بلغَ السعرَ كاملاً مع دفعٍ موجب — `suspiciousZero` خادميّاً. لا
    // نسبةَ له (قسمةٌ على صفر) ولا فارقَ يُستردّ.
    it('متوقَّعٌ صفرٌ ودفعٌ موجب ⇒ suspiciousZero بلا فارق', () => {
        const r = priceReviewOf({
            price_mismatch: true, price_paid: 120, price_expected_net: 0,
        });
        expect(r.suspiciousZero).toBe(true);
        expect(r.shortfall).toBeNull();
        expect(priceReviewLine(r)).toContain('الخصم بلغ السعر كاملاً');
    });

    it('متوقَّعٌ صفرٌ بلا دفعٍ ⇒ ليس مريباً', () => {
        const r = priceReviewOf({
            price_mismatch: true, price_paid: 0, price_expected_net: 0,
        });
        expect(r.suspiciousZero).toBe(false);
    });
});

describe('سببُ رفضِ الكوبون', () => {
    // الكوبونُ المرفوضُ خادميّاً لا يُرفَضُ له الطلب (سباقُ تطبيقٍ ودفعٍ
    // يَبلغُه بحسنِ نيّة)، فالخصمُ مُنح والمبلغُ نقص — والمحاسبةُ لم يكن
    // لها سبيلٌ إلى معرفةِ السبب. وكوبونُ 10% يُنتجُ نسبةَ 0.9 فلا يَبلغُ
    // عتبةَ النصفِ: لا وسمَ ولا تنبيه، والسببُ وحدَه على المستند.
    it('يَظهرُ ولو بلا وسمٍ أصلاً', () => {
        const r = priceReviewOf({ coupon_rejected_reason: 'other_user' });
        expect(r.kind).toBe('none');
        expect(r.needsCard).toBe(true);
        expect(r.actionable).toBe(false);
        expect(r.couponRejectedReason).toBe('other_user');
    });

    it('والسبابُ الستّةُ كلُّها مترجَمة', () => {
        for (const k of ['not_found', 'inactive', 'expired', 'exhausted',
            'other_user', 'other_zone']) {
            expect(COUPON_REJECT_REASONS[k]).toBeTruthy();
        }
    });

    it('سببٌ فارغٌ أو مسافاتٌ ليس سبباً', () => {
        expect(priceReviewOf({ coupon_rejected_reason: '   ' }).couponRejectedReason)
            .toBeNull();
        expect(priceReviewOf({ coupon_rejected_reason: '' }).needsCard).toBe(false);
    });
});

describe('المُعتمَدُ سابقاً يَبقى مرئيّاً', () => {
    // الاعتمادُ يُبطِلُ علمَ الاستعلام، فلو كان الظهورُ معلَّقاً على العلمِ
    // وحدَه لاختفى القرارُ وصاحبُه لحظةَ اتّخاذِه — صمتٌ من الجهةِ الأخرى.
    it('بلا وسمٍ ومع طابعِ مراجعةٍ ⇒ بطاقةٌ بلا زرّ', () => {
        const r = priceReviewOf({
            price_mismatch: false, price_reviewed_at: { seconds: 1 },
            price_reviewed_by: 'a@b.c', price_paid: 120, price_expected: 300,
        });
        expect(r.needsCard).toBe(true);
        expect(r.actionable).toBe(false);
        expect(priceReviewLine(r)).toContain('اعتمدته مراجعة سابقة');
    });
});

describe('حِمْلُ الاعتماد', () => {
    it('يُبطِلُ علمَي الاستعلامِ ويُوقّعُ القرار', () => {
        const p = priceReviewApprovalPayload('a@b.c');
        for (const f of PRICE_REVIEW_QUERY_FLAGS) expect(p[f]).toBe(false);
        expect(p.price_review_decision).toBe('approved');
        expect(p.price_reviewed_by).toBe('a@b.c');
    });

    it('ولا يَمحو حقلَ شاهدٍ واحداً — الرقمُ الذي بُني عليه القرارُ يَبقى', () => {
        const p = priceReviewApprovalPayload('a@b.c');
        for (const f of PRICE_REVIEW_EVIDENCE_FIELDS) {
            expect(Object.prototype.hasOwnProperty.call(p, f)).toBe(false);
        }
    });

    it('والطابعُ الزمنيُّ ليس هنا — يُضيفُه موضعُ النداء', () => {
        // كي يَبقى الملفُّ نقيّاً قابلاً للاختبارِ بلا Firebase.
        const p = priceReviewApprovalPayload('a@b.c');
        expect(Object.prototype.hasOwnProperty.call(p, 'price_reviewed_at'))
            .toBe(false);
    });
});

describe('قراءةُ الأرقامِ من قيمٍ غيرِ رقميّة', () => {
    it('النصُّ الرقميُّ يُقرأ، وغيرُ الرقميِّ null', () => {
        expect(priceReviewOf({ price_mismatch: true, price_paid: '120.5' }).paid)
            .toBe(120.5);
        expect(priceReviewOf({ price_mismatch: true, price_paid: 'abc' }).paid)
            .toBeNull();
        expect(priceReviewOf({ price_mismatch: true }).paid).toBeNull();
    });
});
