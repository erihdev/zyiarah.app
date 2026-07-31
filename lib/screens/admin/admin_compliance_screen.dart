import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/screens/admin/admin_drivers_screen.dart';
import 'package:zyiarah/services/firebase_service.dart';

class AdminComplianceScreen extends StatefulWidget {
  const AdminComplianceScreen({super.key});

  @override
  State<AdminComplianceScreen> createState() => _AdminComplianceScreenState();
}

class _AdminComplianceScreenState extends State<AdminComplianceScreen> {
  String _filter = 'all'; // all, expired, expiring_soon

  // قواعد Firestore تحصر الكتابة على drivers بـ isOrdersManager، بينما تصل هذه
  // الشاشة كل الأدوار الفرعية (من بطاقة «التزام الكوادر» في Insights بلا بوّابة) —
  // نجلب الدور مرة واحدة (نفس نمط admin_dashboard_screen) لإخفاء زر الحظر عمّن
  // سيُرفض طلبه حتماً (accountant/marketing) بدل permission-denied صامت.
  String _role = 'none';

  bool get _canManageDrivers =>
      ['admin', 'super_admin', 'orders_manager'].contains(_role);

  @override
  void initState() {
    super.initState();
    _fetchAdminRole();
  }

  Future<void> _fetchAdminRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final role = await ZyiarahFirebaseService().getUserRole(user.uid);
      if (mounted) setState(() => _role = role ?? 'none');
    } catch (_) {
      // فشل جلب الدور = نُبقي 'none' فيبقى زر الحظر مخفياً (الخيار الآمن).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("مركز فحص الامتثال", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF660033),
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
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _getComplianceStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final filteredDocs = snapshot.data?.docs ?? [];

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

  // id_expiry مخزَّن كنص ISO 'YYYY-MM-DD' (لا Timestamp) — لذا يُقارَن نصّياً (ترتيب ISO
  // = ترتيب زمني). الاستعلام السابق كان بـ Timestamp فلا يطابق شيئاً أبداً (الشاشة فارغة
  // دائماً). حدّ أدنى '1900-01-01' لاستبعاد السجلات بلا تاريخ.
  static String _isoDate(DateTime x) =>
      '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  Stream<QuerySnapshot<Map<String, dynamic>>> _getComplianceStream() {
    final now = DateTime.now();
    final today = _isoDate(now);
    final soon = _isoDate(now.add(const Duration(days: 30)));
    const floor = '1900-01-01';

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('drivers');

    if (_filter == 'expired') {
      query = query
          .where('id_expiry', isGreaterThan: floor)
          .where('id_expiry', isLessThan: today);
    } else if (_filter == 'expiring_soon') {
      query = query
          .where('id_expiry', isGreaterThanOrEqualTo: today)
          .where('id_expiry', isLessThanOrEqualTo: soon);
    } else {
      query = query
          .where('id_expiry', isGreaterThan: floor)
          .where('id_expiry', isLessThanOrEqualTo: soon);
    }

    return query.snapshots();
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

  Widget _buildComplianceCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final expiryVal = data['id_expiry'];
    final name = data['name'] ?? 'بدون اسم';
    final phone = data['phone'] ?? '';
    final idNumber = data['id_number'] ?? 'غير مسجل';
    
    DateTime? expiryDate;
    if (expiryVal is Timestamp) {
      expiryDate = expiryVal.toDate();
    } else if (expiryVal is String) {
      expiryDate = DateTime.tryParse(expiryVal);
    }

    int diff = 0;
    if (expiryDate != null) {
      diff = expiryDate.difference(DateTime.now()).inDays;
    }

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
                _buildActionBtn(Icons.phone, "اتصال", Colors.blue,
                    // بلا رقم مسجّل لا نحاول 'tel:' فارغاً (كان no-op صامتاً).
                    phone.toString().trim().isEmpty
                        ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('لا يوجد رقم هاتف مسجّل لهذا الكادر'),
                            backgroundColor: Colors.red))
                        : () => _launchURL("tel:$phone")),
                // زر الحظر يظهر فقط لمن تسمح له القواعد بالكتابة على drivers
                // (isOrdersManager) — كان يظهر للمحاسب/التسويق ثم يفشل بصمت.
                if (_canManageDrivers)
                  _buildActionBtn(Icons.block_flipped, isExpired ? "تعطيل الحساب" : "حظر مؤقت", Colors.red, () async {
                     final confirm = await _showConfirm("تأكيد الإجراء", "هل تريد تغيير حالة هذا الكادر؟");
                     if (confirm) {
                       try {
                         // نضبط is_suspended/is_available أيضاً: لوحة الويب تبني شارة الحالة
                         // ومفتاح الإيقاف على is_suspended، فحظرٌ يكتب is_active فقط كان يُظهر
                         // السائق «نشطاً» في الويب رغم تعطيله هنا.
                         await FirebaseFirestore.instance.collection('drivers').doc(doc.id).update({
                           'is_active': false,
                           'is_suspended': true,
                           'is_available': false,
                         });
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تعطيل الحساب بنجاح")));
                       } catch (e) {
                         // كان الفشل (رفض قواعد/شبكة) استثناءً صامتاً — السائق يبقى نشطاً
                         // والأدمن يظن أن التعطيل تم. نُظهر الخطأ صراحةً.
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                             content: Text('فشل تعطيل الحساب: $e'),
                             backgroundColor: Colors.red,
                           ));
                         }
                       }
                     }
                  }),
                _buildActionBtn(Icons.edit_note_rounded, "تحديث البيانات", Colors.grey[700]!, () {
                  // حوار تحديث بيانات السائق موجود في شاشة الكوادر — ننقل الأدمن إليها
                  // فعلياً (كان الزر SnackBar إرشادياً فقط بلا أي فعل).
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDriversScreen()));
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
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final soon = _isoDate(now.add(const Duration(days: 30)));
    try {
      // نص ISO (لا Timestamp) — كان الاستعلام السابق لا يجد شيئاً فيُرسل 0 دائماً.
      final docs = await FirebaseFirestore.instance
          .collection('drivers')
          .where('id_expiry', isGreaterThan: '1900-01-01')
          .where('id_expiry', isLessThanOrEqualTo: soon)
          .get();
      int count = 0;
      for (var doc in docs.docs) {
        final data = doc.data();
        // notification_triggers هي القناة الحقيقية للدفع الموجَّه (processNotificationTriggers
        // يرسل FCM لرمز fcm_tokens/{toUid} ويكتب سجلّ notifications داخل التطبيق) —
        // الكتابة السابقة في 'broadcasts' كانت أثراً ميتاً: لا دالة سحابية تستمع إليها
        // (هي سجلّ تاريخ فقط في شاشة البث) فلم يكن يصل السائقين أي شيء.
        await FirebaseFirestore.instance.collection('notification_triggers').add({
          'toUid': doc.id,
          'title': 'تنبيه انتهاء وثائق رسمية',
          'body': 'عزيزي ${data['name']}، نرجو تحديث بيانات هويتك في أقرب وقت لتجنب إيقاف الحساب.',
          'type': 'compliance_alert',
          'data': {'driverId': doc.id},
          // حارس الخادم يرفض أي trigger موجَّه لغير مُنشئه ما لم يكن المُنشئ موظفاً —
          // نختم بهوية الأدمن الحالي ليُقبل.
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
        count++;
      }
      // سجلّ تاريخ واحد في broadcasts (نفس نمط شاشة البث: broadcasts للتأريخ فقط).
      if (count > 0) {
        await FirebaseFirestore.instance.collection('broadcasts').add({
          'title': 'تنبيه انتهاء وثائق رسمية',
          'body': 'إرسال $count تنبيه امتثال موجَّه للكوادر منتهية/قاربة الانتهاء.',
          'target': 'drivers',
          'timestamp': FieldValue.serverTimestamp(),
          'sent_by': 'Admin',
          'kind': 'compliance_alert',
        });
      }
      messenger.showSnackBar(SnackBar(
        content: Text("تم إرسال $count تنبيه استباقي آلي بنجاح 🤖✅"),
        backgroundColor: Colors.blueAccent,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('تعذّر إرسال التنبيهات — أعد المحاولة'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _launchURL(String url) async {
    // كان فشل canLaunchUrl (جهاز لوحي/ويب بلا تطبيق اتصال) يمرّ بلا أي أثر —
    // نُظهر الخطأ بدل الصمت.
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر فتح تطبيق الاتصال على هذا الجهاز'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر فتح تطبيق الاتصال: $e'),
          backgroundColor: Colors.red,
        ));
      }
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
