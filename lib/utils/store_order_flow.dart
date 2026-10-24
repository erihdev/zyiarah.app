/// **دورةُ طلبِ المتجر (قرار المالك 2026-10-24)** — موضعٌ واحدٌ تَقرؤه
/// شاشةُ الإدارةِ و«طلباتي» ولوحةُ السائق.
///
/// العميلةُ تختارُ من المتجرِ وموقعُها محدَّدٌ تلقائياً وتَدفع، فيَصلُ الطلبُ
/// قسمَ «طلبات المتجر» مدفوعاً. ومن هناك الإدارةُ وحدَها:
///
///   مدفوع (`under_review`) ⇒ قيد التجهيز (`preparing`) ⇒ جاهز للتوصيل
///   (`ready`) ⇒ الإدارةُ تختارُ السائقَ ⇒ مع السائق (`with_driver`) ⇒
///   السائقُ يُسلِّم ⇒ تم التسليم (`delivered`) فيَخرجُ من لوحتِه.
///
/// والعميلةُ يَصلُها إشعارٌ بكلِّ نقلةٍ وتتغيّرُ حالتُها في التطبيق
/// (`notifyClientOnStoreOrderStatus` خادميّاً).
///
/// **لا «بانتظار الدفع» عند الإدارة:** الطلبُ يُنشأُ قبلَ الدفعِ ليُسعَّرَ
/// خادميّاً، فما لم يُدفَع لا يَعرضُه قسمُ الطلبات — كان يَظهرُ «جديد
/// (بانتظار الموافقة)» و«الدفع: بانتظار الدفع» لسلالٍ هُجرت عند الدفع.
/// وكان متجرُ الأدواتِ طلباً مجدولاً يختارُ له العميلُ يوماً ووقتاً ويُسنَدُ
/// سائقُه تلقائياً؛ صارَ المتجران دورةً واحدةً تُديرُها الإدارة.
library;

import 'package:flutter/material.dart';

const String kStorePaid = 'under_review';
const String kStorePreparing = 'preparing';
const String kStoreReady = 'ready';
const String kStoreWithDriver = 'with_driver';
const String kStoreDelivered = 'delivered';

/// ما قبلَ الدفع — لا يَعرضُه قسمُ الإدارة. (`pending`/`approved` إرثُ مسارِ
/// الموافقةِ القديم.)
const Set<String> kStorePrePaymentStatuses = {
  'awaiting_payment',
  'pending',
  'approved',
};

/// يَظهرُ في «طلبات المتجر»؟ — المدفوعُ وحدَه. وطلبٌ قديمٌ تجاوزَ ما قبلَ
/// الدفعِ (أداره أحدٌ) يَبقى ظاهراً ولو غابَ علمُ الدفع.
bool storeOrderVisibleToAdmin(Map<String, dynamic> order) {
  if (order['is_paid'] == true) return true;
  final s = (order['status'] ?? 'awaiting_payment').toString();
  return !kStorePrePaymentStatuses.contains(s);
}

/// خطوةُ الإدارةِ التالية — `null` حين لا خطوةَ لها (السائقُ يُسلِّم، أو انتهى).
/// `processing` إرثُ «جاري التجهيز» القديم، و`delivering`/`shipped` إرثُ
/// التوصيلِ بلا سائق — تُعامَلُ نظائرَها كي لا تَعلقَ المستنداتُ القديمة.
enum StoreAdminStep { startPreparing, markReady, assignDriver, markDelivered }

StoreAdminStep? storeAdminNextStep(String status) => switch (status) {
      kStorePaid => StoreAdminStep.startPreparing,
      kStorePreparing || 'processing' => StoreAdminStep.markReady,
      kStoreReady => StoreAdminStep.assignDriver,
      'delivering' || 'shipped' => StoreAdminStep.markDelivered,
      _ => null,
    };

extension StoreAdminStepX on StoreAdminStep {
  String get label => switch (this) {
        StoreAdminStep.startPreparing => 'بدء التجهيز',
        StoreAdminStep.markReady => 'جاهز للتوصيل',
        StoreAdminStep.assignDriver => 'إسناد لسائق',
        StoreAdminStep.markDelivered => 'تم التسليم',
      };

  /// الحالةُ التي تَكتبُها الخطوة (الإسنادُ يَكتبُ معه السائق).
  String get nextStatus => switch (this) {
        StoreAdminStep.startPreparing => kStorePreparing,
        StoreAdminStep.markReady => kStoreReady,
        StoreAdminStep.assignDriver => kStoreWithDriver,
        StoreAdminStep.markDelivered => kStoreDelivered,
      };
}

/// اسمُ الحالة. [forClient] لـ«طلباتي»: صياغةٌ موجَّهةٌ للعميلة.
String storeStatusLabel(String status, {bool forClient = false}) =>
    switch (status) {
      'awaiting_payment' || 'pending' || 'approved' => 'بانتظار الدفع',
      kStorePaid => forClient ? 'تم استلام طلبكِ' : 'جديد — مدفوع',
      kStorePreparing || 'processing' => 'قيد التجهيز',
      kStoreReady => 'جاهز للتوصيل',
      kStoreWithDriver => 'مع السائق',
      'delivering' || 'shipped' => 'جاري التوصيل',
      kStoreDelivered || 'completed' => 'تم التسليم',
      'cancelled' || 'rejected' => 'ملغي',
      _ => 'قيد المعالجة',
    };

Color storeStatusColor(String status) => switch (status) {
      'awaiting_payment' || 'pending' || 'approved' => Colors.deepOrange,
      kStorePaid => const Color(0xFFB45309),
      kStorePreparing || 'processing' => Colors.teal,
      kStoreReady => Colors.blue,
      kStoreWithDriver || 'delivering' || 'shipped' => Colors.indigo,
      kStoreDelivered || 'completed' => Colors.green,
      'cancelled' || 'rejected' => Colors.red,
      _ => Colors.grey,
    };
