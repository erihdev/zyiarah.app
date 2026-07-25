import { useState, useEffect, useRef } from 'react';
import { Save, Bell, Shield, Wallet, MapPin, Search, Smartphone, Loader2, CheckCircle2, ChevronLeft, CreditCard, Activity, Globe, Database, KeyRound, ArrowRight, Plus, Navigation, ToggleLeft, ToggleRight, Trash2 } from 'lucide-react';
import { doc, getDoc, setDoc, collection, addDoc, updateDoc, deleteDoc, onSnapshot, query, orderBy, GeoPoint, serverTimestamp } from 'firebase/firestore';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/Notification.tsx';
import { arabizeMapLabels } from '../utils/mapboxArabic.ts';
import { JAZAN_BBOX, jazanMaskGeoJSON, jazanOutlineGeoJSON, isInJazan } from '../utils/jazanBoundary.ts';

interface SystemSettings {
    // General
    terms_url: string;
    support_url: string;
    privacy_policy: string;
    maintenance_mode: boolean;

    // Payments
    commission_rate: number;
    vat_rate: number;
    min_wallet_balance: number;
    tamara_enabled: boolean;

    // Notifications
    sms_on_order: boolean;
    push_on_assign: boolean;
    push_on_completed: boolean;
}

interface CoverageZone {
    id: string;
    name: string;
    latitude: number;
    longitude: number;
    radiusKm: number;
    enabled: boolean;
    rank: number;
}

// (تكافؤ مع تطبيق الأدمن — admin_hourly_zones_screen.dart) نفس خيارات الساعات ونفس
// حقول التسعير حرفياً: prices / sofaSqmPrice / rugSqmPrice / ac*Price / car*Price —
// وهي الحقول الموثوقة التي يقرؤها التسعير الخادمي (functions/pricing.js). كان النموذج
// هنا يبذر أسعار ساعات ثابتة لم يُدخلها أحد (35/120/…) وبلا حقول سيارات إطلاقاً.
const ZONE_HOUR_OPTIONS = [1, 2, 4, 5, 6, 7, 8];
const hourLabel = (h: number) => (h === 1 ? 'ساعة' : `${h} ساعات`);

const emptyZoneForm = {
    name: '', latitude: '', longitude: '', radiusKm: '15',
    // الساعات تبدأ فارغة: فارغ/0 = «غير مسعّرة» فتُعطَّل الشريحة بدل بيعها بسعر لم يُعتمد.
    hourPrices: Object.fromEntries(ZONE_HOUR_OPTIONS.map(h => [String(h), ''])) as Record<string, string>,
    // البقية تُبذر بنفس افتراضيات التطبيق (service_pricing_defaults.dart).
    sofaSqmPrice: '35', rugSqmPrice: '15',
    acMaintWindowPrice: '100', acMaintSplitPrice: '150',
    acWashWindowPrice: '80', acWashSplitPrice: '120',
    carSmallPrice: '100', carMediumPrice: '150', carLargePrice: '200',
};

// مجموعات حقول الأسعار المفردة — نفس تسميات حوار التطبيق.
const SOFA_RUG_FIELDS = [
    { key: 'sofaSqmPrice', label: 'الكنب (ر.س/م طولي)' },
    { key: 'rugSqmPrice', label: 'السجاد (ر.س/م²)' },
] as const;
const AC_FIELDS = [
    { key: 'acMaintWindowPrice', label: 'صيانة — شباك' },
    { key: 'acMaintSplitPrice', label: 'صيانة — سبليت' },
    { key: 'acWashWindowPrice', label: 'غسيل — شباك' },
    { key: 'acWashSplitPrice', label: 'غسيل — سبليت' },
] as const;
const CAR_FIELDS = [
    { key: 'carSmallPrice', label: 'صغيرة' },
    { key: 'carMediumPrice', label: 'وسط' },
    { key: 'carLargePrice', label: 'كبيرة' },
] as const;

const zoneInputCls = 'w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all';

