import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/price_review.dart';
import 'package:zyiarah/utils/home_packages.dart';
import 'package:zyiarah/utils/store_order_flow.dart';

class AdminStoreOrdersScreen extends StatefulWidget {
  /// داخلَ تبويبِ المتجرِ في اللوحةِ (`AdminStoreHubScreen`) تُرسَمُ بلا
  /// `AppBar` خاصٍّ؛ وتَحتفظُ به حين تُفتَحُ وحدَها من الإحصاءات.
  final bool embedded;
  const AdminStoreOrdersScreen({super.key, this.embedded = false});

  @override
  State<AdminStoreOrdersScreen> createState() => _AdminStoreOrdersScreenState();
}

class _AdminStoreOrdersScreenState extends State<AdminStoreOrdersScreen> {
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
  Stream<QuerySnapshot<Map<String, dynamic>>>? _orders;
  Stream<QuerySnapshot<Map<String, dynamic>>> get _ordersStream =>
      _orders ??= FirebaseFirestore.instance
          .collection('store_orders')
          .orderBy('created_at', descending: true)
          .limit(100)
          .snapshots()
          .firstEventTimeout();

  void _reopenOrders() => setState(() => _orders = null);

  // (المتجر المباشر — قرار المالك) حُذف مسار «الموافقة والتسعير النهائي»:
  // العميل يدفع فوراً، والإدارة تدير التوصيل نقرةً نقرة أدناه.

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateOrderStatus(BuildContext context, String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('store_orders').doc(orderId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ZyiarahAuditService().logAction(
        action: 'UPDATE_STORE_ORDER_STATUS',
        details: {'new_status': newStatus},
        targetId: orderId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث حالة الطلب بنجاح")));
      }
    } catch (e) {
      if (context.mounted) {
        // تحديث store_orders حكر على مديري الطلبات (firestore.rules) — الرسالة
        // العامة كانت تبتلع permission-denied فيُعيد الأدمن المحاولة بلا جدوى.
        final String msg = e is FirebaseException && e.code == 'permission-denied'
            ? 'لا تملك صلاحية تحديث طلبات المتجر'
            : 'حدث خطأ أثناء التحديث: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    }
  }

  /// **وسمُ مراجعةِ السعرِ على طلبِ متجرٍ كان بلا قارئٍ أيضاً.**
  ///
  /// `_verifyStoreOrderPrice` يَسِمُ المستندَ بنفسِ حقولِ `orders`
  /// (`price_mismatch` / `price_unverifiable` / `price_expected` …) ويُنبّهُ
  /// الإدارةَ بأكوادٍ — وهذه هي الشاشةُ الوحيدةُ التي تَعرضُ طلباتِ المتجر،
  /// ولم تكن تَذكرُ شيئاً من ذلك. والاعتمادُ هو ما يُصرّفُ نافذةَ المكنسة.
  /// **الإدارةُ تختارُ السائق** (قرار المالك) — لا إسنادَ تلقائيّاً لطلبِ
  /// المتجر. السائقونَ النشطون (`drivers.is_active`، ومعرّفُ المستندِ هو
  /// معرّفُ دخولِ السائق الذي تَفحصُه القواعد)، والكتابةُ تَنقلُ الطلبَ «مع
  /// السائق» فيَظهرُ في لوحتِه ويُشعَرُ هو والعميلة.
  Future<void> _assignDriver(BuildContext context, String orderId,
      Map<String, dynamic> order) async {
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, String>> drivers;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .where('is_active', isEqualTo: true)
          // الخادمُ لا المخزن: قائمةٌ باردةٌ فارغةٌ تَقولُ «لا سائق» فيُحجَبُ الإسناد.
          .get(const GetOptions(source: Source.server))
          .timeout(kNetCallTimeout);
      drivers = snap.docs
          .map((d) => {
                'id': d.id,
                'name': (d.data()['name'] ?? 'بدون اسم').toString(),
              })
          .toList();
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text('تعذّر تحميل السائقين — تحقّق من الاتصال'),
          backgroundColor: Colors.red));
      return;
    }
    if (!context.mounted) return;
    if (drivers.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('لا يوجد سائق نشط — فعّل سائقاً من «السائقين والعمال»'),
          backgroundColor: Colors.orange));
      return;
    }
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('اختر السائق لتوصيل الطلب',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              for (final d in drivers)
                ListTile(
                  leading: const Icon(Icons.person_pin_circle_outlined, color: Color(0xFF660033)),
                  title: Text(d['name']!, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await FirebaseFirestore.instance.collection('store_orders').doc(orderId).update({
        'status': kStoreWithDriver,
        'driver_id': picked['id'],
        'driver_name': picked['name'],
        'assigned_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ZyiarahAuditService().logAction(
        action: 'ASSIGN_STORE_ORDER_DRIVER',
        details: {'driver_id': picked['id'] ?? '', 'driver_name': picked['name'] ?? ''},
        targetId: orderId,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('أُسند الطلب إلى ${picked['name']}'),
          backgroundColor: Colors.green));
    } catch (e) {
      final String msg = e is FirebaseException && e.code == 'permission-denied'
          ? 'لا تملك صلاحية تحديث طلبات المتجر'
          : 'تعذّر إسناد السائق — أعد المحاولة';
      messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Widget _priceReviewBanner(BuildContext context, String orderId,
      Map<String, dynamic> order) {
    final PriceReview r = priceReviewOf(order);
    if (!r.needsCard) return const SizedBox.shrink();
    final bool pending = r.actionable;
    final Color accent =
        pending ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final String line = r.kind == PriceReviewKind.underpaid
        ? (r.paid != null && r.expected != null
            ? 'مراجعة سعر: دُفع ${r.paid!.toStringAsFixed(2)} مقابل ${r.expected!.toStringAsFixed(2)} ر.س'
            : 'مراجعة سعر: المبلغ أدنى من المتوقَّع')
        : r.kind == PriceReviewKind.unverifiable
            ? 'تعذّر تسعير السلّة من products — منتج محذوف أو عنصر بلا معرّف'
            : 'سعر هذا الطلب اعتمدته مراجعة سابقة';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(pending ? Icons.price_check_rounded : Icons.verified_rounded,
                  size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(line,
                    style: GoogleFonts.tajawal(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent)),
              ),
            ],
          ),
          if (r.couponRejectedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'كوبون مرفوض خادميّاً: '
                '${kCouponRejectReasons[r.couponRejectedReason] ?? r.couponRejectedReason}',
                style:
                    GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade800),
              ),
            ),
          if (pending)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('اعتمدتُ المبلغ'),
                style: TextButton.styleFrom(foregroundColor: accent),
                onPressed: () => _approveStorePrice(context, orderId),
              ),
            ),
          if (!pending && order['price_reviewed_by'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('اعتُمد بواسطة ${order['price_reviewed_by']}',
                  style: GoogleFonts.tajawal(
                      fontSize: 11, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }

  Future<void> _approveStorePrice(BuildContext context, String orderId) async {
    try {
      final String by =
          FirebaseAuth.instance.currentUser?.email ?? 'Unknown Admin';
      await FirebaseFirestore.instance
          .collection('store_orders')
          .doc(orderId)
          .update({
        ...priceReviewApprovalPayload(by),
        'price_reviewed_at': FieldValue.serverTimestamp(),
      }).timeout(kNetCallTimeout);
      await ZyiarahAuditService().logAction(
        action: ZyiarahAuditService.actionReviewOrderPrice,
        details: {'decision': 'approved', 'collection': 'store_orders'},
        targetId: orderId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم اعتماد المبلغ ✅'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        final String msg =
            e is FirebaseException && e.code == 'permission-denied'
                ? 'لا تملك صلاحية اعتماد مبالغ طلبات المتجر'
                : 'تعذّر اعتماد المبلغ: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    }
  }

  void _showOrderItems(BuildContext context, Map<String, dynamic> order) {
    final List<dynamic> items = order['items'] ?? [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('مشتريات العميل (${items.length} منتجات)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.inventory_2, color: Colors.blue),
                    ),
                    title: Text(item['name'] ?? 'منتج غير معروف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('الكمية: ${item['quantity']} × السعر: ${formatSarAny(item['price'])} ر.س'),
                    trailing: Text('${formatSar((double.tryParse('${item['quantity'] ?? 0}') ?? 0) * (double.tryParse('${item['price'] ?? 0}') ?? 0))} ر.س', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
                  );
                },
              ),
              const Divider(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي المطلوب:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${formatSarAny(order['total_amount'])} ر.س', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF660033), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق التفاصيل'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  String _paymentLabel(Map<String, dynamic> order) {
    final method = order['payment_method'] ?? 'pending';
    final paid = order['is_paid'] == true;
    switch (method) {
      // شاهد قبر: الدفع عند الاستلام حُذف من الجذور ولا يمكن إنشاؤه بعد اليوم، لكن
      // طلبات المتجر التاريخية قد تحمله — تركُ التسمية يُبقيها مقروءة للإدارة بدل
      // عرض 'cash_on_delivery' خامّاً. لا شيء في التطبيق يكتب هذه القيمة الآن.
      case 'cash_on_delivery':
        return 'عند الاستلام (طلب قديم)';
      case 'tamara':
        return paid ? 'تمارا (مدفوع)' : 'تمارا';
      case 'card':
        return paid ? 'بطاقة (مدفوع)' : 'بطاقة';
      case 'pending':
        return 'بانتظار الدفع';
      default:
        return paid ? 'مدفوع' : 'غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: widget.embedded ? null : AppBar(
          title: Text("مبيعات المتجر الإلكتروني", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الطلب أو اسم العميل',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF660033)),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF660033), width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _ordersStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) {
                    // قراءة store_orders كاملةً حكر على مديري الطلبات (firestore.rules)
                    // — رفض القواعد كان يُعرَض «تحقّق من الاتصال» فيلوم الشبكة زوراً.
                    final err = snapshot.error;
                    final denied =
                        err is FirebaseException && err.code == 'permission-denied';
                    // وزرُّ الإعادةِ للاتّصالِ وحدَه: «أعد المحاولة» فوقَ رفضِ
                    // صلاحيّةٍ دعوى بأنّ المحاولةَ تُجدي، وهي لا تُجدي.
                    return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(denied
                          ? 'لا تملك صلاحية عرض طلبات المتجر — هذه الشاشة لمديري الطلبات فقط'
                          : 'تعذّر تحميل الطلبات، تحقّق من الاتصال'),
                      if (!denied)
                        TextButton(
                            onPressed: _reopenOrders,
                            child: const Text('إعادة المحاولة')),
                    ]));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات في المتجر حتى الآن"));

                  // **المدفوعُ وحدَه** (قرار المالك): طلبُ المتجرِ يُنشأُ قبلَ الدفعِ
                  // ليُسعَّرَ خادميّاً، فسلّةٌ هُجرت عند الدفعِ كانت تَظهرُ هنا
                  // «جديد (بانتظار الموافقة)» و«الدفع: بانتظار الدفع».
                  final paid = snapshot.data!.docs
                      .where((doc) => storeOrderVisibleToAdmin(
                          doc.data() as Map<String, dynamic>))
                      .toList();
                  if (paid.isEmpty) {
                    return const Center(child: Text('لا توجد طلبات مدفوعة في المتجر حتى الآن'));
                  }
                  final query = _search.trim().toLowerCase();
                  final docs = query.isEmpty
                      ? paid
                      : paid.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final code = doc.id.substring(0, 6).toLowerCase();
                          final clientName = (data['client_name'] ?? '').toString().toLowerCase();
                          return code.contains(query) || clientName.contains(query);
                        }).toList();

                  if (docs.isEmpty) {
                    return Center(child: Text('لا نتائج للبحث «${_search.trim()}»'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final orderDoc = docs[index];
                      final order = orderDoc.data() as Map<String, dynamic>;
                      final status = order['status'] ?? 'pending';

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("رقم الطلب #${orderDoc.id.substring(0, 6).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: storeStatusColor(status).withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                              child: Text(storeStatusLabel(status), style: TextStyle(color: storeStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const Divider(height: 25),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text("العميل: ${order['client_name'] ?? 'غير محدد'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.attach_money, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              order['final_amount'] != null
                                  ? "المعتمد: ${formatSarAny(order['final_amount'])} ر.س (السلة: ${formatSarAny(order['total_amount'])})"
                                  : "الإجمالي: ${formatSarAny(order['total_amount'])} ر.س",
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.payment, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text("الدفع: ${_paymentLabel(order)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        if ((order['driver_name'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 20, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('السائق: ${order['driver_name']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            ],
                          ),
                        ],
                        _priceReviewBanner(context, orderDoc.id, order),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('عرض المشتريات'),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF660033)),
                              onPressed: () => _showOrderItems(context, order),
                            ),
                            // دورةُ الإدارة (`store_order_flow.dart`): مدفوع ⇒ قيد
                            // التجهيز ⇒ جاهز للتوصيل ⇒ إسناد لسائق ⇒ يُسلِّمُه السائق.
                            // كلُّ نقرةٍ تَصِلُ العميلةَ بإشعارٍ خادميّ.
                            if (storeAdminNextStep(status) case final step?)
                              ElevatedButton.icon(
                                icon: Icon(
                                    switch (step) {
                                      StoreAdminStep.startPreparing => Icons.inventory_2_outlined,
                                      StoreAdminStep.markReady => Icons.check_box_outlined,
                                      StoreAdminStep.assignDriver => Icons.local_shipping_outlined,
                                      StoreAdminStep.markDelivered => Icons.check_circle_outline,
                                    },
                                    size: 18),
                                label: Text(step.label),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: storeStatusColor(step.nextStatus),
                                    foregroundColor: Colors.white),
                                onPressed: () => step == StoreAdminStep.assignDriver
                                    ? _assignDriver(context, orderDoc.id, order)
                                    : _updateOrderStatus(context, orderDoc.id, step.nextStatus),
                              ),
                          ],
                        ),
                        if (order['delivery_location'] is GeoPoint)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.location_on_outlined, size: 18),
                              label: const Text('عنوان التوصيل على الخريطة'),
                              onPressed: () async {
                                final gp = order['delivery_location'] as GeoPoint;
                                // launchUrl كانت تُطلَق وتُنسى — فشلها (لا معالج خرائط/متصفح)
                                // يتبخّر بلا أي إشعار. ننتظرها ونُظهر الخطأ كنمط
                                // _updateOrderStatus في نفس الملف.
                                try {
                                  final ok = await launchUrl(
                                      Uri.parse(
                                          'https://maps.google.com/?q=${gp.latitude},${gp.longitude}'),
                                      mode: LaunchMode.externalApplication);
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('تعذّر فتح الخريطة'),
                                        backgroundColor: Colors.red));
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text('تعذّر فتح الخريطة: $e'),
                                        backgroundColor: Colors.red));
                                  }
                                }
                              },
                            ),
                          )
                      ],
                    ),
                  ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
