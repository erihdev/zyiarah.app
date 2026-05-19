import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
    final bool isNew = docId == null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isSaving = false;

          Future<void> onSave() async {
            final name = nameCtrl.text.trim();
            final email = emailCtrl.text.trim();
            final password = passwordCtrl.text.trim();

            if (name.isEmpty || (isNew && (email.isEmpty || password.isEmpty))) return;

            setDialogState(() => isSaving = true);
            // Capture messenger before any async gap to avoid BuildContext issues.
            final messenger = ScaffoldMessenger.of(context);

            try {
              if (isNew) {
                // Create Firebase Auth user via a temporary secondary app so
                // the current admin session is NOT displaced.
                FirebaseApp? tempApp;
                try {
                  tempApp = await Firebase.initializeApp(
                    name: 'accountant_tmp_${DateTime.now().millisecondsSinceEpoch}',
                    options: Firebase.app().options,
                  );
                  final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
                  final cred = await tempAuth.createUserWithEmailAndPassword(
                    email: email,
                    password: password,
                  );
                  final uid = cred.user!.uid;
                  await _db.collection('accountants').doc(uid).set({
                    'name': name,
                    'email': email,
                    'role': 'accountant',
                    'is_active': true,
                    'created_at': FieldValue.serverTimestamp(),
                  });
                } finally {
                  await tempApp?.delete();
                }
              } else {
                await _db.collection('accountants').doc(docId).update({
                  'name': name,
                  'is_active': currentData?['is_active'] ?? true,
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } on FirebaseAuthException catch (e) {
              if (ctx.mounted) setDialogState(() => isSaving = false);
              String msg = 'خطأ في إنشاء الحساب';
              if (e.code == 'email-already-in-use') msg = 'هذا البريد مسجّل مسبقاً';
              if (e.code == 'weak-password') msg = 'كلمة المرور ضعيفة — 6 أحرف على الأقل';
              if (e.code == 'invalid-email') msg = 'تنسيق البريد الإلكتروني غير صحيح';
              messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
            } catch (e) {
              if (ctx.mounted) setDialogState(() => isSaving = false);
              messenger.showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
            }
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                isNew ? "محاسب جديد" : "تعديل بيانات المحاسب",
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
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
                      enabled: isNew,
                      decoration: InputDecoration(
                        labelText: "البريد الإلكتروني",
                        border: const OutlineInputBorder(),
                        helperText: isNew ? null : "لا يمكن تغيير البريد بعد الإنشاء",
                      ),
                    ),
                    if (isNew) ...[
                      const SizedBox(height: 15),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "كلمة المرور",
                          border: OutlineInputBorder(),
                          helperText: "6 أحرف على الأقل",
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                if (!isNew)
                  TextButton(
                    onPressed: isSaving ? null : () async {
                      await _db.collection('accountants').doc(docId).delete();
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("حذف", style: TextStyle(color: Colors.red)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                  onPressed: isSaving ? null : onSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text("حفظ", style: TextStyle(color: Colors.white)),
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
