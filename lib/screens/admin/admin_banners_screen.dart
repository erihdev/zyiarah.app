import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:zyiarah/utils/upload_content_type.dart';
import 'package:zyiarah/utils/banner_destination.dart';

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
        final docSnap = await _db.collection('promo_banners').doc(id).get().timeout(kNetCallTimeout);
        if (docSnap.exists) {
          final data = docSnap.data();
          final String? imageUrl = data?['imageUrl'];
          if (imageUrl != null && imageUrl.isNotEmpty) {
            // **الحذفُ خادميّ.** `storage.rules` لا تَقرأُ Firestore فلا
            // تَعرفُ الدورَ، وكانت تَسمحُ لأيِّ مسجَّلٍ بالحذف — فحُصِر
            // الحذفُ في `deleteStorageObject` بعد `_assertAdmin`. والفشلُ
            // يُقال: `debugPrint` وحدَه كان يَترُكُ كائناً معلّقاً بلا أثر.
            try {
              await FirebaseFunctions.instance
                  .httpsCallable('deleteStorageObject')
                  .call({'url': imageUrl})
                  .timeout(kNetCallTimeout);
            } catch (storageErr) {
              debugPrint('deleteStorageObject failed: $storageErr');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('حُذف السجل، وتعذّر حذف الصورة من المخزن'),
                    backgroundColor: Colors.orange));
              }
            }
          }
        }

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
    // القائمةُ أدناه تَقرأُ `== true` (وهو ما يَستعلمُه العميلُ)، وكان
    // افتراضُ الحوارِ `?? true` فيُقرأُ بانرٌ قديمٌ بلا الحقلِ «نشطاً» هنا
    // و«مخفيّاً» في الصفِّ نفسِه — تناقضٌ داخلَ شاشةٍ واحدة.
    bool isActive = data?['isActive'] == true;
    int rank = data?['rank'] ?? 0;
    String selectedRoute = data?['routeType'] ?? kBannerExternalRoute;
    // مكان الظهور: 'main' = البانر الرئيسي على الرئيسية، 'offers' = قسم العروض.
    // الغياب = 'main' كي تبقى كل البانرات القائمة على الرئيسية كما هي.
    String placement = data?['placement'] ?? 'main';
    bool isSaving = false;
    bool isUploading = false;

    // **القائمة مُشتقّة من الوجهات التي يقرؤها البنر فعلاً**
    // (`kBannerTargetOptions`) لا مكتوبة بيد: كانت ستّاً والسطحان يقرآن
    // سبعاً — فخدمة المكيفات مقروءة في الطرفين ولا سبيل للأدمن إليها.
    final List<Map<String, String>> routingOptions = [
      {'value': kBannerExternalRoute, 'label': 'رابط واتساب (خارجي)'},
      for (final o in kBannerTargetOptions.values)
        {'value': o.route, 'label': o.label},
      {'value': kBannerNoRoute, 'label': 'بدون توجيه (صورة فقط)'},
    ];
    // مستند قائم يحمل قيمة قديمة (`/rug_cleaning`) أو قيمة لا خيار لها:
    // بلا هذا يرمي DropdownButton («exactly one item with value») فيتعذّر
    // تعديل البنر إطلاقاً.
    if (!routingOptions.any((o) => o['value'] == selectedRoute)) {
      final BannerServiceTarget? legacy = kBannerServiceRoutes[selectedRoute];
      selectedRoute = legacy != null
          ? kBannerTargetOptions[legacy]!.route
          : kBannerNoRoute;
    }

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
                      const Padding(padding: EdgeInsets.only(bottom: 15), child: LinearProgressIndicator(color: Color(0xFF660033))),
                    
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text("المقاس المفضل: نسبة 2:1 (مثل 1200×600 بكسل)", style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                    ),

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
                          // maxWidth/maxHeight: imageQuality وحده يضغط JPEG دون تصغير الأبعاد —
                          // صورة كاميرا 4000×3000 كانت تُرفع كما هي (2-3MB) ويحمّلها كل عميل.
                          final file = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);
                          if (file != null) {
                            setDialogState(() => isUploading = true);
                            try {
                              final storageRef = FirebaseStorage.instance.ref().child('banners/${DateTime.now().millisecondsSinceEpoch}.jpg');
                              UploadTask uploadTask;
                              if (kIsWeb) {
                                // النوعُ يُصرَّحُ: `putData` بلا بياناتٍ
                                // وصفيّةٍ يَرفعُ octet-stream، وقاعدةُ
                                // المخزنِ تَحصرُ المسارَ في `image/*`.
                                uploadTask = storageRef.putData(
                                    await file.readAsBytes(),
                                    SettableMetadata(
                                        contentType:
                                            imageContentTypeFor(file.name)));
                              } else {
                                uploadTask = storageRef.putFile(
                                    File(file.path),
                                    SettableMetadata(
                                        contentType:
                                            imageContentTypeFor(file.path)));
                              }

                              final TaskSnapshot snapshot = await uploadTask;
                              if (snapshot.state == TaskState.success) {
                                final url = await snapshot.ref.getDownloadURL();
                                setDialogState(() { 
                                  imageUrl = url; 
                                  isUploading = false; 
                                });
                              } else {
                                throw Exception("Upload task ended with state: ${snapshot.state}");
                              }
                            } catch (e) {
                              setDialogState(() => isUploading = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الرفع: ${e.toString()}"), backgroundColor: Colors.redAccent));
                              }
                            }
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 160,
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
                      // احرس القيمة: بانر قديم قد يحمل مساراً غير موجود في العناصر → null بدل الانهيار.
                      initialValue: routingOptions.any((e) => e['value'] == selectedRoute)
                          ? selectedRoute
                          : null,
                      decoration: const InputDecoration(labelText: 'توجيه العميل', border: OutlineInputBorder()),
                      items: routingOptions.map((e) => DropdownMenuItem(value: e['value'], child: Text(e['label']!))).toList(),
                      onChanged: (val) => setDialogState(() => selectedRoute = val!),
                    ),
                    if (selectedRoute == 'whatsapp') ...[
                      const SizedBox(height: 15),
                      // التسمية تتبع الوجهة: الحقل **مطلوب** حين تكون الوجهة
                      // رابطاً خارجياً (هو الوجهة كلها)، وغير مستخدم مع وجهة
                      // داخلية. «(اختياري)» ثابتةً كانت تدعو إلى نشر بنر
                      // ضغطته لا تفعل شيئاً.
                      TextField(
                        controller: actionUrlCtrl,
                        decoration: InputDecoration(
                          labelText: selectedRoute == kBannerExternalRoute
                              ? 'الرابط الخارجي (مطلوب) — مع https://'
                              : 'الرابط الخارجي (غير مستخدم مع وجهة داخلية)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.link),
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),
                    // (تحكّم المالك) مكان ظهور البانر: الرئيسي أعلى الرئيسية أم قسم العروض.
                    DropdownButtonFormField<String>(
                      initialValue: placement,
                      decoration: const InputDecoration(
                          labelText: 'مكان الظهور', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'main', child: Text('البانر الرئيسي')),
                        DropdownMenuItem(value: 'offers', child: Text('قسم العروض')),
                      ],
                      onChanged: (val) => setDialogState(() => placement = val ?? 'main'),
                    ),
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
                    // **وجهة «رابط خارجي» بلا رابط تُنشر بنراً ميّتاً.** كان
                    // التحقّق على الصورة وحدها، والحقل مُسمّى «اختياري» —
                    // فبنر واتساب بلا رابط يُحفظ بـ«حفظ ونشر» ثم تُقابَل
                    // ضغطته بـ«هذا الرابط غير متاح حالياً» (وكانت صامتة
                    // تماماً في قسم العروض). ونفس قاعدة القارئ هنا:
                    // bannerExternalUrlIsUsable — فلا يُقبل رابط بلا مخطَّط.
                    if (selectedRoute == kBannerExternalRoute &&
                        !bannerExternalUrlIsUsable(actionUrlCtrl.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              "وجهة البنر رابط خارجي — يرجى إدخال رابط كامل يبدأ بـ https://، أو اختيار «بدون توجيه (صورة فقط)»")));
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final newData = {
                        'imageUrl': imageUrl,
                        'routeType': selectedRoute,
                        'actionUrl': actionUrlCtrl.text.trim(),
                        'isActive': isActive,
                        'placement': placement,
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
                      // كان الفشل صامتاً تماماً: الزر يرتد من «جاري الحفظ...» بلا أي
                      // مؤشر فيغلق الأدمن الحوار ظاناً أن البنر نُشر — نُظهر الخطأ
                      // بنفس نمط فشل الرفع أعلاه.
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الحفظ: ${e.toString()}"), backgroundColor: Colors.redAccent));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF660033), foregroundColor: Colors.white),
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ ونشر"),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => actionUrlCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('إدارة البنرات الإعلانية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showBannerDialog(),
          backgroundColor: const Color(0xFF660033),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('promo_banners').orderBy('rank').snapshots()
            .firstEventTimeout(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            // فشل البث كان يُعرض كقائمة فارغة — خطأ صريح مع إعادة محاولة.
            if (snapshot.hasError) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
                const SizedBox(height: 10),
                Text('تعذّر تحميل البيانات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.red)),
                TextButton(onPressed: () => setState(() {}), child: const Text('إعادة المحاولة')),
              ]));
            }
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
                            Row(children: [
                              Text(isActive ? "✅ نشط" : "⚠️ مخفي", style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.green : Colors.red, fontSize: 13)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF660033).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (data['placement'] ?? 'main') == 'offers' ? 'قسم العروض' : 'رئيسي',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF660033)),
                                ),
                              ),
                            ]),
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
