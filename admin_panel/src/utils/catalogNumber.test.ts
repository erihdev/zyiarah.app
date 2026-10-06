import { describe, it, expect } from 'vitest';
import {
    normalizeDigits, positiveNum, positiveInt, visitsFromText,
    resolvedVisits, packageFormError,
} from './catalogNumber';

// جدولُ الحالاتِ **مشترَكٌ بين اللغتَين**: `test/catalog_number_test.dart`
// يَقرأُ هذا الملفَّ بين العلامتَين ويُقارِنُه `jsonDecode`اً، فحالةٌ تُضافُ
// لجهةٍ دون الأخرى تَسقط. (الاتّجاهُ هكذا لأنّ `node:fs` بلا أنواعٍ تحت
// `tsconfig.app.json` — قاعدةٌ أسقطت البناءَ هنا ثلاثَ مرّات.)
// صيغةُ الصفّ: [raw, positiveNum, positiveInt]
// ⟦CASES⟧
const CASES: [string, number | null, number | null][] = [
    ['350', 350, 350],
    ['٣٥٠', 350, 350],
    ['۳۵۰', 350, 350],
    ['350.5', 350.5, null],
    ['٣٥٠٫٥', 350.5, null],
    ['١٬٢٥٠', 1250, 1250],
    ['4.0', 4, 4],
    ['3e2', 300, 300],
    ['', null, null],
    ['   ', null, null],
    ['abc', null, null],
    ['0', null, null],
    ['٠', null, null],
    ['-50', null, null],
    ['350 ر.س', null, null],
    ['‏350', 350, 350],
    ['1e16', 1e16, null],
];
// ⟦/CASES⟧

describe('catalogNumber', () => {
    it('(أ) الجدولُ المشترَكُ: positiveNum و positiveInt', () => {
        for (const [raw, num, int] of CASES) {
            expect(positiveNum(raw), `positiveNum(${JSON.stringify(raw)})`).toBe(num);
            expect(positiveInt(raw), `positiveInt(${JSON.stringify(raw)})`).toBe(int);
        }
    });

    it('(ب) تطبيعُ الأرقامِ يُبقي ما ليس رقماً كما هو', () => {
        expect(normalizeDigits('باقة ٨ زيارات')).toBe('باقة 8 زيارات');
        expect(normalizeDigits('  ٤  ')).toBe('4');
    });

    it('(ج) «N زيار» — نفسُ احتياطيِّ العميلِ والخادم', () => {
        expect(visitsFromText('باقة 8 زيارات شهرياً')).toBe(8);
        expect(visitsFromText('باقة ٨ زيارات شهرياً')).toBe(8);
        expect(visitsFromText('4 زيارة')).toBe(4);
        expect(visitsFromText('باقة ذهبية')).toBe(0);
    });

    it('(د) الحقلُ يَغلبُ النصَّ، والنصُّ احتياطٌ لا بديل', () => {
        expect(resolvedVisits('6', 'باقة 8 زيارات')).toBe(6);
        expect(resolvedVisits('', 'باقة 8 زيارات')).toBe(8);
        expect(resolvedVisits('', 'باقة ذهبية')).toBe(0);
        expect(resolvedVisits('abc', 'باقة 8 زيارات')).toBe(8);
    });

    it('(هـ) حِملٌ صحيحٌ يَمرّ', () => {
        expect(packageFormError({
            title: 'باقة شهرية', price: '350', visits: '4', hours: '4',
            text: 'باقة شهرية',
        })).toBeNull();
    });

    it('(و) سعرٌ لا يَنحلُّ إلى رقمٍ يُرفَضُ ولا يُبتلَعُ صفراً', () => {
        for (const bad of ['', '0', '-50', 'abc', '350 ر.س']) {
            expect(packageFormError({
                title: 'باقة', price: bad, visits: '4', hours: '4', text: 'باقة',
            }), `price=${JSON.stringify(bad)}`).toBe('السعر يجب أن يكون رقماً أكبر من صفر');
        }
    });

    it('(ز) الأرقامُ العربيّةُ تُقبَلُ لا تُرفَض', () => {
        expect(packageFormError({
            title: 'باقة', price: '٣٥٠', visits: '٤', hours: '٤', text: 'باقة',
        })).toBeNull();
    });

    it('(ح) زياراتٌ فارغةٌ بلا «N زيار» في النصِّ تُرفَض', () => {
        expect(packageFormError({
            title: 'باقة ذهبية', price: '350', visits: '', hours: '4',
            text: 'باقة ذهبية مميزة',
        })).toBe('أدخِل عدد الزيارات — باقة بلا عدد زيارات لا يستطيع العميل شراءها');
        // ومع العددِ في النصِّ تَمرّ — الاحتياطيُّ القائمُ لا يُنقَض
        expect(packageFormError({
            title: 'باقة 8 زيارات', price: '350', visits: '', hours: '4',
            text: 'باقة 8 زيارات',
        })).toBeNull();
    });

    it('(ط) زياراتٌ مكتوبةٌ وغيرُ صالحةٍ تُرفَضُ ولا تَسقطُ إلى النصّ', () => {
        expect(packageFormError({
            title: 'باقة 8 زيارات', price: '350', visits: '0', hours: '4',
            text: 'باقة 8 زيارات',
        })).toBe('عدد الزيارات يجب أن يكون رقماً صحيحاً أكبر من صفر');
        expect(packageFormError({
            title: 'باقة 8 زيارات', price: '350', visits: '2.5', hours: '4',
            text: 'باقة 8 زيارات',
        })).toBe('عدد الزيارات يجب أن يكون رقماً صحيحاً أكبر من صفر');
    });

    it('(ي) ساعاتٌ فارغةٌ تَمرُّ (الافتراضُ 4)، وغيرُ الصالحةِ تُرفَض', () => {
        expect(packageFormError({
            title: 'باقة', price: '350', visits: '4', hours: '', text: 'باقة',
        })).toBeNull();
        expect(packageFormError({
            title: 'باقة', price: '350', visits: '4', hours: 'abc', text: 'باقة',
        })).toBe('عدد الساعات لكل زيارة يجب أن يكون رقماً صحيحاً أكبر من صفر');
    });

    it('(ك) عاملاتُ المناسباتِ: الحقلُ يُفحَصُ متى مُرِّر وحدَه', () => {
        expect(packageFormError({
            title: 'باقة', price: '350', visits: '4', hours: '4',
            workers: '2', text: 'باقة',
        })).toBeNull();
        for (const bad of ['', '0', 'abc']) {
            expect(packageFormError({
                title: 'باقة', price: '350', visits: '4', hours: '4',
                workers: bad, text: 'باقة',
            }), `workers=${JSON.stringify(bad)}`).toBe('عدد العاملات يجب أن يكون رقماً صحيحاً أكبر من صفر');
        }
        // باقاتُ الاشتراكِ لا تَحملُ الحقلَ أصلاً فلا يُفحَص
        expect(packageFormError({
            title: 'باقة', price: '350', visits: '4', hours: '4', text: 'باقة',
        })).toBeNull();
    });

    it('(ل) العنوانُ أوّلُ ما يُفحَصُ', () => {
        expect(packageFormError({
            title: '   ', price: '', visits: '', hours: '', text: '',
        })).toBe('أدخِل اسم الباقة');
    });
});
