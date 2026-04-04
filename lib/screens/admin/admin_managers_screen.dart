import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminManagersScreen extends StatefulWidget {
  const AdminManagersScreen({super.key});

  @override
  State<AdminManagersScreen> createState() => _AdminManagersScreenState();
}

class _AdminManagersScreenState extends State<AdminManagersScreen> {
  final _db = FirebaseFirestore.instance;

  void _showManagerDialog({String? docId, Map<String, dynamic>? currentData}) {
    final TextEditingController nameCtrl = TextEditingController(text: currentData?['name'] ?? '');
    final TextEditingController emailCtrl = TextEditingController(text: currentData?['email'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();
    String role = currentData?['role'] ?? 'orders_manager';

    final List<Map<String, String>> roles = [
      {'value': 'super_admin', 'label': 'مدير كامل الصلاحيات'},
      {'value': 'orders_manager', 'label': 'مدير طلبات وكوادر'},
      {'value': 'accountant_admin', 'label': 'مدير مالي ومحاسبة'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(docId == null ? "مدير جديد" : "تعديل بيانات المدير", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: "البريد الإلكتروني", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "كلمة المرور", 
                        border: OutlineInputBorder(),
                        helperText: "اتركها فارغة لعدم التغيير",
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: roles.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => role = val);
                      },
                      decoration: const InputDecoration(labelText: "مستوى الصلاحيات", border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                if (docId != null) 
                  TextButton(
                    onPressed: () async {
                      await _db.collection('admins').doc(docId).delete();
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("حذف", style: TextStyle(color: Colors.red)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                  onPressed: () async {
                    if (emailCtrl.text.isEmpty || (docId == null && passwordCtrl.text.isEmpty)) return;
                    
                    final data = {
                      'name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'role': role,
                      'is_active': currentData?['is_active'] ?? true,
                    };
                    if (passwordCtrl.text.isNotEmpty) {
                      data['password'] = passwordCtrl.text.trim();
                    }
                    
                    if (docId == null) {
                      await _db.collection('admins').add(data);
                    } else {
                      await _db.collection('admins').doc(docId).update(data);
                    }
                    if (context.mounted) Navigator.pop(ctx);
                  },
                  child: const Text("حفظ", style: TextStyle(color: Colors.white)),
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
        appBar: AppBar(
          title: Text("إدارة المدراء", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showManagerDialog(),
          icon: const Icon(Icons.add),
          label: Text("إضافة مدير", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('admins').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("أنت المدير الوحيد هنا"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final admin = doc.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _showManagerDialog(docId: doc.id, currentData: admin),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFF1E293B), child: Icon(Icons.admin_panel_settings, color: Colors.white)),
                      title: Text(admin['name'] ?? 'مدير', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${admin['email'] ?? ''}\nالصلاحيات: ${_getRoleLabel(admin['role'])}"),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: admin['is_active'] ?? true, 
                            activeThumbColor: const Color(0xFF1E293B),
                            onChanged: (val) {
                              _db.collection('admins').doc(doc.id).update({'is_active': val});
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

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'super_admin': return 'مدير كامل الصلاحيات';
      case 'orders_manager': return 'مدير طلبات وكوادر';
      case 'accountant_admin': return 'مدير مالي ومحاسبة';
      default: return 'مدير عام';
    }
  }
}
