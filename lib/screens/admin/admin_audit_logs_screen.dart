import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

class AdminAuditLogsScreen extends StatefulWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  State<AdminAuditLogsScreen> createState() => _AdminAuditLogsScreenState();
}

class _AdminAuditLogsScreenState extends State<AdminAuditLogsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("سجل العمليات الإدارية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildHeaderInfo(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('audit_logs').orderBy('timestamp', descending: true).limit(100).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)));
                  }

                  final logs = snapshot.data?.docs ?? [];
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
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          _getActionLabel(action),
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

  String _getActionLabel(String action) {
    switch (action) {
      case 'CREATE_STAFF': return "إضافة موظف جديد";
      case 'UPDATE_STAFF': return "تعديل بيانات موظف";
      case 'DELETE_STAFF': return "حذف موظف";
      case 'CREATE_COUPON': return "إنشاء كود خصم";
      case 'UPDATE_COUPON': return "تعديل كود خصم";
      case 'DELETE_COUPON': return "حذف كود خصم";
      case 'UPDATE_SERVICE_PRICE': return "تغيير سعر خدمة";
      case 'TOGGLE_SERVICE_STATUS': return "تغيير حالة خدمة";
      case 'REGISTER_DRIVER': return "تسجيل كادر/عامل جديد";
      case 'UPDATE_DRIVER': return "تعديل بيانات كادر";
      case 'DELETE_DRIVER': return "حذف كادر نهائياً";
      case 'TOGGLE_DRIVER_STATUS': return "تغيير حالة كادر";
      case 'CREATE_ZONE': return "إضافة منطقة تغطية";
      case 'UPDATE_ZONE': return "تعديل منطقة تغطية";
      case 'DELETE_ZONE': return "حذف منطقة تغطية";
      default: return action;
    }
  }

  String _translateKey(String key) {
    switch (key) {
      case 'name': return "الاسم";
      case 'email': return "البريد";
      case 'role': return "الدور";
      case 'code': return "الكود";
      case 'price': return "السعر";
      case 'service': return "الخدمة";
      case 'type': return "النوع";
      case 'phone': return "الجوال";
      case 'status': return "الحالة";
      default: return key;
    }
  }
}
