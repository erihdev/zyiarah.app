import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zyiarah_contract_pdf_service.dart';

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

            final rawDocs = snapshot.data!.docs;
            final Map<String, DocumentSnapshot> uniqueMap = {};
            for (var doc in rawDocs) {
              final data = doc.data() as Map<String, dynamic>;
              final cId = data['contractId'] ?? doc.id;
              if (!uniqueMap.containsKey(cId)) {
                uniqueMap[cId] = doc;
              }
            }
            final contracts = uniqueMap.values.toList();
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: contracts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 15),
              itemBuilder: (context, index) {
                final data = contracts[index].data() as Map<String, dynamic>;
                final contractDocId = contracts[index].id;
                return _buildContractCard(context, data, contractDocId);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContractCard(BuildContext context, Map<String, dynamic> data, String contractDocId) {
    final status = data['status'] ?? 'pending';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final planName = data['planName'] ?? 'عقد باقة عائلية';
    
    Color statusColor = Colors.orange;
    String statusText = "بانتظار الاعتماد";
    IconData statusIcon = Icons.hourglass_empty_rounded;

    if (status == 'active') {
      statusColor = Colors.green;
      statusText = "نشط وموثق";
      statusIcon = Icons.verified_rounded;
    } else if (status == 'expired') {
      statusColor = Colors.grey;
      statusText = "منتهي";
      statusIcon = Icons.history_rounded;
    } else if (status == 'approved_waiting_payment') {
      statusColor = const Color(0xFF2563EB);
      statusText = "بانتظار الدفع";
      statusIcon = Icons.payments_outlined;
    } else if (status == 'rejected') {
      statusColor = Colors.red;
      statusText = "مرفوض";
      statusIcon = Icons.cancel_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: statusColor.withValues(alpha: 0.05),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Text(statusText, style: GoogleFonts.tajawal(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(
                    intl.DateFormat('yyyy/MM/dd').format(createdAt),
                    style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: brandPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.description_outlined, color: brandPurple, size: 24),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(planName, 
                              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF0F172A))),
                            Text('رقم العقد: #${data['contractId'] ?? contractDocId.substring(0, 8).toUpperCase()}', 
                              style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildQuickInfo(Icons.event_available, 'الزيارات', '${data['planVisits'] ?? 0} زيارة'),
                      const SizedBox(width: 20),
                      _buildQuickInfo(Icons.sell_outlined, 'القيمة', '${data['planPrice'] ?? 0} ر.س'),
                    ],
                  ),
                  const Divider(height: 30),
                  Row(
                    children: [
                      if (status == 'approved_waiting_payment')
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PaymentSummaryScreen(
                                  serviceName: planName,
                                  amount: (data['planPrice'] ?? 0.0).toDouble(),
                                  contractId: contractDocId,
                                  planVisits: (data['planVisits'] ?? 0).toInt(),
                                )
                              ));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text('دفع وتفعيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                          ),
                        )
                      else if (status == 'active' || status == 'completed' || status == 'pending')
                         Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ZyiarahContractPdfService.generateAndDownloadContract(
                                contractId: data['contractId'] ?? contractDocId.substring(0, 8),
                                planName: planName,
                                userName: data['userName'] ?? 'عميل زيارة',
                                userPhone: data['userPhone'] ?? '000000000',
                                price: (data['planPrice'] ?? 0.0).toDouble(),
                                visits: (data['planVisits'] ?? 0).toInt(),
                                startDate: createdAt,
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: Text('تحميل العقد (PDF)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: brandPurple,
                              side: BorderSide(color: brandPurple.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => _viewContractDetails(context, data),
                        child: Text(status == 'approved_waiting_payment' ? 'عرض البنود' : 'مشاهدة التفاصيل', 
                          style: GoogleFonts.tajawal(color: Colors.grey.shade600, fontSize: 13)),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfo(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
      ],
    );
  }

  void _viewContractDetails(BuildContext context, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.description_rounded, color: brandPurple, size: 28),
                  const SizedBox(width: 12),
                  Text('تفاصيل العقد الموثق', style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 40),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailItem('الطرف الثاني (العميل)', data['userName'] ?? data['clientName'] ?? 'غير محدد'),
                      _buildDetailItem('رقم الهاتف', data['userPhone'] ?? 'غير محدد'),
                      _buildDetailItem('الباقة المختارة', data['planName'] ?? 'غير محدد'),
                      _buildDetailItem('القيمة الإجمالية', '${data['planPrice'] ?? 0} ر.س'),
                      _buildDetailItem('عدد الزيارات', '${data['planVisits'] ?? 0} زيارة'),
                      const SizedBox(height: 20),
                      Text('نص الاتفاقية:', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Text(
                          'تم إبرام هذا العقد إلكترونياً بين مؤسسة زيارة والعميل المذكور أعلاه. '
                          'يلتزم مقدم الخدمة بتقديم الزيارات المحددة في الباقة المذكورة، '
                          'ويلتزم العميل بسداد قيمة العقد والالتزام بمواعيد الزيارات المجدولة.',
                          style: GoogleFonts.tajawal(height: 1.8, fontSize: 13, color: Colors.blueGrey[800]),
                        ),
                      ),
                      const SizedBox(height: 30),
                      if (data['status'] == 'active')
                        Center(
                          child: Column(
                            children: [
                              const Icon(Icons.verified_user, color: Colors.green, size: 50),
                              const SizedBox(height: 10),
                              Text('عقد موثق ونشط', style: GoogleFonts.tajawal(color: Colors.green, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text('إغلاق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: brandPurple.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.description_outlined, size: 80, color: brandPurple.withValues(alpha: 0.2)),
          ),
          const SizedBox(height: 24),
          Text('لا توجد عقود حالياً', 
            style: GoogleFonts.tajawal(color: const Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('ستظهر عقودك الموقعة هنا بمجرد إنشائها', 
            style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

