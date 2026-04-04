import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminAccountantsScreen extends StatefulWidget {
  const AdminAccountantsScreen({super.key});

  @override
  State<AdminAccountantsScreen> createState() => _AdminAccountantsScreenState();
}

class _AdminAccountantsScreenState extends State<AdminAccountantsScreen> {
  final _db = FirebaseFirestore.instance;

  void _showAccountantDialog({String? docId, Map<String, dynamic>? currentData}) {
    final TextEditingController nameCtrl = TextEditingController(text: currentData?['name'] ?? '');
    final TextEditingController emailCtrl = TextEditingController(text: currentData?['email'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(docId == null ? "محاسب جديد" : "تعديل بيانات المحاسب", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                    helperText: "اتركها فارغة لعدم التغيير (للمحاسبين الحاليين)",
                  ),
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
                  await _db.collection('accountants').doc(docId).delete();
                  if (context.mounted) Navigator.pop(ctx);
                },
                child: const Text("حذف", style: TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
              onPressed: () async {
                if (nameCtrl.text.isEmpty || (docId == null && passwordCtrl.text.isEmpty)) return;
                
                final data = {
                  'name': nameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'role': 'accountant',
                  'is_active': currentData?['is_active'] ?? true,
                };
                if (passwordCtrl.text.isNotEmpty) {
                  data['password'] = passwordCtrl.text.trim(); // Storing password loosely in firestore strictly for simple auth role login. In prod Firebase Auth is better for multiple admins
                }

                if (docId == null) {
                  await _db.collection('accountants').add(data);
                } else {
                  await _db.collection('accountants').doc(docId).update(data);
                }
                if (context.mounted) Navigator.pop(ctx);
              },
              child: const Text("حفظ", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("المحاسبون والمالية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAccountantDialog(),
          icon: const Icon(Icons.add),
          label: Text("إضافة محاسب", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('accountants').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا يوجد محاسبين مسجلين"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final acc = doc.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _showAccountantDialog(docId: doc.id, currentData: acc),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.account_balance_wallet, color: Colors.white)),
                      title: Text(acc['name'] ?? 'محاسب', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${acc['email'] ?? ''}\nالصلاحيات: كشف الحسابات فقط"),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: acc['is_active'] ?? true, 
                            activeThumbColor: const Color(0xFF1E293B),
                            onChanged: (val) {
                              _db.collection('accountants').doc(doc.id).update({'is_active': val});
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
}
