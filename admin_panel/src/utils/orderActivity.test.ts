import { describe, it, expect } from 'vitest';
import {
  TERMINAL_ORDER_STATUSES,
  STORE_NEEDS_ACTION_STATUSES,
  orderIsOpen,
  storeOrderNeedsAction,
} from './orderActivity';

describe('orderActivity — مرآةُ order_activity.dart', () => {
  it('الحالاتُ المنتهيةُ وحدَها تُقرأ منتهية', () => {
    for (const s of ['delivered', 'completed', 'cancelled', 'rejected']) {
      expect(orderIsOpen(s), s).toBe(false);
    }
  });

  it('كلُّ حالةٍ من الدورةِ الحقيقيّةِ مفتوحة', () => {
    for (const s of [
      'pending', 'awaiting_payment', 'under_review', 'assigned', 'scheduled',
      'accepted', 'on_the_way', 'in_progress', 'delivering', 'processing',
      'shipped', 'paid', 'approved',
    ]) {
      expect(orderIsOpen(s), s).toBe(true);
    }
  });

  it('حالةٌ لم تُولد بعد مفتوحةٌ — وهذا الشقُّ المُصلَح', () => {
    for (const s of ['out_for_delivery', 'preparing', 'redelivery']) {
      expect(orderIsOpen(s), s).toBe(true);
    }
  });

  it('الغائبُ والفارغُ مفتوحان', () => {
    expect(orderIsOpen(null)).toBe(true);
    expect(orderIsOpen(undefined)).toBe(true);
    expect(orderIsOpen('')).toBe(true);
    expect(orderIsOpen('  ')).toBe(true);
    expect(orderIsOpen(7)).toBe(true);
  });

  it('المسافاتُ المحيطةُ لا تُغيّر الحكم', () => {
    expect(orderIsOpen(' delivered ')).toBe(false);
    expect(orderIsOpen(' on_the_way ')).toBe(true);
  });

  it('«يَنتظرُ إجراءً» هو ما تَعرضُ له الإدارةُ زرّاً', () => {
    for (const s of ['under_review', 'delivering', 'processing', 'shipped']) {
      expect(storeOrderNeedsAction(s), s).toBe(true);
    }
    for (const s of ['awaiting_payment', 'delivered', 'pending', '', 'x']) {
      expect(storeOrderNeedsAction(s), s).toBe(false);
    }
    expect(storeOrderNeedsAction(null)).toBe(false);
  });

  it('pending ليست في مجموعةِ الإجراء — كان الشرطَ الصفريَّ الأبدي', () => {
    expect(STORE_NEEDS_ACTION_STATUSES).not.toContain('pending');
  });

  it('المجموعتان لا تتقاطعان', () => {
    const t = new Set(TERMINAL_ORDER_STATUSES);
    for (const s of STORE_NEEDS_ACTION_STATUSES) expect(t.has(s)).toBe(false);
  });

  it('refunded ليست حالةَ status', () => {
    expect(TERMINAL_ORDER_STATUSES).not.toContain('refunded');
  });

  it('استعلامُ Firestore يَقبلُ المجموعةَ في in (≤10 قيم)', () => {
    expect(STORE_NEEDS_ACTION_STATUSES.length).toBeLessThanOrEqual(10);
    expect(STORE_NEEDS_ACTION_STATUSES.length).toBeGreaterThan(0);
  });
});
