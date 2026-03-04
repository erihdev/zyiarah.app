import 'package:flutter/material.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/screens/profile_screen.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  final TamaraService _tamaraService = TamaraService();
  bool _isLoading = false;

  void _initiatePayment(String serviceName, double amount) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final String currentOrderId = "ORD-${DateTime.now().millisecondsSinceEpoch}";
      // إنشاء جلسة دفع تجريبية
      String? checkoutUrl = await _tamaraService.createCheckoutSession(
        orderId: currentOrderId,
        amount: amount,
        customerPhone: "500000000", // تجريبي
        customerName: "عميل تجريبي",
      );

      if (checkoutUrl != null && mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // الانتقال لشاشة الدفع
        final String currentOrderId = "ORD-${DateTime.now().millisecondsSinceEpoch}";
        bool? paymentSuccess = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TamaraCheckoutScreen(
              checkoutUrl: checkoutUrl,
              amount: amount,
              orderId: currentOrderId,
              serviceType: serviceName,
            ),
          ),
        );

        if (paymentSuccess == true && mounted) {
          // يمكن هنا نقل العميل لخريطة التتبع بعد الدفع
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('تم تأكيد طلب $serviceName بنجاح!')),
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
                  const Text("مرحباً بك،", style: TextStyle(fontSize: 18, color: Colors.grey)),
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
