import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

class AdminContractsScreen extends StatefulWidget {
  const AdminContractsScreen({super.key});

  @override
  State<AdminContractsScreen> createState() => _AdminContractsScreenState();
}

class _AdminContractsScreenState extends State<AdminContractsScreen> {
  final Color primaryNavy = const Color(0xFF1E293B);
  final Color brandBlue = const Color(0xFF2563EB);
  final Color brandPurple = const Color(0xFF660033);

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  // حذف العقود في firestore.rules حكرٌ على isSuperAdmin، والشاشة تُفتح أيضاً من
  // orders_manager (شاشة المزيد) و accountant/marketing (بطاقة الرؤى) — نجلب الدور
  // مرة (نمط AdminDashboardScreen) لإخفاء زر حذفٍ كان يفشل حتماً لهؤلاء.
  String _role = 'none';

  bool get _canDeleteContracts => const ['admin', 'super_admin'].contains(_role);

  // اعتماد العقد عملية إدارة طلبات (يغيّر status ويطلق إشعار العميل) — حكرها
  // على مديري الطلبات كسائر إجراءات الإدارة، لا للمحاسب/التسويق الواصلَين من
  // بطاقة الرؤى للعرض فقط.
  bool get _canApproveContracts =>
      const ['admin', 'super_admin', 'orders_manager'].contains(_role);

  @override
  void initState() {
    super.initState();
    _fetchRole();
  }

