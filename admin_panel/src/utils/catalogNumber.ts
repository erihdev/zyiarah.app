// **حقلٌ رقميٌّ في محرِّرٍ إداريٍّ: يُرفَضُ غيرُ الصالحِ ولا يُبتلَعُ صفراً.**
//
// مرآةُ `lib/utils/catalog_number.dart` — والقرارُ واحدٌ والجدولُ مشترَكٌ
// (كتلةُ الحالاتِ في `catalogNumber.test.ts` يَقرؤها فحصُ الدارتِ ويُقارِنُها).
//
// كان المحرِّرانِ هنا وفي التطبيقِ يَكتبانِ `parseFloat(x) || 0` و
// `parseInt(x) || 0`، فقيمةٌ لا تَنحلُّ إلى رقمٍ تُخزَّنُ **صفراً** مع
// «تمّ الحفظُ بنجاح» والنتيجةُ باقةٌ **لا تُباع**: سعرٌ صفرٌ تَرفُضُه قاعدةُ
// إنشاءِ العقدِ (`planPrice > 0`) بعد أن عُرِضَت للعميلةِ بـ«0 ر.س»، وزياراتٌ
// صفرٌ تُجمِّدُ زرَّ المتابعةِ بلا رسالة. وحقلُ الزياراتِ ليس إلزاميّاً في
// أيِّ محرِّر، فتركُه فارغاً يَكتبُ صفراً في الأربعِ.
//
// `<input type="number">` يَمنعُ الأرقامَ العربيّةَ هنا، والتطبيقُ لا يَمنعُها
// (`TextField` بلا `inputFormatters`) — فالتطبيعُ لازمٌ هناك وغيرُ ضارٍّ هنا،
// والقاعدةُ تَبقى واحدةً.

/** تطبيعُ الأرقامِ العربيّةِ-الهنديّةِ والفارسيّةِ وعلاماتِ الاتّجاه. */
export function normalizeDigits(input: string): string {
    let out = '';
    for (const ch of input) {
        const c = ch.codePointAt(0)!;
        if (c >= 0x0660 && c <= 0x0669) out += String.fromCharCode(0x30 + (c - 0x0660));
        else if (c >= 0x06F0 && c <= 0x06F9) out += String.fromCharCode(0x30 + (c - 0x06F0));
        else if (c === 0x066B) out += '.';
        else if (c === 0x066C || c === 0x200E || c === 0x200F || c === 0x061C) {
            // فاصلُ الآلافِ وعلاماتُ الاتّجاه: تُحذَف
        } else out += ch;
    }
    return out.trim();
}

/**
 * رقمٌ موجبٌ صالح، أو `null` — والـ`null` يَعني **غيرَ صالح** فلا يُبتلَعُ
 * إلى قيمةٍ افتراضيّة. `Number('')` صفرٌ في JS، فالفراغُ يُرَدُّ صراحةً.
 */
export function positiveNum(raw: string): number | null {
    const s = normalizeDigits(raw);
    if (s === '') return null;
    const v = Number(s);
    if (!Number.isFinite(v) || v <= 0) return null;
    return v;
}

/**
 * نفسُ القاعدةِ لعددٍ صحيحٍ موجب — مُشتَقّةً من `positiveNum` في الجهتَين
 * (`int.tryParse` في الدارتِ تَرُدُّ «3e2» و«4.0» و`Number` تَقبلُهما، فالمرآةُ
 * تَنحرِفُ لو بُنِيت عليها). والحدُّ `1e15` يُطابِقُ حدَّ `toInt()` هناك.
 */
export function positiveInt(raw: string): number | null {
    const v = positiveNum(raw);
    if (v === null || !Number.isInteger(v) || v > 1e15) return null;
    return v;
}

/**
 * العددُ المجاورُ لكلمةِ «زيار» — **نفسُ** احتياطيِّ العميلِ والخادم، فالمحرِّرُ
 * يَرفُضُ ما لا يَستطيعُ أحدُهما حلَّه بعينِه.
 */
export function visitsFromText(text: string): number {
    const m = /(\d+)\s*زيار/.exec(normalizeDigits(text));
    if (!m) return 0;
    const v = Number(m[1]);
    return Number.isFinite(v) ? v : 0;
}

/**
 * عددُ الزياراتِ الذي يُكتَبُ على الباقة. وكتابةُ المُستخرَجِ من النصِّ
 * **تُفعِّلُ فحصَ الخادمِ** للزيارات: كان يُتخطّى كلَّه متى كان
 * `pkg.visits <= 0`، فيَقبلُ أيَّ `planVisits` يُعلِنُه العميل.
 */
export function resolvedVisits(visitsField: string, text: string): number {
    return positiveInt(visitsField) ?? visitsFromText(text);
}

/** رسالةُ الخطأِ الأولى، أو `null` إن صحّ الحِمل. */
export function packageFormError(f: {
    title: string;
    price: string;
    visits: string;
    hours: string;
    text: string;
    workers?: string;
}): string | null {
    if (f.title.trim() === '') return 'أدخِل اسم الباقة';
    if (positiveNum(f.price) === null) {
        return 'السعر يجب أن يكون رقماً أكبر من صفر';
    }
    if (f.visits.trim() !== '' && positiveInt(f.visits) === null) {
        return 'عدد الزيارات يجب أن يكون رقماً صحيحاً أكبر من صفر';
    }
    if (f.visits.trim() === '' && visitsFromText(f.text) <= 0) {
        return 'أدخِل عدد الزيارات — باقة بلا عدد زيارات لا يستطيع العميل شراءها';
    }
    if (f.hours.trim() !== '' && positiveInt(f.hours) === null) {
        return 'عدد الساعات لكل زيارة يجب أن يكون رقماً صحيحاً أكبر من صفر';
    }
    if (f.workers !== undefined && positiveInt(f.workers) === null) {
        return 'عدد العاملات يجب أن يكون رقماً صحيحاً أكبر من صفر';
    }
    return null;
}
