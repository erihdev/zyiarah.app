import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:zyiarah/models/wallet_model.dart';
import 'package:zyiarah/services/audit_service.dart';

class ZyiarahWalletService {
  // Singleton Pattern
  static final ZyiarahWalletService _instance = ZyiarahWalletService._internal();
  factory ZyiarahWalletService() => _instance;
  ZyiarahWalletService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();

  /// جلب محفظة المستخدم أو إنشائها تلقائياً إذا لم تكن موجودة (Safe Guard)
  Future<ZyiarahWallet> getOrCreateWallet(String userId) async {
    final walletRef = _db.collection('wallets').doc(userId);
    final doc = await walletRef.get();

    if (doc.exists) {
      return ZyiarahWallet.fromFirestore(doc);
    } else {
      // المحفظة تُنشأ خادمياً عند أول إيداع (كتابة العميل للمحفظة محظورة بعد قفل القاعدة).
      return ZyiarahWallet(
        userId: userId,
        balance: 0.0,
        qatratPoints: 0,
        lastUpdated: DateTime.now(),
      );
    }
  }

  // processRefund و grantQatratReward أُزيلتا: المرتجع ونقاط زيارة تُمنح الآن
  // خادمياً عبر onOrderRewards (Cloud Function) فلا يمكن تزويرها من العميل.

  /// استبدال نقاط قطرات وتحويلها لرصيد مالي حقيقي (كل 50 نقطة = 1 ريال).
  /// تحوّل المنطق إلى Cloud Function (redeemQatratPoints) ليكون التحقق والتحويل
  /// خادميَّيْن — لا يمكن للعميل تزوير النقاط/الرصيد عبر هذا المسار. الخادم يستخدم
  /// هوية المصادقة (auth.uid) ويتجاهل [userId] الممرَّر، فلا يمكن الاستبدال لحساب آخر.
  /// **لا يبتلع الفشل.** كان `catch (e) { return false; }` يلتقط كل شيء ويُرجع false،
  /// فتعرض الواجهة «تحتاج 50 نقطة على الأقل» — وهي رسالة **خاطئة**: الشاشة لا تستدعي
  /// الدالة أصلاً إلا والنقاط ≥ 50. فالمستخدمة تملك النقاط ويُقال لها إنها لا تملكها.
  ///
  /// والدالة الخادمية **ترمي** سبباً عربياً دقيقاً لكل فشل («نقاطك غير كافية»،
  /// «الحد الأدنى للاستبدال 50 نقطة»، «يجب تسجيل الدخول أولاً») ولا تُرجع
  /// `success:false` أبداً — فكان الابتلاع يرمي الرسالة الصحيحة ويعرض بدلاً منها
  /// رسالة مخترَعة. نترك الاستثناء يصعد لتعرضه الواجهة كما هو.
  Future<bool> redeemQatratPoints({required String userId, required int pointsToRedeem}) async {
    if (pointsToRedeem < 50) return false; // الحد الأدنى للاستبدال 50 نقطة
    final callable =
        FirebaseFunctions.instance.httpsCallable('redeemQatratPoints');
    final res = await callable.call<Map<String, dynamic>>(
      {'pointsToRedeem': pointsToRedeem},
    );
    final bool success = res.data['success'] == true;
    if (success) {
      // التدقيق أفضل-جهد: فشل تسجيله لا يجوز أن يُظهر استبدالاً ناجحاً كأنه فاشل.
      try {
        await _audit.logAction(
          action: 'W_QATRAT_REDEEM_SUCCESS',
          targetId: userId,
          details: {'points_redeemed': pointsToRedeem},
        );
      } catch (e) {
        debugPrint('[wallet] audit log failed (non-fatal): $e');
      }
    }
    return success;
  }

  /// بث تيار لحظي لسجل المعاملات والتحصيلات الخاصة بمحفظة المستخدم (Real-time Stream)
  Stream<List<WalletTransaction>> streamTransactions(String userId) {
    return _db
        .collection('wallets')
        .doc(userId)
        .collection('transactions')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WalletTransaction.fromFirestore(doc))
            .toList());
  }
}
