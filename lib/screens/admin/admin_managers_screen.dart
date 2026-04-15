import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';
import 'package:zyiarah/services/firebase_service.dart';

class AdminManagersScreen extends StatefulWidget {
  const AdminManagersScreen({super.key});

  @override
  State<AdminManagersScreen> createState() => _AdminManagersScreenState();
}

class _AdminManagersScreenState extends State<AdminManagersScreen> {
  final _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();

  void _showManagerDialog({String? docId, Map<String, dynamic>? currentData}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ManagerFormSheet(
        docId: docId,
        currentData: currentData,
        onSuccess: () {
          if (mounted) Navigator.pop(ctx);
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
          title: Text(ZyiarahStrings.unifiedStaffManagement, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
             IconButton(
               icon: const Icon(Icons.search_rounded),
               onPressed: () {
                 showSearch(
                   context: context,
                   delegate: StaffSearchDelegate(onSelect: (doc) => _showManagerDialog(docId: doc.id, currentData: doc.data() as Map<String, dynamic>)),
                 );
               },
             ),
             const SizedBox(width: 10),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showManagerDialog(),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text("إضافة منسوب", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13)),
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
                    Icon(Icons.people_outline_rounded, size: 80, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("لا يوجد منسوبين مسجلين", style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 16)),
                  ],
                ),
              );
            }

            return ListWheelScrollView.useDelegate(
              itemExtent: 110,
              physics: const FixedExtentScrollPhysics(),
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: snapshot.data!.docs.length,
                builder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final admin = doc.data() as Map<String, dynamic>;
                  final bool isActive = admin['is_active'] ?? true;
                  final String role = admin['staff_role'] ?? admin['role'] ?? 'staff';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: InkWell(
                        onTap: () => _showManagerDialog(docId: doc.id, currentData: admin),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: _getRoleColor(role).withValues(alpha: 0.1),
                                child: Icon(_getRoleIcon(role), color: _getRoleColor(role), size: 28),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(admin['name'] ?? 'بدون اسم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(admin['email'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(color: _getRoleColor(role).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                      child: Text(_getRoleLabel(role), style: TextStyle(fontSize: 9, color: _getRoleColor(role), fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Switch.adaptive(
                                    value: isActive, 
                                    activeThumbColor: Colors.green,
                                    onChanged: (val) {
                                      _db.collection('admins').doc(doc.id).update({'is_active': val});
                                      _audit.logAction(action: 'TOGGLE_ADMIN_STATUS', details: {'email': admin['email'], 'new_status': val});
                                    }
                                  ),
                                  Text(isActive ? "نشط" : "معطل", style: TextStyle(fontSize: 9, color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
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
      case 'super_admin': return 'الإدارة العليا';
      case 'orders_manager': return 'إدارة العمليات';
      case 'accountant_admin': return 'الإدارة المالية';
      case 'marketing_admin': return 'إدارة التسويق';
      default: return 'منسوب منصة';
    }
  }
}

class _ManagerFormSheet extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? currentData;
  final VoidCallback onSuccess;

  const _ManagerFormSheet({this.docId, this.currentData, required this.onSuccess});

  @override
  State<_ManagerFormSheet> createState() => _ManagerFormSheetState();
}

class _ManagerFormSheetState extends State<_ManagerFormSheet> {
  late TextEditingController nameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController passwordCtrl;
  late String role;
  bool isSaving = false;

