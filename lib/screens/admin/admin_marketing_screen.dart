import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/admin/admin_coupons_screen.dart';
import 'package:zyiarah/screens/admin/admin_banners_screen.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';

class AdminMarketingScreen extends StatefulWidget {
  const AdminMarketingScreen({super.key});

  @override
  State<AdminMarketingScreen> createState() => _AdminMarketingScreenState();
}

class _AdminMarketingScreenState extends State<AdminMarketingScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  bool _isSending = false;
  bool _isScheduled = false;
  DateTime? _scheduledTime;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(minutes: 10)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  void _sendNotification() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال عنوان ونص الإشعار')));
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
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          target: 'all_users',
          scheduledAt: _scheduledTime!,
          createdBy: 'Marketing',
        );
      } else {
        // 1. تسجيل العملية في سجل الإشعارات
        await FirebaseFirestore.instance.collection('notifications_log').add({
          'title': _titleController.text,
          'body': _bodyController.text,
          'target': 'all',
          'created_at': FieldValue.serverTimestamp(),
          'type': 'marketing_broadcast',
        });

        // 2. إرسال أمر بربط الإشعار بنظام التنبيهات (Broadcast Trigger)
        await FirebaseFirestore.instance.collection('notification_triggers').add({
          'userId': 'broadcast_all',
          'title': _titleController.text,
          'body': _bodyController.text,
          'type': 'marketing_broadcast',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isScheduled ? "تم جدولة إشعار الحملة بنجاح! 📅" : 'تم إرسال الإشعار لجميع المستخدمين بنجاح! ✅'),
        backgroundColor: Colors.green,
      ));
      
      setState(() {
        if (!_isScheduled) {
          _titleController.clear();
          _bodyController.clear();
        }
        _isScheduled = false;
        _scheduledTime = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ جذري أثناء الإرسال: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("التسويق والإشعارات", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.campaign, size: 80, color: Color(0xFF1E293B)),
            const SizedBox(height: 20),
            _buildMarketingButton(
              title: "إدارة أكواد الخصم (Coupons)",
              icon: Icons.local_offer,
              color: const Color(0xFFE11D48),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCouponsScreen())),
            ),
            const SizedBox(height: 15),
            _buildMarketingButton(
              title: "إدارة البنرات الإعلانية (Banners)",
              icon: Icons.view_carousel,
              color: const Color(0xFF2563EB),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBannersScreen())),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),
            Text(
              "إرسال إشعار للجميع (Push Notification)",
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            _buildLuxuryField(controller: _titleController, label: "عنوان الإشعار", icon: Icons.title, enabled: !_isSending),
            const SizedBox(height: 20),
            _buildLuxuryField(controller: _bodyController, label: "نص العرض أو رسالة الإشعار", icon: Icons.chat_bubble_outline, maxLines: 4, enabled: !_isSending),
            const SizedBox(height: 30),
            
            _buildSchedulingSection(),
            
            const SizedBox(height: 30),
            if (_isSending)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: LinearProgressIndicator(color: Color(0xFF1E293B)),
              ),
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendNotification,
              icon: Icon(_isScheduled ? Icons.watch_later_rounded : Icons.send),
              label: Text(_isSending ? "جاري الإرسال..." : (_isScheduled ? "جدولة الإشعار الآن" : "إرسال الآن"), 
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketingButton({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color),
      label: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: color, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildLuxuryField({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1, bool enabled = true}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      style: GoogleFonts.tajawal(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1E293B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSchedulingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isScheduled ? Colors.blue.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isScheduled ? Colors.blue.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month, color: _isScheduled ? Colors.blue : Colors.grey),
                  const SizedBox(width: 10),
                  Text("جدولة الإرسال لوقت لاحق", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _isScheduled ? Colors.blue : Colors.grey[700])),
                ],
              ),
              Switch(
                value: _isScheduled,
                onChanged: (val) => setState(() => _isScheduled = val),
                activeColor: Colors.blue,
              ),
            ],
          ),
          if (_isScheduled) ...[
            const Divider(),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.blue.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: Colors.blue, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _scheduledTime == null ? "تحديد التاريخ والوقت" : intl.DateFormat('yyyy/MM/dd HH:mm').format(_scheduledTime!),
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
