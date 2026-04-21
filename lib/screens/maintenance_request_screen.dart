import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/counter_service.dart';
import 'package:zyiarah/services/location_service.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/services/zyiarah_comm_service.dart';
import 'package:zyiarah/screens/order_success_screen.dart';


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
      if (user == null) {
        throw Exception("يجب تسجيل الدخول لإرسال طلب");
      }
      
      // Fetch user name
      String userName = 'عميل زيارة';
      String userPhone = user.phoneNumber ?? '000000000';
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? 'عميل زيارة';
          userPhone = userDoc.data()?['phone'] ?? userPhone;
        }
      } catch (e) {
        debugPrint("User data fetch failed: $e");
      }

      // Generate Smart Sequential Code
      String orderCode;
      try {
        final seq = await ZyiarahCounterService().getNextOrderNumber();
        orderCode = ZyiarahOrderUtil.formatSmartCode(seq);
      } catch (e) {
        debugPrint("Counter service failed, using fallback code: $e");
        orderCode = "SRV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
      }

      final scheduledDateTime = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );

      // Get User Location
      GeoPoint? location;
      try {
        final pos = await ZyiarahLocationService().getCurrentLocation();
        if (pos != null) {
          location = GeoPoint(pos.latitude, pos.longitude);
        }
      } catch (e) {
        debugPrint("Location capture failed: $e");
      }

      await _firestore.collection('maintenance_requests').add({
        'requestId': orderCode,
        'code': orderCode,
        'userId': user.uid,
        'userName': userName,
        'userPhone': userPhone,
        'serviceType': _selectedService,
        'quantity': _quantity,
        'floor': _selectedFloor,
        'location': location, // New field for mapping
        'scheduledAt': Timestamp.fromDate(scheduledDateTime),
        'status': 'under_review',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Audit Log
      ZyiarahAuditService().logAction(
        action: 'CREATE_MAINTENANCE_REQUEST',
        details: {
          'code': orderCode,
          'user': userName,
          'service': _selectedService,
        },
        targetId: user.uid,
      );

      if (mounted) {
        // Trigger Notifications
        await ZyiarahNotificationTriggerService().notifyOrderCreated(
          clientId: user.uid,
          orderCode: orderCode,
          serviceName: _selectedService ?? 'صيانة',
          type: 'maintenance',
        );
        
        // إرسال تأكيد بالبريد الإلكتروني لطلب الصيانة (قيد المراجعة)
        await ZyiarahCommService().notifyNewOrder({
          'code': orderCode,
          'client_name': userName,
          'client_phone': userPhone,
          'service_type': _selectedService ?? 'صيانة وتكييف',
          'amount': 0.0, // قيد التسعير
          'zone': _selectedFloor ?? 'غير محدد',
          'date_time': intl.DateFormat('yyyy-MM-dd HH:mm').format(scheduledDateTime),
          'worker_count': _quantity,
          'coupon': 'لا يوجد',
        }, customerEmail: user.email);


        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ZyiarahOrderSuccessScreen(
              orderCode: orderCode,
              title: "تم استلام طلب الصيانة!",
              subtitle: "طلبك قيد المراجعة حالياً. سنقوم بتسعير الخدمة وإرسال عرض سعر لك فوراً للبدء.",
            ),
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
