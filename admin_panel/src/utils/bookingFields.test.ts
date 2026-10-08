import { describe, it, expect } from 'vitest';
import { bookingDateOf, bookingTimeSlotOf, REMINDER_FLAGS, rescheduleDerivedFields } from './bookingFields.ts';

// BOOKING_FIELDS_CASES_START
// [year, month, day, hour, minute, expectedBookingDate, expectedTimeSlot]
const CASES: [number, number, number, number, number, string, string][] = [
    [2026, 10, 8, 14, 0, '2026-10-08', '14:00'],
    [2026, 1, 1, 0, 0, '2026-01-01', '00:00'],
    [2026, 12, 31, 23, 59, '2026-12-31', '23:00'],
    [2026, 3, 9, 8, 30, '2026-03-09', '08:00'],
    [2026, 11, 30, 9, 5, '2026-11-30', '09:00'],
    [2026, 2, 28, 22, 45, '2026-02-28', '22:00'],
    [2028, 2, 29, 7, 0, '2028-02-29', '07:00'],
];
// BOOKING_FIELDS_CASES_END

describe('bookingFields', () => {
    it('يشتقّ الحقلين من ساعة الحائط', () => {
        for (const [y, mo, d, h, mi, date, slot] of CASES) {
            const chosen = new Date(y, mo - 1, d, h, mi);
            expect(bookingDateOf(chosen)).toBe(date);
            expect(bookingTimeSlotOf(chosen)).toBe(slot);
        }
    });

    it('والحِمْل يحمل الحقلين وأعلام التذكير مصفَّرة', () => {
        const out = rescheduleDerivedFields(new Date(2026, 9, 8, 14, 0));
        expect(out.booking_date).toBe('2026-10-08');
        expect(out.booking_time_slot).toBe('14:00');
        for (const f of REMINDER_FLAGS) expect(out[f]).toBe(false);
        // ولا `service_date`: قيمةُ المنادي لا مشتقّة.
        expect(out.service_date).toBeUndefined();
        expect(Object.keys(out).length).toBe(2 + REMINDER_FLAGS.length);
    });

    it('والدقائق تُطرح: الخانة ساعةٌ كاملة', () => {
        expect(bookingTimeSlotOf(new Date(2026, 9, 8, 14, 59))).toBe('14:00');
    });
});
