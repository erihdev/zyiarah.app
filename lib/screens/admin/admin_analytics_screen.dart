import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;

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
      final ordersSnap = await _db.collection('orders').get();
      _totalOrders = ordersSnap.docs.length;
      
      double revenue = 0.0;
      int completed = 0;
      Map<String, int> distribution = {};

      for (var doc in ordersSnap.docs) {
        final data = doc.data();
        
        final status = data['status'] ?? 'pending';
        final amount = (data['amount'] ?? 0.0) as num;
        final serviceType = data['service_type'] ?? 'أخرى';

        // Count services
        distribution[serviceType] = (distribution[serviceType] ?? 0) + 1;

        if (status == 'completed') {
          completed++;
        }
        // Assuming revenue is counted for non-cancelled orders, or just completed
        if (status != 'cancelled') {
          revenue += amount.toDouble();
        }
      }

      _completedOrders = completed;
      _totalRevenue = revenue;
      _serviceDistribution = distribution;

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
        title: Text('لوحة الإحصائيات والأرباح', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نظرة عامة', style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    const SizedBox(height: 20),
                    
                    // Main Revenue Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF047857)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
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
                              const Text('إجمالي المبيعات (التقديرية)', style: TextStyle(color: Colors.white, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            intl.NumberFormat.currency(symbol: 'ر.س', decimalDigits: 0).format(_totalRevenue),
                            style: GoogleFonts.tajawal(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Grid Stats
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('إجمالي الطلبات', _totalOrders.toString(), Icons.shopping_bag_outlined, Colors.blue)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildStatCard('الطلبات المكتملة', _completedOrders.toString(), Icons.check_circle_outline, Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('إجمالي العملاء', _totalUsers.toString(), Icons.people_outline, Colors.purple)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildStatCard('معدل الإنجاز', _totalOrders > 0 ? '${((_completedOrders / _totalOrders) * 100).toStringAsFixed(1)}%' : '0%', Icons.analytics_outlined, Colors.orange)),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    Text('توزيع الطلبات حسب الخدمة', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    const SizedBox(height: 15),
                    
                    ..._serviceDistribution.entries.map((e) {
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
                                Text('${e.value} طلب (${(percentage * 100).toStringAsFixed(0)}%)', style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: percentage,
                                minHeight: 10,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.primaries[e.key.hashCode % Colors.primaries.length]),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
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
          Text(value, style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
        ],
      ),
    );
  }
}
