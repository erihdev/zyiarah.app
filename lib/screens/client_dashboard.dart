import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/screens/profile_screen.dart';
import 'package:zyiarah/models/order_model.dart';
import 'package:zyiarah/models/user_model.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  final TamaraService _tamaraService = TamaraService();
  bool _isLoading = false;
  ZyiarahUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
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

    setState(() {
      _isLoading = true;
    });

    try {
      final String currentOrderId = "ORD-${DateTime.now().millisecondsSinceEpoch}";
      
      // Creating the order object using our new Model
      final newOrder = ZyiarahOrder(
        id: currentOrderId,
        clientId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
        serviceType: serviceName,
        amount: amount,
        status: 'pending',
        paymentStatus: 'unpaid',
        location: selectedLocation,
        createdAt: DateTime.now(),
      );

      // إنشاء جلسة دفع تجريبية
      String? checkoutUrl = await _tamaraService.createCheckoutSession(
        orderId: newOrder.id,
        amount: newOrder.amount,
        customerPhone: _currentUser?.phone ?? "500000000",
        customerName: _currentUser?.name ?? "عميل زيارة",
      );

      if (checkoutUrl != null && mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // الانتقال لشاشة الدفع
        bool? paymentSuccess = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TamaraCheckoutScreen(
              checkoutUrl: checkoutUrl,
              amount: newOrder.amount,
              orderId: newOrder.id,
              serviceType: newOrder.serviceType,
              location: newOrder.location,
            ),
          ),
        );

        if (paymentSuccess == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('تم تأكيد طلب ${newOrder.serviceType} بنجاح!')),
          );
        }
      } else {
        throw Exception("لم نتمكن من جلب رابط الدفع");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الدفع: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("زيارة - اطلب الآن", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahProfileScreen()));
            },
          )
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "مرحباً بك${_currentUser != null ? '، ${_currentUser!.name}' : ''}", 
                    style: const TextStyle(fontSize: 18, color: Colors.grey)
                  ),
                  const Text("ما الخدمة التي تحتاجينها اليوم؟", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                      children: [
                        _buildServiceItem(Icons.cleaning_services, "نظافة منزلية", 150.0),
                        _buildServiceItem(Icons.local_laundry_service, "كي وغسيل", 50.0),
                        _buildServiceItem(Icons.child_care, "رعاية أطفال", 200.0),
                        _buildServiceItem(Icons.settings_suggest, "صيانة خفيفة", 100.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItem(IconData icon, String label, double price) {
    return InkWell(
      onTap: () => _initiatePayment(label, price),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF1E3A8A)),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text("$price ر.س", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
