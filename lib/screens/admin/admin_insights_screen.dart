import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/admin/admin_compliance_screen.dart';
import 'package:zyiarah/screens/admin/admin_staff_performance_screen.dart';
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_contracts_screen.dart';

class AdminInsightsScreen extends StatefulWidget {
  // الدور يصل من AdminDashboardScreen (مطبَّع: admin→super_admin) — نحتاجه لتخطي
  // استعلام store_orders الذي تحصره القواعد في مديري الطلبات.
  final String role;
  const AdminInsightsScreen({super.key, required this.role});

  @override
  State<AdminInsightsScreen> createState() => _AdminInsightsScreenState();
}

class _AdminInsightsScreenState extends State<AdminInsightsScreen> {
  List<DocumentSnapshot> _orders = [];
  List<DocumentSnapshot> _maintenance = [];
  List<DocumentSnapshot> _drivers = [];
  List<DocumentSnapshot> _storeOrders = [];
  int _userCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final db = FirebaseFirestore.instance;
    // عزل كل استعلام بخطئه الخاص: رفضُ مجموعةٍ واحدة كان يُسقط أول await فتُهمل
    // نتائج الباقي وتُعرض لوحة مصفّرة بالكامل بلا أي تنبيه (تبدو كحالة فارغة حقيقية).
    Object? firstError;
    Future<T?> guarded<T>(Future<T> f) => f.then<T?>((v) => v, onError: (Object e) {
          firstError ??= e;
          return null;
        });
    // قراءة store_orders محصورة في القواعد بمالك الطلب أو isOrdersManager — نتخطاها
    // للمحاسب/التسويق بدل استعلامٍ محكومٍ عليه بـ permission-denied.
    final canReadStore = ['admin', 'super_admin', 'orders_manager'].contains(widget.role);
    try {
      // Fire all requests in parallel; limit keeps memory and cost bounded.
      // (خدمة الصيانة حُذفت من الجذور — لم نعد نجلب maintenance_requests: بقاياها
      // اليتيمتان under_review كانتا تُضخّمان «طلبات نشطة» وترسمان شريحة «صيانة»
      // وهمية للأبد. القائمة تبقى فارغة فتصفر كل مشتقاتها تلقائياً.)
      final ordersF     = guarded(db.collection('orders').orderBy('created_at', descending: true).limit(500).get());
      // عملاء فقط: مجموعة users تضمّ سائقين وإداريين (يُكتبون فيها أيضاً)، فعدّها كاملةً
      // كان يضخّم «إجمالي العملاء». (حسابات العملاء تُكتب بـ role='client'.)
      final usersF      = guarded(db.collection('users').where('role', isEqualTo: 'client').count().get());
      final driversF    = guarded(db.collection('drivers').limit(200).get());
      final storeF      = canReadStore
          ? guarded(db.collection('store_orders').orderBy('created_at', descending: true).limit(500).get())
          : Future<QuerySnapshot<Map<String, dynamic>>?>.value(null);

      final ordersSnap      = await ordersF;
      final usersSnap       = await usersF;
      final driversSnap     = await driversF;
      final storeSnap       = await storeF;

      if (!mounted) return;
      setState(() {
        // عند فشل استعلامٍ نُبقي بياناته السابقة (مهم في السحب للتحديث) بدل تصفيرها.
        _orders      = ordersSnap?.docs ?? _orders;
        _maintenance = [];
        _userCount   = usersSnap?.count ?? _userCount;
        _drivers     = driversSnap?.docs ?? _drivers;
        _storeOrders = storeSnap?.docs ?? _storeOrders;
        _isLoading   = false;
      });
      if (firstError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تحميل بعض بيانات اللوحة: $firstError'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      // ضمان عدم بقاء المؤشر عالقاً مهما كان مسار الفشل.
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)));
    }

    final stats = _calculateStats(_orders, _maintenance, _storeOrders);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: RefreshIndicator(
          onRefresh: _fetchData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLivePulseSection(),
                const SizedBox(height: 15),
                _buildReputationSentinel(),
                const SizedBox(height: 20),
                _buildSectionTitle("نظرة سريعة"),
                const SizedBox(height: 15),
                _buildQuickStats(stats),
                const SizedBox(height: 30),
                
                _buildChartCard(
                  title: "نمو الإيرادات (آخر 7 أيام)",
                  subtitle: "إجمالي الدخل اليومي لجميع الخدمات",
                  child: _buildRevenueLineChart(_orders, _maintenance),
                ),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildChartCard(
                        title: "توزيع الخدمات",
                        subtitle: "نسب الطلبات حسب النوع",
                        height: 300,
                        child: _buildServicePieChart(_orders, _maintenance),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildChartCard(
                        title: "حالة العمليات",
                        subtitle: "تحليل كفاءة الإنجاز",
                        height: 300,
                        child: _buildStatusStatusBarChart(_orders, _maintenance),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // (دمج من لوحة الويب — Accountants) لوحة مالية مصغّرة: صافي الإيراد
                // بعد الضريبة + توزيع طرق الدفع بعدد المعاملات ومبالغها.
                _buildFinanceCard(stats),
                const SizedBox(height: 20),
                _buildRecentActivityList(_orders, _maintenance),
                const SizedBox(height: 20),
                _buildSystemHealthSection(_drivers),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _calculateStats(List<DocumentSnapshot> orders, List<DocumentSnapshot> maintenance, List<DocumentSnapshot> storeOrders) {
    // تحويل آمن: بعض المبالغ مخزّنة كنص → الجمع المباشر (double += String) ينهار.
    double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
    double cleaningRevenue = 0;
    double maintenanceRevenue = 0;
    double storeRevenue = 0;
    int activeOrders = 0;

    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'pending';
      if (status != 'cancelled') {
        final amount = d(data['final_amount'] ?? data['amount']);
        // طلبات متجر الأدوات والتنظيف تعيش الآن في `orders` (صارت مجدولة كالخدمات)
        // لكنها مبيعات متجر — ننسبها لإيراد المتجر لا التنظيف كي تبقى بطاقة «إيرادات
        // المتجر» دقيقة ولا يتضخّم إيراد التنظيف. (متجر الشركات ما زال في store_orders.)
        final meta = data['service_meta'];
        final bool isStore = meta is Map && meta['kind'] == 'store_products';
        if (isStore) {
          storeRevenue += amount;
        } else {
          cleaningRevenue += amount;
        }
      }
      if (status == 'pending' || status == 'assigned' || status == 'in_progress') {
        activeOrders++;
      }
    }

    for (var doc in maintenance) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'pending';
      if (status == 'paid' || status == 'completed' || status == 'approved') {
        maintenanceRevenue += d(data['quotePrice']);
      }
      if (status == 'under_review' || status == 'waiting_payment' || status == 'approved') {
        activeOrders++;
      }
    }

    for (var doc in storeOrders) {
      final data = doc.data() as Map<String, dynamic>;
      final sStatus = data['status'];
      // الإيراد للمدفوع فقط: كان يجمع كل الطلبات (بما فيها pending/awaiting/rejected)
      // فيُضخّم إيراد المتجر. نعتمد is_paid أو حالات ما بعد الدفع، ونفضّل final_amount.
      final bool storePaid = data['is_paid'] == true ||
          ['processing', 'shipped', 'delivered', 'completed', 'approved'].contains(sStatus);
      if (storePaid) {
        storeRevenue += d(data['final_amount'] ?? data['total_amount'] ?? data['total_price']);
      }
      if (sStatus == 'pending' || sStatus == 'processing') {
        activeOrders++;
      }
    }

    final double totalRevenue = cleaningRevenue + maintenanceRevenue + storeRevenue;
    // VAT in KSA is 15% inclusive. Tax = Total - (Total / 1.15)
    final double vatLiability = totalRevenue - (totalRevenue / 1.15);

    // (دمج من لوحة الويب) نمو شهري: الشهر التقويمي الحالي مقابل السابق، من نفس
    // العيّنة المجلوبة (آخر 500) — حدّها حدّ بقية الإحصاءات هنا، لا استعلامات إضافية.
    final now = DateTime.now();
    final curStart = DateTime(now.year, now.month, 1);
    final prevStart = DateTime(now.year, now.month - 1, 1);
    DateTime? createdOf(Map<String, dynamic> data) {
      final v = data['created_at'];
      return v is Timestamp ? v.toDate() : null;
    }

    double revCur = 0, revPrev = 0;
    int ordCur = 0, ordPrev = 0;
    void tally(Iterable<DocumentSnapshot> docs, {required bool store}) {
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        if ((data['status'] ?? '') == 'cancelled') continue;
        final t = createdOf(data);
        if (t == null || t.isBefore(prevStart)) continue;
        final amount = d(store
            ? (data['final_amount'] ?? data['total_amount'] ?? data['total_price'])
            : (data['final_amount'] ?? data['amount']));
        if (t.isBefore(curStart)) {
          revPrev += amount;
          ordPrev++;
        } else {
          revCur += amount;
          ordCur++;
        }
      }
    }

    tally(orders, store: false);
    tally(storeOrders, store: true);
    // null = لا أساس للمقارنة (شهر سابق فارغ) — البطاقة تُخفي الشارة بدل «∞%».
    double? growth(num cur, num prev) =>
        prev <= 0 ? null : (cur - prev) / prev * 100;

    return {
      'revenue': totalRevenue,
      'vat': vatLiability,
      'cleaning': cleaningRevenue,
      'maintenance': maintenanceRevenue,
      'store': storeRevenue,
      'active': activeOrders,
      'users': _userCount,
      'revenueGrowth': growth(revCur, revPrev),
      'ordersGrowth': growth(ordCur, ordPrev),
    };
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)));
  }

  Widget _buildQuickStats(Map<String, dynamic> stats) {
    return Column(
      children: [
        SizedBox(
          height: 124,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildStatCard("إجمالي الإيرادات", "${stats['revenue'].toStringAsFixed(0)} ر.س", const Color(0xFF059669), Icons.account_balance_wallet_rounded, growth: stats['revenueGrowth']),
              _buildStatCard("الوعاء الضريبي (VAT)", "${stats['vat'].toStringAsFixed(0)} ر.س", const Color(0xFFD97706), Icons.account_balance_rounded),
              _buildStatCard("طلبات نشطة", stats['active'].toString(), const Color(0xFF2563EB), Icons.speed_rounded, growth: stats['ordersGrowth']),
              _buildStatCard("إجمالي العملاء", stats['users'].toString(), const Color(0xFF7C3AED), Icons.people_alt_rounded),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniRevenue("تنظيف", stats['cleaning'], Colors.blue),
              _buildMiniRevenue("متجر", stats['store'], Colors.teal),
              _buildMiniRevenue("صيانة", stats['maintenance'], Colors.orange),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniRevenue(String label, double amount, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey)),
        Text("${amount.toStringAsFixed(0)} ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon,
      {double? growth}) {
    final bool up = (growth ?? 0) >= 0;
    return Container(
      width: 160,
      margin: const EdgeInsets.only(left: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
          // (دمج من لوحة الويب) شارة النمو الشهري — تُخفى بلا شهرٍ سابقٍ يُقارن به.
          if (growth != null) ...[
            const SizedBox(height: 3),
            Text(
              "${up ? '▲' : '▼'} ${growth.abs().toStringAsFixed(0)}% عن الشهر الماضي",
              style: GoogleFonts.tajawal(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: up ? const Color(0xFF059669) : const Color(0xFFDC2626)),
            ),
          ],
        ],
      ),
    );
  }

  /// (دمج من لوحة الويب) اللوحة المالية: صافي الإيراد بعد الضريبة + توزيع طرق
  /// الدفع (عدد المعاملات والمبلغ ونسبته) من الطلبات المدفوعة في العيّنة المجلوبة.
  Widget _buildFinanceCard(Map<String, dynamic> stats) {
    double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
    const labels = {
      'moyasar': 'بطاقة (ميسر)',
      'credit_card': 'بطاقة (ميسر)',
      'creditcard': 'بطاقة (ميسر)',
      'apple_pay': 'Apple Pay',
      'applepay': 'Apple Pay',
      'stc_pay': 'STC Pay',
      'stcpay': 'STC Pay',
      'samsung_pay': 'Samsung Pay',
      'google_pay': 'Google Pay',
      'wallet': 'المحفظة',
      'tamara': 'تمارا',
      'tabby': 'تابي',
      'subscription': 'اشتراك',
    };
    final Map<String, double> amounts = {};
    final Map<String, int> counts = {};
    void tally(Iterable<DocumentSnapshot> docs) {
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        if ((data['status'] ?? '') == 'cancelled') continue;
        if (data['is_paid'] != true) continue;
        final raw = '${data['payment_method'] ?? ''}'.toLowerCase().trim();
        final label = labels[raw] ?? (raw.isEmpty ? 'غير محدد' : raw);
        final amount = d(data['final_amount'] ??
            data['amount'] ??
            data['total_amount'] ??
            data['total_price']);
        amounts[label] = (amounts[label] ?? 0) + amount;
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }

    tally(_orders);
    tally(_storeOrders);
    final entries = amounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final double maxAmount =
        entries.isEmpty ? 1 : (entries.first.value <= 0 ? 1 : entries.first.value);
    final double net = (stats['revenue'] as double) - (stats['vat'] as double);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("اللوحة المالية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          Text("صافي الإيراد وتوزيع طرق الدفع (المدفوع فقط)", style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.savings_rounded, size: 18, color: Color(0xFF660033)),
              const SizedBox(width: 8),
              Text("صافي الإيراد بعد الضريبة:",
                  style: GoogleFonts.tajawal(fontSize: 13, color: const Color(0xFF334155))),
              const Spacer(),
              Text("${net.toStringAsFixed(0)} ر.س",
                  style: GoogleFonts.tajawal(
                      fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF660033))),
            ],
          ),
          const Divider(height: 22),
          if (entries.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text("لا معاملات مدفوعة بعد",
                    style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)),
              ),
            )
          else
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(e.key,
                              style: GoogleFonts.tajawal(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          const SizedBox(width: 6),
                          Text("×${counts[e.key]} معاملة",
                              style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey)),
                          const Spacer(),
                          Text("${e.value.toStringAsFixed(0)} ر.س",
                              style: GoogleFonts.tajawal(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF660033))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (e.value / maxAmount).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: const Color(0xFFF2DEE9),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF8E2B5C)),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildChartCard({required String title, required String subtitle, required Widget child, double height = 350}) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(subtitle, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildRevenueLineChart(List<DocumentSnapshot> orders, List<DocumentSnapshot> maintenance) {
    Map<String, double> dailyRevenue = {};
    for (int i = 0; i < 7; i++) {
      String day = intl.DateFormat('MM/dd').format(DateTime.now().subtract(Duration(days: i)));
      dailyRevenue[day] = 0.0;
    }

    void processDocs(List<DocumentSnapshot> docs, String dateField, String amountField) {
      for (var doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final rawDate = data[dateField];
        if (rawDate is! Timestamp) continue; // تجاهل التواريخ النصّية/المفقودة بدل الانهيار
        DateTime date = rawDate.toDate();
        String dayKey = intl.DateFormat('MM/dd').format(date);
        if (dailyRevenue.containsKey(dayKey)) {
          dailyRevenue[dayKey] = dailyRevenue[dayKey]! + (double.tryParse(data[amountField].toString()) ?? 0.0);
        }
      }
    }

    // كانت تقرأ final_amount/total_price (غير مكتوبة) فيظهر مخطّط الإيرادات مسطّحاً.
    processDocs(orders, 'created_at', 'amount');
    processDocs(maintenance, 'createdAt', 'amount');
    processDocs(_storeOrders, 'created_at', 'total_amount');

    List<String> sortedDays = dailyRevenue.keys.toList().reversed.toList();
    List<FlSpot> spots = [];
    for (int i = 0; i < sortedDays.length; i++) {
      spots.add(FlSpot(i.toDouble(), dailyRevenue[sortedDays[i]]!));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                if (val.toInt() >= sortedDays.length || val.toInt() < 0) return const Text("");
                return Text(sortedDays[val.toInt()], style: const TextStyle(fontSize: 10, color: Colors.grey));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF2563EB),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicePieChart(List<DocumentSnapshot> orders, List<DocumentSnapshot> maintenance) {
    int maintenanceCount = maintenance.length;
    // طلبات متجر العملاء تعيش في orders بوسم service_meta.kind='store_products'
    // (منذ ad1b5ec) — كانت تُحسب «خدمات أخرى» بينما شريحة «المتجر» تعدّ متجر
    // الشركات فقط. نصنّفها متجراً كما تفعل بطاقات الإيراد في نفس الشاشة.
    int clientStoreCount = orders.where((d) {
      final meta = (d.data() as Map)['service_meta'];
      return meta is Map && meta['kind'] == 'store_products';
    }).length;
    int cleaningCount = orders.where((d) => (d.data() as Map)['service_name']?.toString().contains('نظافة') ?? false).length;
    int otherServicesCount = orders.length - cleaningCount - clientStoreCount;
    int storeCount = _storeOrders.length + clientStoreCount;
    int total = (maintenanceCount + cleaningCount + otherServicesCount + storeCount);
    if (total == 0) return const Center(child: Text("لا توجد بيانات"));

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(color: const Color(0xFF660033), value: cleaningCount.toDouble(), title: 'تنظيف', radius: 50, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          if (otherServicesCount > 0)
            PieChartSectionData(color: const Color(0xFF8E2B5C), value: otherServicesCount.toDouble(), title: 'خدمات أخرى', radius: 50, titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
          if (maintenanceCount > 0)
            PieChartSectionData(color: const Color(0xFFF59E0B), value: maintenanceCount.toDouble(), title: 'صيانة', radius: 50, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          PieChartSectionData(color: const Color(0xFF7C3AED), value: storeCount.toDouble(), title: 'المتجر', radius: 50, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildStatusStatusBarChart(List<DocumentSnapshot> orders, List<DocumentSnapshot> maintenance) {
    int completedCount = orders.where((d) => (d.data() as Map)['status'] == 'completed').length + maintenance.where((d) => (d.data() as Map)['status'] == 'completed').length;
    int activeCount = (orders.length + maintenance.length) - completedCount;

    return BarChart(
      BarChartData(
        barGroups: [
          BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: activeCount.toDouble(), color: Colors.orange, width: 16, borderRadius: BorderRadius.circular(4))]),
          BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: completedCount.toDouble(), color: Colors.green, width: 16, borderRadius: BorderRadius.circular(4))]),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) {
                if (val == 0) return const Text("نشط", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
                if (val == 1) return const Text("مكتمل", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
                return const Text("");
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildRecentActivityList(List<DocumentSnapshot> orders, List<DocumentSnapshot> maintenance) {
    List<Map<String, dynamic>> activities = [];
    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      activities.add({
        'title': data['service_name'] ?? 'خدمة عامة',
        'subtitle': 'طلب نظافة جديد - ${data['amount']} ر.س',
        'time': data['created_at'],
        'icon': Icons.cleaning_services_rounded,
        'color': const Color(0xFF2563EB),
      });
    }
    for (var doc in maintenance) {
      final data = doc.data() as Map<String, dynamic>;
      activities.add({
        'title': data['serviceType'] ?? 'صيانة',
        'subtitle': 'طلب صيانة - ${data['quotePrice'] ?? "قيد التسعير"} ر.س',
        'time': data['createdAt'],
        'icon': Icons.build_circle_rounded,
        'color': const Color(0xFFF59E0B),
      });
    }

    activities.sort((a, b) {
      // تحويل آمن: قيمة time قد تكون نصّية (بيانات قديمة)، والتحويل الصلب as Timestamp
      // كان يرمي TypeError فيُسقط شاشة الرؤى بالكامل.
      final aTime = a['time'] is Timestamp ? a['time'] as Timestamp : null;
      final bTime = b['time'] is Timestamp ? b['time'] as Timestamp : null;
      return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
    });

    final recent = activities.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("النشاطات الأخيرة"),
        const SizedBox(height: 15),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
            itemBuilder: (context, index) {
              final act = recent[index];
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: act['color'].withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(act['icon'], color: act['color'], size: 20),
                ),
                title: Text(act['title'], style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(act['subtitle'], style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                trailing: Text(
                  act['time'] is Timestamp ? intl.DateFormat('HH:mm').format((act['time'] as Timestamp).toDate()) : '-',
                  style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildLivePulseSection() {
    // Calculating New (Pending) Counts for each section
    final int cleaningNew = _orders.where((doc) => (doc.data() as Map)['status'] == 'pending' || (doc.data() as Map)['status'] == 'waiting_payment').length;
    final int storeNew = _storeOrders.where((doc) => (doc.data() as Map)['status'] == 'pending').length;

    // بطاقتا «خدمات بالساعة» و«طلبات المتجر» تفتحان شاشتين حكرهما على مديري
    // الطلبات (تبويب الطلبات في اللوحة وقيود firestore.rules) — كانتا تظهران
    // للمحاسب/التسويق فتنتهي نقراتهما برفض صلاحيات يُلام عليه الاتصال. نحجبهما
    // بنفس معيار admin_more_screen (طلبات المتجر: super_admin/orders_manager).
    final bool canManageOrders =
        ['admin', 'super_admin', 'orders_manager'].contains(widget.role);

    // For contracts, we'll use a snapshot count if available, or 0
    // (Note: In a real scenario, you'd add a listener for contracts too)
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle("رادار الطلبات الجديدة"),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.2), blurRadius: 4)]
              ),
              child: Text("محدث", style: GoogleFonts.tajawal(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 15),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.3 : 1.15,
          children: [
            if (canManageOrders) ...[
              _buildLuxuryRequestCard(
                title: "خدمات بالساعة",
                count: cleaningNew,
                icon: Icons.cleaning_services_rounded,
                gradient: const [Color(0xFF1E293B), Color(0xFF475569)], // Gray/Slate
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen())),
              ),
              _buildLuxuryRequestCard(
                title: "طلبات المتجر",
                count: storeNew,
                icon: Icons.shopping_basket_rounded,
                gradient: const [Color(0xFF1E1B4B), Color(0xFF312E81)], // Deep Indigo
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStoreOrdersScreen())),
              ),
            ],
            _buildLuxuryRequestCard(
              title: "عقود تنفيذية",
              count: 0, 
              icon: Icons.history_edu_rounded,
              gradient: const [Color(0xFF581C87), Color(0xFF701A75)], // Purple/Fuchsia
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminContractsScreen())),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLuxuryRequestCard({
    required String title,
    required int count,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade500,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                    ),
                    child: Text(
                      "$count",
                      style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              count > 0 ? "يوجد مهمات عاجلة" : "لا توجد طلبات جديدة",
              style: GoogleFonts.tajawal(
                color: Colors.white.withValues(alpha: count > 0 ? 0.9 : 0.5),
                fontSize: 10,
                fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReputationSentinel() {
    final lowRatings = _orders.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final rating = double.tryParse('${data['rating'] ?? 5.0}') ?? 5.0;
      return rating <= 2.0 && data['rating_comment'] != null;
    }).toList();

    if (lowRatings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("رادار حماية السمعة ⚠️"),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Column(
            children: lowRatings.take(3).map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text("${data['rating']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("العميل: ${data['client_name']}", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text("السبب: ${data['rating_reason'] ?? 'غير محدد'}", style: GoogleFonts.tajawal(color: Colors.red[700], fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSystemHealthSection(List<DocumentSnapshot> drivers) {
    int expiringSoon = 0;
    final now = DateTime.now();

    for (var doc in drivers) {
      final data = doc.data() as Map<String, dynamic>;
      final expiryStr = data['id_expiry']?.toString() ?? '';
      try {
        final expiryDate = DateTime.parse(expiryStr);
        if (expiryDate.difference(now).inDays < 30) {
          expiringSoon += 1;
        }
      } catch (e) {
        // ...
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("صحة النظام والرقابة"),
        const SizedBox(height: 15),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          child: Column(
            children: [
              _buildHealthItem(
                title: "التزام الكوادر (Compliance)",
                subtitle: expiringSoon > 0 ? "يوجد $expiringSoon كادر تنتهي هوياتهم قريباً" : "جميع الهويات سارية المفعول",
                icon: Icons.gavel_rounded,
                color: expiringSoon > 0 ? Colors.red : Colors.green,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminComplianceScreen())),
              ),
              const Divider(height: 30),
              _buildHealthItem(
                title: "كفاءة الكوادر (Performance)",
                subtitle: "متابعة الإنجازات والتقييمات",
                icon: Icons.insights_rounded,
                color: const Color(0xFF660033),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStaffPerformanceScreen())),
              ),
              const Divider(height: 30),
              _buildHealthItem(
                title: "استقرار قاعدة البيانات",
                subtitle: "الحالة: ممتازة (Real-time Sync)",
                icon: Icons.cloud_done_rounded,
                color: Colors.blue,
                // صفّ حالةٍ فقط بلا وجهة — null يخفي السهم ويعطّل التموّج بدل
                // onTap فارغ كان يوحي بإمكانية الفتح ولا يفعل شيئاً.
                onTap: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthItem({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          // السهم للصفوف القابلة للفتح فقط — لا نعرض إيحاء تنقّلٍ لصفوف الحالة.
          if (onTap != null) const Icon(Icons.chevron_left_rounded, color: Colors.grey),
        ],
      ),
    );
  }

}
