// **مرآةٌ بلا فحصٍ على جهتِها — والقاعدةُ هي ما كان مكشوفاً (2026-10-07).**
//
// `driverActivation.ts` يُعلِنُ نفسَه مرآةَ `lib/utils/driver_activation.dart`،
// وكان حارسُ المرآةِ يُثبّتُ **حِمْلَي الكتابةِ** حرفيّاً ولا يَمَسُّ
// `driverIsDisabled` إلّا بأنّ الصفحةَ تُنادِيها. فاختبارُ قضمٍ ضيَّقَ القاعدةَ
// إلى `d.is_active === false` **فمرَّ أخضرَ**: مجموعةُ دارت (٣٢ فحصاً)،
// و`tsc`، وفحوصُ اللوحةِ (٢٣٩) — كلُّها خضراء. أي أنّ العطلَ الذي وُجدت
// المرآةُ لمنعِه كان قابلاً للعودةِ بسطرٍ واحد:
//
//   مستنداتُ الإنتاجِ تَحملُ `is_active` **أو** `is_suspended` (المحرِّرانِ
//   كانا يَكتبانِ مختلفَين قبلَ إصلاحِ هذا الشهر)، فقراءةُ أحدِهما تُخطئُ
//   نصفَها: شارةٌ خضراءُ «متاح» لسائقٍ عطَّلَه المالك، وزرٌّ يَعرضُ «إيقاف»
//   كأنّه نشط، وعدّادُ «السائقون المتاحون» يَعدُّه.
//
// فجدولُ الحالاتِ أدناه **مشترَكٌ بين اللغتَين**: `test/driver_activation_test.dart`
// يَقرأُ هذه الكتلةَ بعينِها ويُمرِّرُها على قاعدةِ دارت — فانحرافُ أيِّ جهةٍ
// يَسقط.
import { describe, it, expect } from 'vitest';

import { driverActivationFields, driverIsDisabled } from './driverActivation';

// ⟦CASES⟧
// [is_active, is_suspended, disabled?]
// `null` = الحقلُ غائبٌ عن المستند.
const CASES: [boolean | null, boolean | null, boolean][] = [
  // غيابُ الحقلَين يُقرأُ **مُفعَّلاً** — وهو قرارٌ: الخادمُ
  // (`isAssignableDriver`) و`staffEnabled()` كلاهما يَقرأُ الغيابَ مُفعَّلاً.
  [null, null, false],
  [true, null, false],
  [null, false, false],
  [true, false, false],
  // وأيُّ العلَمَين كفى — وهو ما يَقرؤه `unassignJobsOnDriverDisable`.
  [false, null, true],
  [null, true, true],
  [false, false, true],
  [true, true, true],
  [false, true, true],
];
// ⟦/CASES⟧

describe('driverActivation', () => {
  it('أيُّ العلَمَين كفى — نفسُ قراءةِ الخادم', () => {
    for (const [active, suspended, disabled] of CASES) {
      const d: { is_active?: boolean; is_suspended?: boolean } = {};
      if (active !== null) d.is_active = active;
      if (suspended !== null) d.is_suspended = suspended;
      expect(driverIsDisabled(d)).toBe(disabled);
    }
  });

  it('حِمْلُ الإيقافِ يَكتبُ الثلاثةَ، والتفعيلُ لا يَزعمُ الاتّصال', () => {
    expect(driverActivationFields(false)).toEqual({
      is_active: false,
      is_suspended: true,
      is_available: false,
    });
    expect(driverActivationFields(true)).toEqual({
      is_active: true,
      is_suspended: false,
    });
    // `is_available` قرارُ السائقِ لا قرارُ الأدمن.
    expect('is_available' in driverActivationFields(true)).toBe(false);
  });

  it('والحِمْلُ يُوافقُ القاعدةَ: ما يُكتَبُ للإيقافِ يُقرأُ معطَّلاً', () => {
    expect(driverIsDisabled(driverActivationFields(false))).toBe(true);
    expect(driverIsDisabled(driverActivationFields(true))).toBe(false);
  });
});
