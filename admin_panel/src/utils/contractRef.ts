// مرآةُ `lib/utils/contract_ref.dart` — القرارُ واحدٌ والصياغةُ تَختلفُ باللغة.
//
// جدولُ الحالاتِ مشترَكٌ بين اللغتَين: النسخةُ المرجعيّةُ بين العلامتَين في
// `test/contract_ref_test.dart`، و`contractRef.test.ts` يَقرؤها ويُقارِنُها —
// فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
//
// وسببُ وجودِها مكتوبٌ في الأصلِ: الرقمُ المطبوعُ على العقدِ الموقَّعِ كان
// غيرَ موجودٍ في أيِّ قائمةٍ إداريّةٍ وغيرَ قابلٍ للعثورِ بأيِّ بحث — وهذه
// الصفحةُ لم تَكن تَقرأُ الحقلَ المخزَّنَ إطلاقاً.

/** الرقمُ المعروضُ: المخزَّنُ إن كان نصّاً غيرَ فارغ، وإلّا ٨ محارفَ من المعرّف. */
export function contractRef(stored: unknown, docId: string): string {
    if (typeof stored === 'string' && stored.trim() !== '') return stored.trim();
    const s = (docId || '').toUpperCase();
    return s.length >= 8 ? s.slice(0, 8) : s;
}

/** الرقمُ المعروضُ **أو** المعرّفُ كاملاً — فالروابطُ القديمةُ تَحملُ المعرّف. */
export function contractRefMatches(
    stored: unknown,
    docId: string,
    query: string,
): boolean {
    const q = query.trim().toLowerCase();
    if (q === '') return true;
    return (
        contractRef(stored, docId).toLowerCase().includes(q) ||
        (docId || '').toLowerCase().includes(q)
    );
}
