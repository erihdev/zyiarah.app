import { describe, it, expect } from 'vitest';
import { orderPaidForDispatch, UNPAID_DISPATCH_REFUSAL, serviceDateAllowed, PAST_SERVICE_DATE_REFUSAL } from './orderDispatch.ts';

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

// ═══════════════════════ «لا موعدَ في الماضي» ═══════════════════════
//
// جدولٌ مشترَكٌ ثانٍ يَقرؤه `test/past_service_date_test.dart`. و«الآن» مثبّتٌ
// (`NOW_MS`) فلا يَتعلّقُ الفحصُ بساعةِ التشغيل، والمواعيدُ **ساعةُ حائطٍ
// ساذجة** كما يُرسِلُها حقلُ `datetime-local` وكما يَقرؤها الخادم.
//
// والأصنافُ **مُسمّاةٌ** لا حدٌّ عدديٌّ وحدَه: نزعُ صفٍّ يُبقي الجدولَ فوقَ
// أيِّ عتبةٍ فيَمرّ، وهو الدرسُ المسجَّلُ في جدولِ الأرقامِ العربيّة.

// 2026-10-08T00:30Z = 03:30 بالرياضِ من اليومِ نفسِه — فاليومُ «اليوم» هو
// 2026-10-08، واليومُ الذي قبلَه ماضٍ.
// NOW_BEGIN
const NOW_MS = Date.UTC(2026, 9, 8, 0, 30);
// NOW_END

// DATE_CASES_BEGIN
const DATE_CASES: [string, string, boolean][] = [
  ['اليومُ عند منتصفِ الليل', '2026-10-08T00:00', true],
  ['اليومُ في ساعةٍ مضت', '2026-10-08T01:00', true],
  ['اليومُ في ساعةٍ قادمة', '2026-10-08T23:00', true],
  ['الغد', '2026-10-09T09:00', true],
  ['بعدَ سنة', '2027-10-08T09:00', true],
  ['أمس', '2026-10-07T23:59', false],
  ['الأسبوعُ الماضي', '2026-10-01T09:00', false],
  ['سنةٌ مُخطَأةٌ بالكتابة', '2025-10-08T09:00', false],
  ['فارغ', '', false],
  ['نصٌّ غيرُ تاريخ', 'tomorrow', false],
  ['تاريخٌ ناقص', '2026-10', false],
];
// DATE_CASES_END

describe('بوّابةُ «لا موعدَ في الماضي»', () => {
  it('(أ) القاعدةُ سلوكاً على جدولِ الحالاتِ المشترَك', () => {
    expect(DATE_CASES.length).toBeGreaterThanOrEqual(11);
    for (const [tag, wall, allowed] of DATE_CASES) {
      expect(serviceDateAllowed(wall, NOW_MS), tag).toBe(allowed);
    }
  });

  it('(ب) والحدُّ **بدايةُ يومِ الرياضِ** لا «ليس قبلَ الآن»', () => {
    // الآنُ 03:30 بالرياض، و01:00 من اليومِ نفسِه **قبلَه** — ومسموحةٌ بقصد:
    // موعدٌ مشروعٌ يُسجّلُه الأدمنُ لزيارةٍ تأخّرَ إدخالُها، وداخلَ نافذةِ
    // الـ١٣ ساعةً فقابلٌ للاستعادة.
    expect(serviceDateAllowed('2026-10-08T01:00', NOW_MS)).toBe(true);
    // وآخرُ لحظةٍ من أمسَ مرفوضةٌ — فالحدُّ يَفصلُ باليومِ لا بالدقيقة.
    expect(serviceDateAllowed('2026-10-07T23:59', NOW_MS)).toBe(false);
  });

  it('(ج) ويومُ الرياضِ لا يومُ المتصفّح — وهذا ما يُثبِتُه العبورُ', () => {
    // 2026-10-07T21:30Z = 00:30 بالرياضِ من **الثامن**، فالسابعُ ماضٍ. ولو
    // قُرئ يومُ UTC لكانَ «اليوم» السابعَ فمرَّ موعدٌ ماضٍ بالرياض.
    const crossing = Date.UTC(2026, 9, 7, 21, 30);
    expect(serviceDateAllowed('2026-10-08T00:00', crossing)).toBe(true);
    expect(serviceDateAllowed('2026-10-07T23:00', crossing)).toBe(false);
  });

  it('(د) و`Date` تُقرأُ بمكوّناتِها لا بلحظتِها', () => {
    // منتقي الدارتِ ونصُّ الحقلِ كلاهما ساعةُ حائطٍ: `new Date('…T09:00')`
    // يَبنيه المتصفّحُ بمنطقتِه، فالقراءةُ بالمكوّناتِ هي ما يُطابقُ النصّ.
    expect(serviceDateAllowed(new Date(2026, 9, 8, 9, 0), NOW_MS)).toBe(true);
    expect(serviceDateAllowed(new Date(2026, 9, 7, 9, 0), NOW_MS)).toBe(false);
  });

  it('(هـ) ونصُّ الرفضِ غيرُ فارغٍ ويُسمّي السببَ والعلاج', () => {
    expect(PAST_SERVICE_DATE_REFUSAL).toContain('الماضي');
    expect(PAST_SERVICE_DATE_REFUSAL).toContain('اليوم');
  });
});
