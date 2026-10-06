import { describe, it, expect } from 'vitest';
import { formatSar, formatSarAny } from './money';

// جدولُ الحالاتِ **مشترَكٌ مع `formatSar` في الدارت**:
// `test/money_format_test.dart` يَقرأُ هذه الكتلةَ ويُقارِنُها `jsonDecode`اً.
// والصفّ: [القيمة, المعروض].
// ⟦CASES⟧
const SHARED: [number, string][] = [
  [35, '35'],
  [35.0, '35'],
  [172.5, '172.50'],
  [172.55, '172.55'],
  [0, '0'],
  [0.5, '0.50'],
  [1234.567, '1234.57'],
  [-20, '-20'],
  [99999.99, '99999.99'],
];
// ⟦/CASES⟧

describe('formatSar — الجدولُ المشترَك', () => {
  it('كلُّ صفٍّ', () => {
    for (const [v, want] of SHARED) {
      expect(formatSar(v), `${v}`).toBe(want);
    }
  });
});

describe('formatSarAny', () => {
  it('يَقبلُ نصّاً ورقماً، والفاسدُ صفرٌ لا NaN', () => {
    expect(formatSarAny('35')).toBe('35');
    expect(formatSarAny('172.5')).toBe('172.50');
    expect(formatSarAny(172.5)).toBe('172.50');
    expect(formatSarAny(null)).toBe('0');
    expect(formatSarAny(undefined)).toBe('0');
    expect(formatSarAny('')).toBe('0');
    expect(formatSarAny('غير رقم')).toBe('0');
    expect(formatSarAny(Number.NaN)).toBe('0');
    expect(formatSarAny(Number.POSITIVE_INFINITY)).toBe('0');
  });
});
