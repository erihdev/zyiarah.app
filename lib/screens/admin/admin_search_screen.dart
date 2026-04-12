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
  List<DocumentSnapshot> _userResults = [];
  List<DocumentSnapshot> _driverResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        _orderResults = [];
        _userResults = [];
        _driverResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    final db = FirebaseFirestore.instance;
    final q = query.toLowerCase().trim();

    try {
      // 1. Search Orders by Code (if likely a code)
      final ordersSnap = await db.collection('orders')
          .where('code', isGreaterThanOrEqualTo: q.toUpperCase())
          .where('code', isLessThanOrEqualTo: '${q.toUpperCase()}\uf8ff')
          .limit(10).get();

      // 2. Search Users by Name
      final usersSnap = await db.collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10).get();

      // 3. Search Drivers by Name
      final driversSnap = await db.collection('drivers')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10).get();

      if (mounted) {
        setState(() {
          _orderResults = ordersSnap.docs;
          _userResults = usersSnap.docs;
          _driverResults = driversSnap.docs;
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
              decoration: InputDecoration(
                hintText: "ابحث عن طلب، عميل، أو كادر...",
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                suffixIcon: IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18), onPressed: () => _searchCtrl.clear()),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: "الطلبات"),
              Tab(text: "العملاء"),
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
                _buildResultsList(_userResults, 'user'),
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
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("لا توجد نتائج مطابقة", style: GoogleFonts.tajawal(color: Colors.grey)),
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

    if (type == 'order') {
      title = data['service_name'] ?? 'طلب';
      subtitle = "رقم الطلب: #${data['code'] ?? doc.id.substring(0, 8)}";
      icon = Icons.receipt_long_rounded;
      color = Colors.blue;
    } else if (type == 'user') {
      title = data['name'] ?? 'عميل';
      subtitle = data['phone'] ?? 'بدون رقم';
      icon = Icons.person_rounded;
      color = Colors.purple;
    } else if (type == 'driver') {
      title = data['name'] ?? 'سائق';
      subtitle = "${data['type'] == 'worker' ? 'كادر تنظيف' : 'سائق توصيل'} - ${data['phone']}";
      icon = Icons.local_shipping_rounded;
      color = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        onTap: () {
          if (type == 'order') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(orderId: doc.id)));
          } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("جاري فتح ملف: $title")));
          }
        },
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.grey),
      ),
    );
  }
}