// دائرة نطاق التغطية كمضلّع GeoJSON (64 نقطة) حول المركز — MapBox لا يرسم دائرة
// جغرافية بالكيلومتر مباشرةً (طبقة circle بالبكسل)، فنبنيها كمضلّع يثبُت مع التقريب.
const circleGeoJSON = (lat: number, lng: number, radiusKm: number): GeoJSON.FeatureCollection => {
    const points = 64;
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

// إعداد التحديث الإجباري — يُخزَّن في مستند منفصل system_configs/app_update
// والذي يقرأه التطبيق (app_update_service.dart). كانت اللوحة سابقاً تكتب
// force_update_version/enabled في main_settings الذي لا يقرأه التطبيق إطلاقاً.
interface AppUpdateConfig {
    enabled: boolean;
    latest_build: number;
    force: boolean;
    message: string;
}
const defaultAppUpdate: AppUpdateConfig = {
    enabled: false,
    latest_build: 0,
    force: false,
    message: '',
};

const defaultSettings: SystemSettings = {
    terms_url: "https://zyiarah.com/terms",
    support_url: "https://zyiarah.com/support",
    privacy_policy: "نحن في تطبيق زيارة نلتزم بحماية بياناتك الشخصية...",
    maintenance_mode: false,
    commission_rate: 15,
    vat_rate: 15,
    min_wallet_balance: -50,
    tamara_enabled: false,
    sms_on_order: true,
    push_on_assign: true,
    push_on_completed: true,
};

type TabType = 'general' | 'payments' | 'notifications' | 'coverage';

export default function Settings() {
    const { toast } = useNotification();
    const [activeTab, setActiveTab] = useState<TabType>('general');
    const [settings, setSettings] = useState<SystemSettings>(defaultSettings);
    const [appUpdate, setAppUpdate] = useState<AppUpdateConfig>(defaultAppUpdate);
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [saveSuccess, setSaveSuccess] = useState(false);
    const [zones, setZones] = useState<CoverageZone[]>([]);
    const [newZone, setNewZone] = useState(emptyZoneForm);
    const [isAddingZone, setIsAddingZone] = useState(false);
    const [showAddForm, setShowAddForm] = useState(false);
    // true فقط عند فشل قراءة الإعدادات (لا عند غيابها لأول مرة) — يمنع الحفظ فوق
    // الإعدادات الإنتاجية بالقيم الافتراضية المعروضة بعد قراءة فاشلة.
    const [loadFailed, setLoadFailed] = useState(false);
    const zoneNameRef = useRef<HTMLInputElement>(null);

    // (تكافؤ التطبيق) خريطة اختيار مركز المحافظة: نقرة تحدّد المركز، والدائرة تتبع النطاق.
    const zoneMapContainer = useRef<HTMLDivElement>(null);
    const zoneMap = useRef<mapboxgl.Map | null>(null);
    const zoneMarker = useRef<mapboxgl.Marker | null>(null);
    // مرآة للنموذج تقرؤها معالِجات الخريطة (load/click) دون أسر state قديم.
    const newZoneRef = useRef(newZone);
    newZoneRef.current = newZone;

    useEffect(() => {
        const fetchSettings = async () => {
            try {
                const docRef = doc(db, 'system_configs', 'main_settings');
                const updRef = doc(db, 'system_configs', 'app_update');
                const [docSnap, updSnap] = await Promise.all([getDoc(docRef), getDoc(updRef)]);
                if (docSnap.exists()) {
                    setSettings({ ...defaultSettings, ...docSnap.data() } as SystemSettings);
                }
                if (updSnap.exists()) {
                    setAppUpdate({ ...defaultAppUpdate, ...updSnap.data() } as AppUpdateConfig);
                }
            } catch (error) {
                console.error("Error fetching settings:", error);
                setLoadFailed(true);
            } finally {
                setIsLoading(false);
            }
        };
        fetchSettings();
    }, []);

    useEffect(() => {
        const q = query(collection(db, 'service_zones'), orderBy('rank'));
        const unsub = onSnapshot(q, (snap) => {
            setZones(snap.docs.map(d => {
                const data = d.data();
                const center = data.centerLoc;
                return {
                    id: d.id,
                    name: data.name || '',
                    latitude: center ? center.latitude : 0.0,
                    longitude: center ? center.longitude : 0.0,
                    radiusKm: data.radiusKm || 15,
                    enabled: data.enabled !== false,
                    rank: data.rank || 0,
                } as CoverageZone;
            }));
        }, (err) => console.error('service_zones snapshot error:', err));
        return () => unsub();
    }, []);

    // يرسم/يحرّك الدبوس والدائرة من قيم النموذج الحالية (يدوية كانت أم من نقرة الخريطة).
    const syncZoneMapFromForm = () => {
        const m = zoneMap.current;
        if (!m) return;
        const z = newZoneRef.current;
        const lat = parseFloat(z.latitude);
        const lng = parseFloat(z.longitude);
        const radius = parseFloat(z.radiusKm) || 15;
        if (isNaN(lat) || isNaN(lng)) return;
        if (!zoneMarker.current) {
            zoneMarker.current = new mapboxgl.Marker({ color: '#006FBA' }).setLngLat([lng, lat]).addTo(m);
        } else {
            zoneMarker.current.setLngLat([lng, lat]);
        }
        const src = m.getSource('zone-circle') as mapboxgl.GeoJSONSource | undefined;
        if (src) src.setData(circleGeoJSON(lat, lng, radius));
    };

    // إنشاء الخريطة عند فتح النموذج وتدميرها عند إغلاقه (الحاوية لا تُرسم إلا وهو مفتوح).
    useEffect(() => {
        if (!showAddForm) {
            zoneMarker.current = null;
            zoneMap.current?.remove();
            zoneMap.current = null;
            return;
        }
        if (zoneMap.current || !zoneMapContainer.current) return;
        mapboxgl.accessToken = import.meta.env.VITE_MAPBOX_TOKEN;
        const m = new mapboxgl.Map({
            container: zoneMapContainer.current,
            style: 'mapbox://styles/mapbox/streets-v12',
            // العرض الابتدائي = منطقة جازان كاملة، والكاميرا مقفولة داخلها (بهامش طفيف)
            // — لا تحريك/تصغير يُخرج الخريطة لأي منطقة أخرى.
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
                toast.error('خارج نطاق منطقة جازان — حدد داخل حدود المنطقة');
                return;
            }
            setNewZone(p => ({
                ...p,
                latitude: e.lngLat.lat.toFixed(5),
                longitude: e.lngLat.lng.toFixed(5),
            }));
        });
        m.on('load', () => {
            arabizeMapLabels(m); // التسميات بالعربية (name_ar) بدل الإنجليزية الافتراضية
            // قناع «خارج جازان»: يُعتِّم كل ما حول المنطقة فلا تظهر إلا محافظاتها
            // وقراها وهجرها، مع حدّ بنفسجي يرسم حدودها الإدارية (اليابسة + فرسان).
            m.addSource('jazan-mask', { type: 'geojson', data: jazanMaskGeoJSON() });
            m.addLayer({ id: 'jazan-mask-fill', type: 'fill', source: 'jazan-mask', paint: { 'fill-color': '#e2e8f0', 'fill-opacity': 0.9 } });
            m.addSource('jazan-outline', { type: 'geojson', data: jazanOutlineGeoJSON() });
            m.addLayer({ id: 'jazan-outline-line', type: 'line', source: 'jazan-outline', paint: { 'line-color': '#006FBA', 'line-width': 2.5 } });
            m.addSource('zone-circle', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] },
            });
            m.addLayer({ id: 'zone-circle-fill', type: 'fill', source: 'zone-circle', paint: { 'fill-color': '#006FBA', 'fill-opacity': 0.15 } });
            m.addLayer({ id: 'zone-circle-line', type: 'line', source: 'zone-circle', paint: { 'line-color': '#006FBA', 'line-width': 2 } });
            syncZoneMapFromForm(); // قيمٌ أُدخلت يدوياً قبل جاهزية الخريطة تُرسم الآن
        });
        zoneMap.current = m;
        return () => {
            zoneMarker.current = null;
            zoneMap.current?.remove();
            zoneMap.current = null;
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [showAddForm]);

    // مزامنة الدبوس/الدائرة مع أي تغيير في الإحداثيات أو النطاق.
    useEffect(() => {
        syncZoneMapFromForm();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [newZone.latitude, newZone.longitude, newZone.radiusKm, showAddForm]);

    // (تكافؤ التطبيق) كتابة اسم المحافظة تنقل الخريطة إليه تلقائياً — geocoding بنفس التوكن،
    // بلا تثبيت دبوس: الانتقال للعرض فقط، والنقرة هي التي تحدّد المركز. صامت عند الفشل.
    useEffect(() => {
        if (!showAddForm || newZone.name.trim().length < 3) return;
        const t = setTimeout(async () => {
            try {
                const q = encodeURIComponent(newZone.name.trim());
                // bbox: قصر نتائج البحث على منطقة جازان فقط (لا مدن/مناطق أخرى).
                const r = await fetch(`https://api.mapbox.com/geocoding/v5/mapbox.places/${q}.json?access_token=${import.meta.env.VITE_MAPBOX_TOKEN}&country=sa&language=ar&limit=1&bbox=${JAZAN_BBOX.join(',')}`);
                const j = await r.json();
                const c = j?.features?.[0]?.center;
                if (Array.isArray(c) && c.length >= 2 && zoneMap.current) {
                    zoneMap.current.flyTo({ center: [c[0], c[1]], zoom: 10 });
                }
            } catch { /* صامت — الخريطة تبقى حيث هي */ }
        }, 800);
        return () => clearTimeout(t);
    }, [newZone.name, showAddForm]);

    const handleAddZone = async () => {
        const lat = parseFloat(newZone.latitude);
        const lng = parseFloat(newZone.longitude);
        const radius = parseFloat(newZone.radiusKm);
        if (!newZone.name.trim() || isNaN(lat) || isNaN(lng) || isNaN(radius)) {
            toast.error('يرجى إدخال جميع الحقول بشكل صحيح');
            return;
        }
        setIsAddingZone(true);
        try {
            // نفس مخطط حفظ تطبيق الأدمن حرفياً — التسعير الخادمي يقرأ هذه الحقول.
            // فارغ/غير رقمي = 0 = «غير مسعّرة» فتُعطَّل الخدمة/الشريحة بدل بيعها بسعر لم يُعتمد.
            const num = (s: string) => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
            await addDoc(collection(db, 'service_zones'), {
                name: newZone.name.trim(),
                centerLoc: new GeoPoint(lat, lng),
                radiusKm: radius,
                enabled: true,
                rank: zones.length + 1,
                prices: Object.fromEntries(
                    ZONE_HOUR_OPTIONS.map(h => [String(h), num(newZone.hourPrices[String(h)])])),
                sofaSqmPrice: num(newZone.sofaSqmPrice),
                rugSqmPrice: num(newZone.rugSqmPrice),
                acMaintWindowPrice: num(newZone.acMaintWindowPrice),
                acMaintSplitPrice: num(newZone.acMaintSplitPrice),
                acWashWindowPrice: num(newZone.acWashWindowPrice),
                acWashSplitPrice: num(newZone.acWashSplitPrice),
                carSmallPrice: num(newZone.carSmallPrice),
                carMediumPrice: num(newZone.carMediumPrice),
                carLargePrice: num(newZone.carLargePrice),
                updated_at: serverTimestamp(),
            });
            setNewZone(emptyZoneForm);
            setShowAddForm(false);
            toast.success(`تمت إضافة ${newZone.name.trim()} بنجاح`);
        } catch (e) {
            console.error(e);
            toast.error('حدث خطأ أثناء الإضافة');
        } finally {
            setIsAddingZone(false);
        }
    };

    // (تكافؤ التطبيق) نسخ أسعار محافظة قائمة إلى النموذج — تعبئة فقط، لا كتابة على أحد؛
    // الحفظ الصريح هو التأكيد. تُجلب من المستند مباشرةً لأن قائمة zones لا تحمل الأسعار.
    const handleCopyPricesFrom = async (zoneId: string) => {
        if (!zoneId) return;
        try {
            const snap = await getDoc(doc(db, 'service_zones', zoneId));
            if (!snap.exists()) return;
            const d = snap.data() as Record<string, unknown>;
            const p = (d.prices ?? {}) as Record<string, unknown>;
            const s = (v: unknown) => (v === undefined || v === null ? '' : String(v));
            setNewZone(prev => ({
                ...prev,
                hourPrices: Object.fromEntries(
                    ZONE_HOUR_OPTIONS.map(h => [String(h), s(p[String(h)])])) as Record<string, string>,
                sofaSqmPrice: s(d.sofaSqmPrice), rugSqmPrice: s(d.rugSqmPrice),
                acMaintWindowPrice: s(d.acMaintWindowPrice), acMaintSplitPrice: s(d.acMaintSplitPrice),
                acWashWindowPrice: s(d.acWashWindowPrice), acWashSplitPrice: s(d.acWashSplitPrice),
                carSmallPrice: s(d.carSmallPrice), carMediumPrice: s(d.carMediumPrice), carLargePrice: s(d.carLargePrice),
            }));
            toast.success('نُسخت الأسعار إلى النموذج — راجعها ثم احفظ');
        } catch (e) {
            console.error(e);
            toast.error('تعذّر نسخ الأسعار');
        }
    };

    const handleToggleZone = async (zone: CoverageZone) => {
        try {
            await updateDoc(doc(db, 'service_zones', zone.id), { enabled: !zone.enabled });
        } catch (e) {
            toast.error('حدث خطأ أثناء التحديث');
        }
    };

    const handleDeleteZone = async (zone: CoverageZone) => {
        if (!await confirm(`حذف محافظة "${zone.name}" نهائياً؟`)) return;
        try {
            await deleteDoc(doc(db, 'service_zones', zone.id));
        } catch (e) {
            toast.error('حدث خطأ أثناء الحذف');
        }
    };

    const handleSave = async () => {
        if (loadFailed) {
            toast.error('تعذّر تحميل الإعدادات الحالية — لا يمكن الحفظ فوقها بقيم افتراضية. أعد تحميل الصفحة أولاً.');
            return;
        }
        setIsSaving(true);
        try {
            const docRef = doc(db, 'system_configs', 'main_settings');
            const updRef = doc(db, 'system_configs', 'app_update');
            await Promise.all([
                setDoc(docRef, settings, { merge: true }),
                // نكتب بالمفاتيح التي يقرأها التطبيق فعلاً: enabled / latest_build (int) / force / message
                setDoc(updRef, {
                    enabled: appUpdate.enabled,
                    latest_build: Number(appUpdate.latest_build) || 0,
                    force: appUpdate.force,
                    message: appUpdate.message || '',
                }, { merge: true }),
                // نشر سياسة الخصوصية لمستند **عام** تقرأه صفحة zyiarah.com/privacy بلا
                // تسجيل دخول (system_configs يتطلّب مصادقة فلا تصلح للصفحة العامة).
                setDoc(doc(db, 'public_content', 'privacy'), {
                    content: settings.privacy_policy || '',
                    updated_at: new Date(),
                }, { merge: true }),
            ]);

            // Show brief success indication
            setSaveSuccess(true);
            setTimeout(() => setSaveSuccess(false), 3000);
        } catch (error) {
            console.error("Error saving settings:", error);
            toast.error("حدث خطأ أثناء حفظ الإعدادات.");
        } finally {
            setIsSaving(false);
        }
    };

    const handleChange = <K extends keyof SystemSettings>(key: K, value: SystemSettings[K]) => {
        setSettings(prev => ({ ...prev, [key]: value }));
    };

    if (isLoading) {
        return (
            <div className="flex flex-col h-[70vh] items-center justify-center space-y-4">
                <div className="relative w-20 h-20">
                    <div className="absolute inset-0 rounded-full border-t-4 border-[#006FBA] animate-spin"></div>
                    <div className="absolute inset-2 rounded-full border-t-4 border-sky-500 animate-spin opacity-50 animation-delay-150"></div>
                </div>
                <div className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-[#006FBA] to-sky-600 animate-pulse">
                    تهيئة الإعدادات...
                </div>
            </div>
        );
    }

    const tabs = [
        { id: 'general', label: 'عام وأمان', icon: Shield, color: 'from-[#006FBA] to-[#006FBA]', bg: 'bg-[#EDF5FC]/50', border: 'border-[#D4E8F7]', text: 'text-[#00578F]' },
        { id: 'payments', label: 'المدفوعات', icon: Wallet, color: 'from-emerald-500 to-green-600', bg: 'bg-emerald-50/50', border: 'border-emerald-100', text: 'text-emerald-700' },
        { id: 'notifications', label: 'الإشعارات', icon: Bell, color: 'from-orange-500 to-amber-600', bg: 'bg-orange-50/50', border: 'border-orange-100', text: 'text-orange-700' },
        { id: 'coverage', label: 'التغطية', icon: MapPin, color: 'from-blue-500 to-sky-600', bg: 'bg-blue-50/50', border: 'border-blue-100', text: 'text-blue-700' },
    ] as const;

    const currentTabColor = tabs.find(t => t.id === activeTab)?.color || tabs[0].color;

    return (
        <div className="space-y-8 pb-12 animate-in fade-in slide-in-from-bottom-8 duration-700 max-w-7xl mx-auto">
            {/* Header Section */}
            <div className="relative p-8 rounded-[2rem] bg-white border border-slate-100 shadow-[0_8px_30px_rgb(0,0,0,0.04)] overflow-hidden flex flex-col md:flex-row items-center justify-between gap-6 isolation-auto z-0">
                {/* Decorative background blurs */}
                <div className={`absolute top-0 right-0 w-64 h-64 bg-gradient-to-bl ${currentTabColor} rounded-full opacity-[0.05] blur-3xl -translate-y-1/2 translate-x-1/2 transition-colors duration-500`}></div>
                <div className={`absolute bottom-0 left-0 w-80 h-80 bg-gradient-to-tr ${currentTabColor} rounded-full opacity-[0.03] blur-3xl translate-y-1/3 -translate-x-1/3 transition-colors duration-500`}></div>
                
                <div className="relative z-10 flex items-center gap-6">
                    <div className={`w-16 h-16 rounded-2xl bg-gradient-to-br ${currentTabColor} p-0.5 shadow-lg shadow-[#2E86C8]/20 transition-colors duration-500`}>
                        <div className="w-full h-full bg-white rounded-[14px] flex items-center justify-center">
                            <SettingsIcon activeTab={activeTab} />
                        </div>
                    </div>
                    <div>
                        <h2 className="text-3xl font-black text-slate-900 tracking-tight mb-2">إعدادات النظام</h2>
                        <p className="text-slate-500 font-medium flex items-center gap-2">
                            <Activity size={16} className="text-emerald-500" />
                            إدارة شاملة لتكوينات التطبيق وقواعد العمل
                        </p>
                    </div>
                </div>

                <div className="relative z-10 flex w-full md:w-auto">
                    <button
                        type="button"
                        onClick={handleSave}
                        disabled={isSaving}
                        className={`w-full md:w-auto relative group overflow-hidden flex items-center justify-center gap-3 px-8 py-4 rounded-2xl font-bold text-white transition-all duration-300 disabled:opacity-70 disabled:cursor-not-allowed disabled:transform-none shadow-xl
                            ${saveSuccess 
                                ? 'bg-emerald-500 shadow-emerald-500/30' 
                                : `bg-gradient-to-r ${currentTabColor} shadow-[#2E86C8]/25 hover:shadow-[#2E86C8]/40 hover:-translate-y-1 hover:scale-[1.02]`
                            }`}
                    >
                        <div className="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform duration-300 ease-out"></div>
                        <span className="relative z-10 flex items-center gap-3">
                            {isSaving ? (
                                <><Loader2 size={22} className="animate-spin" /> جاري الحفظ...</>
                            ) : saveSuccess ? (
                                <><CheckCircle2 size={24} className="text-white" /> تم الحفظ بنجاح!</>
                            ) : (
                                <><Save size={22} className="group-hover:scale-110 transition-transform" /> حفظ التغييرات</>
                            )}
                        </span>
                    </button>
                </div>
            </div>

            <div className="flex flex-col lg:flex-row gap-8 items-start">
                {/* Advanced Modern Navigation Sidebar */}
                <div className="w-full lg:w-[320px] flex-shrink-0 space-y-4">
                    <div className="bg-white rounded-[2rem] p-3 shadow-[0_8px_30px_rgb(0,0,0,0.03)] border border-slate-100 relative z-20">
                        {/* Search Input */}
                        <div className="p-2 mb-2">
                            <div className="relative group">
                                <div className="absolute inset-y-0 right-0 flex items-center pr-4 pointer-events-none">
                                    <Search size={18} className="text-slate-400 group-focus-within:text-[#2E86C8] transition-colors" />
                                </div>
                                <input
                                    type="text"
                                    placeholder="بحث سريع..."
                                    className="w-full bg-slate-50/50 border border-slate-200 text-sm rounded-xl py-3 pr-11 pl-4 outline-none focus:bg-white focus:border-[#a86faa] focus:ring-4 focus:ring-[#2E86C8]/10 transition-all text-slate-700 font-medium placeholder-slate-400"
                                />
                            </div>
                        </div>

                        <div className="h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent mb-4 mx-4"></div>

                        <nav className="space-y-1">
                            {tabs.map((tab) => {
                                const isActive = activeTab === tab.id;
                                const Icon = tab.icon;
                                return (
                                    <button
                                        key={tab.id}
                                        type="button"
                                        onClick={() => setActiveTab(tab.id as TabType)}
                                        className={`w-full relative flex items-center justify-between px-5 py-4 rounded-xl font-bold transition-all duration-300 group overflow-hidden ${
                                            isActive ? 'bg-slate-50' : 'hover:bg-slate-50/50 text-slate-500 hover:text-slate-800'
                                        }`}
                                    >
                                        {/* Active State Background Gradient Effect */}
                                        <div className={`absolute inset-0 opacity-0 transition-opacity duration-300 ${isActive ? 'opacity-100' : 'group-hover:opacity-100'}`}>
                                            <div className={`absolute right-0 top-0 bottom-0 w-1.5 rounded-l-full bg-gradient-to-b ${tab.color} transform origin-right transition-transform duration-300 ${isActive ? 'scale-x-100' : 'scale-x-0 group-hover:scale-x-100 opacity-50'}`}></div>
                                            {isActive && <div className={`absolute inset-0 bg-gradient-to-l ${tab.color} opacity-[0.03]`}></div>}
                                        </div>

                                        <div className="relative z-10 flex items-center gap-4">
                                            <div className={`flex items-center justify-center w-10 h-10 rounded-xl transition-all duration-300 ${
                                                isActive 
                                                    ? `bg-gradient-to-br ${tab.color} shadow-lg shadow-${tab.color.split('-')[1]}/30 text-white scale-110` 
                                                    : `bg-slate-100 text-slate-400 group-hover:text-slate-600 group-hover:scale-105`
                                            }`}>
                                                <Icon size={20} strokeWidth={isActive ? 2.5 : 2} />
                                            </div>
                                            <span className={`text-[15px] tracking-wide ${isActive ? 'text-slate-800' : ''}`}>{tab.label}</span>
                                        </div>
                                        
                                        <ChevronLeft size={18} className={`relative z-10 transition-transform duration-300 ${isActive ? `text-${tab.color.split('-')[1]}-500 -translate-x-1` : 'text-slate-200 group-hover:-translate-x-1'}`} />
                                    </button>
                                );
                            })}
                        </nav>
                    </div>
                    
                    {/* Compact Help Box */}
                    <div className="bg-gradient-to-br from-[#006FBA] to-[#00578F] rounded-[2rem] p-6 text-white shadow-xl shadow-[#006FBA]/20 relative overflow-hidden hidden lg:block">
                        <div className="absolute -right-8 -top-8 w-32 h-32 bg-white opacity-10 rounded-full blur-2xl"></div>
                        <div className="relative z-10">
                            <h3 className="font-bold text-lg mb-2">هل تحتاج مساعدة؟</h3>
                            <p className="text-[#D4E8F7] text-sm mb-4 leading-relaxed font-medium">وثائق النظام تحتوي على تفاصيل كاملة لجميع الإعدادات المبينة هنا.</p>
                            <a href={settings.support_url || 'https://zyiarah.com/support'} target="_blank" rel="noopener noreferrer" className="bg-white/10 hover:bg-white/20 backdrop-blur-md border border-white/20 text-white text-sm font-bold py-2.5 px-4 rounded-xl transition-colors inline-flex items-center gap-2">
                                تصفح الدليل <ArrowRight size={16} />
                            </a>
                        </div>
                    </div>
                </div>

                {/* Main Content Area - Glassmorphism & Animations */}
                <div className="flex-1 w-full bg-white rounded-[2.5rem] shadow-[0_8px_40px_rgb(0,0,0,0.04)] border border-slate-100 relative overflow-hidden min-h-[600px] z-10 isolate transition-all duration-500">
                    {/* Animated Tab Content Container */}
                    <div key={activeTab} className="h-full animate-in fade-in zoom-in-95 slide-in-from-left-4 duration-500 fill-mode-both">
                        
                        {activeTab === 'general' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-slate-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-[#EDF5FC] text-[#006FBA] rounded-2xl">
                                            <Shield size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">عام وأمان</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">تكوين إعدادات الوصول وتفضيلات الأمان الرئيسية للنظام</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="p-10 space-y-10 overflow-y-auto">
                                    
                                    {/* API Keys Section */}
                                    <section>
                                        <h4 className="flex items-center gap-2 text-lg font-bold text-slate-800 mb-6">
                                            <KeyRound size={20} className="text-[#006FBA]" /> المفاتيح الأمنية السحابية
                                        </h4>
                                        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-[#A9D2EF] group">
                                                <label htmlFor="zatca-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                                                <div className="relative">
                                                    <input id="zatca-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-[#a86faa] transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => toast.info('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح الزكاة والدخل من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-[#006FBA] bg-[#EDF5FC] hover:bg-[#006FBA] hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-[#A9D2EF] group">
                                                <label htmlFor="firebase-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح Firebase Admin</label>
                                                <div className="relative">
                                                    <input id="firebase-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-[#a86faa] transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => toast.info('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح Firebase من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-[#006FBA] bg-[#EDF5FC] hover:bg-[#006FBA] hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                        </div>
                                    </section>

                                    <div className="w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>

                                    {/* App Versioning & Legal */}
                                    <section>
                                        <h4 className="flex items-center gap-2 text-lg font-bold text-slate-800 mb-6">
                                            <Smartphone size={20} className="text-[#2E86C8]" /> توافق المتاجر والنصوص القانونية
                                        </h4>
                                        <div className="bg-white border border-slate-200 shadow-sm rounded-[2rem] p-8 relative overflow-hidden">
                                            <div className="absolute top-0 right-0 w-32 h-32 bg-[#EDF5FC] rounded-full blur-3xl -translate-y-10 translate-x-10 pointer-events-none"></div>
                                            
                                            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 relative z-10">
                                                <div className="md:col-span-2 flex flex-col gap-5 p-5 bg-[#EDF5FC]/50 border border-[#D4E8F7]/50 rounded-2xl">
                                                    <div className="flex flex-col md:flex-row gap-6 items-start md:items-center">
                                                        <div className="flex-1 w-full">
                                                            <label htmlFor="latest-build" className="block text-sm font-bold text-slate-800 mb-2">أحدث رقم بناء منشور (Latest Build)</label>
                                                            <p className="text-xs text-slate-500 font-medium mb-3">يظهر إشعار التحديث لكل مستخدم رقم بنائه أقدم من هذا الرقم فقط. (مثال: 209)</p>
                                                            <input
                                                                id="latest-build"
                                                                type="number"
                                                                min={0}
                                                                value={appUpdate.latest_build}
                                                                onChange={(e) => setAppUpdate(p => ({ ...p, latest_build: parseInt(e.target.value) || 0 }))}
                                                                className="w-full md:w-64 bg-white border border-slate-300 focus:border-[#2E86C8] focus:ring-4 focus:ring-[#2E86C8]/20 text-slate-800 font-bold text-sm rounded-xl px-5 py-3.5 outline-none transition-all shadow-sm text-left font-mono"
                                                                dir="ltr"
                                                                placeholder="209"
                                                            />
                                                        </div>
                                                        <div className="flex flex-col gap-3 self-stretch md:self-auto">
                                                            <div className="flex items-center justify-between gap-4 bg-white border border-slate-200 p-2 pl-4 pr-2 rounded-2xl shadow-sm">
                                                                <span className="text-sm font-bold text-slate-700">تفعيل الإشعار</span>
                                                                <label className="relative inline-flex items-center cursor-pointer">
                                                                    <input type="checkbox" aria-label="تفعيل إشعار التحديث" className="sr-only peer" checked={appUpdate.enabled} onChange={(e) => setAppUpdate(p => ({ ...p, enabled: e.target.checked }))} />
                                                                    <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-emerald-600"></div>
                                                                </label>
                                                            </div>
                                                            <div className="flex items-center justify-between gap-4 bg-white border border-slate-200 p-2 pl-4 pr-2 rounded-2xl shadow-sm">
                                                                <span className="text-sm font-bold text-slate-700">إجباري (لا يمكن تجاهله)</span>
                                                                <label className="relative inline-flex items-center cursor-pointer">
                                                                    <input type="checkbox" aria-label="تحديث إجباري" className="sr-only peer" checked={appUpdate.force} onChange={(e) => setAppUpdate(p => ({ ...p, force: e.target.checked }))} />
                                                                    <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-[#006FBA]"></div>
                                                                </label>
                                                            </div>
                                                        </div>
                                                    </div>
                                                    <div>
                                                        <label htmlFor="update-message" className="block text-sm font-bold text-slate-800 mb-2">رسالة التحديث (اختياري)</label>
                                                        <input
                                                            id="update-message"
                                                            type="text"
                                                            value={appUpdate.message}
                                                            onChange={(e) => setAppUpdate(p => ({ ...p, message: e.target.value }))}
                                                            className="w-full bg-white border border-slate-300 focus:border-[#2E86C8] focus:ring-4 focus:ring-[#2E86C8]/20 text-slate-800 font-medium text-sm rounded-xl px-5 py-3.5 outline-none transition-all shadow-sm"
                                                            placeholder="يتوفّر إصدار جديد بمزايا وتحسينات مهمة..."
                                                        />
                                                    </div>
                                                </div>

                                                <div className="space-y-2">
                                                    <label htmlFor="terms-url" className="block text-sm font-bold text-slate-700">رابط الشروط والأحكام</label>
                                                    <input
                                                        id="terms-url" type="url" value={settings.terms_url} onChange={(e) => handleChange('terms_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-[#2E86C8] focus:ring-4 focus:ring-[#2E86C8]/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/terms"
                                                    />
                                                </div>
                                                <div className="space-y-2">
                                                    <label htmlFor="support-url" className="block text-sm font-bold text-slate-700">رابط الدعم الفني</label>
                                                    <input
                                                        id="support-url" type="url" value={settings.support_url} onChange={(e) => handleChange('support_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-[#2E86C8] focus:ring-4 focus:ring-[#2E86C8]/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/support"
                                                    />
                                                </div>
                                                <div className="md:col-span-2 space-y-2">
                                                    <label htmlFor="privacy-policy" className="block text-sm font-bold text-slate-700">سياسة الخصوصية</label>
                                                    <p className="text-xs text-slate-500 font-medium">تُنشَر للعملاء داخل التطبيق <span className="font-bold">وعلى صفحة <a href="https://zyiarah.com/privacy" target="_blank" rel="noopener noreferrer" className="text-[#006FBA] underline">zyiarah.com/privacy</a> العامة</span> فور الحفظ. اترك سطراً فارغاً بين الفقرات.</p>
                                                    <textarea
                                                        id="privacy-policy" rows={12} value={settings.privacy_policy} onChange={(e) => handleChange('privacy_policy', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-4 outline-none focus:border-[#2E86C8] focus:ring-4 focus:ring-[#2E86C8]/10 transition-all resize-y leading-loose"
                                                        placeholder="اكتب سياسة الخصوصية هنا..."
                                                    />
                                                </div>
                                            </div>
                                        </div>
                                    </section>

                                    {/* Danger Zone: Maintenance Mode */}
                                    <section className="pt-4">
                                        <div className={`relative overflow-hidden rounded-[2rem] border transition-all duration-500 ${
                                            settings.maintenance_mode 
                                            ? 'bg-gradient-to-r from-red-50 to-orange-50 border-red-200 shadow-[0_0_40px_rgba(239,68,68,0.15)] ring-1 ring-red-500/20' 
                                            : 'bg-white border-slate-200 hover:border-slate-300'
                                        }`}>
                                            {settings.maintenance_mode && (
                                                <div className="absolute top-0 right-0 w-full h-full bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-red-500/10 via-transparent to-transparent pointer-events-none"></div>
                                            )}
                                            <div className="p-8 flex flex-col md:flex-row gap-6 items-center justify-between relative z-10">
                                                <div className="flex items-center gap-5">
                                                    <div className={`p-4 rounded-2xl border flex-shrink-0 transition-colors duration-500 ${
                                                        settings.maintenance_mode ? 'bg-red-500 border-red-600 text-white shadow-lg shadow-red-500/30 animate-pulse' : 'bg-slate-100 border-slate-200 text-slate-400'
                                                    }`}>
                                                        <Database size={32} strokeWidth={2} />
                                                    </div>
                                                    <div>
                                                        <h4 className={`text-xl font-black mb-1 transition-colors ${settings.maintenance_mode ? 'text-red-700' : 'text-slate-800'}`}>وضع الصيانة الداخلي (Maintenance)</h4>
                                                        <p className={`text-sm font-medium max-w-xl leading-relaxed ${settings.maintenance_mode ? 'text-red-600/80' : 'text-slate-500'}`}>عند تفعيل وضع الصيانة، سيتم قفل التطبيق للمستخدمين الخارجيين مع عرض رسالة صيانة مؤقتة ولن يتم استقبال طلبات جديدة.</p>
                                                    </div>
                                                </div>
                                                <button
                                                    type="button"
                                                    onClick={() => handleChange('maintenance_mode', !settings.maintenance_mode)}
                                                    className={`px-8 py-4 rounded-xl font-bold transition-all duration-300 w-full md:w-auto flex items-center justify-center gap-2 whitespace-nowrap border-2 ${
                                                        settings.maintenance_mode 
                                                        ? 'bg-white border-red-200 text-red-600 hover:bg-red-50 hover:border-red-300 shadow-sm' 
                                                        : 'bg-white border-slate-200 text-slate-700 hover:border-slate-300 hover:bg-slate-50 shadow-sm'
                                                    }`}
                                                >
                                                    {settings.maintenance_mode ? 'إيقاف الصيانة وفتح التطبيق' : 'تفعيل الصيانة وإغلاق التطبيق'}
                                                </button>
                                            </div>
                                        </div>
                                    </section>
                                </div>
                            </div>
                        )}

                        {activeTab === 'payments' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-emerald-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-emerald-50 text-emerald-600 rounded-2xl">
                                            <Wallet size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">المدفوعات والعمولات</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">إعداد وهيكلة الضرائب، العمولات، وسياسات الدفع النقدي.</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="p-10 space-y-8 overflow-y-auto">
                                    
                                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                                        <div className="bg-white border border-slate-200 p-8 rounded-[2rem] shadow-sm relative overflow-hidden group hover:border-emerald-200 hover:shadow-md transition-all">
                                            <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity"><Activity size={64} /></div>
                                            <label htmlFor="vat-rate" className="block text-sm font-bold text-slate-800 mb-2 relative z-10">ضريبة القيمة المضافة (VAT)</label>
                                            <p className="text-xs text-slate-500 font-medium mb-4 h-8 relative z-10">تضاف على تكلفة الخدمة كرسوم إضافية.</p>
                                            <div className="relative z-10 flex items-center">
                                                <input
                                                    id="vat-rate"
                                                    type="number" value={settings.vat_rate} onChange={(e) => handleChange('vat_rate', Number(e.target.value))}
                                                    className="w-full bg-slate-50 border border-slate-200 text-slate-800 font-black text-2xl rounded-xl px-5 py-4 outline-none focus:bg-white focus:border-emerald-500 focus:ring-4 focus:ring-emerald-500/10 transition-all text-center"
                                                    dir="ltr"
                                                />
                                                <span className="absolute left-6 text-slate-400 font-black text-xl pointer-events-none">%</span>
                                            </div>
                                        </div>

                                        <div className="bg-white border border-red-100 p-8 rounded-[2rem] shadow-sm relative overflow-hidden group hover:border-red-300 hover:shadow-md transition-all">
                                            <div className="absolute top-0 right-0 p-4 text-red-500 opacity-5 group-hover:opacity-10 transition-opacity"><ArrowRight size={64} className="rotate-90" /></div>
                                            <label htmlFor="min-wallet" className="block text-sm font-bold text-slate-800 mb-2 relative z-10">الحد الأدنى للمحفظة</label>
                                            <p className="text-xs text-slate-500 font-medium mb-4 h-8 relative z-10">حد المديونية الذي يتم عنده إيقاف السائق.</p>
                                            <div className="relative z-10 flex items-center">
                                                <input
                                                    id="min-wallet"
                                                    type="number" value={settings.min_wallet_balance} onChange={(e) => handleChange('min_wallet_balance', Number(e.target.value))}
                                                    className="w-full bg-red-50 border border-red-200 text-red-700 font-black text-2xl rounded-xl px-5 py-4 outline-none focus:bg-white focus:border-red-500 focus:ring-4 focus:ring-red-500/10 transition-all text-center"
                                                    dir="ltr"
                                                />
                                                <span className="absolute left-6 text-red-400 font-bold text-sm pointer-events-none">SAR</span>
                                            </div>
                                        </div>
                                    </div>

                                    {/* Tamara Section */}
                                    <div className="bg-slate-50/50 border border-slate-200 rounded-[2.5rem] p-8">
                                        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                                            <div className="flex items-center gap-5">
                                                <div className="p-4 bg-orange-50 rounded-2xl border border-orange-100">
                                                    <CreditCard size={28} className="text-orange-500" />
                                                </div>
                                                <div>
                                                    <h4 className="text-xl font-black text-slate-800">تمارا | Tamara</h4>
                                                    <p className="text-slate-500 font-medium mt-1 text-sm">السماح للعملاء بتقسيم الفاتورة على 4 دفعات عبر تمارا. يظهر الخيار للعميل عند الطلبات التي تتجاوز 100 ريال.</p>
                                                </div>
                                            </div>
                                            <div className="bg-white p-2 rounded-2xl shadow-sm border border-slate-100 flex items-center gap-3">
                                                <span className="px-3 font-bold text-slate-700 text-sm">{settings.tamara_enabled ? 'مفعّل' : 'معطّل'}</span>
                                                <label className="relative inline-flex items-center cursor-pointer">
                                                    <input type="checkbox" aria-label="تفعيل تمارا" className="sr-only peer" checked={settings.tamara_enabled} onChange={(e) => handleChange('tamara_enabled', e.target.checked)} />
                                                    <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-orange-500"></div>
                                                </label>
                                            </div>
                                        </div>
                                    </div>

                                </div>
                            </div>
                        )}

                        {activeTab === 'notifications' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-orange-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center gap-4">
                                        <div className="p-3 bg-orange-50 text-orange-600 rounded-2xl">
                                            <Bell size={28} strokeWidth={2.5} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-black text-slate-800">توجيه الرسائل والإشعارات</h3>
                                            <p className="text-sm text-slate-500 font-medium mt-1">التحكم في تنبيهات النظام المعززة لتحسين تواصل العملاء والسائقين.</p>
                                        </div>
                                    </div>
                                </div>
                                <div className="p-10">
                                    <div className="space-y-4 max-w-4xl mx-auto">
                                        <NotificationRow 
                                            title="رسالة نصية SMS للمستفيد بالفاتورة"
                                            desc="تفعيل إرسال رسالة SMS للعميل تتضمن رابط الفاتورة وحالة الطلب."
                                            checked={settings.sms_on_order}
                                            onChange={(val) => handleChange('sms_on_order', val)}
                                            icon={<Smartphone className="text-[#006FBA]" />}
                                            colorTheme="blue"
                                        />
                                        <NotificationRow 
                                            title="إشعار Push للسائقين بالطلبات القريبة"
                                            desc="إرسال تنبيه في الوقت الفعلي للسائقين المتاحين في نفس المنطقة."
                                            checked={settings.push_on_assign}
                                            onChange={(val) => handleChange('push_on_assign', val)}
                                            icon={<Globe className="text-emerald-500" />}
                                            colorTheme="emerald"
                                        />
                                        <NotificationRow 
                                            title="تنبيه Push للعميل للإفادة بالانتهاء"
                                            desc="تحفيز العميل لتقييم الخدمة فور انتهاء السائق من تنفيذها."
                                            checked={settings.push_on_completed}
                                            onChange={(val) => handleChange('push_on_completed', val)}
                                            icon={<CheckCircle2 className="text-orange-500" />}
                                            colorTheme="orange"
                                        />
                                    </div>
                                </div>
                            </div>
                        )}

                        {activeTab === 'coverage' && (
                            <div className="flex flex-col h-full">
                                <div className="px-10 py-8 border-b border-blue-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center justify-between gap-4 flex-wrap">
                                        <div className="flex items-center gap-4">
                                            <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl">
                                                <MapPin size={28} strokeWidth={2.5} />
                                            </div>
                                            <div>
                                                <h3 className="text-2xl font-black text-slate-800">مناطق التغطية التشغيلية</h3>
                                                <p className="text-sm text-slate-500 font-medium mt-1">
                                                    {zones.filter(z => z.enabled).length} محافظة مفعّلة من أصل {zones.length} — التطبيق يقرأ هذه البيانات مباشرةً
                                                </p>
                                            </div>
                                        </div>
                                        <button
                                            type="button"
                                            onClick={() => { setShowAddForm(v => !v); setTimeout(() => zoneNameRef.current?.focus(), 50); }}
                                            className="flex items-center gap-2 px-5 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold rounded-xl transition-all shadow-sm"
                                        >
                                            <Plus size={18} />
                                            إضافة محافظة
                                        </button>
                                    </div>
                                </div>

                                <div className="p-8 space-y-6 overflow-y-auto">
                                    {/* Add zone form */}
                                    {showAddForm && (
                                        <div className="bg-blue-50 border-2 border-blue-200 rounded-[2rem] p-6 space-y-4">
                                            <h4 className="font-black text-slate-800 text-lg">بيانات المحافظة الجديدة</h4>
                                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">اسم المحافظة أو القرية</label>
                                                    <input
                                                        ref={zoneNameRef}
                                                        type="text"
                                                        value={newZone.name}
                                                        onChange={e => setNewZone(p => ({ ...p, name: e.target.value }))}
                                                        placeholder="مثال: الدائر، فيفاء، بني مالك..."
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all"
                                                        dir="rtl"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">نطاق التغطية (كيلومتر)</label>
                                                    <input
                                                        type="number"
                                                        value={newZone.radiusKm}
                                                        onChange={e => setNewZone(p => ({ ...p, radiusKm: e.target.value }))}
                                                        placeholder="15"
                                                        min="1" max="100"
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all"
                                                        dir="ltr"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">خط العرض (Latitude)</label>
                                                    <input
                                                        type="number"
                                                        value={newZone.latitude}
                                                        onChange={e => setNewZone(p => ({ ...p, latitude: e.target.value }))}
                                                        placeholder="مثال: 17.3453"
                                                        step="0.0001"
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all"
                                                        dir="ltr"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">خط الطول (Longitude)</label>
                                                    <input
                                                        type="number"
                                                        value={newZone.longitude}
                                                        onChange={e => setNewZone(p => ({ ...p, longitude: e.target.value }))}
                                                        placeholder="مثال: 43.1572"
                                                        step="0.0001"
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all"
                                                        dir="ltr"
                                                    />
                                                </div>
                                            </div>
                                            {/* (تكافؤ التطبيق) خريطة تفاعلية: نقرة تحدّد المركز وتملأ الإحداثيات، والدائرة تتبع النطاق */}
                                            <div>
                                                <label className="block text-xs font-bold text-slate-600 mb-1">
                                                    اضغط على الخريطة لتحديد مركز المحافظة — الدائرة تعرض نطاق التغطية
                                                </label>
                                                <div
                                                    ref={zoneMapContainer}
                                                    className="w-full h-72 rounded-2xl overflow-hidden border-2 border-blue-200"
                                                />
                                            </div>

                                            <div className="flex items-center gap-3 flex-wrap">
                                                <a
                                                    href={`https://www.google.com/maps/search/${encodeURIComponent(newZone.name || 'جازان')}`}
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    className="flex items-center gap-2 text-sm font-bold text-[#006FBA] hover:text-[#00578F] underline"
                                                >
                                                    <Navigation size={14} />
                                                    ابحث في خرائط Google عن الإحداثيات
                                                </a>
                                                <span className="text-xs text-slate-400">(انقر على الموقع → انسخ الأرقام من شريط العنوان)</span>
                                            </div>

                                            {/* ═══ التسعير — تكافؤ كامل مع حوار التطبيق ═══ */}
                                            {zones.length > 0 && (
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">نسخ الأسعار من محافظة سابقة (اختياري)</label>
                                                    <select
                                                        defaultValue=""
                                                        onChange={e => { handleCopyPricesFrom(e.target.value); e.target.value = ''; }}
                                                        className={zoneInputCls}
                                                        dir="rtl"
                                                    >
                                                        <option value="">— اختر محافظة لنسخ أسعارها —</option>
                                                        {zones.map(z => <option key={z.id} value={z.id}>{z.name}</option>)}
                                                    </select>
                                                </div>
                                            )}

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-1">أسعار النظافة بالساعة (ر.س)</h5>
                                                <p className="text-xs text-slate-400 mb-2">اترك الحقل فارغاً (أو 0) لتعطيل الشريحة — لا تُباع ساعة غير مسعّرة.</p>
                                                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                                                    {ZONE_HOUR_OPTIONS.map(h => (
                                                        <div key={h}>
                                                            <label className="block text-xs font-bold text-slate-600 mb-1">{hourLabel(h)}</label>
                                                            <input
                                                                type="number" dir="ltr" min="0" step="0.5"
                                                                value={newZone.hourPrices[String(h)]}
                                                                onChange={e => setNewZone(p => ({ ...p, hourPrices: { ...p.hourPrices, [String(h)]: e.target.value } }))}
                                                                className={zoneInputCls}
                                                            />
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-2">أسعار الكنب (بالمتر الطولي) والسجاد (بالمتر المربع)</h5>
                                                <div className="grid grid-cols-2 gap-3">
                                                    {SOFA_RUG_FIELDS.map(f => (
                                                        <div key={f.key}>
                                                            <label className="block text-xs font-bold text-slate-600 mb-1">{f.label}</label>
                                                            <input
                                                                type="number" dir="ltr" min="0" step="0.5"
                                                                value={newZone[f.key]}
                                                                onChange={e => setNewZone(p => ({ ...p, [f.key]: e.target.value }))}
                                                                className={zoneInputCls}
                                                            />
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-2">أسعار المكيفات — لكل مكيف (ر.س)</h5>
                                                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                                                    {AC_FIELDS.map(f => (
                                                        <div key={f.key}>
                                                            <label className="block text-xs font-bold text-slate-600 mb-1">{f.label}</label>
                                                            <input
                                                                type="number" dir="ltr" min="0" step="0.5"
                                                                value={newZone[f.key]}
                                                                onChange={e => setNewZone(p => ({ ...p, [f.key]: e.target.value }))}
                                                                className={zoneInputCls}
                                                            />
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-2">تنظيف داخلية السيارة — لكل سيارة (ر.س)</h5>
                                                <div className="grid grid-cols-3 gap-3">
                                                    {CAR_FIELDS.map(f => (
                                                        <div key={f.key}>
                                                            <label className="block text-xs font-bold text-slate-600 mb-1">{f.label}</label>
                                                            <input
                                                                type="number" dir="ltr" min="0" step="0.5"
                                                                value={newZone[f.key]}
                                                                onChange={e => setNewZone(p => ({ ...p, [f.key]: e.target.value }))}
                                                                className={zoneInputCls}
                                                            />
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>

                                            <div className="flex gap-3">
                                                <button
                                                    type="button"
                                                    onClick={handleAddZone}
                                                    disabled={isAddingZone}
                                                    className="flex items-center gap-2 px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:opacity-60 text-white font-bold rounded-xl transition-all"
                                                >
                                                    {isAddingZone ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />}
                                                    حفظ المحافظة
                                                </button>
                                                <button type="button" onClick={() => setShowAddForm(false)} className="px-6 py-3 border border-slate-200 text-slate-600 font-bold rounded-xl hover:bg-slate-50 transition-all">
                                                    إلغاء
                                                </button>
                                            </div>
                                        </div>
                                    )}

                                    {/* Zones list */}
                                    {zones.length === 0 ? (
                                        <div className="flex flex-col items-center justify-center py-20 text-slate-400">
                                            <MapPin size={56} className="mb-4 opacity-20" />
                                            <p className="font-black text-xl">لا توجد مناطق بعد</p>
                                            <p className="text-sm mt-2">سيتم تحميل المناطق الافتراضية تلقائياً عند فتح التطبيق لأول مرة</p>
                                        </div>
                                    ) : (
                                        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                                            {zones.map(zone => (
                                                <div
                                                    key={zone.id}
                                                    className={`relative group p-5 rounded-2xl border-2 transition-all ${zone.enabled ? 'bg-white border-blue-200 shadow-sm shadow-blue-500/5' : 'bg-slate-50 border-slate-200 opacity-60'}`}
                                                >
                                                    <div className="flex items-start justify-between gap-2">
                                                        <div className="flex items-center gap-3">
                                                            <div className={`w-11 h-11 rounded-xl flex items-center justify-center font-black text-lg ${zone.enabled ? 'bg-blue-100 text-blue-700' : 'bg-slate-200 text-slate-500'}`}>
                                                                {zone.name.charAt(0)}
                                                            </div>
                                                            <div>
                                                                <p className="font-black text-slate-800">{zone.name}</p>
                                                                <p className="text-xs text-slate-500 font-mono mt-0.5">{zone.radiusKm} كم</p>
                                                            </div>
                                                        </div>
                                                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                                            <button
                                                                type="button"
                                                                onClick={() => handleToggleZone(zone)}
                                                                className={`p-1.5 rounded-lg transition-all ${zone.enabled ? 'text-blue-600 hover:bg-blue-50' : 'text-slate-400 hover:bg-slate-100'}`}
                                                                title={zone.enabled ? 'إيقاف' : 'تفعيل'}
                                                            >
                                                                {zone.enabled ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() => handleDeleteZone(zone)}
                                                                className="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 transition-all"
                                                                title="حذف"
                                                            >
                                                                <Trash2 size={16} />
                                                            </button>
                                                        </div>
                                                    </div>
                                                    <div className="mt-3 flex gap-2 text-xs font-mono text-slate-400">
                                                        <span>ع: {zone.latitude?.toFixed(4)}</span>
                                                        <span>·</span>
                                                        <span>ط: {zone.longitude?.toFixed(4)}</span>
                                                    </div>
                                                    <div className={`mt-2 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold ${zone.enabled ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-200 text-slate-500'}`}>
                                                        <span className={`w-1.5 h-1.5 rounded-full ${zone.enabled ? 'bg-emerald-500' : 'bg-slate-400'}`}></span>
                                                        {zone.enabled ? 'مفعّل' : 'موقوف'}
                                                    </div>
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                </div>
                            </div>
                        )}
                        
                    </div>
                </div>
            </div>
        </div>
    );
}

// Helper Components
function SettingsIcon({ activeTab }: { activeTab: TabType }) {
    switch (activeTab) {
        case 'general': return <Shield size={32} className="text-[#006FBA]" strokeWidth={2} />;
        case 'payments': return <Wallet size={32} className="text-emerald-500" strokeWidth={2} />;
        case 'notifications': return <Bell size={32} className="text-orange-500" strokeWidth={2} />;
        case 'coverage': return <MapPin size={32} className="text-blue-600" strokeWidth={2} />;
        default: return <Shield size={32} className="text-[#006FBA]" strokeWidth={2} />;
    }
}

function NotificationRow({ title, desc, checked, onChange, icon, colorTheme }: { title: string, desc: string, checked: boolean, onChange: (val: boolean) => void, icon: React.ReactNode, colorTheme: string }) {
    return (
        <div className={`flex flex-col sm:flex-row items-start sm:items-center justify-between p-6 bg-white border-2 rounded-3xl transition-all duration-300 ${checked ? `border-${colorTheme}-200 shadow-lg shadow-${colorTheme}-500/5` : 'border-slate-100 hover:border-slate-200'} group`}>
            <div className="flex items-center gap-5 pr-2">
                <div className={`p-4 rounded-2xl bg-slate-50 border border-slate-100 group-hover:bg-white group-hover:shadow-sm transition-all`}>
                    {icon}
                </div>
                <div>
                    <h4 className="text-lg font-bold text-slate-800 mb-1">{title}</h4>
                    <p className="text-sm font-medium text-slate-500 leading-relaxed max-w-lg">{desc}</p>
                </div>
            </div>
            <div className="mt-4 sm:mt-0 mr-14 sm:mr-0 pl-2">
                <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" aria-label={title} className="sr-only peer" checked={checked} onChange={(e) => onChange(e.target.checked)} />
                    <div className={`w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-${colorTheme}-500`}></div>
                </label>
            </div>
        </div>
    );
}

