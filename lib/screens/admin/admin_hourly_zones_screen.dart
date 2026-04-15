import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';

class AdminHourlyZonesScreen extends StatefulWidget {
  const AdminHourlyZonesScreen({super.key});

  @override
  State<AdminHourlyZonesScreen> createState() => _AdminHourlyZonesScreenState();
}

class _AdminHourlyZonesScreenState extends State<AdminHourlyZonesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _deleteZone(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من حذف هذه المنطقة نهائياً؟ سيؤثر هذا على توفر الخدمة في هذا النطاق."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _db.collection('hourly_zones').doc(id).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف المنطقة بنجاح")));
        
        ZyiarahAuditService().logAction(
          action: 'DELETE_ZONE',
          details: {'zone_id': id},
          targetId: id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
      }
    }
  }

  void _showZoneDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;
    final nameCtrl = TextEditingController(text: data?['name'] ?? '');
    final radiusCtrl = TextEditingController(text: data?['radiusKm']?.toString() ?? '15');
    
    final p1Ctrl = TextEditingController(text: data?['prices']?['1']?.toString() ?? '');
    final p4Ctrl = TextEditingController(text: data?['prices']?['4']?.toString() ?? '');
    final p5Ctrl = TextEditingController(text: data?['prices']?['5']?.toString() ?? '');
    final p6Ctrl = TextEditingController(text: data?['prices']?['6']?.toString() ?? '');
    final p8Ctrl = TextEditingController(text: data?['prices']?['8']?.toString() ?? '');

    final pSofaCtrl = TextEditingController(text: data?['sofaPrice']?.toString() ?? '35');
    final pRugCtrl = TextEditingController(text: data?['rugPrice']?.toString() ?? '15');

    int rank = data?['rank'] ?? 0;
    GeoPoint? selectedGeo = data?['centerLoc'] as GeoPoint?;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(doc == null ? "إضافة منطقة تغطية" : "تعديل المنطقة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving) const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF1E293B))),

                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنطقة (مثلاً: شمال الرياض)', border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    
                    // Map Selection
                    InkWell(
                      onTap: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => LocationPickerScreen(
                          serviceName: 'تحديد موقع المنطقة',
                          radius: double.tryParse(radiusCtrl.text) ?? 15.0,
                        )));
                        if (result != null && result is GeoPoint) {
                          setDialogState(() => selectedGeo = result);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                        child: Row(
                          children: [
                            const Icon(Icons.map_outlined, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text(selectedGeo == null ? "اضغط لتحديد مركز المنطقة من الخريطة" : "تم تحديد الإحداثيات بنجاح ✅", style: TextStyle(fontSize: 12, color: Colors.blue.shade900))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextField(controller: radiusCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نصف القطر للتغطية (كم)', border: OutlineInputBorder())),
                    
                    const Divider(height: 30),
                    const Text("أسعار النظافة بالساعة (ر.س):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: p1Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ساعة', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: p4Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '4 ساعات', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: p5Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '5 ساعات', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: p6Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6 ساعات', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Spacer(),
                        Expanded(child: TextField(controller: p8Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '8 ساعات', border: OutlineInputBorder()))),
                        const Spacer(),
                      ],
                    ),
                    
                    const Divider(height: 30),
                    const Text("أسعار الكنب والزل (ر.س للمتر):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: pSofaCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكنب', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: pRugCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الزل / السجاد', border: OutlineInputBorder()))),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    if (nameCtrl.text.isEmpty || selectedGeo == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات وتحديد الموقع")));
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final newData = {
                        'name': nameCtrl.text.trim(),
                        'centerLoc': selectedGeo,
                        'radiusKm': double.tryParse(radiusCtrl.text) ?? 15.0,
                        'prices': {
                          '1': double.tryParse(p1Ctrl.text) ?? 0,
                          '4': double.tryParse(p4Ctrl.text) ?? 0,
                          '5': double.tryParse(p5Ctrl.text) ?? 0,
                          '6': double.tryParse(p6Ctrl.text) ?? 0,
                          '8': double.tryParse(p8Ctrl.text) ?? 0,
                        },
                        'sofaPrice': double.tryParse(pSofaCtrl.text) ?? 35,
                        'rugPrice': double.tryParse(pRugCtrl.text) ?? 15,
                        'rank': rank,
                        'updated_at': FieldValue.serverTimestamp(),
                      };

                      if (doc == null) {
                        await _db.collection('hourly_zones').add(newData);
                      } else {
                        await _db.collection('hourly_zones').doc(doc.id).update(newData);
                      }
                      
                      ZyiarahAuditService().logAction(
                        action: doc == null ? 'CREATE_ZONE' : 'UPDATE_ZONE',
                        details: {
                          'name': newData['name'],
                          'zone_id': doc?.id ?? 'NEW',
                        },
                        targetId: doc?.id,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ المنطقة"),
                ),
              ],
            ),
          );
        },
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
          title: Text('إدارة ونطاقات الخدمة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showZoneDialog(),
          backgroundColor: const Color(0xFF1E293B),
          child: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('hourly_zones').orderBy('rank').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text("لا توجد مناطق تغطية حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: const Icon(Icons.location_on, color: Colors.blue)),
                    title: Text(data['name'] ?? '', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    subtitle: Text("نطاق التغطية: ${data['radiusKm']} كم", style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20), onPressed: () => _showZoneDialog(doc: doc)),
                        IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _deleteZone(doc.id)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
