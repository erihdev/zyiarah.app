import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() => _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _deletePackage(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من حذف هذه الباقة؟ لن تظهر للعملاء الجدد، ولكن قد تظل نشطة للمشتركين الحاليين."),
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
        await _db.collection('subscription_packages').doc(id).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف الباقة بنجاح")));
        
        ZyiarahAuditService().logAction(
          action: 'DELETE_SUBSCRIPTION',
          details: {'subscription_id': id},
          targetId: id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
      }
    }
  }

  void _showPackageDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;
    final titleCtrl = TextEditingController(text: data?['title'] ?? '');
    final subtitleCtrl = TextEditingController(text: data?['subtitle'] ?? '');
    final priceCtrl = TextEditingController(text: data?['price'] ?? '');
    final featuresCtrl = TextEditingController(text: (data?['features'] as List<dynamic>?)?.join('\n') ?? '');
    bool isPremium = data?['isPremium'] ?? false;
    int rank = data?['rank'] ?? 0;
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
              title: Text(doc == null ? "إضافة باقة إشتراك" : "تعديل الباقة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving) const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF5D1B5E))),

                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم الباقة الرئيسية', border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    TextField(controller: subtitleCtrl, decoration: const InputDecoration(labelText: 'العنوان الفرعي/الوصف القصير', border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر الإجمالي (ر.س)', border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    TextField(
                      controller: featuresCtrl, 
                      maxLines: 4, 
                      decoration: const InputDecoration(labelText: 'الميزات (كل ميزة في سطر منفصل)', hintText: "مثال:\nزيارة أسبوعية\nتوفير 20%\nدعم فني", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: const Text('باقة مميزة (Golden)؟'),
                      value: isPremium,
                      onChanged: (val) => setDialogState(() => isPremium = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    if (titleCtrl.text.isEmpty || priceCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات الأساسية")));
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final newData = {
                        'title': titleCtrl.text.trim(),
                        'subtitle': subtitleCtrl.text.trim(),
                        'price': priceCtrl.text.trim(),
                        'features': featuresCtrl.text.trim().split('\n').where((s) => s.isNotEmpty).toList(),
                        'isPremium': isPremium,
                        'rank': rank,
                        'updated_at': FieldValue.serverTimestamp(),
                      };
                      if (doc == null) {
                        await _db.collection('subscription_packages').add(newData);
                      } else {
                        await _db.collection('subscription_packages').doc(doc.id).update(newData);
                      }
                      
                      ZyiarahAuditService().logAction(
                        action: doc == null ? 'CREATE_SUBSCRIPTION' : 'UPDATE_SUBSCRIPTION',
                        details: {
                          'title': newData['title'],
                          'price': newData['price'],
                        },
                        targetId: doc?.id,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ الباقة"),
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
          title: Text('إدارة باقات الاشتراك', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showPackageDialog(),
          backgroundColor: const Color(0xFF5D1B5E),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('subscription_packages').orderBy('rank').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text("لا توجد باقات متاحة حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final bool isPremium = data['isPremium'] == true;
                final List features = data['features'] ?? [];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isPremium ? Colors.amber : Colors.transparent, width: 2),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(data['title'] ?? '', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF5D1B5E)))),
                            Row(
                              children: [
                                IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20), onPressed: () => _showPackageDialog(doc: doc)),
                                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _deletePackage(doc.id)),
                              ],
                            )
                          ],
                        ),
                        Text(data['subtitle'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        const SizedBox(height: 8),
                        Text("${data['price']} ر.س", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                        const Divider(height: 24),
                        ...features.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 16, color: isPremium ? Colors.amber : const Color(0xFF5D1B5E)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(f.toString(), style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )),
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
