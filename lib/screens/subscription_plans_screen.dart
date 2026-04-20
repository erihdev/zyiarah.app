import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/contract_signing_screen.dart';

class ZyiarahSubscriptionPlansScreen extends StatefulWidget {
  const ZyiarahSubscriptionPlansScreen({super.key});

  @override
  State<ZyiarahSubscriptionPlansScreen> createState() => _ZyiarahSubscriptionPlansScreenState();
}

class _ZyiarahSubscriptionPlansScreenState extends State<ZyiarahSubscriptionPlansScreen> {
  final Color brandPurple = const Color(0xFF5D1B5E);
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _packages = [];

  @override
  void initState() {
    super.initState();
    _fetchPackages();
  }

  Future<void> _fetchPackages() async {
    try {
      final snapshot = await _db.collection('subscription_packages').orderBy('rank').get();
      if (mounted) {
        setState(() {
          _packages = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('سلة العائلة (الاشتراكات)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoSection(),
                  const SizedBox(height: 30),
                  if (_packages.isEmpty)
                    Center(
                      child: Text(
                        'لا توجد باقات متاحة حالياً', 
                        style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  ..._packages.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final features = (data['features'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                    final isPremium = data['isPremium'] == true;
                    // Provide aesthetic colors
                    Color cardColor = brandPurple;
                    if (isPremium) {
                      cardColor = Colors.amber.shade700;
                    } else if (_packages.indexOf(doc) % 2 == 0) {
                      cardColor = Colors.blue.shade600;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _buildPlanCard(
                        context,
                        data['title'] ?? 'باقة اشتراك',
                        data['subtitle'] ?? '',
                        '${data['price']} ر.س',
                        features,
                        cardColor,
                        isPremium: isPremium,
                        priceValue: (data['price'] ?? 0).toDouble(),
                        visits: (data['visits'] ?? 0).toInt(),
                      ),
                    );
                  }),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brandPurple.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: brandPurple, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'اختر الباقة المناسبة لعائلتك. بعد اختيار الباقة سيتم توجيه طلبك للإدارة للموافقة عليه قبل توقيع العقد الإلكتروني.',
              style: GoogleFonts.tajawal(fontSize: 13, height: 1.5, color: Colors.blueGrey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, String title, String subtitle, String price, List<String> features, Color color, {bool isPremium = false, double priceValue = 0.0, int visits = 0}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: isPremium ? Border.all(color: color, width: 2) : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                    Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(price, style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: GoogleFonts.tajawal(fontSize: 14, color: Colors.blueGrey[700]))),
              ],
            ),
          )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ZyiarahContractSigningScreen(planName: title, planPrice: priceValue, planVisits: visits)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text('اطلب الان', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
