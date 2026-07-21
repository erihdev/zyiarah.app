import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';

/// Lightweight financial snapshot computed client-side from the `orders`
/// collection (current + last month only — never the full history).
class _FinancialData {
  final double thisMonthRevenue;
  final double lastMonthRevenue;
  final Map<String, double> methodTotals; // this month, keyed by payment_method
  final List<_TxRow> latestTransactions; // latest completed this month (~15)

  _FinancialData({
    required this.thisMonthRevenue,
    required this.lastMonthRevenue,
    required this.methodTotals,
    required this.latestTransactions,
  });

  /// Month-over-month growth as a fraction (e.g. 0.25 == +25%).
  /// Null when there is no prior-month baseline to compare against.
  double? get growth {
    if (lastMonthRevenue <= 0) return null;
    return (thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue;
  }
}

class _TxRow {
  final String clientName;
  final String service;
  final double amount;
  final DateTime? date;

  _TxRow({
    required this.clientName,
    required this.service,
    required this.amount,
    required this.date,
  });
}

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  late final Future<_FinancialData> _financialFuture;

  // Arabic labels for payment methods.
  static const Map<String, String> _methodLabels = {
    'card': 'بطاقة',
    'tamara': 'تمارا',
    'tabby': 'تابي',
    'wallet': 'محفظة',
    'stc_pay': 'STC Pay',
    'apple_pay': 'Apple Pay',
  };

  @override
  void initState() {
    super.initState();
    _financialFuture = _loadFinancials();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  Future<_FinancialData> _loadFinancials() async {
    final now = DateTime.now();
    final startOfThisMonth = DateTime(now.year, now.month, 1);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    // Bounded window: only this month + last month. We range/order on
    // created_at (single-field index) and filter status client-side to
    // avoid requiring a composite index.
    final snap = await db
        .collection('orders')
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfLastMonth))
        .where('created_at', isLessThan: Timestamp.fromDate(startOfNextMonth))
        .orderBy('created_at', descending: true)
        .get();

    double thisMonthRevenue = 0;
    double lastMonthRevenue = 0;
    final Map<String, double> methodTotals = {};
    final List<_TxRow> latestTransactions = [];

    for (final doc in snap.docs) {
      final d = doc.data();
      if ((d['status'] ?? '') != 'completed') continue;

      final createdAt = (d['created_at'] as Timestamp?)?.toDate();
      final amount = _toDouble(d['amount']);
      final isThisMonth =
          createdAt != null && !createdAt.isBefore(startOfThisMonth);

      if (isThisMonth) {
        thisMonthRevenue += amount;

        final method = (d['payment_method'] ?? 'card').toString();
        methodTotals[method] = (methodTotals[method] ?? 0) + amount;

        if (latestTransactions.length < 15) {
          latestTransactions.add(_TxRow(
            clientName:
                (d['client_name'] ?? d['userName'] ?? 'عميل').toString(),
            service: (d['service_name'] ??
                    d['service_type'] ??
                    d['service_name_ar'] ??
                    'خدمة')
                .toString(),
            amount: _toDouble(d['final_amount'] ?? d['amount']),
            date: createdAt,
          ));
        }
      } else {
        lastMonthRevenue += amount;
      }
    }

