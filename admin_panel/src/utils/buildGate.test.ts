import { describe, it, expect } from 'vitest';
import { publishedBuild, latestBuildFor } from './buildGate.ts';

// جدولُ الحالاتِ **مشتركٌ بين اللغتَين**: نسخةٌ بعينِها في
// `test/build_gate_test.dart` بين العلامتَين نفسِهما، و`build_gate_test` يَقرأُ
// هذا الملفَّ ويُقارِنُ الجدولَين `jsonDecode`اً — فحالةٌ تُضافُ لجهةٍ دون
// الأخرى تَسقط.
// ── BUILD_GATE_CASES_BEGIN ──
const CASES: [unknown, number | null][] = [
  [261, 261],
  ["261", 261],
  [" 261 ", 261],
  [261.9, 261],
  [0, null],
  ["0", null],
  [-1, null],
  ["-1", null],
  ["", null],
  ["  ", null],
  ["v261", null],
  ["26.1", null],
  [null, null],
  [undefined, null],
  [true, null],
  [[], null]
];
// ── BUILD_GATE_CASES_END ──

describe('publishedBuild', () => {
  it('الصفرُ والسالبُ والفارغُ وغيرُ الرقميِّ غيابٌ — لا بوّابةٌ مفتوحة', () => {
    for (const [input, want] of CASES) {
      expect(publishedBuild(input), `publishedBuild(${JSON.stringify(input)})`)
        .toBe(want);
    }
  });
});

describe('latestBuildFor', () => {
  it('حقلُ المنصّةِ أوّلاً — وعكسُه عطلُ 2026-08-31', () => {
    const d = { latest_build_ios: 261, latest_build_android: 208, latest_build: 208 };
    expect(latestBuildFor(d, true)).toBe(261);
    expect(latestBuildFor(d, false)).toBe(208);
  });

  it('والسقوطُ إلى الموحّدِ للمستنداتِ القديمةِ وحدَها', () => {
    const old = { latest_build: 208 };
    expect(latestBuildFor(old, true)).toBe(208);
    expect(latestBuildFor(old, false)).toBe(208);
  });

  it('والصفرُ يَسقطُ إلى الموحّدِ ولا يُطفئُ البوّابة — هذا هو العطل', () => {
    // قبلَ الإصلاح: `d[platformField] ?? d['latest_build']` فالصفرُ يُفضَّلُ
    // (ليس `null`) و`currentBuild >= 0` صحيحٌ أبداً ⇒ لا مطالبةَ أبداً.
    const zeroed = { latest_build_ios: 261, latest_build_android: 0, latest_build: 208 };
    expect(latestBuildFor(zeroed, false)).toBe(208);
    expect(latestBuildFor(zeroed, true)).toBe(261);
  });

  it('ولا بوّابةَ حين لا رقمَ منشوراً إطلاقاً', () => {
    expect(latestBuildFor({ latest_build_ios: 0, latest_build: 0 }, true)).toBeNull();
    expect(latestBuildFor({}, true)).toBeNull();
  });

  it('ونصُّ الكونسولِ اليدويُّ مقبولٌ — كان يَرمي فتَموتُ البوّابةُ للمنصّتَين', () => {
    expect(latestBuildFor({ latest_build_ios: '261' }, true)).toBe(261);
  });
});
