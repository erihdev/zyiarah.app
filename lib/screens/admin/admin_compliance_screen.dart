import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminComplianceScreen extends StatefulWidget {
  const AdminComplianceScreen({super.key});

  @override
  State<AdminComplianceScreen> createState() => _AdminComplianceScreenState();
}

class _AdminComplianceScreenState extends State<AdminComplianceScreen> {
  String _filter = 'all'; // all, expired, expiring_soon

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("مركز فحص الامتثال", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: "إرسال تنبيه جماعي للمخالفين",
              icon: const Icon(Icons.mark_email_unread_rounded),
              onPressed: () => _notifyAllExpiring(context),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFilterTabs(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final filteredDocs = _applyFilter(allDocs);

                  if (filteredDocs.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) => _buildComplianceCard(filteredDocs[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildTab("الكل", 'all'),
            _buildTab("منتهية 🔴", 'expired'),
            _buildTab("تنتهي قريباً 🟡", 'expiring_soon'),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, String value) {
    final bool isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        margin: const EdgeInsets.only(left: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: GoogleFonts.tajawal(color: isSelected ? const Color(0xFF1E293B) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  List<DocumentSnapshot> _applyFilter(List<DocumentSnapshot> docs) {
    final now = DateTime.now();
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final expiryStr = data['id_expiry']?.toString() ?? '';
      try {
        final expiryDate = DateTime.parse(expiryStr);
        final diff = expiryDate.difference(now).inDays;

        if (_filter == 'expired') return diff < 0;
        if (_filter == 'expiring_soon') return diff >= 0 && diff < 30;
        return diff < 30; // 'all' showing anything of concern
      } catch (e) {
        return false;
      }
    }).toList();
  }

  Widget _buildComplianceCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final expiryStr = data['id_expiry']?.toString() ?? '';
    final name = data['name'] ?? 'بدون اسم';
    final phone = data['phone'] ?? '';
    final idNumber = data['id_number'] ?? 'غير مسجل';
    
    DateTime? expiryDate;
    int diff = 0;
    try {
      expiryDate = DateTime.parse(expiryStr);
      diff = expiryDate.difference(DateTime.now()).inDays;
    } catch (_) {}

    final bool isExpired = diff < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isExpired ? Colors.red.shade100 : Colors.orange.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isExpired ? Colors.red[50] : Colors.orange[50],
                  child: Icon(isExpired ? Icons.warning_rounded : Icons.timer_rounded, color: isExpired ? Colors.red : Colors.orange),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text("رقم الهوية: $idNumber", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: (isExpired ? Colors.red : Colors.orange).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(isExpired ? "منتهية" : "تنتهي خلال $diff يوم", style: TextStyle(color: isExpired ? Colors.red : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionBtn(Icons.phone, "اتصال", Colors.blue, () => _launchURL("tel:$phone")),
                _buildActionBtn(Icons.block_flipped, isExpired ? "تعطيل الحساب" : "حظر مؤقت", Colors.red, () async {
                   final confirm = await _showConfirm("تأكيد الإجراء", "هل تريد تغيير حالة هذا الكادر؟");
                   if (confirm) {
                     await FirebaseFirestore.instance.collection('drivers').doc(doc.id).update({'is_active': false});
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تعطيل الحساب بنجاح")));
                   }
                }),
                _buildActionBtn(Icons.edit_note_rounded, "تحديث البيانات", Colors.grey[700]!, () {
                  // This is a placeholder as the dialog is in AdminDriversScreen
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى التوجه إلى شاشة الكوادر لتحديث البيانات")));
                }),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded, size: 80, color: Colors.green[100]),
          const SizedBox(height: 20),
          Text("نظامك سليم تماماً!", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green[700])),
          Text("لا توجد مخالفات امتثال حالياً", style: GoogleFonts.tajawal(color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _notifyAllExpiring(BuildContext context) async {
    final docs = await FirebaseFirestore.instance.collection('drivers').get();
    final now = DateTime.now();
    int count = 0;

    for (var doc in docs.docs) {
      final data = doc.data();
      final expiryStr = data['id_expiry']?.toString() ?? '';
      try {
        final expiryDate = DateTime.parse(expiryStr);
        if (expiryDate.difference(now).inDays < 30) {
          // In a real app, this would trigger an FCM push.
          // For now, we log the "Notification Request" in broadcasts for specific target.
          await FirebaseFirestore.instance.collection('broadcasts').add({
            'title': 'تنبيه انتهاء وثائق رسمية',
            'body': 'عزيزي ${data['name']}، نرجو تحديث بيانات هويتك في أقرب وقت لتجنب إيقاف الحساب.',
            'target': 'drivers',
            'target_uid': doc.id,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'compliance_alert',
          });
          count++;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("تم إرسال $count تنبيه استباقي آلي بنجاح 🤖✅"),
      backgroundColor: Colors.blueAccent,
    ));
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<bool> _showConfirm(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("تأكيد")),
          ],
        ),
      ),
    ) ?? false;
  }
}