    return _FinancialData(
      thisMonthRevenue: thisMonthRevenue,
      lastMonthRevenue: lastMonthRevenue,
      methodTotals: methodTotals,
      latestTransactions: latestTransactions,
    );
  }

  Widget _buildHeroRevenueCard(BuildContext context, double totalRevenue) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text('إجمالي الإيرادات (تقديري)', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              intl.NumberFormat.currency(symbol: 'ر.س ', decimalDigits: 0).format(totalRevenue),
              style: GoogleFonts.tajawal(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text('محدث فورياً من قاعدة البيانات (انقر للتفاصيل)', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Small colored +/- badge showing month-over-month revenue growth,
  /// placed near the revenue hero card.
  Widget _buildGrowthBadge(_FinancialData f) {
    final growth = f.growth;
    if (growth == null) {
      // No prior-month baseline to compare against.
      return const SizedBox.shrink();
    }
    final bool up = growth >= 0;
    final Color color = up ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final String pct = '${up ? '+' : ''}${(growth * 100).toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            pct,
            style: GoogleFonts.tajawal(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          const Text('عن الشهر الماضي', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildPaymentBreakdown(_FinancialData f) {
    final total =
        f.methodTotals.values.fold<double>(0, (acc, v) => acc + v);
    if (f.methodTotals.isEmpty || total <= 0) {
      return _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طرق الدفع هذا الشهر',
                style: GoogleFonts.tajawal(
                    fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
            const SizedBox(height: 16),
            const Text('لا توجد مدفوعات مكتملة هذا الشهر',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    // Sort methods by amount descending.
    final entries = f.methodTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('طرق الدفع هذا الشهر',
              style: GoogleFonts.tajawal(
                  fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          const SizedBox(height: 16),
          ...entries.map((e) {
            final label = _methodLabels[e.key] ?? 'أخرى';
            final fraction = total > 0 ? (e.value / total) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: GoogleFonts.tajawal(
                              fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                      const Spacer(),
                      Text(
                        '${intl.NumberFormat.currency(symbol: 'ر.س ', decimalDigits: 0).format(e.value)}  (${(fraction * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5D1B5E)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLatestTransactions(_FinancialData f) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أحدث المعاملات',
              style: GoogleFonts.tajawal(
                  fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          const SizedBox(height: 12),
          if (f.latestTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('لا توجد معاملات مكتملة هذا الشهر',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
            ...f.latestTransactions.map((tx) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5D1B5E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF5D1B5E), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tx.clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.tajawal(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                          const SizedBox(height: 2),
                          Text(tx.service,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          intl.NumberFormat.currency(symbol: 'ر.س ', decimalDigits: 0).format(tx.amount),
                          style: GoogleFonts.tajawal(
                              fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tx.date != null ? intl.DateFormat('d MMM', 'ar').format(tx.date!) : '',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFinancialSection() {
    return FutureBuilder<_FinancialData>(
      future: _financialFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return _sectionCard(
            child: const Text('تعذّر تحميل البيانات المالية',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          );
        }
        final f = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGrowthBadge(f),
            const SizedBox(height: 20),
            Text(
              'الأداء المالي',
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 15),
            _buildPaymentBreakdown(f),
            const SizedBox(height: 20),
            _buildLatestTransactions(f),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 15),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 5),
              Text(
                value,
                style: GoogleFonts.tajawal(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('لوحة التحليلات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<DocumentSnapshot>(
          stream: db.collection('metadata').doc('analytics_summary').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final double totalRevenue = (docData['total_revenue'] ?? 0.0).toDouble();
            final int activeOrders = (docData['active_orders'] ?? 0).toInt();
            final int completedOrders = (docData['completed_orders'] ?? 0).toInt();
            // الإيراد المخزَّن شامل الضريبة (المبلغ المشحون = الأساس×1.15)، فالضريبة
            // تُستخرج منه قسمةً لا تُضاف عليه ثانيةً (كانت تُضخَّم 15% زيادة).
            final double vatAmount = totalRevenue - (totalRevenue / 1.15);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroRevenueCard(context, totalRevenue),
                  const SizedBox(height: 16),
                  _buildFinancialSection(),
                  const SizedBox(height: 20),
                  Text(
                    'نظرة سريعة',
                    style: GoogleFonts.tajawal(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'الطلبات النشطة',
                          activeOrders.toString(),
                          Icons.pending_actions_outlined,
                          Colors.blue,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'الطلبات المكتملة',
                          completedOrders.toString(),
                          Icons.check_circle_outline,
                          Colors.green,
                          onTap: null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'ضريبة القيمة المضافة (15%)',
                          intl.NumberFormat.currency(symbol: 'ر.س ', decimalDigits: 0).format(vatAmount),
                          Icons.receipt_long_outlined,
                          Colors.purple,
                          onTap: null,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'معدل الإنجاز',
                          (activeOrders + completedOrders) > 0
                              ? '${((completedOrders / (activeOrders + completedOrders)) * 100).toStringAsFixed(0)}%'
                              : '0%',
                          Icons.analytics_outlined,
                          Colors.orange,
                          onTap: null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
