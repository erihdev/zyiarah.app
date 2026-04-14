import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahCounterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Gets the next sequential order number using a Firestore Transaction.
  /// This ensures that even if 100 people order at once, they all get unique numbers.
  Future<int> getNextOrderNumber() async {
    final counterRef = _db.collection('metadata').doc('order_counter');

    return await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);

      if (!snapshot.exists) {
        // First order in the system's life
        transaction.set(counterRef, {'last_id': 101}); // Starting from 101 for a professional look
        return 101;
      }

      final lastId = snapshot.data()?['last_id'] ?? 100;
      final nextId = lastId + 1;

      transaction.update(counterRef, {'last_id': nextId});
      return nextId;
    });
  }
}
