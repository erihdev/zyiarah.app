import { useEffect, useRef } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { arabizeMapLabels } from '../utils/mapboxArabic.ts';
import { JAZAN_BBOX, jazanMaskGeoJSON, jazanOutlineGeoJSON, isInJazan } from '../utils/jazanBoundary.ts';
import { circleGeoJSON } from '../utils/circleGeoJSON.ts';

// منتقي مركز المحافظة على الخريطة — **كلُّ شيفرة mapbox-gl في اللوحة هنا، ولا
// في أي ملفٍّ آخر.**
//
// ولمَ ملفٌّ منفصل: `mapbox-gl` أثقلُ تبعيات اللوحة بفارقٍ كبير، وكانت
// `Settings.tsx` تستوردها في رأس الملفّ. فتقسيمُ المسارات وضعها في قطعة
// Settings — أي أنّ فتحَ الإعدادات على **أيّ** تبويب يجلب محرّك الخرائط كاملاً،
// حتى لو لم يُفتح تبويب التغطية قطّ. والآن القطعةُ مستقلّة ويُجلبها فتحُ نموذج
// «إضافة محافظة» وحده (المُركِّب الوحيد لهذا المكوّن، داخل `showAddForm &&`).
//
// و`utils/mapboxArabic.ts` كانت تُبقي التبعيةَ في قطعة Settings حتى لو أُزيل
// الاستيراد المباشر: هي تستورد mapboxgl على مستوى الوحدة **وتُسجّل إضافة RTL
// كأثرٍ جانبي**. فنقلُ استيرادها إلى هنا جزءٌ لا يُستغنى عنه من الفصل.
//
// المكوّن **أصمّ عن السياق**: لا يقرأ notificationContext ولا Firestore، بل
// يُبلّغ عبر `onPick`/`onReject` — فيُختبر بلا مزوّدات (نمط المستودع: حمولاتٌ
// وردود نداءٍ مُمرَّرة).

export interface ZoneMapPickerProps {
    /** قيم النموذج كما هي (نصوصاً) — الدبوس والدائرة يتبعانها. */
    latitude: string;
    longitude: string;
    radiusKm: string;
    /** اسم المحافظة — كتابتُه تنقل الكاميرا إليه (geocoding)، بلا تثبيت دبوس. */
    name: string;
    /** نقرةٌ داخل جازان: المركز الجديد. */
    onPick: (lat: number, lng: number) => void;
    /** نقرةٌ خارج حدود المنطقة — الرسالة للمستعمل شأنُ المُستدعي. */
    onReject: (message: string) => void;
    className?: string;
}

