import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/utils/deletion_log_row.dart';

// StatefulWidget كي تعمل «إعادة المحاولة» بإعادة إنشاء التدفق عند فشل القراءة.
class AdminDeletionsScreen extends StatefulWidget {
  const AdminDeletionsScreen({super.key});

  @override
  State<AdminDeletionsScreen> createState() => _AdminDeletionsScreenState();
}

class _AdminDeletionsScreenState extends State<AdminDeletionsScreen> {
  // **البثُّ يُبنى مرّةً واحدةً، لا في كلِّ `build`.** كان يُنشأُ داخلَ دالّةِ
  // البناءِ، فكلُّ `setState` — حرفٌ في حقلِ البحثِ، تبديلُ مُرشِّح، فتحُ
  // حوار — يُلغي مستمِعَ Firestore ويُنشئُ غيرَه. والبياناتُ لا تَختفي
  // (`StreamBuilder` يَحفظُ آخرَ لقطةٍ عبرَ إعادةِ الاشتراك) فلا يُرى شيء،
  // والكلفةُ حقيقيّة — **والأثرُ الأخطرُ أنّ `firstEventTimeout` تُستأنف**:
  // على وصلةٍ تَبدو قائمةً ولا تَنفُذ (بوّابةُ فندقٍ، وكيلٌ شفّاف) تُعادُ
  // مهلةُ العشرينَ ثانيةً مع كلِّ حرفٍ يُكتَب، فلا يُبلَغُ فرعُ الخطأِ ولا
  // زرُّ إعادتِه أبداً — وهو العطلُ بعينِه الذي وُجدت المهلةُ لأجلِه.
  // والقاعدةُ مقرَّرةٌ في `driver_tasks_screen` ومُنفَّذةٌ فيه وحدَه.
  //
  // وإعادةُ المحاولةِ كانت تَعتمدُ على ذلك الأثرِ الجانبيِّ عينِه، فصارت
  // صريحةً: تَصفيرُ الحقلِ يَجعلُ البناءَ التاليَ يَفتحُ بثّاً جديداً.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _requests;
  Stream<QuerySnapshot<Map<String, dynamic>>> get _requestsStream =>
      _requests ??= FirebaseFirestore.instance
          .collection('account_deletions')
          .orderBy('requested_at', descending: true)
          .limit(300)
          .snapshots()
          .firstEventTimeout();

  void _reopenRequests() => setState(() => _requests = null);

