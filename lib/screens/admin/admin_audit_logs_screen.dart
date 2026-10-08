import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/audit_actions.dart';
import 'package:zyiarah/utils/net_timeout.dart';

class AdminAuditLogsScreen extends StatefulWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  State<AdminAuditLogsScreen> createState() => _AdminAuditLogsScreenState();
}

class _AdminAuditLogsScreenState extends State<AdminAuditLogsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _selectedFilter = 'ALL';

  final List<Map<String, String>> _filters = [
    {'id': 'ALL', 'label': 'الكل'},
    {'id': 'ORDER', 'label': 'الطلبات'},
    {'id': 'STAFF', 'label': 'الموظفين'},
    {'id': 'COUPON', 'label': 'الأكواد'},
    {'id': 'DRIVER', 'label': 'الكوادر'},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("سجل العمليات الإدارية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildHeaderInfo(),
            _buildFilterBar(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getFilteredStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)));
                  }

                  // فشل البث كان يُعرض كقائمة فارغة — خطأ صريح مع إعادة محاولة.
                  if (snapshot.hasError) {
                    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 10),
                      Text('تعذّر تحميل البيانات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.red)),
                      TextButton(onPressed: _reopenLogs, child: const Text('إعادة المحاولة')),
                    ]));
                  }

                  final logs = _applyFilter(snapshot.data?.docs ?? []);
                  if (logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history_edu, size: 80, color: Colors.grey),
                          const SizedBox(height: 20),
                          Text("لا توجد سجلات حالياً", style: GoogleFonts.tajawal(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index].data() as Map<String, dynamic>;
                      return _buildLogCard(log);
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

  Widget _buildHeaderInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "تتبع الشفافية والمسؤولية",
            style: GoogleFonts.tajawal(color: Colors.blue[200], fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "هذا السجل يوثق كافة التغييرات الجوهرية التي يقوم بها أعضاء الفريق الإداري لضمان جودة العمل.",
            style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter['id'];
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(filter['label']!,
                  style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              selected: isSelected,
              onSelected: (val) => setState(() => _selectedFilter = filter['id']!),
              selectedColor: const Color(0xFF1E293B).withValues(alpha: 0.1),
              checkmarkColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

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
  Stream<QuerySnapshot<Map<String, dynamic>>>? _logs;

  /// الاستعلامُ **لا يَتبعُ المُرشِّح**: الترشيحُ محلّيٌّ (`_applyFilter`) تجنّباً
  /// لفهرسٍ مركَّبٍ على (action, timestamp) — فلا شيءَ يُوجِبُ إعادةَ فتحِه.
  Stream<QuerySnapshot<Map<String, dynamic>>> _getFilteredStream() => _logs ??= _db
      .collection('audit_logs')
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots()
      .firstEventTimeout();

  void _reopenLogs() => setState(() => _logs = null);

  List<QueryDocumentSnapshot> _applyFilter(List<QueryDocumentSnapshot> docs) {
    if (_selectedFilter == 'ALL') return docs.take(100).toList();
    // contains لا startsWith: أسماء الإجراءات تبدأ بفعل (CREATE_STAFF/DELETE_COUPON/
    // ASSIGN_DRIVER) بينما المرشّحات أسماء (STAFF/COUPON/DRIVER/ORDER) — كان startsWith
    // لا يطابق أي إجراء فتظهر كل الفلاتر فارغة.
    return docs
        .where((d) =>
            ((d.data() as Map)['action'] as String? ?? '')
                .toUpperCase()
                .contains(_selectedFilter))
        .take(100)
        .toList();
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final DateTime? ts = (log['timestamp'] as Timestamp?)?.toDate();
    final String timeStr = ts != null ? intl.DateFormat('yyyy-MM-dd HH:mm').format(ts) : '-';
    final String action = log['action'] ?? 'Unknown';
    final String email = log['admin_email'] ?? 'System';
    final Map<String, dynamic> details = log['details'] ?? {};

    IconData icon;
    Color color;

    if (action.contains('CREATE')) {
      icon = Icons.add_circle_outline;
      color = Colors.green;
    } else if (action.contains('DELETE')) {
      icon = Icons.remove_circle_outline;
      color = Colors.red;
    } else if (action.contains('UPDATE')) {
      icon = Icons.edit_note;
      color = Colors.blue;
    } else {
      icon = Icons.settings_accessibility;
      color = Colors.blueGrey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          auditActionLabel(action),
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          "$email • $timeStr",
          style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[600]),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                ...details.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text("${_translateKey(e.key)}: ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Expanded(child: Text("${e.value}", style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _translateKey(String key) {
    switch (key) {
      case 'name': return "الاسم";
      case 'email': return "البريد";
      case 'role': return "الدور";
      case 'code': return "الكود";
      case 'order_code': return "رقم الطلب";
      case 'new_status': return "الحالة الجديدة";
      case 'old_status': return "الحالة السابقة";
      case 'assigned_driver': return "الكادر المعين";
      case 'price': return "السعر";
      case 'service': return "الخدمة";
      case 'type': return "النوع";
      case 'phone': return "الجوال";
      case 'status': return "الحالة";
      case 'staff_role': return "تخصص الإدارة";
      case 'admin_email': return "بريد المسؤول";
      case 'contract_id': return "رقم العقد";
      case 'plan': return "الباقة";
      case 'visits': return "عدد الزيارات";
      case 'client': return "اسم العميل";
      default: return key;
    }
  }
}
