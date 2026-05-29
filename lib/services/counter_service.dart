import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahCounterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Gets the next sequential order number using a Firestore Transaction.
  /// This ensures that even if 100 people order at once, they all get unique numbers.
  Future<int> getNextOrderNumber([Transaction? transaction]) async {
    final counterRef = _db.collection('metadata').doc('order_counter');

    Future<int> logic(Transaction tx) async {
      final snapshot = await tx.get(counterRef);

      if (!snapshot.exists) {
        // First order in the system's life
        tx.set(counterRef, {'last_id': 101}); // Starting from 101 for a professional look
        return 101;
      }

      final lastId = snapshot.data()?['last_id'] ?? 100;
      final nextId = lastId + 1;

      tx.update(counterRef, {'last_id': nextId});
      return nextId;
    }

    if (transaction != null) {
      return await logic(transaction);
    } else {
      return await _db.runTransaction(logic);
    }
  }

  /// Gets the next sequential maintenance request number (counter منفصل عن الطلبات).
  /// يمنع استهلاك أرقام الطلبات في حالات الصيانة.
  Future<int> getNextMaintenanceNumber([Transaction? transaction]) async {
    final counterRef = _db.collection('metadata').doc('maintenance_counter');

    Future<int> logic(Transaction tx) async {
      final snapshot = await tx.get(counterRef);

      if (!snapshot.exists) {
        tx.set(counterRef, {'last_id': 101});
        return 101;
      }

      final lastId = snapshot.data()?['last_id'] ?? 100;
      final nextId = lastId + 1;

      tx.update(counterRef, {'last_id': nextId});
      return nextId;
    }

    if (transaction != null) {
      return await logic(transaction);
    } else {
      return await _db.runTransaction(logic);
    }
  }
}