  /// **زرُّ إعادةِ المحاولة — المَخرَجُ الذي لم يَكن للفشل.**
  ///
  /// الخادمُ يَكتبُ `failed_deletion` ويَقولُ السطحانِ «يتطلب مراجعة»
  /// **بلا إجراء**: الأزرارُ كلُّها محصورةٌ بـ`status == 'pending'` ولا
  /// كاتبَ لها في المستودع (المساراتُ الأربعةُ تَكتبُ `'deleted'` مباشرةً)،
  /// فالمَخرَجُ الوحيدُ كان تعديلَ Firestore بيدٍ — على مسارٍ يَلزمُه
  /// متطلّبُ آبل وقد يَكونُ حسابُ المصادقةِ ما زال حيّاً.
  ///
  /// وزرُّ «رفض» وشقيقُه «حذف» **لم يُمَسّا**: قرارُ مالكٍ مسجَّلٌ
  /// (2026-07-21، «رفض الطلب بدل الحذف الإجباري») يَحرُسُه
  /// `admin_ban_reject_test`. وأنّهما غيرُ قابلَي الوصولِ حقيقةٌ مشدودةٌ في
  /// `account_deletion_log_test` لا قراراً يُنقَض هنا.
  ///
  /// وإعادةُ كتابةِ `'deleted'` هي المُشغِّلُ نفسُه:
  /// `onAccountDeletionStatusChanged` شرطُه `before.status !== 'deleted'`
  /// وهو مُستوفًى من `failed_deletion` — فلا آليّةَ جديدة.
  Widget _retryButton(BuildContext context, String docId, String identity) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF660033),
        side: const BorderSide(color: Color(0xFF660033)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text("إعادة المحاولة"),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text("إعادة محاولة الحذف",
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: Text("إعادة تشغيل حذف حساب $identity خادمياً؟ "
                  "الحذف لا رجعة فيه: حساب الدخول ومستند المستخدم ورموز "
                  "الإشعارات تُمسح، والرصيد المتبقّي يُسجَّل ديناً للتسوية "
                  "اليدوية."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("إلغاء")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("إعادة المحاولة")),
              ],
            ),
          ),
        );
        if (ok != true) return;
        try {
          await FirebaseFirestore.instance
              .collection('account_deletions')
              .doc(docId)
              .update({'status': 'deleted'});
          await ZyiarahAuditService().logAction(
            action: ZyiarahAuditService.actionProcessAccountDeletion,
            details: {'account': identity, 'decision': 'retry'},
            targetId: docId,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("أُعيد تشغيل الحذف — تابع الحالة بعد ثوانٍ.")));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("تعذّرت إعادة المحاولة: $e")));
          }
        }
      },
    );
  }

  // (دمج من لوحة الويب) رفض طلب حذف الحساب — بدل إجبار الأدمن على الحذف أو تركه معلّقاً.
  // يضبط status='rejected' (الشاشة تعرضه أصلاً). لا يُحذف الحساب.
  Widget _rejectButton(BuildContext context, String docId) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF64748B),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text("رفض طلب الحذف",
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              content: const Text(
                  "رفض طلب حذف هذا الحساب؟ لن يُحذف الحساب — سيُعلَّم الطلب كمرفوض فقط."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("إلغاء")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("رفض")),
              ],
            ),
          ),
        );
        if (ok == true) {
          try {
            await FirebaseFirestore.instance
                .collection('account_deletions')
                .doc(docId)
                .update({'status': 'rejected'});
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم رفض طلب الحذف.")));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text("فشل: $e")));
            }
          }
        }
      },
      child: const Text("رفض"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلبات حذف الحسابات", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF660033), // Red
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          // نافذة محدودة (300) مثل لوحة الويب — لا نحمّل الأرشيف كله في بثّ حي.
          stream: _requestsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            // فشل القراءة كان يظهر كقائمة فارغة نظيفة — خطر على مهلة معالجة
            // طلبات الحذف (متطلب Apple)، فنعرض خطأً صريحاً بإعادة محاولة.
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 10),
                    const Text("تعذّر تحميل طلبات حذف الحسابات", style: TextStyle(color: Colors.red)),
                    TextButton(
                      onPressed: _reopenRequests,
                      child: const Text("إعادة المحاولة", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات حذف حساب حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final req = doc.data() as Map<String, dynamic>;
                final status = req['status'] as String? ?? 'pending';
                // زر الحذف/الرفض يظهر فقط للحالة pending (قرارُ مالكٍ
                // 2026-07-21 يَحرُسُه `admin_ban_reject_test`) — **ولا كاتبَ
                // لها في المستودع**، فهذان سجلٌّ لا إجراء. والحقيقةُ
                // مشدودةٌ في `account_deletion_log_test`، وما يَلزمُ فعلاً
                // هو مَخرَجُ الفشلِ أدناه لا نقضُ ذلك القرار.
                final isPending = status == 'pending';
                // **التسميةُ من القاعدةِ المشترَكة** — كانت تعداداً هنا
                // وثانياً في اللوحة، وافترقا: `'deleted'` يُقرأُ هنا «جاري
                // المسح» (صحيح) وفي اللوحةِ «تم الحذف نهائياً» بعلامةٍ
                // خضراءَ، وهو «سُجِّلَ والخادمُ يَعملُ عليه» وقد يَعلَق.
                final state = deletionRequestState(req['status']);
                final DateTime? requestedAt =
                    (req['requested_at'] as Timestamp?)?.toDate();
                final bool canRetry = deletionRetryAllowed(
                    state: state,
                    requestedAt: requestedAt,
                    now: DateTime.now());
                final statusText = deletionStateLabel(state);
                final String? failureReason = deletionFailureReason(req);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.no_accounts, color: Colors.white)),
                    title: Text(deletionRowIdentity(req), style: const TextStyle(fontWeight: FontWeight.bold)),
                    // **سطرُ الدَّين.** `wallet_balance_at_deletion` يَكتبُه
                    // الخادمُ «كي يبقى الدَّينُ مكتوباً في مكانٍ يَقرؤه
                    // البشرُ» — وكان مكتوباً في موضعٍ **ومقروءاً في صفر**.
                    subtitle: Text([
                      "السبب: ${req['reason'] ?? 'غير محدد'}",
                      // `requestedAt` نفسُها: التحويلُ الصلبُ `as Timestamp`
                      // كان يَرمي على قيمةٍ نصّيّةٍ (مستندٌ كُتبَ بيدٍ في
                      // الكونسول — مسارٌ موثَّقٌ في هذا المشروع).
                      if (requestedAt != null)
                        "تاريخ الطلب: ${requestedAt.toString().split(' ')[0]}",
                      "الحالة: $statusText",
                      // سببُ الفشلِ كما كتبَه الخادمُ — كان بلا قارئٍ في
                      // أيِّ سطح، فـ«يتطلب مراجعة» بلا ما يُراجَع. واسمُه
                      // «سبب الفشل» لا «السبب»: الأوّلُ فوقَه سببُ العميلة.
                      if (failureReason != null) "سبب الفشل: $failureReason",
                      if (deletionStrandedNotice(req) != null)
                        deletionStrandedNotice(req)!,
                    ].join('\n')),
                    isThreeLine: true,
                    // الترتيبُ: إعادةُ المحاولةِ أوّلاً (فهي الإجراءُ
                    // القابلُ للوصولِ فعلاً)، ثمّ زوجُ `pending` كما تَركَه
                    // قرارُ المالك، وإلّا التسمية. ولا تقاطُع: `'pending'`
                    // تُقرأُ `unknown` و`canRetry` تَرفُضُ الجهلَ.
                    trailing: canRetry
                        ? _retryButton(
                            context, doc.id, deletionRowIdentity(req))
                        : !isPending
                        ? Text(
                            statusText,
                            style: TextStyle(
                              color: state == DeletionRequestState.completed
                                  ? Colors.green
                                  : state == DeletionRequestState.failed ||
                                          state == DeletionRequestState.rejected
                                      ? Colors.red
                                      : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _rejectButton(context, doc.id),
                              const SizedBox(width: 4),
                              ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: Text("تأكيد الحذف النهائي", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                                    content: const Text("هل أنت متأكد من حذف هذا الحساب نهائياً؟ ستتم إزالة بيانات المستخدم والملف الشخصي FCM والرمز المميز وكلمة المرور فوراً عبر خادم آمن تماشياً مع معايير حماية البيانات GDPR."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (confirm == true) {
                                try {
                                  await FirebaseFirestore.instance.collection('account_deletions').doc(doc.id).update({
                                    'status': 'deleted',
                                  });
                                  // شاشةُ المستخدمينَ تُقيّدُ طلبَ الحذفِ
                                  // (DELETE_USER)، وتنفيذُه — وهو ما لا رجعةَ
                                  // فيه ويَترُكُ رصيدَ المحفظةِ دَيناً — كان
                                  // بلا أثر.
                                  await ZyiarahAuditService().logAction(
                                    action: ZyiarahAuditService.actionProcessAccountDeletion,
                                    details: {
                                      'account': deletionRowIdentity(req),
                                      if (deletionStrandedBalance(req) != null)
                                        'stranded_balance': deletionStrandedBalance(req),
                                    },
                                    targetId: doc.id,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("تم بدء عملية الحذف بنجاح. سيتم مسح البيانات خلال ثوانٍ.")),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("فشل الحذف: $e")),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Text("حذف"),
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
    );
  }
}
