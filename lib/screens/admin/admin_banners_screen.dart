import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class AdminBannersScreen extends StatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  State<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends State<AdminBannersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من حذف هذا البنر الإعلاني نهائياً؟"),
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
        await _db.collection('promo_banners').doc(id).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف البنر بنجاح")));
        
        ZyiarahAuditService().logAction(
          action: 'DELETE_BANNER',
          details: {'banner_id': id},
          targetId: id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
      }
    }
  }

  void _showBannerDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;
    final actionUrlCtrl = TextEditingController(text: data?['actionUrl'] ?? '');
    String? imageUrl = data?['imageUrl'];
    bool isActive = data?['isActive'] ?? true;
    int rank = data?['rank'] ?? 0;
    String selectedRoute = data?['routeType'] ?? 'whatsapp';
    bool isSaving = false;
    bool isUploading = false;

    final List<Map<String, String>> routingOptions = [
      {'value': 'whatsapp', 'label': 'رابط واتساب (خارجي)'},
      {'value': '/hourly_cleaning', 'label': 'خدمة النظافة بالساعة'},
      {'value': '/sofa_cleaning', 'label': 'خدمة تنظيف الكنب'},
      {'value': '/rug_cleaning', 'label': 'خدمة تنظيف الزل'},
      {'value': '/maintenance', 'label': 'طلب صيانة'},
      {'value': '/store', 'label': 'المتجر'},
      {'value': '/subscriptions', 'label': 'باقات الاشتراك'},
      {'value': '/support', 'label': 'الدعم الفني'},
      {'value': 'none', 'label': 'بدون توجيه (صورة فقط)'},
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(doc == null ? 'إضافة بنر جديد' : 'تعديل البنر', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving || isUploading)
                      const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF2563EB))),
                    
                    // Designing Tip
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Text("المقاس المفضل: نسبة 2:1 (مثل 1200×600 بكسل)", style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                    ),

                    // Image Section
                    GestureDetector(
                      onTap: isUploading || isSaving ? null : () async {
                        final source = await showModalBottomSheet<ImageSource>(
                          context: context,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(leading: const Icon(Icons.camera_alt), title: const Text("الكاميرا"), onTap: () => Navigator.pop(context, ImageSource.camera)),
                              ListTile(leading: const Icon(Icons.photo_library), title: const Text("معرض الصور"), onTap: () => Navigator.pop(context, ImageSource.gallery)),
                            ],
                          ),
                        );

                        if (source != null) {
                          final file = await _picker.pickImage(source: source, imageQuality: 70);
                          if (file != null) {
                            setDialogState(() => isUploading = true);
                            try {
                              final ref = FirebaseStorage.instance.ref().child('banners/${DateTime.now().millisecondsSinceEpoch}.jpg');
                              if (kIsWeb) {
                                await ref.putData(await file.readAsBytes());
                              } else {
                                await ref.putFile(File(file.path));
                              }
                              final url = await ref.getDownloadURL();
                              setDialogState(() { imageUrl = url; isUploading = false; });
                            } catch (e) {
                              setDialogState(() => isUploading = false);
                              if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الرفع: $e")));
                            }
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: imageUrl != null
                            ? ClipRRect(borderRadius: BorderRadius.circular(15), child: CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover))
                            : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey), Text("اضغط لرفع صورة")]),
                      ),
                    ),
                    const SizedBox(height: 20),

                    DropdownButtonFormField<String>(
                      value: selectedRoute,
                      decoration: const InputDecoration(labelText: 'توجيه العميل', border: OutlineInputBorder()),
                      items: routingOptions.map((e) => DropdownMenuItem(value: e['value'], child: Text(e['label']!))).toList(),
                      onChanged: (val) => setDialogState(() => selectedRoute = val!),
                    ),
                    if (selectedRoute == 'whatsapp') ...[
                      const SizedBox(height: 15),
                      TextField(controller: actionUrlCtrl, decoration: const InputDecoration(labelText: 'رابط الواتساب (اختياري)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link))),
                    ],
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: const Text('نشط (يظهر للعملاء)'),
                      value: isActive,
                      onChanged: (val) => setDialogState(() => isActive = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isSaving || isUploading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  onPressed: isSaving || isUploading ? null : () async {
                    if (imageUrl == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار صورة أولاً")));
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final newData = {
                        'imageUrl': imageUrl,
                        'routeType': selectedRoute,
                        'actionUrl': actionUrlCtrl.text.trim(),
                        'isActive': isActive,
                        'rank': rank,
                        'updated_at': FieldValue.serverTimestamp(),
                      };
                      if (doc == null) {
                        await _db.collection('promo_banners').add(newData);
                      } else {
                        await _db.collection('promo_banners').doc(doc.id).update(newData);
                      }
                      
                      ZyiarahAuditService().logAction(
                        action: doc == null ? 'CREATE_BANNER' : 'UPDATE_BANNER',
                        details: {
                          'route': newData['routeType'],
                          'banner_id': doc?.id ?? 'NEW',
                        },
                        targetId: doc?.id,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ ونشر"),
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
          title: Text('إدارة البنرات الإعلانية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showBannerDialog(),
          backgroundColor: const Color(0xFF2563EB),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('promo_banners').orderBy('rank').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text("لا توجد بنرات حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final bool isActive = data['isActive'] == true;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 1,
                        child: CachedNetworkImage(imageUrl: data['imageUrl'] ?? '', fit: BoxFit.cover),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isActive ? "✅ نشط" : "⚠️ مخفي", style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.green : Colors.red, fontSize: 13)),
                            Row(
                              children: [
                                IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20), onPressed: () => _showBannerDialog(doc: doc)),
                                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _deleteBanner(doc.id)),
                              ],
                            )
                          ],
                        ),
                      ),
                    ],
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
