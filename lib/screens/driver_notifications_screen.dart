import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

class DriverNotificationsScreen extends StatelessWidget {
  const DriverNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('الإشعارات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: uid == null
            ? const Center(child: Text('يرجى تسجيل الدخول'))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userId', isEqualTo: uid)
                    .limit(50)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF5D1B5E)));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('تعذّر تحميل الإشعارات', style: GoogleFonts.tajawal(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  final docs = (snapshot.data?.docs ?? [])
                    ..sort((a, b) {
                      final aT = (a.data() as Map)['created_at'] as Timestamp?;
                      final bT = (b.data() as Map)['created_at'] as Timestamp?;
                      if (aT == null && bT == null) return 0;
                      if (aT == null) return 1;
                      if (bT == null) return -1;
                      return bT.compareTo(aT);
                    });

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none_outlined,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('لا توجد إشعارات بعد',
                              style: GoogleFonts.tajawal(
                                  color: Colors.grey, fontSize: 15)),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final data =
                          docs[i].data() as Map<String, dynamic>;
                      return _NotifCard(data: data);
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _NotifCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'إشعار جديد';
    final body = data['body'] as String? ?? '';
    final type = data['type'] as String? ?? '';
    final createdAt =
        (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeAgo = _formatTimeAgo(createdAt);
    final isRead = data['is_read'] as bool? ?? false;

    IconData icon;
    Color iconColor;

    switch (type) {
      case 'new_order':
        icon = Icons.add_task_rounded;
        iconColor = Colors.green;
        break;
      case 'order_cancelled':
        icon = Icons.cancel_outlined;
        iconColor = Colors.red;
        break;
      case 'driver_near':
      case 'driver_status':
        icon = Icons.directions_car_outlined;
        iconColor = Colors.blue;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColor = const Color(0xFF5D1B5E);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRead
              ? Colors.grey.shade100
              : const Color(0xFF5D1B5E).withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.tajawal(
                        fontWeight:
                            isRead ? FontWeight.w600 : FontWeight.bold,
                        fontSize: 13,
                        color: const Color(0xFF1E293B))),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(body,
                      style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.4)),
                ],
                const SizedBox(height: 4),
                Text(timeAgo,
                    style: GoogleFonts.tajawal(
                        fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ),
          if (!isRead)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF5D1B5E),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return DateFormat('yyyy/MM/dd').format(dt);
  }
}
