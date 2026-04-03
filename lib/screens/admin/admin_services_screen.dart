import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/models/service_model.dart';

class AdminServicesScreen extends StatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  State<AdminServicesScreen> createState() => _AdminServicesScreenState();
}

class _AdminServicesScreenState extends State<AdminServicesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _toggleServiceStatus(ZyiarahService service) async {
    try {
      await _db.collection('services').doc(service.id).update({
        'is_active': !service.isActive,
      });
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

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text("تعديل تسعير: ${service.title}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: displayCtrl,
              decoration: const InputDecoration(labelText: "السعر المعروض (للعميل)", hintText: "مثال: من 50 ر.س"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "السعر الأساسي الرقمي"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              try {
                await _db.collection('services').doc(service.id).update({
                  'base_price': double.tryParse(priceCtrl.text) ?? service.basePrice,
                  'price_text': displayCtrl.text,
                });
                if (!dialogCtx.mounted) return;
                Navigator.pop(dialogCtx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم التحديث")));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
              }
            },
            child: const Text("حفظ التعديل"),
          ),
        ],
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
