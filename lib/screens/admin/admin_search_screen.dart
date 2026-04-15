import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';

class AdminSearchScreen extends StatefulWidget {
  const AdminSearchScreen({super.key});

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  
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
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 3) {
      setState(() {
        _orderResults = []; _storeResults = []; _userResults = []; _productResults = []; _driverResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    final db = FirebaseFirestore.instance;
    final q = query.trim();
    final qUpper = q.toUpperCase();

    try {
      // Parallel searches
      final results = await Future.wait([
        // 1. Regular Orders (Cleaning/Services) - Search by Code
        db.collection('orders').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get(),
        // 2. Store Orders - Search by Code
        db.collection('store_orders').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get(),
        // 3. Maintenance Requests - Search by Code
        db.collection('maintenance_requests').where('code', isGreaterThanOrEqualTo: qUpper).where('code', isLessThanOrEqualTo: '$qUpper\uf8ff').limit(15).get(),
        // 4. Users - Search by Name
        db.collection('users').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get(),
        // 5. Products - Search by Name
        db.collection('products').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get(),
        // 6. Drivers - Search by Name
        db.collection('drivers').where('name', isGreaterThanOrEqualTo: q).where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(15).get(),
      ]);

      if (mounted) {
        setState(() {
          _orderResults = results[0].docs;
          _storeResults = results[1].docs;
          _maintenanceResults = results[2].docs;
          _userResults = results[3].docs;
          _productResults = results[4].docs;
          _driverResults = results[5].docs;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Container(
            height: 45,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: _performSearch,
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
                _buildResultsList(_storeResults, 'store_order'),
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
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طلب صيانة: $title")));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("ملف: $title")));
          }
        },
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 18)),
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.arrow_back_ios_rounded, size: 12, color: Colors.grey),
      ),
    );
  }
}
