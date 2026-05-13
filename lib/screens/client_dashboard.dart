import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
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
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/maintenance_listener_service.dart';
import 'package:zyiarah/widgets/support_fab.dart';

import 'package:provider/provider.dart';
import 'package:zyiarah/providers/user_provider.dart';
import 'package:zyiarah/providers/order_provider.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    MaintenanceListenerService().startListening();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZyiarahPopupService.checkAndShowPopup(context);
    });
  }

  void _onNavTap(int index) {
    ZyiarahCoreService.triggerHapticLight();
    if (index == 0) {
      setState(() => _selectedNavIndex = 0);
    } else if (index == 1) {
      setState(() => _selectedNavIndex = 1);
      Navigator.push(context, _pageRoute(const OrdersListScreen())).then((_) {
        if (mounted) setState(() => _selectedNavIndex = 0);
      });
    } else if (index == 2) {
      setState(() => _selectedNavIndex = 2);
      Navigator.push(context, _pageRoute(const ZyiarahStoreScreen())).then((_) {
        if (mounted) setState(() => _selectedNavIndex = 0);
      });
    } else if (index == 3) {
      setState(() => _selectedNavIndex = 3);
      Navigator.push(context, _pageRoute(const ZyiarahProfileScreen())).then((_) {
        if (mounted) setState(() => _selectedNavIndex = 0);
      });
    }
  }

  PageRouteBuilder _pageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<ZyiarahUserProvider>(context);
    final orderProvider = Provider.of<ZyiarahOrderProvider>(context);
    final user = userProvider.user;
    final isLoading = userProvider.isLoading || orderProvider.isLoading;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: _buildTopBar(),
        floatingActionButton: const ZyiarahSupportFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: _buildNavBar(),
        body: SafeArea(
          child: isLoading
              ? _buildShimmerLoading()
              : RefreshIndicator(
                  color: const Color(0xFF5D1B5E),
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 600));
                    if (mounted) setState(() {});
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildActiveTrackingCard(user?.uid),
                        _buildAnimatedItem(_buildPromoBanners()),
                        _buildMaintenanceAlertCard(user?.uid),
                        if (user?.hasActiveSubscription == true) _buildAnimatedItem(_buildSubscriptionCard(user!)),
                        const SizedBox(height: 10),
                        _buildAnimatedItem(_buildMetricsList(user?.uid)),
                        const SizedBox(height: 25),
                        _buildAnimatedItem(_buildSectionTitle(ZyiarahStrings.servicesHeader, Icons.auto_awesome, Colors.amber)),
                        const SizedBox(height: 15),
                        _buildAnimatedItem(_buildServicesGrid()),
                        const SizedBox(height: 25),
                        _buildAnimatedItem(_buildSectionTitle(ZyiarahStrings.latestBookings, Icons.calendar_month, const Color(0xFF5D1B5E))),
                        const SizedBox(height: 15),
                        _buildAnimatedItem(_buildLatestBookings(orderProvider.activeOrders.take(5).toList())),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return NavigationBar(
      selectedIndex: _selectedNavIndex,
      onDestinationSelected: _onNavTap,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      elevation: 8,
      indicatorColor: const Color(0xFF5D1B5E).withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF5D1B5E)),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFF5D1B5E)),
          label: 'طلباتي',
        ),
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront_rounded, color: Color(0xFF5D1B5E)),
          label: 'المتجر',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: Color(0xFF5D1B5E)),
          label: 'حسابي',
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner skeleton
            Container(height: 160, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
            const SizedBox(height: 20),
            // Metric cards row skeleton
            Row(children: [
              Expanded(child: Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)))),
              const SizedBox(width: 15),
              Expanded(child: Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)))),
            ]),
            const SizedBox(height: 25),
            // Section title skeleton
            Container(height: 24, width: 140, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 15),
            // Service cards grid skeleton
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 0.75,
              children: List.generate(4, (_) => Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              )),
            ),
            const SizedBox(height: 25),
            // Orders skeleton
            Container(height: 24, width: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 15),
            ...List.generate(3, (_) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 68,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTrackingCard(String? uid) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('client_id', isEqualTo: uid)
          .where('status', whereIn: ['accepted', 'in_progress'])
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
        if (status == 'in_progress') statusText = ZyiarahStrings.serviceInProgress;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5D1B5E), Color(0xFF8B3D8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: const Color(0xFF5D1B5E).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId))),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.cleaning_services, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(ZyiarahStrings.tapToTrackMap, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(ZyiarahStrings.track, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaintenanceAlertCard(String? uid) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_requests')
          .where('userId', isEqualTo: uid)
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentSummaryScreen(
                          serviceName: serviceType,
                          amount: price,
                          maintenanceId: reqDoc.id,
                          location: data['location'] is GeoPoint ? data['location'] : null,
                        ),
                      ),
                    );
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
      backgroundColor: Colors.white.withValues(alpha: 0.85),
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(color: Colors.transparent),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF5D1B5E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.maps_home_work_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('زيارة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
              Text('بوابة العميل', style: TextStyle(fontWeight: FontWeight.w400, fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(ZyiarahUser user) {
    final int remaining = user.visitsRemaining;
    final int total = user.subscriptionTotalVisits > 0 ? user.subscriptionTotalVisits : 4;
    final double progress = (remaining / total).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3D1040), Color(0xFF5D1B5E), Color(0xFF8B3D8C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5D1B5E).withValues(alpha: 0.35),
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
              if (user.subscriptionExpiry != null)
                Text(
                  'التجديد في: ${user.subscriptionExpiry!.day}/${user.subscriptionExpiry!.month}',
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

  Widget _buildMetricsList(String? uid) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final rating = (userData?['rating'] ?? 4.9).toString();
        final orderProvider = Provider.of<ZyiarahOrderProvider>(context, listen: false);
        final totalBookings = orderProvider.recentOrders.length.toString();

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 500 ? 3 : 2;
        final ratio = constraints.maxWidth > 500 ? 0.85 : 0.75;
        return _buildGrid(cols, ratio);
      },
    );
  }

  Widget _buildGrid(int crossAxisCount, double childAspectRatio) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: childAspectRatio,
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
          subtitle: "أدوات احترافية",
          price: "عروض حصرية",
          numericPrice: 0.0,
          themeColor: const Color(0xFF5D1B5E),
          icon: Icons.storefront,
          iconBgColor: const Color(0xFFFCEEFA),
          imagePath: 'assets/images/store.png',
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
      onTap: () {
        ZyiarahCoreService.triggerHapticLight();
        onTap?.call();
      },
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
            Hero(
              tag: 'svc-$imagePath',
              child: ClipRRect(
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
                ),
              ),
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
                          color: themeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 14),
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
            final isCompleted = status == 'completed';
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen())),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5D1B5E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF5D1B5E), size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['service_type'] ?? 'خدمة زيارة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                          const SizedBox(height: 2),
                          Text(
                            isCompleted ? 'تم التنفيذ ✓' : 'قيد المعالجة',
                            style: TextStyle(
                              color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left_rounded, color: Color(0xFFCBD5E1), size: 20),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }


  Widget _buildAnimatedItem(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
