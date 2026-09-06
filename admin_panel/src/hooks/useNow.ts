import { useEffect, useState } from 'react';

/**
 * طابع زمني يتجدّد دورياً، بديلاً عن استدعاء Date.now() أثناء الرندر.
 *
 * قراءة الساعة أثناء الرندر تجعل مُخرَج المكوّن غير ثابت: النتيجة تتغيّر بين
 * رندرتين لنفس المدخلات (وهذا ما ترصده قاعدة react-hooks/purity). والأثر
 * الجانبي أن النصوص النسبية «منذ ٥ دقائق» كانت تتجمّد على قيمتها حتى يُعيد
 * سببٌ آخر رندرَ الصفحة.
 *
 * @param intervalMs فترة التجديد (افتراضياً دقيقة — دقّة «منذ س دقيقة»).
 */
export function useNow(intervalMs = 60_000): number {
    const [now, setNow] = useState(() => Date.now());
    useEffect(() => {
        const id = setInterval(() => setNow(Date.now()), intervalMs);
        return () => clearInterval(id);
    }, [intervalMs]);
    return now;
}
