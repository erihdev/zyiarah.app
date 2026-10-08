import { describe, it, expect } from 'vitest';
import { refundNoticeText, refundServiceImpact } from './refundNotice.ts';
import type { RefundOp, RefundServiceImpact } from './refundNotice.ts';

// جدولُ الحالاتِ **واحدٌ بين اللغتَين**: `test/refund_notice_test.dart` يَقرأُ
// هذه الكتلةَ بعينِها ويُقارِنُها `jsonDecode`اً، فحالةٌ تُضافُ لجهةٍ دون
// الأخرى تَسقط. والصفُّ: [الحالة، أله سائق؟، الأثرُ المتوقَّع].
// IMPACT_BEGIN
const IMPACT_CASES: [string | null, boolean, string][] = [
  ['scheduled', true, 'crewStillAssigned'],
  ['scheduled', false, 'openWithoutCrew'],
  ['pending', false, 'openWithoutCrew'],
  ['pending', true, 'crewStillAssigned'],
  ['in_progress', true, 'crewStillAssigned'],
  ['completed', true, 'serviceEnded'],
  ['cancelled', false, 'serviceEnded'],
  ['delivered', true, 'serviceEnded'],
  ['rejected', false, 'serviceEnded'],
  [null, false, 'openWithoutCrew'],
  ['under_review', true, 'crewStillAssigned'],
];
// IMPACT_END

// والصفُّ: [العمليّة، الأثر، جزئيّ؟، أيُقالُ شيء؟، كلمةُ الفعل].
// TEXT_BEGIN
const TEXT_CASES: [string, string, boolean, boolean, string][] = [
  ['refund', 'crewStillAssigned', false, true, 'استردادُ المبلغ'],
  ['voidAuth', 'crewStillAssigned', false, true, 'إلغاءُ التفويض'],
  ['refund', 'openWithoutCrew', false, true, 'استردادُ المبلغ'],
  ['voidAuth', 'openWithoutCrew', false, true, 'إلغاءُ التفويض'],
  ['refund', 'serviceEnded', false, false, ''],
  ['voidAuth', 'serviceEnded', false, false, ''],
  ['refund', 'serviceEnded', true, true, ''],
  ['refund', 'crewStillAssigned', true, true, 'استردادُ المبلغ'],
];
// TEXT_END

describe('جملةُ ما يَحدثُ للخدمةِ عند إعادةِ المال', () => {
  it('(أ) الأثرُ على الخدمةِ — جدولُ الحالاتِ المشترَك', () => {
    expect(IMPACT_CASES.length).toBeGreaterThanOrEqual(11);
    for (const [status, hasDriver, want] of IMPACT_CASES) {
      expect(refundServiceImpact(status, hasDriver)).toBe(want);
    }
  });

  it('(ب) والنصُّ — جدولُ الحالاتِ المشترَك', () => {
    expect(TEXT_CASES.length).toBeGreaterThanOrEqual(8);
    for (const [op, impact, partial, saysSomething, verb] of TEXT_CASES) {
      const s = refundNoticeText(
        op as RefundOp, impact as RefundServiceImpact, partial);
      expect(s.length > 0).toBe(saysSomething);
      if (verb) expect(s).toContain(verb);
    }
  });

  it('(ج) والجزئيّةُ تُقالُ في كلِّ أثر', () => {
    for (const impact of
      ['crewStillAssigned', 'openWithoutCrew', 'serviceEnded'] as const) {
      expect(refundNoticeText('refund', impact, true))
        .toContain('غير مدفوع بالكامل');
    }
  });

  it('(د) ولا جملةَ عن الفريقِ لطلبٍ منتهٍ', () => {
    expect(refundNoticeText('refund', 'serviceEnded', false)).toBe('');
    expect(refundNoticeText('refund', 'serviceEnded', true))
      .not.toContain('الفريق');
  });
});