  final List<Map<String, String>> roles = [
    {'value': 'super_admin', 'label': 'مدير كامل الصلاحيات'},
    {'value': 'orders_manager', 'label': 'مدير عمليات وكوادر'},
    {'value': 'accountant_admin', 'label': 'مدير مالي ومحاسبة'},
    {'value': 'marketing_admin', 'label': 'مدير تسويق وعروض'},
  ];

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.currentData?['name'] ?? '');
    emailCtrl = TextEditingController(text: widget.currentData?['email'] ?? '');
    passwordCtrl = TextEditingController();
    role = widget.currentData?['staff_role'] ?? widget.currentData?['role'] ?? 'orders_manager';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(color: const Color(0xFF1E293B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                     child: Icon(widget.docId == null ? Icons.person_add_rounded : Icons.edit_note_rounded, color: const Color(0xFF1E293B), size: 28),
                   ),
                   const SizedBox(width: 15),
                   Text(
                     widget.docId == null ? "إضافة كادر جديد" : "تعديل بيانات مصلحي", 
                     style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 20, color: const Color(0xFF1E293B))
                   ),
                ],
              ),
              const SizedBox(height: 30),
              if (isSaving) const LinearProgressIndicator(color: Color(0xFF1E293B), backgroundColor: Color(0xFFF1F5F9)),
              const SizedBox(height: 15),
              
              _fieldLabel("الاسم الكامل"),
              TextField(
                controller: nameCtrl,
                enabled: !isSaving,
                decoration: _inputDecoration("أدخل الاسم الرباعي", Icons.person_outline),
              ),
              const SizedBox(height: 20),
              
              _fieldLabel("البريد الإلكتروني"),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                enabled: !isSaving,
                decoration: _inputDecoration("email@example.com", Icons.alternate_email_rounded),
              ),
              const SizedBox(height: 20),
              
              _fieldLabel("كلمة المرور"),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                enabled: !isSaving,
                decoration: _inputDecoration(widget.docId != null ? "اتركها فارغة لعدم التغيير" : "كلمة المرور الافتتاحية", Icons.lock_outline),
              ),
              const SizedBox(height: 20),
              
              _fieldLabel("مستوى الصلاحيات"),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: roles.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!, style: GoogleFonts.tajawal(fontSize: 14)))).toList(),
                onChanged: isSaving ? null : (val) => setState(() => role = val!),
                decoration: _inputDecoration("", Icons.admin_panel_settings_outlined),
              ),
              const SizedBox(height: 40),
              
              Row(
                children: [
                  if (widget.docId != null) 
                    IconButton(
                      onPressed: isSaving ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.pop(context),
                    child: Text("إلغاء", style: GoogleFonts.tajawal(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 15),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    onPressed: isSaving ? null : _saveStaff,
                    child: Text(isSaving ? "جاري الحفظ..." : "حفظ الموظف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(padding: const EdgeInsets.only(bottom: 8, right: 4), child: Text(label, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)));

  InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: const Color(0xFF1E293B)),
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  );

  Future<void> _confirmDelete() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("تأكيد الحذف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من سحب كافة صلاحيات هذا المنسوب وحذف حسابه نهائياً؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")),
            TextButton(
              onPressed: () => Navigator.pop(c, true), 
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("حذف نهائياً", style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
      )
    );
    if (confirm != true || !mounted) return;

    setState(() => isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('admins').doc(widget.docId).delete();
      await ZyiarahAuditService().logAction(
        action: ZyiarahAuditService.actionDeleteStaff,
        details: {'email': widget.docId},
        targetId: widget.docId,
      );
      widget.onSuccess();
    } catch (e) {
       setState(() => isSaving = false);
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحذف: $e")));
    }
  }

  Future<void> _saveStaff() async {
    if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات الأساسية")));
      return;
    }
    
    setState(() => isSaving = true);
    final email = emailCtrl.text.trim().toLowerCase();
    
    try {
      if (widget.docId == null) {
        await ZyiarahFirebaseService().createAccountViaAdmin(
          name: nameCtrl.text.trim(),
          phone: "000000000",
          email: email,
          role: 'admin',
          isActive: true,
          extraData: {'staff_role': role}
        );
      } else {
        final updates = {
          'name': nameCtrl.text.trim(),
          'role': 'admin',
          'staff_role': role,
          'updated_at': FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance.collection('users').doc(widget.docId).set(updates, SetOptions(merge: true));
        await FirebaseFirestore.instance.collection('admins').doc(widget.docId).set({...updates, 'email': email}, SetOptions(merge: true));
      }
      
      await ZyiarahAuditService().logAction(
        action: widget.docId == null ? ZyiarahAuditService.actionCreateStaff : ZyiarahAuditService.actionUpdateStaff,
        details: {'name': nameCtrl.text, 'email': email, 'role': role},
        targetId: email,
      );
      
      widget.onSuccess();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تنفيذ العملية بنجاح ✅")));
    } catch (e) {
      setState(() => isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ: $e")));
    }
  }
}

class StaffSearchDelegate extends SearchDelegate {
  final Function(DocumentSnapshot) onSelect;
  StaffSearchDelegate({required this.onSelect});

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = "")];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('admins').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final results = snapshot.data!.docs.where((doc) {
            final name = doc['name'].toString().toLowerCase();
            final email = doc['email'].toString().toLowerCase();
            return name.contains(query.toLowerCase()) || email.contains(query.toLowerCase());
          }).toList();

          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final doc = results[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(doc['name']),
                subtitle: Text(doc['email']),
                onTap: () {
                  onSelect(doc);
                  close(context, null);
                },
              );
            },
          );
        },
      ),
    );
  }
}
