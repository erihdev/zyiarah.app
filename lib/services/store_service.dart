import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/counter_service.dart';
import 'package:zyiarah/utils/vat.dart';
import 'package:zyiarah/utils/net_timeout.dart';

class StoreProduct {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String description;

  /// جمهور المنتج: 'client' (المتجر العادي) أو 'companies' (متجر الشركات).
  /// الغياب = 'client' كي يبقى كل القديم في متجر العميل كما هو حرفياً.
  final String audience;

  StoreProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.description = "",
    this.audience = 'client',
  });

  factory StoreProduct.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return StoreProduct(
      id: doc.id,
      name: data['name'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      imageUrl: data['image_url'] ?? '',
      description: data['description'] ?? '',
      // **لا `isHidden` هنا.** `streamProducts` يُرشّح `is_hidden == false`
      // في الاستعلام، فمنتجٌ مخفيٌّ لا يَبلغُ هذا النموذجَ أبداً؛ والسطحُ
      // الإداريُّ يَقرأُ `data['is_hidden']` خامّاً. فكان الحقلُ يُحلَّل
      // ولا يَقرؤه أحد (2026-10-08).
      audience: data['store_audience'] ?? 'client',
    );
  }
}

// **ولا نوعَ `StoreOrder` هنا (حُذف 2026-10-08).** كان تعريفاً وبانيةً بلا
// `fromFirestore` وبلا مرجعٍ واحدٍ في المستودع: طلباتُ المتجرِ تَنتقلُ بين
// الشاشاتِ خرائطَ خامّةً (`Map<String, dynamic>`) كما تَنتقلُ طلباتُ الخدمة —
// وهو سببُ حذفِ `lib/models/order_model.dart` نفسُه، مجموعةً إلى الجانب.
//
// ولم يَرَه `no_dead_code_test`: حقولُه أسماءٌ عامّةٌ (`id`، `items`،
// `status`) تَتصادمُ مع نظائرِها في كلِّ نموذج، وهو العمى المُعلَنُ في رأسِ
// ذلك الحارس — وعلاجُه المُعلَنُ قائمةُ منعٍ صريحة، في
// `test/unread_user_fields_test.dart`.
class ZyiarahStoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// [audience] يصفّي محلياً ('client'/'companies')؛ null = الكل — تستعمله
  /// ورقة السلة لتحلّ أسماء منتجاتها أياً كان جمهورها. التصفية محلية لأن
  /// المستندات القديمة بلا حقل store_audience ولا يمكن استعلام «غائب أو يساوي».
  Stream<List<StoreProduct>> streamProducts({String? audience}) {
    return _db.collection('products')
        .where('is_hidden', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StoreProduct.fromFirestore(doc))
            .where((p) => audience == null || p.audience == audience)
            .toList())
        .firstEventTimeout();
  }

  /// إنشاء طلب متجر بحالة `awaiting_payment` — **لا موافقةَ قبل الدفع**
  /// (قرارُ المالك): الدورةُ `awaiting_payment ⇒ under_review ⇒ delivering
  /// ⇒ delivered`، فالمراجعةُ تَلي الدفعَ لا تَسبقُه. والدفعُ وتوليدُ
  /// الفاتورةِ عبر [StorePaymentScreen].
  ///
  /// (وكان هذا الشرحُ يَقولُ «بانتظار موافقة الإدارة (بدون دفع) … بعد اعتماد
  /// الإدارة للطلب» — وهو عكسُ ما يَكتبُه السطرُ أدناه وعكسُ القرار.)
  Future<Map<String, dynamic>?> createStoreOrder({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    String clientName = 'عميل زيارة';
    String clientPhone = '000000000';
    // بريد العميل يُحفظ على الطلب كي يُرسل المُشغّل الخادمي إيميل تحديث الحالة إليه
    // (تحت المراجعة/جاري التوصيل/تم التسليم) بلا جلبٍ إضافي.
    String? clientEmail = user.email;
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get().timeout(kNetCallTimeout);
      if (userDoc.exists) {
        clientName = userDoc.data()?['name'] ?? 'عميل زيارة';
        clientPhone = userDoc.data()?['phone'] ?? '000000000';
        clientEmail = userDoc.data()?['email'] ?? user.email;
      }
    } catch (e) {
      // Fallback
    }

    // Atomic: increment counter + create store order in one Transaction
    final docRef = _db.collection('store_orders').doc();
    String orderCode = '';
    double serverCalculatedTotal = 0.0;

    await _db.runTransaction((transaction) async {
      // ─── 1) جميع القراءات أولاً ───
      // متطلّب Firestore: يجب تنفيذ كل القراءات قبل أي كتابة داخل المعاملة.
      // كان العدّاد (قراءة + كتابة) يُستدعى قبل قراءة المنتجات، ما يجعل
      // transaction.get للمنتجات يأتي بعد كتابة العدّاد → استثناء وفشل كل طلب متجر.
      double tempTotal = 0.0;
      final List<Map<String, dynamic>> verifiedItems = [];

      for (final item in items) {
        final productId = item['id'] as String? ?? '';
        final quantity = (item['quantity'] as num?)?.toInt() ?? 1;

        if (productId.isEmpty) continue;

        final productRef = _db.collection('products').doc(productId);
        final productSnap = await transaction.get(productRef);

        if (!productSnap.exists) {
          throw Exception('المنتج غير موجود في قاعدة البيانات: $productId');
        }

        final productData = productSnap.data();
        final name = productData?['name'] as String? ?? 'منتج غير معروف';
        final price = (productData?['price'] as num?)?.toDouble() ?? 0.0;

        tempTotal += price * quantity;
        verifiedItems.add({
          'id': productId,
          'name': name,
          'quantity': quantity,
          'price': price,
        });
      }

      // الضريبة 15% تُضاف فوق مجموع أسعار المنتجات (قرار المالك). total_amount هو
      // الإجمالي شامل الضريبة = ما يدفعه العميل، وهو ما تطابقه verifyMoyasarPayment.
      serverCalculatedTotal = grossFromBaseRounded(tempTotal);

      // ─── 2) العدّاد (قراءة ثم كتابة) — بعد كل قراءات المنتجات ───
      final nextId = await ZyiarahCounterService().getNextOrderNumber(transaction);
      orderCode = ZyiarahOrderUtil.formatSmartCode(nextId);

      // ─── 3) الكتابة النهائية ───
      transaction.set(docRef, {
        'code': orderCode,
        'client_id': user.uid,
        'client_name': clientName,
        'client_phone': clientPhone,
        'client_email': clientEmail,
        'items': verifiedItems,
        'total_amount': serverCalculatedTotal,
        'payment_method': 'pending',
        'is_paid': false,
        // (المتجر المباشر — قرار المالك) لا موافقة قبل الدفع: يُنشأ بانتظار
        // الدفع مباشرةً، وبعد تأكيده تديره الإدارة نقرةً نقرة:
        // under_review ⇒ delivering ⇒ delivered — والعميل يُشعَر بكل نقلة.
        'payment_status': 'awaiting_payment',
        'status': 'awaiting_payment',
        'created_at': FieldValue.serverTimestamp(),
      });
    });

    // Audit Log
    ZyiarahAuditService().logAction(
      action: 'CREATE_STORE_ORDER',
      details: {
        'code': orderCode,
        'amount': serverCalculatedTotal,
        'client': clientName,
        'item_count': items.length,
      },
      targetId: docRef.id,
    );

    // الفاتورة الضريبية تُولَّد بعد الدفع في StorePaymentScreen (يفتحها
    // التطبيق فوراً بعد هذا الإنشاء — لا موافقة إدارية قبل الدفع).

    return {
      'id': docRef.id,
      'code': orderCode,
      'total': serverCalculatedTotal,
      'client_name': clientName,
      'client_phone': clientPhone,
    };
  }

}
