// دائرة نطاق التغطية كمضلّع GeoJSON (64 نقطة) حول المركز — MapBox لا يرسم دائرة
// جغرافية بالكيلومتر مباشرةً (طبقة `circle` بالبكسل فتتغيّر مع التقريب)، فنبنيها
// مضلّعاً جغرافياً يثبُت حجمُه الحقيقي مهما قُرِّبت الخريطة.
//
// هندسةٌ خالصة بلا أيّ تبعية — لا mapbox-gl ولا React — فتبقى خارج قطعة الخريطة
// وتُختبر وحدها. (كانت في Settings.tsx، ونُقلت هنا لا إلى مكوّن الخريطة: تصديرُ
// دالّةٍ من ملفّ مكوّنٍ يُعطّل fast refresh.)
export const circleGeoJSON = (
    lat: number,
    lng: number,
    radiusKm: number,
): GeoJSON.FeatureCollection => {
    const points = 64;
    // درجةُ الطول تضيق بجيب تمام خط العرض؛ ودرجةُ العرض شبه ثابتة (110.574 كم).
    const distX = radiusKm / (111.32 * Math.cos((lat * Math.PI) / 180));
    const distY = radiusKm / 110.574;
    const coords: [number, number][] = [];
    for (let i = 0; i <= points; i++) {
        const theta = (i / points) * 2 * Math.PI;
        coords.push([lng + distX * Math.cos(theta), lat + distY * Math.sin(theta)]);
    }
    return {
        type: 'FeatureCollection',
        features: [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [coords] } }],
    };
};
