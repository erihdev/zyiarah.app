import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('التنبيهات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.done_all_rounded, size: 20),
              tooltip: "قراءة الكل",
              onPressed: () => _markAllAsRead(user?.uid),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: user?.uid)
              .orderBy('sentAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            final notifications = snapshot.data!.docs;
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = notifications[index];
                final note = doc.data() as Map<String, dynamic>;
                final isRead = note['isRead'] ?? false;
                
                return _buildNotificationCard(doc.id, note, isRead);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(
            'https://lottie.host/936c7457-3759-4d64-98aa-3e753456c636/Hw4h8Pndr5.json', 
            height: 200,
          ),
          const SizedBox(height: 20),
          Text('لا توجد تنبيهات حالياً', 
            style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text('سنوافيك بكل جديد هنا فور وصوله', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(String docId, Map<String, dynamic> note, bool isRead) {
    return InkWell(
      onTap: () {
        ZyiarahCoreService.triggerHapticLight();
        if (!isRead) {
          FirebaseFirestore.instance.collection('notifications').doc(docId).update({'isRead': true});
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isRead ? Colors.grey.shade100 : const Color(0xFFDBEAFE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRead ? const Color(0xFFF8FAFC) : const Color(0xFF2563EB).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRead ? Icons.notifications_none : Icons.notifications_active, 
                color: isRead ? Colors.grey : const Color(0xFF2563EB), 
                size: 20
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(note['title'] ?? 'تنبيه جديد', 
                        style: GoogleFonts.tajawal(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 15)),
                      if (!isRead)
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(note['body'] ?? '', 
                    style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _markAllAsRead(String? uid) async {
    if (uid == null) return;
    ZyiarahCoreService.triggerHapticSuccess();
    
    final batch = FirebaseFirestore.instance.batch();
    final notes = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in notes.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    
    await batch.commit();
  }
}
