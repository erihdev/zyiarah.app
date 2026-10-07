import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/ticket_authorship.dart';
import 'package:zyiarah/utils/time_format.dart';

class ZyiarahSupportScreen extends StatefulWidget {
  const ZyiarahSupportScreen({super.key});

  @override
  State<ZyiarahSupportScreen> createState() => _ZyiarahSupportScreenState();
}

class _ZyiarahSupportScreenState extends State<ZyiarahSupportScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  // وحدة تحكّم ردّ مستقلّة لكل تذكرة — كانت وحدة واحدة مشتركة، فيتسرّب نصّ إحدى
  // التذاكر المفتوحة إلى الأخرى ويمحو clear() مسوّدتها.
  final Map<String, TextEditingController> _replyControllers = {};
  bool _isSending = false;

  /// يُبدَّلُ فيُعادُ الاشتراكُ ببثٍّ جديد — زرُّ «إعادة المحاولة».
  int _reloadKey = 0;

  TextEditingController _replyCtrlFor(String ticketId) =>
      _replyControllers.putIfAbsent(ticketId, () => TextEditingController());

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("تذاكر الدعم الفني", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: "التذاكر النشطة"),
              Tab(text: "السجلات السابقة"),
            ],
          ),
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: TabBarView(
            children: [
              _buildTicketList(user, ['open', 'replied']),
              _buildTicketList(user, ['resolved', 'closed']),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showNewTicketDialog(context),
          label: const Text("تذكرة جديدة"),
          icon: const Icon(Icons.add),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
        ),
      ),
    ),
  );
  }

  Widget _buildTicketList(User? user, List<String> statuses) {
    return StreamBuilder<QuerySnapshot>(
      // `_reloadKey` يُعيدُ بناءَ هذا `StreamBuilder` بمفتاحٍ جديدٍ فيُعادُ
      // الاشتراكُ — فزرُّ «إعادة المحاولة» يُحاولُ فعلاً. و`firstEventTimeout`
      // لا تُغلِقُ البثَّ عند الخطأ، فبياناتٌ متأخّرةٌ تَشفي الشاشةَ بنفسِها
      // كذلك؛ الزرُّ لِمن لا تَنتظر.
      key: ValueKey('tickets-${statuses.join(',')}-$_reloadKey'),
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .where('userId', isEqualTo: user?.uid)
          .where('status', whereIn: statuses)
          .snapshots()
            .firstEventTimeout(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // **كان «خطأ: ${snapshot.error}» (2026-10-07).** نصُّ الاستثناءِ
          // خامّاً في وجهِ العميلةِ — «[cloud_firestore/permission-denied]
          // Missing or insufficient permissions.» أو «TimeoutException after
          // 0:00:20.000000: Future not completed» — بحرفٍ لاتينيٍّ في واجهةٍ
          // عربيّةٍ، على الشاشةِ التي فتحَتها لأنّ شيئاً أعطبَها أصلاً. ولا
          // زرَّ إعادةٍ معه، فالقائمةُ تَبقى نصَّ خطأٍ لا مَخرجَ منه.
          //
          // وحارسُ «لا نصَّ استثناءٍ خامّاً» لم يَرَهُ: نطاقُه كتلةُ
          // `showSnackBar(...)`، والحاملُ هنا `Text` مرسومٌ في الصفحة —
          // فالقاعدةُ عامّةٌ والكاشفُ كان على حاملٍ واحد. وُسِّعَ في
          // `net_timeout_guard_test`.
          debugPrint('support tickets stream error: ${snapshot.error}');
          return _buildLoadError();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var tickets = snapshot.data?.docs ?? [];

        if (tickets.isEmpty) {
          return _buildEmptyState(statuses.contains('open'));
        }

        // Sort locally
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
    );
  }

  /// فشلُ تحميلِ القائمةِ: جملةٌ عربيّةٌ وزرٌّ يُعيدُ المحاولة — لا نصُّ
  /// استثناءٍ خامّ. والصياغةُ هي صياغةُ `offers_screen._inlineError` نفسُها
  /// («تعذّر تحميل …، تحقّقي من الاتصال») فلا جملةَ رابعةً لنفسِ الحالة.
  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'تعذّر تحميل التذاكر، تحقّقي من الاتصال',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() => _reloadKey++),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF660033),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isActive) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isActive ? Icons.support_agent : Icons.history_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            isActive ? "لا توجد تذاكر نشطة حالياً" : "لا توجد سجلات سابقة",
            style: const TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          if (isActive) ...[
            const SizedBox(height: 10),
            const Text("اضغطي على الزر أدناه لفتح تذكرة جديدة", style: TextStyle(color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketCard(String id, Map<String, dynamic> data) {
    final status = data['status'] ?? 'open';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final formattedDate = '${intl.DateFormat('yyyy/MM/dd').format(createdAt)} '
        '${formatTime12(createdAt)}';

    Color statusColor = Colors.orange;
    String statusText = "قيد المراجعة";

    if (status == 'replied') {
      statusColor = Colors.green;
      statusText = "تم الرد";
    } else if (status == 'resolved') {
      // كانت resolved تسقط للحالة الافتراضية «قيد المراجعة» رغم عرضها في سجل التذاكر.
      statusColor = Colors.teal;
      statusText = "تم الحل";
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
    bool isSendingReply = false;
    final replyCtrl = _replyCtrlFor(ticketId);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(ticketId)
          .collection('messages')
          .orderBy('sentAt', descending: false)
          .snapshots()
            .firstEventTimeout(),
      builder: (context, snapshot) {
        // خطأ البث كان يُخفي المحادثة وصندوق الرد معاً بصمت (SizedBox فارغ).
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('تعذّر تحميل الرسائل',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                // setState يعيد بناء الاستعلام فيُعاد الاشتراك بالبث.
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('إعادة المحاولة',
                      style: TextStyle(color: Color(0xFF660033))),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          // تمييز التحميل عن «لا رسائل» — كان كلاهما فراغاً.
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final messages = snapshot.data!.docs;

        return StatefulBuilder(
          builder: (context, setInternalState) {
            return Column(
              children: [
                ...messages.map((doc) {
                  final m = doc.data() as Map<String, dynamic>;
                  // القاعدةُ المشترَكةُ — والمالكُ هنا هي نفسُها.
                  final isAdmin = ticketMessageIsFromTeam(
                      m, FirebaseAuth.instance.currentUser?.uid);

                  return Align(
                    alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      decoration: BoxDecoration(
                        color: isAdmin ? const Color(0xFFF1F5F9) : const Color(0xFF660033),
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
                            formatTime12((m['sentAt'] as Timestamp?)?.toDate() ??
                                (m['timestamp'] as Timestamp?)?.toDate() ??
                                DateTime.now()),
                            style: TextStyle(
                              fontSize: 9, 
                              color: isAdmin ? Colors.grey : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: replyCtrl,
                        decoration: InputDecoration(
                          hintText: "اكتبي ردك هنا...",
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    isSendingReply 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF660033)),
                          onPressed: () async {
                            final text = replyCtrl.text.trim();
                            if (text.isEmpty) return;
                            
                            setInternalState(() => isSendingReply = true);
                            try {
                              await FirebaseFirestore.instance
                                  .collection('support_tickets')
                                  .doc(ticketId)
                                  .collection('messages')
                                  .add({
                                    'senderId': FirebaseAuth.instance.currentUser?.uid,
                                    'senderRole': 'user',
                                    'text': text,
                                    'sentAt': FieldValue.serverTimestamp(),
                                  });

                              await FirebaseFirestore.instance
                                  .collection('support_tickets')
                                  .doc(ticketId)
                                  .update({
                                    'status': 'open',
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });

                              replyCtrl.clear();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('فشل إرسال الرسالة، حاولي مجدداً')),
                                );
                              }
                            } finally {
                              // BUG-003: setInternalState هنا يقع بعد انتظارَين
                              // شبكيَّين. لو أغلق المستخدم البطاقة أو انتقل خلالهما
                              // صار عنصر StatefulBuilder مُتلَفاً، فينفجر
                              // «setState() called after dispose()». الحارس يجعل
                              // الفشل صامتاً بلا أثر بدل استثناء في Crashlytics.
                              if (context.mounted) {
                                setInternalState(() => isSendingReply = false);
                              }
                            }
                          },
                        ),
                  ],
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showNewTicketDialog(BuildContext context) {
    // خارج builder الـ sheet لا داخله: الـ builder يقرأ viewInsets فيُعاد استدعاؤه
    // مع كل حركة كيبورد، وكان إعلان المتغيّر داخله يصفّره مجدداً فيختفي المؤشّر
    // ويعود الزر للعمل ظاهرياً أثناء الإرسال (والضغطة الثانية تُبتلع صامتة).
    bool sheetSending = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Directionality(
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
              // StatefulBuilder: الزر داخل الـ sheet لا يُعاد بناؤه على setState الأب،
              // فكان لا يُظهر مؤشّر التحميل ولا يتعطّل بصريّاً أثناء الإرسال.
              StatefulBuilder(
                builder: (context, setSheetState) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF660033),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: sheetSending
                          ? null
                          : () => _submitTicket(context, (v) => setSheetState(() => sheetSending = v)),
                      child: sheetSending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("إرسال التذكرة", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
        );
      },
    );
  }

  void _submitTicket(BuildContext sheetContext, [void Function(bool)? setSending]) async {
    if (_isSending) return; // حارس ضدّ الإرسال المزدوج
    if (_subjectController.text.isEmpty || _messageController.text.isEmpty) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text("يرجى ملء جميع الحقول")));
      return;
    }

    setSending?.call(true);
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

      // إغلاق الـ BottomSheet بسياقه الخاص، ثم SnackBar بسياق الشاشة الأم
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      _subjectController.clear();
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إرسال التذكرة بنجاح")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تعذّر إرسال الرسالة — أعيدي المحاولة")));
      }
    } finally {
      setSending?.call(false);
      if (mounted) setState(() => _isSending = false);
    }
  }
}
