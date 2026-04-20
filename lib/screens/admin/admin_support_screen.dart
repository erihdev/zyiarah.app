import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/admin/admin_ticket_details_screen.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';

class AdminSupportScreen extends StatelessWidget {
  const AdminSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text("مركز المساعدة والدعم", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            bottom: TabBar(
              indicatorColor: Colors.blueAccent,
              labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: "تذاكر نشطة"),
                Tab(text: "الأرشيف"),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildTicketsList(context, ['open', 'replied']),
              _buildTicketsList(context, ['resolved', 'closed']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketsList(BuildContext context, List<String> statuses) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .where('status', whereIn: statuses)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ZyiarahShimmer.buildListSkeleton(count: 5);
        }
        
        final docs = snapshot.data?.docs ?? [];
        
        // Sort locally by date
        final sortedDocs = docs.toList()..sort((a, b) {
          final aDate = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bDate = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return bDate.compareTo(aDate);
        });

        if (sortedDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.support_agent_rounded, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text("لا توجد تذاكر في هذا القسم", style: GoogleFonts.tajawal(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final ticket = sortedDocs[index].data() as Map<String, dynamic>;
            String status = ticket['status'] ?? 'open';
            
            Color statusColor = Colors.orange;
            String statusAr = "قيد الانتظار";

            if (status == 'replied') {
              statusColor = Colors.blue;
              statusAr = "تم الرد";
            } else if (status == 'resolved' || status == 'closed') {
              statusColor = Colors.green;
              statusAr = "مكتمل";
            }

            final createdAt = (ticket['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade100),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.forum_rounded, color: statusColor, size: 20),
                ),
                title: Text(
                  ticket['subject'] ?? 'تذكرة دعم',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(ticket['userEmail'] ?? 'عميل زيارة', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusAr,
                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${createdAt.day}/${createdAt.month}",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    const Icon(Icons.chevron_left, color: Colors.grey, size: 18),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(
                      builder: (_) => AdminTicketDetailsScreen(ticketId: sortedDocs[index].id)
                    )
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
