import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/services/audit_service.dart';

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
  final ZyiarahAuditService _audit = ZyiarahAuditService();

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

      // 4. Log the referral link with a DETERMINISTIC id (= referee uid) so the
      // server trigger (onOrderRewards) can claim it by id; each user is referred once.
      await _db.collection('referrals').doc(newUserId).set({
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

  // processReferralReward أُزيلت: مكافأة الإحالة (50 ر.س للمُحيل + كوبون 10% للمُحال)
  // تُمنح الآن خادمياً وآمنةً من سباقات التزامن عبر onOrderRewards (Cloud Function)
  // التي تطالب وثيقة الإحالة (pending -> rewarded) ذرياً بمعرّف حتمي.
}
