import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart' as intl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/contract_signing_screen.dart';
import 'package:zyiarah/services/zyiarah_capacity_service.dart';

class ZyiarahSubscriptionPlansScreen extends StatefulWidget {
  const ZyiarahSubscriptionPlansScreen({super.key});

  @override
  State<ZyiarahSubscriptionPlansScreen> createState() =>
      _ZyiarahSubscriptionPlansScreenState();
}

class _ZyiarahSubscriptionPlansScreenState
    extends State<ZyiarahSubscriptionPlansScreen> {
  static const Color _brand = Color(0xFF5D1B5E);
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _hasError = false;
  List<QueryDocumentSnapshot> _packages = [];

  // --- NEW CAPACITY AND BOOKING FIELDS ---
  int? _selectedPackageIndex;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int? _selectedStartHour;
  Map<int, bool> _slotAvailability = {};
  bool _checkingSlots = false;

  String? _userZoneName;
  bool _loadingZone = true;

  int _maxOrdersPerDay = 10;
  Map<String, int> _dailyOrderCounts = {};
  bool _loadingDailyCounts = true;
  final ZyiarahCapacityService _capacityService = ZyiarahCapacityService();

  StreamSubscription<DocumentSnapshot>? _configSubscription;
  StreamSubscription<DocumentSnapshot>? _mainConfigSubscription;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  // ----------------------------------------

  @override
  void initState() {
    super.initState();
    _fetchPackages();
    _fetchUserDefaultZone();
    _fetchDailyCapacityAndOrders();
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    _mainConfigSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchUserDefaultZone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final ordersSnap = await _db
            .collection('orders')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        if (ordersSnap.docs.isNotEmpty) {
          final orderData = ordersSnap.docs.first.data();
          final zone = orderData['zone_name'] as String?;
          if (zone != null && zone.isNotEmpty) {
            if (mounted) {
              setState(() {
                _userZoneName = zone;
                _loadingZone = false;
              });
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Error getting user default zone: $e');
      }
    }
    // Fallback to first enabled zone
    try {
      final zonesSnap = await _db
          .collection('service_zones')
          .where('enabled', isEqualTo: true)
          .limit(1)
          .get();
      if (zonesSnap.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _userZoneName = zonesSnap.docs.first.data()['name'] as String?;
            _loadingZone = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _userZoneName = 'المنطقة الافتراضية';
            _loadingZone = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userZoneName = 'المنطقة الافتراضية';
          _loadingZone = false;
        });
      }
    }
  }

  void _fetchDailyCapacityAndOrders() {
    if (!mounted) return;
    setState(() => _loadingDailyCounts = true);

    // 1. Listen to admin config changes in real-time (hourly_settings)
    _configSubscription = _db
        .collection('system_configs')
        .doc('hourly_settings')
        .snapshots()
        .listen((configDoc) {
      if (configDoc.exists && mounted) {
        setState(() {
          _maxOrdersPerDay = configDoc.data()?['max_orders_per_day'] ?? 10;
        });
        _loadSlotAvailability();
      }
    }, onError: (e) {
      debugPrint("Error listening to config: $e");
    });

    // 2. Listen to admin config changes in real-time (main_settings)
    _mainConfigSubscription = _db
        .collection('system_configs')
        .doc('main_settings')
        .snapshots()
        .listen((mainConfigDoc) {
      if (mainConfigDoc.exists && mounted) {
        _capacityService.invalidateCache();
        _loadSlotAvailability();
      }
    }, onError: (e) {
      debugPrint("Error listening to main settings config: $e");
    });

    // 3. Listen to active orders for the next 30 days in real-time
    try {
      final now = DateTime.now();
      final todayStr = intl.DateFormat('yyyy-MM-dd').format(now);
      final endDateStr = intl.DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 31)));

      _ordersSubscription = _db
          .collection('orders')
          .where('booking_date', isGreaterThanOrEqualTo: todayStr)
          .where('booking_date', isLessThanOrEqualTo: endDateStr)
          .snapshots()
          .listen((snapshot) {
        final Map<String, int> counts = {};
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['status'] != 'cancelled') {
            final String? bDate = data['booking_date'];
            if (bDate != null) {
              counts[bDate] = (counts[bDate] ?? 0) + 1;
            }
          }
        }

        if (mounted) {
          setState(() {
            _dailyOrderCounts = counts;
            _loadingDailyCounts = false;

            // Auto-select the first available date in the next 30 days if current selection is booked
            final String currentSelectedStr = intl.DateFormat('yyyy-MM-dd').format(_selectedDate);
            final int currentCount = counts[currentSelectedStr] ?? 0;
            if (currentCount >= _maxOrdersPerDay) {
              for (int i = 0; i < 30; i++) {
                final checkDate = now.add(Duration(days: i + 1));
                final checkDateStr = intl.DateFormat('yyyy-MM-dd').format(checkDate);
                final checkCount = counts[checkDateStr] ?? 0;
                if (checkCount < _maxOrdersPerDay) {
                  _selectedDate = checkDate;
                  break;
                }
              }
            }
          });
          _loadSlotAvailability();
        }
      }, onError: (e) {
        debugPrint("Error listening to orders: $e");
        if (mounted) {
          setState(() => _loadingDailyCounts = false);
        }
      });
    } catch (e) {
      debugPrint("Error setting up stream listeners: $e");
      if (mounted) {
        setState(() => _loadingDailyCounts = false);
      }
    }
  }

  List<int> _getStartHours() {
    int visitHours = 4;
    if (_selectedPackageIndex != null && _selectedPackageIndex! < _packages.length) {
      final data = _packages[_selectedPackageIndex!].data() as Map<String, dynamic>;
      visitHours = (data['hours'] ?? 4).toInt();
    }
    const startHour = 8;
    const endHour = 22;
    final last = endHour - visitHours;
    if (last < startHour) return [];
    return List.generate(last - startHour + 1, (i) => startHour + i);
  }

  Future<void> _loadSlotAvailability() async {
    if (!mounted) return;
    if (_userZoneName == null) return;

    _capacityService.invalidateCache();
    setState(() {
      _checkingSlots = true;
      _slotAvailability = {};
      _selectedStartHour = null;
    });

    final slots = _getStartHours();
    final String zoneId = _userZoneName ?? '';
    final Map<int, bool> result = {};

    for (final h in slots) {
      final String timeSlot = '${h.toString().padLeft(2, '0')}:00';
      final bool available = await _capacityService.checkSlotAvailability(
        date: _selectedDate,
        timeSlot: timeSlot,
        zoneId: zoneId,
      );
      result[h] = available;
      if (mounted) setState(() => _slotAvailability = Map.from(result));
    }
    if (mounted) setState(() => _checkingSlots = false);
  }

  Future<void> _fetchPackages() async {
    if (mounted) setState(() { _isLoading = true; _hasError = false; });
    try {
      final snapshot = await _db.collection('subscription_packages').get();
      if (mounted) {
        final docs = snapshot.docs;
        docs.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aRank = (aData['rank'] ?? 999) as num;
          final bRank = (bData['rank'] ?? 999) as num;
          return aRank.compareTo(bRank);
        });

        // Filter out any packages whose title or subtitle contains "يومية" or "daily"
        final filteredDocs = docs.where((doc) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          final subtitle = (data['subtitle'] ?? '').toString().toLowerCase();
          return !title.contains('يومية') && !title.contains('daily') &&
                 !subtitle.contains('يومية') && !subtitle.contains('daily');
        }).toList();

        setState(() {
          _packages = filteredDocs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('SUBSCRIPTION_FETCH_ERROR: $e');
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F0F7),
        appBar: AppBar(
          title: Text('باقات الاشتراكات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _isLoading ? _buildShimmer() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 16),
          ...List.generate(3, (_) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 220,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          )),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoBanner(),
          const SizedBox(height: 20),
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.wifi_off_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('فشل تحميل الباقات، تحقق من اتصالك',
                        style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchPackages,
                      style: ElevatedButton.styleFrom(backgroundColor: _brand),
                      child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else if (_packages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('لا توجد باقات متاحة حالياً',
                        style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            ..._packages.asMap().entries.map((entry) {
              final i = entry.key;
              final doc = entry.value;
              final data = doc.data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: SubscriptionPlanCard(
                  data: data,
                  isSelected: _selectedPackageIndex == i,
                  index: i,
                  onTap: () {
                    setState(() {
                      if (_selectedPackageIndex == i) {
                        _selectedPackageIndex = null;
                      } else {
                        _selectedPackageIndex = i;
                      }
                    });
                    if (_selectedPackageIndex != null) {
                      _loadSlotAvailability();
                    }
                  },
                ),
              );
            }),
          
          if (_selectedPackageIndex != null) ...[
            const SizedBox(height: 24),
            _buildBookingSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brand.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded, color: _brand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'اختر الباقة المناسبة لعائلتك. سيتم توجيه طلبك للإدارة للموافقة عليه قبل توقيع العقد الإلكتروني.',
              style: GoogleFonts.tajawal(fontSize: 13, height: 1.5, color: Colors.blueGrey[700]),
            ),
          ),
        ],
      ),
    );
  }

  // The old _buildPlanCard was replaced by the beautiful, stateful SubscriptionPlanCard widget class defined at the bottom.

  Widget _buildBookingSection() {
    final selectedDoc = _packages[_selectedPackageIndex!];
    final selectedData = selectedDoc.data() as Map<String, dynamic>;
    final String title = selectedData['title'] ?? 'باقة اشتراك';
    final double priceValue = double.tryParse(selectedData['price']?.toString() ?? '0') ?? 0.0;
    final int visits = (selectedData['visits'] ?? 0).toInt();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E0ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_month, color: _brand, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحديد موعد تفعيل الباقة',
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'اختر تاريخ البدء ووقت تفعيل باقة: $title',
                      style: GoogleFonts.tajawal(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32, color: Color(0xFFE2E8F0)),

          // 1. User Zone Display (Informative)
          if (_loadingZone)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
                  SizedBox(width: 10),
                  Text('جاري التحقق من منطقتك المغطاة...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تفعيل الباقة في منطقة التغطية: $_userZoneName',
                      style: GoogleFonts.tajawal(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // 2. Date Selection Header
          Text(
            'تاريخ التفعيل المتاح للـ 30 يوماً القادمة:',
            style: GoogleFonts.tajawal(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Date Picker Widget
          _buildSubscriptionDatePicker(),
          const SizedBox(height: 10),
          _buildDateLegend(),
          const SizedBox(height: 24),

          // 4. Time Slot Header
          Text(
            'وقت بدء الزيارة الأولى:',
            style: GoogleFonts.tajawal(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),

          // 5. Time Slot Selector Widget
          _buildSubscriptionTimeSlotSelector(),
          const SizedBox(height: 32),

          // 6. Action Button to proceed to signing
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_selectedStartHour == null || _checkingSlots)
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      final DateTime serviceDate = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        _selectedStartHour!,
                      );
                      final String timeSlotStr = '${_selectedStartHour!.toString().padLeft(2, '0')}:00';

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ZyiarahContractSigningScreen(
                            planName: title,
                            planPrice: priceValue,
                            planVisits: visits,
                            bookingDate: serviceDate,
                            bookingTimeSlot: timeSlotStr,
                          ),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[200],
                disabledForegroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'المتابعة لتوقيع العقد الإلكتروني',
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionDatePicker() {
    if (_loadingDailyCounts) {
      return const SizedBox(
        height: 82,
        child: Center(
          child: CircularProgressIndicator(color: _brand),
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
          final isFullyBooked = activeOrders >= _maxOrdersPerDay;

          return GestureDetector(
            onTap: isFullyBooked
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                        "هذا اليوم محجوز بالكامل، يرجى اختيار تاريخ آخر لتفعيل الاشتراك.",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ));
                  }
                : () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedDate = date;
                    });
                    _loadSlotAvailability();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected
                    ? _brand
                    : isFullyBooked
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? _brand
                      : isFullyBooked
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFE8F5E9),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: _brand.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
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
                          : isFullyBooked 
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
        Text("متاح للحجز", style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(width: 20),
        _legendDot(const Color(0xFFEF4444)),
        const SizedBox(width: 6),
        Text("محجوز بالكامل", style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _legendDot(Color color, {Color? border}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border != null ? Border.all(color: border) : null,
      ),
    );
  }

  Widget _buildSubscriptionTimeSlotSelector() {
    if (_slotAvailability.isEmpty && !_checkingSlots) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          "اختر التاريخ أولاً لعرض الأوقات المتاحة",
          style: GoogleFonts.tajawal(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_checkingSlots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
                const SizedBox(width: 10),
                Text("جاري التحقق من التوفر الفعلي للموعد...", style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _getStartHours().map((h) {
            final isBooked = _slotAvailability[h] == false;
            final isChecked = _slotAvailability.containsKey(h);
            final isSelected = _selectedStartHour == h;
            final label = '${h.toString().padLeft(2, '0')}:00';
            return GestureDetector(
              onTap: (!isChecked || isBooked)
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedStartHour = h);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isBooked
                      ? Colors.red.shade50
                      : isSelected
                          ? _brand
                          : !isChecked
                              ? Colors.grey.shade100
                              : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBooked
                        ? Colors.red.shade300
                        : isSelected
                            ? _brand
                            : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isBooked
                        ? Colors.red.shade400
                        : isSelected
                            ? Colors.white
                            : !isChecked
                                ? Colors.grey.shade400
                                : const Color(0xFF1E293B),
                    decoration: isBooked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_slotAvailability.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                _legendDot(Colors.red.shade200),
                const SizedBox(width: 4),
                Text("محجوز", style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 12),
                _legendDot(_brand),
                const SizedBox(width: 4),
                Text("مختار", style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 12),
                _legendDot(Colors.white, border: Colors.grey.shade300),
                const SizedBox(width: 4),
                Text("متاح", style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class SubscriptionPlanCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  const SubscriptionPlanCard({
    super.key,
    required this.data,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  State<SubscriptionPlanCard> createState() => _SubscriptionPlanCardState();
}

class _SubscriptionPlanCardState extends State<SubscriptionPlanCard>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _breathingController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    // Spring Scale Animation
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // Breathing Glow Animation
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _glowAnimation = Tween<double>(begin: 4.0, end: 16.0).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    if (widget.isSelected) {
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionPlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _breathingController.repeat(reverse: true);
      } else {
        _breathingController.stop();
        _breathingController.reset();
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final title = data['title'] ?? 'باقة اشتراك';
    final subtitle = data['subtitle'] ?? '';
    final price = '${data['price']} ر.س';
    final int hours = (data['hours'] ?? 4).toInt();
    final List<String> features = (data['features'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    
    // Check if the plan is weekly or monthly (determine gradient type)
    final isMonthly = title.toString().contains('شهر') || title.toString().toLowerCase().contains('month');
    
    // Super Premium Gradients:
    // Weekly: Cobalt & Sky to Emerald
    // Monthly: Purple to Magenta
    final List<Color> cardGradient = isMonthly
        ? [const Color(0xFF3B0764), const Color(0xFF6B21A8), const Color(0xFF701A75)] 
        : [const Color(0xFF0F172A), const Color(0xFF0284C7), const Color(0xFF0D9488)];

    final Color glowColor = isMonthly 
        ? const Color(0xFFD946EF) 
        : const Color(0xFF06B6D4); 

    final Color accentColor = isMonthly
        ? const Color(0xFFFBBF24) 
        : const Color(0xFF34D399); 

    return GestureDetector(
      onTapDown: (_) {
        _scaleController.forward();
      },
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        _scaleController.reverse();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnimation, _glowAnimation]),
        builder: (context, child) {
          final double currentScale = widget.isSelected 
              ? (_scaleAnimation.value * 1.03) 
              : _scaleAnimation.value;

          return Transform.scale(
            scale: currentScale,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: widget.isSelected 
                        ? glowColor.withValues(alpha: 0.4 + (_glowAnimation.value / 40)) 
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: widget.isSelected ? _glowAnimation.value + 6 : 12,
                    spreadRadius: widget.isSelected ? _glowAnimation.value / 6 : 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: cardGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: widget.isSelected 
                          ? glowColor.withValues(alpha: 0.8) 
                          : Colors.white.withValues(alpha: 0.15),
                      width: widget.isSelected ? 2.5 : 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Background glassmorphism shapes
                      Positioned(
                        top: -50,
                        right: -50,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -30,
                        left: -30,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.03),
                          ),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          isMonthly ? 'الاشتراك الشهري المميز ✨' : 'الاشتراك الأسبوعي المريح ⚡',
                                          style: GoogleFonts.tajawal(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        title,
                                        style: GoogleFonts.tajawal(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      price,
                                      style: GoogleFonts.tajawal(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: accentColor,
                                      ),
                                    ),
                                    Text(
                                      'زيارات مجدولة',
                                      style: GoogleFonts.tajawal(
                                        fontSize: 10,
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 8),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: GoogleFonts.tajawal(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.timer_outlined, color: accentColor, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'مدة الزيارة: $hours ساعات',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(width: 1, height: 12, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(width: 12),
                                  Icon(Icons.calendar_today_outlined, color: accentColor, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    'عدد الزيارات: ${data['visits'] ?? 0}',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: widget.isSelected
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 16),
                                        Divider(color: Colors.white.withValues(alpha: 0.15)),
                                        const SizedBox(height: 8),
                                        Text(
                                          'مميزات الباقة المشمولة:',
                                          style: GoogleFonts.tajawal(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: accentColor,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...features.asMap().entries.map((featureEntry) {
                                          final fIndex = featureEntry.key;
                                          final fText = featureEntry.value;
                                          return TweenAnimationBuilder<double>(
                                            tween: Tween<double>(begin: 0.0, end: 1.0),
                                            duration: Duration(milliseconds: 250 + (fIndex * 100)),
                                            curve: Curves.easeOut,
                                            builder: (context, val, child) {
                                              return Transform.translate(
                                                offset: Offset(0, 15 * (1.0 - val)),
                                                child: Opacity(
                                                  opacity: val,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(bottom: 10),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(3),
                                                          decoration: BoxDecoration(
                                                            color: accentColor.withValues(alpha: 0.2),
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: Icon(Icons.check_rounded, color: accentColor, size: 12),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Expanded(
                                                          child: Text(
                                                            fText,
                                                            style: GoogleFonts.tajawal(
                                                              fontSize: 13,
                                                              color: Colors.white.withValues(alpha: 0.9),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        }),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: widget.isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : [],
                                ),
                                child: ElevatedButton(
                                  onPressed: widget.onTap,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: widget.isSelected
                                        ? const Color(0xFF10B981)
                                        : Colors.white.withValues(alpha: 0.15),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: widget.isSelected
                                            ? Colors.transparent
                                            : Colors.white.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.isSelected ? 'تم اختيار الباقة بنجاح ✓' : 'اطلب هذه الباقة الآن',
                                        style: GoogleFonts.tajawal(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (widget.isSelected) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
