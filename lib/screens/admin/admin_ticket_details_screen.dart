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

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    
    try {
      // إشعار العميل يتولّاه خادميّاً مُشغّل sendNotificationOnTicketReply عند إضافة
      // رسالة senderRole:'admin' (يعمل الآن لكل من تطبيق الأدمن ولوحة الويب). كان
      // الاستدعاء المباشر notifyUserOfSupportReply هنا يُنتج إشعاراً ثانياً مكرّراً.
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
    // كان بلا try/catch: فشل الكتابة (أوفلاين/صلاحية) يُلقى غير مُلتقَط لكن الشاشة
    // تُغلَق فيظنّ الأدمن أن التذكرة حُلّت. نُغلق فقط عند النجاح مع تنبيه عند الفشل.
    try {
      await _db.collection('support_tickets').doc(widget.ticketId).update({
        'status': 'resolved',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إغلاق التذكرة، حاول مجدداً')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("محادثة التذكرة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
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
                      final isUser = senderRole != 'admin';

                      // RTL Logic: Me (Admin) on the Right, Other (User) on the Left
                      final isMe = !isUser;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(15),
                              topRight: const Radius.circular(15),
                              bottomLeft: isMe ? const Radius.circular(15) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(15),
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2))
                            ],
                            border: Border.all(color: isMe ? Colors.transparent : Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['text'] ?? '',
                                style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg['sentAt'] != null
                                  ? "${(msg['sentAt'] as Timestamp).toDate().hour.toString().padLeft(2, '0')}:${(msg['sentAt'] as Timestamp).toDate().minute.toString().padLeft(2, '0')}"
                                  : "...",
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey, 
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
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
