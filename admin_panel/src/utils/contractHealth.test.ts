// مرآةُ صحّةِ العقدِ وبوّابةِ اعتمادِه — **جدولُ الحالاتِ واحدٌ بين
// اللغتَين**: يُقرأُ من `test/contract_approve_gate_test.dart` ويُقارَنُ
// `JSON.parse`اً، فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  contractHealthOf, contractApproveAllowed, contractApproveBlockedReason,
  contractNeedsHuman, CONTRACT_HEALTH_TITLES, type ContractHealth,
  type ContractDoc,
} from './contractHealth.ts';

type Row = [ContractDoc, ContractHealth, boolean];

/** الاقتطاعُ **بموازنةِ الأقواس من آخرِ `]` إلى الوراء** — `indexOf('[')`
 *  أوقعَ حُرّاساً في هذا المستودعِ مرّاتٍ (قوسُ تعليقِ نوعٍ، قوسُ معامَلات). */
function sharedCases(): Row[] {
  const src = readFileSync(
    new URL('../../../test/contract_approve_gate_test.dart', import.meta.url),
    'utf-8',
  );
  const a = src.indexOf('CONTRACT_HEALTH_CASES_BEGIN');
  const b = src.indexOf('CONTRACT_HEALTH_CASES_END');
  if (a < 0 || b < 0 || b <= a) {
    throw new Error('علامتا جدولِ الحالاتِ غابتا عن الملفِّ الدارتيّ');
  }
  const block = src.slice(a, b);
  const end = block.lastIndexOf(']');
  if (end < 0) throw new Error('لا مصفوفةَ حالاتٍ بين العلامتَين');
  let depth = 0;
  let start = -1;
  for (let i = end; i >= 0; i--) {
    if (block[i] === ']') depth++;
    if (block[i] === '[') {
      depth--;
      if (depth === 0) { start = i; break; }
    }
  }
  if (start < 0) throw new Error('قوسٌ غيرُ مُوازَنٍ في جدولِ الحالات');
  return JSON.parse(block.slice(start, end + 1)) as Row[];
}

describe('contractHealth — المرآة', () => {
  const rows = sharedCases();

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

  it('النصوصُ حرفيّاً كما في `kContractHealthTitles` الدارتيّة', () => {
    const dart = readFileSync(
      new URL('../../../lib/utils/contract_health.dart', import.meta.url),
      'utf-8',
    );
    // الفواصلُ في الدارتِ نصوصٌ مُلتصقةٌ على أسطُر، فتُطابَقُ كلماتُها
    // الحاسمةُ لا الجملةُ كاملةً: المقصودُ أن لا تَنحرِفَ الدعوى.
    for (const key of ['لا يطابق الباقة', 'لا زيارات ولا بطاقة',
      'وما زال معلَّقاً', 'رصيد بلا مواعيد']) {
      expect(dart).toContain(key);
      expect(Object.values(CONTRACT_HEALTH_TITLES).join(' | ')).toContain(key);
    }
  });
});
