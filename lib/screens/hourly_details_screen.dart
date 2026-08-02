import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/utils/home_packages.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';


class HourlyCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const HourlyCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<HourlyCleaningDetailsScreen> createState() => _HourlyCleaningDetailsScreenState();
}

class _HourlyCleaningDetailsScreenState extends State<HourlyCleaningDetailsScreen>
    with WidgetsBindingObserver {
  // (نظام باقات السكن) اختيار العميل: نوع السكن + عدد الكوادر — بدل الساعات.
  List<HomePackage> _packages = [];
  String? _selectedType;
  int? _selectedCrews;
  double _basePrice = 0.0; // أساس (قبل الضريبة) لخيار (النوع × الكوادر) المختار
  int _durationHours = 4; // مدة الجدولة للنوع المختار — تحجز فترة السائق وتفحص السعة

  // (قرار المالك) العميل يختار **اليوم فقط** — لا وقت بدء. السعة اليومية
  // (max_orders_per_day) تضبطها الإدارة من الإعدادات، ووقت البدء الفعلي يُرسى
  // على ساعة فتح المنطقة وتعدّله الإدارة من «تعديل الزيارة» عند الحاجة.
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isLoading = true;

  /// مراقبة تنقّل العميل: يعاد التحديد بصمت دورياً وعند العودة للتطبيق،
  /// فإن دخل محافظة أخرى تتبدّل المنطقة والأسعار تلقائياً.
  Timer? _zoneWatch;

  /// اختار العميل موقعه يدوياً من الخريطة (يحجز لبيته وهو في مكان آخر) —
  /// **تتوقف المراقبة الصامتة** كي لا يسحقه GPS موضعِه الحالي كل 45 ثانية
  /// ويُرسَل السائق لموقفه بدل بيته. زر «حدّد موقعي تلقائياً» يعيد تفعيلها.
  bool _manualLocationOverride = false;

  int _maxOrdersPerDay = 10;
  Map<String, int> _dailyOrderCounts = {};   // "yyyy-MM-dd" → total orders
  // (إتاحة اليوم = سعة يومية **و** سائق متاح) عدّادات الساعات وعدد السائقين
  // النشطين — لا تُعرض كأوقات للعميل، بل تقرر داخلياً هل يتسع اليومُ لمدة الباقة.
  Map<String, int> _slotCounts = {};          // "yyyy-MM-dd_HH:00" → طلبات تشغل الساعة
  int _maxTeamsPerSlot = 5;                   // عدد السائقين النشطين
  Map<String, List<int>> _openHours = {};     // yyyy-MM-dd → [فتح، إغلاق] — لساعة بدء الإرساء
  Set<String> _closedDates = {};              // أيام لا تُخدَم فيها المنطقة
  bool _loadingDailyCounts = true;

  /// تعذّر جلب الإتاحة من الخادم. **لا يجوز عرض تقويم أخضر في هذه الحالة**: الأعداد
  /// تكون فارغة فيبدو كل يوم متاحاً، فيختار العميل يوماً ممتلئاً. نعرض إعادة محاولة.
  bool _availabilityError = false;

  /// حارس تسلسلي لطلبات الإتاحة: نداء الفتح (بلا منطقة) ونداء ما بعد التحديد
  /// (بمنطقة) يتسابقان — الأبطأ كان يكتب فوق الأحدث فتظهر أيام مغلقة خضراء.
  int _availabilityReqId = 0;

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;

  /// حالة التحديد التلقائي — تُعرض للعميلة بدل الصمت.
  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<Map<String, dynamic>> _zones = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchConfigAndZones();
    _loadAvailabilityFromServer();
    // إعادة تحديد صامتة دورية: إن تنقّل العميل لمحافظة أخرى تتبدّل المنطقة تلقائياً.
    _zoneWatch = Timer.periodic(
        const Duration(seconds: 45), (_) => _attemptAutoLocation(silent: true));
    // شرط الخدمة: يجب أن تُقرّ العميلة بوجود سيدة في المنزل قبل طلب العاملات.
    // «إلغاء» يعيدها للرئيسية فلا تُكمل الطلب؛ «نعم» يتيح المتابعة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirmWomanPresent());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عاد للتطبيق (ربما من مدينة أخرى) → أعد التحديد بصمت.
    if (state == AppLifecycleState.resumed) _attemptAutoLocation(silent: true);
  }

  Future<void> _confirmWomanPresent() async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('تنبيه',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF1E293B))),
          // الزرّان داخل content ضمن Row (وهي Flex تقبل Expanded). كانا في actions
          // التي تُرسَم في OverflowBar (ليست Flex) فيرمي Expanded استثناء تخطيط —
          // ويظهر كصندوق رمادي فارغ ضخم على الجهاز في نسخة الإصدار.
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('يشترط وجود سيدة في المنزل',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontSize: 15,
                      height: 1.6,
                      color: const Color(0xFF660033),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFFDECEC),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('إلغاء',
                          style: GoogleFonts.tajawal(
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF660033),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('نعم',
                          style:
                              GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // لم توافق (أو أُغلقت) → لا يمكن إكمال الطلب: عودة للشاشة السابقة.
    if (ok != true && mounted) Navigator.of(context).pop();
  }

  /// جلب بيانات الإتاحة عبر Cloud Function (Admin SDK — لا قيود صلاحيات).
  /// تُعيد الأعداد الحقيقية للطلبات لكل تاريخ وكل خانة زمنية.
  Future<void> _loadAvailabilityFromServer() async {
    if (!mounted) return;
    final int reqId = ++_availabilityReqId; // استجابة أقدم من الأحدث تُهمَل
    setState(() {
      _loadingDailyCounts = true;
      _availabilityError = false;
    });
    try {
      final now = DateTime.now();
      final startDate = intl.DateFormat('yyyy-MM-dd').format(now);
      final endDate = intl.DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 31)));

      // السعة رقم واحد للنشاط كلّه (السائقون بلا مناطق). المنطقة تُمرَّر لجلب **جدول
      // فتحها** فقط — أيام وساعات عمل المنطقة، يفرضها الخادم وترسمها الشاشة.
      final result = await FirebaseFunctions.instance
          .httpsCallable('getHourlyAvailability')
          .call({
            'startDate': startDate,
            'endDate': endDate,
            if (_selectedZoneName != null) 'zoneName': _selectedZoneName,
          });

      final data = result.data as Map;

      final rawDaily = data['dailyCounts'] as Map? ?? {};
      final rawSlots = data['slotCounts'] as Map? ?? {};

      final Map<String, int> daily = rawDaily.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
      final Map<String, int> slots = rawSlots.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
      final Map<String, List<int>> openHours =
          (data['openHours'] as Map? ?? {}).map((k, v) => MapEntry(
              k.toString(), (v as List).map((e) => (e as num).toInt()).toList()));
      final Set<String> closed = ((data['closedDates'] as List?) ?? [])
          .map((e) => e.toString())
          .toSet();

      final int maxPerDay = ((data['maxOrdersPerDay'] as num?)?.toInt()) ?? 10;
      final int maxPerSlot = ((data['maxTeamsPerSlot'] as num?)?.toInt()) ?? 5;

      if (!mounted || reqId != _availabilityReqId) return;
      setState(() {
        _dailyOrderCounts = daily;
        _slotCounts = slots;
        _openHours = openHours;
        _closedDates = closed;
        _maxOrdersPerDay = maxPerDay;
        _maxTeamsPerSlot = maxPerSlot;
        _loadingDailyCounts = false;

        // انتقل تلقائياً لأول تاريخ متاح (سعةً وسائقين، وغير مغلق بالجدول).
        if (_dateUnavailable(_selectedDate)) {
          for (int i = 0; i < 30; i++) {
            final candidate = now.add(Duration(days: i + 1));
            if (!_dateUnavailable(candidate)) {
              _selectedDate = candidate;
              break;
            }
          }
        }
      });
    } catch (e) {
      // **لا نبتلع الفشل بصمت.** كان هذا الـ catch يكتفي بإطفاء الدوّار، فتبقى
      // ‎_dailyOrderCounts فارغة ⇒ ‎`activeOrders = 0` لكل تاريخ ⇒ ‎`0 >= _maxOrdersPerDay`
      // = false ⇒ **كل التواريخ تظهر خضراء** والعميل يختار يوماً ممتلئاً.
      // الأخضر يجب أن يعني «متاح»، لا «لا نعرف».
      debugPrint('[getHourlyAvailability] error: $e');
      if (mounted && reqId == _availabilityReqId) {
        setState(() {
          _loadingDailyCounts = false;
          _availabilityError = true;
        });
      }
    }
  }

  Future<void> _fetchConfigAndZones() async {
    // (باقات السكن) لا إعدادات ساعات بعد الآن — الخيارات والأسعار والمدد كلها من
    // وثيقة المنطقة packages، وسقف اليوم يأتي مع استجابة الإتاحة الخادمية.
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('service_zones')
          .where('enabled', isEqualTo: true)
          .get();
      if (mounted) {
        final sorted = snapshot.docs.map((doc) => doc.data()).toList()
          ..sort((a, b) => (a['rank'] as int? ?? 0).compareTo(b['rank'] as int? ?? 0));
        setState(() {
          _zones = sorted;
          _isLoading = false;
        });
        _attemptAutoLocation();
      }
    } catch (e) {
      // **لا نبتلع فشل جلب المناطق بصمت** (كما أُصلح جلب الإتاحة أعلاه): كان
      // الـ catch يكتفي بإطفاء الدوّار فتُرسم الشاشة طبيعية بقائمة مناطق فارغة —
      // زر «حدّد موقعي» يصبح ميتاً وكل موقع يُتَّهم زوراً «خارج نطاق الخدمة».
      debugPrint('[Hourly] fetchZones failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر تحميل مناطق الخدمة: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// تحديد تلقائي **يقول السبب عند الفشل**.
  ///
  /// كان كل مسار فشل هنا ينتهي بـ`return;` صامت أو `catch { /* Silent error */ }`،
  /// فتبقى الشاشة على «لم يُحدَّد موقعك بعد» لكل الأسباب على السواء — والعميلة (ونحن)
  /// لا نعرف: أالخدمة مطفأة؟ أم الإذن مرفوض؟ أم GPS لم يستجب؟ ولا سطر في السجلّ.
  ///
  /// [userInitiated] عند الفتح نحاول بلا إظهار مربّع الإذن إن كان مرفوضاً سلفاً؛
  /// وعند ضغط «حدّد موقعي تلقائياً» نطلبه صراحةً.
  ///
  /// [silent] (مراقبة التنقّل): محاولة خلفية دورية — لا مؤشر تحميل، والفشل يُتجاهل
  /// (تبقى المنطقة الحالية)، ولا إشعار إلا إن تغيّرت المنطقة فعلاً.
  Future<void> _attemptAutoLocation(
      {bool userInitiated = false, bool silent = false}) async {
    if (!mounted) return;
    // مناطق فارغة = فشل جلبها عند الفتح غالباً — كان return الصامت يجعل زرّ
    // «حدّد موقعي تلقائياً» ميتاً بلا أي أثر. عند طلبٍ صريح نعيد الجلب، وإن
    // استمر الفشل نعرض سبباً قابلاً لإعادة المحاولة بدل الصمت.
    if (_zones.isEmpty) {
      if (!userInitiated) return;
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[Hourly] fetchZones retry failed: $e');
      }
      if (!mounted) return;
      if (_zones.isEmpty) {
        setState(() {
          _isLocating = false;
          _locateFailure = LocateFailure.unknown;
        });
        return;
      }
    }
    // اختيار يدوي قائم: المراقبة الصامتة لا تكتبه أبداً. الطلب الصريح يلغيه.
    if (silent && _manualLocationOverride) return;
    if (userInitiated) _manualLocationOverride = false;
    if (silent && _isLocating) return; // لا نزاحم محاولة ظاهرة جارية
    if (!silent) {
      setState(() {
        _isLocating = true;
        _locateFailure = null;
      });
    }

    final res = await ZyiarahZoneLocator.locate(_zones,
        requestPermission: userInitiated);
    if (!mounted) return;

    if (!res.isSuccess) {
      if (silent) return; // خلفية: أبقِ الحالة الحالية بلا إزعاج
      setState(() {
        _isLocating = false;
        _locateFailure = res.failure;
        if (res.location != null) _selectedLocation = res.location; // خارج النطاق
      });
      return;
    }

    final bool zoneChanged = _selectedZoneName != res.zoneName;
    if (silent && !zoneChanged) return; // لا جديد — لا إعادة رسم ولا شبكة

    setState(() {
      _selectedLocation = res.location;
      _selectedZoneName = res.zoneName;
      _isLocating = false;
      _locateFailure = null;
    });
    _applyZonePackages(res.zone!);
    await _loadAvailabilityFromServer();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(silent
          ? "انتقلتِ إلى منطقة أخرى — حُدِّثت الأسعار: $_selectedZoneName"
          : "تم تحديد موقعك تلقائياً: $_selectedZoneName"),
      backgroundColor: const Color(0xFF660033),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _pickLocation() async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LocationPickerScreen(
          serviceName: "تحديد موقع النظافة بالساعة",
        ),
      ),
    );

    if (!mounted) return;
    if (result == null || result is! GeoPoint) return;

    GeoPoint loc = result;
    // اختيارٌ يدوي صريح — أوقف الكتابة الصامتة فوقه (يحجز لبيته من مكان عمله).
    _manualLocationOverride = true;

    // قائمة مناطق فارغة (فشل جلبها عند الفتح) تجعل matchZone يُرجع null لكل
    // نقطة — فيُتَّهم عميلٌ داخل النطاق زوراً بأنه «خارج نطاق الخدمة» ويُحجب
    // الحجز بسببٍ كاذب. نعيد الجلب أولاً، وإن استمر الفشل نقول السبب الحقيقي.
    if (_zones.isEmpty) {
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[Hourly] fetchZones retry failed: $e');
      }
      if (!mounted) return;
      if (_zones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر تحميل مناطق الخدمة — تحقّق من اتصالك وأعد المحاولة'),
            backgroundColor: Colors.red));
        return;
      }
    }

    // مطابقة المنطقة من المصدر المشترك — كانت منسوخة حرفياً في ثلاث شاشات.
    final matchedZone = ZyiarahZoneLocator.matchZone(loc, _zones);

    if (matchedZone != null) {
      if (mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = matchedZone['name'] as String?;
          _locateFailure = null;
        });
        _applyZonePackages(matchedZone);
        // حمّل بيانات الإتاحة من الـ CF ثم احسب الخانات من الـ cache
        await _loadAvailabilityFromServer();
      }
    } else {
      if (mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = null;
          _packages = [];
          _selectedType = null;
          _selectedCrews = null;
          _basePrice = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("نأسف، موقعك خارج نطاق الخدمة حالياً"), backgroundColor: Colors.red));
      }
    }
  }

  /// يقرأ باقات المنطقة ويتحقق أن الاختيار الحالي ما زال مفعّلاً فيها —
  /// عند التنقّل لمحافظةٍ خيارُ كوادرها المطابق معطّل يُصفَّر الاختيار.
  void _applyZonePackages(Map<String, dynamic> zone) {
    final pkgs = zoneHomePackages(zone);
    String? type = _selectedType;
    int? crews = _selectedCrews;
    double price = 0.0;
    int duration = _durationHours;

    final current = pkgs.where((p) => p.type == type).toList();
    if (current.isEmpty || !current.first.sellable) {
      type = null;
      crews = null;
    } else {
      final match =
          current.first.options.where((o) => o.crews == crews).toList();
      if (match.isEmpty) {
        crews = null;
      } else {
        price = match.first.basePrice;
        duration = current.first.durationHours;
      }
    }

    setState(() {
      _packages = pkgs;
      _selectedType = type;
      _selectedCrews = crews;
      _basePrice = price;
      _durationHours = duration;
    });
  }

  /// ساعات فتح المنطقة في يومٍ ما (من الجدول، وإلا 8..22 الافتراضية).
  List<int> _openHoursFor(DateTime d) {
    final key = intl.DateFormat('yyyy-MM-dd').format(d);
    return _openHours[key] ?? const [8, 22];
  }

  /// أول ساعة في اليوم يتسع فيها **سائقٌ** لمدة الباقة كاملةً — null إن لم توجد.
  /// لا تُعرض للعميل: تقرر إتاحة اليوم وتُرسي موعد الطلب على فترةٍ حرّة فعلاً.
  int? _firstFeasibleStart(DateTime d) {
    final key = intl.DateFormat('yyyy-MM-dd').format(d);
    final open = _openHoursFor(d);
    final last = open[1] - _durationHours;
    for (int h = open[0]; h <= last; h++) {
      bool free = true;
      for (int hh = h; hh < h + _durationHours; hh++) {
        final slotKey = '${key}_${hh.toString().padLeft(2, '0')}:00';
        if ((_slotCounts[slotKey] ?? 0) >= _maxTeamsPerSlot) {
          free = false;
          break;
        }
      }
      if (free) return h;
    }
    return null;
  }

  /// (قرار المالك) إتاحة اليوم = **سعة يومية تسمح + سائق متاح لمدة الباقة** —
  /// لا يكفي أحدهما. اليوم المغلق بجدول المنطقة غير متاح بداهةً.
  bool _dateUnavailable(DateTime d) {
    final s = intl.DateFormat('yyyy-MM-dd').format(d);
    if (_closedDates.contains(s)) return true;
    if ((_dailyOrderCounts[s] ?? 0) >= _maxOrdersPerDay) return true;
    return _firstFeasibleStart(d) == null; // لا سائق يتسع جدوله = غير متاح
  }

  // (باقات السكن) سعر الخيار المختار يشمل عدد الكوادر سلفاً — لا ضرب بعدد عاملات.
  double get totalAmount => _basePrice;

  // الأساس من اللوحة؛ الضريبة 15% تُضاف فوقه (قرار المالك) — المعروض «شامل الضريبة».
  double get grandTotal => ((totalAmount * 1.15) * 100).roundToDouble() / 100;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _handleInitiateFlow() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى تحديد موقعك أولاً لمعرفة الأسعار المتاحة")));
      return;
    }
    if (_selectedType == null || _selectedCrews == null || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("اختر نوع السكن وعدد الكوادر أولاً")));
      return;
    }
    // (قرار المالك) لا وقت بدء يختاره العميل: يُرسى الموعد على **أول ساعة فيها
    // سائق متاح لمدة الباقة** في اليوم المختار — فالإسناد يجد سائقاً فعلاً،
    // والإدارة تعدّل الوقت من «تعديل الزيارة» عند الحاجة (يُشعَر الطرفان تلقائياً).
    final int? feasibleStart = _firstFeasibleStart(_selectedDate);
    if (feasibleStart == null || _dateUnavailable(_selectedDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("اكتملت مواعيد هذا اليوم — اختر يوماً آخر متاحاً")));
      return;
    }
    final serviceDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day, feasibleStart,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            // اسم وصفي بالباقة المختارة — يظهر في الإيميلات وفاتورة ZATCA وقوائم
            // الإدارة بدل «نظافة بالساعة» العامة. **بلا كلمة «باقة»**: مُصالح
            // الدفعات اليتيمة يتخطى أي service_name يحويها (فلتر الاشتراكات).
            serviceName:
                'تنظيف منزلي — ${kHomeTypeLabels[_selectedType]} (${crewLabel(_selectedCrews!)})',
            amount: grandTotal, // الأساس + 15% — شاشة الدفع تعامله كإجمالي
            location: _selectedLocation!,
            // مدة الجدولة (تحجز فترة السائق وتفحصها السعة) — من الباقة لا من العميل.
            hours: _durationHours,
            serviceDate: serviceDateTime,
            workerCount: _selectedCrews!,
            zoneName: _selectedZoneName,
            // تفصيل الباقة: يراه الأدمن والسائق، ويتحقق منه التسعير الخادمي.
            serviceMeta: {
              'kind': 'home_package',
              'homeType': _selectedType,
              'homeLabel': kHomeTypeLabels[_selectedType],
              'crewCount': _selectedCrews,
              'durationHours': _durationHours,
            },
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void dispose() {
    _zoneWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text(widget.serviceName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3D1040), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF660033)))
              : Column(
            children: [
              Hero(
                tag: 'svc-assets/images/hourly_cleaning.png',
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/images/hourly_cleaning.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFE1F0E4),
                      child: const Icon(Icons.access_time_filled, color: Color(0xFF10B981), size: 60),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLocationPickerSection(),
                    const SizedBox(height: 30),
                    
                    if (_selectedLocation != null) ...[
                      const Text("اختر نوع سكنك:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 6),
                      const Text("الأسعار شاملة الضريبة وتشمل كامل الكوادر المختارة",
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 15),
                      _buildPackageSelector(),
                      const SizedBox(height: 30),

                      const Text("تاريخ الخدمة:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      _buildDateSelector(),
                      const SizedBox(height: 10),
                      _buildDateLegend(),
                      const SizedBox(height: 30),

                      // (قرار المالك) لا اختيار وقت — اليوم يكفي، والإدارة تضبط
                      // الوقت المناسب ضمن ساعات عمل المنطقة ويصل العميل إشعار به.
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF1F6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF2DEE9)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.schedule_rounded,
                                color: Color(0xFF660033), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "يصلك الفريق ضمن ساعات عمل منطقتك في اليوم المختار — وتصلك رسالة بالوقت المحدد.",
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF660033),
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // (ملاحظة العميل 2026-08-01) توضيح ما تشمله الخدمة: الضريبة
                      // وأدوات التنظيف الأساسية مشمولة، ومواد التنظيف لا — مع
                      // توجيه صريح لمتجر زيارة بدل ترك العميلة تكتشف يوم الزيارة.
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.cleaning_services_rounded,
                                    color: Color(0xFF15803D), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "السعر شامل الضريبة وأدوات التنظيف الأساسية. مواد التنظيف غير مشمولة.",
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF15803D),
                                        fontWeight: FontWeight.w600,
                                        height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ZyiarahStoreScreen())),
                              child: const Padding(
                                padding: EdgeInsets.only(right: 30),
                                child: Text(
                                  "تحتاجين مواد تنظيف؟ تسوّقيها من متجر زيارة ←",
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF660033),
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      _buildSummaryCard(),
                      const SizedBox(height: 30),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _handleInitiateFlow,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF660033), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 4),
                          child: const Text("متابعة لملخص الحجز", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ] else ...[
                       const Center(child: Text("يرجى تحديد الموقع الجغرافي لعرض باقات النظافة بالساعة والأسعار المخصصة لمنطقتك.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5))),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildLocationPickerSection() {
    return ZyiarahZoneLocationCard(
      isLocating: _isLocating,
      zoneName: _selectedZoneName,
      failure: _locateFailure,
      onLocateMe: () => _attemptAutoLocation(userInitiated: true),
      onPickManually: _pickLocation,
    );
  }

  /// بطاقات باقات السكن: لكل نوعٍ وصفُه وخيارات الكوادر **المفعّلة في منطقة العميل
  /// فقط** بسعرها شامل الضريبة — اختيار الكادر يختار الباقة ويعيد حساب الخانات
  /// بمدة الجدولة الخاصة بالنوع.
  Widget _buildPackageSelector() {
    final sellable = _packages.where((p) => p.sellable).toList();
    if (sellable.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200)),
        child: const Text("لا توجد باقات مسعّرة في منطقتك حالياً",
            style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
      );
    }
    return Column(
      children: sellable.map((pkg) {
        final bool isTypeSelected = _selectedType == pkg.type;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: isTypeSelected
                    ? const Color(0xFF660033)
                    : Colors.grey.shade200,
                width: isTypeSelected ? 2 : 1.5),
            boxShadow: [
              BoxShadow(
                  color: isTypeSelected
                      ? const Color(0xFF660033).withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      pkg.type == 'villa'
                          ? Icons.villa_rounded
                          : Icons.apartment_rounded,
                      color: const Color(0xFF660033),
                      size: 22),
                  const SizedBox(width: 8),
                  Text(pkg.label,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 30),
                child: Text("(${pkg.desc})",
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF64748B))),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pkg.options.map((opt) {
                  final bool isSelected =
                      isTypeSelected && _selectedCrews == opt.crews;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _selectedType = pkg.type;
                        _selectedCrews = opt.crews;
                        _basePrice = opt.basePrice;
                        _durationHours = pkg.durationHours;
                        // مدةٌ أطول قد تُفقِد اليوم المختار سائقَه المتاح —
                        // انتقل لأول يومٍ يتسع (سعةً وسائقين) بدل تركه محجوباً.
                        if (_dateUnavailable(_selectedDate)) {
                          final now = DateTime.now();
                          for (int i = 0; i < 30; i++) {
                            final c = now.add(Duration(days: i + 1));
                            if (!_dateUnavailable(c)) {
                              _selectedDate = c;
                              break;
                            }
                          }
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF660033)
                            : const Color(0xFFFAF1F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isSelected
                                ? const Color(0xFF660033)
                                : const Color(0xFFF2DEE9),
                            width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Text(crewLabel(opt.crews),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF660033))),
                          const SizedBox(height: 2),
                          Text("${formatSar(opt.grossPrice)} ر.س",
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateSelector() {
    // تعذّر معرفة الإتاحة ⇒ لا نرسم تقويماً أخضر كاذباً. الأخضر وعدٌ بوجود سائق.
    if (_availabilityError) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'تعذّر تحميل المواعيد المتاحة.\nتحقّق من اتصالك وأعد المحاولة.',
                style: TextStyle(fontSize: 13, color: Color(0xFF991B1B), height: 1.5),
              ),
            ),
            TextButton.icon(
              onPressed: _loadAvailabilityFromServer,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            ),
          ],
        ),
      );
    }
    if (_loadingDailyCounts) {
      return const SizedBox(
        height: 82,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF660033)),
        ),
      );
    }
    const dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    final now = DateTime.now();
    return SizedBox(
      height: 82,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 30,
        itemBuilder: (context, index) {
          final date = now.add(Duration(days: index + 1));
          final isSelected = _isSameDay(_selectedDate, date);
          
          final dateStr = intl.DateFormat('yyyy-MM-dd').format(date);
          final activeOrders = _dailyOrderCounts[dateStr] ?? 0;
          // مغلق بالجدول (رمادي) ≠ محجوز بالكامل (أحمر) — سببان مختلفان.
          // «محجوز» = سعة اليوم امتلأت **أو** لا سائق يتسع لمدة الباقة (قرار المالك).
          final isClosed = _closedDates.contains(dateStr);
          final isFullyBooked = !isClosed &&
              (activeOrders >= _maxOrdersPerDay ||
                  _firstFeasibleStart(date) == null);
          final unavailable = isClosed || isFullyBooked;
          final Color availBg = isClosed
              ? const Color(0xFFF1F5F9)
              : isFullyBooked
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFECFDF5);
          final Color availBorder = isClosed
              ? const Color(0xFFE2E8F0)
              : isFullyBooked
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFA7F3D0);

          return GestureDetector(
            onTap: isClosed
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("لا نخدم منطقتك في هذا اليوم. اختر يوماً متاحاً (الأخضر).",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: Color(0xFF64748B),
                      duration: Duration(seconds: 2),
                    ));
                  }
                : isFullyBooked
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("هذا اليوم محجوز بالكامل، يرجى اختيار تاريخ آخر.", style: TextStyle(fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 2),
                        ));
                      }
                    : () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedDate = date);
                      },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF660033) : availBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF660033) : availBorder,
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: const Color(0xFF660033).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayNames[date.weekday % 7],
                    style: TextStyle(
                      fontSize: 9,
                      color: isSelected
                          ? Colors.white70
                          : unavailable
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF34D399),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSelected 
                          ? Colors.white 
                          : isFullyBooked 
                              ? const Color(0xFFEF4444) 
                              : const Color(0xFF10B981),
                    ),
                  ),
                  Text(
                    '/${date.month}',
                    style: TextStyle(
                      fontSize: 10, 
                      color: isSelected 
                          ? Colors.white60 
                          : isFullyBooked 
                              ? const Color(0xFFFCA5A5) 
                              : const Color(0xFF34D399),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateLegend() {
    return Row(
      children: [
        _legendDot(const Color(0xFF10B981)),
        const SizedBox(width: 6),
        const Text("متاح للحجز", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(width: 20),
        _legendDot(const Color(0xFFEF4444)),
        const SizedBox(width: 6),
        const Text("محجوز بالكامل", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _legendDot(Color color, {Color? border}) => Container(
    width: 12, height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: border ?? color)),
  );

  Widget _buildSummaryCard() {
    final String pkgLabel = _selectedType == null
        ? '—'
        : (kHomeTypeLabels[_selectedType] ?? _selectedType!);
    final String crewsLabel =
        _selectedCrews == null ? '—' : crewLabel(_selectedCrews!);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("الباقة:", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              Text(pkgLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("الكوادر:", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              Text(crewsLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const Divider(height: 20, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("الإجمالي شامل الضريبة:", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text("${grandTotal.toStringAsFixed(2)} ر.س", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF660033))),
            ],
          )
        ],
      ),
    );
  }
}
