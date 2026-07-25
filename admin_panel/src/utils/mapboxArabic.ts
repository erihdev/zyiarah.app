import type { Map as MapboxMap } from 'mapbox-gl';

// تعريب تسميات خرائط MapBox: أنماط mapbox تعرض الأسماء الإنجليزية افتراضياً؛ نبدّل
// حقل النص في كل طبقات التسمية (symbol) إلى name_ar مع سقوطٍ إلى name حيث لا تعريب.
// تُستدعى بعد جاهزية الستايل (داخل on('load') أو on('style.load')).
export const arabizeMapLabels = (m: MapboxMap) => {
    try {
        for (const layer of m.getStyle()?.layers ?? []) {
            if (layer.type === 'symbol' && m.getLayoutProperty(layer.id, 'text-field')) {
                m.setLayoutProperty(layer.id, 'text-field', [
                    'coalesce', ['get', 'name_ar'], ['get', 'name'],
                ]);
            }
        }
    } catch { /* تجميلي — لا نُسقط الخريطة إن تغيّر شكل الستايل */ }
};
