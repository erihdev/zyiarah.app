import 'package:cloud_firestore/cloud_firestore.dart';

/// محفظة العميل — **قراءةً فقط.** كل تغيير للرصيد خادميّ (`firestore.rules`
/// تمنع كتابة العميل على `wallets/*`)، فالنموذج يحمل ما تعرضه الواجهة وحده.
///
/// **وزال منه ثلاثةُ أعضاءٍ ونوعٌ كامل (2026-10-08) — كلُّها مُحلَّلةٌ ولا
/// قارئَ لها:**
///
///   • `userId` — كان يُسنَد من `doc.id` وصفرُ `.userId` في `lib/` كلِّها،
///     والمُنادي يَملكُ الـuid أصلاً لأنّه مَن طلبَ المحفظةَ به.
///   • `lastUpdated` — كان يُحلَّل من `last_updated`، وصفرُ قارئ.
///   • `toMap()` — صفرُ مُنادٍ، **وكتابتُها محظورةٌ بالقواعدِ أصلاً**: شكلٌ
///     جاهزٌ لكتابةٍ لا يَجوزُ أن تَحدُث، كـ`ZyiarahUser.toMap()` قبلَها.
///   • `WalletTransaction` — النوعُ كلُّه بلا مرجعٍ خارجَ هذا الملفّ، و
///     `fromFirestore` فيه يَصِفُ مجموعةً باسمٍ **لا وجودَ له**: سجلُّ
///     المحفظةِ الحقيقيُّ هو `transactions` (يَكتبُه `rewards.js` و
///     `refund_engine.js` بـ`t.create` على معرّفٍ حتميّ)، ولا شاشةَ تَقرؤه.
///     فشكلُ الحقولِ كان صحيحاً والوجهةُ لا — نظيرُ
///     `admin_panel/src/types/index.ts` المحذوف.
///
/// وسجلُّ معاملاتٍ للعميلة ميزةٌ لا إصلاح: مرفوعةٌ في `CLAUDE.md`.
class ZyiarahWallet {
  final double balance;
  final int qatratPoints;

  ZyiarahWallet({
    required this.balance,
    required this.qatratPoints,
  });

  factory ZyiarahWallet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ZyiarahWallet(
      // التأمين ضد أخطاء الـ Casting (int vs double) القادمة من Firestore
      balance: (data['balance'] ?? 0.0).toDouble(),
      qatratPoints: (data['qatrat_points'] ?? 0).toInt(),
    );
  }
}
