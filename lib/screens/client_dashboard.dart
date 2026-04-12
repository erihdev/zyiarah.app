import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/profile_screen.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/screens/hourly_details_screen.dart';
import 'package:zyiarah/screens/orders_list_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/popup_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/sofa_rug_details_screen.dart';
import 'package:zyiarah/screens/subscription_plans_screen.dart';
import 'package:zyiarah/screens/maintenance_request_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/services/maintenance_listener_service.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  bool _isLoading = true;
  ZyiarahUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    MaintenanceListenerService().startListening();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZyiarahPopupService.checkAndShowPopup(context);
    });
  }

  Stream<DocumentSnapshot> _getUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  Stream<QuerySnapshot> _getOrdersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('orders')
        .where('client_id', isEqualTo: user.uid)
        .orderBy('created_at', descending: true)
        .limit(5)
        .snapshots();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(user.uid, doc.data()!);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: _buildTopBar(),
        drawer: _buildDrawer(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActiveTrackingCard(),
                _buildPromoBanners(),
                _buildMaintenanceAlertCard(),
                if (_currentUser?.hasActiveSubscription == true) _buildSubscriptionCard(),
                const SizedBox(height: 10),
                _buildMetricsList(),
                const SizedBox(height: 25),
                _buildSectionTitle(ZyiarahStrings.servicesHeader, Icons.auto_awesome, Colors.amber),
                const SizedBox(height: 15),
                _isLoading ? _buildShimmerGrid() : _buildServicesGrid(),
                const SizedBox(height: 25),
                _buildSectionTitle(ZyiarahStrings.latestBookings, Icons.calendar_month, Colors.blue.shade800),
                const SizedBox(height: 15),
                _isLoading 
                  ? _buildShimmerList()
                  : StreamBuilder<QuerySnapshot>(
                    stream: _getOrdersStream(),
                    builder: (context, snapshot) {
                      return _buildLatestBookings(snapshot.data?.docs ?? []);
                    },
                  ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 15,
        crossAxisSpacing: 15,
        childAspectRatio: 0.75,
        children: List.generate(4, (index) => Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        )),
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: List.generate(3, (index) => Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        )),
      ),
    );
  }

  Widget _buildActiveTrackingCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('client_id', isEqualTo: user.uid)
          .where('status', whereIn: ['accepted', 'arrived', 'in_progress'])
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final orderDoc = snapshot.data!.docs.first;
        final data = orderDoc.data() as Map<String, dynamic>;
        final String orderId = orderDoc.id;
        final String status = data['status'] ?? '';
        String statusText = ZyiarahStrings.driverOnWay;
        if (status == 'arrived') statusText = ZyiarahStrings.driverArrived;
        if (status == 'in_progress') statusText = ZyiarahStrings.serviceInProgress;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.shade100, width: 2),
            boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.cleaning_services, color: Colors.blue),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(ZyiarahStrings.tapToTrackMap, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                   Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId)));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(ZyiarahStrings.track, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaintenanceAlertCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_requests')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'waiting_payment')
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final reqDoc = snapshot.data!.docs.first;
        final data = reqDoc.data() as Map<String, dynamic>;
        final String serviceType = data['serviceType'] ?? 'صيانة';
        final double price = (data['quotePrice'] ?? 0.0).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.orange.shade200, width: 2),
            boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.receipt_long, color: Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Text(ZyiarahStrings.waitingPayment, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.orange, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "تم تحديد تكلفة خدمة ($serviceType) بمبلغ $price ر.س. يرجى إتمام الدفع لبدء التنفيذ.",
                style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF431407)),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(ZyiarahStrings.viewAndPayNow, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.7),
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(color: Colors.transparent),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(ZyiarahStrings.portalSubtitle, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF64748B))),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final int remaining = _currentUser?.visitsRemaining ?? 0;
    const int total = 4;
    final double progress = remaining / total;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('زيارة جولد (الذهبية)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('اشتراك فعّال', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              Text('$remaining / $total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الزيارات المتبقية لهذا الشهر', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
              if (_currentUser?.subscriptionExpiry != null)
                Text(
                  'التجديد في: ${_currentUser!.subscriptionExpiry!.day}/${_currentUser!.subscriptionExpiry!.month}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanners() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('promo_banners')
          .where('isActive', isEqualTo: true)
          .orderBy('rank')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final banners = snapshot.data!.docs;

        return Container(
          height: 160,
          margin: const EdgeInsets.only(bottom: 20),
          child: PageView.builder(
            itemCount: banners.length,
            controller: PageController(viewportFraction: 0.95),
            itemBuilder: (context, index) {
              final data = banners[index].data() as Map<String, dynamic>;
              final imageUrl = data['imageUrl'] ?? '';
              final String routeType = data['routeType'] ?? 'none';
              final String actionUrl = data['actionUrl'] ?? '';
              
              return GestureDetector(
                onTap: () async {
                  if (routeType == 'whatsapp' && actionUrl.isNotEmpty) {
                    final uri = Uri.parse(actionUrl);
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  } else if (routeType == '/hourly_cleaning') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HourlyCleaningDetailsScreen(serviceName: "نظافة بالساعة")));
                  } else if (routeType == '/store') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahStoreScreen()));
                  } else if (routeType == '/support') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()));
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMetricsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getUserStream(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final rating = (userData?['rating'] ?? 4.9).toString();

        return StreamBuilder<QuerySnapshot>(
          stream: _getOrdersStream(),
          builder: (context, orderSnapshot) {
            final totalBookings = (orderSnapshot.data?.docs.length ?? 0).toString();

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  _buildColorfulMetricCard(
                    title: 'إجمالي الحجوزات',
                    value: totalBookings,
                    iconPath: Icons.calendar_today_rounded,
                    cardColor: const Color(0xFF3B82F6),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen())),
                  ),
                  const SizedBox(width: 15),
                  _buildColorfulMetricCard(
                     title: 'تقييمك',
                     value: '$rating ★',
                     iconPath: Icons.star_border_rounded,
                     cardColor: const Color(0xFFF59E0B),
                     onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahProfileScreen())),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildColorfulMetricCard({
    required String title,
    required String value,
    required IconData iconPath,
    required Color cardColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(iconPath, color: cardColor, size: 28),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildServicesGrid() {
    return _buildDefaultStaticGrid();
  }

  Widget _buildDefaultStaticGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 0.75,
      children: [
        _buildWebStyleServiceCard(
          title: "خدمة بالساعة",
          subtitle: "عاملة منزلية بالساعة",
          price: "من 50 ر.س",
          numericPrice: 50.0,
          themeColor: const Color(0xFF10B981),
          icon: Icons.access_time_filled,
          iconBgColor: const Color(0xFFE1F0E4),
          imagePath: 'assets/images/hourly_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HourlyCleaningDetailsScreen(serviceName: "نظافة بالساعة"))),
        ),
        _buildWebStyleServiceCard(
          title: "تنظيف الكنب والزل",
          subtitle: "تنظيف عميق بالبخار",
          price: "حسب المتر",
          numericPrice: 0.0,
          themeColor: const Color(0xFF8B5CF6),
          icon: Icons.chair,
          iconBgColor: const Color(0xFFF1E9FE),
          imagePath: 'assets/images/sofa_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SofaRugCleaningDetailsScreen(serviceName: "تنظيف الكنب والزل"))),
        ),
        _buildWebStyleServiceCard(
          title: "باقات الإشتراك",
          subtitle: "زيارات مجدولة",
          price: "باقات شهرية",
          numericPrice: 0.0,
          themeColor: const Color(0xFF10B981),
          icon: Icons.workspace_premium,
          iconBgColor: const Color(0xFFE1F0E4),
          imagePath: 'assets/images/monthly_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSubscriptionPlansScreen())),
        ),
        _buildWebStyleServiceCard(
          title: "صيانة وغسيل المكيفات",
          subtitle: "تنظيف وصيانة شاملة",
          price: "حسب الطلب",
          numericPrice: 0.0,
          themeColor: const Color(0xFF475569),
          icon: Icons.handyman,
          iconBgColor: const Color(0xFFF1F5F9),
          imagePath: 'assets/images/company_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahMaintenanceRequestScreen())),
        ),
        _buildWebStyleServiceCard(
          title: "متجر المنظفات",
          subtitle: "سويفت كلين",
          price: "عروض حصرية",
          numericPrice: 0.0,
          themeColor: const Color(0xFF5D1B5E),
          icon: Icons.storefront,
          iconBgColor: const Color(0xFFFCEEFA),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahStoreScreen())),
        ),
      ],
    );
  }

  Widget _buildWebStyleServiceCard({
    required String title,
    required String subtitle,
    required String price,
    required double numericPrice,
    required Color themeColor,
    required IconData icon,
    required Color iconBgColor,
    String? imagePath,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
           BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imagePath != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Image.asset(
                imagePath,
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 90,
                  width: double.infinity,
                  color: iconBgColor,
                  child: Icon(icon, color: themeColor, size: 40),
                ),
              )
            )
          else
            Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Center(child: Icon(icon, color: themeColor, size: 40)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildLatestBookings(List<DocumentSnapshot> orders) {
    return Column(
      children: [
        if (orders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                Lottie.network(
                  'https://lottie.host/9972352b-4780-4545-8f65-021199346747/XJzQitkR2f.json', // Search/Empty anim
                  height: 150,
                ),
                const SizedBox(height: 10),
                Text(ZyiarahStrings.noBookings, style: GoogleFonts.tajawal(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        else
          ...orders.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'pending';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.cleaning_services, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['service_type'] ?? 'خدمة زيارة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(status == 'completed' ? 'تم التنفيذ' : 'تحت المعالجة', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left, color: Colors.grey),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const Icon(Icons.maps_home_work, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  const Text('زيارة', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  IconButton(
                     onPressed: ()=> Navigator.pop(context),
                     icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
                  )
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildDrawerItem(Icons.home_outlined, 'الرئيسية', true, onTap: () => Navigator.pop(context)),
            _buildDrawerItem(Icons.person_outline, 'الملف الشخصي', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahProfileScreen()));
            }),
            _buildDrawerItem(Icons.calendar_today_outlined, 'حجوزاتي', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen()));
            }),
            _buildDrawerItem(Icons.inventory_2_outlined, 'الطلبات', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen()));
            }),
            _buildDrawerItem(Icons.support_agent, 'الدعم الفني', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahSupportScreen()));
            }),
            _buildDrawerItem(Icons.description_outlined, 'عقودي الإلكتـرونية', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahContractsListScreen()));
            }),
            const Spacer(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.of(context).pushReplacementNamed('/');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, bool isActive, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isActive ? Colors.white : Colors.transparent,
        leading: Icon(icon, color: isActive ? const Color(0xFF2563EB) : Colors.white),
        title: Text(
          title, 
          style: TextStyle(
            color: isActive ? const Color(0xFF2563EB) : Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
