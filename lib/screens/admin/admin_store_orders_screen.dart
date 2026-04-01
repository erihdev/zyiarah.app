import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminStoreOrdersScreen extends StatelessWidget {
  const AdminStoreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلبات المتجر (Swift Clean)", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('store_orders').orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لم يقم أحد بالشراء من المتجر بعد"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final order = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.shopping_bag, color: Colors.white)),
                    title: Text("طلب رقم #${snapshot.data!.docs[index].id.substring(0, 5)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("العميل: ${order['customerName'] ?? 'مستخدم'}\nالإجمالي: ${order['totalPrice'] ?? 0} ر.س\nالحالة: ${order['status'] ?? 'قيد المعالجة'}"),
                    isThreeLine: true,
                    trailing: const Icon(Icons.local_shipping, color: Colors.blue),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
