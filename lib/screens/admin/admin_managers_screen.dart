import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/utils/strings.dart';

class AdminManagersScreen extends StatefulWidget {
  const AdminManagersScreen({super.key});

  @override
  State<AdminManagersScreen> createState() => _AdminManagersScreenState();
}

class _AdminManagersScreenState extends State<AdminManagersScreen> {
  final _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();

  void _showManagerDialog({String? docId, Map<String, dynamic>? currentData}) {
    final TextEditingController nameCtrl = TextEditingController(text: currentData?['name'] ?? '');
    final TextEditingController emailCtrl = TextEditingController(text: currentData?['email'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();
    String role = currentData?['role'] ?? 'orders_manager';
    bool isSaving = false;

    final List<Map<String, String>> roles = [
      {'value': 'super_admin', 'label': 'مدير كامل الصلاحيات - Super Admin'},
      {'value': 'orders_manager', 'label': 'مدير عمليات وكوادر - Operations'},
      {'value': 'accountant_admin', 'label': 'مدير مالي ومحاسبة - Financial'},
      {'value': 'marketing_admin', 'label': 'مدير تسويق وعروض - Marketing'},
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                   Icon(docId == null ? Icons.person_add_rounded : Icons.edit_note_rounded, color: const Color(0xFF1E293B)),
                   const SizedBox(width: 10),
                   Text(
                     docId == null ? "إضافة كادر جديد" : "تعديل بيانات المنسوب", 
                     style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)
                   ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaving)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(color: Color(0xFF1E293B), backgroundColor: Color(0xFFF1F5F9)),
                      ),
                    TextField(
                      controller: nameCtrl,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: "الاسم الكامل", 
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: "البريد الإلكتروني للعمل", 
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        helperText: "سيتم استخدامه كاسم مستخدم لتسجيل الدخول",
                        helperStyle: const TextStyle(fontSize: 10)
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: "كلمة المرور", 
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        helperText: docId != null ? "اتركها فارغة لعدم التغيير" : "كلمة المرور المطلوبة للدخول",
                        helperStyle: const TextStyle(fontSize: 10)
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: roles.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: isSaving ? null : (val) {
                        if (val != null) setDialogState(() => role = val);
                      },
                      decoration: InputDecoration(
                        labelText: "مستوى الصلاحيات", 
                        prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                const Spacer(),
                if (docId != null) 
                  IconButton(
                    onPressed: isSaving ? null : () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("تأكيد الحذف"),
                          content: const Text("هل أنت متأكد من سحب كافة صلاحيات هذا المنسوب وحذف حسابه؟"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("حذف نهائياً", style: TextStyle(color: Colors.red))),
                          ],
                        )
                      );
                      if (confirm != true) return;

                      setDialogState(() => isSaving = true);
                      try {
                        await _db.collection('admins').doc(docId).delete();
                        await _audit.logAction(
                          action: ZyiarahAuditService.actionDeleteStaff,
                          details: {'email': docId},
                          targetId: docId,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                         setDialogState(() => isSaving = false);
                         if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحذف الجذري: $e")));
                      }
                    },
                    icon: Icon(Icons.delete_forever_rounded, color: isSaving ? Colors.grey : Colors.red),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: isSaving ? null : () async {
                    if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || (docId == null && passwordCtrl.text.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات الأساسية")));
                      return;
                    }
                    
                    setDialogState(() => isSaving = true);
                    
                    try {
                      final email = emailCtrl.text.trim().toLowerCase();
                      final data = {
                        'name': nameCtrl.text.trim(),
                        'email': email,
                        'role': role,
                        'is_active': currentData?['is_active'] ?? true,
                        'updated_at': FieldValue.serverTimestamp(),
                      };
                      if (passwordCtrl.text.isNotEmpty) {
                        data['password'] = passwordCtrl.text.trim();
                      }
                      
                      // Using Email as ID ensuring compatibility with Dashboard checks
                      await _db.collection('admins').doc(email).set(data, SetOptions(merge: true));
                      
                      await _audit.logAction(
                        action: docId == null ? ZyiarahAuditService.actionCreateStaff : ZyiarahAuditService.actionUpdateStaff,
                        details: {'name': nameCtrl.text, 'email': email, 'role': role},
                        targetId: email,
                      );
                      
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث بيانات المنسوب بنجاح ✅")));
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ جذري: $e")));
                      }
                    }
                  },
                  child: Text(isSaving ? "جاري الحفظ..." : "حفظ البيانات", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text(ZyiarahStrings.unifiedStaffManagement, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showManagerDialog(),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text("إضافة منسوب", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('admins').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)));
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text("لا يوجد منسوبين مسجلين حالياً", style: GoogleFonts.tajawal(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final admin = doc.data() as Map<String, dynamic>;
                final bool isActive = admin['is_active'] ?? true;

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                  child: InkWell(
                    onTap: () => _showManagerDialog(docId: doc.id, currentData: admin),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: _getRoleColor(admin['role']).withValues(alpha: 0.1),
                          child: Icon(_getRoleIcon(admin['role']), color: _getRoleColor(admin['role'])),
                        ),
                        title: Text(admin['name'] ?? 'منسوب جديد', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(admin['email'] ?? '', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: _getRoleColor(admin['role']).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                              child: Text(_getRoleLabel(admin['role']), style: TextStyle(fontSize: 10, color: _getRoleColor(admin['role']), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isActive, 
                                activeColor: const Color(0xFF1E293B),
                                onChanged: (val) {
                                  _db.collection('admins').doc(doc.id).update({'is_active': val});
                                }
                              ),
                            ),
                            Text(isActive ? "نشط" : "معطل", style: TextStyle(fontSize: 9, color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
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

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'super_admin': return Icons.verified_user_rounded;
      case 'orders_manager': return Icons.engineering_rounded;
      case 'accountant_admin': return Icons.account_balance_rounded;
      case 'marketing_admin': return Icons.campaign_rounded;
      default: return Icons.person_rounded;
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'super_admin': return const Color(0xFF1E293B);
      case 'orders_manager': return const Color(0xFF2563EB);
      case 'accountant_admin': return const Color(0xFF059669);
      case 'marketing_admin': return const Color(0xFFD97706);
      default: return Colors.blueGrey;
    }
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'super_admin': return 'إدارة عليا';
      case 'orders_manager': return 'إدارة عمليات وكوادر';
      case 'accountant_admin': return 'إدارة مالية';
      case 'marketing_admin': return 'إدارة تسويق';
      default: return 'منسوب عام';
    }
  }
}
