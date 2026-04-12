import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/services/audit_service.dart';

class AdminCouponsScreen extends StatefulWidget {
  const AdminCouponsScreen({super.key});

  @override
  State<AdminCouponsScreen> createState() => _AdminCouponsScreenState();
}

class _AdminCouponsScreenState extends State<AdminCouponsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _coupons = [];

  @override
  void initState() {
    super.initState();
    _fetchCoupons();
  }

  Future<void> _fetchCoupons() async {
    try {
      final snapshot = await _db.collection('promo_codes').get();
      if (mounted) {
        setState(() {
          _coupons = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCouponDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;

    final codeCtrl = TextEditingController(text: data?['code'] ?? '');
    final valueCtrl = TextEditingController(text: (data?['value'] ?? '').toString());
    final maxUsesCtrl = TextEditingController(text: (data?['maxUses'] ?? '100').toString());
    
    String type = data?['type'] ?? 'percentage';
    String status = data?['status'] ?? 'active';
    DateTime expiryDate = data?['expiry'] != null ? DateTime.tryParse(data!['expiry']) ?? DateTime.now().add(const Duration(days: 30)) : DateTime.now().add(const Duration(days: 30));
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(doc == null ? 'إضافة كود خصم' : 'تعديل كود الخصم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'كود الخصم (Letters & Numbers)'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('نسبة مئوية %', style: TextStyle(fontSize: 12)),
                              value: 'percentage',
                              // ignore: deprecated_member_use
                              groupValue: type,
                              // ignore: deprecated_member_use
                              onChanged: (val) => setDialogState(() => type = val!),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('مبلغ ثابت', style: TextStyle(fontSize: 12)),
                              value: 'fixed',
                              // ignore: deprecated_member_use
                              groupValue: type,
                              // ignore: deprecated_member_use
                              onChanged: (val) => setDialogState(() => type = val!),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: type == 'percentage' ? 'قيمة الخصم (من 1 إلى 100)' : 'قيمة الخصم بالريال (ر.س)'),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: maxUsesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'الحد الأقصى لمرات الاستخدام'),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          const Text('تاريخ الانتهاء: '),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: expiryDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 1000)),
                              );
                              if (picked != null) {
                                setDialogState(() => expiryDate = picked);
                              }
                            },
                            child: Text(intl.DateFormat('yyyy-MM-dd').format(expiryDate)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text('حالة الكود (فعال / غير فعال)'),
                        value: status == 'active',
                        onChanged: (val) {
                          setDialogState(() {
                            status = val ? 'active' : 'inactive';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إلغاء', style: GoogleFonts.tajawal(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      if (codeCtrl.text.isEmpty || valueCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات")));
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        final newData = {
                          'code': codeCtrl.text.trim().toUpperCase(),
                          'type': type,
                          'value': num.tryParse(valueCtrl.text) ?? 0,
                          'maxUses': int.tryParse(maxUsesCtrl.text) ?? 0,
                          'uses': data?['uses'] ?? 0,
                          'expiry': expiryDate.toIso8601String(),
                          'status': status,
                          'updatedAt': FieldValue.serverTimestamp(),
                        };

                        if (doc == null) {
                          await _db.collection('promo_codes').add(newData);
                          await _audit.logAction(
                            action: ZyiarahAuditService.actionCreateCoupon,
                            details: {'code': codeCtrl.text, 'value': valueCtrl.text, 'type': type},
                          );
                        } else {
                          await _db.collection('promo_codes').doc(doc.id).update(newData);
                          await _audit.logAction(
                            action: ZyiarahAuditService.actionUpdateCoupon,
                            details: {'code': codeCtrl.text, 'value': valueCtrl.text, 'type': type},
                            targetId: doc.id,
                          );
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حفظ كود الخصم بنجاح ✅")));
                          _fetchCoupons();
                        }
                      } catch (e) {
                         setDialogState(() => isSaving = false);
                         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الحفظ: $e")));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                    child: Text(isSaving ? "جاري الحفظ..." : 'حفظ الكود', style: GoogleFonts.tajawal(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _deleteCoupon(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الكود'),
          content: const Text('هل أنت متأكد من حذف كود الخصم نهائياً؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _db.collection('promo_codes').doc(id).delete();
        await _audit.logAction(
          action: ZyiarahAuditService.actionDeleteCoupon,
          details: {'id': id},
          targetId: id,
        );
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف الكود بنجاح")));
        _fetchCoupons();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الحذف الجذري: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('إدارة أكواد الخصم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFE11D48),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _coupons.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_offer_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    Text('لا توجد أكواد خصم متاحة حالياً', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey[600])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _coupons.length,
                itemBuilder: (context, index) {
                  final doc = _coupons[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final bool isActive = data['status'] == 'active';
                  final expiry = DateTime.tryParse(data['expiry'] ?? '') ?? DateTime.now();
                  final isExpired = expiry.isBefore(DateTime.now());

                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                    shadowColor: Colors.black.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.pink.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.pink.shade200, style: BorderStyle.solid),
                                ),
                                child: Text(
                                  data['code'] ?? '', 
                                  style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFE11D48), letterSpacing: 2),
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showCouponDialog(doc: doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteCoupon(doc.id),
                                  ),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('الخصم: ${data['value']} ${data['type'] == 'percentage' ? '%' : 'ر.س'}', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive && !isExpired ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isExpired ? 'منتهي الصلاحية' : (isActive ? 'فعال' : 'غير فعال'),
                                  style: TextStyle(color: isActive && !isExpired ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: (data['maxUses'] ?? 1) > 0 ? (data['uses'] ?? 0) / (data['maxUses'] ?? 1) : 0,
                            backgroundColor: Colors.grey[200],
                            color: const Color(0xFFE11D48),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('الاستخدام: ${data['uses'] ?? 0} من ${data['maxUses'] ?? 0}', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[700])),
                              Text('ينتهي في: ${intl.DateFormat('yyyy-MM-dd').format(expiry)}', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[700])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCouponDialog(),
        backgroundColor: const Color(0xFFE11D48),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
