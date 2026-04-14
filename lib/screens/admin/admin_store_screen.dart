import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminStoreScreen extends StatefulWidget {
  const AdminStoreScreen({super.key});

  @override
  State<AdminStoreScreen> createState() => _AdminStoreScreenState();
}

class _AdminStoreScreenState extends State<AdminStoreScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  void _toggleProductVisibility(DocumentSnapshot doc) async {
    final isHidden = doc['is_hidden'] ?? false;
    await _db.collection('products').doc(doc.id).update({'is_hidden': !isHidden});
  }

  Future<void> _deleteProduct(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من حذف هذا المنتج نهائياً من المتجر؟"),
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
        await _db.collection('products').doc(id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف المنتج بنجاح")));
        }
        ZyiarahAuditService().logAction(
          action: 'DELETE_PRODUCT',
          details: {'product_id': id},
          targetId: id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
      }
    }
  }

  void _showProductDialog({DocumentSnapshot? product}) {
    final nameCtrl = TextEditingController(text: product?['name'] ?? '');
    final priceCtrl = TextEditingController(text: (product?['price'] ?? '').toString());
    final descCtrl = TextEditingController(text: product?['description'] ?? '');
    String? imageUrl = product?['image_url'];
    XFile? pickedFile;
    bool isSaving = false;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                product == null ? "إضافة منتج جديد" : "تعديل المنتج",
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving || isUploading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(color: Color(0xFF1E293B)),
                      ),
                    
                    // Image Section
                    GestureDetector(
                      onTap: isUploading || isSaving ? null : () async {
                        final source = await showModalBottomSheet<ImageSource>(
                          context: context,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.camera_alt),
                                title: const Text("الكاميرا"),
                                onTap: () => Navigator.pop(context, ImageSource.camera),
                              ),
                              ListTile(
                                leading: const Icon(Icons.photo_library),
                                title: const Text("معرض الصور"),
                                onTap: () => Navigator.pop(context, ImageSource.gallery),
                              ),
                            ],
                          ),
                        );

                        if (source != null) {
                          final file = await _picker.pickImage(imageSource: source, imageQuality: 70);
                          if (file != null) {
                            setDialogState(() {
                              pickedFile = file;
                              isUploading = true;
                            });

                            try {
                              final fileName = 'products/${DateTime.now().millisecondsSinceEpoch}.jpg';
                              final ref = FirebaseStorage.instance.ref().child(fileName);
                              
                              if (kIsWeb) {
                                await ref.putData(await file.readAsBytes());
                              } else {
                                await ref.putFile(File(file.path));
                              }
                              
                              final url = await ref.getDownloadURL();
                              setDialogState(() {
                                imageUrl = url;
                                isUploading = false;
                              });
                            } catch (e) {
                              setDialogState(() => isUploading = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل رفع الصورة: $e")));
                              }
                            }
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (c, u) => const Center(child: CircularProgressIndicator()),
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, size: 40, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text("اضغط لإضاة صورة", style: GoogleFonts.tajawal(color: Colors.grey)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    TextField(
                      controller: nameCtrl,
                      enabled: !isSaving && !isUploading,
                      decoration: const InputDecoration(labelText: "اسم المنتج", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: priceCtrl,
                      enabled: !isSaving && !isUploading,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "السعر (ر.س)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: descCtrl,
                      enabled: !isSaving && !isUploading,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: "وصف المنتج (اختياري)", border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving || isUploading ? null : () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: isSaving || isUploading ? null : () async {
                    if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty || imageUrl == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات واختيار صورة")));
                      return;
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      final data = {
                        'name': nameCtrl.text.trim(),
                        'price': double.tryParse(priceCtrl.text) ?? 0.0,
                        'description': descCtrl.text.trim(),
                        'image_url': imageUrl,
                        'is_hidden': product?['is_hidden'] ?? false,
                        'updated_at': FieldValue.serverTimestamp(),
                        if (product == null) 'created_at': FieldValue.serverTimestamp(),
                      };

                      if (product == null) {
                        await _db.collection('products').add(data);
                      } else {
                        await _db.collection('products').doc(product.id).update(data);
                      }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حفظ المنتج بنجاح ✅")));
                        }
                        
                        ZyiarahAuditService().logAction(
                          action: product == null ? 'CREATE_PRODUCT' : 'UPDATE_PRODUCT',
                          details: {
                            'name': data['name'],
                            'price': data['price'],
                            'product_id': product?.id ?? 'NEW',
                          },
                          targetId: product?.id,
                        );
                      } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحفظ: $e")));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ المنتج"),
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
          title: Text("إدارة المتجر", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showProductDialog(),
          backgroundColor: const Color(0xFF1E293B),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('products').orderBy('created_at', descending: true).snapshots(),
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
                    Icon(Icons.storefront_rounded, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text("لا توجد منتجات حالياً", style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _showProductDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text("أضف أول منتج"),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                    )
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final isHidden = data['is_hidden'] ?? false;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: data['image_url'] ?? '',
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorWidget: (c, u, e) => Container(width: 80, height: 80, color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['name'] ?? '',
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${data['price']} ر.س",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              if ((data['description'] ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    data['description']!,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                                  onPressed: () => _showProductDialog(product: doc),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                  onPressed: () => _deleteProduct(doc.id),
                                ),
                              ],
                            ),
                            Switch(
                              value: !isHidden,
                              onChanged: (val) => _toggleProductVisibility(doc),
                              activeColor: Colors.green,
                            ),
                            Text(isHidden ? "مخفي" : "نشط", style: TextStyle(fontSize: 9, color: isHidden ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                          ],
                        ),
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
