import { useState, useEffect, useRef } from 'react';
import { Save, Shield, Wallet, MapPin, Search, Smartphone, Loader2, CheckCircle2, ChevronLeft, CreditCard, Activity, Database, KeyRound, ArrowRight, Plus, Navigation, ToggleLeft, ToggleRight, Trash2, Pencil, CalendarClock, Copy } from 'lucide-react';
import { doc, getDoc, setDoc, collection, addDoc, updateDoc, deleteDoc, onSnapshot, query, orderBy, GeoPoint, serverTimestamp, writeBatch } from 'firebase/firestore';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { db } from '../services/firebase.ts';
import { useNotification } from '../components/notificationContext.ts';
import { logAudit, AUDIT } from '../services/audit.ts';
import ZoneScheduleEditor from '../components/ZoneScheduleEditor.tsx';
import { type ZoneSchedule } from '../utils/zoneSchedule.ts';
import { arabizeMapLabels } from '../utils/mapboxArabic.ts';
import { JAZAN_BBOX, jazanMaskGeoJSON, jazanOutlineGeoJSON, isInJazan } from '../utils/jazanBoundary.ts';

interface SystemSettings {
    // General
    terms_url: string;
    support_url: string;
    privacy_policy: string;
    maintenance_mode: boolean;

    // Payments — أزيلت vat_rate/min_wallet_balance ومفاتيح الإشعارات الثلاثة:
    // لا قارئ لها في التطبيق أو الدوال (الضريبة مثبّتة 15% في functions/pricing.js)،
    // فكان الأدمن «يحفظها بنجاح» بلا أي أثر تشغيلي. tamara_enabled حيّ فعلاً
    // (payment_summary_screen / store_payment_screen).
    commission_rate: number;
    tamara_enabled: boolean;
}

interface CoverageZone {
    id: string;
    name: string;
    latitude: number;
    longitude: number;
    radiusKm: number;
    enabled: boolean;
    rank: number;
    // (تسعير القرى والوعورة — تكافؤ مع حوار التطبيق) المحافظة الأم وطبيعة التضاريس
    // ورسوم الوعورة % فوق الأساس قبل الضريبة — يقرؤها التسعير الخادمي وشاشة الدفع.
    governorate?: string;
    terrain?: string;
    terrainSurchargePercent?: number;
}

// (تكافؤ مع تطبيق الأدمن — admin_hourly_zones_screen.dart) نفس حقول التسعير حرفياً:
// sofaSqmPrice / rugSqmPrice / ac*Price / car*Price — وهي الحقول الموثوقة التي يقرؤها
// التسعير الخادمي (functions/pricing.js). أسعار الساعات (prices) حُذفت من النموذج
// بطلب المالك — النظافة المنزلية صارت «باقات السكن»؛ الحفظ لا يكتب prices إطلاقاً
// فلا يمسّ ما لدى المحافظات القائمة (تقرؤه النسخ القديمة وزيارات العقود فقط).

// (باقات السكن — النظافة بالساعة الجديدة) نفس مخطط تطبيق الأدمن حرفياً:
// packages[type] = { desc, durationHours, crews: { '1..4': {price, enabled} } }.
// السعر أساس قبل الضريبة ويشمل كامل الكوادر؛ المعطَّل/الصفر لا يظهر للعميل.
const HOME_TYPES = [
    { key: 'small', label: 'شقة صغيرة', desc: '4 غرف + دورتا مياه', dur: 4 },
    { key: 'medium', label: 'شقة متوسطة', desc: '6 غرف + 3 دورات مياه', dur: 6 },
    // (ملاحظة العميل 2026-08-01) «فيلا أو دور» بلا كلمة «كامل».
    { key: 'villa', label: 'فيلا أو دور', desc: 'جميع الغرف ودورات المياه', dur: 8 },
] as const;
const CREW_LABELS: Record<string, string> = { '1': 'كادر واحد', '2': 'كادران', '3': '3 كوادر', '4': '4 كوادر' };
type PkgCrewForm = { price: string; enabled: boolean };
type PkgForm = { desc: string; dur: string; crews: Record<string, PkgCrewForm> };
const emptyPackagesForm = (): Record<string, PkgForm> => Object.fromEntries(
    HOME_TYPES.map(t => [t.key, {
        desc: t.desc, dur: String(t.dur),
        crews: Object.fromEntries(['1', '2', '3', '4'].map(n => [n, { price: '', enabled: false }])),
    }]));

const emptyZoneForm = {
    name: '', latitude: '', longitude: '', radiusKm: '15',
    governorate: '', terrain: '', terrainSurchargePercent: '',
    // تُبذر بنفس افتراضيات التطبيق (service_pricing_defaults.dart).
    sofaSqmPrice: '35', rugSqmPrice: '15',
    acMaintWindowPrice: '100', acMaintSplitPrice: '150',
    acWashWindowPrice: '80', acWashSplitPrice: '120',
    carSmallPrice: '100', carMediumPrice: '150', carLargePrice: '200',
    // (عاملات المناسبات) سعر ساعة العاملة قبل الضريبة — بلا افتراضي: الفراغ/الصفر
    // = الخدمة غير مسعّرة ⇒ لا تظهر للعميل في هذه المنطقة.
    eventWorkerHourPrice: '',
    packages: emptyPackagesForm(),
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

const zoneInputCls = 'w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all';

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
    tamara_enabled: false,
};

type TabType = 'general' | 'payments' | 'coverage';

