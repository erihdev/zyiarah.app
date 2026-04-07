import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:zyiarah/services/firebase_service.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  final _db = FirebaseFirestore.instance;
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();

  void _showDriverDialog({String? docId, Map<String, dynamic>? currentData}) {
    final TextEditingController nameCtrl = TextEditingController(text: currentData?['name'] ?? '');
    final TextEditingController phoneCtrl = TextEditingController(text: currentData?['phone'] ?? '');
    final TextEditingController emailCtrl = TextEditingController(text: currentData?['email'] ?? '');
    final TextEditingController carInfoCtrl = TextEditingController(text: currentData?['car_info'] ?? '');
    final TextEditingController licenseCtrl = TextEditingController(text: currentData?['license_info'] ?? '');
    String type = currentData?['type'] ?? 'driver'; 
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(docId == null ? "موظف جديد" : "تعديل الموظف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: "الاسم", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: "رقم الجوال", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: docId == null, // لا يمكن تعديل الايميل بعد الانشاء لتجنب مشاكل Auth
                      decoration: const InputDecoration(labelText: "البريد الإلكتروني", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: carInfoCtrl,
                      decoration: const InputDecoration(labelText: "بيانات السيارة (اختياري)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: licenseCtrl,
                      decoration: const InputDecoration(labelText: "رقم رخصة القيادة (اختياري)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const [
                        DropdownMenuItem(value: 'driver', child: Text("سائق")),
                        DropdownMenuItem(value: 'worker', child: Text("عامل / عاملة")),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => type = val);
                      },
                      decoration: const InputDecoration(labelText: "الوظيفة / الدور", border: OutlineInputBorder()),
                    )
                  ],
                ),
              ),
              actions: [
                if (!isSaving)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                  ),
                if (docId != null && !isSaving) 
                  TextButton(
                    onPressed: () async {
                      await _db.collection('drivers').doc(docId).delete();
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("حذف", style: TextStyle(color: Colors.red)),
                  ),
                isSaving 
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                      onPressed: () async {
                        final email = emailCtrl.text.trim();
                        final name = nameCtrl.text.trim();
                        
                        if (name.isEmpty || email.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم والبريد الإلكتروني إجبارية')));
                          return;
                        }

                        setState(() => isSaving = true);

                        try {
                          if (docId == null) {
                            // إنشاء موظف جديد وحسابه
                            await _firebaseService.createDriverAccountViaAdmin(
                              name: name,
                              phone: phoneCtrl.text.trim(),
                              email: email,
                              carInfo: carInfoCtrl.text.trim(),
                              licenseInfo: licenseCtrl.text.trim(),
                              role: type,
                              isActive: currentData?['is_active'] ?? true,
                            );
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('تم إنشاء الحساب وإرسال رابط التفعيل للسائق بنجاح'),
                                backgroundColor: Colors.green,
                              ));
                              Navigator.pop(ctx);
                            }
                          } else {
                            // تعديل بيانات الموظف
                            final data = {
                              'name': name,
                              'phone': phoneCtrl.text.trim(),
                              'car_info': carInfoCtrl.text.trim(),
                              'license_info': licenseCtrl.text.trim(),
                              'type': type,
                              'is_active': currentData?['is_active'] ?? true,
                            };
                            await _db.collection('drivers').doc(docId).update(data);
                            if (context.mounted) Navigator.pop(ctx);
                          }
                        } catch (e) {
                          setState(() => isSaving = false);
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctxErr) => AlertDialog(
                                title: const Text("رسالة خطأ (يرجى تصويرها)"),
                                content: Text(e.toString(), style: const TextStyle(color: Colors.red, fontSize: 13)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctxErr),
                                    child: const Text("حسناً"),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      },
                      child: const Text("حفظ", style: TextStyle(color: Colors.white)),
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
        appBar: AppBar(
          title: Text("إدارة الكوادر والتوصيل", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showDriverDialog(),
          icon: const Icon(Icons.add),
          label: Text("تسجيل كادر جديد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return _buildShimmerLoading();
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد سجلات"));


            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final driver = doc.data() as Map<String, dynamic>;
                final bool isWorker = (driver['type'] ?? 'driver') == 'worker';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _showDriverDialog(docId: doc.id, currentData: driver),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isWorker ? Colors.pinkAccent : Colors.orange, 
                        child: Icon(isWorker ? Icons.cleaning_services : Icons.local_shipping, color: Colors.white)
                      ),
                      title: Text(driver['name'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${isWorker ? 'عامل' : 'سائق'} | ${driver['phone'] ?? 'بدون رقم'}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: driver['is_active'] ?? true, 
                            activeThumbColor: const Color(0xFF1E293B),
                            onChanged: (val) async {
                              await _db.collection('drivers').doc(doc.id).update({'is_active': val});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(val ? "تم تفعيل الحساب بنجاح" : "تم تعطيل الحساب"),
                                  backgroundColor: val ? Colors.green : Colors.orange,
                                  duration: const Duration(seconds: 1),
                                ));
                              }
                            }
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
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
}
