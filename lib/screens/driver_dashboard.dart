import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:math';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:go_router/go_router.dart';
import 'package:zyiarah/screens/driver_tasks_screen.dart';
import 'package:zyiarah/screens/driver_notifications_screen.dart';
import 'package:zyiarah/screens/driver_profile_screen.dart';
import 'package:zyiarah/screens/driver_earnings_screen.dart';

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
  bool _isOnline = true;
  String? _currentDriverId;
  String? _activeOrderId;
  String _driverName = 'السائق';

  // DRIVER-001: guard against double-tap on status update
  bool _isUpdatingStatus = false;
  // DRIVER-002: track which order is being accepted
  String? _acceptingOrderId;

  @override
  void initState() {
    super.initState();
    _currentDriverId = _auth.currentUser?.uid;
    _syncOnlineStatus();
    // DRIVER-005/007: single stable stream initialized once with battery-efficient settings
    _locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  Future<void> _syncOnlineStatus() async {
    if (_currentDriverId == null) return;
    final doc = await FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId).get();
    if (!mounted) return;
    final data = doc.data();
    setState(() {
      _isOnline = data?['is_available'] as bool? ?? true;
      _driverName = data?['name'] as String? ?? 'السائق';
    });
  }

  Timer? _syncTimer;

  // DRIVER-005/007: stream created once, reused across rebuilds
  late final Stream<Position> _locationStream;

  void _startSync(String orderId) {
    if (_syncTimer != null && _activeOrderId == orderId) return;
    _stopSync();
    _activeOrderId = orderId;
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        Position pos = await Geolocator.getCurrentPosition();
        await _orderService.updateDriverLocation(orderId, GeoPoint(pos.latitude, pos.longitude));
      } on PermissionDeniedException {
        // DRIVER-006: GPS permission revoked mid-session — stop timer and alert driver
        timer.cancel();
        _syncTimer = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ تعطّل التتبع — إذن الموقع مسحوب. يُرجى إعادة تشغيل التطبيق لاستئناف الخدمة.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
      } catch (e) {
        debugPrint("Location sync error: $e");
      }
    });
  }

  void _stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _activeOrderId = null;
  }

  @override
  void dispose() {
    _stopSync();
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
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final isActive = data['is_active'] ?? true;

          if (!isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تعطيل حسابك من قبل الإدارة.'), backgroundColor: Colors.red),
              );
              context.go('/login');
            });
            return const Scaffold(body: Center(child: Text("تم حظر أو تعطيل حسابك.")));
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
                              _buildStatsRow(),
                              const SizedBox(height: 25),
                              _buildMainSection(),
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
                // Tab 4: Earnings
                const DriverEarningsScreen(),
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
      backgroundColor: const Color(0xFF5D1B5E),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(right: 20, bottom: 16),
        title: Text(
          "لوحة التحكم",
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5D1B5E), Color(0xFF7E3080)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              Text(
                _isOnline ? "متصل" : "أوفلاين",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              Switch(
                value: _isOnline,
                onChanged: (val) async {
                  setState(() => _isOnline = val);
                  // DRIVER-004: cancel sync timer immediately when going offline
                  if (!val) _stopSync();
                  if (_currentDriverId != null) {
                    await FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId).update({
                      'is_available': val,
                      'status': val ? 'idle' : 'off',
                    });
                  }
                },
                activeThumbColor: Colors.greenAccent,
                inactiveThumbColor: Colors.grey[400],
              ),
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
        selectedItemColor: const Color(0xFF5D1B5E),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'المالية',
          ),
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
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/login');
  }

  // DRIVER-009: error state returns zero values instead of silent crash
  Widget _buildStatsRow() {
    if (_currentDriverId == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driver_id', isEqualTo: _currentDriverId)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, allSnapshot) {
        if (allSnapshot.hasError) {
          return Row(
            children: [
              _buildCompactStat("اليوم", "0", Icons.today_outlined, Colors.blue),
              const SizedBox(width: 10),
              _buildCompactStat("الأسبوع", "0", Icons.date_range_outlined, Colors.green),
              const SizedBox(width: 10),
              _buildCompactStat("الشهر", "0", Icons.calendar_month_outlined, Colors.orange),
            ],
          );
        }

        final allOrders = allSnapshot.data?.docs ?? [];

        int todayTasks = 0, weeklyTasks = 0, monthlyTasks = 0;
        for (final doc in allOrders) {
          final data = doc.data() as Map<String, dynamic>;
          final endTime = (data['end_time'] as Timestamp?)?.toDate();
          if (endTime == null) continue;
          if (endTime.isAfter(todayStart)) todayTasks++;
          if (endTime.isAfter(weekStart)) weeklyTasks++;
          if (endTime.isAfter(monthStart)) monthlyTasks++;
        }

        return Row(
          children: [
            _buildCompactStat("اليوم", "$todayTasks", Icons.today_outlined, Colors.blue),
            const SizedBox(width: 10),
            _buildCompactStat("الأسبوع", "$weeklyTasks", Icons.date_range_outlined, Colors.green),
            const SizedBox(width: 10),
            _buildCompactStat("الشهر", "$monthlyTasks", Icons.calendar_month_outlined, Colors.orange),
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
    if (!_isOnline) {
      return Column(
        children: [
          _buildDailyManifest(),
          const SizedBox(height: 20),
          _buildStatusPlaceholder(Icons.cloud_off, "أنت حالياً غير متصل", "قم بتغيير حالتك للأعلى لبدء استقبال الطلبات"),
        ],
      );
    }

    return Column(
      children: [
        // --- Daily Route Sheet always visible at the top ---
        _buildDailyManifest(),
        const SizedBox(height: 20),
        StreamBuilder<QuerySnapshot>(
          stream: _orderService.streamDriverActiveOrders(_currentDriverId!),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
              final orderDoc = snapshot.data!.docs.first;
              final status = orderDoc.get('status');
              if (status == 'accepted' || status == 'in_progress') {
                WidgetsBinding.instance.addPostFrameCallback((_) => _startSync(orderDoc.id));
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) => _stopSync());
              }
              return _buildActivePipeline(orderDoc);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) => _stopSync());
            return _buildAvailableTasksSection();
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // DAILY ROUTE MANIFEST (جدول الرحلات اليومي)
  // ─────────────────────────────────────────────
  Widget _buildDailyManifest() {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driver_id', isEqualTo: _currentDriverId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        // Filter for today — support both booking_date string and service_date Timestamp
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] == 'cancelled') return false;

          // Check booking_date string field (hourly orders)
          final bookingDate = data['booking_date'] as String?;
          if (bookingDate == todayKey) return true;

          // Fallback: check service_date Timestamp
          final serviceDate = (data['service_date'] as Timestamp?)?.toDate();
          if (serviceDate != null) {
            return serviceDate.year == DateTime.now().year &&
                serviceDate.month == DateTime.now().month &&
                serviceDate.day == DateTime.now().day;
          }
          return false;
        }).toList();

        // Sort chronologically by booking_time_slot or service_date hour
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aSlot = aData['booking_time_slot'] as String? ??
              (aData['service_date'] as Timestamp?)?.toDate()
                  .toIso8601String() ?? '';
          final bSlot = bData['booking_time_slot'] as String? ??
              (bData['service_date'] as Timestamp?)?.toDate()
                  .toIso8601String() ?? '';
          return aSlot.compareTo(bSlot);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_rounded, color: Color(0xFF5D1B5E), size: 20),
                const SizedBox(width: 8),
                Text(
                  'جدول الرحلات اليومي',
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5D1B5E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${docs.length} رحلة',
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5D1B5E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_available, color: Colors.grey.shade300, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'لا توجد رحلات مجدولة لهذا اليوم',
                      style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, i) =>
                    _buildManifestOrderCard(docs[i].id, docs[i].data() as Map<String, dynamic>),
              ),
          ],
        );
      },
    );
  }

  Widget _buildManifestOrderCard(String orderId, Map<String, dynamic> data) {
    // Resolve time slot display
    String timeSlot = data['booking_time_slot'] as String? ?? '';
    if (timeSlot.isEmpty) {
      final sd = (data['service_date'] as Timestamp?)?.toDate();
      if (sd != null) {
        timeSlot = DateFormat('HH:mm').format(sd);
      }
    }

    final String serviceName =
        data['service_name'] ?? data['service_type'] ?? 'خدمة زيارة';
    final String clientPhone = data['client_phone'] ?? data['user_phone'] ?? '';
    final String clientName = data['client_name'] ?? 'العميل';
    final String status = data['status'] ?? 'pending';
    final GeoPoint? location = data['location'] as GeoPoint?;

    // Status badge color
    final Color statusColor = status == 'completed'
        ? Colors.green
        : status == 'in_progress'
            ? Colors.blue
            : status == 'accepted'
                ? Colors.orange
                : const Color(0xFF5D1B5E);

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
                if (data['zone_name'] != null)
                  Text(
                    data['zone_name'] as String,
                    style: GoogleFonts.tajawal(
                      fontSize: 10,
                      color: Colors.grey.shade400,
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
                "مهمة نشطة — يُرجى التركيز",
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
    Color stateColor = const Color(0xFF5D1B5E);
    IconData stateIcon = Icons.directions_car;

    switch (status) {
      case 'accepted':
        stateTitle = "في الطريق للعميل";
        actionLabel = "اسحب للتأكيد — وصلت، بدء الخدمة";
        nextStatus = "in_progress";
        stateColor = Colors.blue;
        stateIcon = Icons.map;
        break;
      case 'in_progress':
        stateTitle = "الخدمة قيد التنفيذ";
        actionLabel = "اسحب للتأكيد — إتمام المهمة";
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
                    if (status == 'accepted' && data['location'] is GeoPoint)
                      _buildDistanceInfo(data['location'] as GeoPoint),
                  ],
                ),
              ),
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
          if (data['client_id'] != null) _buildHouseRulesAlert(data['client_id']),
          if (data['client_id'] != null) const Divider(height: 28),
          if (status == 'in_progress') _buildTimer(data['hours_contracted'] ?? 4),
          const SizedBox(height: 8),
          // DRIVER-001/008: swipe-to-confirm replaces tap button — prevents accidental triggers
          _SwipeToActButton(
            label: actionLabel,
            color: stateColor,
            isLoading: _isUpdatingStatus,
            onConfirmed: () => _updateStatus(id, nextStatus),
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

  Widget _buildHouseRulesAlert(String clientId) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(clientId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docData = snapshot.data?.data() as Map<String, dynamic>?;
        final rules = docData?['house_rules'] as String?;
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
      },
    );
  }

  Widget _buildDistanceInfo(GeoPoint clientLoc) {
    return StreamBuilder<Position>(
      stream: _locationStream,
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

  Future<void> _checkAndNotifyProximity(String orderId, GeoPoint target) async {
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

  Widget _buildAvailableTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("الطلبات المتاحة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 15),
        StreamBuilder<QuerySnapshot>(
          stream: _orderService.streamAvailableOrders(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildStatusPlaceholder(Icons.search, "لا توجد طلبات حالياً", "بانتظار وصول طلبات جديدة من العملاء");
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                return _buildNewTaskCard(doc.id, doc.data() as Map<String, dynamic>);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildNewTaskCard(String id, Map<String, dynamic> data) {
    final isAccepting = _acceptingOrderId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF5D1B5E).withValues(alpha: 0.1),
            child: const Icon(Icons.local_offer, color: Color(0xFF5D1B5E), size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['service_type'] ?? "خدمة تنظيف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                Text("${data['hours_contracted'] ?? 4} ساعات", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isAccepting ? null : () => _acceptOrder(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D1B5E),
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: isAccepting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("قبول", style: TextStyle(color: Colors.white)),
          ),
        ],
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

  Widget _buildTimer(int hours) {
    return Column(children: [
      const Text("وقت بدء المهمة", style: TextStyle(fontSize: 10, color: Colors.grey)),
      StreamBuilder<Duration>(
        stream: _coreService.taskTimerStream(hours),
        builder: (context, snapshot) {
          String time = "--:--:--";
          Color timerColor = const Color(0xFF5D1B5E);
          if (snapshot.hasData) {
            final d = snapshot.data!;
            time = "${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
            if (d.inMinutes < 15) timerColor = Colors.redAccent;
          }
          return Text(time, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: timerColor));
        },
      ),
      const SizedBox(height: 15),
    ]);
  }

  void _reportIssue(String orderId) async {
    final message = "بلاغ عن الطلب #$orderId: لدي مشكلة في هذا الطلب — السائق: $_currentDriverId";
    String adminPhone = "966500000000";
    try {
      final configDoc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
      adminPhone = configDoc.data()?['admin_whatsapp'] ?? adminPhone;
    } catch (_) {}
    final url = "https://wa.me/$adminPhone?text=${Uri.encodeComponent(message)}";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }

  // DRIVER-002: try/catch + per-order loading state
  void _acceptOrder(String id) async {
    if (_acceptingOrderId != null) return;
    setState(() => _acceptingOrderId = id);
    try {
      bool success = await _orderService.acceptOrder(id, _currentDriverId!);
      if (success) {
        final doc = await FirebaseFirestore.instance.collection('orders').doc(id).get();
        final data = doc.data();
        if (data != null && data['client_id'] != null) {
          await _notificationService.notifyClientOfDriverStatus(
            clientId: data['client_id'],
            status: 'accepted',
            orderCode: data['code'] ?? id,
            driverName: _driverName,
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لديك طلب نشط بالفعل!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل قبول الطلب، تحقق من اتصالك بالإنترنت', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingOrderId = null);
    }
  }

  // DRIVER-001: try/catch + double-tap guard via _isUpdatingStatus
  void _updateStatus(String id, String status) async {
    if (_isUpdatingStatus) return;
    setState(() => _isUpdatingStatus = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('orders').doc(id).get();
      final data = doc.data();
      if (data == null) return;

      final paymentMethod = data['payment_method'];
      final amount = (data['amount'] ?? 0.0).toDouble();
      final clientName = data['client_name'] ?? 'العميل';

      if (status == 'completed' && paymentMethod == 'cod') {
        if (!mounted) return;

        // Generate 4-digit PIN and write to Firestore so client can see it immediately
        final pin = (Random().nextInt(9000) + 1000).toString();
        await FirebaseFirestore.instance.collection('orders').doc(id).update({
          'payment_pin': pin,
          'payment_pin_generated_at': FieldValue.serverTimestamp(),
        });

        // Show PIN entry dialog for driver — client will show the same PIN from their app
        if (!mounted) return;
        final pinController = TextEditingController();
        String? pinError;
        bool confirmed = false;
        try {
        final dialogResult = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => StatefulBuilder(
            builder: (dialogCtx, setDialogState) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Color(0xFF5D1B5E)),
                    const SizedBox(width: 8),
                    Text("رمز الدفع", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("المبلغ: ", style: GoogleFonts.tajawal(fontSize: 13)),
                          Text("${amount.toStringAsFixed(2)} ر.س",
                              style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.green.shade800)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "اطلب من $clientName رمز الدفع المعروض في تطبيقه وأدخله هنا",
                      style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey[600], height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 10),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '0000',
                        hintStyle: TextStyle(color: Colors.grey[300], letterSpacing: 10),
                        errorText: pinError,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF5D1B5E), width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      // Cancel: remove the PIN from Firestore and abort
                      await FirebaseFirestore.instance.collection('orders').doc(id).update({
                        'payment_pin': FieldValue.delete(),
                        'payment_pin_generated_at': FieldValue.delete(),
                      });
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx, false);
                    },
                    child: Text("إلغاء", style: GoogleFonts.tajawal(color: Colors.grey[600])),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (pinController.text == pin) {
                        Navigator.pop(dialogCtx, true);
                      } else {
                        setDialogState(() => pinError = "الرمز غير صحيح، حاول مجدداً");
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5D1B5E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text("تأكيد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
        confirmed = dialogResult == true;
        } finally {
          pinController.dispose();
        }

        if (!confirmed) return;

        await FirebaseFirestore.instance.collection('orders').doc(id).update({
          'is_paid': true,
          'paid_at': FieldValue.serverTimestamp(),
          'cash_collected_by': _currentDriverId,
          'cash_confirmed': true,
          'cash_confirmed_at': FieldValue.serverTimestamp(),
          'payment_pin': FieldValue.delete(),
          'payment_pin_generated_at': FieldValue.delete(),
        });

        await _notificationService.notifyAdminOfCashCollection(
          driverName: _driverName,
          orderCode: data['code'] ?? id,
          amount: amount,
        );
      }

      await _orderService.updateOrderStatus(id, status, driverId: _currentDriverId);

      if (data['client_id'] != null) {
        final orderCode = data['code'] ?? id;
        await _notificationService.notifyClientOfDriverStatus(
          clientId: data['client_id'],
          status: status,
          orderCode: orderCode,
          driverName: _driverName,
        );
        if (status == 'accepted' || status == 'completed') {
          await _notificationService.notifyAdminOfDriverUpdate(
            driverName: _driverName,
            status: status,
            orderCode: orderCode,
          );
        }
      }

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
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Lottie.network('https://lottie.host/85cc1144-6729-4d64-88aa-3e753456c636/Hw4h8Pndr5.json', width: 200, height: 200, repeat: false),
          const SizedBox(height: 10),
          Text('تمت المهمة بنجاح', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _openMaps(dynamic loc) async {
    if (loc is! GeoPoint) return;
    final url = 'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }

  void _callClient(String phone) async {
    final url = 'tel:$phone';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }
}

/// Swipe-to-confirm button — prevents accidental taps on critical field actions.
/// RTL layout: thumb starts at right edge, user drags left to confirm (82% threshold).
class _SwipeToActButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onConfirmed;
  final bool isLoading;

  const _SwipeToActButton({
    required this.label,
    required this.color,
    required this.onConfirmed,
    required this.isLoading,
  });

  @override
  State<_SwipeToActButton> createState() => _SwipeToActButtonState();
}

class _SwipeToActButtonState extends State<_SwipeToActButton> {
  double _dragX = 0;
  bool _triggered = false;
  static const double _thumbSize = 52.0;

  @override
  void didUpdateWidget(_SwipeToActButton old) {
    super.didUpdateWidget(old);
    // Reset drag state after the operation completes (success or failure)
    if (old.isLoading && !widget.isLoading) {
      setState(() {
        _dragX = 0;
        _triggered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = (trackWidth - _thumbSize - 8).clamp(0.0, double.infinity);

        return SizedBox(
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track background
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              // Progress fill — grows from right leftward as user drags (RTL)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: (_thumbSize + 8 + _dragX).clamp(0.0, trackWidth),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              // Label / spinner
              widget.isLoading
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(color: widget.color, strokeWidth: 2.5),
                    )
                  : Text(
                      widget.label,
                      style: GoogleFonts.tajawal(color: widget.color, fontWeight: FontWeight.bold, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
              // Draggable thumb (RTL: right=4 at rest, moves left as _dragX grows)
              if (!widget.isLoading)
                Positioned(
                  right: (4 + maxDrag - _dragX).clamp(4.0, 4 + maxDrag),
                  top: 4,
                  bottom: 4,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      if (_triggered) return;
                      setState(() {
                        // RTL: dragging left → negative delta.dx → increase _dragX
                        _dragX = (_dragX - d.delta.dx).clamp(0.0, maxDrag);
                      });
                      if (_dragX >= maxDrag * 0.82 && !_triggered) {
                        _triggered = true;
                        HapticFeedback.heavyImpact();
                        widget.onConfirmed();
                      }
                    },
                    onHorizontalDragEnd: (_) {
                      if (!_triggered) setState(() => _dragX = 0);
                    },
                    child: Container(
                      width: _thumbSize,
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
