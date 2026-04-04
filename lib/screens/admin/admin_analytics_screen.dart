import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_users_screen.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  int _totalUsers = 0;
  int _totalOrders = 0;
  int _completedOrders = 0;
  double _totalRevenue = 0.0;
  
  Map<String, int> _serviceDistribution = {};
  List<Map<String, dynamic>> _recentOrders = [];
  
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
      List<Map<String, dynamic>> recent = [];

      for (int i = 0; i < ordersSnap.docs.length; i++) {
        final doc = ordersSnap.docs[i];
        final data = doc.data();
        
        final status = data['status'] ?? 'pending';
        final amount = (data['amount'] ?? 0.0) as num;
        final serviceType = data['service_type'] ?? 'أخرى';

        // Count services
        distribution[serviceType] = (distribution[serviceType] ?? 0) + 1;

        if (status == 'completed') {
          completed++;
        }
        if (status != 'cancelled') {
          revenue += amount.toDouble();
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
                    _buildSectionHeader('توزيع الخدمات'),
                    const SizedBox(height: 15),
                    _buildServiceDistributionBars(),
                    
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