export default function Settings({ role }: { role?: string | null }) {
    const { toast } = useNotification();
    // مدير العمليات يملك «نطاق التغطية» وحده: firestore.rules تسمح له بـservice_zones
    // وتمنعه عن system_configs — فإظهار «عام وأمان» و«المدفوعات» له يعني أزراراً
    // ترفضها القواعد دائماً. نفتح له التبويب المسموح مباشرةً.
    const zonesOnly = role === 'orders_manager';
    // نشر الأسعار على محافظات مختارة (نظير «تطبيق على مناطق…» في التطبيق).
    const [showApplyPicker, setShowApplyPicker] = useState(false);
    const [applyTargets, setApplyTargets] = useState<string[]>([]);
    const [isApplying, setIsApplying] = useState(false);
    // جدول ساعات المحافظة. null = لم يُلمَس المحرّر ⇒ **لا نكتب schedule إطلاقاً**،
    // فحفظُ سعرٍ عابر لا يُعيد كتابة جدول بلقطة قديمة (نفس الخلل الذي أُصلح في التطبيق).
    const [scheduleDraft, setScheduleDraft] = useState<ZoneSchedule | null>(null);
    const [scheduleInitial, setScheduleInitial] = useState<unknown>(undefined);
    const [activeTab, setActiveTab] = useState<TabType>(zonesOnly ? 'coverage' : 'general');
    const [settings, setSettings] = useState<SystemSettings>(defaultSettings);
    const [appUpdate, setAppUpdate] = useState<AppUpdateConfig>(defaultAppUpdate);
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [saveSuccess, setSaveSuccess] = useState(false);
    const [zones, setZones] = useState<CoverageZone[]>([]);
    const [newZone, setNewZone] = useState(emptyZoneForm);
    const [isAddingZone, setIsAddingZone] = useState(false);
    const [showAddForm, setShowAddForm] = useState(false);
    // تعديل محافظة قائمة: النموذج نفسه يُعبَّأ من مستندها ويُحفَظ بـ updateDoc —
    // كانت اللوحة تضيف فقط، وأي تصحيح سعر/موقع يستلزم فتح تطبيق الأدمن.
    const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
    const [editingZoneName, setEditingZoneName] = useState('');
    // هدف الحذف الجاري تأكيده — يفتح نافذة تأكيد داخلية بدل window.confirm.
    const [deleteTarget, setDeleteTarget] = useState<CoverageZone | null>(null);
    const [isDeletingZone, setIsDeletingZone] = useState(false);
    // الطاقة الاستيعابية اليومية (سقف الطلبات المجدولة) — يقرؤها العميل والخادم
    // من system_configs/hourly_settings؛ كانت تُضبط من التطبيق فقط.
    const [maxOrdersPerDay, setMaxOrdersPerDay] = useState('');
    const [isSavingCapacity, setIsSavingCapacity] = useState(false);
    // true فقط عند فشل قراءة الإعدادات (لا عند غيابها لأول مرة) — يمنع الحفظ فوق
    // الإعدادات الإنتاجية بالقيم الافتراضية المعروضة بعد قراءة فاشلة.
    const [loadFailed, setLoadFailed] = useState(false);
    const zoneNameRef = useRef<HTMLInputElement>(null);

    // (تكافؤ التطبيق) خريطة اختيار مركز المحافظة: نقرة تحدّد المركز، والدائرة تتبع النطاق.
    const zoneMapContainer = useRef<HTMLDivElement>(null);
    const zoneMap = useRef<mapboxgl.Map | null>(null);
    const zoneMarker = useRef<mapboxgl.Marker | null>(null);
    // مرآة للنموذج تقرؤها معالِجات الخريطة (load/click) دون أسر state قديم.
    // التحديث في أثر لا أثناء الرندر: الكتابة على ref أثناء الرندر غير آمنة في
    // الرندر المتزامن (قد يُلغى الرندر أو يُعاد تشغيله). معالِجات الخريطة لا
    // تعمل إلا بعد التركيب، فتقرأ القيمة المحدَّثة دائماً.
    const newZoneRef = useRef(newZone);
    useEffect(() => { newZoneRef.current = newZone; }, [newZone]);

    useEffect(() => {
        const fetchSettings = async () => {
            try {
                const docRef = doc(db, 'system_configs', 'main_settings');
                const updRef = doc(db, 'system_configs', 'app_update');
                const capRef = doc(db, 'system_configs', 'hourly_settings');
                const [docSnap, updSnap, capSnap] = await Promise.all([getDoc(docRef), getDoc(updRef), getDoc(capRef)]);
                if (docSnap.exists()) {
                    setSettings({ ...defaultSettings, ...docSnap.data() } as SystemSettings);
                }
                if (updSnap.exists()) {
                    setAppUpdate({ ...defaultAppUpdate, ...updSnap.data() } as AppUpdateConfig);
                }
                const cap = capSnap.exists() ? capSnap.data().max_orders_per_day : undefined;
                if (typeof cap === 'number' && cap > 0) setMaxOrdersPerDay(String(cap));
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
                    governorate: data.governorate || '',
                    terrain: data.terrain || '',
                    terrainSurchargePercent: Number(data.terrain_surcharge_percent) || 0,
                } as CoverageZone;
            }));
        }, (err) => {
            // فشل المستمع = قائمة متجمدة: يحذف الأدمن بنجاح والبطاقة لا تختفي فيظن
            // الزر معطّلاً. نُظهر الخطأ صراحةً بدل الصمت.
            console.error('service_zones snapshot error:', err);
            toast.error('انقطع تحديث قائمة المحافظات — أعد تحميل الصفحة');
        });
        return () => unsub();
        // eslint-disable-next-line react-hooks/exhaustive-deps
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
            zoneMarker.current = new mapboxgl.Marker({ color: '#660033' }).setLngLat([lng, lat]).addTo(m);
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
            m.addLayer({ id: 'jazan-outline-line', type: 'line', source: 'jazan-outline', paint: { 'line-color': '#660033', 'line-width': 2.5 } });
            m.addSource('zone-circle', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] },
            });
            m.addLayer({ id: 'zone-circle-fill', type: 'fill', source: 'zone-circle', paint: { 'fill-color': '#660033', 'fill-opacity': 0.15 } });
            m.addLayer({ id: 'zone-circle-line', type: 'line', source: 'zone-circle', paint: { 'line-color': '#660033', 'line-width': 2 } });
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
        // النقر على الخريطة محروس بـisInJazan، أما حقلا الإحداثيات اليدويان فلا —
        // فكان رقمٌ مكتوب بالخطأ يُنشئ محافظة خارج جازان تماماً، ولا يكتشفها أحد
        // إلا حين يُتَّهم موقع عميلة صحيح بأنه «خارج نطاق خدماتنا».
        if (!isInJazan(lat, lng)) {
            toast.error('الإحداثيات خارج منطقة جازان — حدّد الموقع من الخريطة');
            return;
        }
        // الحدّان في وسم input لا يُفعَّلان أصلاً: الزرّ type="button" فلا يمرّ بتحقّق
        // النموذج — فكان نصف قطر 0 أو سالب أو 500كم يُحفظ كما هو.
        if (radius < 1 || radius > 100) {
            toast.error('نصف القطر يجب أن يكون بين 1 و100 كم');
            return;
        }
        // رسوم الوعورة: فارغ = 0، وإلا رقم بين 0 و100 (نفس حارس حوار التطبيق).
        const terrainPct = newZone.terrainSurchargePercent.trim() === '' ? 0 : parseFloat(newZone.terrainSurchargePercent);
        if (isNaN(terrainPct) || terrainPct < 0 || terrainPct > 100) {
            toast.error('رسوم الوعورة يجب أن تكون بين 0 و100%');
            return;
        }
        setIsAddingZone(true);
        try {
            // نفس مخطط حفظ تطبيق الأدمن حرفياً — التسعير الخادمي يقرأ هذه الحقول.
            // فارغ/غير رقمي = 0 = «غير مسعّرة» فتُعطَّل الخدمة/الشريحة بدل بيعها بسعر لم يُعتمد.
            const num = (s: string) => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
            const payload = {
                name: newZone.name.trim(),
                centerLoc: new GeoPoint(lat, lng),
                radiusKm: radius,
                // (تسعير القرى والوعورة) نفس مفاتيح حوار التطبيق حرفياً.
                governorate: newZone.governorate.trim(),
                terrain: newZone.terrain,
                terrain_surcharge_percent: terrainPct,
                sofaSqmPrice: num(newZone.sofaSqmPrice),
                rugSqmPrice: num(newZone.rugSqmPrice),
                acMaintWindowPrice: num(newZone.acMaintWindowPrice),
                acMaintSplitPrice: num(newZone.acMaintSplitPrice),
                acWashWindowPrice: num(newZone.acWashWindowPrice),
                acWashSplitPrice: num(newZone.acWashSplitPrice),
                carSmallPrice: num(newZone.carSmallPrice),
                carMediumPrice: num(newZone.carMediumPrice),
                carLargePrice: num(newZone.carLargePrice),
                eventWorkerHourPrice: num(newZone.eventWorkerHourPrice),
                // (باقات السكن) نفس مخطط تطبيق الأدمن حرفياً — يقرؤه العميل
                // ويتحقق منه التسعير الخادمي (functions/pricing.js).
                packages: buildPackagesPayload(),
                // جدول الساعات — يُكتب **فقط** إن لمس الأدمن المحرّر فعلاً.
                ...(scheduleDraft ? { schedule: scheduleDraft } : {}),
                updated_at: serverTimestamp(),
            };
            if (editingZoneId) {
                // تحديث الحقول المعروضة فقط — schedule/enabled/rank لا تُلمَس فلا يُمسح
                // جدول دوام المحافظة أو ترتيبها بحفظ تعديل سعر.
                await updateDoc(doc(db, 'service_zones', editingZoneId), payload);
                await logAudit(AUDIT.UPDATE_ZONE, { name: payload.name }, editingZoneId);
                toast.success(`تم تحديث ${payload.name} بنجاح`);
            } else {
                // منطقة جديدة تُذيَّل القائمة (أعلى rank + 1) — تكافؤ حقيقي مع تطبيق
                // الأدمن: zones.length + 1 كانت تكرّر رتبة قائمة بعد أي حذف
                // (رتب {1,3,4} ⇒ الطول+1 = 4 مكرّرة) فيتذبذب ترتيب القوائم.
                const nextRank = zones.reduce((m, z) => Math.max(m, z.rank || 0), 0) + 1;
                const ref = await addDoc(collection(db, 'service_zones'), { ...payload, enabled: true, rank: nextRank });
                await logAudit(AUDIT.CREATE_ZONE, { name: payload.name }, ref.id);
                toast.success(`تمت إضافة ${payload.name} بنجاح`);
            }
            setNewZone(emptyZoneForm);
            setShowAddForm(false);
            setEditingZoneId(null);
            setEditingZoneName('');
        } catch (e) {
            console.error(e);
            toast.error(editingZoneId ? 'حدث خطأ أثناء التحديث' : 'حدث خطأ أثناء الإضافة');
        } finally {
            setIsAddingZone(false);
        }
    };

    // فتح النموذج مُعبّأً من مستند المحافظة كاملاً (الاسم/الموقع/الأسعار/الباقات) للتعديل.
    const handleEditZone = async (zone: CoverageZone) => {
        try {
            const snap = await getDoc(doc(db, 'service_zones', zone.id));
            if (!snap.exists()) { toast.error('المحافظة لم تعد موجودة'); return; }
            const d = snap.data() as Record<string, unknown>;
            const s = (v: unknown) => (v === undefined || v === null ? '' : String(v));
            const srcPkgs = (d.packages ?? {}) as Record<string, {
                desc?: string; durationHours?: number;
                crews?: Record<string, { price?: number; enabled?: boolean }>;
            }>;
            const packages: Record<string, PkgForm> = Object.fromEntries(
                HOME_TYPES.map(t => {
                    const sp = srcPkgs[t.key] ?? {};
                    const crews = sp.crews ?? {};
                    return [t.key, {
                        desc: (sp.desc ?? '').trim() || t.desc,
                        dur: String(sp.durationHours ?? t.dur),
                        crews: Object.fromEntries(['1', '2', '3', '4'].map(n => [n, {
                            price: s(crews[n]?.price),
                            enabled: crews[n]?.enabled === true,
                        }])),
                    }];
                }));
            setNewZone({
                name: s(d.name),
                latitude: zone.latitude ? zone.latitude.toFixed(5) : '',
                longitude: zone.longitude ? zone.longitude.toFixed(5) : '',
                radiusKm: s(d.radiusKm) || '15',
                governorate: s(d.governorate), terrain: s(d.terrain),
                terrainSurchargePercent: Number(d.terrain_surcharge_percent) > 0 ? s(d.terrain_surcharge_percent) : '',
                sofaSqmPrice: s(d.sofaSqmPrice), rugSqmPrice: s(d.rugSqmPrice),
                acMaintWindowPrice: s(d.acMaintWindowPrice), acMaintSplitPrice: s(d.acMaintSplitPrice),
                acWashWindowPrice: s(d.acWashWindowPrice), acWashSplitPrice: s(d.acWashSplitPrice),
                carSmallPrice: s(d.carSmallPrice), carMediumPrice: s(d.carMediumPrice), carLargePrice: s(d.carLargePrice),
                eventWorkerHourPrice: s(d.eventWorkerHourPrice),
                packages,
            });
            // الجدول القائم يُعرض في المحرّر، والمسوّدة تبقى null حتى يُلمَس فعلاً.
            setScheduleInitial(d.schedule);
            setScheduleDraft(null);
            setEditingZoneId(zone.id);
            setEditingZoneName(s(d.name));
            setShowAddForm(true);
            setTimeout(() => zoneNameRef.current?.focus(), 50);
        } catch (e) {
            console.error(e);
            toast.error('تعذّر تحميل بيانات المحافظة');
        }
    };

    // سقف الطلبات اليومي — merge حتى لا تُمسح بقية إعدادات hourly_settings.
    // مخطط الباقات — مصدر واحد يستعمله الحفظ المفرد ونشر الأسعار على محافظات معاً،
    // فلا ينحرف أحدهما عن الآخر.
    const buildPackagesPayload = () => {
        const num = (s: string) => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
        return Object.fromEntries(HOME_TYPES.map(t => {
            const p = newZone.packages[t.key];
            return [t.key, {
                desc: p.desc.trim() || t.desc,
                // تثبيت 1..12 — سالب مكتوب يتجاوز min/max في HTML.
                durationHours: Math.min(12, Math.max(1, parseInt(p.dur) || t.dur)),
                crews: Object.fromEntries(['1', '2', '3', '4'].map(n => {
                    const c = p.crews[n];
                    return [n, { price: num(c.price), enabled: !!c.enabled }];
                })),
            }];
        }));
    };

    // نشر الأسعار على محافظات مختارة — نظير «تطبيق على مناطق…» في تطبيق الأدمن.
    // كان الويب يملك نصف العملية فقط (النسخ **من** محافظة إلى النموذج) بلا نشر
    // **إلى** محافظات، فتغيير سعر في 10 محافظات = فتح وحفظ 10 مرات يدوياً.
    // دفعة واحدة تكتب الأسعار والباقات فقط — لا الاسم ولا الموقع ولا نصف القطر
    // ولا التفعيل ولا الجدول، كي لا يمسح النشرُ خصوصيةَ كل محافظة.
    const handleApplyPricesToZones = async () => {
        const targets = zones.filter(z => applyTargets.includes(z.id));
        if (targets.length === 0) { toast.error('اختر محافظة واحدة على الأقل'); return; }
        setIsApplying(true);
        try {
            const num = (s: string) => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
            const prices = {
                sofaSqmPrice: num(newZone.sofaSqmPrice),
                rugSqmPrice: num(newZone.rugSqmPrice),
                acMaintWindowPrice: num(newZone.acMaintWindowPrice),
                acMaintSplitPrice: num(newZone.acMaintSplitPrice),
                acWashWindowPrice: num(newZone.acWashWindowPrice),
                acWashSplitPrice: num(newZone.acWashSplitPrice),
                carSmallPrice: num(newZone.carSmallPrice),
                carMediumPrice: num(newZone.carMediumPrice),
                carLargePrice: num(newZone.carLargePrice),
                eventWorkerHourPrice: num(newZone.eventWorkerHourPrice),
                packages: buildPackagesPayload(),
                updated_at: serverTimestamp(),
            };
            const batch = writeBatch(db);
            for (const z of targets) batch.update(doc(db, 'service_zones', z.id), prices);
            await batch.commit();
            await logAudit(AUDIT.APPLY_PRICES_TO_ZONES,
                { count: targets.length, zones: targets.map(z => z.name) });
            toast.success(`طُبِّقت الأسعار على ${targets.length} محافظة`);
            setApplyTargets([]);
            setShowApplyPicker(false);
        } catch (e) {
            console.error(e);
            toast.error('تعذّر تطبيق الأسعار');
        } finally {
            setIsApplying(false);
        }
    };

    const handleSaveCapacity = async () => {
        const n = parseInt(maxOrdersPerDay);
        if (isNaN(n) || n < 1) { toast.error('أدخل رقماً صحيحاً (1 فأكثر)'); return; }
        setIsSavingCapacity(true);
        try {
            await setDoc(doc(db, 'system_configs', 'hourly_settings'),
                { max_orders_per_day: n, updated_at: serverTimestamp() }, { merge: true });
            toast.success(`تم الحفظ — سقف الطلبات اليومي: ${n}`);
        } catch (e) {
            console.error(e);
            toast.error('تعذّر حفظ الطاقة الاستيعابية');
        } finally {
            setIsSavingCapacity(false);
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
            const s = (v: unknown) => (v === undefined || v === null ? '' : String(v));
            // (باقات السكن) تعبئة من المنطقة المصدر — أسعار وتفعيلات ومدد.
            const srcPkgs = (d.packages ?? {}) as Record<string, {
                desc?: string; durationHours?: number;
                crews?: Record<string, { price?: number; enabled?: boolean }>;
            }>;
            const packages: Record<string, PkgForm> = Object.fromEntries(
                HOME_TYPES.map(t => {
                    const sp = srcPkgs[t.key] ?? {};
                    const crews = sp.crews ?? {};
                    return [t.key, {
                        desc: (sp.desc ?? '').trim() || t.desc,
                        dur: String(sp.durationHours ?? t.dur),
                        crews: Object.fromEntries(['1', '2', '3', '4'].map(n => [n, {
                            price: s(crews[n]?.price),
                            enabled: crews[n]?.enabled === true,
                        }])),
                    }];
                }));
            setNewZone(prev => ({
                ...prev,
                sofaSqmPrice: s(d.sofaSqmPrice), rugSqmPrice: s(d.rugSqmPrice),
                acMaintWindowPrice: s(d.acMaintWindowPrice), acMaintSplitPrice: s(d.acMaintSplitPrice),
                acWashWindowPrice: s(d.acWashWindowPrice), acWashSplitPrice: s(d.acWashSplitPrice),
                carSmallPrice: s(d.carSmallPrice), carMediumPrice: s(d.carMediumPrice), carLargePrice: s(d.carLargePrice),
                eventWorkerHourPrice: s(d.eventWorkerHourPrice),
                packages,
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
            await logAudit(AUDIT.TOGGLE_SERVICE_STATUS,
                { name: zone.name, enabled: !zone.enabled }, zone.id);
        } catch (e) {
            console.error('toggle zone failed:', e);
            toast.error('حدث خطأ أثناء التحديث');
        }
    };

    // التأكيد بنافذة داخلية (deleteTarget) لا window.confirm: المتصفح قد يكبتها
    // بصمت («منع هذه الصفحة من إظهار مربعات حوار») فيبدو زر الحذف معطّلاً بلا أي
    // خطأ — وهو ما اشتكى منه المالك. النجاح يظهر بتوست صريح لا بمجرد اختفاء البطاقة.
    const handleConfirmDeleteZone = async () => {
        const zone = deleteTarget;
        if (!zone) return;
        setIsDeletingZone(true);
        try {
            await deleteDoc(doc(db, 'service_zones', zone.id));
            await logAudit(AUDIT.DELETE_ZONE, { name: zone.name }, zone.id);
            toast.success(`تم حذف «${zone.name}» نهائياً`);
            setDeleteTarget(null);
        } catch (e) {
            console.error(e);
            toast.error(`تعذّر حذف «${zone.name}»: ${e instanceof Error ? e.message : e}`);
        } finally {
            setIsDeletingZone(false);
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
                    <div className="absolute inset-0 rounded-full border-t-4 border-[#660033] animate-spin"></div>
                    <div className="absolute inset-2 rounded-full border-t-4 border-lime-500 animate-spin opacity-50 animation-delay-150"></div>
                </div>
                <div className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-[#660033] to-lime-600 animate-pulse">
                    تهيئة الإعدادات...
                </div>
            </div>
        );
    }

    const allTabs = [
        { id: 'general', label: 'عام وأمان', icon: Shield, color: 'from-[#660033] to-[#660033]', bg: 'bg-[#FAF1F6]/50', border: 'border-[#F2DEE9]', text: 'text-[#4D0026]' },
        { id: 'payments', label: 'المدفوعات', icon: Wallet, color: 'from-emerald-500 to-green-600', bg: 'bg-emerald-50/50', border: 'border-emerald-100', text: 'text-emerald-700' },
        { id: 'coverage', label: 'التغطية', icon: MapPin, color: 'from-rose-500 to-lime-600', bg: 'bg-rose-50/50', border: 'border-rose-100', text: 'text-rose-700' },
    ] as const;
    const tabs = zonesOnly ? allTabs.filter(t => t.id === 'coverage') : allTabs;

    const currentTabColor = tabs.find(t => t.id === activeTab)?.color || tabs[0].color;

    return (
        <div className="space-y-8 pb-12 animate-in fade-in slide-in-from-bottom-8 duration-700 max-w-7xl mx-auto">
            {/* Header Section */}
            <div className="relative p-8 rounded-[2rem] bg-white border border-slate-100 shadow-[0_8px_30px_rgb(0,0,0,0.04)] overflow-hidden flex flex-col md:flex-row items-center justify-between gap-6 isolation-auto z-0">
                {/* Decorative background blurs */}
                <div className={`absolute top-0 right-0 w-64 h-64 bg-gradient-to-bl ${currentTabColor} rounded-full opacity-[0.05] blur-3xl -translate-y-1/2 translate-x-1/2 transition-colors duration-500`}></div>
                <div className={`absolute bottom-0 left-0 w-80 h-80 bg-gradient-to-tr ${currentTabColor} rounded-full opacity-[0.03] blur-3xl translate-y-1/3 -translate-x-1/3 transition-colors duration-500`}></div>
                
                <div className="relative z-10 flex items-center gap-6">
                    <div className={`w-16 h-16 rounded-2xl bg-gradient-to-br ${currentTabColor} p-0.5 shadow-lg shadow-[#8E2B5C]/20 transition-colors duration-500`}>
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
                                : `bg-gradient-to-r ${currentTabColor} shadow-[#8E2B5C]/25 hover:shadow-[#8E2B5C]/40 hover:-translate-y-1 hover:scale-[1.02]`
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
                                    <Search size={18} className="text-slate-400 group-focus-within:text-[#8E2B5C] transition-colors" />
                                </div>
                                <input
                                    type="text"
                                    placeholder="بحث سريع..."
                                    className="w-full bg-slate-50/50 border border-slate-200 text-sm rounded-xl py-3 pr-11 pl-4 outline-none focus:bg-white focus:border-[#a86faa] focus:ring-4 focus:ring-[#8E2B5C]/10 transition-all text-slate-700 font-medium placeholder-slate-400"
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
                    <div className="bg-gradient-to-br from-[#660033] to-[#4D0026] rounded-[2rem] p-6 text-white shadow-xl shadow-[#660033]/20 relative overflow-hidden hidden lg:block">
                        <div className="absolute -right-8 -top-8 w-32 h-32 bg-white opacity-10 rounded-full blur-2xl"></div>
                        <div className="relative z-10">
                            <h3 className="font-bold text-lg mb-2">هل تحتاج مساعدة؟</h3>
                            <p className="text-[#F2DEE9] text-sm mb-4 leading-relaxed font-medium">وثائق النظام تحتوي على تفاصيل كاملة لجميع الإعدادات المبينة هنا.</p>
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
                                        <div className="p-3 bg-[#FAF1F6] text-[#660033] rounded-2xl">
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
                                            <KeyRound size={20} className="text-[#660033]" /> المفاتيح الأمنية السحابية
                                        </h4>
                                        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-[#E5C3D5] group">
                                                <label htmlFor="zatca-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح ZATCA (هيئة الزكاة والدخل)</label>
                                                <div className="relative">
                                                    <input id="zatca-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-[#a86faa] transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => toast.info('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح الزكاة والدخل من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-[#660033] bg-[#FAF1F6] hover:bg-[#660033] hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                            <div className="bg-slate-50 border border-slate-100 rounded-2xl p-6 transition-all hover:shadow-md hover:border-[#E5C3D5] group">
                                                <label htmlFor="firebase-key" className="block text-sm font-bold text-slate-700 mb-3">مفتاح Firebase Admin</label>
                                                <div className="relative">
                                                    <input id="firebase-key" type="password" value="••••••••••••••••••••••••" disabled className="w-full bg-white border border-slate-200 text-slate-400 text-sm rounded-xl px-4 py-3.5 outline-none font-mono tracking-widest cursor-not-allowed group-hover:border-[#a86faa] transition-colors shadow-inner" />
                                                    <button type="button" onClick={() => toast.info('لأسباب أمنية، لا يمكن عرض أو تعديل مفتاح Firebase من هنا. يرجى التواصل مع الإدارة الفنية.')} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-bold text-[#660033] bg-[#FAF1F6] hover:bg-[#660033] hover:text-white px-4 py-2 rounded-lg transition-all shadow-sm">مراجعة</button>
                                                </div>
                                            </div>
                                        </div>
                                    </section>

                                    <div className="w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>

                                    {/* App Versioning & Legal */}
                                    <section>
                                        <h4 className="flex items-center gap-2 text-lg font-bold text-slate-800 mb-6">
                                            <Smartphone size={20} className="text-[#8E2B5C]" /> توافق المتاجر والنصوص القانونية
                                        </h4>
                                        <div className="bg-white border border-slate-200 shadow-sm rounded-[2rem] p-8 relative overflow-hidden">
                                            <div className="absolute top-0 right-0 w-32 h-32 bg-[#FAF1F6] rounded-full blur-3xl -translate-y-10 translate-x-10 pointer-events-none"></div>
                                            
                                            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 relative z-10">
                                                <div className="md:col-span-2 flex flex-col gap-5 p-5 bg-[#FAF1F6]/50 border border-[#F2DEE9]/50 rounded-2xl">
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
                                                                className="w-full md:w-64 bg-white border border-slate-300 focus:border-[#8E2B5C] focus:ring-4 focus:ring-[#8E2B5C]/20 text-slate-800 font-bold text-sm rounded-xl px-5 py-3.5 outline-none transition-all shadow-sm text-left font-mono"
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
                                                                    <div className="w-14 h-7 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all after:shadow-sm peer-checked:bg-[#660033]"></div>
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
                                                            className="w-full bg-white border border-slate-300 focus:border-[#8E2B5C] focus:ring-4 focus:ring-[#8E2B5C]/20 text-slate-800 font-medium text-sm rounded-xl px-5 py-3.5 outline-none transition-all shadow-sm"
                                                            placeholder="يتوفّر إصدار جديد بمزايا وتحسينات مهمة..."
                                                        />
                                                    </div>
                                                </div>

                                                <div className="space-y-2">
                                                    <label htmlFor="terms-url" className="block text-sm font-bold text-slate-700">رابط الشروط والأحكام</label>
                                                    <input
                                                        id="terms-url" type="url" value={settings.terms_url} onChange={(e) => handleChange('terms_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-[#8E2B5C] focus:ring-4 focus:ring-[#8E2B5C]/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/terms"
                                                    />
                                                </div>
                                                <div className="space-y-2">
                                                    <label htmlFor="support-url" className="block text-sm font-bold text-slate-700">رابط الدعم الفني</label>
                                                    <input
                                                        id="support-url" type="url" value={settings.support_url} onChange={(e) => handleChange('support_url', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-3.5 outline-none focus:border-[#8E2B5C] focus:ring-4 focus:ring-[#8E2B5C]/10 transition-all text-left"
                                                        dir="ltr" placeholder="https://example.com/support"
                                                    />
                                                </div>
                                                <div className="md:col-span-2 space-y-2">
                                                    <label htmlFor="privacy-policy" className="block text-sm font-bold text-slate-700">سياسة الخصوصية</label>
                                                    <p className="text-xs text-slate-500 font-medium">تُنشَر للعملاء داخل التطبيق <span className="font-bold">وعلى صفحة <a href="https://zyiarah.com/privacy" target="_blank" rel="noopener noreferrer" className="text-[#660033] underline">zyiarah.com/privacy</a> العامة</span> فور الحفظ. اترك سطراً فارغاً بين الفقرات.</p>
                                                    <textarea
                                                        id="privacy-policy" rows={12} value={settings.privacy_policy} onChange={(e) => handleChange('privacy_policy', e.target.value)}
                                                        className="w-full bg-slate-50 hover:bg-white focus:bg-white border border-slate-200 text-slate-700 text-sm rounded-xl px-5 py-4 outline-none focus:border-[#8E2B5C] focus:ring-4 focus:ring-[#8E2B5C]/10 transition-all resize-y leading-loose"
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

                                    {/* أزيلت بطاقتا VAT والحد الأدنى للمحفظة: حقول ميتة بلا قارئ —
                                        الضريبة مثبّتة 15% خادمياً (functions/pricing.js) وكان تعديلها
                                        هنا «ينجح» بلا أثر، وهو أخطر من غيابه. */}

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

                        {/* أزيل تبويب الإشعارات بمفاتيحه الثلاثة (sms_on_order/push_on_assign/
                            push_on_completed): لا قارئ لها في التطبيق أو الدوال — الإشعارات
                            الفعلية تديرها مُشغّلات functions/index.js بلا هذه الأعلام، فكان
                            «تعطيلها» يوهم الأدمن بأثر لا يحدث. */}

                        {activeTab === 'coverage' && (
                            <div className="flex flex-col h-full">
                                {/* نافذة تأكيد الحذف الداخلية — بديل window.confirm القابل للكبت */}
                                {deleteTarget && (
                                    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
                                        <div className="bg-white rounded-3xl p-6 w-full max-w-sm shadow-2xl" dir="rtl">
                                            <div className="flex items-center gap-3 mb-3">
                                                <div className="p-2.5 bg-red-50 text-red-600 rounded-xl">
                                                    <Trash2 size={20} />
                                                </div>
                                                <h4 className="font-black text-slate-800 text-lg">تأكيد الحذف</h4>
                                            </div>
                                            <p className="text-sm text-slate-600 mb-5">
                                                حذف محافظة <span className="font-black text-slate-800">«{deleteTarget.name}»</span> نهائياً؟
                                                ستختفي أسعارها وباقاتها وجدولها ولن تظهر للعملاء.
                                            </p>
                                            <div className="flex gap-3">
                                                <button
                                                    type="button"
                                                    onClick={handleConfirmDeleteZone}
                                                    disabled={isDeletingZone}
                                                    className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-red-600 hover:bg-red-700 disabled:opacity-60 text-white font-bold rounded-xl transition-all"
                                                >
                                                    {isDeletingZone ? <Loader2 size={16} className="animate-spin" /> : <Trash2 size={16} />}
                                                    حذف نهائياً
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setDeleteTarget(null)}
                                                    disabled={isDeletingZone}
                                                    className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 font-bold rounded-xl hover:bg-slate-50 transition-all"
                                                >
                                                    إلغاء
                                                </button>
                                            </div>
                                        </div>
                                    </div>
                                )}
                                <div className="px-10 py-8 border-b border-rose-50 bg-white/80 backdrop-blur-xl sticky top-0 z-20">
                                    <div className="flex items-center justify-between gap-4 flex-wrap">
                                        <div className="flex items-center gap-4">
                                            <div className="p-3 bg-rose-50 text-rose-600 rounded-2xl">
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
                                            onClick={() => {
                                                // فتح «إضافة» بعد جلسة تعديل يبدأ بنموذج نظيف — لا بقايا محافظة سابقة.
                                                if (!showAddForm && editingZoneId) { setNewZone(emptyZoneForm); setEditingZoneId(null); setEditingZoneName(''); }
                                                setShowAddForm(v => !v);
                                                setTimeout(() => zoneNameRef.current?.focus(), 50);
                                            }}
                                            className="flex items-center gap-2 px-5 py-3 bg-rose-600 hover:bg-rose-700 text-white font-bold rounded-xl transition-all shadow-sm"
                                        >
                                            <Plus size={18} />
                                            إضافة محافظة
                                        </button>
                                    </div>
                                </div>

                                <div className="p-8 space-y-6 overflow-y-auto">
                                    {/* (تكافؤ التطبيق) الطاقة الاستيعابية اليومية — سقف الطلبات المجدولة في اليوم الواحد،
                                        يقرؤه العميل (الإتاحة) والخادم (التحقق) من system_configs/hourly_settings.
                                        مخفيّة عن مدير العمليات: القواعد تقصر كتابة system_configs على الإدارة
                                        العليا (firestore.rules:397)، فزرّ الحفظ كان سيفشل له دائماً. */}
                                    <div className={`bg-white border-2 border-rose-100 rounded-[2rem] p-6 ${zonesOnly ? 'hidden' : ''}`}>
                                        <div className="flex items-center gap-3 mb-3">
                                            <div className="p-2.5 bg-rose-50 text-rose-600 rounded-xl">
                                                <CalendarClock size={20} strokeWidth={2.5} />
                                            </div>
                                            <div>
                                                <h4 className="font-black text-slate-800">الطاقة الاستيعابية اليومية</h4>
                                                <p className="text-xs text-slate-500 font-medium">سقف الطلبات المجدولة في اليوم الواحد — عند بلوغه يظهر اليوم غير متاح للعملاء</p>
                                            </div>
                                        </div>
                                        <div className="flex items-center gap-3 flex-wrap">
                                            <input
                                                type="number" dir="ltr" min="1" step="1"
                                                value={maxOrdersPerDay}
                                                onChange={e => setMaxOrdersPerDay(e.target.value)}
                                                placeholder="مثال: 20"
                                                className="w-40 bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all"
                                            />
                                            <button
                                                type="button"
                                                onClick={handleSaveCapacity}
                                                disabled={isSavingCapacity}
                                                className="flex items-center gap-2 px-5 py-3 bg-rose-600 hover:bg-rose-700 disabled:opacity-60 text-white font-bold rounded-xl transition-all"
                                            >
                                                {isSavingCapacity ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
                                                حفظ السقف
                                            </button>
                                        </div>
                                    </div>

                                    {/* Add zone form */}
                                    {showAddForm && (
                                        <div className="bg-rose-50 border-2 border-rose-200 rounded-[2rem] p-6 space-y-4">
                                            <h4 className="font-black text-slate-800 text-lg">
                                                {editingZoneId ? `تعديل محافظة: ${editingZoneName}` : 'بيانات المحافظة الجديدة'}
                                            </h4>
                                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">اسم المحافظة أو القرية</label>
                                                    <input
                                                        ref={zoneNameRef}
                                                        type="text"
                                                        value={newZone.name}
                                                        onChange={e => setNewZone(p => ({ ...p, name: e.target.value }))}
                                                        placeholder="مثال: الدائر، فيفاء، بني مالك..."
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all"
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
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all"
                                                        dir="ltr"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">المحافظة التابعة لها (اختياري)</label>
                                                    <input
                                                        type="text"
                                                        list="zone-governorates"
                                                        value={newZone.governorate}
                                                        onChange={e => setNewZone(p => ({ ...p, governorate: e.target.value }))}
                                                        placeholder="مثال: الداير بني مالك"
                                                        className={zoneInputCls}
                                                        dir="rtl"
                                                    />
                                                    <datalist id="zone-governorates">
                                                        {[...new Set(zones.map(z => (z.governorate || '').trim()).filter(Boolean))].map(g => (
                                                            <option key={g} value={g} />
                                                        ))}
                                                    </datalist>
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">طبيعة التضاريس</label>
                                                    <select
                                                        value={newZone.terrain}
                                                        onChange={e => setNewZone(p => ({ ...p, terrain: e.target.value }))}
                                                        className={zoneInputCls}
                                                        dir="rtl"
                                                    >
                                                        <option value="">غير محدّدة</option>
                                                        <option value="mountain">مرتفعات جبلية</option>
                                                        <option value="plain">سهلية منبسطة</option>
                                                    </select>
                                                </div>
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">رسوم الوعورة % (اختياري — على الأساس قبل الضريبة، لا على العقود)</label>
                                                    <input
                                                        type="number"
                                                        value={newZone.terrainSurchargePercent}
                                                        onChange={e => setNewZone(p => ({ ...p, terrainSurchargePercent: e.target.value }))}
                                                        placeholder="0"
                                                        min="0" max="100" step="0.5"
                                                        className={zoneInputCls}
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
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all"
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
                                                        className="w-full bg-white border border-slate-200 rounded-xl px-4 py-3 font-bold text-slate-800 outline-none focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 transition-all"
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
                                                    className="w-full h-72 rounded-2xl overflow-hidden border-2 border-rose-200"
                                                />
                                            </div>

                                            <div className="flex items-center gap-3 flex-wrap">
                                                <a
                                                    href={`https://www.google.com/maps/search/${encodeURIComponent(newZone.name || 'جازان')}`}
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    className="flex items-center gap-2 text-sm font-bold text-[#660033] hover:text-[#4D0026] underline"
                                                >
                                                    <Navigation size={14} />
                                                    ابحث في خرائط Google عن الإحداثيات
                                                </a>
                                                <span className="text-xs text-slate-400">(انقر على الموقع → انسخ الأرقام من شريط العنوان)</span>
                                            </div>

                                            {/* ═══ التسعير — تكافؤ كامل مع حوار التطبيق ═══ */}
                                            {zones.some(z => z.id !== editingZoneId) && (
                                                <div>
                                                    <label className="block text-xs font-bold text-slate-600 mb-1">نسخ الأسعار من محافظة سابقة (اختياري)</label>
                                                    <select
                                                        defaultValue=""
                                                        onChange={e => { handleCopyPricesFrom(e.target.value); e.target.value = ''; }}
                                                        className={zoneInputCls}
                                                        dir="rtl"
                                                    >
                                                        <option value="">— اختر محافظة لنسخ أسعارها —</option>
                                                        {/* نستبعد المحافظة قيد التعديل: كانت تظهر في قائمتها
                                                            فيصير الخيار الوحيد «انسخ من نفسك» — يُعيد ملء
                                                            النموذج بالقيم المحفوظة ويُلغي تعديلات لم تُحفظ بعد. */}
                                                        {zones.filter(z => z.id !== editingZoneId)
                                                            .map(z => <option key={z.id} value={z.id}>{z.name}</option>)}
                                                    </select>
                                                </div>
                                            )}

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

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-1">عاملات للمناسبات — لكل عاملة/ساعة (ر.س، قبل الضريبة)</h5>
                                                <p className="text-xs text-slate-400 mb-2">العميل يختار العدد والمدة واليوم والساعة، والسعر = العدد × الساعات × هذا السعر. اتركه فارغاً لتعطيل الخدمة في هذه المحافظة.</p>
                                                <div className="grid grid-cols-3 gap-3">
                                                    <div>
                                                        <label className="block text-xs font-bold text-slate-600 mb-1">سعر ساعة العاملة</label>
                                                        <input
                                                            type="number" dir="ltr" min="0" step="0.5"
                                                            value={newZone.eventWorkerHourPrice}
                                                            onChange={e => setNewZone(p => ({ ...p, eventWorkerHourPrice: e.target.value }))}
                                                            className={zoneInputCls}
                                                        />
                                                    </div>
                                                </div>
                                            </div>

                                            <div>
                                                <h5 className="font-black text-slate-800 text-sm mb-1">باقات السكن — التنظيف المنزلي (ر.س، قبل الضريبة)</h5>
                                                <p className="text-xs text-slate-400 mb-2">السعر لكل خيار يشمل كامل الكوادر. المفتاح يفعّل/يعطّل الخيار لهذه المحافظة — المعطَّل أو الصفر لا يظهر للعميل. «المدة» تحجز فترة السائق ولا تظهر للعميل.</p>
                                                <div className="space-y-3">
                                                    {HOME_TYPES.map(t => {
                                                        const pkg = newZone.packages[t.key];
                                                        return (
                                                            <div key={t.key} className="bg-white border border-rose-100 rounded-2xl p-4 space-y-3">
                                                                <p className="font-black text-[#660033] text-sm">{t.label}</p>
                                                                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                                                                    <div className="sm:col-span-2">
                                                                        <label className="block text-xs font-bold text-slate-600 mb-1">الوصف (يظهر للعميل)</label>
                                                                        <input type="text" dir="rtl" value={pkg.desc}
                                                                            onChange={e => setNewZone(p => ({ ...p, packages: { ...p.packages, [t.key]: { ...p.packages[t.key], desc: e.target.value } } }))}
                                                                            className={zoneInputCls} />
                                                                    </div>
                                                                    <div>
                                                                        <label className="block text-xs font-bold text-slate-600 mb-1">المدة (ساعات)</label>
                                                                        <input type="number" dir="ltr" min="1" max="12" value={pkg.dur}
                                                                            onChange={e => setNewZone(p => ({ ...p, packages: { ...p.packages, [t.key]: { ...p.packages[t.key], dur: e.target.value } } }))}
                                                                            className={zoneInputCls} />
                                                                    </div>
                                                                </div>
                                                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                                                    {['1', '2', '3', '4'].map(n => {
                                                                        const c = pkg.crews[n];
                                                                        return (
                                                                            <div key={n} className="flex items-center gap-2">
                                                                                <input type="checkbox" checked={c.enabled}
                                                                                    title={`تفعيل ${CREW_LABELS[n]}`}
                                                                                    onChange={e => setNewZone(p => ({ ...p, packages: { ...p.packages, [t.key]: { ...p.packages[t.key], crews: { ...p.packages[t.key].crews, [n]: { ...p.packages[t.key].crews[n], enabled: e.target.checked } } } } }))}
                                                                                    className="w-4 h-4 accent-[#660033] shrink-0" />
                                                                                <span className="text-xs font-bold text-slate-600 w-20 shrink-0">{CREW_LABELS[n]}</span>
                                                                                <input type="number" dir="ltr" min="0" step="0.5" value={c.price}
                                                                                    disabled={!c.enabled}
                                                                                    placeholder="السعر"
                                                                                    onChange={e => setNewZone(p => ({ ...p, packages: { ...p.packages, [t.key]: { ...p.packages[t.key], crews: { ...p.packages[t.key].crews, [n]: { ...p.packages[t.key].crews[n], price: e.target.value } } } } }))}
                                                                                    className={zoneInputCls + (c.enabled ? '' : ' opacity-50')} />
                                                                            </div>
                                                                        );
                                                                    })}
                                                                </div>
                                                            </div>
                                                        );
                                                    })}
                                                </div>
                                            </div>

                                            {/* جدول ساعات المحافظة — فتح/إقفال كل ساعة، فترات
                                                استثنائية، وأيام إغلاق كامل. كان في التطبيق وحده. */}
                                            <ZoneScheduleEditor
                                                key={editingZoneId ?? 'new'}
                                                initial={scheduleInitial}
                                                onChange={setScheduleDraft}
                                            />

                                            <div className="flex gap-3">
                                                <button
                                                    type="button"
                                                    onClick={handleAddZone}
                                                    disabled={isAddingZone}
                                                    className="flex items-center gap-2 px-6 py-3 bg-rose-600 hover:bg-rose-700 disabled:opacity-60 text-white font-bold rounded-xl transition-all"
                                                >
                                                    {isAddingZone ? <Loader2 size={16} className="animate-spin" /> : (editingZoneId ? <Pencil size={16} /> : <Plus size={16} />)}
                                                    {editingZoneId ? 'حفظ التعديلات' : 'حفظ المحافظة'}
                                                </button>
                                                {/* نشر الأسعار على محافظات مختارة — الأسعار والباقات فقط،
                                                    لا الاسم/الموقع/نصف القطر/التفعيل/الجدول. */}
                                                {zones.length > 0 && (
                                                    <button
                                                        type="button"
                                                        onClick={() => setShowApplyPicker(true)}
                                                        className="flex items-center gap-2 px-5 py-3 border border-rose-200 text-rose-700 font-bold rounded-xl hover:bg-rose-50 transition-all"
                                                    >
                                                        <Copy size={16} />
                                                        تطبيق الأسعار على محافظات…
                                                    </button>
                                                )}
                                                <button type="button" onClick={() => { setShowAddForm(false); setEditingZoneId(null); setEditingZoneName(''); setNewZone(emptyZoneForm); }} className="px-6 py-3 border border-slate-200 text-slate-600 font-bold rounded-xl hover:bg-slate-50 transition-all">
                                                    إلغاء
                                                </button>
                                            </div>

                                            {showApplyPicker && (
                                                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm">
                                                    <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md max-h-[85vh] flex flex-col">
                                                        <div className="p-6 border-b border-slate-100">
                                                            <h3 className="text-lg font-extrabold text-slate-800">تطبيق الأسعار على محافظات</h3>
                                                            <p className="text-xs text-slate-500 mt-1">تُنسخ الأسعار والباقات المعروضة في النموذج إلى المحافظات المختارة. الاسم والموقع ونصف القطر وجدول الساعات لا تُمسّ.</p>
                                                        </div>
                                                        <div className="p-4 overflow-y-auto flex-1 space-y-1">
                                                            <button
                                                                type="button"
                                                                onClick={() => setApplyTargets(applyTargets.length === zones.length ? [] : zones.map(z => z.id))}
                                                                className="w-full text-right px-3 py-2 rounded-lg text-sm font-bold text-rose-700 hover:bg-rose-50"
                                                            >
                                                                {applyTargets.length === zones.length ? 'إلغاء تحديد الكل' : 'تحديد الكل'}
                                                            </button>
                                                            {zones.map(z => (
                                                                <label key={z.id} className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-50 cursor-pointer">
                                                                    <input
                                                                        type="checkbox"
                                                                        checked={applyTargets.includes(z.id)}
                                                                        onChange={e => setApplyTargets(prev => e.target.checked ? [...prev, z.id] : prev.filter(x => x !== z.id))}
                                                                        className="w-4 h-4 accent-rose-600"
                                                                    />
                                                                    <span className="font-bold text-slate-700 text-sm">{z.name}</span>
                                                                </label>
                                                            ))}
                                                        </div>
                                                        <div className="p-4 border-t border-slate-100 flex gap-3">
                                                            <button type="button" onClick={() => { setShowApplyPicker(false); setApplyTargets([]); }} className="flex-1 px-4 py-3 border border-slate-200 text-slate-600 rounded-xl font-bold hover:bg-slate-50">إلغاء</button>
                                                            <button type="button" disabled={isApplying || applyTargets.length === 0} onClick={handleApplyPricesToZones} className="flex-1 px-4 py-3 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 disabled:opacity-60 flex justify-center items-center gap-2">
                                                                {isApplying ? <Loader2 size={16} className="animate-spin" /> : null}
                                                                حفظ ({applyTargets.length})
                                                            </button>
                                                        </div>
                                                    </div>
                                                </div>
                                            )}
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
                                                    className={`relative group p-5 rounded-2xl border-2 transition-all ${zone.enabled ? 'bg-white border-rose-200 shadow-sm shadow-rose-500/5' : 'bg-slate-50 border-slate-200 opacity-60'}`}
                                                >
                                                    <div className="flex items-start justify-between gap-2">
                                                        <div className="flex items-center gap-3">
                                                            <div className={`w-11 h-11 rounded-xl flex items-center justify-center font-black text-lg ${zone.enabled ? 'bg-rose-100 text-rose-700' : 'bg-slate-200 text-slate-500'}`}>
                                                                {zone.name.charAt(0)}
                                                            </div>
                                                            <div>
                                                                <p className="font-black text-slate-800">{zone.name}</p>
                                                                <p className="text-xs text-slate-500 font-mono mt-0.5">{zone.radiusKm} كم{zone.governorate ? ` • ${zone.governorate}` : ''}{zone.terrainSurchargePercent ? ` • وعورة +${zone.terrainSurchargePercent}%` : ''}</p>
                                                            </div>
                                                        </div>
                                                        {/* ظاهرة دائماً على اللمس، وتخفت حتى التحويم على الفأرة فقط.
                                                            Tailwind v4 يترجم hover داخل @media (hover: hover)، فعلى جهاز
                                                            لمسي لم تكن القاعدة تُطابَق إطلاقاً — تبقى الأزرار بشفافية 0
                                                            للأبد (بلا pointer-events-none، فهي غير مرئية لا معطّلة).
                                                            زرّا التعديل والحذف كانا غير قابلين للاكتشاف على أي تابلت. */}
                                                        <div className="flex items-center gap-1 opacity-100 [@media(hover:hover)]:opacity-0 group-hover:opacity-100 transition-opacity">
                                                            <button
                                                                type="button"
                                                                onClick={() => handleEditZone(zone)}
                                                                className="p-1.5 rounded-lg text-slate-400 hover:text-[#660033] hover:bg-rose-50 transition-all"
                                                                title="تعديل"
                                                            >
                                                                <Pencil size={16} />
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() => handleToggleZone(zone)}
                                                                className={`p-1.5 rounded-lg transition-all ${zone.enabled ? 'text-rose-600 hover:bg-rose-50' : 'text-slate-400 hover:bg-slate-100'}`}
                                                                title={zone.enabled ? 'إيقاف' : 'تفعيل'}
                                                            >
                                                                {zone.enabled ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() => setDeleteTarget(zone)}
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
        case 'general': return <Shield size={32} className="text-[#660033]" strokeWidth={2} />;
        case 'payments': return <Wallet size={32} className="text-emerald-500" strokeWidth={2} />;
        case 'coverage': return <MapPin size={32} className="text-rose-600" strokeWidth={2} />;
        default: return <Shield size={32} className="text-[#660033]" strokeWidth={2} />;
    }
}


