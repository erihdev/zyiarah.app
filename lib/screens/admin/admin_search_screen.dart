import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';

class AdminSearchScreen extends StatefulWidget {
  // الدور يصل من AdminDashboardScreen (مطبَّع: admin→super_admin) — قواعد Firestore
  // تحصر قراءة store_orders في مديري الطلبات، فنحتاجه لتخطي ذلك الاستعلام.
  final String role;
  const AdminSearchScreen({super.key, required this.role});

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  Timer? _debounceTimer;
  
  List<DocumentSnapshot> _orderResults = [];
  List<DocumentSnapshot> _storeResults = [];
  List<DocumentSnapshot> _maintenanceResults = [];
  List<DocumentSnapshot> _userResults = [];
  List<DocumentSnapshot> _productResults = [];
  List<DocumentSnapshot> _driverResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 3) {
      setState(() {
        _orderResults = []; _storeResults = []; _userResults = []; _productResults = []; _driverResults = [];
        _maintenanceResults = []; // كان مفقوداً فتبقى نتائج الصيانة القديمة معروضة بعد مسح البحث
      });
      return;
    }

    setState(() => _isSearching = true);
    final db = FirebaseFirestore.instance;
    final q = query.trim();
    final qUpper = q.toUpperCase();

    // \u0639\u0632\u0644 \u0643\u0644 \u0627\u0633\u062a\u0639\u0644\u0627\u0645 \u0628\u062e\u0637\u0626\u0647 \u0627\u0644\u062e\u0627\u0635: \u0631\u0641\u0636\u064f \u0645\u062c\u0645\u0648\u0639\u0629\u064d \u0648\u0627\u062d\u062f\u0629 (store_orders \u0644\u0644\u0645\u062d\u0627\u0633\u0628/\u0627\u0644\u062a\u0633\u0648\u064a\u0642)
    // \u0643\u0627\u0646 \u064a\u064f\u0641\u0634\u0650\u0644 Future.wait \u0643\u0627\u0645\u0644\u0627\u064b \u0641\u062a\u0628\u0642\u0649 \u0627\u0644\u0642\u0648\u0627\u0626\u0645 \u0627\u0644\u0633\u062a \u0641\u0627\u0631\u063a\u0629 \u2014 \u0628\u062d\u062b\u064c \u0645\u064a\u062a \u0628\u0635\u0645\u062a.
    Object? firstError;
    Future<QuerySnapshot<Map<String, dynamic>>?> guarded(Future<QuerySnapshot<Map<String, dynamic>>> f) =>
        f.then<QuerySnapshot<Map<String, dynamic>>?>((v) => v, onError: (Object e) {
          firstError ??= e;
          return null;
        });
    try {
      // Parallel searches
      final results = await Future.wait([
        // 1. Regular Orders (Cleaning/Services) - Search by Code
        guarded(db.collection('orders').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get()),
        // 2. Store Orders - Search by Code (\u0642\u0631\u0627\u0621\u062a\u0647\u0627 \u0645\u062d\u0635\u0648\u0631\u0629 \u0628\u0627\u0644\u0642\u0648\u0627\u0639\u062f \u0641\u064a \u0645\u062f\u064a\u0631\u064a \u0627\u0644\u0637\u0644\u0628\u0627\u062a \u2014
        // \u0646\u062a\u062e\u0637\u0627\u0647\u0627 \u0644\u0644\u0623\u062f\u0648\u0627\u0631 \u0627\u0644\u0623\u062e\u0631\u0649 \u0628\u062f\u0644 \u0627\u0633\u062a\u0639\u0644\u0627\u0645\u064d \u0645\u062d\u0643\u0648\u0645\u064d \u0639\u0644\u064a\u0647 \u0628\u0640 permission-denied)
        _canReadStore
            ? guarded(db.collection('store_orders').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get())
            : Future<QuerySnapshot<Map<String, dynamic>>?>.value(null),
        // 3. Maintenance Requests - Search by Code
        guarded(db.collection('maintenance_requests').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get()),
        // 4. Users - Search by Name
        guarded(db.collection('users').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get()),
        // 5. Products - Search by Name
        guarded(db.collection('products').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get()),
        // 6. Drivers - Search by Name
        guarded(db.collection('drivers').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get()),
      ]);

      if (mounted) {
        setState(() {
          _orderResults = results[0]?.docs ?? [];
          _storeResults = results[1]?.docs ?? [];
          _maintenanceResults = results[2]?.docs ?? [];
          _userResults = results[3]?.docs ?? [];
          _productResults = results[4]?.docs ?? [];
          _driverResults = results[5]?.docs ?? [];
          _isSearching = false;
        });
        if (firstError != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('\u0641\u0634\u0644 \u0627\u0644\u0628\u062d\u062b \u0641\u064a \u0628\u0639\u0636 \u0627\u0644\u0623\u0642\u0633\u0627\u0645: $firstError'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } finally {
      // \u0636\u0645\u0627\u0646 \u0639\u062f\u0645 \u0628\u0642\u0627\u0621 \u0645\u0624\u0634\u0631 \u0627\u0644\u0628\u062d\u062b \u0639\u0627\u0644\u0642\u0627\u064b \u0645\u0647\u0645\u0627 \u0643\u0627\u0646 \u0645\u0633\u0627\u0631 \u0627\u0644\u0641\u0634\u0644.
      if (mounted && _isSearching) setState(() => _isSearching = false);
    }
  }

  // \u0627\u0644\u062f\u0648\u0631 \u0645\u0637\u0628\u064e\u0651\u0639 \u0645\u0646 \u0627\u0644\u062f\u0627\u0634\u0628\u0648\u0631\u062f\u061b admin \u062a\u0628\u0642\u0649 \u0644\u0644\u0627\u062d\u062a\u064a\u0627\u0637 \u0644\u0648 \u0645\u064f\u0631\u0651\u0631\u062a \u0628\u0644\u0627 \u062a\u0637\u0628\u064a\u0639.
  bool get _canReadStore => ['admin', 'super_admin', 'orders_manager'].contains(widget.role);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Container(
            height: 45,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: "ابحث عن أي شيء في المنصة...",
                hintStyle: TextStyle(color: Colors.white54, fontSize: 12),
                prefixIcon: Icon(Icons.manage_search_rounded, color: Colors.white70),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.blueAccent,
            labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 11),
            isScrollable: true,
            tabs: const [
              Tab(text: "الخدمات"),
              Tab(text: "المتجر"),
              Tab(text: "الصيانة"),
              Tab(text: "العملاء"),
              Tab(text: "المنتجات"),
              Tab(text: "الكوادر"),
            ],
          ),
        ),
        body: _isSearching 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E293B)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildResultsList(_orderResults, 'order'),
                // للأدوار الممنوعة من قراءة store_orders نوضّح السبب بدل «لا توجد
                // نتائج» المضلِّلة (الاستعلام مُتخطّى أصلاً لتفادي permission-denied).
                _canReadStore
                    ? _buildResultsList(_storeResults, 'store_order')
                    : Center(
                        child: Text(
                          "البحث في طلبات المتجر متاح لمديري الطلبات فقط",
                          style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                _buildResultsList(_maintenanceResults, 'maintenance'),
                _buildResultsList(_userResults, 'user'),
                _buildResultsList(_productResults, 'product'),
                _buildResultsList(_driverResults, 'driver'),
              ],
            ),
      ),
    );
  }

  Widget _buildResultsList(List<DocumentSnapshot> docs, String type) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("لا توجد نتائج متوفرة", style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) => _buildResultCard(docs[index], type),
    );
  }

  Widget _buildResultCard(DocumentSnapshot doc, String type) {
    final data = doc.data() as Map<String, dynamic>;
    String title = '';
    String subtitle = '';
    IconData icon = Icons.help_outline;
    Color color = Colors.grey;

    switch (type) {
      case 'order':
        title = data['service_name'] ?? 'خدمة';
        subtitle = "رقم: #${data['code'] ?? doc.id.substring(0, 5)} - ${data['amount']} ر.س";
        icon = Icons.receipt_long_rounded;
        color = Colors.blue;
        break;
      case 'store_order':
        title = "طلب متجر #${data['code'] ?? doc.id.substring(0, 6)}";
        subtitle = "الإجمالي: ${data['total_amount']} ر.س - الحالة: ${data['status']}";
        icon = Icons.shopping_basket_rounded;
        color = Colors.teal;
        break;
      case 'maintenance':
        title = data['serviceType'] ?? 'طلب صيانة';
        subtitle = "رقم: #${data['code'] ?? doc.id.substring(0, 5)} - العميل: ${data['userName']}";
        icon = Icons.plumbing_rounded;
        color = Colors.orange;
        break;
      case 'user':
        title = data['name'] ?? 'عميل';
        subtitle = data['phone'] ?? 'بدون رقم';
        icon = Icons.person_pin_rounded;
        color = Colors.purple;
        break;
      case 'product':
        title = data['name'] ?? 'منتج';
        subtitle = "السعر: ${data['price']} ر.س";
        icon = Icons.inventory_2_rounded;
        color = Colors.indigo;
        break;
      case 'driver':
        title = data['name'] ?? 'سائق/عامل';
        subtitle = "${data['phone']} - ${data['type']}";
        icon = Icons.engineering_rounded;
        color = Colors.orange;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ListTile(
        onTap: () {
          if (type == 'order') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(orderId: doc.id)));
          } else if (type == 'maintenance') {
             // Future: AdminMaintenanceDetailsScreen
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طلب صيانة: $title — $subtitle")));
          } else {
            // لا شاشات تفاصيل لهذه الأنواع بعد (توجد قوائم فقط) — نعرض البيانات
            // المتاحة بدل ترديد العنوان الظاهر أصلاً على البطاقة.
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title — $subtitle")));
          }
        },
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 18)),
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        // سهم التنقّل للطلبات فقط — بقية الأنواع بلا شاشة تفاصيل، فالسهم كان يوهم
        // بوجهةٍ لا تُفتح.
        trailing: type == 'order' ? const Icon(Icons.arrow_back_ios_rounded, size: 12, color: Colors.grey) : null,
      ),
    );
  }
}
