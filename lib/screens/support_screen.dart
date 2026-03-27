import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahSupportScreen extends StatefulWidget {
  const ZyiarahSupportScreen({super.key});

  @override
  State<ZyiarahSupportScreen> createState() => _ZyiarahSupportScreenState();
}

class _ZyiarahSupportScreenState extends State<ZyiarahSupportScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("تذاكر الدعم الفني", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_tickets')
              .where('userId', isEqualTo: user?.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("خطأ: ${snapshot.error}"));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            var tickets = snapshot.data?.docs ?? [];

            if (tickets.isEmpty) {
              return _buildEmptyState();
            }

            // Sort locally to avoid requiring a Firestore composite index
            tickets = tickets.toList()..sort((a, b) {
              final aMap = a.data() as Map<String, dynamic>;
              final bMap = b.data() as Map<String, dynamic>;
              final aDate = (aMap['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
              final bDate = (bMap['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
              return bDate.compareTo(aDate);
            });

            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: tickets.length,
              separatorBuilder: (context, index) => const SizedBox(height: 15),
              itemBuilder: (context, index) {
                final ticket = tickets[index].data() as Map<String, dynamic>;
                final ticketId = tickets[index].id;
                return _buildTicketCard(ticketId, ticket);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewTicketDialog(context),
        label: const Text("تذكرة جديدة"),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.support_agent, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          const Text(
            "لا توجد لديك تذاكر دعم حالياً",
            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text("اضغط على الزر أدناه لفتح تذكرة جديدة", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTicketCard(String id, Map<String, dynamic> data) {
    final status = data['status'] ?? 'open';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final formattedDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(createdAt);

    Color statusColor = Colors.orange;
    String statusText = "قيد المراجعة";

    if (status == 'replied') {
      statusColor = Colors.green;
      statusText = "تم الرد";
    } else if (status == 'closed') {
      statusColor = Colors.grey;
      statusText = "مغلقة";
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        title: Text(data['subject'] ?? "بدون عنوان", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Text(formattedDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMessagesList(id),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(String ticketId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(ticketId)
          .collection('messages')
          .orderBy('sentAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final messages = snapshot.data!.docs;

        return Column(
          children: messages.map((doc) {
            final m = doc.data() as Map<String, dynamic>;
            final isAdmin = m['senderId'] == 'admin';
            return Align(
              alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: isAdmin ? const Color(0xFFF1F5F9) : const Color(0xFF5D1B5E),
                  borderRadius: BorderRadius.circular(16).copyWith(
                    topLeft: isAdmin ? const Radius.circular(0) : const Radius.circular(16),
                    topRight: isAdmin ? const Radius.circular(16) : const Radius.circular(0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['text'] ?? "",
                      style: TextStyle(color: isAdmin ? Colors.black87 : Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      intl.DateFormat('HH:mm').format((m['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now()),
                      style: TextStyle(
                        fontSize: 9, 
                        color: isAdmin ? Colors.grey : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showNewTicketDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 30,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("فتح تذكرة دعم جديدة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: "العنوان (مثلاً: مشكلة في الدفع)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "تفاصيل المشكلة",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D1B5E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: _isSending ? null : () => _submitTicket(context),
                  child: _isSending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("إرسال التذكرة", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  void _submitTicket(BuildContext context) async {
    if (_subjectController.text.isEmpty || _messageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى ملء جميع الحقول")));
      return;
    }

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final ticketRef = FirebaseFirestore.instance.collection('support_tickets').doc();

      await ticketRef.set({
        'userId': user?.uid,
        'userEmail': user?.email,
        'subject': _subjectController.text,
        'lastMessage': _messageController.text,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await ticketRef.collection('messages').add({
        'senderId': user?.uid,
        'text': _messageController.text,
        'sentAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        Navigator.pop(context);
        _subjectController.clear();
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إرسال التذكرة بنجاح")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الإرسال: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}
