import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

  static const Color _brand = Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('المالية والراتب',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: uid == null
            ? const Center(child: Text('يرجى تسجيل الدخول'))
            : _DriverEarningsBody(uid: uid),
      ),
    );
  }
}

class _DriverEarningsBody extends StatelessWidget {
  final String uid;
  const _DriverEarningsBody({required this.uid});

  static const Color _brand = Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('drivers').doc(uid).get(),
      builder: (context, driverSnap) {
        final driverData = driverSnap.data?.data() as Map<String, dynamic>? ?? {};
        final salary = (driverData['monthly_salary'] as num?)?.toDouble() ?? 0;
        final driverName = driverData['name'] as String? ?? 'السائق';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSalaryCard(salary, driverName),
              const SizedBox(height: 16),
              _buildMonthlyStats(),
              const SizedBox(height: 16),
              _buildPaymentHistory(),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalaryCard(double salary, String name) {
    final now = DateTime.now();
    final monthName = DateFormat('MMMM yyyy', 'ar').format(now);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5D1B5E), Color(0xFF7E3080)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الراتب الشهري',
                      style: GoogleFonts.tajawal(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(monthName,
                      style: GoogleFonts.tajawal(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            salary > 0
                ? '${salary.toStringAsFixed(0)} ريال'
                : 'غير محدد',
            style: GoogleFonts.tajawal(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              style: GoogleFonts.tajawal(
                  color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMonthlyStats() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driver_id', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snap) {
        final all = snap.data?.docs ?? [];

        final monthlyTasks = all.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final t = (data['end_time'] as Timestamp?)?.toDate();
          return t != null && t.isAfter(monthStart);
        }).length;

        final weeklyTasks = all.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final t = (data['end_time'] as Timestamp?)?.toDate();
          return t != null && t.isAfter(weekStart);
        }).length;

        final totalTasks = all.length;

        return Row(
          children: [
            _statCard('هذا الشهر', '$monthlyTasks', Icons.calendar_month_outlined, Colors.blue),
            const SizedBox(width: 10),
            _statCard('هذا الأسبوع', '$weeklyTasks', Icons.date_range_outlined, Colors.green),
            const SizedBox(width: 10),
            _statCard('الإجمالي', '$totalTasks', Icons.done_all_rounded, Colors.amber),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.tajawal(
                    fontSize: 10, color: Colors.grey[500]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('driver_payments')
          .where('driver_id', isEqualTo: uid)
          .orderBy('paid_at', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: _brand, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('سجل المدفوعات',
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
            if (snap.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator(color: _brand))
            else if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_outlined,
                          size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text('لا توجد سجلات مدفوعات بعد',
                          style: GoogleFonts.tajawal(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _PaymentCard(data: data);
              }),
          ],
        );
      },
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PaymentCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final note = data['note'] as String? ?? 'راتب شهري';
    final status = data['status'] as String? ?? 'paid';
    final paidAt =
        (data['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('yyyy/MM/dd').format(paidAt);

    final isPaid = status == 'paid';
    final statusColor = isPaid ? Colors.green : Colors.orange;
    final statusLabel = isPaid ? 'مدفوع' : 'معلق';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPaid
                  ? Icons.check_circle_outline
                  : Icons.hourglass_empty_outlined,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note,
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(dateStr,
                        style: GoogleFonts.tajawal(
                            fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${amount.toStringAsFixed(0)} ريال',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: const Color(0xFF1E293B))),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.tajawal(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