  Future<void> _fetchRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final role = await ZyiarahFirebaseService().getUserRole(user.uid) ?? 'none';
      if (mounted) setState(() => _role = role);
    } catch (_) {
      // فشل جلب الدور يُبقي زر الحذف مخفياً — الافتراض الآمن، ولا فائدة من إزعاج
      // المستخدم بخطأ لا يعطّل باقي الشاشة (العرض والاعتماد يعملان).
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(DocumentSnapshot doc) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    final data = doc.data() as Map<String, dynamic>;
    final String planName = (data['planName'] ?? '').toString().toLowerCase();
    final String clientName =
        (data['userName'] ?? data['clientName'] ?? '').toString().toLowerCase();
    final String contractCode = doc.id.substring(0, 8).toLowerCase();
    return planName.contains(query) ||
        clientName.contains(query) ||
        contractCode.contains(query);
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _search = value),
        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: "ابحث بالاسم أو الباقة أو رقم العقد",
          hintStyle: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: brandPurple),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.blueGrey.shade100, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: brandPurple, width: 2),
          ),
        ),
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
          title: Text("العقود الإلكترونية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildSearchField(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('contracts').orderBy('createdAt', descending: true).limit(100).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // خطأ البثّ كان يُعرض «لا توجد عقود حالياً» — لا يميّزه الأدمن
                  // عن مجموعة فارغة فعلاً. نُظهر خطأً صريحاً مع إعادة محاولة
                  // (setState يعيد الاشتراك لأن خطأ الاستماع يُنهي البثّ نهائياً).
                  if (snapshot.hasError) {
                    return _buildErrorState();
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final filteredDocs = snapshot.data!.docs.where(_matchesSearch).toList();

                  if (filteredDocs.isEmpty) {
                    return _buildNoResultsState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      return _buildContractCard(doc);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String planName = data['planName'] ?? 'باقة اشتراك';
    final String clientName = data['userName'] ?? data['clientName'] ?? 'عميل زيارة';
    final String status = data['status'] ?? 'pending';
    final DateTime createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final String contractId = doc.id.substring(0, 8).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueGrey.shade100, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brandBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.description_rounded, color: brandBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 16, color: primaryNavy),
                      ),
                      Text(
                        "رقم العقد: #$contractId",
                        style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
          ),
          
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Details Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildInfoBit("العميل", clientName, Icons.person_outline),
                _buildInfoBit("تاريخ التوقيع", intl.DateFormat('dd-MM-yyyy').format(createdAt), Icons.calendar_today_outlined),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (status == 'pending' && _canApproveContracts)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveContract(doc),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text("اعتماد العقد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _showDetails(data),
                  icon: const Icon(Icons.info_outline_rounded),
                  style: IconButton.styleFrom(backgroundColor: Colors.blueGrey[50], foregroundColor: Colors.blueGrey[600]),
                ),
                if (_canDeleteContracts)
                  IconButton.filled(
                    onPressed: () => _deleteContract(doc.id),
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBit(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold, color: primaryNavy),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    String text = status;
    IconData icon = Icons.help_outline;

    switch (status) {
      case 'active':
        color = Colors.green;
        text = "مفعل";
        icon = Icons.verified_user_rounded;
        break;
      case 'approved_waiting_payment':
        color = Colors.blue;
        text = "بانتظار الدفع";
        icon = Icons.payments_rounded;
        break;
      case 'pending':
        color = Colors.orange;
        text = "قيد المراجعة";
        icon = Icons.timer_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _approveContract(DocumentSnapshot doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = doc.data() as Map<String, dynamic>;
    final confirm = await _showConfirm("اعتماد العقد", "هل أنت متأكد من اعتماد باقة (${data['planName']})؟");
    if (!confirm) return;
    try {
      await FirebaseFirestore.instance.collection('contracts').doc(doc.id).update({
        'status': 'approved_waiting_payment',
        'adminApprovedAt': FieldValue.serverTimestamp(),
      });
      await ZyiarahMessagingService().notifyContractApproved(
        data['userId'] ?? '',
        data['planName'] ?? 'باقة اشتراك',
      );
      messenger.showSnackBar(const SnackBar(
          content: Text('تم اعتماد العقد ✅'), backgroundColor: Colors.green));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('تعذّر اعتماد العقد — أعد المحاولة'), backgroundColor: Colors.red));
    }
  }

  void _deleteContract(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await _showConfirm("حذف العقد", "سيتم حذف هذا السجل نهائياً. هل أنت متأكد؟");
    if (!confirm) return;
    try {
      await FirebaseFirestore.instance.collection('contracts').doc(id).delete();
      messenger.showSnackBar(const SnackBar(
          content: Text('تم حذف العقد'), backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      // permission-denied دائمٌ لغير المدير العام (rules) — «أعد المحاولة» كانت
      // مضلِّلة وتدفع للتكرار بلا جدوى.
      messenger.showSnackBar(SnackBar(
          content: Text(e.code == 'permission-denied'
              ? 'صلاحية غير كافية — حذف العقود متاح للمدير العام فقط'
              : 'تعذّر حذف العقد — أعد المحاولة'),
          backgroundColor: Colors.red));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('تعذّر حذف العقد — أعد المحاولة'), backgroundColor: Colors.red));
    }
  }

  void _showDetails(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Text("تفاصيل العقد", style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 20)),
            const Divider(height: 32),
            _buildDetailRow("اسم العميل", data['userName'] ?? data['clientName'] ?? 'عميل زيارة'),
            _buildDetailRow("الباقة", data['planName'] ?? 'باقة اشتراك'),
            _buildDetailRow("قيمة التعاقد", "${data['planPrice'] ?? 0} ر.س"),
            _buildDetailRow("الزيارات المتاحة", "${data['planVisits'] ?? 0} زيارة"),
            _buildDetailRow("رقم الاتصال", data['userPhone'] ?? 'غير مسجل'),
            const Divider(height: 32),
            if (data['status'] == 'active' || data['status'] == 'approved_waiting_payment')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ZyiarahPdfService.generateAndDownloadContract(
                        contractId: data['contractId'] ?? 'XXXX',
                        planName: data['planName'] ?? 'باقة اشتراك',
                        userName: data['userName'] ?? data['clientName'] ?? 'عميل زيارة',
                        userPhone: data['userPhone'] ?? 'غير مسجل',
                        price: (data['planPrice'] ?? 0).toDouble(),
                        visits: data['planVisits'] ?? 0,
                        startDate: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        signatureData: data['signatureData'], // Passing the actual signature data
                      );
                    } catch (e) {
                      // SnackBar الشاشة يُرسم خلف الشيت المفتوحة فيبدو الزر ميتاً —
                      // نغلق الشيت أولاً ثم نعرض الخطأ عبر messenger ملتقط مسبقاً
                      // (نفس نمط _deleteContract).
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(SnackBar(
                          content: Text('فشل إنشاء الملف: $e'),
                          backgroundColor: Colors.red));
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("تحميل نسخة العقد (PDF)", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.blue),
                    foregroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("إغلاق", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(value, style: GoogleFonts.tajawal(color: primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<bool> _showConfirm(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        content: Text(body, style: GoogleFonts.tajawal()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: primaryNavy, foregroundColor: Colors.white), child: const Text("تأكيد")),
        ],
      ),
    ) ?? false;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text("لا توجد عقود حالياً", style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // خطأ ≠ فارغ: رسالة حمراء صريحة وزر إعادة محاولة يعيد الاشتراك في البثّ.
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 80, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text("تعذّر تحميل العقود", style: GoogleFonts.tajawal(fontSize: 18, color: Colors.red[700], fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text("إعادة المحاولة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: brandPurple, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            "لا نتائج للبحث «${_search.trim()}»",
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
