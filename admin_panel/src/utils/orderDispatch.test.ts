import { describe, it, expect } from 'vitest';
import { orderPaidForDispatch, UNPAID_DISPATCH_REFUSAL } from './orderDispatch.ts';

// جدولُ الحالاتِ **واحدٌ بين اللغتَين**: `test/unpaid_dispatch_guard_test.dart`
// يَقرأُ هذه الكتلةَ بعينِها ويُقارِنُها `jsonDecode`اً، فحالةٌ تُضافُ لجهةٍ
// دون الأخرى تَسقط. والمفاتيحُ **أصنافٌ مُسمّاةٌ** لا قيمٌ خامّة، لأنّ «غائب»
// هو `null` في دارت و`undefined` هنا — فترميزُ القيمةِ نفسِها كان سيُنتجَ
// جدولاً يَعني شيئَين مختلفَين على الجهتَين.
// CASES_BEGIN
const CASES: [string, boolean][] = [
  ['true', true],
  ['false', false],
  ['absent', false],
  ['null', false],
  ['string-true', false],
  ['zero', false],
  ['one', false],
];
// CASES_END

function valueFor(tag: string): unknown {
  switch (tag) {
    case 'true': return true;
    case 'false': return false;
    case 'absent': return undefined;
    case 'null': return null;
    case 'string-true': return 'true';
    case 'zero': return 0;
    case 'one': return 1;
    default: throw new Error(`unknown case tag: ${tag}`);
  }
}

describe('بوّابةُ الدفعِ قبلَ إسنادِ سائق', () => {
  it('(أ) القاعدةُ سلوكاً على جدولِ الحالاتِ المشترَك', () => {
    expect(CASES.length).toBeGreaterThanOrEqual(7);
    for (const [tag, allowed] of CASES) {
      expect(orderPaidForDispatch(valueFor(tag))).toBe(allowed);
    }
  });

  it('(ب) ونصُّ الرفضِ غيرُ فارغٍ ويُسمّي الدفعَ والانتظار', () => {
    expect(UNPAID_DISPATCH_REFUSAL).toContain('غير مدفوع');
    expect(UNPAID_DISPATCH_REFUSAL).toContain('تأكيد الدفع');
  });

  it('(ج) ولا قيمةَ غيرِ `true` تُقرأُ مدفوعة', () => {
    for (const v of [true]) expect(orderPaidForDispatch(v)).toBe(true);
    for (const v of [false, undefined, null, '', 'true', 'TRUE', 0, 1, {}, []]) {
      expect(orderPaidForDispatch(v)).toBe(false);
    }
  });
});
