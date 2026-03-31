import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahContractsListScreen extends StatelessWidget {
  const ZyiarahContractsListScreen({super.key});

  final Color brandPurple = const Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('عقودي الإلكترونية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: brandPurple,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('contracts')
              .where('userId', isEqualTo: user?.uid)
            .snapshots(),
          builder: (context, snapshot) {
            if (user == null) {
              return const Center(child: Text('يرجى تسجيل الدخول لعرض عقودك'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: brandPurple));
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text('حدث خطأ أثناء جلب العقود: ${snapshot.error}', 
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(color: Colors.red)),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            final contracts = snapshot.data!.docs;
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: contracts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 15),
              itemBuilder: (context, index) {
                final data = contracts[index].data() as Map<String, dynamic>;
                return _buildContractCard(data);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContractCard(Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    Color statusColor = Colors.orange;
    String statusText = "بانتظار الاعتماد";

    if (status == 'active') {
      statusColor = Colors.green;
      statusText = "نشط وموثق";
    } else if (status == 'expired') {
      statusColor = Colors.grey;
      statusText = "منتهي";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data['planName'] ?? 'عقد باقة عائلية', 
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildInfoRow(Icons.calendar_today_outlined, 'تاريخ البدء', intl.DateFormat('yyyy/MM/dd').format(createdAt)),
          _buildInfoRow(Icons.verified_user_outlined, 'الرقم التعاقدي', '#${data['contractId'] ?? '10293'}'),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {},
                child: Text('تحميل العقد (PDF)', style: GoogleFonts.tajawal(color: brandPurple, fontWeight: FontWeight.bold)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
          Text(value, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Text('لا توجد عقود نشطة حالياً', 
            style: GoogleFonts.tajawal(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
