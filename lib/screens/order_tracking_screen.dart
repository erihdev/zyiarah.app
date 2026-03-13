import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String driverId;
  final GeoPoint destination;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.driverId,
    required this.destination,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription? _driverSubscription;
  LatLng? _driverLocation;
  LatLng? _oldLocation;
  
  // Animation for smooth marker movement
  late AnimationController _moveController;
  Animation<double>? _moveAnimation;

  @override
  void initState() {
    super.initState();
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _startTracking();
  }

  void _startTracking() {
    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final location = data['location'] as GeoPoint?;
        if (location != null) {
          final newLatLng = LatLng(location.latitude, location.longitude);
          
          if (_driverLocation == null) {
            setState(() {
              _driverLocation = newLatLng;
              _oldLocation = newLatLng;
            });
            _mapController.move(newLatLng, 15);
          } else {
            // Start animation from old to new
            _oldLocation = _driverLocation;
            _driverLocation = newLatLng;
            
            _moveAnimation = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: _moveController, curve: Curves.easeInOut),
            )..addListener(() {
                setState(() {}); // Rebuild for marker position
              });
            
            _moveController.forward(from: 0);
          }
        }
      }
    });
  }

  LatLng _getAnimatedLocation() {
    if (_moveAnimation == null || _oldLocation == null || _driverLocation == null) {
      return _driverLocation ?? LatLng(widget.destination.latitude, widget.destination.longitude);
    }
    
    final double t = _moveAnimation!.value;
    final double lat = _oldLocation!.latitude + ((_driverLocation!.latitude - _oldLocation!.latitude) * t);
    final double lng = _oldLocation!.longitude + ((_driverLocation!.longitude - _oldLocation!.longitude) * t);
    return LatLng(lat, lng);
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    _moveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animatedPos = _getAnimatedLocation();
    final dest = LatLng(widget.destination.latitude, widget.destination.longitude);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تتبع السائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: dest,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: const ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: [
                    // Client Destination
                    Marker(
                      point: dest,
                      width: 80,
                      height: 80,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 45),
                    ),
                    // Driver Car
                    Marker(
                      point: animatedPos,
                      width: 80,
                      height: 80,
                      child: Transform.rotate(
                        angle: 0, // Could calculate bearing here
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
                          ),
                          child: const Icon(Icons.directions_car, color: Color(0xFF2563EB), size: 30),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _buildStatusCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Positioned(
      bottom: 30,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFDBEAFE),
                  child: Icon(Icons.person, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('السائق في الطريق إليك', 
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('يتم تحديث الموقع لحظياً', 
                        style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('قريب منك', 
                    style: GoogleFonts.tajawal(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAction(Icons.call, 'اتصال', () {}),
                _buildAction(Icons.message, 'دردشة', () {}),
                _buildAction(Icons.info_outline, 'التفاصيل', () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: Colors.grey[100],
          child: Icon(icon, color: Colors.black87, size: 20),
        ),
        const SizedBox(height: 5),
        Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}
