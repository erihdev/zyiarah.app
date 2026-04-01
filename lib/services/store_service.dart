import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StoreProduct {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String description;
  final bool isHidden;

  StoreProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.description = "",
    this.isHidden = false,
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

  Stream<List<StoreProduct>> streamProducts() {
    return _db.collection('products')
        .where('is_hidden', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StoreProduct.fromFirestore(doc))
            .toList());
  }

  Future<void> createStoreOrder({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    String paymentMethod = 'cash_on_delivery',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String clientName = 'عميل زيارة';
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        clientName = userDoc.data()?['name'] ?? 'عميل زيارة';
      }
    } catch (e) {
      // Fallback to anonymous
    }

    await _db.collection('store_orders').add({
      'client_id': user.uid,
      'client_name': clientName,
      'items': items,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
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
        'description': 'منتج عالي الجودة من شركة Swift Clean',
        'is_hidden': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }
}
