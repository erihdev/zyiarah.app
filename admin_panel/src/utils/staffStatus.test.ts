// حالةُ حسابِ الموظّفِ — القاعدةُ سلوكاً، ثمّ شدُّها إلى الجدول.
//
// العطلُ المُصلَح: الجدولُ كان `admin.status !== 'inactive'` وقيمةُ
// `'inactive'` لا يَكتبُها شيءٌ على مستندِ مستخدم، فالعمودُ «نشط» أبداً —
// ومنه حسابٌ حظرَته هذه اللوحةُ نفسُها من صفحةِ المستخدمين.
import { describe, it, expect } from 'vitest';
import { staffState, staffIsActive, STAFF_DISABLE_FIELDS } from './staffStatus.ts';

describe('staffState', () => {
  it('غيابُ كلِّ علَمٍ = نشط (مستنداتُ الإنتاجِ لا تَحملُ الحقول)', () => {
    expect(staffState({})).toBe('active');
    expect(staffState(null)).toBe('active');
    expect(staffState(undefined)).toBe('active');
    expect(staffIsActive({})).toBe(true);
  });

  it('is_active === false ⇒ موقوف (مفتاحُ تطبيقِ الإدارة، وما تَقرؤه القواعد)', () => {
    expect(staffState({ is_active: false })).toBe('suspended');
    expect(staffIsActive({ is_active: false })).toBe(false);
  });

  it('is_active === true لا يَرفعُ حظراً', () => {
    expect(staffState({ is_active: true, status: 'banned' })).toBe('banned');
  });

  it("status === 'banned' ⇒ محظور (تَكتبُه صفحةُ المستخدمينَ في هذه اللوحة)", () => {
    expect(staffState({ status: 'banned' })).toBe('banned');
    expect(staffIsActive({ status: 'banned' })).toBe(false);
  });

  it('is_blocked === true ⇒ محظور (العلَمُ القديمُ، يَقرؤه user_provider)', () => {
    expect(staffState({ is_blocked: true })).toBe('banned');
  });

  it('الحظرُ يَغلِبُ الوقفَ — رفعُه للمدير العامِّ وحدَه فلا يُعرَضُ كوقف', () => {
    expect(staffState({ is_active: false, status: 'banned' })).toBe('banned');
    expect(staffState({ is_active: false, is_blocked: true })).toBe('banned');
  });

  it("'inactive' ليست قيمةً مُعطِّلةً — لا كاتبَ لها، وقراءتُها هي العطل", () => {
    // الصريحُ: مستندٌ يَحملُها (لو كُتبت يوماً بيدٍ) لا يُعَدُّ موقوفاً من
    // تلقاءِ نفسِه، لأنّ الوقفَ علَمُه `is_active`. والمهمُّ أنّ الجدولَ لم
    // يَعُد يَقرأُها.
    expect(staffState({ status: 'inactive' })).toBe('active');
  });

  it('حالةٌ غيرُ معروفةٍ لا تُعطّل (status للعميلةِ يَحملُ active/banned)', () => {
    expect(staffState({ status: 'active' })).toBe('active');
    expect(staffState({ status: 'whatever' })).toBe('active');
  });

  it('الأعلامُ الثلاثةُ مُعلَنةٌ — الحارسُ الدارتيُّ يَشتقُّها من القواعدِ ويُقابِلُها', () => {
    expect([...STAFF_DISABLE_FIELDS].sort()).toEqual(
      ['is_active', 'is_blocked', 'status'].sort(),
    );
  });
});
