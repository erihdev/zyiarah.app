import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:zyiarah/services/audit_service.dart';

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // التحقق من كود الخصم
  Future<Map<String, dynamic>?> validateCoupon(String code, {String? currentUserZone}) async {
    try {
      final snapshot = await _db
          .collection('promo_codes')
          .where('code', isEqualTo: code.toUpperCase())
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final data = snapshot.docs.first.data();
      final expiry = data['expiry'];
      final maxUses = (data['maxUses'] as num?)?.toInt() ?? 0;
      final uses = (data['uses'] as num?)?.toInt() ?? 0;
      final List<dynamic>? restrictedZones = data['restricted_zones'];

      // تحقق من التاريخ
      if (expiry != null) {
        DateTime? expiryDate;
        if (expiry is Timestamp) {
          expiryDate = expiry.toDate();
        } else if (expiry is String) {
          expiryDate = DateTime.tryParse(expiry);
        }
        if (expiryDate != null && expiryDate.isBefore(DateTime.now())) {
          return null;
        }
      }

      // تحقق من عدد مرات الاستخدام (0 تعني غير محدود)
      if (maxUses > 0 && uses >= maxUses) {
        return null;
      }

      // تحقق من القيود الجغرافية
      if (restrictedZones != null && restrictedZones.isNotEmpty) {
        if (currentUserZone == null || !restrictedZones.contains(currentUserZone)) {
          return null; // الكوبون غير متاح في هذه المنطقة
        }
      }

      // كوبون موجَّه لمستخدم بعينه (إحالة/هدية) لا يستخدمه غيره — كان يُقبل لأي أحد.
      final target = data['target_user_id'];
      if (target != null &&
          target != FirebaseAuth.instance.currentUser?.uid) {
        return null;
      }

      return data;
    } catch (e) {
      // لا نُعيد null هنا: null لدى المستدعي تعني «الكود باطل/منتهٍ»، بينما هذا
      // فشل بنيوي (شبكة/صلاحيات) — إعادته null كانت تعرض «كود غير صحيح» لكوبون
      // سليم أثناء انقطاع عابر، فيظن العميل أن كوبونه فاسد بدل أن يعيد المحاولة.
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
        throw Exception("لا يمكن إلغاء طلب قيد التنفيذ — تواصل مع الدعم");
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

  // قبول الطلب باستخدام Transaction لمنع التعارض المزدوج (Race Condition)
  Future<bool> acceptOrder(String orderId, String driverId) async {
    return await _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final driverRef = _db.collection('drivers').doc(driverId);
      
      final orderSnap = await transaction.get(orderRef);
      
      // 1. التحقق من أن الطلب ما زال متاحاً (قيد الانتظار)
      if (!orderSnap.exists || orderSnap.data()?['status'] != 'pending') {
        return false;
      }

      // 2. جلب بيانات السائق والتحقق من توفره (داخل الـ Transaction)
      final driverSnap = await transaction.get(driverRef);
      final driverData = driverSnap.data() ?? {};

      // التحقق من أن السائق متاح (ليس في طلب آخر)
      if (driverData['is_available'] == false) {
        return false;
      }

      // 3. تنفيذ التحديث بشكل ذري (Atomic)
      transaction.update(orderRef, {
        'status': 'accepted',
        'driver_id': driverId,
        'driver_phone': driverData['phone'] ?? '000000000', // مزامنة الرقم
        'assigned_driver': driverData['name'] ?? 'سائق', // مزامنة الاسم
        'accepted_at': FieldValue.serverTimestamp(),
      });

      transaction.update(driverRef, {
        'status': 'en_route',
        'current_order_id': orderId,
        'is_available': false,
      });

      return true;
    });
  }

  // التحقق من توفر فتحة زمنية لخدمة التنظيف بالساعة (عبر دالة سحابية آمنة)
  Future<Map<String, dynamic>> checkHourlySlotAvailability({
    required DateTime startDateTime,
    required int durationHours,
    String? zoneName,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('checkHourlySlotAvailability')
          .call({
        'startDateTimeIso': startDateTime.toIso8601String(),
        'durationHours': durationHours,
        if (zoneName != null) 'zoneName': zoneName,
      });

      final data = result.data as Map;
      return {
        'available': data['available'] == true,
        'driverId': data['driverId'] as String?,
        'driverName': data['driverName'] as String?,
        'driverEmail': data['driverEmail'] as String?,
      };
    } catch (e) {
      debugPrint('Error calling checkHourlySlotAvailability Cloud Function, using secure fallback: $e');
      // fail-open حتى لا يحجب خطأ عابر الحجز (يغطّيه sweepUnassignedPaidOrders +
      // autoAssign خادمياً). لا نُرجع معرّف سائق وهمياً كي لا يُكتب driver_id زائف.
      return {
        'available': true,
        'driverId': null,
        'driverName': null,
        'driverEmail': null,
      };
    }
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

  // التحقق مما إذا كان السائق مشغولاً بمهمة قيد التنفيذ الآن (ليس مجرد مهمة مجدولة مستقبلية)
  Future<bool> hasActiveOrder(String driverId) async {
    final activeSnap = await _db
        .collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['on_the_way', 'in_progress', 'accepted'])
        .limit(1)
        .get();
    return activeSnap.docs.isNotEmpty;
  }

  // الاستماع للطلبات المتاحة (التي لم يقبلها أحد بعد)
  Stream<List<QueryDocumentSnapshot>> streamAvailableOrders() {
    return _db.collection('orders')
        .where('status', isEqualTo: 'pending')
        // (D) تقييد الحجم لمنع استنزاف الذاكرة عند تضخّم الطلبات المعلّقة
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.toList()
          ..sort((a, b) {
            final aT = (a.data() as Map?)?['created_at'] as Timestamp?;
            final bT = (b.data() as Map?)?['created_at'] as Timestamp?;
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          }));
  }

  // الاستماع للمهام المُسنَدة للسائق (غير المكتملة) — نموذج التوزيع المباشر.
  // 'accepted' مُبقاة للتوافق مع الطلبات الجارية أثناء الانتقال.
  Stream<QuerySnapshot> streamDriverActiveOrders(String driverId) {
    return _db.collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['scheduled', 'on_the_way', 'in_progress', 'accepted'])
        .snapshots();
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
    return _db.collection('orders').doc(orderId).snapshots();
  }

  // تقديم تقييم للطلب وتحديث معدل تقييم الكادر
  Future<void> submitOrderRating(String orderId, double rating, String comment, {String? reason, File? evidence}) async {
    final orderDoc = await _db.collection('orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    final data = orderDoc.data() as Map<String, dynamic>;
    if (data['rating'] != null) return; // منع التقييم المزدوج
    final String? driverId = data['driver_id'];
    String? evidenceUrl;

    // 0. رفع صورة الإثبات إذا وجدت
    if (evidence != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child('order_feedback/${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(evidence);
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

    // 2. إطلاق رادار حماية السمعة الفاخر إذا كان التقييم منخفضاً
    if (rating <= 2.0) {
      ZyiarahMessagingService().alertReputationRisk(
        orderCode: data['code'] ?? 'N/A',
        rating: rating,
        reason: reason,
        comment: comment,
        evidenceUrl: evidenceUrl,
        clientName: data['client_name'] ?? 'عميل',
      );

      // تنبيه الإدارة اللحظي على الجوال
      ZyiarahMessagingService().notifyAdminOfLowRating(
        orderCode: data['code'] ?? orderId,
        rating: rating,
        clientName: data['client_name'] ?? 'عميل',
        comment: comment,
      );
    }

    // 2. تحديث معدل تقييم الكادر (أفضل-جهد): قواعد Firestore تمنع العميل من قراءة/تعديل
    //    مستند السائق (rating_avg/rating_count محجوزة)، فكان الرفض يتسرّب من هنا
    //    **بعد** حفظ التقييم على الطلب — فيرى العميل «تعذّر إرسال التقييم» بالأحمر
    //    لتقييم مُسجَّل فعلاً. نبتلع الفشل: نجاح كتابة الطلب هو نجاح التقييم.
    //    ملاحظة: لا يوجد Cloud Function يُجمِّع التقييمات حالياً — التجميعة الخادمية
    //    مطلوبة لاحقاً (backlog) كي تتحرّك rating_avg/rating_count فعلياً.
    if (driverId != null) {
      final driverRef = _db.collection('drivers').doc(driverId);

      try {
        await _db.runTransaction((transaction) async {
          final driverSnap = await transaction.get(driverRef);
          if (!driverSnap.exists) return;

          final driverData = driverSnap.data() as Map<String, dynamic>;
          double currentAvg = (driverData['rating_avg'] ?? 5.0).toDouble();
          int currentCount = (driverData['rating_count'] ?? 0).toInt();

          // حساب المعدل الجديد: (المعدل القديم * العدد القديم + التقييم الجديد) / (العدد الجديد)
          double newAvg = ((currentAvg * currentCount) + rating) / (currentCount + 1);

          transaction.update(driverRef, {
            'rating_avg': newAvg,
            'rating_count': currentCount + 1,
          });
        });
      } catch (e) {
        // متوقَّع للعميل (permission-denied) — التقييم نفسه محفوظ على الطلب.
        debugPrint('RATING_AGGREGATE_SKIPPED: $e');
      }
    }
  }
}
