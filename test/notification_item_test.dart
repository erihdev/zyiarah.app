import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/notification_item.dart';

/// تصنيف إشعارات العميل (تصميم Stitch، 2026-09-16) بالمفردات — أنواع الخادم
/// الفعلية (order_update, payment_update, refund, qatrat_reward, global_broadcast…)
/// لم تكن تطابق قائمة البطاقة القديمة فكانت كلها بأيقونة افتراضية.
void main() {
  test('categoryOf: أنواع الخادم الفعلية تذهب لتصنيفها', () {
    for (final t in ['order_update', 'order_assignment', 'driver_near', 'visit_reminder']) {
      expect(NotificationItem.categoryOf(t), NotificationCategory.orders, reason: t);
    }
    for (final t in [
      'payment_update', 'payment', 'refund', 'qatrat_reward', 'qatrat_redeem',
      'referral_reward', 'subscription_activated', 'contract_signed', 'wallet_topup',
    ]) {
      expect(NotificationItem.categoryOf(t), NotificationCategory.payments, reason: t);
    }
    for (final t in ['global_broadcast', 'promo', 'offer_new', 'coupon_gift']) {
      expect(NotificationItem.categoryOf(t), NotificationCategory.offers, reason: t);
    }
    expect(NotificationItem.categoryOf(''), NotificationCategory.other);
    expect(NotificationItem.categoryOf('system'), NotificationCategory.other);
    // العروض قبل المدفوعات: «promo_payment» عرضٌ.
    expect(NotificationItem.categoryOf('promo_payment'), NotificationCategory.offers);
  });

  test('fromMap: الوقت من sentAt أو created_at، والمقروء بأيّ من الحقلين', () {
    final ts = Timestamp.fromDate(DateTime(2026, 9, 16, 10));
    final a = NotificationItem.fromMap('a', {
      'title': 'تم تأكيد دفعتك',
      'body': 'x',
      'type': 'payment_update',
      'relatedId': 'AbCdEfGhIjKlMnOpQrSt',
      'sentAt': ts,
      'isRead': true,
    });
    expect(a.createdAt, DateTime(2026, 9, 16, 10));
    expect(a.isRead, isTrue);
    expect(a.relatedId, 'AbCdEfGhIjKlMnOpQrSt');
    expect(a.relatedLooksLikeOrderDoc, isTrue);

    final b = NotificationItem.fromMap('b', {'created_at': ts, 'is_read': true});
    expect(b.isRead, isTrue);
    expect(b.title, 'إشعار جديد');
    expect(b.relatedId, isNull);

    final c = NotificationItem.fromMap('c', {'sentAt': 'not a timestamp'});
    expect(c.createdAt, isNull);
    expect(c.isRead, isFalse);
  });

  test('relatedLooksLikeOrderDoc: كود الطلب ومعرّف المشغّل ليسا مستند طلب', () {
    NotificationItem n(String? r) => NotificationItem(
        id: 'x', title: '', body: '', type: 'order_update',
        createdAt: null, isRead: false, relatedId: r);
    expect(n('ZY-202600042').relatedLooksLikeOrderDoc, isFalse);
    expect(n('trig_abc123def456ghi').relatedLooksLikeOrderDoc, isFalse);
    expect(n('short').relatedLooksLikeOrderDoc, isFalse);
    expect(n(null).relatedLooksLikeOrderDoc, isFalse);
    expect(n('AbCdEfGhIjKlMnOpQrSt').relatedLooksLikeOrderDoc, isTrue);
  });

  test('newestFirst: الأحدث أولاً وبلا وقت آخراً', () {
    NotificationItem n(String id, DateTime? t) => NotificationItem(
        id: id, title: '', body: '', type: '', createdAt: t, isRead: false, relatedId: null);
    final list = [
      n('old', DateTime(2026, 1, 1)),
      n('none', null),
      n('new', DateTime(2026, 9, 1)),
    ]..sort(NotificationItem.newestFirst);
    expect(list.map((x) => x.id).toList(), ['new', 'old', 'none']);
  });
}
