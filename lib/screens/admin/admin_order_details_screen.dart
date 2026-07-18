import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/widgets/service_meta_view.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/utils/status_util.dart';
import 'package:zyiarah/screens/map_screen.dart';

class AdminOrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const AdminOrderDetailsScreen({super.key, required this.orderId});

  @override
  State<AdminOrderDetailsScreen> createState() => _AdminOrderDetailsScreenState();
}

class _AdminOrderDetailsScreenState extends State<AdminOrderDetailsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  bool _isLoading = true;
  bool _fetchError = false; // تمييز فشل التحميل عن الطلب غير الموجود
  Map<String, dynamic>? _orderData;

  String _currentStatus = 'pending';
  String? _selectedDriverId;
  String? _selectedDriverName;
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoadingDrivers = true;

  // Canonical set of statuses the admin may set manually. The order's *actual*
  // current status (e.g. scheduled / on_the_way / pending_admin_approval / accepted
  // from the Direct Dispatch flow) is always merged in below so the dropdown never
  // throws an assertion when the value isn't in this base list.
  final List<String> _baseStatuses = [
    'pending', 'under_review', 'scheduled', 'assigned', 'accepted',
    'on_the_way', 'in_progress', 'completed', 'cancelled',
  ];

  List<String> get _statuses => [
        ..._baseStatuses,
        if (!_baseStatuses.contains(_currentStatus)) _currentStatus,
      ];
  
  String _getStatusText(String status) {
    return ZyiarahStatus.getOrderStatus(status)['text'];
  }

  @override
  void initState() {
    super.initState();
    _fetchOrder();
  }

  Future<void> _fetchOrder() async {
    if (mounted) setState(() { _isLoading = true; _fetchError = false; });
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
      if (mounted) setState(() { _isLoading = false; _fetchError = true; });
    }
  }

  Future<void> _fetchDrivers() async {
    try {
      final snapshotF = _db.collection('drivers').where('is_active', isEqualTo: true).get();
      final activeOrdersF = _db.collection('orders')
          // كل الحالات النشطة الفعلية — لولا scheduled/on_the_way/accepted يظهر
          // سائق مشغول كأنه متاح ويُحجز مرتين.
          .where('status', whereIn: ['assigned', 'scheduled', 'on_the_way', 'in_progress', 'accepted'])
          .get();
      final results = await Future.wait([snapshotF, activeOrdersF]);
      final snapshot = results[0];
      final activeOrders = results[1];

      // نستثني الطلب الحالي: سائقه المُسنَد ليس «مشغولاً» بالنسبة لهذا الطلب، وإلا
      // اختفى من القائمة وظهر المنسدل فارغاً ولم يعُد الأدمن يرى من هو المُعيَّن.
      final busyDriverIds = activeOrders.docs
          .where((d) => d.id != widget.orderId)
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
      final String oldStatus = _orderData?['status'] ?? 'pending';

      if (_currentStatus == 'cancelled' && oldStatus != 'cancelled') {
        // Route through the unified cancel so the refund flag (needs_refund),
        // driver release (freeDriverOnOrderCancel) and notifications all fire.
        // A direct status write would skip every side-effect (silent no-refund).
        await _orderService.cancelOrder(widget.orderId, cancelledBy: 'admin');
      } else if (_currentStatus == 'completed' && oldStatus != 'completed') {
        // Unified completion: server rewards + driver release + end_time. Reads the
        // OLD status (we don't pre-write) so updateOrderStatus doesn't early-return.
        await _orderService.updateOrderStatus(
          widget.orderId,
          'completed',
          driverId: _selectedDriverId,
          adminOverride: true, // إكمال يدوي إداري — يتجاوز فرض التسلسل
        );
      } else {
        // Non-terminal: assignment / manual status override written directly.
        final Map<String, dynamic> updatePayload = {'status': _currentStatus};
        if (_selectedDriverId != null) {
          updatePayload['driver_id'] = _selectedDriverId!;
          updatePayload['driver_name'] = _selectedDriverName ?? '';
          updatePayload['assigned_driver'] = _selectedDriverName ?? '';
          updatePayload['assigned_at'] = FieldValue.serverTimestamp();
          // scheduled_at لازم لتذكير الساعة (remindDriversUpcomingTasks يستعلم به).
          // كان مفقوداً في هذا المسار فتفوت الطلبات المُسندة يدوياً تذكيرَ السائق.
          final sd = _orderData?['service_date'];
          if (sd is Timestamp) updatePayload['scheduled_at'] = sd;
          // Promote to 'scheduled' (a state the driver CAN advance and which shows in
          // the driver's active-orders stream) — not the dead-end 'assigned'.
          if (_currentStatus == 'pending') {
            updatePayload['status'] = 'scheduled';
            setState(() => _currentStatus = 'scheduled');
          }
        }
        await _db.collection('orders').doc(widget.orderId).update(updatePayload);
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
        // ملاحظة: لا نُرسل إشعار تعيين يدوياً — كتابة driver_id أعلاه تُطلق المُشغّل
        // الخادمي notifyDriverOnAssignment الذي يُشعِر السائق (push + سجل). كان
        // الاستدعاء الصريح هنا يُنتج إشعاراً ثانياً مكرّراً بنص مختلف.
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

      // نُحدّث _orderData من الخادم بعد الحفظ. بدونه يبقى driver_id/status قديماً في
      // الذاكرة، فحفظٌ ثانٍ يحسب isNewAssignment=true مجدداً فيُعيد كتابة driver_id
      // (يُطلق إشعار تعيين مكرّراً) ويُضيف سجلّ تدقيق مكرّراً في كل ضغطة.
      await _fetchOrder();

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

  
  /// Calls a Moyasar admin Cloud Function (refund / void / capture).
  Future<void> _moyasarOperation({
    required String functionName,
    required String label,
    required String paymentId,
    int? amountHalalas,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        content: Text(
          amountHalalas != null
              ? 'هل تريد تنفيذ "$label" بمبلغ ${(amountHalalas / 100).toStringAsFixed(2)} ر.س؟'
              : 'هل أنت متأكد من تنفيذ "$label"؟ لا يمكن التراجع.',
          style: GoogleFonts.tajawal(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text('تأكيد', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(functionName);
      await callable.call({
        'paymentId': paymentId,
        'orderId': widget.orderId,
        if (amountHalalas != null) 'amountHalalas': amountHalalas,
      });

      // Refresh order data
      await _fetchOrder();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم تنفيذ "$label" بنجاح ✅', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.green,
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'فشل تنفيذ العملية', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ غير متوقع: $e', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red.shade700,
        ));
      }
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

  Widget _buildMoyasarOperationsCard(Map<String, dynamic> data) {
    final String paymentId = data['moyasar_payment_id'] as String? ?? '';
    final String moyasarStatus = data['moyasar_status'] as String? ?? data['payment_status'] as String? ?? '';
    final double amount = double.tryParse('${data['final_amount'] ?? data['amount'] ?? 0}') ?? 0.0;

    // Determine available operations per Moyasar docs
    final bool canVoid = moyasarStatus == 'authorized' ||
        moyasarStatus == 'paid' ||
        moyasarStatus == 'captured';
    final bool canRefund = moyasarStatus == 'paid' || moyasarStatus == 'captured';
    final bool canCapture = moyasarStatus == 'authorized';
    final bool alreadyFinal = moyasarStatus == 'refunded' || moyasarStatus == 'voided';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: const Color(0xFFF0FDF4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment_rounded, color: Color(0xFF16A34A), size: 20),
                const SizedBox(width: 8),
                Text(
                  'عمليات الدفع — Moyasar',
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
            const Divider(),
            // Payment ID chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      paymentId,
                      style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _moyasarStatusColor(moyasarStatus).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _moyasarStatusLabel(moyasarStatus),
                      style: GoogleFonts.tajawal(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _moyasarStatusColor(moyasarStatus),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (alreadyFinal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'تمت المعالجة النهائية لهذه العملية (${_moyasarStatusLabel(moyasarStatus)})',
                  style: GoogleFonts.tajawal(color: Colors.grey.shade600, fontSize: 13),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  // Capture button (for authorized/manual payments)
                  if (canCapture)
                    _operationButton(
                      label: 'تحصيل المبلغ',
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF2563EB),
                      onTap: () => _moyasarOperation(
                        functionName: 'moyasarCapturePayment',
                        label: 'تحصيل المبلغ',
                        paymentId: paymentId,
                      ),
                    ),

                  // Void button
                  if (canVoid)
                    _operationButton(
                      label: 'إلغاء العملية',
                      icon: Icons.cancel_outlined,
                      color: const Color(0xFFD97706),
                      onTap: () => _moyasarOperation(
                        functionName: 'moyasarVoidPayment',
                        label: 'إلغاء العملية',
                        paymentId: paymentId,
                      ),
                    ),

                  // Full Refund button
                  if (canRefund)
                    _operationButton(
                      label: 'استرداد كامل',
                      icon: Icons.undo_rounded,
                      color: const Color(0xFFDC2626),
                      onTap: () => _moyasarOperation(
                        functionName: 'moyasarRefundPayment',
                        label: 'استرداد كامل',
                        paymentId: paymentId,
                      ),
                    ),

                  // Partial Refund (50%)
                  if (canRefund && amount > 0)
                    _operationButton(
                      label: 'استرداد جزئي (50%)',
                      icon: Icons.remove_circle_outline,
                      color: const Color(0xFF7C3AED),
                      onTap: () => _moyasarOperation(
                        functionName: 'moyasarRefundPayment',
                        label: 'استرداد جزئي (50%)',
                        paymentId: paymentId,
                        amountHalalas: (amount * 0.5 * 100).round(),
                      ),
                    ),
                ],
              ),

            // Tip from Moyasar docs
            if (canVoid && !alreadyFinal)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '💡 يُفضّل الإلغاء على الاسترداد متى أمكن — الإلغاء أسرع ولا يتضمن رسوماً',
                  style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _operationButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: GoogleFonts.tajawal(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Color _moyasarStatusColor(String status) {
    return switch (status) {
      'paid' || 'captured' => const Color(0xFF16A34A),
      'authorized' => const Color(0xFF2563EB),
      'refunded' => const Color(0xFF7C3AED),
      'voided' => const Color(0xFF6B7280),
      'failed' || 'abandoned' => const Color(0xFFDC2626),
      _ => const Color(0xFF6B7280),
    };
  }

  String _moyasarStatusLabel(String status) {
    return switch (status) {
      'paid' => 'مدفوع',
      'captured' => 'محصّل',
      'authorized' => 'محجوز',
      'refunded' => 'مُسترجع',
      'voided' => 'ملغي',
      'failed' => 'فاشل',
      'abandoned' => 'متروك',
      'initiated' => 'قيد الإجراء',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    if (_fetchError) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الطلب')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.orange),
              const SizedBox(height: 12),
              const Text('تعذّر تحميل الطلب، تحقّق من الاتصال'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _fetchOrder, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
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
    if (data['created_at'] is Timestamp) {
      date = (data['created_at'] as Timestamp).toDate();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلب #$code", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // تفصيل الخدمة (قطع الكنب بمقاساتها / المكيفات بأنواعها) — كان الطلب يصل
            // بمبلغ مجرّد فلا تملك الإدارة ما تدقّق به المبلغ إن اعترضت العميلة.
            ZyiarahServiceMetaView(meta: data['service_meta']),
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
                        title: Text("الموقع الجغرافي",
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          data['driver_location'] != null
                              ? "اضغط لتتبع السائق مباشرة على الخريطة"
                              : "اضغط لعرض موقع العميل",
                          style: GoogleFonts.tajawal(fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5D1B5E).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            data['driver_location'] != null
                                ? Icons.gps_fixed
                                : Icons.map_outlined,
                            color: const Color(0xFF5D1B5E),
                            size: 20,
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ZyiarahMapTracking(orderId: widget.orderId),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            // ── Moyasar Payment Operations ──────────────────────────────────────
            if (data['moyasar_payment_id'] != null) ...[
              const SizedBox(height: 15),
              _buildMoyasarOperationsCard(data),
            ],
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
                        // احرس القيمة: سائق الطلب الحالي قد يكون مشغولاً/غير نشط ومستبعَداً
                        // من القائمة → لو لم يكن ضمن العناصر اعرض التلميح بدل الانهيار.
                        initialValue: _drivers.any((d) => d['id'] == _selectedDriverId)
                            ? _selectedDriverId
                            : null,
                        hint: const Text("اختر من قائمة الكوادر النشطة..."),
                        items: _drivers.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(d['name'] as String))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedDriverId = val;
                              _selectedDriverName = _drivers.firstWhere((d) => d['id'] == val, orElse: () => {'name': ''})['name'];
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
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E)),
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
