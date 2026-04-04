import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminTicketDetailsScreen extends StatefulWidget {
  final String ticketId;

  const AdminTicketDetailsScreen({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailsScreen> createState() => _AdminTicketDetailsScreenState();
}

class _AdminTicketDetailsScreenState extends State<AdminTicketDetailsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _replyCtrl = TextEditingController();
  bool _isSending = false;

  void _sendMessage() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    
    try {
      await _db.collection('support_tickets').doc(widget.ticketId).collection('messages').add({
        'text': text,
        'senderRole': 'admin',
        'sentAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('support_tickets').doc(widget.ticketId).update({
        'status': 'replied',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _replyCtrl.clear();
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال الرد')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _closeTicket() async {
    await _db.collection('support_tickets').doc(widget.ticketId).update({
      'status': 'Resolved',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("محادثة التذكرة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          actions: [
            TextButton.icon(
              onPressed: _closeTicket, 
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
              label: const Text("إغلاق التذكرة", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('support_tickets').doc(widget.ticketId).collection('messages').orderBy('sentAt', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) return const Center(child: Text("لا توجد رسائل حتى الآن", style: TextStyle(color: Colors.grey)));

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(15),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final msg = docs[index].data() as Map<String, dynamic>;
                      final senderRole = msg['senderRole'] ?? '';
                      final sender = msg['sender'] ?? ''; // Legacy
                      final isUser = senderRole != 'admin' && sender != 'admin';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.white : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isUser ? Colors.grey.shade300 : Colors.transparent),
                          ),
                          child: Text(
                            msg['text'] ?? '',
                            style: TextStyle(color: isUser ? Colors.black : Colors.white),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      decoration: const InputDecoration(
                        hintText: "اكتب ردك هنا...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  _isSending 
                    ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())
                    : IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF1E293B)),
                        onPressed: _sendMessage,
                      ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