export default function ZoneMapPicker({
    latitude, longitude, radiusKm, name, onPick, onReject,
    className = 'w-full h-72 rounded-2xl overflow-hidden border-2 border-rose-200',
}: ZoneMapPickerProps) {
    const container = useRef<HTMLDivElement>(null);
    const map = useRef<mapboxgl.Map | null>(null);
    const marker = useRef<mapboxgl.Marker | null>(null);

    // مرآة للخواصّ تقرؤها معالِجات الخريطة (load/click) دون أسر قيمةٍ قديمة.
    // التحديث في أثر لا أثناء الرندر: الكتابة على ref أثناء الرندر غير آمنة في
    // الرندر المتزامن. المعالِجات لا تعمل إلا بعد التركيب فتقرأ المحدَّث دائماً.
    const vals = useRef({ latitude, longitude, radiusKm, onPick, onReject });
    useEffect(() => {
        vals.current = { latitude, longitude, radiusKm, onPick, onReject };
    }, [latitude, longitude, radiusKm, onPick, onReject]);

    /** يرسم/يحرّك الدبوس والدائرة من القيم الحالية (يدوية كانت أم من نقرة). */
    const syncFromProps = () => {
        const m = map.current;
        if (!m) return;
        const v = vals.current;
        const lat = parseFloat(v.latitude);
        const lng = parseFloat(v.longitude);
        const radius = parseFloat(v.radiusKm) || 15;
        if (isNaN(lat) || isNaN(lng)) return;
        if (!marker.current) {
            marker.current = new mapboxgl.Marker({ color: '#660033' }).setLngLat([lng, lat]).addTo(m);
        } else {
            marker.current.setLngLat([lng, lat]);
        }
        const src = m.getSource('zone-circle') as mapboxgl.GeoJSONSource | undefined;
        if (src) src.setData(circleGeoJSON(lat, lng, radius));
    };

    // إنشاء الخريطة عند التركيب وتدميرها عند التفكيك. كان الأثر معلّقاً على
    // `showAddForm` داخل Settings؛ وبصيرورته مكوّناً صار التركيب/التفكيك نفسه
    // هو البوّابة — فلا فرعَ «مغلق» يُدار بيده.
    useEffect(() => {
        if (map.current || !container.current) return;
        mapboxgl.accessToken = import.meta.env.VITE_MAPBOX_TOKEN;
        const m = new mapboxgl.Map({
            container: container.current,
            style: 'mapbox://styles/mapbox/streets-v12',
            // العرض الابتدائي = منطقة جازان كاملة، والكاميرا مقفولة داخلها (بهامش
            // طفيف) — لا تحريك/تصغير يُخرج الخريطة لأي منطقة أخرى.
            bounds: [[JAZAN_BBOX[0], JAZAN_BBOX[1]], [JAZAN_BBOX[2], JAZAN_BBOX[3]]],
            fitBoundsOptions: { padding: 24 },
            maxBounds: [
                [JAZAN_BBOX[0] - 0.25, JAZAN_BBOX[1] - 0.25],
                [JAZAN_BBOX[2] + 0.25, JAZAN_BBOX[3] + 0.25],
            ],
        });
        m.addControl(new mapboxgl.NavigationControl(), 'bottom-right');
        m.on('click', (e) => {
            // المحافظات محصورة بجازان — لا مركز خارج حدودها الإدارية.
            if (!isInJazan(e.lngLat.lng, e.lngLat.lat)) {
                vals.current.onReject('خارج نطاق منطقة جازان — حدد داخل حدود المنطقة');
                return;
            }
            vals.current.onPick(
                Number(e.lngLat.lat.toFixed(5)),
                Number(e.lngLat.lng.toFixed(5)),
            );
        });
        m.on('load', () => {
            arabizeMapLabels(m); // التسميات بالعربية (name_ar) بدل الإنجليزية الافتراضية
            // قناع «خارج جازان»: يُعتِّم كل ما حول المنطقة فلا تظهر إلا محافظاتها
            // وقراها وهجرها، مع حدّ بنفسجي يرسم حدودها الإدارية (اليابسة + فرسان).
            m.addSource('jazan-mask', { type: 'geojson', data: jazanMaskGeoJSON() });
            m.addLayer({ id: 'jazan-mask-fill', type: 'fill', source: 'jazan-mask', paint: { 'fill-color': '#e2e8f0', 'fill-opacity': 0.9 } });
            m.addSource('jazan-outline', { type: 'geojson', data: jazanOutlineGeoJSON() });
            m.addLayer({ id: 'jazan-outline-line', type: 'line', source: 'jazan-outline', paint: { 'line-color': '#660033', 'line-width': 2.5 } });
            m.addSource('zone-circle', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] },
            });
            m.addLayer({ id: 'zone-circle-fill', type: 'fill', source: 'zone-circle', paint: { 'fill-color': '#660033', 'fill-opacity': 0.15 } });
            m.addLayer({ id: 'zone-circle-line', type: 'line', source: 'zone-circle', paint: { 'line-color': '#660033', 'line-width': 2 } });
            syncFromProps(); // قيمٌ أُدخلت يدوياً قبل جاهزية الخريطة تُرسم الآن
        });
        map.current = m;
        return () => {
            marker.current = null;
            map.current?.remove();
            map.current = null;
        };
    }, []);

    // مزامنة الدبوس/الدائرة مع أي تغيير في الإحداثيات أو النطاق.
    useEffect(() => {
        syncFromProps();
    }, [latitude, longitude, radiusKm]);

    // (تكافؤ التطبيق) كتابة اسم المحافظة تنقل الخريطة إليه تلقائياً — geocoding
    // بنفس التوكن، بلا تثبيت دبوس: الانتقال للعرض فقط، والنقرة هي التي تحدّد
    // المركز. صامت عند الفشل.
    useEffect(() => {
        if (name.trim().length < 3) return;
        const t = setTimeout(async () => {
            try {
                const q = encodeURIComponent(name.trim());
                // bbox: قصر نتائج البحث على منطقة جازان فقط (لا مدن/مناطق أخرى).
                const r = await fetch(`https://api.mapbox.com/geocoding/v5/mapbox.places/${q}.json?access_token=${import.meta.env.VITE_MAPBOX_TOKEN}&country=sa&language=ar&limit=1&bbox=${JAZAN_BBOX.join(',')}`);
                const j = await r.json();
                const c = j?.features?.[0]?.center;
                if (Array.isArray(c) && c.length >= 2 && map.current) {
                    map.current.flyTo({ center: [c[0], c[1]], zoom: 10 });
                }
            } catch { /* صامت — الخريطة تبقى حيث هي */ }
        }, 800);
        return () => clearTimeout(t);
    }, [name]);

    return <div ref={container} className={className} />;
}
