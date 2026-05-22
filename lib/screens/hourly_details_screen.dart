import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zyiarah_capacity_service.dart';


class HourlyCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const HourlyCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<HourlyCleaningDetailsScreen> createState() => _HourlyCleaningDetailsScreenState();
}

class _HourlyCleaningDetailsScreenState extends State<HourlyCleaningDetailsScreen> {
  int _selectedHours = 4;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int? _selectedStartHour;
  Map<int, bool> _slotAvailability = {};
  bool _checkingSlots = false;
  int _workerCount = 1;
  bool _isLoading = true;
  final ZyiarahCapacityService _capacityService = ZyiarahCapacityService();

  int _maxOrdersPerDay = 10;
  Map<String, int> _dailyOrderCounts = {};
  bool _loadingDailyCounts = true;

  StreamSubscription<DocumentSnapshot>? _configSubscription;
  StreamSubscription<DocumentSnapshot>? _mainConfigSubscription;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  double _hourlyBasePrice = 0.0;
  String? _selectedZoneName;
  GeoPoint? _selectedLocation;

  List<int> _allowedHours = [4, 5, 6, 8];
  int _maxAllowedWorkers = 5;
  List<Map<String, dynamic>> _zones = [];

  @override
  void initState() {
    super.initState();
    _fetchConfigAndZones();
    _fetchDailyCapacityAndOrders();
  }

