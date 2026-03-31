import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahMaintenanceRequestScreen extends StatefulWidget {
  const ZyiarahMaintenanceRequestScreen({super.key});

  @override
  State<ZyiarahMaintenanceRequestScreen> createState() => _ZyiarahMaintenanceRequestScreenState();
}

class _ZyiarahMaintenanceRequestScreenState extends State<ZyiarahMaintenanceRequestScreen> {
  final Color brandPurple = const Color(0xFF5D1B5E);
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _selectedService;
  int _quantity = 1;
  String? _selectedFloor;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isSubmitting = false;

  final List<String> _services = ['صيانة مكيفات', 'غسيل مكيفات', 'صيانة اجهزة منزلية'];
  final List<String> _floors = ['الدور الأرضي', 'الدور الأول', 'الدور الثاني', 'الدور الثالث'];

  Future<void> _submitRequest() async {
    if (_selectedService == null || _selectedFloor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اكمال جميع الحقول')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _auth.currentUser;
      
      // Fetch user name
      String userName = 'عميل زيارة';
      try {
        final userDoc = await _firestore.collection('users').doc(user?.uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'عميل زيارة';
        }
      } catch (e) {
        // Fallback
      }

      // Generate unique 5-digit ID
      final requestId = (10000 + (90000 * (DateTime.now().microsecondsSinceEpoch % 1000000) / 1000000)).toInt().toString();

      final scheduledDateTime = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );

      await _firestore.collection('maintenance_requests').add({
        'requestId': requestId,
        'userId': user?.uid,
        'userName': userName,
        'userPhone': user?.phoneNumber,
        'serviceType': _selectedService,
        'quantity': _quantity,
        'floor': _selectedFloor,
        'scheduledAt': Timestamp.fromDate(scheduledDateTime),
        'status': 'under_review',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تم إرسال الطلب'),
            content: Text('طلبك رقم #$requestId قيد المراجعة الآن. سنقوم بإبلاغك فور قبوله لإتمام عملية الدفع.'),
            actions: [
              TextButton(onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }, child: const Text('حسناً'))
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الإرسال: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('طلب صيانة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('نوع الخدمة المطلوب'),
              _buildDropdown(_services, _selectedService, (val) => setState(() => _selectedService = val)),
              
              const SizedBox(height: 25),
              _buildSectionTitle('العدد (أجهزة / مكيفات)'),
              _buildQuantitySelector(),

              const SizedBox(height: 25),
              _buildSectionTitle('الدور / الطابق'),
              _buildDropdown(_floors, _selectedFloor, (val) => setState(() => _selectedFloor = val)),

              const SizedBox(height: 25),
              _buildSectionTitle('موعد الزيارة'),
              _buildDateTimePicker(),

              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                  ),
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('إرسال الطلب للمراجعة', style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 5),
      child: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B))),
    );
  }

  Widget _buildDropdown(List<String> items, String? selected, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          hint: Text('اختر من القائمة', style: GoogleFonts.tajawal(color: Colors.grey)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.tajawal()))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildQuantitySelector() {
    return Row(
      children: [
        _buildQtyBtn(Icons.remove, () => setState(() => _quantity = (_quantity > 1 ? _quantity - 1 : 1))),
        Container(
          width: 80,
          alignment: Alignment.center,
          child: Text('$_quantity', style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        _buildQtyBtn(Icons.add, () => setState(() => _quantity++)),
      ],
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: brandPurple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: brandPurple),
      ),
    );
  }

  Widget _buildDateTimePicker() {
    final dateStr = intl.DateFormat('yyyy/MM/dd').format(_selectedDate);
    final timeStr = _selectedTime.format(context);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context, 
                initialDate: _selectedDate, 
                firstDate: DateTime.now(), 
                lastDate: DateTime.now().add(const Duration(days: 90)),
                builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: brandPurple)), child: child!),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            child: _buildPickerBox(dateStr, Icons.calendar_today),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showTimePicker(
                context: context, 
                initialTime: _selectedTime,
                builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: brandPurple)), child: child!),
              );
              if (picked != null) setState(() => _selectedTime = picked);
            },
            child: _buildPickerBox(timeStr, Icons.access_time),
          ),
        ),
      ],
    );
  }

  Widget _buildPickerBox(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: brandPurple),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
