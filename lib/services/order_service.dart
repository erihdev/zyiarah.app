import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/upload_content_type.dart';

/// نتيجةُ تحقّقِ كودِ الخصم: مؤهَّلٌ بحقولِه، أو سببُ رفضٍ من أسبابِ
/// `couponProblem` الستّة (`not_found`/`inactive`/`expired`/`exhausted`/
/// `other_user`/`other_zone`) — وترجمتُها في `kCouponRejectReasons`.
class CouponValidation {
  const CouponValidation.ok(this.coupon) : reason = null;
  const CouponValidation.rejected(this.reason) : coupon = null;

  /// حقولُ العرضِ التي يُعيدُها الخادم — لا المستندُ كلُّه.
  final Map<String, dynamic>? coupon;

  /// سببُ الرفضِ، أو `null` متى كان مؤهَّلاً.
  final String? reason;

  bool get ok => coupon != null;
}

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// **تحقّقُ كودِ الخصمِ صارَ خادميّاً.**
  ///
  /// كانت هذه الدالّةُ تَستعلمُ `promo_codes` من الجهازِ وتَفحصُ الشروطَ
  /// الستّةَ بيدِها — **نسخةٌ ثانيةٌ بلغةٍ أخرى** من `couponProblem` في
  /// `functions/coupons.js`، التي تَقولُ في ترويستِها إنّ «جهةً واحدةً
  /// تَقرّرُ والطرفانِ يَسألانها». والنسختانِ كانتا مختلفتَين: المُرشِّحُ
  /// `where('status','==','active')` هنا يَحجبُ مستنداً قديماً بلا `status`،
  /// بينما الخادمُ يَقبلُ غيابَه (ويَقولُ عن نفسِه «نفسُ تسامحِ العميل»).
  ///
  /// والأهمُّ أنّ القراءةَ نفسَها كانت تَفتحُ المجموعةَ كلَّها: قاعدةُ
  /// `promo_codes` هي `allow read: if isLoggedIn()`، فأيُّ عميلةٍ مسجَّلةٍ
  /// تَقرأُ كلَّ كودِ خصمٍ — ومنها ما وسَمَته الإدارةُ `show_in_offers:
  /// false` كي **لا** يُكشَف (تعليقُ `PromoCoupon` يَقولُه نصّاً: «كي لا
  /// يُكشَفَ كودُ قناةٍ خاصّة… لعمومِ العملاء»). فالقرارُ كان في الواجهةِ
  /// وحدَها.
  ///
  /// تُعيدُ [CouponValidation]: مؤهَّلٌ بحقولِ العرض، أو سببُ رفضٍ من أسبابِ
  /// الخادمِ الستّة. والفشلُ البنيويُّ (شبكة/صلاحيات) **يُرمى** لا يُعادُ
  /// رفضاً — رفضٌ زائفٌ كان يَتّهمُ كوبوناً سليماً بالبطلانِ أثناء انقطاعٍ
  /// عابر.
  Future<CouponValidation> validateCoupon(String code,
      {String? currentUserZone}) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return const CouponValidation.rejected('not_found');
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('validateCouponCode')
          .call({
        'code': trimmed.toUpperCase(),
        if (currentUserZone != null) 'zoneName': currentUserZone,
      }).timeout(kNetCallTimeout);
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['ok'] == true && data['coupon'] is Map) {
        return CouponValidation.ok(
            Map<String, dynamic>.from(data['coupon'] as Map));
      }
      final reason = data['reason'];
      return CouponValidation.rejected(
          reason is String && reason.isNotEmpty ? reason : 'not_found');
    } catch (e) {
      debugPrint('Error validating coupon: $e');
      rethrow;
    }
  }

  // إلغاء الطلب — يسمح فقط للطلبات في حالة pending أو accepted
  Future<void> cancelOrder(String orderId, {String cancelledBy = 'client'}) async {
    String? orderCode;
    bool needsRefund = false;

    await _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists) throw Exception("الطلب غير موجود");

      final orderData = orderSnap.data() as Map<String, dynamic>;
      final currentStatus = orderData['status'] as String?;

      if (currentStatus == 'completed' || currentStatus == 'cancelled') {
        throw Exception("لا يمكن إلغاء طلب مكتمل أو ملغي بالفعل");
      }
      // العميل لا يلغي طلباً قيد التنفيذ (يتواصل مع الدعم)؛ الإدارة تستطيع.
      if (currentStatus == 'in_progress' && cancelledBy != 'admin') {
        throw Exception("لا يمكن إلغاء طلب قيد التنفيذ — تواصلي مع الدعم");
      }

      orderCode = orderData['code'] as String?;
      needsRefund = orderData['is_paid'] == true;

      transaction.update(orderRef, {
        'status': 'cancelled',
        'cancelled_at': FieldValue.serverTimestamp(),
        'cancelled_by': cancelledBy,
        'needs_refund': needsRefund,
        // المرتجع للمحفظة يعالجه الخادم (onOrderRewards) لهذا الطلب — منعاً لتزوير الرصيد.
        'rewards_handled_by': 'server',
      });

      // تحديث حالة السائق يتم من Cloud Function عند تغيير حالة الطلب
      // (العميل لا يملك صلاحية تعديل مستند السائق مباشرة)

      // إعادة زيارة الاشتراك تُعالَج خادمياً عبر `syncOrderLinkedRecords`، ولا تُعاد
      // إلا إذا كانت الزيارة قد استُهلكت فعلاً (visit_counted) — يمنع تعويم زيارات
      // مجانية عند إلغاء زيارة لم تُنفَّذ أصلاً ضمن الباقة المدفوعة مسبقاً.
    });

    ZyiarahAuditService().logAction(
      action: 'CANCEL_ORDER',
      details: {'code': orderCode, 'by': cancelledBy, 'needs_refund': needsRefund},
      targetId: orderId,
    );

    // إعادة الرصيد للطلب الملغي المدفوع تُعالَج الآن خادمياً عبر onOrderRewards
    // (يقرأ needs_refund + is_paid + amount من مستند الطلب) — منعاً لتزوير الرصيد.
    // -------------------------------------------------------------------------

    // إشعار السائق بالإلغاء صار **خادميّاً** (freeDriverOnOrderCancel): مصدر واحد
    // يغطي إلغاء العميل والإدارة والإلغاء المباشر معاً بلا ازدواج. كان هنا نداءٌ
    // من العميل يُضاعف الإشعار عند إلغاء العميل/الإدارة، ويغيب عن الإلغاء المباشر.

    // (#3) إشعار الإدارة بالإلغاء صار **خادميّاً** (notifyClientOnOrderCancellation):
    // مصدر واحد لكل إلغاء بلا ازدواج، ولا يُحجَب بحارس ADMIN_BROADCAST (createdBy='server').
    // نداء العميل هنا كان يُحقن عبر notification_triggers القابلة للكتابة من العميل، وكان
    // يُضاعف تنبيه الإدارة عند إلغاء الأدمن (createdBy موثوق يمرّ + المُشغّل الخادمي).
  }

  // تحديث حالة الطلب باستخدام Transaction لضمان سلامة البيانات ومنع التعارض
  Future<void> updateOrderStatus(String orderId, String status,
      {String? driverId, Map<String, dynamic>? extraOrderUpdates,
      bool adminOverride = false}) async {
    await _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists) throw Exception("الطلب غير موجود");

      final orderData = orderSnap.data() as Map<String, dynamic>;
      final currentStatus = orderData['status'] as String?;

      // منع التحديث إذا كانت الحالة هي نفسها أو إذا كانت الحالة النهائية (مكتمل/ملغي) قد تم الوصول إليها
      if (currentStatus == status) return;
      if (currentStatus == 'completed' || currentStatus == 'cancelled') {
        throw Exception("لا يمكن تعديل حالة طلب مكتمل أو ملغي");
      }
      // (تسلسل منطقي) لا يُكمَل طلب لم يمرّ بـ in_progress — أي لم يصل السائق ويبدأ
      // الخدمة فعلاً — فلا يبقى «مكتمل» بسجلّ زمني ناقص. الإدارة تتجاوزه صراحةً
      // (adminOverride) للإكمال اليدوي من لوحة التحكم.
      if (status == 'completed' && !adminOverride && currentStatus != 'in_progress') {
        throw Exception("لا يمكن إكمال الطلب قبل بدء الخدمة");
      }

      // (حارس الازدواج) نقرأ مستند السائق داخل المعاملة قبل أي كتابة (شرط Firestore:
      // كل القراءات قبل الكتابات) — كي لا نُحرّر/نُعيد توجيه سائق منشغل بطلب آخر.
      DocumentSnapshot? driverSnap;
      if (driverId != null) {
        driverSnap =
            await transaction.get(_db.collection('drivers').doc(driverId));
      }

      final Map<String, dynamic> updates = {
        'status': status,
        if (driverId != null) 'driver_id': driverId,
        if (status == 'accepted') 'accepted_at': FieldValue.serverTimestamp(),
        // (Direct Dispatch) السائق غادر متوجهاً للعميل
        if (status == 'on_the_way') 'on_the_way_at': FieldValue.serverTimestamp(),
        if (status == 'in_progress') 'arrived_at': FieldValue.serverTimestamp(),
        if (status == 'in_progress') 'start_time': FieldValue.serverTimestamp(),
        if (status == 'completed') 'end_time': FieldValue.serverTimestamp(),
        // (Server rewards) علّم الطلب بأن الجوائز/المرتجع يعالجها الخادم (onOrderRewards)
        // فلا يمنحها العميل. النسخة القديمة لا تكتب هذا الحقل فتبقى تمنح محلياً.
        if (status == 'completed' || status == 'cancelled') 'rewards_handled_by': 'server',
        // (C) حقول إضافية (مثل تأكيد دفع COD) تُدمج ذرّياً داخل نفس الـ Transaction
        if (extraOrderUpdates != null) ...extraOrderUpdates,
      };

      transaction.update(orderRef, updates);

      // تحديث حالة السائق بالتزامن (Atomic).
      // ملاحظة: حالة 'scheduled' تُضبط عند الإسناد (مرحلة التوزيع) لا من هنا،
      // فلا يُعدّ السائق مشغولاً لمجرد وجود مهمة مجدولة مستقبلية.
      if (driverId != null) {
        final driverRef = _db.collection('drivers').doc(driverId);
        String driverStatus = 'available';
        if (status == 'accepted' || status == 'on_the_way') driverStatus = 'en_route';
        if (status == 'in_progress') driverStatus = 'in_service';

        // (حارس التطابق) لا نلمس حالة السائق إلا إن كان منشغلاً بهذا الطلب تحديداً
        // أو حرّاً — نفس حارس المُشغّلات الخادمية (freeDriverOnOrderCancel). بدونه
        // كان إكمال الأدمن لطلب قديم عالق يُحرّر سائقاً في منتصف خدمة طلب آخر
        // (is_available:true + current_order_id:null) فيقبل طلباً ثانياً — حجز مزدوج.
        final dCur = (driverSnap?.data() as Map<String, dynamic>?)?['current_order_id'];
        final bool ownsDriver = dCur == null || dCur == '' || dCur == orderId;

        final Map<String, dynamic> driverUpdates = {
          if (ownsDriver) 'status': driverStatus,
          if (ownsDriver) 'current_order_id': status == 'completed' ? null : orderId,
          if (ownsDriver) 'is_available': status == 'completed',
          // عدّاد المهام المنجزة الدائم — كان غير موجود إطلاقاً، فشاشة أداء الكوادر
          // ولوحة السائق تعرضان صفراً دائماً وترتيب الكفاءة بلا معنى. نزيده عند الإكمال
          // دون شرط الحارس: الإنجاز محسوب له حتى لو انتقل لمهمة أخرى.
          if (status == 'completed') 'completed_orders_count': FieldValue.increment(1),
        };
        if (driverUpdates.isNotEmpty) {
          transaction.update(driverRef, driverUpdates);
        }
      }

      // ملاحظة: مزامنة السجلات المرتبطة (حالة طلب الصيانة + خصم زيارات الاشتراك)
      // تُنفَّذ الآن خادمياً عبر Cloud Function `syncOrderLinkedRecords` — لأن السائق
      // لا يملك صلاحية الكتابة على `maintenance_requests` ولا مستند العميل، فكانت
      // كتابتها هنا تُفشل الـ Transaction بالكامل وتُبقي الطلب عالقاً.
    });

    // الجوائز (نقاط زيارة + مكافأة الإحالة) والمرتجع ومزامنة الصيانة/الاشتراك
    // تُعالَج كلها خادمياً (onOrderRewards + syncOrderLinkedRecords) فور تعليم الطلب
    // rewards_handled_by:'server' وتغيّر الحالة — منعاً للتزوير والازدواج.
  }

  // التوزيع التلقائي والتعيين المباشر للسائق المتاح (Direct Auto Assign)
  Future<bool> autoAssignDriverForHourly({
    required String orderId,
    required DateTime startDateTime,
    required int durationHours,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('autoAssignDriverDirectly')
          .call({
        'orderId': orderId,
        'durationHours': durationHours,
      });

      final data = result.data as Map;
      if (data['assigned'] == true) {
        debugPrint('Successfully assigned driver directly: ${data['driverId']}');
        return true;
      }
      debugPrint('No available driver to assign directly: ${data['error']}');
      return false;
    } catch (e) {
      // لا توزيع احتياطي من العميل: كان هنا `_fallbackSmartDispatch` يقرأ مستندات
      // السائقين ويكتب driver_id/status على الطلب — وكلها ممنوعة على العميل بقواعد
      // Firestore، فكل محاولة تنتهي permission-denied وشبكة أمان وهمية. المكنسة
      // الخادمية sweepUnassignedPaidOrders هي المسؤولة عن إسناد/تصعيد الطلبات
      // المدفوعة العالقة.
      debugPrint('Error calling autoAssignDriverDirectly Cloud Function: $e');
      return false;
    }
  }

  // الاستماع لتحديثات طلب معين
  // تحديث موقع السائق اللحظي للطلب (للمتابعة من قبل العميل)
  Future<void> updateDriverLocation(String orderId, GeoPoint location) async {
    await _db.collection('orders').doc(orderId).update({
      'driver_location': location,
      'last_location_update': FieldValue.serverTimestamp(),
    });
  }

  // الاستماع لتتبع طلب معين (للمتابعة من قبل العميل)
  Stream<DocumentSnapshot> streamOrderTracking(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots().firstEventTimeout();
  }

  // تقديم تقييم للطلب وتحديث معدل تقييم الكادر
  Future<void> submitOrderRating(String orderId, double rating, String comment, {String? reason, File? evidence}) async {
    final orderDoc = await _db.collection('orders').doc(orderId).get().timeout(kNetCallTimeout);
    if (!orderDoc.exists) return;

    final data = orderDoc.data() as Map<String, dynamic>;
    if (data['rating'] != null) return; // منع التقييم المزدوج
    String? evidenceUrl;

    // 0. رفع صورة الإثبات إذا وجدت
    if (evidence != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child('order_feedback/${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(evidence,
            SettableMetadata(contentType: imageContentTypeFor(evidence.path)));
        evidenceUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint("Error uploading feedback evidence: $e");
      }
    }

    // 1. كتابة التقييم **ذرّياً**: نقرأ الحالة داخل المعاملة ونتخطّى إن سبق التقييم —
    //    يمنع التقييم المزدوج (ضغطتان سريعتان/شاشتان) الذي كان يُفسد تجميعة السائق
    //    (rating_count يقفز 2) ويكرّر تنبيه الإدارة، لأن القراءة والكتابة كانتا منفصلتين.
    final orderRef = _db.collection('orders').doc(orderId);
    final bool didWrite = await _db.runTransaction<bool>((transaction) async {
      final snap = await transaction.get(orderRef);
      if (!snap.exists ||
          (snap.data() as Map<String, dynamic>)['rating'] != null) {
        return false;
      }
      transaction.update(orderRef, {
        'rating': rating,
        'rating_comment': comment,
        'rating_reason': reason,
        'rating_evidence_url': evidenceUrl,
        'rated_at': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!didWrite) return; // سبق تقييمه — لا تنبيه ولا تحديث تجميعة مكرّر.

    // **لا تنبيهَ ولا تجميعةَ من هنا — الخادمُ يَفعلُ الاثنين، وما كان هنا ميتٌ.**
    //
    // كان بعد هذا السطرِ ثلاثةُ أشياء، ثلاثتُها لا تَعمل:
    //
    //  1. نداءانِ للإدارةِ عند تقييمٍ ≤ 2 (`alertReputationRisk` بريداً و
    //     `notifyAdminOfLowRating` إشعاراً) — وكلاهما يُكتَبُ من **العميلة**
    //     إلى `ADMIN_BROADCAST`، وحارسُ الانتحالِ في `index.js` يَرفضُ ذلك
    //     صراحةً («وأي بثٍّ من عميل يُرفَض») فيَسِمُ المُشغّلَ
    //     `refused_untrusted_sender`. فكلُّ تقييمٍ منخفضٍ كان يَترُكُ مستندَ
    //     مُشغّلٍ مرفوضاً ولا يَصلُ شيء. والبديلُ قائمٌ خادميّاً:
    //     `exports.notifyAdminOnLowRating` يُطلَقُ مرّةً واحدةً على كلِّ
    //     تقييمٍ ≤ 2، وتعليقُه يُسمّي هذا المسارَ المحجوبَ بالاسم.
    //
    //  2. تجميعةُ معدَّلِ السائقِ: القواعدُ تَحصرُ الكتابةَ على `drivers`
    //     بـ`isOrdersManager`، فالعميلةُ تُرفَضُ دائماً — وكان الرفضُ يُبتلَع.
    //     والأسوأُ أنّها لو نَفذت يوماً لأفسدت الرقم: تَبذرُ المعدَّلَ
    //     بـ`5.0` حين يَغيبُ، وهو ما يَتجنّبُه الخادمُ بنصِّ تعليقِه («البذرُ
    //     الثابت لا يَدخلُ المتوسط»)، ثمّ تُضاعفُ العدَّ مع
    //     `exports.aggregateDriverRating` الذي يُجمّعُ أصلاً.
    //
    //  3. تعليقٌ يَقولُ «لا يوجد Cloud Function يُجمِّع التقييمات حالياً —
    //     مطلوبةٌ لاحقاً (backlog)». وهي قائمةٌ وتَعمل. من يَقرأُ ذلك قد
    //     «يُصلحُه» بتوسيعِ القواعدِ فيُعيدَ الاحتسابَ المزدوج.
    //
    // فالعميلةُ تَكتبُ `rating` على الطلبِ وحدَه، والخادمُ يَتولّى الباقي —
    // وهذا ما كان يَحدثُ فعلاً قبلَ هذا التنظيفِ أيضاً.
  }
}
