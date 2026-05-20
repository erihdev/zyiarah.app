import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/utils/status_util.dart';

class AdminOrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const AdminOrderDetailsScreen({super.key, required this.orderId});

  @override
  State<AdminOrderDetailsScreen> createState() => _AdminOrderDetailsScreenState();
}

class _AdminOrderDetailsScreenState extends State<AdminOrderDetailsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahMessagingService _notificationService = ZyiarahMessagingService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  bool _isLoading = true;
  Map<String, dynamic>? _orderData;

  String _currentStatus = 'pending';
  String? _selectedDriverId;
  String? _selectedDriverName;
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoadingDrivers = true;

  final List<String> _statuses = ['pending', 'assigned', 'in_progress', 'completed', 'cancelled'];
  
  String _getStatusText(String status) {
    return ZyiarahStatus.getOrderStatus(status)['text'];
  }

  @override
  void initState() {
    super.initState();
    _fetchOrder();
  }

  Future<void> _fetchOrder() async {
    try {
      final doc = await _db.collection('orders').doc(widget.orderId).get();
      
      // Try maintenance collection if not in orders
      DocumentSnapshot? finalDoc = doc;
      if (!finalDoc.exists) {
        finalDoc = await _db.collection('maintenance_requests').doc(widget.orderId).get();
      }

      if (finalDoc.exists && mounted) {
        final data = finalDoc.data() as Map<String, dynamic>;
        
        // Unified field extraction with fallbacks
        String? phone = data['user_phone'] ?? data['userPhone'] ?? data['client_phone'];
        String? name = data['client_name'] ?? data['userName'];
        
        // If phone/name is missing in order doc, fetch from user profile
        final userId = data['client_id'] ?? data['userId'];
        if (userId != null && (phone == null || name == null)) {
          try {
            final userDoc = await _db.collection('users').doc(userId).get();
            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;
              phone ??= userData['phone'];
              name ??= userData['name'];
            }
          } catch (e) {
             debugPrint("Error fetching fallback user data: $e");
          }
        }

        setState(() {
          _orderData = {
            ...data,
            'user_phone': phone,
            'client_name': name,
          };
          _currentStatus = _orderData?['status'] ?? 'pending';
          _selectedDriverId = _orderData?['driver_id'];
          _selectedDriverName = _orderData?['assigned_driver'];
          _isLoading = false;
        });
        _fetchDrivers();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDrivers() async {
    try {
      final snapshotF = _db.collection('drivers').where('is_active', isEqualTo: true).get();
      final activeOrdersF = _db.collection('orders')
          .where('status', whereIn: ['assigned', 'in_progress'])
          .get();
      final results = await Future.wait([snapshotF, activeOrdersF]);
      final snapshot = results[0];
      final activeOrders = results[1];

      final busyDriverIds = activeOrders.docs
          .map((d) => d.data()['driver_id'] as String?)
          .whereType<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _drivers = snapshot.docs
              .where((doc) => !busyDriverIds.contains(doc.id))
              .map((doc) => {
                'id': doc.id,
                'name': doc.data()['name'] ?? 'بدون اسم',
              }).toList();
          _isLoadingDrivers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDrivers = false);
    }
  }

  Future<void> _updateOrder() async {
    setState(() => _isLoading = true);
    try {
      final bool isNewAssignment = _selectedDriverId != null &&
          _selectedDriverId != _orderData?['driver_id'];

      // Build the atomic Firestore update payload
      final Map<String, dynamic> updatePayload = {'status': _currentStatus};
      if (_selectedDriverId != null) {
        updatePayload['driver_id'] = _selectedDriverId!;
        updatePayload['driver_name'] = _selectedDriverName ?? '';
        updatePayload['assigned_at'] = FieldValue.serverTimestamp();
        // Auto-promote from pending to assigned when a driver is selected
        if (_currentStatus == 'pending') {
          updatePayload['status'] = 'assigned';
          setState(() => _currentStatus = 'assigned');
        }
      }

      // 1. Write driver fields + status atomically
      await _db.collection('orders').doc(widget.orderId).update(updatePayload);

      // 2. Invoke unified order service for side-effects
      //    (wallet refund, Qatrat, etc.) only for terminal statuses
      if (_currentStatus == 'completed' || _currentStatus == 'cancelled') {
        await _orderService.updateOrderStatus(
          widget.orderId,
          _currentStatus,
          driverId: _selectedDriverId,
        );
      }

      // 3. Audit: dedicated assignment entry when driver changes
      if (isNewAssignment) {
        await ZyiarahAuditService().logAction(
          action: ZyiarahAuditService.actionAssignDriver,
          targetId: widget.orderId,
          details: {
            'order_code': _orderData?['code'] ?? widget.orderId.substring(0, 8),
            'driver_id': _selectedDriverId!,
            'driver_name': _selectedDriverName ?? '',
          },
        );
        // 4. Immediate push alert to the assigned driver
        await _notificationService.notifyDriverOfAssignment(
          _selectedDriverId!,
          widget.orderId,
        );
      }

      // 5. Always log the status update
      await ZyiarahAuditService().logAction(
        action: ZyiarahAuditService.actionUpdateOrderStatus,
        targetId: widget.orderId,
        details: {
          'order_code': _orderData?['code'] ?? widget.orderId.substring(0, 8),
          'new_status': _currentStatus,
          'old_status': _orderData?['status'] ?? 'pending',
          'assigned_driver': _selectedDriverName ?? 'None',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            isNewAssignment
                ? 'تم تعيين ${_selectedDriverName ?? "السائق"} وإرسال إشعار فوري ✅'
                : 'تم حفظ تعديلات الطلب بنجاح ✅',
          ),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('فشل تحديث الطلب — تحقق من اتصالك بالإنترنت'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  
  Future<void> _openWhatsApp(String phone) async {
    try {
      final url = Uri.parse("https://wa.me/$phone");
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح واتساب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    if (_orderData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الطلب')),
        body: const Center(child: Text("الطلب غير موجود")),
      );
    }

    final data = _orderData!;
    final userPhone = data['user_phone'] ?? '';
    final code = data['code'] ?? widget.orderId.substring(0, 8).toUpperCase();
    
    DateTime date = DateTime.now();
    if (data['created_at'] != null) {
      date = (data['created_at'] as Timestamp).toDate();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلب #$code", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("معلومات الخدمة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2563EB))),
                    const Divider(),
                    ListTile(
                      title: const Text("الخدمة"), 
                      subtitle: Text(data['service_name'] ?? data['serviceType'] ?? data['service_type'] ?? '-'),
                    ),
                    ListTile(
                      title: const Text("المبلغ الإجمالي"), 
                      subtitle: Text("${data['final_amount'] ?? data['amount'] ?? data['totalAmountPaid'] ?? data['quotePrice'] ?? 0} ر.س"),
                    ),
                    ListTile(title: const Text("تاريخ إنشاء الطلب"), subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(date))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("معلومات العميل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2563EB))),
                    const Divider(),
                    ListTile(
                      title: const Text("رقم الجوال"), 
                      subtitle: Text(userPhone),
                      trailing: userPhone.isNotEmpty ? IconButton(
                        icon: const Icon(Icons.forum, color: Colors.green),
                        onPressed: () => _openWhatsApp(userPhone),
                      ) : null,
                    ),
                    if (data['location'] != null)
                      ListTile(
                        title: const Text("الموقع"),
                        subtitle: const Text("اضغط لفتح الخريطة"),
                        trailing: const Icon(Icons.map, color: Colors.blue),
                        onTap: () {
                           final GeoPoint pt = data['location'];
                           final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}");
                           launchUrl(url);
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("إدارة الطلب", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2563EB))),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text("حالة الطلب"),
                    DropdownButtonFormField<String>(
                      initialValue: _currentStatus,
                      items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(_getStatusText(s)))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _currentStatus = val);
                      },
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    const Text("تعيين السائق / العامل المسؤول"),
                    _isLoadingDrivers 
                      ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
                      : DropdownButtonFormField<String>(
                        initialValue: _selectedDriverId,
                        hint: const Text("اختر من قائمة الكوادر النشطة..."),
                        items: _drivers.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(d['name'] as String))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedDriverId = val;
                              _selectedDriverName = _drivers.firstWhere((d) => d['id'] == val)['name'];
                            });
                          }
                        },
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                        onPressed: _updateOrder,
                        child: const Text("حفظ التعديلات", style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
