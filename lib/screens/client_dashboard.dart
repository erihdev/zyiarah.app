import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/screens/hourly_details_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';
import 'package:zyiarah/services/popup_service.dart';
import 'package:zyiarah/services/app_update_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/sofa_rug_details_screen.dart';
import 'package:zyiarah/screens/subscription_plans_screen.dart';
import 'package:zyiarah/screens/ac_service_details_screen.dart';
import 'package:zyiarah/screens/car_interior_details_screen.dart';
import 'package:zyiarah/screens/event_worker_packages_screen.dart';
import 'package:zyiarah/widgets/support_fab.dart';
import 'package:zyiarah/screens/client_notifications_screen.dart';

import 'package:provider/provider.dart';
import 'package:zyiarah/providers/user_provider.dart';
import 'package:zyiarah/providers/order_provider.dart';

// تحويل رقمي دفاعي: حقول Firestore قد تصل نصّاً ("150") أو null من لوحة الإدارة،

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int _selectedNavIndex = 0;
  final PageController _bannerController =
      PageController(viewportFraction: 0.95);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZyiarahPopupService.checkAndShowPopup(context);
      // إشعار توفّر تحديث للتطبيق (متحكَّم به من الإدارة، يظهر للنسخ القديمة فقط)
      ZyiarahAppUpdateService.checkAndPrompt(context);
    });
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    ZyiarahCoreService.triggerHapticLight();
    if (index == 0) {
      setState(() => _selectedNavIndex = 0);
    } else if (index == 1) {
      setState(() => _selectedNavIndex = 1);
      _openTab('/orders');
    } else if (index == 2) {
      setState(() => _selectedNavIndex = 2);
      _openTab('/store');
    } else if (index == 3) {
      setState(() => _selectedNavIndex = 3);
      _openTab('/offers');
    } else if (index == 4) {
      setState(() => _selectedNavIndex = 4);
      _openTab('/profile');
    }
  }

  /// عبر الراوتر لا Navigator: هذه الشاشات تستدعي context.go(...) بداخلها، ودفعها فوق
  /// المكدّس كان يجعل الراوتر يتغيّر تحتها وهي تبقى فوقه (فشل صامت). الانتقال يبقى
  /// كما هو — عُرِّف في lib/router.dart كـ CustomTransitionPage بالحركة نفسها.
  /// context.push يُرجع Future يكتمل عند الرجوع، تماماً كـ Navigator.push، فيبقى
  /// إرجاع مؤشّر التبويب للرئيسية سليماً.
  void _openTab(String location) {
    context.push(location).then((_) {
      if (mounted) setState(() => _selectedNavIndex = 0);
    });
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
                  color: const Color(0xFF660033),
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
                        _buildAnimatedItem(_buildSubscriptionCards(user?.uid)),
                        const SizedBox(height: 15),
                        _buildAnimatedItem(_buildSectionTitle(ZyiarahStrings.servicesHeader, Icons.auto_awesome, Colors.amber)),
                        const SizedBox(height: 15),
                        _buildAnimatedItem(_buildServicesGrid()),
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
      indicatorColor: const Color(0xFF660033).withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF660033)),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFF660033)),
          label: 'طلباتي',
        ),
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront_rounded, color: Color(0xFF660033)),
          label: 'المتجر',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_offer_outlined),
          selectedIcon: Icon(Icons.local_offer_rounded, color: Color(0xFF660033)),
          label: 'العروض',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: Color(0xFF660033)),
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
          .where('status', whereIn: ['assigned', 'scheduled', 'accepted', 'on_the_way', 'in_progress'])
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // اختر الأنسب: الطلبات الحيّة (في الطريق/جارية) أولاً، ثم الأقرب موعداً
        const liveRank = {'in_progress': 0, 'on_the_way': 1, 'accepted': 2, 'assigned': 3, 'scheduled': 4};
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final ad = a.data() as Map<String, dynamic>;
            final bd = b.data() as Map<String, dynamic>;
            final ar = liveRank[ad['status']] ?? 5;
            final br = liveRank[bd['status']] ?? 5;
            if (ar != br) return ar.compareTo(br);
            int ts(Map<String, dynamic> d) {
              final v = d['service_date'];
              return v is Timestamp ? v.millisecondsSinceEpoch : (1 << 62);
            }
            return ts(ad).compareTo(ts(bd));
          });

        final orderDoc = docs.first;
        final data = orderDoc.data() as Map<String, dynamic>;
        final String orderId = orderDoc.id;
        final String status = data['status'] ?? '';
        // نص دقيق لكل حالة — لا نقول "السائق في الطريق" لحجز مجدول مستقبلي
        String statusText;
        bool isLive; // هل السائق فعلاً في الطريق/يعمل الآن؟
        switch (status) {
          case 'in_progress':
            statusText = ZyiarahStrings.serviceInProgress;
            isLive = true;
            break;
          case 'on_the_way':
            statusText = ZyiarahStrings.driverOnWay;
            isLive = true;
            break;
          case 'accepted':
            statusText = ZyiarahStrings.orderAccepted;
            isLive = false;
            break;
          case 'assigned':
            statusText = ZyiarahStrings.driverAssigned;
            isLive = false;
            break;
          case 'scheduled':
          default:
            statusText = ZyiarahStrings.orderScheduled;
            isLive = false;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF660033), Color(0xFF8B3D8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: const Color(0xFF660033).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/track/$orderId'),
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
                          Text(isLive ? ZyiarahStrings.tapToTrackMap : ZyiarahStrings.tapToViewDetails, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
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
                      child: Text(isLive ? ZyiarahStrings.track : ZyiarahStrings.view, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
              color: const Color(0xFF660033),
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
      actions: [
        _NotifBell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClientNotificationsScreen()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // يعرض بطاقة مستقلّة لكل عقد اشتراك نشط (الشهرية + الأسبوعية معاً) — لا يُنسى أيٌّ منها.
  Widget _buildSubscriptionCards(String? uid) {
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      // فلترة userId فقط (حقل واحد، بلا فهرس مركّب)؛ نُصفّي الحالة محلياً.
      stream: FirebaseFirestore.instance
          .collection('contracts')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        // إزالة التكرار بمعرّف العقد ثم إبقاء العقود النشطة التي بقيت بها زيارات
        final Map<String, Map<String, dynamic>> unique = {};
        for (final d in snapshot.data!.docs) {
          final m = d.data() as Map<String, dynamic>;
          final key = (m['contractId'] ?? d.id).toString();
          final existing = unique[key];
          if (existing == null) {
            unique[key] = m;
            continue;
          }
          // عند تكرار المعرّف (تجديد): فضّل النشِط، ثم الأحدث — كي لا تُسقِط نسخةٌ
          // منتهيةٌ العقدَ النشط فتختفي بطاقة اشتراك فعّالة من الرئيسية.
          final bool mActive = m['status'] == 'active';
          final bool eActive = existing['status'] == 'active';
          if (mActive != eActive) {
            if (mActive) unique[key] = m;
            continue;
          }
          final mt = (m['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final et = (existing['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          if (mt > et) unique[key] = m;
        }
        final active = unique.values.where((m) {
          if (m['status'] != 'active') return false;
          final rem = (m['visits_remaining'] as num?)?.toInt();
          // عقود قديمة قبل العدّاد (rem == null) تظهر أيضاً
          return rem == null || rem > 0;
        }).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        return Column(
          children: active.map(_buildSubscriptionCard).toList(),
        );
      },
    );
  }

  Widget _buildSubscriptionCard(Map<String, dynamic> contract) {
    final int total = ((contract['visits_total'] ?? contract['planVisits']) as num?)?.toInt() ?? 4;
    final int remainingRaw = (contract['visits_remaining'] as num?)?.toInt() ?? total;
    final int remaining = remainingRaw.clamp(0, total); // يمنع عرض "6 / 4"
    final double progress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    final String planName = ((contract['planName'] as String?)?.trim().isNotEmpty ?? false)
        ? contract['planName'] as String
        : 'باقة اشتراك';
    final DateTime? expiry = (contract['expiry'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3D1040), Color(0xFF660033), Color(0xFF8B3D8C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF660033).withValues(alpha: 0.35),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Text('اشتراك فعّال', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
              Text('الزيارات المتبقية', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
              if (expiry != null)
                Text(
                  'ينتهي في: ${expiry.day}/${expiry.month}/${expiry.year}',
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
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // الرئيسية تعرض بانرات «الرئيسي» فقط؛ ما اختارت له الإدارة «قسم العروض»
        // يظهر في شاشة العروض. الغياب = رئيسي (توافق مع البانرات القائمة).
        // التصفية محلية: لا يمكن استعلام «الحقل غائب أو = main» في Firestore.
        final banners = snapshot.data!.docs.where((d) {
          final p = (d.data() as Map<String, dynamic>)['placement'];
          return p == null || p == 'main';
        }).toList();
        if (banners.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 160,
          margin: const EdgeInsets.only(bottom: 20),
          child: PageView.builder(
            itemCount: banners.length,
            controller: _bannerController,
            itemBuilder: (context, index) {
              final data = banners[index].data() as Map<String, dynamic>;
              final imageUrl = data['imageUrl'] ?? '';
              final String routeType = data['routeType'] ?? 'none';
              final String actionUrl = data['actionUrl'] ?? '';
              
              return GestureDetector(
                onTap: () async {
                  if (routeType == 'whatsapp' && actionUrl.isNotEmpty) {
                    final uri = Uri.parse(actionUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تعذّر فتح الرابط')),
                      );
                    }
                  } else if (routeType == '/hourly_cleaning') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HourlyCleaningDetailsScreen(serviceName: "تنظيف منزلي")));
                  } else if (routeType == '/store') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahStoreScreen()));
                  } else if (routeType == '/support') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()));
                  } else if (routeType == '/sofa_cleaning' || routeType == '/rug_cleaning') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SofaRugCleaningDetailsScreen(serviceName: "تنظيف الكنب والزل")));
                  } else if (routeType == '/ac' || routeType == '/ac_service') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AcServiceDetailsScreen()));
                  } else if (routeType == '/subscriptions') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSubscriptionPlansScreen()));
                  } else if (routeType != 'none' && routeType.isNotEmpty && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('هذا الرابط غير متاح حالياً')),
                    );
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
                      // سقف فك الترميز بعرض الشاشة: البنرات تُرفع بدقة الكاميرا الكاملة
                      // وفكّها كاملةً لخانة 160px يستهلك عشرات الميغابايت ويقطّع التمرير.
                      memCacheWidth: (MediaQuery.of(context).size.width *
                              MediaQuery.of(context).devicePixelRatio)
                          .round(),
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
        // (باقات السكن) البطاقة تعكس المنتج الجديد: باقة بنوع السكن وعدد الكوادر —
        // لا ساعات ولا «من 50 ر.س» التي لم تعد تطابق أي سعر خلف الضغطة.
        _buildWebStyleServiceCard(
          title: "تنظيف منزلي",
          subtitle: "باقة حسب نوع سكنك وعدد الكوادر",
          price: "حسب الباقة",
          numericPrice: 50.0,
          themeColor: const Color(0xFF10B981),
          icon: Icons.access_time_filled,
          iconBgColor: const Color(0xFFE1F0E4),
          imagePath: 'assets/images/hourly_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HourlyCleaningDetailsScreen(serviceName: "تنظيف منزلي"))),
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
          subtitle: "شباك أو سبليت",
          price: "سعر لكل مكيف",
          numericPrice: 0.0,
          themeColor: const Color(0xFF475569),
          icon: Icons.ac_unit_rounded,
          iconBgColor: const Color(0xFFF1F5F9),
          imagePath: 'assets/images/company_cleaning.png',
          // صارت طلباً مباشراً مسعّراً بدل طلب عرض سعر ينتظر تسعير الإدارة.
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AcServiceDetailsScreen())),
        ),
        _buildWebStyleServiceCard(
          title: "تنظيف داخلية السيارة",
          subtitle: "مراتب وأسقف السيارة",
          price: "حسب حجم السيارة",
          numericPrice: 0.0,
          themeColor: const Color(0xFF0E7490),
          icon: Icons.directions_car_filled_rounded,
          iconBgColor: const Color(0xFFE0F2FE),
          imagePath: 'assets/images/car_cleaning.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarInteriorDetailsScreen())),
        ),
        _buildWebStyleServiceCard(
          title: "عاملات للمناسبات",
          subtitle: "باقات جاهزة بأسعار ثابتة",
          price: "باقات مسبقة الإعداد",
          numericPrice: 0.0,
          themeColor: const Color(0xFF9333EA),
          icon: Icons.celebration_rounded,
          iconBgColor: const Color(0xFFF3E8FF),
          imagePath: 'assets/images/cleaning_hero.png',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventWorkerPackagesScreen())),
        ),
        _buildWebStyleServiceCard(
          title: "متجر المنظفات",
          subtitle: "أدوات احترافية",
          price: "عروض حصرية",
          numericPrice: 0.0,
          themeColor: const Color(0xFF660033),
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
                  // فك الترميز بارتفاع وجهة الـ Hero (220px) بدل الأصل 640-1024px:
                  // يقلّص ذاكرة الصور ~10x ويُبقي انتقال Hero حاداً في شاشة التفاصيل.
                  cacheHeight:
                      (220 * MediaQuery.of(context).devicePixelRatio).round(),
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

class _NotifBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotifBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.notifications_outlined, color: Color(0xFF0F172A)),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        // غير المقروء = لا isRead ولا is_read = true (يوحّد مع شاشة الإشعارات)
        final hasUnread = (snapshot.data?.docs ?? []).any((d) {
          final m = d.data() as Map<String, dynamic>;
          return m['isRead'] != true && m['is_read'] != true;
        });
        return Stack(
          children: [
            IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.notifications_outlined, color: Color(0xFF0F172A)),
            ),
            if (hasUnread)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF660033),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
