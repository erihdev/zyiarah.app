import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/app_update_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/widgets/service_meta_view.dart';
import 'package:zyiarah/utils/time_format.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:zyiarah/services/location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:zyiarah/screens/driver_tasks_screen.dart';
import 'package:zyiarah/screens/driver_notifications_screen.dart';
import 'package:zyiarah/screens/driver_profile_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final ZyiarahCoreService _coreService = ZyiarahCoreService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  final ZyiarahMessagingService _notificationService = ZyiarahMessagingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int _currentIndex = 0;
  String? _currentDriverId;
  String? _activeOrderId;
  String _driverName = 'السائق';

  // DRIVER-001: guard against double-tap on status update
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    _currentDriverId = _auth.currentUser?.uid;
    _ensureAlwaysAvailable();
    // إشعار توفّر تحديث — حرج للسائقين لإغلاق فجوة الإصدار (حالة scheduled لا تظهر بالنسخة القديمة)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZyiarahAppUpdateService.checkAndPrompt(context);
      // اطلب إذن الموقع صراحةً — بدونه لا يعمل التتبّع/الوصول على أندرويد (كان لا يُطلب أبداً).
      _ensureLocationPermission();
    });
  }

  /// يطلب إذن الموقع ثم يُنشئ تيار الموقع. بدون هذا الطلب الصريح لا يظهر مربّع الإذن
  /// على أندرويد وتفشل كل عمليات الموقع بصمت.
  Future<void> _ensureLocationPermission() async {
    final granted = await ZyiarahLocationService().requestPermission();
    if (!mounted) return;
    if (granted) {
      if (mounted) setState(() => _locationDenied = false);
      // (DRIVER-005/007) تدفّق الموقع الوحيد بوضع خفيف — يبدّله _startSync لوضع
      // التتبّع عند المهمة النشطة. الواجهة تقرأ من _posHub (بثّ) فلا تعطّل إعادة اشتراك.
      _startPositionStream(tracking: false);
    } else {
      setState(() => _locationDenied = true);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: const Text('يحتاج التطبيق إذن الموقع لاستقبال المهام وتتبّع التوصيل.'),
        action: SnackBarAction(
          // Geolocator.openAppSettings() ترمي UnimplementedError على الويب.
          label: 'الإعدادات',
          onPressed: kIsWeb ? () {} : () => Geolocator.openAppSettings(),
        ),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  /// السائق **متصل دائماً** (أُزيل مفتاح الاتصال/الفصل بقرار المالك: كان يوقف
  /// نفسه بالخطأ فتتوقّف عنه الطلبات والإشعارات). نحمّل اسمه ونضمن توفّره
  /// خادمياً كي تصله كل المهام بلا حالة «أوفلاين» تغلقها.
  Future<void> _ensureAlwaysAvailable() async {
    if (_currentDriverId == null) return;
    final ref = FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId);
    final doc = await ref.get();
    if (!mounted) return;
    final data = doc.data();
    setState(() => _driverName = data?['name'] as String? ?? 'السائق');
    if (data?['is_available'] != true || (data?['status'] as String?) == 'off') {
      // لا نُعِد الضبط أثناء مهمة نشطة (current_order_id قائم) — كان يكتب حالة متناقضة
      // (خامل/متاح مع طلب حيّ) تُظهر السائق متاحاً في لوحة الإدارة وهو مشغول.
      if (data?['current_order_id'] != null) return;
      try {
        await ref.update({'is_available': true, 'status': 'idle'});
      } catch (_) {}
    }
  }

  // تدفّق موقع **واحد** يغذّي الواجهة (عبر _posHub) والرفع الخادمي معاً. geolocator
  // يسمح بتدفّق موقع حيّ واحد فقط، ويُعيد استخدام إعدادات النداء الأول متجاهلاً
  // اللاحقة — فتدفّقان (خفيف للواجهة + تتبّع للرفع) يعني أن إعدادات الخدمة الأمامية
  // لا تُطبَّق أبداً، فيتجمّد تتبّع العميل حين يصغّر السائق التطبيق (فتح خرائط جوجل).
  // لذا: مصدرٌ واحد، نُلغيه ونُعيد إنشاءه عند تبديل الوضع كي تُطبَّق الإعدادات فعلاً.
  StreamSubscription<Position>? _posSub;
  bool _posTracking = false;
  bool _hasLocationStream = false;
  // حارس تداخل: نداءان متزامنان لـ _startPositionStream (طلب الإذن + مزامنة المهمة)
  // كانا يُنشئان اشتراكين ويُيتّمان أحدهما (تسريب GPS لا يُلغى أبداً). لا يُنشئ
  // الاشتراك إلا حامل أحدث جيل، ويُرفع الجيل في dispose فلا يُنشأ اشتراك بعد الإغلاق.
  int _posStreamGen = 0;
  final StreamController<Position> _posHub = StreamController<Position>.broadcast();
  bool _locationDenied = false;

  // إعدادات موقع تستمرّ في الخلفية: خدمة أمامية بإشعار على أندرويد، وتحديثات
  // خلفية على iOS — كي لا يتجمّد تتبّع العميل إذا صغّر السائق التطبيق (مثلاً
  // لفتح خرائط جوجل أثناء التوصيل).
  LocationSettings _trackingSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // مؤقّتاً بلا foregroundNotificationConfig (خدمة أمامية): يُبقي أندرويد التتبّع
      // أثناء فتح التطبيق فقط، لتفادي إقرار «الخدمة الأمامية» في Google Play وإطلاق
      // النسخة فوراً. لاستعادة الاستمرار عند تصغير التطبيق: أعِد foregroundNotificationConfig
      // هنا + أذني FOREGROUND_SERVICE(_LOCATION) في AndroidManifest + إقرار FGS. (2026-07-19)
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 15),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 20);
  }

  LocationSettings _lightSettings() => const LocationSettings(
      accuracy: LocationAccuracy.high, distanceFilter: 10);

  /// يبدأ/يبدّل تدفّق الموقع الوحيد. tracking=true أثناء مهمة نشطة (خدمة أمامية/
  /// تحديثات خلفية للرفع المستمر)، false لعرض المسافة قبل الانطلاق. الإلغاء ثم
  /// إعادة الإنشاء إلزامي: geolocator يتجاهل إعدادات تدفّق قائم.
  Future<void> _startPositionStream({required bool tracking}) async {
    if (_posSub != null && _posTracking == tracking) return;
    final gen = ++_posStreamGen;
    _posTracking = tracking;
    _hasLocationStream = true;
    await _posSub?.cancel();
    _posSub = null;
    // نداء أحدث (أو dispose) سبقنا أثناء انتظار الإلغاء — لا نُنشئ اشتراكاً يتيماً.
    if (gen != _posStreamGen) return;
    _posSub = Geolocator.getPositionStream(
      locationSettings: tracking ? _trackingSettings() : _lightSettings(),
    ).listen((pos) {
      if (!_posHub.isClosed) _posHub.add(pos);
      final oid = _activeOrderId;
      if (oid != null) {
        _orderService
            .updateDriverLocation(oid, GeoPoint(pos.latitude, pos.longitude))
            .catchError((e) => debugPrint("Location sync write error: $e"));
      }
    }, onError: (e) {
      if (e is PermissionDeniedException) {
        // DRIVER-006: إذن الموقع سُحب أثناء الجلسة — أوقف وأبلغ السائق.
        _stopSync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ تعطّل التتبع — إذن الموقع مسحوب. يُرجى إعادة تشغيل التطبيق لاستئناف الخدمة.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
      } else {
        debugPrint("Location stream error: $e");
      }
    });
  }

  void _startSync(String orderId) {
    if (_activeOrderId == orderId && _posTracking) return;
    _activeOrderId = orderId;
    _startPositionStream(tracking: true); // خدمة أمامية للرفع المستمر
  }

  void _stopSync() {
    _activeOrderId = null;
    // ارجع للتدفّق الخفيف (بلا خدمة أمامية) — تبقى المسافة تعمل لمهمة مجدولة قادمة.
    if (_hasLocationStream) _startPositionStream(tracking: false);
  }

  @override
  void dispose() {
    // رفع الجيل يمنع نداء _startPositionStream معلّقاً من إنشاء اشتراك بعد التخلص.
    _posStreamGen++;
    _posSub?.cancel();
    _activeOrderId = null;
    _posHub.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDriverId == null) {
      return const Scaffold(body: Center(child: Text("يرجى تسجيل الدخول")));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('تعذّر الاتصال، تحقق من الإنترنت', style: GoogleFonts.tajawal(color: Colors.grey)),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          // الشرط كان `&& snapshot.data!.exists` فيفشل **مفتوحاً**: سائق حُذف مستنده
          // يتخطّى بوّابة الطرد كلياً ويبقى داخل اللوحة. المستند المفقود = لم يعد سائقاً.
          final exists = snapshot.data!.exists;
          final data = exists ? snapshot.data!.data() as Map<String, dynamic> : null;
          final isActive = exists && (data!['is_active'] ?? true);

          if (!isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // الخروج المركزي (B3): حتى عند التعطيل القسري يتم تنظيف الذاكرة بالكامل
              await ZyiarahFirebaseService().signOut();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(exists
                      ? 'تم تعطيل حسابك من قبل الإدارة.'
                      : 'لم يعد حسابك مسجّلاً كسائق.'),
                  backgroundColor: Colors.red,
                ),
              );
              context.go('/login');
            });
            return Scaffold(
              body: Center(
                child: Text(exists
                    ? 'تم حظر أو تعطيل حسابك.'
                    : 'لم يعد حسابك مسجّلاً كسائق.'),
              ),
            );
          }
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            body: IndexedStack(
              index: _currentIndex,
              children: [
                // Tab 0: Home dashboard
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: CustomScrollView(
                    slivers: [
                      _buildAppBar(),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMainSection(),
                              const SizedBox(height: 25),
                              _buildStatsRow(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tab 1: Tasks history
                const DriverTasksScreen(),
                // Tab 2: Notifications
                const DriverNotificationsScreen(),
                // Tab 3: Profile
                DriverProfileScreen(onLogout: _performLogout),
              ],
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF660033),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(right: 20, bottom: 16),
        title: Text(
          "مرحباً، $_driverName",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF660033), Color(0xFF8E2B5C)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
        ),
      ),
      actions: [
        // مؤشّر ثابت — السائق متصل دائماً (لا مفتاح فصل يوقف الطلبات بالخطأ).
        Container(
          margin: const EdgeInsets.only(left: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFF34D399), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('متصل',
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = i);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF660033),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle:
            GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.tajawal(fontSize: 11),
        backgroundColor: Colors.white,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.task_outlined),
            activeIcon: Icon(Icons.task),
            label: 'مهامي',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'الإشعارات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'حسابي',
          ),
          // تبويب «المالية/الراتب» أُزيل — السائقون موظفون براتب شهري يُدار خارج التطبيق.
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تسجيل الخروج',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text('هل تريد بالتأكيد تسجيل الخروج من التطبيق؟',
              style: GoogleFonts.tajawal()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('إلغاء', style: GoogleFonts.tajawal())),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('نعم، خروج',
                    style: GoogleFonts.tajawal(color: Colors.red))),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    HapticFeedback.lightImpact();
    _stopSync();
    // الخروج المركزي (B3): تنظيف كامل للذاكرة بدل FirebaseAuth.signOut() المباشرة
    await ZyiarahFirebaseService().signOut();
    if (mounted) context.go('/login');
  }

  // (تدقيق السائق) إحصاءات الإكمال من نافذة محدودة بدل بثّ **كل** الطلبات المكتملة
  // مدى الحياة (كان يُنزّل كل المستندات كاملةً عند كل فتح وتتضخم الكلفة مع الزمن).
  // النافذة: من بداية الشهر بهامش 45 يوماً للخلف (حجوزات أُنشئت قبل شهر إكمالها)
  // بحدّ 500 مستند، ثم تُحتسب اليوم/الأسبوع/الشهر محلياً من end_time. يخدمها فهرس
  // (driver_id, created_at) القائم — count() تجميعي على مدى end_time كان يحتاج
  // فهرساً مركّباً (driver_id, status, end_time) غير موجود.
  Future<List<int>>? _statsFuture;

  Future<List<int>> _loadStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // يُقتطع لمنتصف الليل أولاً — بدونه يبدأ الأسبوع من ساعة اللحظة الحالية،
    // فتُحتسب إكمالات الصباح الباكر من اليوم نفسه ناقصةً.
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final windowStart = monthStart.subtract(const Duration(days: 45));

    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .where('driver_id', isEqualTo: _currentDriverId)
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .orderBy('created_at', descending: true)
        .limit(500)
        .get();

    int todayTasks = 0, weeklyTasks = 0, monthlyTasks = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['status'] != 'completed') continue;
      final endTime = (data['end_time'] as Timestamp?)?.toDate();
      if (endTime == null) continue;
      if (endTime.isAfter(todayStart)) todayTasks++;
      if (endTime.isAfter(weekStart)) weeklyTasks++;
      if (endTime.isAfter(monthStart)) monthlyTasks++;
    }
    return [todayTasks, weeklyTasks, monthlyTasks];
  }

  Widget _buildStatsRow() {
    if (_currentDriverId == null) return const SizedBox.shrink();
    _statsFuture ??= _loadStats();

    return FutureBuilder<List<int>>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // لا أصفار كاذبة عند الفشل (كانت تُعرض "0" فيظنّ السائق سجلّه صُفّر) —
          // لافتة خطأ حمراء + إعادة المحاولة.
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تعذّر تحميل الإحصاءات',
                      style: GoogleFonts.tajawal(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800)),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _statsFuture = _loadStats()),
                  child: Text('إعادة المحاولة',
                      style: GoogleFonts.tajawal(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        final s = snapshot.data;
        return Row(
          children: [
            _buildCompactStat("اليوم", s == null ? "—" : "${s[0]}",
                Icons.today_outlined, Colors.blue),
            const SizedBox(width: 10),
            _buildCompactStat("الأسبوع", s == null ? "—" : "${s[1]}",
                Icons.date_range_outlined, Colors.green),
            const SizedBox(width: 10),
            _buildCompactStat("الشهر", s == null ? "—" : "${s[2]}",
                Icons.calendar_month_outlined, Colors.orange),
          ],
        );
      },
    );
  }

  Widget _buildCompactStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
            Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSection() {
    // مصدر واحد لكل مهام السائق: المهمة الحالية بالأعلى (بطاقة التركيز) ثم
    // القادمة أسفلها — بلا تكرار. كان جدولٌ كامل + بطاقة نشطة منفصلة يعرضان
    // المهمة نفسها مرتين بشكلين مختلفين (لخبطة السائق)، ومفتاح «أوفلاين» يُخفي
    // كل شيء. الآن: تسلسلٌ واضح، والسائق متصل دائماً.
    return StreamBuilder<QuerySnapshot>(
      // (#42) فلترة الحالة على الخادم بدل جلب كل تاريخ طلبات السائق (مكتملة/ملغاة/
      // مرفوضة مدى الحياة) ثم تصفيتها محلياً. المجموعة الخماسية هي مجموعة الحالات
      // النشطة المعتمَدة في التطبيق كله. لا orderBy (يُسقط ما لا يحمل service_date؛
      // الترتيب محلي عبر _focusRank/slotOf). يخدمها فهرس (driver_id, status) القائم.
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driver_id', isEqualTo: _currentDriverId)
          .where('status', whereIn: const [
            'assigned', 'scheduled', 'accepted', 'on_the_way', 'in_progress',
          ])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildStatusPlaceholder(Icons.error_outline,
              "تعذّر تحميل مهامك", "تحقّق من الاتصال وحاول مجدداً");
        }
        if (!snapshot.hasData) {
          return _buildStatusPlaceholder(
              Icons.hourglass_empty, "جارٍ تحميل مهامك", "لحظات من فضلك");
        }
        // مع فلتر whereIn الخادمي أعلاه صار هذا لا-عمليّة غير ضارّة (الحالات الخمس
        // المسموحة لا تتقاطع مع المنتهية الثلاث) — نُبقيه ليبقى المعروض برهاناً مجموعةً
        // جزئيةً من السابق، لا كشبكة أمان (تصفية بعد الاستعلام تُزيل فقط، لا تُعيد).
        final active = snapshot.data!.docs.where((d) {
          final st = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return st != 'completed' && st != 'cancelled' && st != 'rejected';
        }).toList();

        if (active.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _stopSync());
          return _buildStatusPlaceholder(
              Icons.event_available,
              "لا توجد مهام حالياً",
              "ستصلك المهمة فور إسنادها — ويصلك إشعار بكل طلب جديد");
        }

        // المهمة محل التركيز: الأكثر تقدّماً (قيد التنفيذ ← في الطريق ← مجدولة)
        final sorted = [...active]
          ..sort((a, b) => _focusRank(a).compareTo(_focusRank(b)));
        final focus = sorted.first;
        final focusStatus =
            (focus.data() as Map<String, dynamic>)['status'] as String? ?? '';
        if (focusStatus == 'on_the_way' ||
            focusStatus == 'in_progress' ||
            focusStatus == 'accepted') {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _startSync(focus.id));
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) => _stopSync());
        }

        final upcoming = active.where((d) => d.id != focus.id).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActivePipeline(focus),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 26),
              _buildUpcomingList(upcoming),
            ],
          ],
        );
      },
    );
  }

  // ترتيب أولوية التركيز بين مهام السائق غير المكتملة
  int _focusRank(QueryDocumentSnapshot doc) {
    final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? '';
    const order = {'in_progress': 0, 'on_the_way': 1, 'accepted': 1, 'scheduled': 2};
    return order[status] ?? 3;
  }

  // ─────────────────────────────────────────────
  // DAILY ROUTE MANIFEST (جدول الرحلات اليومي)
  // ─────────────────────────────────────────────
  // جدول المهام القادمة للسائق مقسّماً حسب الأيام (Upcoming Tasks)
  /// المهام القادمة (باستثناء المهمة الحالية المعروضة بالأعلى) مجمّعة بالأيام.
  /// عرضٌ خالص بلا تيار — يستقبل القائمة من [_buildMainSection] (مصدر واحد).
  Widget _buildUpcomingList(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final tomorrowKey =
        DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

    final tasks = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      String dayKey = data['booking_date'] as String? ?? '';
      if (dayKey.isEmpty) {
        final sd = (data['service_date'] as Timestamp?)?.toDate();
        if (sd != null) dayKey = DateFormat('yyyy-MM-dd').format(sd);
      }
      if (dayKey.isEmpty) dayKey = todayKey; // افتراضي عند غياب التاريخ
      tasks.add({'id': doc.id, 'data': data, 'dayKey': dayKey});
    }
    if (tasks.isEmpty) return const SizedBox.shrink();

    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final t in tasks) {
      byDay.putIfAbsent(t['dayKey'] as String, () => []).add(t);
    }
    final sortedDays = byDay.keys.toList()..sort();

    String slotOf(Map<String, dynamic> d) =>
        d['booking_time_slot'] as String? ??
        (d['service_date'] as Timestamp?)?.toDate().toIso8601String() ??
        '';
    String dayLabel(String key) {
      if (key == todayKey) return 'اليوم';
      if (key == tomorrowKey) return 'غداً';
      return key;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_rounded,
                color: Color(0xFF660033), size: 20),
            const SizedBox(width: 8),
            Text('مهامك القادمة',
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF1E293B))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF660033).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${tasks.length}',
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF660033))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final day in sortedDays) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF660033),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(dayLabel(day),
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: const Color(0xFF660033))),
              ],
            ),
          ),
          ...(byDay[day]!
                ..sort((a, b) => slotOf(a['data'] as Map<String, dynamic>)
                    .compareTo(slotOf(b['data'] as Map<String, dynamic>))))
              .map((t) => _buildManifestOrderCard(
                  t['id'] as String, t['data'] as Map<String, dynamic>)),
        ],
      ],
    );
  }

  // تسمية عربية لحالة المهمة (نموذج التوزيع المباشر)
  String _statusLabelAr(String status) {
    switch (status) {
      case 'scheduled':
        return 'مجدولة';
      case 'on_the_way':
      case 'accepted':
        return 'في الطريق';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مكتملة';
      default:
        return status;
    }
  }

  /// تفصيل طلب العميل كما يحتاجه السائق: الموقع + عدد العاملات (للساعية) أو
  /// تفصيل الخدمة (نوع/عدد للمكيفات/الكنب/السيارة). في بطاقة التركيز (compact=false)
  /// يُضاف اسم الخدمة نفسه. مصدرٌ واحد لكل بطاقات السائق كي لا يخلط أو ينسى.
  Widget _orderDetailStrip(Map<String, dynamic> data, {bool compact = false}) {
    final rows = <Widget>[];
    if (!compact) {
      final service =
          (data['service_name'] ?? data['service_type'] ?? 'خدمة زيارة')
              .toString();
      rows.add(_detailRow(Icons.cleaning_services_rounded, service,
          const Color(0xFF1E293B),
          bold: true));
    }
    final zone = data['zone_name'];
    if (zone is String && zone.trim().isNotEmpty) {
      rows.add(_detailRow(
          Icons.location_on_outlined, zone, const Color(0xFF475569)));
    }
    // خدمةٌ ذات تفصيل (مكيفات/كنب/سيارة): اعرض ملخّصه. وإلّا (ساعية): عدد العاملات.
    if (data['service_meta'] != null) {
      final m = zyiarahServiceMetaSummary(data['service_meta']);
      if (m != null) {
        rows.add(
            _detailRow(Icons.list_alt_rounded, m, const Color(0xFF660033)));
      }
    } else {
      final w = _workersLabel(data['worker_count']);
      if (w.isNotEmpty) {
        rows.add(_detailRow(
            Icons.groups_2_outlined, w, const Color(0xFF475569)));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _detailRow(IconData icon, String text, Color color,
          {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: color,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  /// عدد العاملات بصيغة عربية سليمة (مفرد/مثنّى/جمع).
  String _workersLabel(dynamic wc) {
    final n = (wc is num) ? wc.toInt() : int.tryParse('${wc ?? ''}') ?? 0;
    if (n <= 0) return '';
    if (n == 1) return 'عاملة واحدة';
    if (n == 2) return 'عاملتان';
    if (n <= 10) return '$n عاملات';
    return '$n عاملة';
  }

  Widget _buildManifestOrderCard(String orderId, Map<String, dynamic> data) {
    // Resolve time slot display
    // عرض 12 ساعة — المخزَّن يبقى "HH:00" لأن الدالة الخادمية تحلّله لحساب السعة.
    String timeSlot = formatSlot12(data['booking_time_slot'] as String?);
    if (timeSlot.isEmpty) {
      final sd = (data['service_date'] as Timestamp?)?.toDate();
      if (sd != null) {
        timeSlot = formatHour12(sd.hour);
      }
    }

    final String serviceName =
        data['service_name'] ?? data['service_type'] ?? 'خدمة زيارة';
    final String clientPhone = data['client_phone'] ?? data['user_phone'] ?? '';
    final String clientName = data['client_name'] ?? 'العميل';
    final String status = data['status'] ?? 'pending';
    final GeoPoint? location = data['location'] as GeoPoint?;

    // لون شارة الحالة (نموذج التوزيع المباشر)
    final Color statusColor = status == 'in_progress'
        ? Colors.green
        : (status == 'on_the_way' || status == 'accepted')
            ? Colors.blue
            : status == 'scheduled'
                ? const Color(0xFF660033)
                : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Time slot badge
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(Icons.schedule, color: statusColor, size: 16),
                const SizedBox(height: 4),
                Text(
                  timeSlot.isNotEmpty ? timeSlot : '--:--',
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Order details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  clientName,
                  style: GoogleFonts.tajawal(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                // تفصيل الطلب على البطاقة نفسها كي لا يخلط السائق أو ينسى:
                // الموقع + عدد العاملات (للساعية) أو تفصيل الخدمة (نوع/عدد).
                _orderDetailStrip(data, compact: true),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabelAr(status),
                    style: GoogleFonts.tajawal(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Action buttons: call + map
          Column(
            children: [
              if (clientPhone.isNotEmpty)
                InkWell(
                  onTap: () => _callClient(clientPhone),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.phone, color: Colors.green.shade700, size: 18),
                  ),
                ),
              if (location != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _openMaps(location),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.map_outlined, color: Colors.blue.shade700, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivePipeline(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'];
    final orderId = doc.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // High-visibility focus banner — Active Order Focus
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                (status == 'scheduled' || status == 'assigned') ? "مهمتك القادمة — استعد للانطلاق" : "مهمة نشطة — يُرجى التركيز",
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange.shade900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildStateGuidedCard(orderId, data, status),
      ],
    );
  }

  Widget _buildStateGuidedCard(String id, Map<String, dynamic> data, String status) {
    String stateTitle = "";
    String actionLabel = "";
    String nextStatus = "";
    Color stateColor = const Color(0xFF660033);
    IconData stateIcon = Icons.directions_car;

    switch (status) {
      case 'assigned':
        // 'assigned' تُكتب يدوياً من لوحة الأدمن، وقواعد Firestore لا تسمح للسائق
        // بتعديل طلبٍ عليها (قائمة الحالات في allow update تستثنيها) — فكانت
        // البطاقة تعرض زرّاً بلا نصّ يستدعي _updateStatus بحالة "" وتُرفض الكتابة
        // برسالة «تحقق من اتصالك» المضلِّلة. نعرض حالة انتظارٍ صريحة بلا زرّ
        // (nextStatus فارغة عمداً) حتى تُحوِّلها الإدارة إلى «مجدولة».
        stateTitle = "مهمة مُسنَدة إليك — بانتظار الجدولة";
        stateColor = Colors.orange.shade800;
        stateIcon = Icons.assignment_ind_outlined;
        break;
      case 'scheduled':
        stateTitle = "مهمة مجدولة — جاهز للانطلاق";
        actionLabel = "اضغط مطولاً — أنا في الطريق";
        nextStatus = "on_the_way";
        stateColor = const Color(0xFF660033);
        stateIcon = Icons.event_available;
        break;
      case 'on_the_way':
      case 'accepted': // توافق مع الطلبات الجارية أثناء الانتقال
        stateTitle = "في الطريق للعميل";
        actionLabel = "اضغط مطولاً — وصلت، بدء الخدمة";
        nextStatus = "in_progress";
        stateColor = Colors.blue;
        stateIcon = Icons.map;
        break;
      case 'in_progress':
        stateTitle = "الخدمة قيد التنفيذ";
        actionLabel = "اضغط مطولاً — إتمام المهمة";
        nextStatus = "completed";
        stateColor = Colors.green;
        stateIcon = Icons.timer;
        break;
    }

    final clientName = data['client_name'] ?? 'بدون اسم';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: stateColor.withValues(alpha: 0.25), width: 2.5),
        boxShadow: [BoxShadow(color: stateColor.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status header — large, high-contrast, fat-finger-friendly layout
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: stateColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(stateIcon, color: stateColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stateTitle, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: stateColor, fontSize: 16)),
                    const SizedBox(height: 3),
                    // Large client name for field readability
                    Text(clientName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.black87)),
                    // موعد المهمة — كان يظهر فقط على بطاقات القائمة لا على بطاقة
                    // التركيز، فالسائق يرى «مهمة مجدولة» بلا وقتها. نعرضه هنا صراحةً.
                    Builder(builder: (_) {
                      String t = formatSlot12(data['booking_time_slot'] as String?);
                      if (t.isEmpty) {
                        final sd = (data['service_date'] as Timestamp?)?.toDate();
                        if (sd != null) t = formatHour12(sd.hour);
                      }
                      final bd = data['booking_date'] as String?;
                      final parts = [if (bd != null) bd, if (t.isNotEmpty) t];
                      if (parts.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule, size: 14, color: stateColor),
                          const SizedBox(width: 5),
                          Text(parts.join('  •  '),
                              style: GoogleFonts.tajawal(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: stateColor)),
                        ]),
                      );
                    }),
                    if ((status == 'accepted' || status == 'on_the_way' || status == 'scheduled') && data['location'] is GeoPoint)
                      _buildDistanceInfo(data['location'] as GeoPoint),
                  ],
                ),
              ),
              // نُظهر زر «خرائط» فقط حين يوجد موقع فعلي — كان _openMaps يرجع بصمت
              // عند غياب الموقع فيبدو الزر معطّلاً بلا أي ردّ فعل للسائق.
              if (data['location'] is GeoPoint)
                TextButton.icon(
                  onPressed: () => _openMaps(data['location']),
                  icon: const Icon(Icons.directions, color: Colors.blue, size: 24),
                  label: Text("خرائط", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          // شريط تفصيل الطلب: الخدمة + الموقع + عدد العاملات — كي يستوعب السائق
          // طلب العميل ولا يخلط أو ينسى. (بطاقة التركيز كانت تُظهر اسم العميل
          // والحالة فقط، بلا أي ذكر لأيّ خدمةٍ هي ولا أين.)
          _orderDetailStrip(data),
          const SizedBox(height: 12),
          // تفصيل الخدمة: كم قطعة ومقاسها / كم مكيفاً ونوعه. كان السائق يصل ولا يعرف
          // ما يحمل من عُدّة — الطلب يحمل مبلغاً واسم خدمة فقط.
          ZyiarahServiceMetaView(meta: data['service_meta']),
          _buildHouseRulesAlert(data),
          if (data['client_id'] != null) const Divider(height: 28),
          if (status == 'in_progress' && data['start_time'] is Timestamp)
            _buildTimer((data['start_time'] as Timestamp).toDate(),
                int.tryParse('${data['hours_contracted'] ?? 4}') ?? 4),
          const SizedBox(height: 8),
          // DRIVER-001/008: swipe-to-confirm replaces tap button — prevents accidental triggers
          // حارس: لا زرّ إلا بوجود انتقالٍ فعلي — أي حالة بلا nextStatus (مثل
          // 'assigned') كانت تُنتج زرّاً فارغاً يفشل دائماً عند التأكيد.
          if (nextStatus.isNotEmpty)
            _HoldToActButton(
              label: actionLabel,
              color: stateColor,
              isLoading: _isUpdatingStatus,
              onConfirmed: () => _updateStatus(id, nextStatus),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stateColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                "بانتظار تأكيد الجدولة من الإدارة — يظهر زر الانطلاق فور تحويل المهمة إلى «مجدولة»",
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: stateColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          const SizedBox(height: 14),
          // DRIVER-003: safe phone call — fake fallback removed
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () {
                  final phone = data['client_phone'] as String?;
                  if (phone != null && phone.isNotEmpty) {
                    _callClient(phone);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('رقم العميل غير متوفر')),
                    );
                  }
                },
                icon: const Icon(Icons.phone, size: 16),
                label: const Text("اتصال بالعميل"),
              ),
              const SizedBox(width: 15),
              TextButton.icon(
                onPressed: () => _reportIssue(id),
                icon: const Icon(Icons.support_agent, size: 16, color: Colors.redAccent),
                label: const Text("بلاغ للإدارة", style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// قوانين البيت من حقل الطلب نفسه — الدالة الخادمية تنسخ house_rules من مستند
  /// العميل إلى الطلب عند الإسناد. القراءة المباشرة لـ users/{clientId} مرفوضة
  /// بقواعد Firestore للسائق فكانت اللوحة تُخفى دائماً (فشل الجلب = لا بيانات).
  /// عند غياب الحقل (طلبات قديمة قبل النسخ) تُخفى بصمت — لا شيء يُعرض خطأً.
  Widget _buildHouseRulesAlert(Map<String, dynamic> orderData) {
    final rules = (orderData['house_rules'] as String?)?.trim();
    if (rules == null || rules.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                "قوانين البيت وتفضيلات العميل:",
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(rules, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo(GeoPoint clientLoc) {
    // قبل منح الإذن (أو عند رفضه) اعرض زر تفعيل بدل الصمت/الانهيار.
    if (!_hasLocationStream) {
      return TextButton.icon(
        onPressed: _ensureLocationPermission,
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
        icon: const Icon(Icons.location_on_outlined, size: 15, color: Colors.redAccent),
        label: Text(
          _locationDenied ? 'إذن الموقع مرفوض — اضغط للتفعيل' : 'فعّل إذن الموقع لتتبّع الوصول',
          style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
      );
    }
    return StreamBuilder<Position>(
      // مصدرٌ واحد دائماً: ناقل بثّ يغذّيه تدفّق الموقع الوحيد (خفيف أو تتبّع).
      stream: _posHub.stream,
      builder: (context, snapshot) {
        // DRIVER-006: GPS permission revoked — visible alert, not silent collapse
        if (snapshot.hasError) {
          return const Text(
            "⚠️ تعذّر تتبع موقعك — تحقق من إذن الموقع",
            style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();

        final pos = snapshot.data!;
        double dist = _coreService.getDistanceInMeters(pos.latitude, pos.longitude, clientLoc.latitude, clientLoc.longitude);
        String formatted = _coreService.getFormattedDistance(dist);

        if (dist <= 2000 && _activeOrderId != null) {
          _checkAndNotifyProximity(_activeOrderId!, clientLoc);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("على بعد: $formatted", style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildMiniMap(pos, clientLoc),
          ],
        );
      },
    );
  }

  // حارس محلي ضد التكرار: تُستدعى الدالة من داخل build عند كل موقع بينما المسافة
  // ≤ 2كم، وعلم المستند (proximity_notified) يُكتب بعد قراءةٍ غير متزامنة فتنطلق
  // عدة نداءات قبل ضبطه. المجموعة تمنع التكرار فوراً في هذه الجلسة.
  final Set<String> _proximityChecked = {};

  Future<void> _checkAndNotifyProximity(String orderId, GeoPoint target) async {
    if (_proximityChecked.contains(orderId)) return;
    _proximityChecked.add(orderId);
    try {
      final docRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
      final doc = await docRef.get();
      final data = doc.data();

      if (data != null && data['proximity_notified'] != true) {
        await docRef.update({'proximity_notified': true});
        final clientId = data['client_id'] ?? '';
        if (clientId.isNotEmpty) {
          await _notificationService.triggerNotification(
            toUid: clientId,
            title: "السائق يقترب! 🚙",
            body: "السائق أصبح على بعد أقل من 2 كم من موقعك. استعد لاستلام الخدمة.",
            type: 'driver_near',
            data: {'orderId': orderId},
          );
        }
      }
    } catch (e) {
      debugPrint("Proximity notify error: $e");
    }
  }

  Widget _buildMiniMap(Position driverPos, GeoPoint clientLoc) {
    final driverLatLng = LatLng(driverPos.latitude, driverPos.longitude);
    final clientLatLng = LatLng(clientLoc.latitude, clientLoc.longitude);
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: driverLatLng,
            initialZoom: 13.0,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.zyiarah.zyiarah'),
            MarkerLayer(markers: [
              Marker(point: driverLatLng, width: 30, height: 30, child: const Icon(Icons.directions_car, color: Colors.blue, size: 30)),
              Marker(point: clientLatLng, width: 30, height: 30, child: const Icon(Icons.location_on, color: Colors.red, size: 30)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPlaceholder(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(children: [
          Icon(icon, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.grey[600])),
          Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[400])),
        ]),
      ),
    );
  }

  Widget _buildTimer(DateTime startedAt, int hours) {
    return Column(children: [
      const Text("مدة الخدمة المنقضية", style: TextStyle(fontSize: 10, color: Colors.grey)),
      StreamBuilder<Duration>(
        stream: _coreService.elapsedSinceStream(startedAt),
        builder: (context, snapshot) {
          final d = snapshot.data ?? Duration.zero;
          final time = ZyiarahCoreService.formatElapsed(d);
          // عدٌّ تصاعديّ: نُلوّن أحمر عند تجاوز مدّة العقد (تخطٍّ للوقت المتوقَّع) —
          // موثوق لأن مرساة البدء صارت خادميّة (start_time == request.time بالقواعد).
          final timerColor = d.inSeconds > hours * 3600
              ? Colors.redAccent
              : const Color(0xFF660033);
          return Text(time, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: timerColor));
        },
      ),
      const SizedBox(height: 15),
    ]);
  }

  void _reportIssue(String orderId) async {
    final message = "بلاغ عن الطلب #$orderId: لدي مشكلة في هذا الطلب — السائق: $_currentDriverId";
    String? adminPhone;
    try {
      final configDoc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
      adminPhone = (configDoc.data()?['support_whatsapp'] ?? configDoc.data()?['admin_whatsapp'])?.toString();
    } catch (_) {
      // قراءة فاشلة (أوفلاين غالباً) — نُبلغ أدناه بدل المتابعة برقم وهمي
    }
    // كان الرقم الوهمي 966500000000 قيمةً افتراضية عند فشل القراءة أو غياب
    // الحقلين، فيفتح واتساب على محادثة لا تصل الإدارة أبداً والبلاغ يضيع بصمت.
    if (adminPhone == null || adminPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر جلب رقم الدعم — حاول لاحقاً', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    final url = "https://wa.me/$adminPhone?text=${Uri.encodeComponent(message)}";
    await _openExternalUrl(url, failMessage: 'تعذّر فتح واتساب — تأكد من تثبيته');
  }

  // DRIVER-001: try/catch + double-tap guard via _isUpdatingStatus
  void _updateStatus(String id, String status) async {
    if (_isUpdatingStatus) return;
    setState(() => _isUpdatingStatus = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('orders').doc(id).get();
      final data = doc.data();
      if (data == null) return;


      // (جيوفنس متساهل) عند الإكمال: لو GPS متاح وموقع الطلب معروف والمسافة > 1كم،
      // امنع (احتيال صارخ). fail-open: إذنٌ مرفوض/لا GPS/لا موقع → اسمح دون منع.
      // نسجّل المسافة على الطلب دائماً (completed_distance_m) لمراجعة الإدارة.
      double? completionDistanceM;
      if (status == 'completed') {
        final GeoPoint? loc = data['location'] as GeoPoint?;
        if (loc != null) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
            ).timeout(const Duration(seconds: 8));
            completionDistanceM = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, loc.latitude, loc.longitude);
            if (completionDistanceM > 1000 && pos.accuracy <= 100) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    'أنت بعيد عن موقع الخدمة (${(completionDistanceM / 1000).toStringAsFixed(1)} كم). اقترب من الموقع لإتمام الطلب.',
                    style: GoogleFonts.tajawal()),
                  backgroundColor: Colors.red.shade800,
                  behavior: SnackBarBehavior.floating,
                ));
              }
              return; // امنع الإكمال — finally يُعيد ضبط _isUpdatingStatus
            }
          } catch (_) {
            // fail-open: تعذّر تحديد الموقع (إذن مرفوض/مهلة) → لا نمنع الإكمال
          }
        }
      }

      // الدفع عند الاستلام أُزيل من الجذور بطلب المالك: لا يقبله العميل.
      // كان هنا: توليد رمز 4 أرقام يُكتب على الطلب، وحوار يُدخله السائق، ثم دمج
      // is_paid/cash_confirmed داخل Transaction الإكمال، وإشعار الإدارة بالتحصيل.
      // الدفع الآن مقدَّم دائماً (بطاقة/Apple Pay/STC/تمارا/تابي/محفظة)، فالطلب يصل
      // السائق مدفوعاً ولا شيء يُحصَّل يدوياً.

      // (C) Transaction واحد ذرّي: الحالة + دفع COD معاً. يفشل بالكامل دون اتصال،
      // فلا يبقى الطلب "مدفوعاً وغير مكتمل" ولا العكس.
      final Map<String, dynamic> extraUpdates = {};
      if (completionDistanceM != null) {
        extraUpdates['completed_distance_m'] = completionDistanceM.round();
      }
      await _orderService.updateOrderStatus(id, status,
          driverId: _currentDriverId,
          extraOrderUpdates: extraUpdates.isEmpty ? null : extraUpdates);

      if (data['client_id'] != null) {
        final orderCode = data['code'] ?? id;
        await _notificationService.notifyClientOfDriverStatus(
          clientId: data['client_id'],
          status: status,
          orderCode: orderCode,
          driverName: _driverName,
          orderId: id,
        );
        if (status == 'accepted' || status == 'completed') {
          await _notificationService.notifyAdminOfDriverUpdate(
            driverName: _driverName,
            status: status,
            orderCode: orderCode,
          );
        }
      }

      // إعادة تحميل الإحصاءات بعد الإكمال — صارت جلبة واحدة مخبّأة لا بثّاً حيّاً،
      // فبدون التصفير تبقى أرقام اليوم/الأسبوع/الشهر قديمة حتى إعادة فتح اللوحة.
      if (status == 'completed') _statsFuture = null;

      // (C) Optimistic UI: لا تُعرض Lottie إلا بعد نجاح Transaction الإكمال فعلياً.
      // الـ Transaction يفشل دون اتصال (يرمي استثناءً) فينتقل للـ catch بلا نجاح كاذب.
      if (status == 'completed' && mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحديث الحالة، تحقق من اتصالك بالإنترنت', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      // PopScope: زر الرجوع (أندرويد) يتجاوز barrierDismissible ويُغلق الحوار،
      // فكان pop المؤجَّل بعد 3 ثوانٍ يُسقط ما تحته — مسار اللوحة نفسها (الجذر).
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded, size: 120, color: Colors.white),
            const SizedBox(height: 10),
            Text('تمت المهمة بنجاح', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      // canPop حزام أمان إضافي: لا نُسقط إلا إذا كان فوق الجذر شيء (الحوار).
      if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
    });
  }

  void _openMaps(dynamic loc) async {
    if (loc is! GeoPoint) return;
    final url = 'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}';
    await _openExternalUrl(url, failMessage: 'تعذّر فتح الخرائط');
  }

  void _callClient(String phone) async {
    await _openExternalUrl('tel:$phone', failMessage: 'تعذّر فتح الاتصال — الرقم: $phone');
  }

  /// فتح رابط خارجي مع إبلاغ مرئي عند الفشل — نفس معالجة driver_profile_screen:
  /// كان `if (await canLaunchUrl(...)) await launchUrl(...)` يفشل بصمت تماماً
  /// (canLaunchUrl يُرجع false زائفاً على iOS بلا LSApplicationQueriesSchemes)
  /// فيظنّ السائق الزرّ معطّلاً.
  Future<void> _openExternalUrl(String url, {String? failMessage}) async {
    final uri = Uri.parse(url);
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failMessage ?? 'تعذّر فتح الرابط', style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
    }
  }
}

