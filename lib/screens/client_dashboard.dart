import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/profile_screen.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/screens/hourly_details_screen.dart';
import 'package:zyiarah/screens/orders_list_screen.dart';
import 'package:zyiarah/screens/notifications_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  bool _isLoading = false;
  ZyiarahUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(user.uid, doc.data()!);
        });
      }
    }
  }

  void _initiatePayment(String serviceName, double amount) async {
    final GeoPoint? selectedLocation = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(serviceName: serviceName),
      ),
    );

    if (selectedLocation == null) {
      return; // المستخدم ألغى الاختيار
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSummaryScreen(
            serviceName: serviceName,
            amount: amount,
            location: selectedLocation,
          ),
        ),
      ).then((success) {
        if (success == true && mounted) {
          _loadUserData(); // Refresh data if payment was successful
        }
      });
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
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentUser?.hasActiveSubscription == true) _buildSubscriptionCard(),
                    const SizedBox(height: 10),
                    _buildMetricsList(),
                    const SizedBox(height: 25),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text('خدماتنا', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    _buildServicesGrid(),
                    const SizedBox(height: 25),
                    StreamBuilder<QuerySnapshot>(
                      stream: _getOrdersStream(),
                      builder: (context, snapshot) {
                        return _buildLatestBookings(snapshot.data?.docs ?? []);
                      },
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahProfileScreen()));
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFDBEAFE),
                  child: Text(
                    _currentUser?.name.isNotEmpty == true ? _currentUser!.name[0].toUpperCase() : 'Z',
                    style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Text(_currentUser?.name ?? 'مستخدم زيارة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                const SizedBox(width: 5),
                const Text('👋', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, size: 24),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen()));
                },
              ),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, size: 24),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFF9FAFB), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final int remaining = _currentUser?.visitsRemaining ?? 0;
    const int total = 4; // Assuming 4 visits per month for Gold
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
               Text(
                'الزيارات المتبقية لهذا الشهر', 
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)
              ),
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

  void _upgradeToSubscription() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'has_active_subscription': true,
        'visits_remaining': 4,
        'subscription_type': 'gold_monthly',
        'subscription_expiry': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      });
      await _loadUserData();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تفعيل اشتراك زيارة جولد بنجاح! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildMetricsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getUserStream(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final wallet = (userData?['wallet_balance'] ?? 0.0).toString();
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
                    cardColor: const Color(0xFF3B82F6), // Blue
                  ),
                  const SizedBox(width: 15),
                  _buildColorfulMetricCard(
                     title: 'رصيد المحفظة',
                     value: '$wallet ر.س',
                     iconPath: Icons.account_balance_wallet_rounded,
                     cardColor: const Color(0xFF10B981), // Green
                  ),
                  const SizedBox(width: 15),
                  _buildColorfulMetricCard(
                     title: 'تقييمك',
                     value: '$rating ★',
                     iconPath: Icons.star_border_rounded,
                     cardColor: const Color(0xFFF59E0B), // Yellow/Orange
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
  }) {
    return Container(
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
    );
  }

  Widget _buildServicesGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 0.75, // Taller cards to fit image
      children: [
        _buildWebStyleServiceCard(
          title: "خدمة بالساعة",
          subtitle: "عاملة منزلية بالساعة",
          price: "من 50 ر.س",
          numericPrice: 50.0,
          themeColor: const Color(0xFF10B981), // Green
          icon: Icons.access_time_filled,
          iconBgColor: const Color(0xFFE1F0E4), // Light Green
          imagePath: 'assets/images/hourly_cleaning.png',
        ),
        _buildWebStyleServiceCard(
          title: "تنظيف الكنب",
          subtitle: "تنظيف عميق بالبخار",
          price: "من 100 ر.س",
          numericPrice: 100.0,
          themeColor: const Color(0xFF8B5CF6), // Purple
          icon: Icons.chair,
          iconBgColor: const Color(0xFFF1E9FE), // Light Purple
        ),
        _buildWebStyleServiceCard(
          title: "سلة العائلة",
          subtitle: "باقات شهرية موفرة",
          price: "من 299 ر.س",
          numericPrice: 299.0,
          themeColor: const Color(0xFFF59E0B), // Orange
          icon: Icons.shopping_basket,
          iconBgColor: const Color(0xFFFEF3C7), // Light Orange
          imagePath: 'assets/images/monthly_cleaning.png',
        ),
        _buildWebStyleServiceCard(
          title: "خدمات الشركات",
          subtitle: "حلول تنظيف مخصصة",
          price: "عرض سعر",
          numericPrice: 0.0,
          themeColor: const Color(0xFF3B82F6), // Blue
          icon: Icons.business_center,
          iconBgColor: const Color(0xFFDBEAFE), // Light Blue
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
  }) {
    return Container(
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
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.2), // Yellow Badge
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (title == "خدمة بالساعة") {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const HourlyCleaningDetailsScreen(serviceName: "نظافة بالساعة"),
                              ),
                            );
                          } else if (title == "سلة العائلة") {
                            _upgradeToSubscription();
                          } else {
                            _initiatePayment(title, numericPrice);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB), // Dark or Primary Action
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestBookings(List<DocumentSnapshot> orders) {
    return Column(
      children: [
        Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Row(
               children: [
                 Icon(Icons.calendar_month, color: Colors.blue.shade800, size: 20),
                 const SizedBox(width: 8),
                 const Text('آخر الحجوزات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
               ],
             ),
             GestureDetector(
               onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen())),
               child: const Row(
                 children: [
                   Text('عرض الكل', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
                   Icon(Icons.chevron_right, color: Color(0xFF2563EB), size: 16),
                 ],
               ),
             ),
           ],
        ),
        const SizedBox(height: 15),
        if (orders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                Text('لا توجد حجوزات', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const SizedBox(height: 15),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  ),
                  child: const Text('احجز الآن', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                ),
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
      backgroundColor: const Color(0xFF0F172A), // Dark slate as in website layout
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
            const SizedBox(height: 20),
            _buildDrawerItem(Icons.language, 'English', false, onTap: () {}),
            _buildDrawerItem(Icons.wb_sunny_outlined, 'الوضع الداكن', false, onTap: () {}),
            const Spacer(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
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
