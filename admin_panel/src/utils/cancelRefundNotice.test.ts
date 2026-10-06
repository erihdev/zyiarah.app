// «ماذا يَحدثُ لمالِ العميلةِ إن أُلغيَ الطلب؟» — القاعدةُ سلوكاً.
//
// جدولُ الحالاتِ **مشتركٌ بين اللغتَين**: نسخةٌ بعينِها في
// `test/cancel_refund_panel_test.dart` بين العلامتَين نفسِهما، وذاك الفحصُ
// يَقرأُ هذا الملفَّ ويُقارِنُ الجدولَين `jsonDecode`اً. (والقراءةُ من جهةِ
// الدارتِ لا من هنا: `node:fs` بلا أنواعٍ تحتَ `tsconfig.app.json`.)
import { describe, it, expect } from 'vitest';
import { cancelRefundNotice, cancelRefundAdminText } from './cancelRefundNotice.ts';

type Row = [{isPaid: boolean; paymentMethod?: string | null; amount?: number | null},
  string, number | null];

// ── CANCEL_REFUND_CASES_BEGIN ──
const CASES: Row[] = [
  [{"isPaid": false}, "nothingPaid", null],
  [{"isPaid": false, "amount": 120}, "nothingPaid", null],
  [{"isPaid": false, "paymentMethod": "subscription"}, "nothingPaid", null],
  [{"isPaid": true, "paymentMethod": "subscription"}, "subscriptionVisit", null],
  [{"isPaid": true, "paymentMethod": "subscription", "amount": 0}, "subscriptionVisit", null],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": 120.5}, "walletCredit", 120.5],
  [{"isPaid": true, "paymentMethod": "tamara", "amount": 300}, "walletCredit", 300],
  [{"isPaid": true, "paymentMethod": "wallet", "amount": 75}, "walletCredit", 75],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": 0}, "walletCredit", null],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": -5}, "walletCredit", null],
  [{"isPaid": true, "paymentMethod": "moyasar"}, "walletCredit", null],
  [{"isPaid": true}, "walletCredit", null]
];
// ── CANCEL_REFUND_CASES_END ──

describe('cancelRefundNotice', () => {
  it.each(CASES.map((r, i) => [i, r] as const))('الحالةُ [%i]', (_i, row) => {
    const [input, kind, amount] = row;
    const n = cancelRefundNotice(input);
    expect(n.kind).toBe(kind);
    expect(n.amount).toBe(amount);
  });

  it('الجدولُ يَصِفُ الحالاتِ الثلاثَ كلَّها', () => {
    expect(new Set(CASES.map(r => r[1])).size).toBe(3);
    expect(CASES.length).toBeGreaterThanOrEqual(10);
  });
});

describe('cancelRefundAdminText', () => {
  it('غيرُ المدفوعِ بلا جملةِ مالٍ إطلاقاً', () => {
    expect(cancelRefundAdminText({kind: 'nothingPaid', amount: null})).toBe('');
  });

  it('زيارةُ الباقةِ: لا مبلغَ يُعاد، والزيارةُ تبقى في الرصيد', () => {
    const t = cancelRefundAdminText({kind: 'subscriptionVisit', amount: null});
    expect(t).toContain('لا مبلغَ يُعاد');
    expect(t).toContain('رصيد الباقة');
    // ولا رقمَ ولا وعدَ محفظةٍ — كان هذا بعينُه ما يَجعلُ جملةً واحدةً كذباً.
    expect(t).not.toContain('محفظة العميلة');
  });

  it('المدفوعُ: المحفظةُ صريحةً و«لا استرداد إلى البطاقة»', () => {
    const t = cancelRefundAdminText({kind: 'walletCredit', amount: 120.5});
    expect(t).toContain('120.50 ر.س');
    expect(t).toContain('محفظة العميلة');
    expect(t).toContain('لا استرداد إلى البطاقة');
  });

  it('عندَ جهلِ المقدارِ: جملةٌ بلا رقمٍ مُلفَّق', () => {
    const t = cancelRefundAdminText({kind: 'walletCredit', amount: null});
    expect(t).toContain('المبلغُ المدفوع');
    expect(t).not.toMatch(/\d/);
  });

  it('الإحالةُ تَتبعُ قدرةَ السطح — تقسيطٌ هنا، وبطاقةٌ في تطبيقِ الإدارة', () => {
    const bnpl = cancelRefundAdminText({kind: 'walletCredit', amount: 300},
      {bnplRefundHere: true});
    expect(bnpl).toContain('هذا الصف');
    const card = cancelRefundAdminText({kind: 'walletCredit', amount: 300});
    expect(card).toContain('تطبيق الإدارة');
    expect(card).not.toContain('هذا الصف');
  });
});
