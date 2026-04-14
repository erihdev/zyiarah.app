import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();
  final ZyiarahAuditService _audit = ZyiarahAuditService();

  void _showDriverDialog({String? docId, Map<String, dynamic>? currentData}) {
    final TextEditingController nameCtrl = TextEditingController(text: currentData?['name'] ?? '');
    final TextEditingController phoneCtrl = TextEditingController(text: currentData?['phone'] ?? '');
    final TextEditingController emailCtrl = TextEditingController(text: currentData?['email'] ?? '');
    final TextEditingController carInfoCtrl = TextEditingController(text: currentData?['car_info'] ?? '');
    final TextEditingController licenseCtrl = TextEditingController(text: currentData?['license_info'] ?? '');
    final TextEditingController nationalityCtrl = TextEditingController(text: currentData?['nationality'] ?? '');
    final TextEditingController idNumberCtrl = TextEditingController(text: currentData?['id_number'] ?? '');
    final TextEditingController idExpiryCtrl = TextEditingController(text: currentData?['id_expiry'] ?? '');
    
    String type = currentData?['type'] ?? 'driver'; 
    String? photoUrl = currentData?['photo_url'];
    Uint8List? selectedImageBytes;
    bool isSaving = false;
    
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(35), topRight: Radius.circular(35)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                children: [
                  // Premium Handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 50, height: 5,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(docId == null ? "تسجيل كادر جديد" : "تعديل بيانات الكادر", 
                                    style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                                  Text("يرجى ملء كافة البيانات الرسمية بدقة", style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              if (docId != null)
                                Container(
                                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(15)),
                                  child: IconButton(
                                    onPressed: isSaving ? null : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: AlertDialog(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            title: const Text("تأكيد الحذف"),
                                            content: const Text("هل أنت متأكد من حذف هذا الكادر نهائياً؟"),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                                child: const Text("حذف", style: TextStyle(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );

                                      if (confirm == true) {
                                        setDialogState(() => isSaving = true);
                                        try {
                                          await FirebaseFirestore.instance.collection('drivers').doc(docId).delete();
                                          await _audit.logAction(
                                            action: ZyiarahAuditService.actionDeleteDriver,
                                            details: {'id': docId},
                                            targetId: docId,
                                          );
                                          if (context.mounted) {
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف الكادر بنجاح")));
                                          }
                                        } catch (e) {
                                          setDialogState(() => isSaving = false);
                                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الحذف: $e")));
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 30),
                          
                          // Premium Image Picker
                          Center(
                            child: GestureDetector(
                              onTap: () async {
                                final XFile? image = await showModalBottomSheet<XFile?>(
                                  context: context,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
                                  builder: (context) => Container(
                                    padding: const EdgeInsets.symmetric(vertical: 25),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("اختيار صورة الكادر", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(height: 20),
                                        ListTile(
                                          leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF1E293B)),
                                          title: const Text("التقاط صورة فورية"),
                                          onTap: () async {
                                            final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);
                                            if (context.mounted) Navigator.pop(context, img);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF1E293B)),
                                          title: const Text("اختيار من الاستوديو"),
                                          onTap: () async {
                                            final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                                            if (context.mounted) Navigator.pop(context, img);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                
                                if (image != null) {
                                  final bytes = await image.readAsBytes();
                                  setDialogState(() => selectedImageBytes = bytes);
                                }
                              },
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(colors: [Color(0xFF1E293B), Colors.blueAccent]),
                                      boxShadow: [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))],
                                    ),
                                    child: CircleAvatar(
                                      radius: 60,
                                      backgroundColor: Colors.white,
                                      backgroundImage: selectedImageBytes != null 
                                        ? MemoryImage(selectedImageBytes!) 
                                        : (photoUrl != null ? NetworkImage(photoUrl!) : null) as ImageProvider?,
                                      child: (selectedImageBytes == null && photoUrl == null)
                                        ? const Icon(Icons.person_add_rounded, size: 50, color: Colors.grey)
                                        : null,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B), 
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),

                          _buildLuxuryField(controller: nameCtrl, label: "الاسم الكامل (كما في الهوية)", icon: Icons.badge_outlined, enabled: !isSaving),
                          const SizedBox(height: 20),
                          _buildLuxuryField(controller: phoneCtrl, label: "رقم الجوال النشط", icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone, enabled: !isSaving),
                          const SizedBox(height: 20),
                          _buildLuxuryField(controller: emailCtrl, label: "البريد الإلكتروني", icon: Icons.alternate_email_rounded, keyboardType: TextInputType.emailAddress, enabled: docId == null && !isSaving),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text("البيانات المهنية والرسمية", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: type,
                              items: const [
                                DropdownMenuItem(value: 'driver', child: Text("سائق توصيل (Delivery)")),
                                DropdownMenuItem(value: 'worker', child: Text("كادر تنظيف (Cleaning)")),
                              ],
                              onChanged: isSaving ? null : (val) {
                                if (val != null) setDialogState(() => type = val);
                              },
                              decoration: const InputDecoration(border: InputBorder.none, labelText: "تصنيف الموظف"),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          Row(
                            children: [
                              Expanded(child: _buildLuxuryField(controller: nationalityCtrl, label: "الجنسية", icon: Icons.public_rounded, enabled: !isSaving)),
                              const SizedBox(width: 15),
                              Expanded(child: _buildLuxuryField(controller: idNumberCtrl, label: "رقم الهوية / الإقامة", icon: Icons.perm_identity_rounded, enabled: !isSaving)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildLuxuryField(controller: idExpiryCtrl, label: "تاريخ انتهاء الوثيقة (YYYY-MM-DD)", icon: Icons.event_busy_rounded, enabled: !isSaving),
                          const SizedBox(height: 20),
                          
                          if (type == 'driver') ...[
                            _buildLuxuryField(controller: carInfoCtrl, label: "بيانات المركبة (النوع واللوحة)", icon: Icons.minor_crash_rounded, enabled: !isSaving),
                            const SizedBox(height: 20),
                            _buildLuxuryField(controller: licenseCtrl, label: "رقم رخصة القيادة", icon: Icons.checklist_rtl_rounded, enabled: !isSaving),
                          ],
                          
                          const SizedBox(height: 40),
                          
                          // Save Button
                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: isSaving 
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)))
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  elevation: 5,
                                  shadowColor: const Color(0xFF1E293B).withValues(alpha: 0.4),
                                ),
                                onPressed: () async {
                                  final email = emailCtrl.text.trim().toLowerCase();
                                  final name = nameCtrl.text.trim();
                                  
                                  if (name.isEmpty || email.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم والبريد الإلكتروني متطلبات أساسية')));
                                    return;
                                  }

                                  setDialogState(() => isSaving = true);

                                  try {
                                    if (selectedImageBytes != null) {
                                      final String fileName = "profile_${DateTime.now().millisecondsSinceEpoch}.jpg";
                                      photoUrl = await _firebaseService.uploadWorkerPhoto(selectedImageBytes!, fileName);
                                    }

                                    if (docId != null) {
                                      final data = {
                                        'name': name,
                                        'phone': phoneCtrl.text.trim(),
                                        'car_info': carInfoCtrl.text.trim(),
                                        'license_info': licenseCtrl.text.trim(),
                                        'type': type,
                                        'nationality': nationalityCtrl.text.trim(),
                                        'id_number': idNumberCtrl.text.trim(),
                                        'id_expiry': idExpiryCtrl.text.trim(),
                                        'photo_url': photoUrl,
                                        'updated_at': FieldValue.serverTimestamp(),
                                      };
                                      await FirebaseFirestore.instance.collection('drivers').doc(docId).update(data);
                                      await FirebaseFirestore.instance.collection('users').doc(docId).update({
                                        'name': name,
                                        'photo_url': photoUrl,
                                      });

                                      await _audit.logAction(
                                        action: ZyiarahAuditService.actionUpdateDriver,
                                        details: {'name': name, 'type': type},
                                        targetId: docId,
                                      );
                                    } else {
                                      final String newId = await _firebaseService.createDriverAccountViaAdmin(
                                        name: name,
                                        phone: phoneCtrl.text.trim(),
                                        email: email,
                                        carInfo: carInfoCtrl.text.trim(),
                                        licenseInfo: licenseCtrl.text.trim(),
                                        role: type,
                                        isActive: true,
                                        nationality: nationalityCtrl.text.trim(),
                                        idNumber: idNumberCtrl.text.trim(),
                                        idExpiry: idExpiryCtrl.text.trim(),
                                        photoUrl: photoUrl,
                                      );

                                      await _audit.logAction(
                                        action: ZyiarahAuditService.actionRegisterDriver,
                                        details: {'name': name, 'email': email, 'type': type},
                                        targetId: newId,
                                      );
                                    }
                                    if (context.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ أثناء الحفظ الجذري: $e")));
                                  }
                                },
                                child: Text(docId == null ? "تأكيد التسجيل النهائي" : "تحديث البيانات الرسمية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
          title: Text("إدارة الكوادر والتوصيل", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showDriverDialog(),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_task_rounded),
          label: Text("تسجيل كادر جديد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return _buildShimmerLoading();
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد سجلات"));

            final docs = snapshot.data!.docs;
            final stats = _calculateQuickStats(docs);

            return Column(
              children: [
                _buildStatsHeader(stats),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final driver = doc.data() as Map<String, dynamic>;
                      return _buildPremiumDriverCard(doc.id, driver);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Map<String, int> _calculateQuickStats(List<DocumentSnapshot> docs) {
    int total = docs.length;
    int drivers = docs.where((d) => (d.data() as Map)['type'] == 'driver').length;
    int workers = docs.where((d) => (d.data() as Map)['type'] == 'worker').length;
    int active = docs.where((d) => (d.data() as Map)['is_active'] ?? true).length;
    
    return {'total': total, 'drivers': drivers, 'workers': workers, 'active': active};
  }

  Widget _buildStatsHeader(Map<String, int> stats) {
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildMinimalStatCard("الإجمالي", stats['total'].toString(), Colors.blueAccent),
          _buildMinimalStatCard("سائقين", stats['drivers'].toString(), Colors.orangeAccent),
          _buildMinimalStatCard("كوادر تنظيف", stats['workers'].toString(), Colors.pinkAccent),
          _buildMinimalStatCard("نشط حالياً", stats['active'].toString(), Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildMinimalStatCard(String label, String value, Color color) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.tajawal(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildPremiumDriverCard(String docId, Map<String, dynamic> driver) {
    final bool isWorker = (driver['type'] ?? 'driver') == 'worker';
    final bool isActive = driver['is_active'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () => _showDriverDialog(docId: docId, currentData: driver),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: (isWorker ? Colors.pinkAccent : Colors.orangeAccent).withValues(alpha: 0.2), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey[50],
                        backgroundImage: driver['photo_url'] != null ? NetworkImage(driver['photo_url']) : null,
                        child: driver['photo_url'] == null 
                          ? Icon(isWorker ? Icons.cleaning_services_rounded : Icons.local_shipping_rounded, color: Colors.grey[400])
                          : null,
                      ),
                    ),
                    Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver['name'] ?? 'بدون اسم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone_android, size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(driver['phone'] ?? 'لا يوجد بريد', style: GoogleFonts.tajawal(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isWorker ? Colors.pinkAccent : Colors.orangeAccent).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isWorker ? "كادر تنظيف" : "سائق توصيل",
                          style: GoogleFonts.tajawal(color: isWorker ? Colors.pink : Colors.orange[800], fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Performance Badge
                      if ((driver['rating_avg'] ?? 5.0) >= 4.7 && (driver['rating_count'] ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                              const SizedBox(width: 4),
                              Text("نخبة المتميزين", style: GoogleFonts.tajawal(color: Colors.amber[900], fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          (driver['rating_avg'] ?? 5.0).toStringAsFixed(1),
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B)),
                        ),
                      ],
                    ),
                    Text("(${driver['rating_count'] ?? 0} تقييم)", style: TextStyle(fontSize: 8, color: Colors.grey[400])),
                    const SizedBox(height: 10),
                    Switch(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: isActive, 
                      activeThumbColor: const Color(0xFF1E293B),
                      onChanged: (val) async {
                        try {
                          await FirebaseFirestore.instance.collection('drivers').doc(docId).update({'is_active': val});
                          await _audit.logAction(
                            action: ZyiarahAuditService.actionToggleDriver,
                            details: {'name': driver['name'], 'status': val ? 'نشط' : 'معطل'},
                            targetId: docId,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(val ? "تم تفعيل الحساب بنجاح ✅" : "تم تعطيل الحساب"),
                              backgroundColor: val ? Colors.green : Colors.orange,
                              duration: const Duration(seconds: 1),
                            ));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل التحديث: $e")));
                        }
                      }
                    ),
                    Text(isActive ? "متصل" : "معطل", style: GoogleFonts.tajawal(fontSize: 9, color: isActive ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            height: 70,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          );
        },
      ),
    );
  }

  Widget _buildLuxuryField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: GoogleFonts.tajawal(fontSize: 14, color: const Color(0xFF1E293B)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF1E293B).withValues(alpha: 0.7), size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade100)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade100)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF1E293B), width: 1.5)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }
}
