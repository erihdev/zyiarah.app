import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class SofaRugCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const SofaRugCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<SofaRugCleaningDetailsScreen> createState() => _SofaRugCleaningDetailsScreenState();
}

class _SofaRugCleaningDetailsScreenState extends State<SofaRugCleaningDetailsScreen> {
  double _sofaMeters = 0;
  double _rugMeters = 0;
  
  bool _isLoading = true;

  double _sofaPrice = 35.0; // Default fallback
  double _rugPrice = 15.0; // Default fallback
  
  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  
  List<Map<String, dynamic>> _zones = [];

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    try {
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
          _sofaPrice = (matchedZone['sofaPrice'] ?? 35).toDouble();
          _rugPrice = (matchedZone['rugPrice'] ?? 15).toDouble();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("تم تحديد موقعك تلقائياً: $_selectedZoneName"),
          backgroundColor: const Color(0xFF6366F1),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      // Silent error
    }
  }

  Future<void> _pickLocation() async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LocationPickerScreen(
          serviceName: "تحديد موقع تنفيذ خدمة الكنب والزل",
        ),
      ),
    );

    if (!mounted) return;
    if (result == null || result is! GeoPoint) return;
    
    GeoPoint loc = result;
    
    // Find matching zone
    Map<String, dynamic>? matchedZone;
    double minDistance = double.infinity;

    for (var z in _zones) {
      final center = z['centerLoc'];
      if (center is GeoPoint) {
        double radius = (z['radiusKm'] ?? 15.0) * 1000; // to meters
        double distance = Geolocator.distanceBetween(loc.latitude, loc.longitude, center.latitude, center.longitude);
        if (distance <= radius && distance < minDistance) {
          minDistance = distance;
          matchedZone = z;
        }
      }
    }

    if (matchedZone != null) {
      setState(() {
        _selectedLocation = loc;
        _selectedZoneName = matchedZone!['name'];
        _sofaPrice = (matchedZone['sofaPrice'] ?? 35).toDouble();
        _rugPrice = (matchedZone['rugPrice'] ?? 15).toDouble();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("نأسف، موقعك خارج نطاق خدماتنا حالياً"), backgroundColor: Colors.red));
    }
  }

  double get subTotal {
    return (_sofaMeters * _sofaPrice) + (_rugMeters * _rugPrice);
  }

  double get vat => subTotal * 0.15;
  double get totalAmount => subTotal + vat;

  void _handleNext() async {
    if (_selectedLocation == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى تحديد موقعك أولاً")));
       return;
    }
    if (subTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال الأمتار المطلوبة للخدمة")));
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: "${widget.serviceName} (${_selectedZoneName ?? ''})",
            amount: totalAmount,
            location: _selectedLocation!,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(widget.serviceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D1B5E)))
            : Column(
                children: [
                  Hero(
                    tag: 'svc-assets/images/sofa_cleaning.png',
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Image.asset(
                        'assets/images/sofa_cleaning.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFF1E9FE),
                          child: const Icon(Icons.chair, color: Color(0xFF8B5CF6), size: 60),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("موقع تقديم الخدمة:", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (_selectedLocation != null)
                          Text("المنطقة المحددة: $_selectedZoneName", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                        else
                          const Text("لم يتم تحديد الموقع بعد", style: TextStyle(color: Colors.red)),
                        const SizedBox(height: 15),
                        ElevatedButton.icon(
                          onPressed: _pickLocation, 
                          icon: const Icon(Icons.map), 
                          label: Text(_selectedLocation == null ? "تحديد الموقع من الخريطة" : "تغيير الموقع"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  if (_selectedLocation != null) ...[
                    _buildInputRow("أمتار الكنب", _sofaMeters, (val) => setState(() => _sofaMeters = val), _sofaPrice),
                    const SizedBox(height: 20),
                    _buildInputRow("أمتار الزل (السجاد)", _rugMeters, (val) => setState(() => _rugMeters = val), _rugPrice),
                    const SizedBox(height: 40),
                    _buildSummaryCard(),
                    const SizedBox(height: 30),
                    _buildNextButton(),
                  ] else ...[
                     const Center(child: Text("يرجى تحديد الموقع لرؤية الأسعار المخصصة لمنطقتك المحددة", style: TextStyle(color: Colors.grey))),
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

  Widget _buildInputRow(String label, double value, Function(double) onChanged, double pricePerMeter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text("($pricePerMeter ر.س/متر)", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAdjustButton(Icons.remove, () {
                if (value > 0) onChanged(value - 1);
              }),
              Container(width: 80, alignment: Alignment.center, child: Text("${value.toInt()}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
              _buildAdjustButton(Icons.add, () => onChanged(value + 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFF6366F1))),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
      child: Column(
        children: [
          _buildSummaryRow("المجموع الفرعي:", subTotal),
          const Divider(height: 20, thickness: 1),
          _buildSummaryRow("ضريبة القيمة المضافة (15%):", vat, isVat: true),
          const Divider(height: 20, thickness: 2, color: Color(0xFFE2E8F0)),
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

  Widget _buildSummaryRow(String label, double value, {bool isVat = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: TextStyle(color: isVat ? Colors.grey : const Color(0xFF64748B), fontWeight: isVat ? FontWeight.normal : FontWeight.w600)), Text("${value.toStringAsFixed(2)} ر.س", style: TextStyle(fontWeight: FontWeight.bold, color: isVat ? Colors.grey : const Color(0xFF1E293B)))],
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _handleNext,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 4),
        child: const Text("متابعة لملخص الدفع", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}
