import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

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
  
  bool _isScheduled = false;
  DateTime? _scheduledTime;

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

              _buildTemplateBar(),
              const SizedBox(height: 30),
              
              Text("الفئة المستهدفة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(height: 12),
              _buildTargetSelector(),
              
              const SizedBox(height: 30),
              _buildLuxuryField(controller: _titleCtrl, label: "عنوان الرسالة (مثلاً: تنبيه هام، عرض جديد)", icon: Icons.title_rounded),
              const SizedBox(height: 30),
              _buildLuxuryField(
                controller: _bodyCtrl, 
                label: "محتوى الرسالة...", 
                icon: Icons.chat_bubble_outline_rounded,
                maxLines: 5,
              ),
              
              const SizedBox(height: 30),
              _buildSchedulingSection(),
              
              const SizedBox(height: 40),
              _buildSendButton(),
              const SizedBox(height: 40),

              _buildScheduledQueueHeader(),
              const SizedBox(height: 15),
              _buildScheduledQueueList(),
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

  Widget _buildSchedulingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _isScheduled ? const Color(0xFF1E293B).withValues(alpha: 0.1) : Colors.transparent),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: (_isScheduled ? const Color(0xFF1E293B) : Colors.grey).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.schedule_send_rounded, color: _isScheduled ? const Color(0xFF1E293B) : Colors.grey, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text("جدولة الإرسال لاحقاً", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _isScheduled ? const Color(0xFF1E293B) : Colors.grey[700], fontSize: 14)),
                ],
              ),
              Switch.adaptive(
                value: _isScheduled,
                activeTrackColor: const Color(0xFF1E293B).withValues(alpha: 0.5),
                activeThumbColor: const Color(0xFF1E293B),
                onChanged: (val) {
                  setState(() {
                    _isScheduled = val;
                    if (!val) {
                      _scheduledTime = null;
                    }
                  });
                },
              ),
            ],
          ),
          if (_isScheduled) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Divider(),
            ),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(15),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Color(0xFF1E293B), size: 22),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        _scheduledTime == null ? "اختر التاريخ والوقت" : intl.DateFormat('yyyy/MM/dd | HH:mm').format(_scheduledTime!),
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _scheduledTime == null ? Colors.grey : const Color(0xFF1E293B)),
                      ),
                    ),
                    const Icon(Icons.edit_calendar_rounded, color: Colors.grey, size: 18),
                  ],
                ),
              ),
            ),
            if (_scheduledTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "سيتم إطلاق البث تلقائياً في الموعد المختار.\nتأكد من بقاء الخادم نشطاً أو الجدولة المسبقة.",
                        style: GoogleFonts.tajawal(fontSize: 10, color: Colors.blue[800], height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
          ]
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(minutes: 10)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E293B), // استخدام لون العلامة التجارية
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1E293B),
                textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF1E293B),
                onPrimary: Colors.white,
                onSurface: Color(0xFF1E293B),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1E293B),
                  textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            child: child!,
          );
        },
      );
      if (time != null) {
        setState(() {
          _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  Widget _buildTemplateBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("قوالب سريعة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _templateChip("📢 تنبيه عام", "تنبيه هام من زيارة", "نود إفادتكم بوجود تحديثات جديدة في النظام لخدمتكم بشكل أفضل."),
              _templateChip("🛍️ عرض خصم", "خصم خاص في انتظاركم! 🎁", "استمتع بخصم حصري ومحدود بمناسبة التوسعات الجديدة. استخدم الكود: ZYIARAH10"),
              _templateChip("🔧 صيانة", "أعمال صيانة مجدولة", "سنقوم ببعض أعمال الصيانة لتحسين جودة الخدمة، خدماتنا ستعود للعمل بكفاءة خلال وقت قصير."),
            ],
          ),
        ),
      ],
    );
  }

  Widget _templateChip(String label, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ActionChip(
        label: Text(label, style: GoogleFonts.tajawal(fontSize: 12)),
        onPressed: () {
          setState(() {
            _titleCtrl.text = title;
            _bodyCtrl.text = body;
          });
        },
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
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
          icon: Icon(_isScheduled ? Icons.calendar_today_rounded : Icons.send_rounded),
          label: Text(_isScheduled ? "جدولة عملية البث" : "إطلاق البث الموحد الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
    );
  }

  Future<void> _sendBroadcast() async {
    if (_titleCtrl.text.isEmpty || _bodyCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى كتابة العنوان والمحتوى")));
      return;
    }

    if (_isScheduled && (_scheduledTime == null || _scheduledTime!.isBefore(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار موعد مستقبلي صالح للجدولة")));
      return;
    }

    setState(() => _isSending = true);

    try {
      if (_isScheduled) {
        await ZyiarahNotificationTriggerService().scheduleBroadcast(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          target: _target,
          scheduledAt: _scheduledTime!,
        );
      } else {
        // 1. تسجيل العملية في سجل البث (History)
        await FirebaseFirestore.instance.collection('broadcasts').add({
          'title': _titleCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'target': _target,
          'timestamp': FieldValue.serverTimestamp(),
          'sent_by': 'Admin',
        });

        // 2. إطلاق التنبيه الفعلي لنظام الإشعارات (Backend Trigger)
        // التحويل للفئة التي يتوقعها الـ Cloud Function
        final String mappedTarget = _target == 'all_users' ? 'all' : _target;
        
        await FirebaseFirestore.instance.collection('notifications_log').add({
          'title': _titleCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'target': mappedTarget,
          'created_at': FieldValue.serverTimestamp(),
          'type': 'admin_broadcast',
        });
      }

      if (mounted) {
        ZyiarahCoreService.triggerHapticSuccess();
        setState(() {
          _isSending = false;
          if (!_isScheduled) {
            _titleCtrl.clear();
            _bodyCtrl.clear();
          }
          _isScheduled = false;
          _scheduledTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isScheduled ? "تم جدولة البث بنجاح" : "تم إطلاق البث بنجاح 🚀"),
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

  Widget _buildScheduledQueueHeader() {
    return Row(
      children: [
        const Icon(Icons.watch_later_outlined, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text("قائمة الإشعارات المجدولة القادمة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.blue[800])),
      ],
    );
  }

  Widget _buildScheduledQueueList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('scheduled_notifications')
          .where('isProcessed', isEqualTo: false)
          .orderBy('scheduled_at', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100)),
            child: Center(child: Text("لا توجد إشعارات مجدولة حالياً", style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12))),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final DateTime? sched = (data['scheduled_at'] as Timestamp?)?.toDate();
            final String timeStr = sched != null ? intl.DateFormat('yyyy/MM/dd HH:mm').format(sched) : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['title'] ?? '', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(timeStr, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                    onPressed: () => _deleteScheduled(doc.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteScheduled(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('scheduled_notifications').doc(docId).delete();
      if (mounted) {
        ZyiarahCoreService.triggerHapticSuccess();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إلغاء الإشعار المجدول بنجاح")));
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الإلغاء: $e")));
    }
  }
}