  void _fetchDailyCapacityAndOrders() {
    if (!mounted) return;
    setState(() => _loadingDailyCounts = true);

    // 1. Listen to admin config changes in real-time (hourly_settings)
    _configSubscription = FirebaseFirestore.instance
        .collection('system_configs')
        .doc('hourly_settings')
        .snapshots()
        .listen((configDoc) {
      if (configDoc.exists && mounted) {
        setState(() {
          _maxOrdersPerDay = configDoc.data()?['max_orders_per_day'] ?? 10;
        });
        if (_selectedLocation != null) {
          _loadSlotAvailability();
        }
      }
    }, onError: (e) {
      debugPrint("Error listening to config: $e");
    });

    // 2. Listen to admin config changes in real-time (main_settings)
    _mainConfigSubscription = FirebaseFirestore.instance
        .collection('system_configs')
        .doc('main_settings')
        .snapshots()
        .listen((mainConfigDoc) {
      if (mainConfigDoc.exists && mounted) {
        _capacityService.invalidateCache();
        if (_selectedLocation != null) {
          _loadSlotAvailability();
        }
      }
    }, onError: (e) {
      debugPrint("Error listening to main settings config: $e");
    });

    // 3. Listen to active orders for the next 30 days in real-time
    try {
      final now = DateTime.now();
      final todayStr = intl.DateFormat('yyyy-MM-dd').format(now);
      final endDateStr = intl.DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 31)));

      _ordersSubscription = FirebaseFirestore.instance
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
          if (_selectedLocation != null) {
            _loadSlotAvailability();
          }
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

  Future<void> _fetchConfigAndZones() async {
    // system_configs is admin-only — separate try-catch so a permission error
    // doesn't prevent service_zones from loading for regular clients.
    try {
      final configDoc = await FirebaseFirestore.instance.collection('system_configs').doc('hourly_settings').get();
      if (configDoc.exists) {
        final List<dynamic>? hoursList = configDoc.data()?['allowed_hours'];
        if (hoursList != null) {
          _allowedHours = hoursList.map((e) => int.tryParse(e.toString()) ?? 4).toList()..sort();
          if (_allowedHours.isNotEmpty && !_allowedHours.contains(_selectedHours)) {
            _selectedHours = _allowedHours.first;
          }
        }
        if (configDoc.data()!.containsKey('max_workers')) {
          _maxAllowedWorkers = configDoc.data()?['max_workers'] ?? 5;
        }
        if (configDoc.data()!.containsKey('max_orders_per_day')) {
          _maxOrdersPerDay = configDoc.data()?['max_orders_per_day'] ?? 10;
        }
      }
    } catch (_) {
      // Clients lack read access to system_configs — defaults are already set.
    }

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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _attemptAutoLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.deniedForever) return;

      Position pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      GeoPoint loc = GeoPoint(pos.latitude, pos.longitude);

      Map<String, dynamic>? matchedZone;
      double minDistance = double.infinity;

      for (var z in _zones) {
        final center = z['centerLoc'];
        if (center is GeoPoint) {
          double radius = (z['radiusKm'] ?? 15.0) * 1000;
          double distance = Geolocator.distanceBetween(loc.latitude, loc.longitude, center.latitude, center.longitude);
          if (distance <= radius && distance < minDistance) {
            minDistance = distance;
            matchedZone = z;
          }
        }
      }

      if (matchedZone != null && mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = matchedZone!['name'];
        });
        _updatePriceForZone(matchedZone);
        _loadSlotAvailability();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("تم تحديد موقعك تلقائياً: $_selectedZoneName"),
            backgroundColor: const Color(0xFF5D1B5E),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    } catch (e) {
      // Silent error, let user pick manually
    }
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
    
    Map<String, dynamic>? matchedZone;
    double minDistance = double.infinity;

    for (var z in _zones) {
      final center = z['centerLoc'];
      if (center is GeoPoint) {
        double radius = (z['radiusKm'] ?? 15.0) * 1000;
        double distance = Geolocator.distanceBetween(loc.latitude, loc.longitude, center.latitude, center.longitude);
        if (distance <= radius && distance < minDistance) {
          minDistance = distance;
          matchedZone = z;
        }
      }
    }

    if (matchedZone != null) {
      if (mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = matchedZone!['name'];
        });
        _updatePriceForZone(matchedZone);
      }
    } else {
      if (mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = null;
          _hourlyBasePrice = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("نأسف، موقعك خارج نطاق الخدمة حالياً"), backgroundColor: Colors.red));
      }
    }
  }

  void _updatePriceForZone(Map<String, dynamic> zone) {
    if (_allowedHours.isNotEmpty && !_allowedHours.contains(_selectedHours)) {
       _selectedHours = _allowedHours.first;
    }
    final prices = zone['prices'] as Map<String, dynamic>? ?? {};
    double p = 0.0;
    if (prices.containsKey(_selectedHours.toString())) {
       p = (prices[_selectedHours.toString()] as num).toDouble();
    }
    setState(() {
       _hourlyBasePrice = p;
    });
  }

  // الفتحات الزمنية المتاحة (8ص حتى آخر وقت تنتهي فيه الخدمة قبل 10م)
  List<int> _getStartHours() {
    const endHour = 22;
    final last = endHour - _selectedHours;
    return List.generate(last - 8 + 1, (i) => 8 + i);
  }

  Future<void> _loadSlotAvailability() async {
    if (!mounted) return;
    // Invalidate cache so capacity reads latest config
    _capacityService.invalidateCache();
    setState(() {
      _checkingSlots = true;
      _slotAvailability = {};
      _selectedStartHour = null;
    });

    final slots = _getStartHours();
    final String zoneId = _selectedZoneName ?? '';
    final Map<int, bool> result = {};

    for (final h in slots) {
      // Format the time slot key as "HH:00" to match the capacity service schema
      final String timeSlot = '${h.toString().padLeft(2, '0')}:00';
      final bool available = await _capacityService.checkSlotAvailability(
        date: _selectedDate,
        timeSlot: timeSlot,
        zoneId: zoneId,
      );
      result[h] = available;
      // Update UI progressively as each slot resolves
      if (mounted) setState(() => _slotAvailability = Map.from(result));
    }
    if (mounted) setState(() => _checkingSlots = false);
  }

  double get totalAmount => _hourlyBasePrice * _workerCount;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _handleInitiateFlow() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى تحديد موقعك أولاً لمعرفة الأسعار المتاحة")));
      return;
    }
    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("هذه الخدمة غير مسعرة في منطقتك حالياً لعدد الساعات المحدد")));
      return;
    }
    if (_selectedStartHour == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار وقت بدء الخدمة")));
      return;
    }

    // دمج التاريخ مع وقت البدء المختار
    final serviceDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedStartHour!,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: widget.serviceName,
            amount: totalAmount,
            location: _selectedLocation!,
            hours: _selectedHours,
            serviceDate: serviceDateTime,
            workerCount: _workerCount,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    _mainConfigSubscription?.cancel();
    _ordersSubscription?.cancel();
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
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D1B5E)))
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
                      const Text("اختر عدد الساعات:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      _buildHoursSelector(),
                      const SizedBox(height: 30),

                      const Text("تاريخ الخدمة:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      _buildDateSelector(),
                      const SizedBox(height: 10),
                      _buildDateLegend(),
                      const SizedBox(height: 30),

                      const Text("وقت البدء:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      _buildTimeSlotSelector(),
                      const SizedBox(height: 30),

                      const Text("عدد العاملات (اختياري):", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      _buildWorkerCounter(),
                      const SizedBox(height: 40),

                      _buildSummaryCard(),
                      const SizedBox(height: 30),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _handleInitiateFlow,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 4),
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
    bool isOutOfRange = _selectedLocation != null && _selectedZoneName == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOutOfRange ? Colors.red.shade50 : const Color(0xFF5D1B5E).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isOutOfRange ? Colors.red.shade200 : const Color(0xFF5D1B5E).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("تحديد موقع السكن:", style: TextStyle(fontWeight: FontWeight.bold, color: isOutOfRange ? Colors.red : const Color(0xFF5D1B5E))),
          const SizedBox(height: 10),
          if (_selectedLocation != null)
            Row(
              children: [
                Icon(isOutOfRange ? Icons.error_outline : Icons.check_circle, color: isOutOfRange ? Colors.red : Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOutOfRange ? "نعتذر، موقعك حالياً خارج نطاق الخدمة" : "المنطقة المدعومة: $_selectedZoneName", 
                    style: TextStyle(color: isOutOfRange ? Colors.red : Colors.green, fontWeight: FontWeight.bold)
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.location_searching, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text("جاري تحديد موقعك تلقائياً...", style: TextStyle(color: Colors.orange)),
              ],
            ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            onPressed: _pickLocation, 
            icon: const Icon(Icons.map_outlined), 
            label: Text(_selectedLocation == null ? "تحديد من الخريطة يدوياً" : "تغيير الموقع"),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOutOfRange ? Colors.red : const Color(0xFF5D1B5E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoursSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _allowedHours.map((h) {
        final isSelected = _selectedHours == h;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedHours = h;
              final matchedZone = _zones.firstWhere((z) => z['name'] == _selectedZoneName, orElse: () => {});
              if (matchedZone.isNotEmpty) _updatePriceForZone(matchedZone);
            });
            if (_selectedLocation != null) _loadSlotAvailability();
          },
          child: Container(
            width: 70,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5D1B5E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey.shade300, width: 2),
              boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF5D1B5E).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))] : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("$h", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF1E293B))),
                Text("ساعات", style: TextStyle(fontSize: 12, color: isSelected ? Colors.white70 : Colors.grey.shade600))
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateSelector() {
    if (_loadingDailyCounts) {
      return const SizedBox(
        height: 82,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF5D1B5E)),
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
            onTap: isFullyBooked ? () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("هذا اليوم محجوز بالكامل، يرجى اختيار تاريخ آخر.", style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ));
            } : () {
              HapticFeedback.lightImpact();
              setState(() => _selectedDate = date);
              _loadSlotAvailability();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF5D1B5E)
                    : isFullyBooked
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF5D1B5E)
                      : isFullyBooked
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFA7F3D0),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: const Color(0xFF5D1B5E).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
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
        const Text("متاح للحجز", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(width: 20),
        _legendDot(const Color(0xFFEF4444)),
        const SizedBox(width: 6),
        const Text("محجوز بالكامل", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTimeSlotSelector() {
    if (_slotAvailability.isEmpty && !_checkingSlots) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: const Text("اختر التاريخ أولاً لعرض الأوقات المتاحة", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_checkingSlots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5D1B5E))),
              SizedBox(width: 10),
              Text("جاري التحقق من التوفر...", style: TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
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
              onTap: (!isChecked || isBooked) ? null : () {
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
                          ? const Color(0xFF5D1B5E)
                          : !isChecked
                              ? Colors.grey.shade100
                              : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBooked
                        ? Colors.red.shade300
                        : isSelected
                            ? const Color(0xFF5D1B5E)
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
            child: Row(children: [
              _legendDot(Colors.red.shade200), const SizedBox(width: 4),
              Text("محجوز", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFF5D1B5E)), const SizedBox(width: 4),
              Text("مختار", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              _legendDot(Colors.white, border: Colors.grey.shade300), const SizedBox(width: 4),
              Text("متاح", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
      ],
    );
  }

  Widget _legendDot(Color color, {Color? border}) => Container(
    width: 12, height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: border ?? color)),
  );

  Widget _buildWorkerCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("عدد العاملات المطلوب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          Row(
            children: [
              _buildAdjustButton(Icons.remove, () {
                if (_workerCount > 1) setState(() => _workerCount--);
              }),
              Container(width: 50, alignment: Alignment.center, child: Text("$_workerCount", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              _buildAdjustButton(Icons.add, () {
                if (_workerCount < _maxAllowedWorkers) setState(() => _workerCount++);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF5D1B5E).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF5D1B5E))),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("سعر الزيارة:", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              Text("${_hourlyBasePrice.toStringAsFixed(2)} ر.س", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("عدد العاملات:", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              Text("x$_workerCount", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const Divider(height: 20, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("الإجمالي المطلوب:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text("${totalAmount.toStringAsFixed(2)} ر.س", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF6366F1))),
            ],
          )
        ],
      ),
    );
  }
}
