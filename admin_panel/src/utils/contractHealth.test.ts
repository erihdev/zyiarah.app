// مرآةُ صحّةِ العقدِ وبوّابةِ اعتمادِه.
//
// جدولُ الحالاتِ **مشتركٌ بين اللغتَين**: نسخةٌ بعينِها في
// `test/contract_approve_gate_test.dart` بين العلامتَين نفسِهما، وذاك الفحصُ
// يَقرأُ هذا الملفَّ ويُقارِنُ الجدولَين `jsonDecode`اً — فحالةٌ تُضافُ
// لجهةٍ دون الأخرى تَسقط. (والقراءةُ من جهةِ الدارتِ لا من هنا: `node:fs`
// بلا أنواعٍ تحتَ `tsconfig.app.json` فيَسقطُ `npm run build` — فخٌّ مسجَّلٌ
// في هذا المستودعِ وقعتُ فيه ثالثَ مرّة.)
import { describe, it, expect } from 'vitest';
import {
  contractHealthOf,
  contractApproveAllowed,
  contractApproveBlockedReason,
  contractNeedsHuman,
  CONTRACT_HEALTH_TITLES,
  type ContractHealth,
  type ContractDoc,
  contractHealthReason,
} from './contractHealth';

type Row = [ContractDoc, ContractHealth, boolean];

// ── CONTRACT_HEALTH_CASES_BEGIN ──
const CASES: Row[] = [
  [{}, "ok", true],
  [{"status": "pending"}, "ok", true],
  [{"status": "pending", "is_paid": false}, "ok", true],
  [{"status": "pending", "is_paid": true}, "activationStuck", false],
  [{"status": "approved_waiting_payment"}, "ok", false],
  [{"status": "approved_waiting_payment", "is_paid": true},
   "activationStuck", false],
  [{"status": "active", "is_paid": true}, "ok", false],
  [{"status": "pending", "is_paid": true, "plan_validation_failed": true},
   "planMismatch", false],
  [{"status": "pending", "is_paid": true, "contract_activation_failed": true},
   "activationFailed", false],
  [{"status": "active", "is_paid": true, "contract_visits_pending": true},
   "visitsMissing", false],
  [{"status": "pending", "is_paid": true, "contract_visits_pending": true,
    "plan_validation_failed": true}, "planMismatch", false],
  [{"status": "pending", "is_paid": true, "contract_activation_failed": true,
    "contract_visits_pending": true}, "visitsMissing", false]
];
// ── CONTRACT_HEALTH_CASES_END ──

describe('contractHealth — المرآة', () => {
  const rows = CASES;

  it('الاقتطاعُ أصابَ الجدولَ فعلاً — فلا فحصَ على فراغ', () => {
    expect(rows.length).toBeGreaterThanOrEqual(10);
    const seen = new Set(rows.map(r => r[1]));
    expect([...seen].sort()).toEqual(
      ['activationFailed', 'activationStuck', 'ok', 'planMismatch', 'visitsMissing'],
    );
  });

  it.each(rows.map((r, i) => [i, r] as const))(
    'الحالةُ [%i] تُطابقُ الدارت',
    (_i, row) => {
      const [doc, health, approve] = row;
      expect(contractHealthOf(doc)).toBe(health);
      expect(contractApproveAllowed(doc)).toBe(approve);
    },
  );

  it('المدفوعُ المعلَّقُ وحدَه يُحجَبُ بسببٍ منطوق', () => {
    expect(contractApproveBlockedReason({ status: 'pending', is_paid: true }))
      .toBeTruthy();
    expect(contractApproveBlockedReason({ status: 'pending' })).toBeNull();
    expect(contractApproveBlockedReason({ status: 'active', is_paid: true }))
      .toBeNull();
  });

  it('`planMismatch` وحدَها قرارٌ بشريّ — البقيّةُ تُعادُ محاولتُها', () => {
    expect(contractNeedsHuman('planMismatch')).toBe(true);
    for (const h of ['activationFailed', 'activationStuck', 'visitsMissing'] as const) {
      expect(contractNeedsHuman(h)).toBe(false);
    }
  });

  it('نصُّ كلِّ حالةٍ غيرِ سليمةٍ موجودٌ — وبطاقةٌ بلا نصٍّ تُقرأُ عطلاً', () => {
    for (const h of ['planMismatch', 'activationFailed', 'activationStuck',
      'visitsMissing'] as const) {
      expect(CONTRACT_HEALTH_TITLES[h].length).toBeGreaterThan(10);
    }
    expect(CONTRACT_HEALTH_TITLES.ok).toBe('');
  });

  it('نصُّ كلِّ حالةٍ يَحملُ دعواها — والمطابقةُ الحرفيّةُ يَشدُّها فحصُ الدارت', () => {
    const all = Object.values(CONTRACT_HEALTH_TITLES).join(' | ');
    for (const key of ['لا يطابق الباقة', 'لا زيارات ولا بطاقة',
      'وما زال معلَّقاً', 'رصيد بلا مواعيد']) {
      expect(all).toContain(key);
    }
  });
});

// ⟦REASONS⟧
// [doc, expected] — السببُ الذي كتبَه الخادمُ، إن وُجد.
//
// **أُضيفَ لأنّ اللوحةَ تَستورِدُ `contractHealthReason` ولم يُشغّلْه فحصٌ
// على جهتِها (2026-10-07).** وجدَه `panel_mirror_coverage_test` حين وُسِّعَ
// إلى «كلُّ اسمٍ تَستورِدُه اللوحةُ يَجبُ أن يُشغَّل». والقاعدتانِ متّفقتانِ
// اليومَ — فهذه **سدُّ ثغرةٍ في الحارسِ لا إصلاحُ عطل** — لكنّ انحرافَ
// الترتيبِ أو التهذيبِ كان سيَمُرُّ صامتاً، وهو ما يُعرَضُ على بطاقةِ العقدِ
// سبباً لفشلِ تفعيلِه.
const REASONS: [Record<string, unknown>, string | null][] = [
  [{}, null],
  // الأولويّةُ: خطأُ الخطّةِ أوّلاً (قرارٌ لا عطلٌ عابر).
  [{ plan_validation_error: 'السعر لا يطابق الباقة' }, 'السعر لا يطابق الباقة'],
  [
    {
      plan_validation_error: 'أ',
      contract_visits_error: 'ب',
      contract_activation_error: 'ج',
    },
    'أ',
  ],
  [{ contract_visits_error: 'ب', contract_activation_error: 'ج' }, 'ب'],
  [{ contract_activation_error: 'ج' }, 'ج'],
  // نصٌّ فارغٌ أو فراغاتٌ ليس سبباً — فلا تُعرَضُ بطاقةٌ بلا نصّ.
  [{ plan_validation_error: '' }, null],
  [{ plan_validation_error: '   ' }, null],
  [{ plan_validation_error: '  مهذَّب  ' }, 'مهذَّب'],
  // وغيرُ النصِّ يُتخطّى إلى التالي.
  [{ plan_validation_error: 5, contract_visits_error: 'ب' }, 'ب'],
];
// ⟦/REASONS⟧

describe('contractHealthReason', () => {
  it('الأولويّةُ والتهذيبُ ورفضُ الفراغ', () => {
    for (const [doc, expected] of REASONS) {
      expect(contractHealthReason(doc)).toBe(expected);
    }
  });

  it('ولا سببَ لمستندٍ غائب', () => {
    expect(contractHealthReason(null)).toBe(null);
    expect(contractHealthReason(undefined)).toBe(null);
  });
});
