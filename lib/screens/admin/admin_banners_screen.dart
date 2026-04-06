import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class AdminBannersScreen extends StatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  State<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends State<AdminBannersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _banners = [];

  @override
  void initState() {
    super.initState();
    _fetchBanners();
  }

  Future<void> _fetchBanners() async {
    try {
      final snapshot = await _db.collection('promo_banners').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _banners = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBannerDialog({DocumentSnapshot? doc}) {
    final Map<String, dynamic>? data = doc?.data() as Map<String, dynamic>?;

    final actionUrlCtrl = TextEditingController(text: data?['actionUrl'] ?? '');
    String uploadedImageUrl = data?['imageUrl'] ?? '';
    bool isActive = data?['isActive'] ?? true;
    int rank = data?['rank'] ?? (_banners.length + 1);
    String selectedRoute = data?['routeType'] ?? 'whatsapp';
    Uint8List? pickedImageBytes;
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
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(doc == null ? 'إضافة بنر إعلاني' : 'تعديل البنر', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue),
                                SizedBox(width: 8),
                                Expanded(child: Text("تنبيه هام للمصممين", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "للحصول على أفضل مظهر في شاشة العميل، يرجى تصميم البنر بحجم عرضي (نسبة 2:1).\n• العرض المقترح: 1200 بكسل\n• الارتفاع المقترح: 600 بكسل",
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      
                      // Image Piker
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                          if (image != null) {
                            final bytes = await image.readAsBytes();
                            setDialogState(() => pickedImageBytes = bytes);
                          }
                        },
                        child: Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.grey[200],
                            image: pickedImageBytes != null 
                                ? DecorationImage(image: MemoryImage(pickedImageBytes!), fit: BoxFit.cover)
                                : (uploadedImageUrl.isNotEmpty 
                                    ? DecorationImage(image: NetworkImage(uploadedImageUrl), fit: BoxFit.cover) 
                                    : null),
                          ),
                          child: pickedImageBytes == null && uploadedImageUrl.isEmpty
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey),
                                    Text("اضغط لاختيار صورة من الاستديو")
                                  ],
                                )
                              : null,
                        ),
                      ),
                      
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRoute,
                        decoration: const InputDecoration(labelText: 'توجيه العميل عند النقر', border: OutlineInputBorder()),
                        items: routingOptions.map((e) => DropdownMenuItem(value: e['value'], child: Text(e['label']!))).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedRoute = val);
                        },
                      ),
                      
                      if (selectedRoute == 'whatsapp') ...[
                        const SizedBox(height: 15),
                        TextField(
                          controller: actionUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'رابط الواتساب (https://wa.me/...)',
                            hintText: 'https://wa.me/966500000000',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text('حالة البنر (تفعيل / إخفاء)'),
                        value: isActive,
                        onChanged: (val) => setDialogState(() => isActive = val),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isUploading ? null : () => Navigator.pop(ctx),
                    child: Text('إلغاء', style: GoogleFonts.tajawal(color: Colors.grey)),
                  ),
                    ElevatedButton(
                      onPressed: isUploading ? null : () async {
                        if (pickedImageBytes == null && uploadedImageUrl.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار صورة')));
                          return;
                        }

                        setDialogState(() => isUploading = true);

                        try {
                          String finalUrl = uploadedImageUrl;
                          if (pickedImageBytes != null) {
                            final ref = FirebaseStorage.instance.ref().child('banners/${DateTime.now().millisecondsSinceEpoch}.jpg');
                            
                            // Upload as Data (Bytes) instead of File to support Web Platform
                            final uploadTask = ref.putData(pickedImageBytes!, SettableMetadata(contentType: 'image/jpeg'));
                            await uploadTask;
                            finalUrl = await ref.getDownloadURL();
                          }

                        final newData = {
                          'imageUrl': finalUrl,
                          'routeType': selectedRoute,
                          'actionUrl': actionUrlCtrl.text.trim(),
                          'isActive': isActive,
                          'rank': rank,
                        };

                        if (doc == null) {
                          await _db.collection('promo_banners').add(newData);
                        } else {
                          await _db.collection('promo_banners').doc(doc.id).update(newData);
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _fetchBanners();
                        }
                      } catch (e) {
                         if (context.mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الرفع: $e')));
                         }
                      } finally {
                        setDialogState(() => isUploading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                    child: isUploading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('حفظ ونشر', style: GoogleFonts.tajawal(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف البنر'),
          content: const Text('هل أنت متأكد من حذف هذا البنر؟'),
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
      await _db.collection('promo_banners').doc(id).delete();
      _fetchBanners();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('إدارة البنرات الإعلانية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _banners.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.view_carousel_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    Text('لا توجد بنرات إعلانية حالياً', style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey[600])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _banners.length,
                itemBuilder: (context, index) {
                  final doc = _banners[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final bool isActive = data['isActive'] == true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                data['imageUrl'] ?? '',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey.shade300,
                                  child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                ),
                              ),
                              if (!isActive)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  child: const Center(
                                    child: Text('غير مرئي للعملاء', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isActive ? 'مفعل ويظهر للعملاء' : 'مُعطل ومخفي',
                                  style: TextStyle(color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showBannerDialog(doc: doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteBanner(doc.id),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBannerDialog(),
        backgroundColor: const Color(0xFF2563EB),
        child: const Icon(Icons.add_photo_alternate, color: Colors.white),
      ),
    );
  }
}
