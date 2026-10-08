import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/contract_health.dart';
import 'package:zyiarah/utils/home_packages.dart';
import 'package:zyiarah/utils/contract_ref.dart';
import 'package:zyiarah/utils/contract_visits.dart';

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

  // **البثُّ يُبنى مرّةً واحدةً، لا في كلِّ `build`.** كان يُنشأُ داخلَ دالّةِ
  // البناءِ، فكلُّ `setState` — حرفٌ في حقلِ البحثِ، تبديلُ مُرشِّح، فتحُ
  // حوار — يُلغي مستمِعَ Firestore ويُنشئُ غيرَه. والبياناتُ لا تَختفي
  // (`StreamBuilder` يَحفظُ آخرَ لقطةٍ عبرَ إعادةِ الاشتراك) فلا يُرى شيء،
  // والكلفةُ حقيقيّة — **والأثرُ الأخطرُ أنّ `firstEventTimeout` تُستأنف**:
  // على وصلةٍ تَبدو قائمةً ولا تَنفُذ (بوّابةُ فندقٍ، وكيلٌ شفّاف) تُعادُ
  // مهلةُ العشرينَ ثانيةً مع كلِّ حرفٍ يُكتَب، فلا يُبلَغُ فرعُ الخطأِ ولا
  // زرُّ إعادتِه أبداً — وهو العطلُ بعينِه الذي وُجدت المهلةُ لأجلِه.
  // والقاعدةُ مقرَّرةٌ في `driver_tasks_screen` ومُنفَّذةٌ فيه وحدَه.
  //
  // وإعادةُ المحاولةِ كانت تَعتمدُ على ذلك الأثرِ الجانبيِّ عينِه، فصارت
  // صريحةً: تَصفيرُ الحقلِ يَجعلُ البناءَ التاليَ يَفتحُ بثّاً جديداً.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _contracts;
  Stream<QuerySnapshot<Map<String, dynamic>>> get _contractsStream =>
      _contracts ??= FirebaseFirestore.instance
          .collection('contracts')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .firstEventTimeout();

  void _reopenContracts() => setState(() => _contracts = null);

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
    // **تلميحُ الحقلِ يَقولُ «أو رقم العقد»** — وكان المُرشَّحُ معرّفَ
    // المستندِ وحدَه، فالرقمُ المطبوعُ على العقدِ غيرُ قابلٍ للعثور.
    return planName.contains(query) ||
        clientName.contains(query) ||
        contractRefMatches(data['contractId'], doc.id, query);
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
                stream: _contractsStream,
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
    final String contractId = contractRef(data['contractId'], doc.id);

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
          // شارةُ الصفّ: الدفعةُ تُسمّي معرّفَ العقدِ، فبلا علامةٍ في القائمةِ
          // يَبحثُ الأدمنُ بعينِه عن عقدٍ لا يُميّزُه شيء.
          _contractHealthChip(data),
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
                // **الاعتمادُ لِما لم يُدفَع بعد.** كان الشرطُ
                // `status == 'pending'` وحدَها، وعقدٌ فشلَ تفعيلُه يَسكنُ
                // تلك الحالةَ — فالضغطةُ تُطالِبُ مَن دفعَ بالدفعِ وتُخرِجُه
                // ولا يُعادُ إطلاقُ مُشغّلِ التفعيل. التفصيلُ في
                // `contract_health.dart` (وفيه تصحيحُ بندِ «نافذةِ الإنقاذ»).
                if (contractApproveAllowed(data) && _canApproveContracts)
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
                // الإخفاءُ وحدَه يُقرأُ عطلاً في الشاشة، فيُقالُ سببُه مكانَه.
                if (!contractApproveAllowed(data) &&
                    contractApproveBlockedReason(data) != null &&
                    _canApproveContracts)
                  Expanded(
                    child: Text(contractApproveBlockedReason(data)!,
                        style: GoogleFonts.tajawal(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFB45309))),
                  ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _showDetails(data, doc.id),
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
    // شاشةٌ مفتوحةٌ من قبلِ وصولِ الدفعةِ تَحملُ لقطةً قديمةً، والبوّابةُ في
    // البناءِ وحدَها تَحرُسُ العرضَ لا الضغطة — فتُعادُ هنا بنصِّ السبب.
    final String? blocked = contractApproveBlockedReason(data);
    if (blocked != null) {
      messenger.showSnackBar(SnackBar(
          content: Text(blocked), backgroundColor: Colors.orange.shade800));
      return;
    }
    final confirm = await _showConfirm("اعتماد العقد", "هل أنت متأكد من اعتماد باقة (${data['planName']})؟");
    if (!confirm) return;
    try {
      await FirebaseFirestore.instance.collection('contracts').doc(doc.id).update({
        'status': 'approved_waiting_payment',
        'adminApprovedAt': FieldValue.serverTimestamp(),
      });
      // تسميةُ APPROVE_CONTRACT كانت في شاشةِ السجلِّ ولا كاتبَ لها: اعتمادُ
      // العقدِ — وهو ما يَفتحُ بابَ الدفعِ لأكبرِ مبلغٍ في التطبيق — بلا أثر.
      await ZyiarahAuditService().logAction(
        action: ZyiarahAuditService.actionApproveContract,
        details: {'plan': data['planName'] ?? '—', 'client': data['userName'] ?? '—'},
        targetId: doc.id,
      );
      await ZyiarahMessagingService().notifyContractApproved(
        data['userId'] ?? '',
        data['planName'] ?? 'باقة اشتراك',
        contractId: doc.id,
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
      // عمليّةٌ مدمّرةٌ محصورةٌ بالمدير العامِّ في القواعد — فأثرُها باسمِ
      // فاعلِها هو كلُّ ما يَبقى منها.
      await ZyiarahAuditService().logAction(
        action: ZyiarahAuditService.actionDeleteContract,
        details: {'contract_id': id},
        targetId: id,
      );
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

  // **المعرّفُ يُمرَّرُ**: الشِيتُ كان يَقرأُ `data` وحدَها، فزرُّ الـPDF
  // فيها لا يَملكُ معرّفَ المستندِ — ومن هنا جاءَ احتياطُ `'XXXX'`.
  void _showDetails(Map<String, dynamic> data, String docId) {
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
            _buildDetailRow("قيمة التعاقد", "${formatSarAny(data['planPrice'])} ر.س"),
            // **الوسمُ يَتبعُ المصدر.** كان «الزيارات المتاحة» فوقَ
            // `planVisits` — حجمُ الباقةِ الثابتُ — لا فوقَ
            // `visits_remaining` الذي يُحرّكُه الخادمُ. وهذه الورقةُ هي ما
            // يُجيبُ منها الأدمنُ «كم بقيَ لها؟»، فكان يَعِدُ بخدمةٍ على
            // رصيدٍ أُنفِقَ.
            _buildDetailRow(contractVisitsView(data).label,
                contractVisitsView(data).text),
            _buildDetailRow("رقم الاتصال", data['userPhone'] ?? 'غير مسجل'),
            _contractHealthBanner(data),
            const Divider(height: 32),
            if (data['status'] == 'active' || data['status'] == 'approved_waiting_payment')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ZyiarahPdfService.generateAndDownloadContract(
                        contractId: contractRef(data['contractId'], docId),
                        planName: data['planName'] ?? 'باقة اشتراك',
                        userName: data['userName'] ?? data['clientName'] ?? 'عميل زيارة',
                        userPhone: data['userPhone'] ?? 'غير مسجل',
                        price: (data['planPrice'] ?? 0).toDouble(),
                        visits: data['planVisits'] ?? 0,
                        startDate: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        signatureData: data['signatureData'], // Passing the actual signature data
                        // مالكُ العقدِ لا المُنادي: الترشيحُ يَبقى دقيقاً،
                        // وشرطُ الأدمنِ مُستوفًى بدورِه على أيِّ حال.
                        ownerUid: data['userId'] as String?,
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

  Widget _contractHealthChip(Map<String, dynamic> data) {
    final ContractHealth h = contractHealthOf(data);
    if (h == ContractHealth.ok) return const SizedBox.shrink();
    final bool human = contractNeedsHuman(h);
    final Color accent =
        human ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        children: [
          Icon(human ? Icons.gavel_rounded : Icons.autorenew_rounded,
              size: 14, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(kContractHealthTitles[h] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.tajawal(
                    fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          ),
        ],
      ),
    );
  }

  /// **وسمُ التفعيلِ كان بلا قارئ** — الأدمنُ يَتلقّى «لم يُفعَّل — راجعه
  /// يدوياً» ثمّ يَفتحُ عقداً يُشبهُ أيَّ معلَّقٍ غيرِ مدفوع. التفصيلُ في
  /// `lib/utils/contract_health.dart`.
  Widget _contractHealthBanner(Map<String, dynamic> data) {
    final ContractHealth h = contractHealthOf(data);
    if (h == ContractHealth.ok) return const SizedBox.shrink();
    final bool human = contractNeedsHuman(h);
    final Color accent =
        human ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
    final String? reason = contractHealthReason(data);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(human ? Icons.gavel_rounded : Icons.autorenew_rounded,
                  size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(kContractHealthTitles[h] ?? '',
                    style: GoogleFonts.tajawal(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent)),
              ),
            ],
          ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('السبب الذي سجّله الخادم: $reason',
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.grey.shade800)),
            ),
        ],
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
            onPressed: _reopenContracts,
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
