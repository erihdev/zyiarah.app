import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// ZyiarahCapacityService — Centralized fleet availability management.
/// Prevents overbooking by checking active order count against a configurable
/// capacity threshold fetched from Firestore system settings.
class ZyiarahCapacityService {
  // Singleton
  static final ZyiarahCapacityService _instance =
      ZyiarahCapacityService._internal();
  factory ZyiarahCapacityService() => _instance;
  ZyiarahCapacityService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Cache the max capacity to avoid repeated Firestore reads per slot check
  int? _cachedMaxTeams;

  /// Fetches (and caches) the maximum number of teams allowed per slot from
  /// `system_configs/main_settings.max_teams_per_slot`.
  /// Defaults to 5 if the document or field does not exist.
  Future<int> _getMaxTeamsPerSlot() async {
    if (_cachedMaxTeams != null) return _cachedMaxTeams!;
    try {
      final doc = await _db
          .collection('system_configs')
          .doc('main_settings')
          .get();
      _cachedMaxTeams =
          (doc.data()?['max_teams_per_slot'] as num?)?.toInt() ?? 5;
    } catch (e) {
      debugPrint('[ZyiarahCapacityService] Failed to fetch config: $e');
      _cachedMaxTeams = 5; // safe fallback
    }
    return _cachedMaxTeams!;
  }

  /// Invalidates the cached max teams value so the next call re-fetches.
  /// Call this if you know the config has been updated.
  void invalidateCache() => _cachedMaxTeams = null;

  /// Core availability check.
  ///
  /// Parameters:
  /// - [date]: The booking date.
  /// - [timeSlot]: The start hour as a zero-padded string, e.g. `"09:00"`.
  /// - [zoneId]: The zone name / identifier to scope the check.
  ///
  /// Returns `true` if the slot has capacity, `false` if fully booked.
  Future<bool> checkSlotAvailability({
    required DateTime date,
    required String timeSlot,
    required String zoneId,
  }) async {
    try {
      final int maxTeams = await _getMaxTeamsPerSlot();

      // Normalize date to a consistent string key: "yyyy-MM-dd"
      final String dateKey = DateFormat('yyyy-MM-dd').format(date);

      // Count active bookings matching date + timeSlot + zone (exclude cancelled)
      final snapshot = await _db
          .collection('orders')
          .where('booking_date', isEqualTo: dateKey)
          .where('booking_time_slot', isEqualTo: timeSlot)
          .where('zone_name', isEqualTo: zoneId)
          .get();

      // Filter out any cancelled orders (belt-and-suspenders guard)
      final activeCount = snapshot.docs
          .where((doc) => doc.data()['status'] != 'cancelled')
          .length;

      debugPrint(
        '[ZyiarahCapacityService] $dateKey $timeSlot @ $zoneId — '
        'active=$activeCount / max=$maxTeams',
      );

      return activeCount < maxTeams;
    } catch (e) {
      debugPrint('[ZyiarahCapacityService] checkSlotAvailability error: $e');
      // Fail open: allow the slot so user is not blocked by a Firestore error
      return true;
    }
  }

  /// Convenience batch check: returns a map of timeSlot → isAvailable
  /// for all provided slots on a given date in a given zone.
  Future<Map<String, bool>> checkAllSlots({
    required DateTime date,
    required List<String> timeSlots,
    required String zoneId,
  }) async {
    final Map<String, bool> result = {};
    for (final slot in timeSlots) {
      result[slot] = await checkSlotAvailability(
        date: date,
        timeSlot: slot,
        zoneId: zoneId,
      );
    }
    return result;
  }
}
