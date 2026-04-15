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
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('services').orderBy('order_index').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final service = ZyiarahService.fromMap(
                  docs[index].id,
                  docs[index].data() as Map<String, dynamic>,
                );
                return _buildPremiumServiceCard(service);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPremiumServiceCard(ZyiarahService service) {
    final bool active = service.isActive;
    final Color accentColor = active ? const Color(0xFF4F46E5) : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: active ? accentColor.withValues(alpha: 0.1) : Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                // Stylized Icon Holder
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    ZyiarahService.getIcon(service.iconName),
                    color: accentColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Title and Subtitle
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
                                fontSize: 16,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          _buildStatusBadge(active),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        service.subtitle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32, thickness: 0.8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Pricing Info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "التسعير الحالي",
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      service.priceText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
                // Actions Area
                Row(
                  children: [
                    // Edit Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showEditPriceDialog(service),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_note_rounded, color: Colors.blueGrey, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Visibility Toggle
                    Transform.scale(
                      scale: 0.9,
                      child: Switch(
                        value: active,
                        onChanged: (val) => _toggleServiceStatus(service),
                        activeThumbColor: const Color(0xFF4F46E5),
                        activeTrackColor: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 3,
            backgroundColor: active ? const Color(0xFF10B981) : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            active ? "نشط" : "معطل",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: active ? const Color(0xFF059669) : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
