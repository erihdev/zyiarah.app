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
        details: {'service': service.name, 'status': !service.isActive ? 'نشط' : 'معطل'},
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
      child: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('services').orderBy('order_index').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("لا توجد خدمات، يمكنك إضافتها من لوحة الويب."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final service = ZyiarahService.fromMap(docs[index].id, docs[index].data() as Map<String, dynamic>);
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: service.isActive ? Colors.blue[50] : Colors.grey[200],
                    child: Icon(ZyiarahService.getIcon(service.iconName), color: service.isActive ? Colors.blue : Colors.grey),
                  ),
                  title: Text(service.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${service.subtitle}\n${service.priceText}"),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blueGrey),
                        onPressed: () => _showEditPriceDialog(service),
                      ),
                      Switch(
                        value: service.isActive,
                        onChanged: (val) => _toggleServiceStatus(service),
                        activeThumbColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
