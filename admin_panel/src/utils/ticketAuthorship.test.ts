// مرآةُ القرارِ في اللوحة — **الجدولُ نفسُه** يُقرأُ من فحصِ الدارت حرفيّاً
// (نمطُ `serviceMeta`/`buildGate`)، فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
import { describe, it, expect } from 'vitest';
import { ticketMessageSender, ticketMessageIsFromTeam } from './ticketAuthorship';

// `import.meta.glob` لا `node:fs` — القاعدةُ المسجَّلةُ في هذا المستودع
// (لا أنواعَ لـ`node:fs` تحت `tsconfig.app.json`، وقد أعقمَت حارسَين).
const dartTests = import.meta.glob('../../../test/ticket_authorship_test.dart', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>;

function sharedCases(): [Record<string, string>, string | null, string][] {
  const src = Object.values(dartTests)[0];
  if (!src) throw new Error('فحصُ الدارت لم يُقرأ');
  const b = src.indexOf('TICKET_AUTHORSHIP_CASES_BEGIN');
  const e = src.indexOf('TICKET_AUTHORSHIP_CASES_END');
  if (b < 0 || e < 0) throw new Error('علامتا الجدولِ اختفتا');
  const seg = src.slice(b, e);
  const i = seg.indexOf("'''");
  const j = seg.indexOf("'''", i + 3);
  if (i < 0 || j < 0) throw new Error('تعذّرَ اقتطاعُ الجدول');
  return JSON.parse(seg.slice(i + 3, j));
}

describe('ticketAuthorship — القرارُ على الفاعلِ لا الادّعاء', () => {
  const cases = sharedCases();

  it('الجدولُ المشترَكُ قُرِئ فعلاً (لا فحصٌ أجوف)', () => {
    expect(cases.length).toBeGreaterThanOrEqual(12);
  });

  cases.forEach(([msg, owner, want], i) => {
    it(`حالة ${i + 1}: ${JSON.stringify(msg)} (مالك=${owner}) ⇒ ${want}`, () => {
      expect(ticketMessageSender(msg, owner)).toBe(want);
      expect(ticketMessageIsFromTeam(msg, owner)).toBe(want === 'team');
    });
  });

  it('تلفيقُ «الإدارة» بـuid صاحبةِ التذكرةِ يُقرأُ «منها»', () => {
    expect(
      ticketMessageSender(
        { senderRole: 'admin', senderId: 'u1' },
        'u1',
      ),
    ).toBe('client');
  });
});
