import mapboxgl, { type Map as MapboxMap } from 'mapbox-gl';

// إصلاح تشكيل العربية: بدون إضافة RTL يرسم MapBox الحروف مقطّعةً ومعكوسة («افيف»
// بدل «فيفاء»). تُسجَّل مرّة واحدة على مستوى الوحدة (الاستدعاء المكرّر يرمي خطأ)،
// وبتحميل كسول فلا تُجلب إلا حين يظهر نصّ RTL فعلاً على الخريطة.
if (mapboxgl.getRTLTextPluginStatus() === 'unavailable') {
    mapboxgl.setRTLTextPlugin(
        'https://api.mapbox.com/mapbox-gl-js/plugins/mapbox-gl-rtl-text/v0.3.0/mapbox-gl-rtl-text.js',
        () => { /* صامت — فشل التحميل يُبقي التسميات كما كانت */ },
        true,
    );
}

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
