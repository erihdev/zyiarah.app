import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/counter_service.dart';

class StoreProduct {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String description;
  final bool isHidden;

  /// جمهور المنتج: 'client' (المتجر العادي) أو 'companies' (متجر الشركات).
  /// الغياب = 'client' كي يبقى كل القديم في متجر العميل كما هو حرفياً.
  final String audience;

  StoreProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.description = "",
    this.isHidden = false,
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
      isHidden: data['is_hidden'] ?? false,
      audience: data['store_audience'] ?? 'client',
    );
  }
}

class StoreOrder {
  final String id;
  final String clientId;
  final List<dynamic> items;
  final double totalAmount;
  final String status;
  final DateTime createdAt;

  StoreOrder({
    required this.id,
    required this.clientId,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });
}

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
            .toList());
  }

  /// إنشاء طلب متجر بانتظار موافقة الإدارة (بدون دفع).
  /// الدفع وتوليد طلب التوصيل والفاتورة تتم لاحقاً عبر [StorePaymentScreen]
  /// بعد اعتماد الإدارة للطلب.
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
      final userDoc = await _db.collection('users').doc(user.uid).get();
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
      serverCalculatedTotal = ((tempTotal * 1.15) * 100).roundToDouble() / 100;

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

  // Seeding method to be called once or by admin
  Future<void> seedInitialProducts() async {
    final List<Map<String, dynamic>> initialProducts = [
      {'name': '29.0 - TTS (Italy) - MICRO FIBER CLOTH 40X40 - RED', 'price': 6.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/9ba83c7b-648d-4f5b-8ca1-fba5f2afd005-1000x874.58745874587-g2pYH3Bh3S75e7UFZ8rVedtMOxJkw7aeYt4zKiah.png'},
      {'name': 'TTS (Italy) - SCRAPER WITH 25 CM HANDLE', 'price': 48.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/faa42455-09c7-49a3-bd4b-b40a97d1d484-333.33333333333x500-oJRzbODR20GMZhvc8qXFouH47b5L62bSME31elut.jpg'},
      {'name': 'TTS (Italy) - WET FLOOR SIGN TRIPLE', 'price': 100.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/160ffce4-a363-4d31-a25b-9a8b610e1da8-500x389.01869158879-juAjGEajWSIjrQbpV9q8bg6qgtahAvnM1diFw9pj.png'},
      {'name': 'TTS (Italy) - CARRY CADDY - PLASTIC BOTTLE RACK', 'price': 57.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/4fe8f111-9cbe-4a83-9a8f-1657e07f3d09-357.75862068966x500-QELSrwcc8HjT4kVUHXp0bworWPOHbqOD0iPJOte6.png'},
      {'name': 'TTS (Italy) - TELESCOPIC POLE 3 X 300 CM', 'price': 220.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/5f6f900f-6cec-4776-a499-4af79e7d2d59-500x437.1921182266-wIkihURZOjNTmvQ6KpitMa2TcrjrtScK3ppw94pk.png'},
      {'name': 'PULEX (Italy) - WINDOW APPLICATOR KIT 35 CMS', 'price': 48.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/cc7de78f-1714-4a53-b9c6-fd7887decb32-396.75324675325x500-D3R1klyLC6fmSf8HxvEmlHAGDfQg4WaDe62niuc1.png'},
      {'name': 'ALBARIQ - QMATIC 151, 15L DRY (Vac)', 'price': 650.0, 'image_url': 'https://cdn.salla.sa/rAbDyR/3ace69b8-4719-4327-a643-22dfb5740a21-459.37961595273x500-uAFCUgJnvU6o0Fu4V9l8X9RgOD0IIkhIhXQ7eXV3.png'},
      {'name': 'Nitrorem Stain Remover', 'price': 27.5, 'image_url': 'https://cdn.salla.sa/rAbDyR/e478c226-154e-43fa-b400-08282ee4eeef-500x473.52496217852-EyvMBs6EU5HfLtXPSCJqKllD60aMaHmo6ZWvEu81.png'},
    ];

    for (var p in initialProducts) {
      await _db.collection('products').add({
        ...p,
        'description': 'منتج عالي الجودة من زيارة للتنظيف الذكي',
        'is_hidden': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }
}