/// Hold-to-confirm button — deliberate action that works identically on touch
/// and on mouse/web. Replaces a swipe whose 82%-of-track threshold became an
/// ~950px mouse drag on a wide desktop track (the "button does nothing" report):
/// hold-to-confirm is width-independent — press and hold ~0.7s to fire.
class _HoldToActButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onConfirmed;
  final bool isLoading;

  const _HoldToActButton({
    required this.label,
    required this.color,
    required this.onConfirmed,
    required this.isLoading,
  });

  @override
  State<_HoldToActButton> createState() => _HoldToActButtonState();
}

class _HoldToActButtonState extends State<_HoldToActButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addStatusListener((st) {
      if (st == AnimationStatus.completed && !_fired) {
        _fired = true;
        HapticFeedback.heavyImpact();
        widget.onConfirmed();
      }
    });
  bool _fired = false;

  @override
  void didUpdateWidget(_HoldToActButton old) {
    super.didUpdateWidget(old);
    // بعد انتهاء العملية (نجاح/فشل) أعد الزر لوضع السكون.
    if (old.isLoading && !widget.isLoading) {
      _fired = false;
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _startHold() {
    if (widget.isLoading || _fired) return;
    _c.forward();
  }

  void _cancelHold() {
    if (_fired) return;
    _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // onTapDown/Up (لا سحب) — يعمل بنفس السلوك على الفأرة واللمس، ولا يتنازعه
    // تمرير القائمة العمودي كما كان السحب الأفقي على الويب.
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: SizedBox(
        height: 60,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: widget.color.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
                // تعبئة تنمو من جهة البداية (يمين في RTL) مع تقدّم الضغط المطوّل.
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: _c.value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                widget.isLoading
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            color: widget.color, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app_rounded,
                              color: widget.color, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.label,
                              style: GoogleFonts.tajawal(
                                  color: widget.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}
