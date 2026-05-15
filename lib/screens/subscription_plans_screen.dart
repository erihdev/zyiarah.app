import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:zyiarah/screens/contract_signing_screen.dart';

class ZyiarahSubscriptionPlansScreen extends StatefulWidget {
  const ZyiarahSubscriptionPlansScreen({super.key});

  @override
  State<ZyiarahSubscriptionPlansScreen> createState() =>
      _ZyiarahSubscriptionPlansScreenState();
}

class _ZyiarahSubscriptionPlansScreenState
    extends State<ZyiarahSubscriptionPlansScreen> {
  static const Color _brand = Color(0xFF5D1B5E);
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
      final snapshot = await _db.collection('subscription_packages').get();
      if (mounted) {
        final docs = snapshot.docs;
        docs.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aRank = (aData['rank'] ?? 999) as num;
          final bRank = (bData['rank'] ?? 999) as num;
          return aRank.compareTo(bRank);
        });
        setState(() {
          _packages = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('SUBSCRIPTION_FETCH_ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F0F7),
        appBar: AppBar(
          title: Text('سلة العائلة (الاشتراكات)',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _isLoading ? _buildShimmer() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 16),
          ...List.generate(3, (_) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 220,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          )),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoBanner(),
          const SizedBox(height: 20),
          if (_packages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('لا توجد باقات متاحة حالياً',
                        style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ..._packages.asMap().entries.map((entry) {
            final i = entry.key;
            final doc = entry.value;
            final data = doc.data() as Map<String, dynamic>;
            final features = (data['features'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final isPremium = data['isPremium'] == true;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildPlanCard(
                context,
                index: i,
                title: data['title'] ?? 'باقة اشتراك',
                subtitle: data['subtitle'] ?? '',
                price: '${data['price']} ر.س',
                features: features,
                isPremium: isPremium,
                priceValue: (data['price'] ?? 0).toDouble(),
                visits: (data['visits'] ?? 0).toInt(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brand.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded, color: _brand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'اختر الباقة المناسبة لعائلتك. سيتم توجيه طلبك للإدارة للموافقة عليه قبل توقيع العقد الإلكتروني.',
              style: GoogleFonts.tajawal(fontSize: 13, height: 1.5, color: Colors.blueGrey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required String price,
    required List<String> features,
    required bool isPremium,
    required double priceValue,
    required int visits,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isPremium
            ? Border.all(color: _brand, width: 2)
            : Border.all(color: const Color(0xFFE8E0ED)),
        boxShadow: [
          BoxShadow(
            color: isPremium
                ? _brand.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: isPremium ? 20 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPremium
                    ? [const Color(0xFF3D1040), _brand]
                    : [_brand.withValues(alpha: 0.08), _brand.withValues(alpha: 0.04)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.tajawal(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isPremium ? Colors.white : _brand,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: isPremium ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.tajawal(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isPremium ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (isPremium)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade400,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'الأكثر طلباً',
                          style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Features
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded, color: _brand, size: 14),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(f, style: GoogleFonts.tajawal(fontSize: 14, color: Colors.blueGrey[700])),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ZyiarahContractSigningScreen(
                            planName: title,
                            planPrice: priceValue,
                            planVisits: visits,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      'اطلب الآن',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
