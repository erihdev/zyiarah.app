import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_wallet_service.dart';
import 'package:zyiarah/services/zyiarah_referral_service.dart';

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // إنشاء طلب جديد
  Future<String> createOrder({
    required String clientId,
    required String serviceType,
    required double amount,
    required GeoPoint location,
    String paymentMethod = 'card',
    int? hours,
    DateTime? serviceDate,
    String? zoneName,
    int workerCount = 1,
    String? couponCode,
    double discountAmount = 0.0,
  }) async {
    // 1. Fetch Client Details once for efficiency (Name, Phone, Email)
    String clientName = 'عميل زيارة';
    String clientPhone = '000000000';
    String? clientEmail;
    
    try {
      final userDoc = await _db.collection('users').doc(clientId).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        clientName = userData?['name'] ?? 'عميل زيارة';
        clientPhone = userData?['phone'] ?? '000000000';
        clientEmail = userData?['email'];
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }

    // --- Component 4: Dynamic Surge Pricing Calculation ---
    double finalAmount = amount;
    try {
      final surgeResult = await FirebaseFunctions.instance.httpsCallable('getSurgePricingFactor').call();
      final double surgeFactor = (surgeResult.data['surgeFactor'] as num).toDouble();
      finalAmount = amount * surgeFactor;
      if (surgeFactor > 1.0) {
        debugPrint('Surge pricing active! Factor: $surgeFactor, Old: $amount, New: $finalAmount');
      }
    } catch (e) {
      debugPrint('Error fetching surge factor: $e');
    }
    // -----------------------------------------------------

    // 2 & 3. Atomic: increment counter + create order in one Transaction
    // Pre-generate doc ref so we can reference it both inside and outside the transaction
    final orderRef = _db.collection('orders').doc();
    final counterRef = _db.collection('metadata').doc('order_counter');
    String orderCode = '';

    await _db.runTransaction((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final lastId = counterSnap.exists
          ? ((counterSnap.data()?['last_id'] as num?)?.toInt() ?? 100)
          : 100;
      final nextId = lastId + 1;
      orderCode = ZyiarahOrderUtil.formatSmartCode(nextId);

      if (counterSnap.exists) {
        transaction.update(counterRef, {'last_id': nextId});
      } else {
        transaction.set(counterRef, {'last_id': nextId});
      }

      transaction.set(orderRef, {
        'code': orderCode,
        'client_id': clientId,
        'client_name': clientName,
        'client_phone': clientPhone,
        'client_email': clientEmail,
        'user_phone': clientPhone,
        'service_type': serviceType,
        'service_name': serviceType,
        'amount': finalAmount,
        'status': 'pending',
        'location': location,
        'payment_method': paymentMethod,
        'created_at': FieldValue.serverTimestamp(),
        'hours_contracted': hours ?? 4,
        'service_date': serviceDate != null ? Timestamp.fromDate(serviceDate) : null,
        'zone_name': zoneName,
        'worker_count': workerCount,
        'coupon_code': couponCode,
        'discount_amount': discountAmount,
      });
    });

    // Alias for backward compatibility with side-effect code below
    final doc = orderRef;

    // 4. Log and Execute Side-Effects (Coupons & Alerts)
    ZyiarahAuditService().logAction(
      action: 'CREATE_CLEANING_ORDER',
      details: {'code': orderCode, 'amount': finalAmount, 'client': clientName},
      targetId: doc.id,
    );

    if (couponCode != null) {
      await _incrementCouponUsage(couponCode);
    }

    final orderMap = {
      'code': orderCode,
      'client_name': clientName,
      'client_phone': clientPhone,
      'service_type': serviceType,
      'amount': finalAmount,
      'location': location,
    };
    
    // 5. Generate ZATCA QR and Invoice PDF (Professional Touch)
    final String qrData = ZatcaService.generateZatcaQrCode(
      timestamp: DateTime.now(),
      totalAmount: finalAmount,
      vatAmount: finalAmount - (finalAmount / 1.15),
    );

    final String? invoiceUrl = await ZyiarahPdfService.generateAndUploadInvoice(
      orderId: doc.id,
      orderCode: orderCode,
      amount: finalAmount,
      qrData: qrData,
      serviceName: serviceType,
      discountAmount: discountAmount,
      couponCode: couponCode,
    );
    
    final comm = ZyiarahMessagingService();
    await comm.notifyNewOrder(orderMap, customerEmail: clientEmail, invoiceUrl: invoiceUrl);
    
    // --- ارسل تنبيه لحظي للإدارة وللعميل عبر النظام الجديد ---
    await ZyiarahMessagingService().notifyOrderCreated(
      clientId: clientId,
      orderCode: orderCode,
      type: serviceType,
      serviceName: serviceType,
    );
    // -----------------------------------------------------

    return orderCode;
  }

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

      return data;
    } catch (e) {
      debugPrint('Error validating coupon: $e');
      return null;
    }
  }

  // زيادة عداد استخدام الكود
  Future<void> _incrementCouponUsage(String code) async {
    try {
      final snapshot = await _db
          .collection('promo_codes')
          .where('code', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        await snapshot.docs.first.reference.update({
          'uses': FieldValue.increment(1),
        });
      }
    } catch (e) {
      debugPrint('Error incrementing coupon usage: $e');
    }
  }

  // إلغاء الطلب — يسمح فقط للطلبات في حالة pending أو accepted
  Future<void> cancelOrder(String orderId, {String cancelledBy = 'client'}) async {
    String? orderCode;
    bool needsRefund = false;
    String? cancelledDriverId;

    await _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists) throw Exception("الطلب غير موجود");

      final orderData = orderSnap.data() as Map<String, dynamic>;
      final currentStatus = orderData['status'] as String?;

      if (currentStatus == 'completed' || currentStatus == 'cancelled') {
        throw Exception("لا يمكن إلغاء طلب مكتمل أو ملغي بالفعل");
      }
      if (currentStatus == 'in_progress') {
        throw Exception("لا يمكن إلغاء طلب قيد التنفيذ — تواصل مع الدعم");
      }

      orderCode = orderData['code'] as String?;
      needsRefund = orderData['is_paid'] == true;
      final driverId = orderData['driver_id'] as String?;
      cancelledDriverId = driverId;

      transaction.update(orderRef, {
        'status': 'cancelled',
        'cancelled_at': FieldValue.serverTimestamp(),
        'cancelled_by': cancelledBy,
        'needs_refund': needsRefund,
      });

      if (driverId != null) {
        final driverRef = _db.collection('drivers').doc(driverId);
        transaction.update(driverRef, {
          'status': 'available',
          'current_order_id': null,
          'is_available': true,
        });
      }

      // إعادة الزيارة إذا كان الدفع باشتراك — الخصم يتم عند الإنشاء فقط
      final isSubscription = orderData['payment_method'] == 'subscription';
      final clientId = orderData['client_id'] as String?;
      if (isSubscription && clientId != null) {
        final userRef = _db.collection('users').doc(clientId);
        transaction.update(userRef, {'visits_remaining': FieldValue.increment(1)});
      }
    });

    ZyiarahAuditService().logAction(
      action: 'CANCEL_ORDER',
      details: {'code': orderCode, 'by': cancelledBy, 'needs_refund': needsRefund},
      targetId: orderId,
    );

    // --- إعادة المبلغ للمحفظة الرقمية إذا كان الطلب مدفوعاً (ليس اشتراكاً) ---
    if (needsRefund) {
      try {
        final orderSnap = await _db.collection('orders').doc(orderId).get();
        final orderData = orderSnap.data();
        final String? clientId = orderData?['client_id'];
        final double refundAmount = (orderData?['amount'] ?? 0.0).toDouble();
        final String? paymentMethod = orderData?['payment_method'];
        // لا تُعيد رصيد للاشتراك — فقط للدفع النقدي أو البطاقة أو المحفظة
        if (clientId != null && refundAmount > 0 && paymentMethod != 'subscription') {
          await ZyiarahWalletService().processRefund(
            userId: clientId,
            amount: refundAmount,
            orderId: orderId,
            orderCode: orderCode ?? orderId,
          );
        }
      } catch (e) {
        debugPrint('Error processing wallet refund: $e');
      }
    }
    // -------------------------------------------------------------------------

    // إشعار السائق إذا كان مُسنَّداً
    if (cancelledDriverId != null) {
      ZyiarahMessagingService().triggerNotification(
        toUid: cancelledDriverId!,
        title: "تم إلغاء الطلب",
        body: "تم إلغاء الطلب #${orderCode ?? orderId} بواسطة ${cancelledBy == 'client' ? 'العميل' : 'الإدارة'}.",
        type: 'driver_order_cancelled',
        data: {'orderId': orderId, 'code': orderCode ?? orderId},
      ).catchError((_) {});
    }

    // إشعار الإدارة
    await ZyiarahMessagingService().triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "تم إلغاء طلب ⚠️",
      body: "تم إلغاء الطلب #${orderCode ?? orderId} بواسطة ${cancelledBy == 'client' ? 'العميل' : 'الإدارة'}.",
      type: 'admin_order_alert',
      data: {'orderId': orderId, 'code': orderCode ?? orderId, 'needs_refund': needsRefund},
    );
  }

  // تحديث حالة الطلب باستخدام Transaction لضمان سلامة البيانات ومنع التعارض
  Future<void> updateOrderStatus(String orderId, String status, {String? driverId}) async {
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

      final Map<String, dynamic> updates = {
        'status': status,
        if (driverId != null) 'driver_id': driverId,
        if (status == 'accepted') 'accepted_at': FieldValue.serverTimestamp(),
        if (status == 'in_progress') 'arrived_at': FieldValue.serverTimestamp(),
        if (status == 'in_progress') 'start_time': FieldValue.serverTimestamp(),
        if (status == 'completed') 'end_time': FieldValue.serverTimestamp(),
      };

      transaction.update(orderRef, updates);

      // تحديث حالة السائق بالتزامن (Atomic)
      if (driverId != null) {
        final driverRef = _db.collection('drivers').doc(driverId);
        String driverStatus = 'available';
        if (status == 'accepted') driverStatus = 'en_route';
        if (status == 'in_progress') driverStatus = 'in_service';
        
        transaction.update(driverRef, {
          'status': driverStatus,
          'current_order_id': status == 'completed' ? null : orderId,
          'is_available': status == 'completed',
        });
      }

      // --- العمليات المرتبطة بالاكتمال (داخل الـ Transaction لضمان التكامل) ---
      if (status == 'completed') {
        final clientId = orderData['client_id'];
        final isSubscriptionOrder = orderData['payment_method'] == 'subscription';
        final maintenanceId = orderData['maintenance_id'];

        if (maintenanceId != null) {
          final maintenanceRef = _db.collection('maintenance_requests').doc(maintenanceId);
          transaction.update(maintenanceRef, {
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          });
        }

        if (clientId != null && isSubscriptionOrder) {
          final userRef = _db.collection('users').doc(clientId);
          transaction.update(userRef, {
            'visits_remaining': FieldValue.increment(-1),
          });
        }
      } else if (status == 'in_progress') {
        final maintenanceId = orderData['maintenance_id'];
        if (maintenanceId != null) {
          final maintenanceRef = _db.collection('maintenance_requests').doc(maintenanceId);
          transaction.update(maintenanceRef, {
            'status': 'in_progress',
            'startedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    });

    // العمليات غير الحرجة (خارج الـ Transaction)
    if (status == 'completed') {
      try {
        final doc = await _db.collection('orders').doc(orderId).get();
        final data = doc.data();
        if (data != null) {
          final clientId = data['client_id'] as String?;
          final amount = (data['amount'] ?? 0.0).toDouble();
          final code = data['code'] as String? ?? orderId;
          // منح نقاط زيارة للعميل عند إتمام الطلب (1 ريال = 1 نقطة)
          if (clientId != null && amount > 0) {
            await ZyiarahWalletService().grantQatratReward(
              userId: clientId,
              orderId: orderId,
              orderCode: code,
              orderValue: amount,
            );
            // تحقق من مكافأة الإحالة — يُكمّل المحرك الفيروسي دورته عند أول طلب مكتمل
            await ZyiarahReferralService().processReferralReward(
              refereeUserId: clientId,
              refereeOrderId: orderId,
              refereeOrderCode: code,
            );
          }
        }
      } catch (e) {
        debugPrint("Non-critical post-processing error: $e");
      }
    }
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

  // التحقق من توفر فتحة زمنية لخدمة التنظيف بالساعة
  // يُعيد {available, driverId, driverName}
  Future<Map<String, dynamic>> checkHourlySlotAvailability({
    required DateTime startDateTime,
    required int durationHours,
  }) async {
    final endDateTime = startDateTime.add(Duration(hours: durationHours));
    final dayStart = DateTime(startDateTime.year, startDateTime.month, startDateTime.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final driversSnap = await _db
        .collection('drivers')
        .where('is_active', isEqualTo: true)
        .get();

    if (driversSnap.docs.isEmpty) {
      return {'available': false, 'driverId': null, 'driverName': null};
    }

    final ordersSnap = await _db
        .collection('orders')
        .where('service_date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('service_date', isLessThan: Timestamp.fromDate(dayEnd))
        .where('status', whereIn: ['accepted', 'in_progress'])
        .get();

    final busyDriverIds = <String>{};
    for (final doc in ordersSnap.docs) {
      final data = doc.data();
      if (data['service_date'] == null) continue;
      final orderStart = (data['service_date'] as Timestamp).toDate();
      final orderHours = (data['hours_contracted'] as int?) ?? 4;
      final orderEnd = orderStart.add(Duration(hours: orderHours));
      if (startDateTime.isBefore(orderEnd) && orderStart.isBefore(endDateTime)) {
        final driverId = data['driver_id'] as String?;
        if (driverId != null) busyDriverIds.add(driverId);
      }
    }

    final available = driversSnap.docs.where((d) => !busyDriverIds.contains(d.id)).toList();
    if (available.isEmpty) {
      return {'available': false, 'driverId': null, 'driverName': null};
    }

    return {
      'available': true,
      'driverId': available.first.id,
      'driverName': available.first.data()['name'] ?? 'سائق',
      'driverEmail': available.first.data()['email'] as String?,
    };
  }

  // التوزيع الذكي للطلبات للسائقين الأقرب (Smart Dispatch)
  Future<bool> autoAssignDriverForHourly({
    required String orderId,
    required DateTime startDateTime,
    required int durationHours,
  }) async {
    try {
      // 1. Fetch order details
      final orderDoc = await _db.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return false;
      
      final location = orderDoc.data()?['location'] as GeoPoint?;
      final serviceType = orderDoc.data()?['service_type'] as String?;
      final serviceDate = orderDoc.data()?['service_date'] as Timestamp?;
      
      if (location == null) return false;

      // 2. Call Cloud Function to find top 3 nearest drivers
      final result = await FirebaseFunctions.instance.httpsCallable('findNearestDrivers').call({
        'lat': location.latitude,
        'lng': location.longitude,
      });
      
      final List<dynamic> drivers = result.data['drivers'] ?? [];
      if (drivers.isEmpty) return false;

      // 3. Broadcast to the top 3 drivers
      for (var driverId in drivers) {
        await ZyiarahMessagingService().notifyDriverOfAssignment(
          driverId.toString(),
          orderId,
          serviceType: serviceType,
          serviceDate: serviceDate != null ? serviceDate.toDate().toString() : startDateTime.toString(),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error in Smart Dispatch: $e');
      return false;
    }
  }

  // التحقق مما إذا كان السائق لديه طلب نشط حالياً
  Future<bool> hasActiveOrder(String driverId) async {
    final activeSnap = await _db
        .collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['accepted', 'in_progress'])
        .limit(1)
        .get();
    return activeSnap.docs.isNotEmpty;
  }

  // الاستماع للطلبات المتاحة (التي لم يقبلها أحد بعد)
  Stream<QuerySnapshot> streamAvailableOrders() {
    return _db.collection('orders')
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  // الاستماع للطلبات الخاصة بسائق معين (نشطة)
  Stream<QuerySnapshot> streamDriverActiveOrders(String driverId) {
    return _db.collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['accepted', 'in_progress'])
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

    // 1. تحديث الطلب بالتقييم
    await _db.collection('orders').doc(orderId).update({
      'rating': rating,
      'rating_comment': comment,
      'rating_reason': reason,
      'rating_evidence_url': evidenceUrl,
      'rated_at': FieldValue.serverTimestamp(),
    });

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

    // 2. تحديث معدل تقييم الكادر (Atomic Calculation)
    if (driverId != null) {
      final driverRef = _db.collection('drivers').doc(driverId);
      
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
    }
  }
}
