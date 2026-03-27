import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ZyiarahWalletScreen extends StatefulWidget {
  const ZyiarahWalletScreen({super.key});

  @override
  State<ZyiarahWalletScreen> createState() => _ZyiarahWalletScreenState();
}

class _ZyiarahWalletScreenState extends State<ZyiarahWalletScreen> {
  final Color brandPurple = const Color(0xFF5D1B5E);
  bool _isLoading = true;
  double _balance = 0.0;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final transDocs = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      if (mounted) {
        setState(() {
          _balance = (userDoc.data()?['wallet_balance'] ?? 0.0).toDouble();
          _transactions = transDocs.docs.map((d) => d.data() as Map<String, dynamic>).toList();
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
        title: Text('المحفظة الرقمية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading 
          ? Center(child: CircularProgressIndicator(color: brandPurple))
          : Directionality(
              textDirection: TextDirection.rtl,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildBalanceCard()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Text('العمليات الأخيرة', 
                        style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    ),
                  ),
                  _transactions.isEmpty 
                    ? SliverFillRemaining(child: _buildEmptyState())
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildTransactionItem(_transactions[index]),
                          childCount: _transactions.length,
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brandPurple, brandPurple.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: brandPurple.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          Text('الرصيد الحالي', style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 10),
          Text('${_balance.toStringAsFixed(2)} ر.س', 
            style: GoogleFonts.tajawal(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(Icons.add, 'شحن الرصيد', () {}),
              const SizedBox(width: 40),
              _buildActionButton(Icons.arrow_outward, 'تحويل', () {}),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.tajawal(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> data) {
    final bool isCredit = data['type'] == 'credit';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isCredit ? Colors.green : Colors.red).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: isCredit ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['title'] ?? 'عملية محفظة', 
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${timestamp.day}/${timestamp.month}/${timestamp.year}', 
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text('${isCredit ? '+' : '-'}${data['amount']} ر.س', 
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w900, 
              color: isCredit ? Colors.green : Colors.red,
              fontSize: 16,
            )),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Text('لا توجد عمليات سابقة', 
            style: GoogleFonts.tajawal(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
