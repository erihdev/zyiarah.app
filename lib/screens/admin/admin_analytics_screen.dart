import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/admin/admin_users_screen.dart';
import 'package:zyiarah/services/report_service.dart';
import 'package:intl/intl.dart' as intl;
import 'package:fl_chart/fl_chart.dart';
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahReportService _reportService = ZyiarahReportService();
  
  bool _isLoading = true;
  int _totalUsers = 0;
  int _totalOrders = 0;
  int _completedOrders = 0;
  double _totalRevenue = 0.0;
  
  Map<String, int> _serviceDistribution = {};
  List<Map<String, dynamic>> _recentOrders = [];
  List<double> _weeklyRevenue = List.filled(7, 0.0);
  final Map<String, double> _monthlyRevenue = {};
  
  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    try {
      // 1. Fetch Users Count
      final usersSnap = await _db.collection('users').count().get();
      _totalUsers = usersSnap.count ?? 0;

      // 2. Fetch Orders Data
      final ordersSnap = await _db.collection('orders').orderBy('created_at', descending: true).get();
      _totalOrders = ordersSnap.docs.length;
      
      double revenue = 0.0;
      int completed = 0;
      Map<String, int> distribution = {};
      List<double> weeklyRev = List.filled(7, 0.0);
      final now = DateTime.now();
      List<Map<String, dynamic>> recent = [];

      for (int i = 0; i < ordersSnap.docs.length; i++) {
        final doc = ordersSnap.docs[i];
        final data = doc.data();
        
        final status = data['status'] ?? 'pending';
        final amount = (data['amount'] ?? 0.0) as num;
        final serviceType = data['service_type'] ?? 'أخرى';
        final createdAt = (data['created_at'] as Timestamp?)?.toDate() ?? now;

        // Group by service
        distribution[serviceType] = (distribution[serviceType] ?? 0) + 1;

        if (status == 'completed') {
          completed++;
        }
        if (status != 'cancelled') {
          revenue += amount.toDouble();
          
          // Weekly revenue grouping
          final difference = now.difference(createdAt).inDays;
          if (difference >= 0 && difference < 7) {
            weeklyRev[6 - difference] += amount.toDouble();
          }

          // Monthly revenue grouping
          final monthKey = intl.DateFormat('yyyy-MM').format(createdAt);
          _monthlyRevenue[monthKey] = (_monthlyRevenue[monthKey] ?? 0.0) + amount.toDouble();
        }

        // Add to recent if first 5
        if (recent.length < 5) {
          recent.add({
            'id': doc.id,
            'service': data['service_name'] ?? 'خدمة',
            'status': status,
            'amount': amount,
            'date': data['created_at'] != null ? (data['created_at'] as Timestamp).toDate() : DateTime.now(),
          });
        }
      }

      _completedOrders = completed;
      _totalRevenue = revenue;
      _serviceDistribution = distribution;
      _recentOrders = recent;
      _weeklyRevenue = weeklyRev;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('لوحة التحليلات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            tooltip: 'تصدير تقرير PDF',
            onPressed: _isLoading ? null : () async {
               // Fetch all orders for report
               final snap = await _db.collection('orders').get();
               final orders = snap.docs.map((d) => d.data()).toList();
               
               await _reportService.generateOrdersReport(
                 orders: orders, 
                 periodName: "إجمالي الفترة الحالية", 
                 totalRevenue: _totalRevenue
                );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroRevenueCard(),
                    const SizedBox(height: 20),
                    
                    Text('نظرة سريعة', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('إجمالي الطلبات', _totalOrders.toString(), Icons.shopping_bag_outlined, Colors.blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())))),
                        const SizedBox(width: 15),
                        Expanded(child: _buildStatCard('المكتملة', _completedOrders.toString(), Icons.check_circle_outline, Colors.green, onTap: null)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('العملاء', _totalUsers.toString(), Icons.people_outline, Colors.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen())))),
                        const SizedBox(width: 15),
                        Expanded(child: _buildStatCard('معدل الإنجاز', _totalOrders > 0 ? '${((_completedOrders / _totalOrders) * 100).toStringAsFixed(0)}%' : '0%', Icons.analytics_outlined, Colors.orange, onTap: null)),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    _buildSectionHeader('تحليل الإيرادات (آخر 7 أيام)'),
                    const SizedBox(height: 15),
                    _buildRevenueChart(),

                    const SizedBox(height: 30),
                    _buildSectionHeader('توزيع الخدمات'),
                    const SizedBox(height: 15),
                    _buildServiceDistributionBars(),

                    const SizedBox(height: 30),
                    _buildSectionHeader('نمو الإيرادات الشهرية'),
                    const SizedBox(height: 15),
                    _buildMonthlyRevenueList(),
                    
                    const SizedBox(height: 30),
                    _buildSectionHeader('آخر الطلبات'),
                    const SizedBox(height: 15),
                    _buildRecentOrdersList(),
                    
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())), child: const Text("مشاهدة الكل")),
      ],
    );
  }

  Widget _buildHeroRevenueCard() {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text('إجمالي الإيرادات (تقديري)', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              intl.NumberFormat.currency(symbol: 'ر.س ', decimalDigits: 0).format(_totalRevenue),
              style: GoogleFonts.tajawal(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text('محدث فورياً من قاعدة البيانات (انقر للتفاصيل)', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 15),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 5),
              Text(value, style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceDistributionBars() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: _serviceDistribution.entries.map((e) {
          final percentage = _totalOrders > 0 ? e.value / _totalOrders : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${e.value} طلب', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10))),
                    AnimatedContainer(
                      duration: const Duration(seconds: 1),
                      height: 10,
                      width: (MediaQuery.of(context).size.width - 80) * percentage,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.blue, Colors.blue.shade900]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 250,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)]),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _weeklyRevenue.reduce((a, b) => a > b ? a : b) * 1.2 + 100,
          barTouchData: const BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = ['6d', '5d', '4d', '3d', '2d', '1d', 'اليوم'];
                  if (value.toInt() >= 0 && value.toInt() < 7) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(days[value.toInt()], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _weeklyRevenue[i],
                  color: i == 6 ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMonthlyRevenueList() {
    // Sort months descending
    final sortedMonths = _monthlyRevenue.keys.toList()..sort((a, b) => b.compareTo(a));
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: sortedMonths.map((month) {
          final amount = _monthlyRevenue[month]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(height: 8, width: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(month, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Text("${intl.NumberFormat.currency(symbol: '', decimalDigits: 0).format(amount)} ر.س", 
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentOrdersList() {
    return Column(
      children: _recentOrders.map((order) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: const Icon(Icons.shopping_cart, color: Colors.blue, size: 20)),
            title: Text(order['service'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(intl.DateFormat('yyyy-MM-dd HH:mm').format(order['date'])),
            trailing: Text("${order['amount']} ر.س", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        );
      }).toList(),
    );
  }
}
