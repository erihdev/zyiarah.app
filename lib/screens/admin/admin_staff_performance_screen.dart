import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminStaffPerformanceScreen extends StatefulWidget {
  const AdminStaffPerformanceScreen({super.key});

  @override
  State<AdminStaffPerformanceScreen> createState() => _AdminStaffPerformanceScreenState();
}

class _AdminStaffPerformanceScreenState extends State<AdminStaffPerformanceScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _staffStats = [];

  @override
  void initState() {
    super.initState();
    _calculatePerformance();
  }

  Future<void> _calculatePerformance() async {
    final driversSnap = await FirebaseFirestore.instance.collection('drivers').get();
    final ordersSnap = await FirebaseFirestore.instance.collection('orders').where('status', isEqualTo: 'completed').get();

    List<Map<String, dynamic>> stats = [];

    for (var driverDoc in driversSnap.docs) {
      final driverData = driverDoc.data();
      final driverId = driverDoc.id;
      final driverName = driverData['name'] ?? 'بدون اسم';

      final driverOrders = ordersSnap.docs.where((doc) => doc['driver_id'] == driverId).toList();
      final totalCompleted = driverOrders.length;
      
      double totalRating = 0;
      int ratedOrders = 0;
      for (var order in driverOrders) {
        final orderData = order.data();
        if (orderData['rating'] != null) {
          totalRating += (orderData['rating'] as num).toDouble();
          ratedOrders++;
        }
      }

      double avgRating = ratedOrders > 0 ? totalRating / ratedOrders : 5.0;

      stats.add({
        'id': driverId,
        'name': driverName,
        'completed': totalCompleted,
        'rating': avgRating,
        'phone': driverData['phone'] ?? '-',
        'status': driverData['status'] ?? 'offline',
      });
    }

    // Sort by performance (Rating * volume)
    stats.sort((a, b) => (b['rating'] * b['completed']).compareTo(a['rating'] * a['completed']));

    if (mounted) {
      setState(() {
        _staffStats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text("كفاءة وأداء الكوادر", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildEliteHeroSection(),
                const SizedBox(height: 25),
                Text("ترتيب الكفاءة", style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                ..._staffStats.asMap().entries.map((entry) => _buildStaffCard(entry.value, entry.key + 1)),
              ],
            ),
      ),
    );
  }

  Widget _buildEliteHeroSection() {
    if (_staffStats.isEmpty) return const SizedBox.shrink();
    final top = _staffStats.first;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF5D1B5E), Color(0xFF7E3080)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF5D1B5E).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.amber, size: 50),
          const SizedBox(height: 15),
          Text("نجم الشهر الحالي", style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 14)),
          Text(top['name'], style: GoogleFonts.tajawal(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModernMiniStat("مهام", "${top['completed']}"),
              const SizedBox(width: 20),
              _buildModernMiniStat("التقييم", "${top['rating'].toStringAsFixed(1)} ★"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff, int rank) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank <= 3 ? Colors.amber.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text("$rank", style: TextStyle(fontWeight: FontWeight.bold, color: rank <= 3 ? Colors.orange : Colors.grey)),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff['name'], style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                Text(staff['phone'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text("${staff['rating'].toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Text("${staff['completed']} مهمة", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
            ],
          ),
        ],
      ),
    );
  }
}
