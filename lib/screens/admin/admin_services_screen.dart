import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/models/service_model.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminServicesScreen extends StatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  State<AdminServicesScreen> createState() => _AdminServicesScreenState();
}

class _AdminServicesScreenState extends State<AdminServicesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();

  Future<void> _toggleServiceStatus(ZyiarahService service) async {
    try {
      await _db.collection('services').doc(service.id).update({
        'is_active': !service.isActive,
      });
      await _audit.logAction(
        action: ZyiarahAuditService.actionToggleService,
        details: {'service': service.title, 'status': !service.isActive ? 'نشط' : 'معطل'},
        targetId: service.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(service.isActive ? "تم إخفاء الخدمة" : "تم عرض الخدمة"),
        backgroundColor: service.isActive ? Colors.orange : Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ")));
    }
  }

  void _showEditPriceDialog(ZyiarahService service) {
    TextEditingController priceCtrl = TextEditingController(text: service.basePrice.toString());
    TextEditingController displayCtrl = TextEditingController(text: service.priceText);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text("تعديل تسعير: ${service.title}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSaving)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 15),
                      child: LinearProgressIndicator(color: Color(0xFF1E293B)),
                    ),
                  TextField(
                    controller: displayCtrl,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: "السعر المعروض (للعميل)", hintText: "مثال: من 50 ر.س", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: priceCtrl,
                    enabled: !isSaving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "السعر الأساسي الرقمي", border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    setDialogState(() => isSaving = true);
                    try {
                      final double newPrice = double.tryParse(priceCtrl.text) ?? service.basePrice;
                      await _db.collection('services').doc(service.id).update({
                        'base_price': newPrice,
                        'price_text': displayCtrl.text,
                        'updated_at': FieldValue.serverTimestamp(),
                      });
                      
                      await _audit.logAction(
                        action: ZyiarahAuditService.actionUpdateServicePrice,
                        details: {'service': service.title, 'price': newPrice, 'display': displayCtrl.text},
                        targetId: service.id,
                      );

                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم التحديث الجذري بنجاح ✅")));
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (dialogCtx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في التحديث: $e")));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ التعديل", style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            "إدارة الخدمات",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
            ),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('services').orderBy('order_index').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cleaning_services_outlined, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      const Text("لا توجد خدمات حالياً، يرجى إضافتها من لوحة القيادة."),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final service = ZyiarahService.fromMap(
                    docs[index].id,
                    docs[index].data() as Map<String, dynamic>,
                  );
                  return _buildModernServiceIntelligenceCard(service);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModernServiceIntelligenceCard(ZyiarahService service) {
    final bool active = service.isActive;
    final Color accentColor = active ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8);
    
    // Simulate some business logic details (In a real app, these would come from sub-streams)
    final String ordersCount = active ? "12 طلب نشط" : "متوقف";
    final String rating = active ? "4.8" : "-";

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Decorative Background Element
            Positioned(
              left: -20,
              top: -20,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: accentColor.withValues(alpha: 0.03),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon with Glow
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor.withValues(alpha: 0.15), accentColor.withValues(alpha: 0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: accentColor.withValues(alpha: 0.1), width: 1.5),
                        ),
                        child: Icon(
                          ZyiarahService.getIcon(service.iconName),
                          color: accentColor,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Core Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    service.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                _buildStatusChip(active),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              service.subtitle,
                              style: TextStyle(
                                color: Colors.blueGrey[400],
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Intelligence Metrics Row
                  Row(
                    children: [
                      _buildIntelligenceMetric(Icons.trending_up, ordersCount, const Color(0xFF10B981)),
                      const SizedBox(width: 12),
                      _buildIntelligenceMetric(Icons.star_rounded, rating, Colors.amber),
                      const Spacer(),
                      if (active && service.title.contains("تنظيف"))
                        _buildPopularityTag(),
                    ],
                  ),
                  const Divider(height: 48, thickness: 0.8),
                  // Controls Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "التسعير الإستراتيجي",
                            style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            service.priceText,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: active ? const Color(0xFF4F46E5) : Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Edit Action
                          InkWell(
                            onTap: () => _showEditPriceDialog(service),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 16, color: Color(0xFF475569)),
                                  SizedBox(width: 6),
                                  Text("تعديل", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Toggle Action
                          Transform.scale(
                            scale: 1,
                            child: Switch(
                              value: active,
                              onChanged: (val) => _toggleServiceStatus(service),
                              activeColor: const Color(0xFF4F46E5),
                              activeTrackColor: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: Colors.grey.shade300,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntelligenceMetric(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularityTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.whatshot, size: 14, color: Colors.orange),
          SizedBox(width: 6),
          Text(
            "الأكثر طلباً",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        active ? "نشط" : "معطل",
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: active ? const Color(0xFF059669) : Colors.orange.shade800,
        ),
      ),
    );
  }
}
