import 'package:geolocator/geolocator.dart';

class ZyiarahLocationService {
  static final ZyiarahLocationService _instance = ZyiarahLocationService._internal();
  factory ZyiarahLocationService() => _instance;
  ZyiarahLocationService._internal();

  /// Just checks/requests permission without necessarily waiting for a lock.
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }
}
