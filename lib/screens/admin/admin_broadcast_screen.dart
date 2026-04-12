import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  String _target = 'all_users'; // all_users, drivers, clients
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("مركز البث الإداري", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoCard(),
              const SizedBox(height: 30),
              
              Text("الفئة المستهدفة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(height: 12),
              _buildTargetSelector(),
              
              const SizedBox(height: 30),
              _buildLuxuryField(controller: _titleCtrl, label: "عنوان الرسالة (مثلاً: تنبيه هام، عرض جديد)", icon: Icons.title_rounded),
              const SizedBox(height: 20),
              _buildLuxuryField(
                controller: _bodyCtrl, 
                label: "محتوى الرسالة...", 
                icon: Icons.chat_bubble_outline_rounded,
                maxLines: 5,
              ),
              
              const SizedBox(height: 40),
              _buildSendButton(),
              const SizedBox(height: 40),
              
              _buildRecentBroadcastsHeader(),
              const SizedBox(height: 15),
              _buildRecentBroadcastsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "سيتم إرسال هذه الرسالة فوراً للفئة المختارة وستظهر في مركز التنبيهات بداخل تطبيقاتهم.",
              style: GoogleFonts.tajawal(fontSize: 12, color: Colors.blue[900]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          _buildTargetOption("الجميع", 'all_users'),
          _buildTargetOption("العملاء", 'clients'),
          _buildTargetOption("الكوادر", 'drivers'),
        ],
      ),
    );
  }

  Widget _buildTargetOption(String label, String value) {
    final bool isSelected = _target == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _target = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              color: isSelected ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLuxuryField({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.tajawal(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF1E293B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: _isSending 
      ? const Center(child: CircularProgressIndicator())
      : ElevatedButton.icon(
          onPressed: _sendBroadcast,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 5,
            shadowColor: const Color(0xFF1E293B).withValues(alpha: 0.4),
          ),
          icon: const Icon(Icons.send_rounded),
          label: Text("إطلاق البث الموحد الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
    );
  }

  Future<void> _sendBroadcast() async {
    if (_titleCtrl.text.isEmpty || _bodyCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى كتابة العنوان والمحتوى")));
      return;
    }

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('broadcasts').add({
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'target': _target,
        'timestamp': FieldValue.serverTimestamp(),
        'sent_by': 'Admin',
      });

      if (mounted) {
        setState(() {
          _isSending = false;
          _titleCtrl.clear();
          _bodyCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("تم إطلاق البث بنجاح 🚀"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل البث: $e")));
      }
    }
  }

  Widget _buildRecentBroadcastsHeader() {
    return Row(
      children: [
        const Icon(Icons.history_rounded, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text("سجل عمليات البث الأخيرة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildRecentBroadcastsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('broadcasts').orderBy('timestamp', descending: true).limit(5).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        
        if (docs.isEmpty) return Center(child: Text("لا توجد عمليات بث سابقة", style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)));

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String targetLabel = data['target'] == 'all_users' ? 'الجميع' : (data['target'] == 'drivers' ? 'الكوادر' : 'العملاء');
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(data['title'] ?? '', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                        child: Text(targetLabel, style: TextStyle(color: Colors.blue[800], fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(data['body'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
