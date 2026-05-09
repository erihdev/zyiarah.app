import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';


class HourlyCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const HourlyCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<HourlyCleaningDetailsScreen> createState() => _HourlyCleaningDetailsScreenState();
}

class _HourlyCleaningDetailsScreenState extends State<HourlyCleaningDetailsScreen> {
  int _selectedHours = 4;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _workerCount = 1;
  bool _isLoading = true;

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
  }

  Future<void> _fetchConfigAndZones() async {
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
      }

      final snapshot = await FirebaseFirestore.instance.collection('hourly_zones').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _zones = snapshot.docs.map((doc) => doc.data()).toList();
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

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: widget.serviceName,
            amount: totalAmount,
            location: _selectedLocation!,
            hours: _selectedHours,
            serviceDate: _selectedDate,
            workerCount: _workerCount,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
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
              // update price dynamically
              final matchedZone = _zones.firstWhere((z) => z['name'] == _selectedZoneName, orElse: () => {});
              if (matchedZone.isNotEmpty) {
                _updatePriceForZone(matchedZone);
              }
            });
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
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedDate = date);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF5D1B5E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey.shade200,
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
                    style: TextStyle(fontSize: 9, color: isSelected ? Colors.white70 : Colors.grey[500]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    '/${date.month}',
                    style: TextStyle(fontSize: 10, color: isSelected ? Colors.white60 : Colors.grey[400]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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
