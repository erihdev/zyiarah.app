import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/utils/time_format.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';


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

  int _maxOrdersPerDay = 10;
  int _maxTeamsPerSlot = 5;
  Map<String, int> _dailyOrderCounts = {};   // "yyyy-MM-dd" → total orders
  Map<String, int> _slotCounts = {};          // "yyyy-MM-dd_HH:00" → orders in slot
  Map<String, List<int>> _openHours = {};     // yyyy-MM-dd → [فتح، إغلاق] من جدول المنطقة
  Set<String> _closedDates = {};              // أيام لا تُخدَم فيها المنطقة
  bool _loadingDailyCounts = true;

  /// تعذّر جلب الإتاحة من الخادم. **لا يجوز عرض تقويم أخضر في هذه الحالة**: الأعداد
  /// تكون فارغة فيبدو كل يوم متاحاً، فيختار العميل يوماً ممتلئاً. نعرض إعادة محاولة.
  bool _availabilityError = false;

  double _hourlyBasePrice = 0.0;
  String? _selectedZoneName;
  GeoPoint? _selectedLocation;

  /// حالة التحديد التلقائي — تُعرض للعميلة بدل الصمت.
  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<int> _allowedHours = [4, 5, 6, 8];
  int _maxAllowedWorkers = 5;
  List<Map<String, dynamic>> _zones = [];

  @override
  void initState() {
    super.initState();
    _fetchConfigAndZones();
    _loadAvailabilityFromServer();
  }

  /// جلب بيانات الإتاحة عبر Cloud Function (Admin SDK — لا قيود صلاحيات).
  /// تُعيد الأعداد الحقيقية للطلبات لكل تاريخ وكل خانة زمنية.
  Future<void> _loadAvailabilityFromServer() async {
    if (!mounted) return;
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

      if (!mounted) return;
      setState(() {
        _dailyOrderCounts = daily;
        _slotCounts = slots;
        _openHours = openHours;
        _closedDates = closed;
        _maxOrdersPerDay = maxPerDay;
        _maxTeamsPerSlot = maxPerSlot;
        _loadingDailyCounts = false;

        // انتقل تلقائياً لأول تاريخ متاح (غير ممتلئ وغير مغلق بالجدول).
        bool unavailable(DateTime d) {
          final s = intl.DateFormat('yyyy-MM-dd').format(d);
          return closed.contains(s) || (daily[s] ?? 0) >= maxPerDay;
        }
        if (unavailable(_selectedDate)) {
          for (int i = 0; i < 30; i++) {
            final candidate = now.add(Duration(days: i + 1));
            if (!unavailable(candidate)) {
              _selectedDate = candidate;
              break;
            }
          }
        }
      });

      // بعد تحميل البيانات: احسب إتاحة الخانات من الـ cache مباشرة
      if (_selectedLocation != null) {
        _buildSlotAvailabilityFromCache();
      }
    } catch (e) {
      // **لا نبتلع الفشل بصمت.** كان هذا الـ catch يكتفي بإطفاء الدوّار، فتبقى
      // ‎_dailyOrderCounts فارغة ⇒ ‎`activeOrders = 0` لكل تاريخ ⇒ ‎`0 >= _maxOrdersPerDay`
      // = false ⇒ **كل التواريخ تظهر خضراء** والعميل يختار يوماً ممتلئاً.
      // الأخضر يجب أن يعني «متاح»، لا «لا نعرف».
      debugPrint('[getHourlyAvailability] error: $e');
      if (mounted) {
        setState(() {
          _loadingDailyCounts = false;
          _availabilityError = true;
        });
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

  /// تحديد تلقائي **يقول السبب عند الفشل**.
  ///
  /// كان كل مسار فشل هنا ينتهي بـ`return;` صامت أو `catch { /* Silent error */ }`،
  /// فتبقى الشاشة على «لم يُحدَّد موقعك بعد» لكل الأسباب على السواء — والعميلة (ونحن)
  /// لا نعرف: أالخدمة مطفأة؟ أم الإذن مرفوض؟ أم GPS لم يستجب؟ ولا سطر في السجلّ.
  ///
  /// [userInitiated] عند الفتح نحاول بلا إظهار مربّع الإذن إن كان مرفوضاً سلفاً؛
  /// وعند ضغط «حدّد موقعي تلقائياً» نطلبه صراحةً.
  Future<void> _attemptAutoLocation({bool userInitiated = false}) async {
    if (!mounted || _zones.isEmpty) return;
    setState(() {
      _isLocating = true;
      _locateFailure = null;
    });

    final res = await ZyiarahZoneLocator.locate(_zones,
        requestPermission: userInitiated);
    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _isLocating = false;
        _locateFailure = res.failure;
        if (res.location != null) _selectedLocation = res.location; // خارج النطاق
      });
      return;
    }

    setState(() {
      _selectedLocation = res.location;
      _selectedZoneName = res.zoneName;
      _isLocating = false;
      _locateFailure = null;
    });
    _updatePriceForZone(res.zone!);
    await _loadAvailabilityFromServer();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("تم تحديد موقعك تلقائياً: $_selectedZoneName"),
      backgroundColor: const Color(0xFF5D1B5E),
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

    // مطابقة المنطقة من المصدر المشترك — كانت منسوخة حرفياً في ثلاث شاشات.
    final matchedZone = ZyiarahZoneLocator.matchZone(loc, _zones);

    if (matchedZone != null) {
      if (mounted) {
        setState(() {
          _selectedLocation = loc;
          _selectedZoneName = matchedZone['name'] as String?;
          _locateFailure = null;
        });
        _updatePriceForZone(matchedZone);
        // حمّل بيانات الإتاحة من الـ CF ثم احسب الخانات من الـ cache
        await _loadAvailabilityFromServer();
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
  /// ساعات فتح المنطقة في اليوم المختار (من الجدول، وإلا 8..22 الافتراضية).
  List<int> _openHoursForSelected() {
    final key = intl.DateFormat('yyyy-MM-dd').format(_selectedDate);
    return _openHours[key] ?? const [8, 22];
  }

  List<int> _getStartHours() {
    // خانات البدء محصورة بساعات فتح المنطقة لهذا اليوم — لا 8..22 دائماً.
    final open = _openHoursForSelected();
    final startHour = open[0];
    final last = open[1] - _selectedHours;
    // احرس ضد الطول السالب (مدة أطول من نافذة الفتح) → List.generate ينهار.
    if (last < startHour) return <int>[];
    return List.generate(last - startHour + 1, (i) => startHour + i);
  }

  /// يحسب إتاحة الخانات الزمنية من الـ cache المحلي (لا يصدر أي طلب شبكة).
  void _buildSlotAvailabilityFromCache() {
    if (!mounted) return;
    final dateKey = intl.DateFormat('yyyy-MM-dd').format(_selectedDate);
    final slots = _getStartHours();
    final Map<int, bool> result = {};
    for (final h in slots) {
      // متاح فقط إن وُجد سائق حرّ طوال مدة الحجز كلها (لا ساعة البدء وحدها) — وإلا
      // كان العميل يحجز بدايةً متاحة بينما ساعةٌ لاحقة كل السائقين فيها مشغولون،
      // فينتهي الطلب معلّقاً بلا إسناد. slotCounts يراعي التداخل، وmaxTeams = عدد السائقين.
      bool available = true;
      for (int hh = h; hh < h + _selectedHours; hh++) {
        final slotKey = '${dateKey}_${hh.toString().padLeft(2, '0')}:00';
        if ((_slotCounts[slotKey] ?? 0) >= _maxTeamsPerSlot) {
          available = false;
          break;
        }
      }
      result[h] = available;
    }
    setState(() {
      _slotAvailability = result;
      _selectedStartHour = null;
      _checkingSlots = false;
    });
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
            zoneName: _selectedZoneName,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void dispose() {
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
    return ZyiarahZoneLocationCard(
      isLocating: _isLocating,
      zoneName: _selectedZoneName,
      failure: _locateFailure,
      onLocateMe: () => _attemptAutoLocation(userInitiated: true),
      onPickManually: _pickLocation,
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
            if (_selectedLocation != null) _buildSlotAvailabilityFromCache();
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
          // مغلق بالجدول (رمادي) ≠ محجوز بالكامل (أحمر) — سببان مختلفان.
          final isClosed = _closedDates.contains(dateStr);
          final isFullyBooked = !isClosed && activeOrders >= _maxOrdersPerDay;
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
                        _buildSlotAvailabilityFromCache();
                      },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF5D1B5E) : availBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF5D1B5E) : availBorder,
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
            final label = formatHour12(h); // عرض 12 ساعة — التخزين يبقى 24
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
