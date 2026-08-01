import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/admin/admin_ticket_details_screen.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';

class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text("مركز المساعدة والدعم", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF660033),
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
      // حدّ 200 مع ترتيب خادمي: الأرشيف مجموعة تنمو بلا سقف — بدون limit تُقرأ
      // كل التذاكر المغلقة تاريخياً عند كل فتح (فهرس status+createdAt في firestore.indexes.json).
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .where('status', whereIn: statuses)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ZyiarahShimmer.buildListSkeleton(count: 5);
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 10),
                const Text("تعذّر تحميل التذاكر، تحقّق من الاتصال", style: TextStyle(color: Colors.red)),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text("إعادة المحاولة", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        
        // Sort locally by date
        final sortedDocs = docs.toList()..sort((a, b) {
          // اقرأ من الخريطة: a['createdAt'] على المستند يرمي StateError لتذكرة بلا الحقل.
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = (aData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bDate = (bData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return bDate.compareTo(aDate);
        });

        // فلترة محلية على القائمة المحمّلة (بحث حي في الموضوع/اسم العميل/بريده)
        final query = _search.trim().toLowerCase();
        final filteredDocs = query.isEmpty
            ? sortedDocs
            : sortedDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final subject = (data['subject'] ?? '').toString().toLowerCase();
                final email = (data['userEmail'] ?? '').toString().toLowerCase();
                final name = (data['userName'] ?? '').toString().toLowerCase();
                return subject.contains(query) ||
                    email.contains(query) ||
                    name.contains(query);
              }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                style: GoogleFonts.tajawal(),
                decoration: InputDecoration(
                  hintText: "ابحث بالموضوع أو اسم العميل أو البريد",
                  hintStyle: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF660033)),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF660033)),
                  ),
                ),
              ),
            ),
            // تنبيه الاقتطاع: عند بلوغ الحدّ قد توجد تذاكر أقدم غير معروضة
            if (docs.length >= 200)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text("يعرض أحدث 200 تذكرة",
                    style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 11)),
              ),
            Expanded(child: _buildResults(context, sortedDocs, filteredDocs)),
          ],
        );
      },
    );
  }

  Widget _buildResults(
    BuildContext context,
    List<QueryDocumentSnapshot> sortedDocs,
    List<QueryDocumentSnapshot> filteredDocs,
  ) {
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

    if (filteredDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              "لا نتائج للبحث «${_search.trim()}»",
              style: GoogleFonts.tajawal(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final ticket = filteredDocs[index].data() as Map<String, dynamic>;
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
                      builder: (_) => AdminTicketDetailsScreen(ticketId: filteredDocs[index].id)
                    )
                  );
                },
              ),
            );
          },
        );
  }
}
