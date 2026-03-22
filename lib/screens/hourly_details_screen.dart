import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/models/order_model.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class HourlyCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const HourlyCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<HourlyCleaningDetailsScreen> createState() => _HourlyCleaningDetailsScreenState();
}

class _HourlyCleaningDetailsScreenState extends State<HourlyCleaningDetailsScreen> {
  final TamaraService _tamaraService = TamaraService();
  int _selectedHours = 4;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isLoading = false;
  ZyiarahUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(user.uid, doc.data()!);
        });
      }
    }
  }

  // Pricing logic: Each hour is 40 SAR, minimum 2 hours (80 SAR), baseline or variable
  double get totalAmount {
    return _selectedHours * 40.0;
  }

  void _handleInitiateFlow() async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          serviceName: widget.serviceName,
          hours: _selectedHours,
          serviceDate: _selectedDate,
          amount: totalAmount,
        ),
      ),
    );

    if (result == null || result is! Map<String, dynamic>) {
      return; // المستخدم ألغى الاختيار أو لم يتم إرجاع الخريطة
    }

    final GeoPoint selectedLocation = result['location'];

    if (selectedLocation != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: widget.serviceName,
            amount: totalAmount,
            location: selectedLocation,
            hours: _selectedHours,
            serviceDate: _selectedDate,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) {
          Navigator.pop(context, true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تفاصيل ${widget.serviceName}"),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("حدد عدد الساعات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildHourSelector(),
                  const SizedBox(height: 30),
                  const Text("اختر التاريخ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildDatePicker(),
                  const SizedBox(height: 40),
                  _buildSummaryCard(),
                  const SizedBox(height: 30),
                  _buildNextButton(),
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5D1B5E)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [2, 3, 4, 5, 6].map((h) {
        bool isSelected = _selectedHours == h;
        return InkWell(
          onTap: () => setState(() => _selectedHours = h),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "$h",
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(15),
      ),
      child: CalendarDatePicker(
        initialDate: _selectedDate,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 30)),
        onDateChanged: (date) {
          setState(() => _selectedDate = date);
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF5D1B5E).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5D1B5E).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _buildSummaryRow("عدد الساعات", "$_selectedHours ساعة"),
          const Divider(),
          _buildSummaryRow("السعر لكل ساعة", "40.0 ر.س"),
          const Divider(),
          _buildSummaryRow("التاريخ", "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}"),
          const Divider(),
          _buildSummaryRow("الإجمالي", "$totalAmount ر.س", isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 18 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: isTotal ? 20 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.bold, color: isTotal ? Colors.green : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          shape: roundedRectangleCircular(15),
        ),
        onPressed: _handleInitiateFlow,
        child: const Text("متابعة لاختيار الموقع", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

roundedRectangleCircular(double radius) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
