import { describe, it, expect } from 'vitest';
import { COUPON_ACTIVE, COUPON_DISABLED, couponIsActive } from './couponStatus';

// الخادمُ يَحكمُ: `if (coupon.status && coupon.status !== "active")` — فالقاعدةُ
// «ما ليس active فمعطَّل، والغيابُ نشاطٌ». وهذه اللوحةُ كانت تَختبرُ
// `=== 'expired'` وحدَها، فكوبونٌ عُطّل من تطبيقِ الإدارةِ (`'inactive'`)
// لا يُعتَمُ في الجدولِ بينما زرُّه يَعرضُ «تفعيل».
const panelFiles = import.meta.glob('../pages/Marketing.tsx', {
  query: '?raw', import: 'default', eager: true,
}) as Record<string, string>;

describe('حالةُ الكوبون: قاعدةٌ لا تعداد', () => {
  it('نشطٌ = active أو غائب (نفسُ قراءةِ الخادم)', () => {
    expect(couponIsActive('active')).toBe(true);
    expect(couponIsActive(undefined)).toBe(true);
    expect(couponIsActive(null)).toBe(true);
    expect(couponIsActive('')).toBe(true);
  });

  it('وكلُّ ما سواه معطَّل — بما فيه مفردةُ المحرّرِ الآخر', () => {
    expect(couponIsActive('inactive')).toBe(false);
    expect(couponIsActive('expired')).toBe(false);
    expect(couponIsActive('anything')).toBe(false);
  });

  it('والمفردةُ الواحدةُ للتعطيلِ هي ما يَكتبُه محرّرُ التطبيق', () => {
    expect(COUPON_ACTIVE).toBe('active');
    // `admin_coupons_screen.dart`: `status = v ? 'active' : 'inactive'`.
    expect(COUPON_DISABLED).toBe('inactive');
  });
});

describe('واللوحةُ تَقرأُ القاعدةَ لا قيمةً بعينِها', () => {
  const src = Object.values(panelFiles)[0];

  it('قرأَ الملفَّ فعلاً — وإلّا فالفحصُ أجوف', () => {
    expect(src).toBeTruthy();
    expect(src.length).toBeGreaterThan(2000);
  });

  it('لا اختبارَ لـ`expired` بعينِها، والصفُّ يُعتَمُ بالقاعدة', () => {
    expect(src).not.toContain("status === 'expired'");
    expect(src).toContain('!couponIsActive(coupon.status)');
  });

  it('والتعطيلُ يَكتبُ المفردةَ المُشترَكة', () => {
    expect(src).toContain('COUPON_DISABLED');
    expect(src).not.toContain("? 'expired' : 'active'");
  });

  it('والعدّادُ وأيقونةُ الإجراءِ على القاعدةِ نفسِها', () => {
    expect(src).toContain('couponIsActive(c.status)');
    expect(src).not.toContain("c.status === 'active'");
  });
});
