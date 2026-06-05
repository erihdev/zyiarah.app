import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

/// طابور المسار الثاني: طلبات (الكنب/الزل، الصيانة، المتجر) بانتظار اعتماد الإدارة.
/// تعتمدها الإدارة وتختار سائقاً + تاريخاً، فتتحول إلى scheduled وتظهر في جدول السائق.
class AdminApprovalScreen extends StatelessWidget {
  const AdminApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('بانتظار الاعتماد والتعيين',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('status', isEqualTo: 'pending_admin_approval')
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Text('تعذّر تحميل الطلبات، تحقق من الاتصال',
                      style: GoogleFonts.tajawal(color: Colors.grey)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs.toList()
              ..sort((a, b) {
                final at = (a.data() as Map?)?['created_at'] as Timestamp?;
                final bt = (b.data() as Map?)?['created_at'] as Timestamp?;
                if (at == null && bt == null) return 0;
                if (at == null) return 1;
                if (bt == null) return -1;
                return bt.compareTo(at);
              });

            if (docs.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('لا توجد طلبات بانتظار الاعتماد',
                      style: GoogleFonts.tajawal(color: Colors.grey)),
                ]),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, i) => _ApprovalCard(
                orderId: docs[i].id,
                data: docs[i].data() as Map<String, dynamic>,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _ApprovalCard({required this.orderId, required this.data});

  @override
  Widget build(BuildContext context) {
    final serviceType = data['service_type'] ?? data['service_name'] ?? 'خدمة';
    final clientName = data['client_name'] ?? 'عميل';
    final zone = data['zone_name'] as String?;
    final amount = (data['amount'] ?? 0).toString();
    final code = data['code'] ?? orderId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$serviceType',
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('#$code — $clientName',
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Text('$amount ر.س',
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900, color: const Color(0xFF5D1B5E))),
          ]),
          if (zone != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(zone, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openAssignSheet(context),
              icon: const Icon(Icons.how_to_reg, size: 18),
              label: Text('اعتماد وتعيين سائق',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D1B5E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAssignSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AssignSheet(orderId: orderId, data: data),
    );
  }
}

class _AssignSheet extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _AssignSheet({required this.orderId, required this.data});

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  List<Map<String, dynamic>> _drivers = [];
  String? _selectedDriverId;
  late DateTime _selectedDate;
  int _selectedHour = 10;
  bool _loadingDrivers = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // مبدئياً: تاريخ الطلب إن وُجد، وإلا غداً
    final sd = (widget.data['service_date'] as Timestamp?)?.toDate();
    _selectedDate = sd ?? DateTime.now().add(const Duration(days: 1));
    _selectedHour = sd?.hour ?? 10;
    _fetchDrivers();
  }

  Future<void> _fetchDrivers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .where('is_active', isEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        _drivers = snap.docs
            .map((d) => {
                  'id': d.id,
                  'name': d.data()['name'] ?? 'سائق',
                  'zone': d.data()['zone_name'] ?? '',
                })
            .toList();
        _loadingDrivers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDrivers = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر سائقاً أولاً')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final scheduled = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedHour);
      await FirebaseFunctions.instance.httpsCallable('approveAndAssignOrder').call({
        'orderId': widget.orderId,
        'driverId': _selectedDriverId,
        'scheduledIso': scheduled.toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم اعتماد الطلب وإسناده للسائق بنجاح'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التعيين: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اعتماد وتعيين الطلب',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),

            // اختيار السائق
            Text('السائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_loadingDrivers)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_drivers.isEmpty)
              Text('لا يوجد سائقون نشطون', style: GoogleFonts.tajawal(color: Colors.red))
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedDriverId,
                isExpanded: true,
                hint: Text('اختر سائقاً', style: GoogleFonts.tajawal()),
                items: _drivers
                    .map((d) => DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text(
                            (d['zone'] as String).isNotEmpty
                                ? '${d['name']} — ${d['zone']}'
                                : d['name'] as String,
                            style: GoogleFonts.tajawal(),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDriverId = v),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            const SizedBox(height: 16),

            // اختيار التاريخ والوقت
            Text('موعد المهمة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(intl.DateFormat('yyyy-MM-dd').format(_selectedDate),
                      style: GoogleFonts.tajawal()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedHour,
                  items: List.generate(15, (i) => i + 7)
                      .map((h) => DropdownMenuItem(
                            value: h,
                            child: Text('${h.toString().padLeft(2, '0')}:00',
                                style: GoogleFonts.tajawal()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedHour = v ?? 10),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5D1B5E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('تأكيد الاعتماد والتعيين',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
