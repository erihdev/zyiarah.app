import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:zyiarah/services/zyiarah_wallet_service.dart';

/// ZyiarahReferralService — Viral referral engine.
///
/// Responsibilities:
/// 1. Generate a unique 8-char alphanumeric referral code per user.
/// 2. Register a referral link when a new user signs up via a code.
/// 3. On the referee's first completed order:
///    - Credit the referrer 50 SAR to their Zyiarah Wallet.
///    - Issue the referee a 10% discount coupon for their next order.
class ZyiarahReferralService {
  static final ZyiarahReferralService _instance =
      ZyiarahReferralService._internal();
  factory ZyiarahReferralService() => _instance;
  ZyiarahReferralService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahWalletService _wallet = ZyiarahWalletService();
  final ZyiarahAuditService _audit = ZyiarahAuditService();
  final ZyiarahMessagingService _messaging = ZyiarahMessagingService();

  /// Referrer reward: 50 SAR wallet credit.
  static const double referrerRewardSar = 50.0;

  /// Referee reward: 10% discount on their next order.
  static const double refereeDiscountPercent = 10.0;

  // ─────────────────────────────────────────────────────────
  // Code Generation
  // ─────────────────────────────────────────────────────────

  /// Characters used for code generation.
  /// Excludes visually ambiguous characters (0/O, 1/I/L).
  static const String _chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(8, (_) => _chars[rand.nextInt(_chars.length)]).join();
  }

  /// Returns the existing referral code for [userId], or generates and
  /// persists a collision-free one.
  Future<String> getOrCreateReferralCode(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    final doc = await userRef.get();

    if (!doc.exists) throw Exception('User $userId not found');

    final existing = doc.data()?['referral_code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    // Generate a collision-free code (up to 5 retries)
    String code = _generateCode();
    for (int i = 0; i < 5; i++) {
      final collision = await _db
          .collection('users')
          .where('referral_code', isEqualTo: code)
          .limit(1)
          .get();
      if (collision.docs.isEmpty) break;
      code = _generateCode();
    }

    await userRef.update({'referral_code': code});
    debugPrint('[ZyiarahReferralService] Generated code $code for $userId');
    return code;
  }

  // ─────────────────────────────────────────────────────────
  // Apply Referral Code at Registration
  // ─────────────────────────────────────────────────────────

  /// Called immediately after a new user registers.
  /// Validates [referralCode], resolves the referrer, and creates a
  /// `referrals` document with `status: 'pending'`.
  Future<void> applyReferralCode({
    required String newUserId,
    required String referralCode,
  }) async {
    try {
      final code = referralCode.trim().toUpperCase();

      // 1. Find referrer by code
      final referrerSnap = await _db
          .collection('users')
          .where('referral_code', isEqualTo: code)
          .limit(1)
          .get();

      if (referrerSnap.docs.isEmpty) {
        debugPrint('[ZyiarahReferralService] Code $code not found');
        return;
      }

      final referrerDoc = referrerSnap.docs.first;
      final referrerId = referrerDoc.id;

      // 2. Guard: cannot refer yourself
      if (referrerId == newUserId) {
        debugPrint('[ZyiarahReferralService] Self-referral blocked');
        return;
      }

      // 3. Guard: each user can only be referred once
      final existing = await _db
          .collection('referrals')
          .where('referee_id', isEqualTo: newUserId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        debugPrint('[ZyiarahReferralService] $newUserId already referred');
        return;
      }

      // 4. Log the referral link in 'referrals' collection
      await _db.collection('referrals').add({
        'referrer_id': referrerId,
        'referrer_name': referrerDoc.data()['name'] ?? '',
        'referee_id': newUserId,
        'referral_code': code,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'rewarded_at': null,
        'rewarded_on_order': null,
      });

      // 5. Mark on the new user's profile for fast lookup
      await _db.collection('users').doc(newUserId).update({
        'used_referral_code': code,
        'referred_by': referrerId,
      });

      await _audit.logAction(
        action: 'REFERRAL_LINK_CREATED',
        targetId: newUserId,
        details: {'referral_code': code, 'referrer_id': referrerId},
      );

      debugPrint(
          '[ZyiarahReferralService] Referral linked: $referrerId → $newUserId');
    } catch (e) {
      debugPrint('[ZyiarahReferralService] applyReferralCode error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // Process Referral Reward (hook into first completed order)
  // ─────────────────────────────────────────────────────────

  /// Call this after an order transitions to `'completed'`.
  /// Idempotent — silently exits if already rewarded or not a referred user.
  Future<void> processReferralReward({
    required String refereeUserId,
    required String refereeOrderId,
    required String refereeOrderCode,
  }) async {
    try {
      // 1. Find a pending referral for this referee
      final referralSnap = await _db
          .collection('referrals')
          .where('referee_id', isEqualTo: refereeUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (referralSnap.docs.isEmpty) return; // not referred or already rewarded

      final referralDoc = referralSnap.docs.first;
      final referralId = referralDoc.id;
      final referrerId = referralDoc.data()['referrer_id'] as String;

      // 2. Confirm this is truly their first completed order
      final completedOrders = await _db
          .collection('orders')
          .where('client_id', isEqualTo: refereeUserId)
          .where('status', isEqualTo: 'completed')
          .get();

      if (completedOrders.docs.length > 1) {
        // They have prior completions — reward already missed its window
        debugPrint(
            '[ZyiarahReferralService] Not first order for $refereeUserId; skipping');
        return;
      }

      // 3. Atomically mark the referral as rewarded
      await _db.collection('referrals').doc(referralId).update({
        'status': 'rewarded',
        'rewarded_at': FieldValue.serverTimestamp(),
        'rewarded_on_order': refereeOrderId,
      });

      // 4a. Reward referrer: +50 SAR wallet credit (re-uses processRefund)
      await _wallet.processRefund(
        userId: referrerId,
        amount: referrerRewardSar,
        orderId: refereeOrderId,
        orderCode: refereeOrderCode,
      );

      // 4b. Reward referee: 10% discount coupon valid for 30 days
      final couponCode =
          'REF${refereeUserId.substring(0, 6).toUpperCase()}10';
      await _db.collection('promo_codes').doc(couponCode).set({
        'code': couponCode,
        'discount_type': 'percentage',
        'discount_value': refereeDiscountPercent,
        'description': 'خصم الإحالة 10% — مكافأة الانضمام',
        'max_uses': 1,
        'uses': 0,
        'target_user_id': refereeUserId,
        'is_active': true,
        'created_at': FieldValue.serverTimestamp(),
        'expires_at': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      }, SetOptions(merge: true));

      // 5. Push notifications to both parties
      await _messaging.triggerNotification(
        toUid: referrerId,
        title: '🎁 مكافأة إحالتك وصلت!',
        body:
            'أُضيفت ${referrerRewardSar.toStringAsFixed(0)} ر.س لمحفظتك '
            'مكافأة لإحالة صديق أتمّ أول طلب.',
        type: 'referral_reward',
        data: {'orderId': refereeOrderId},
      );

      await _messaging.triggerNotification(
        toUid: refereeUserId,
        title: '🎉 كوبون الإحالة جاهز!',
        body:
            'حصلت على كوبون خصم ${refereeDiscountPercent.toStringAsFixed(0)}% '
            'على طلبك القادم. الكود: $couponCode',
        type: 'referral_coupon',
        data: {'coupon_code': couponCode},
      );

      // 6. Audit trail
      await _audit.logAction(
        action: 'REFERRAL_REWARD_GRANTED',
        targetId: refereeUserId,
        details: {
          'referrer_id': referrerId,
          'referrer_reward_sar': referrerRewardSar,
          'referee_coupon_code': couponCode,
          'on_order_id': refereeOrderId,
        },
      );

      debugPrint(
          '[ZyiarahReferralService] Rewards granted: referrer=$referrerId referee=$refereeUserId');
    } catch (e) {
      debugPrint('[ZyiarahReferralService] processReferralReward error: $e');
    }
  }
}
