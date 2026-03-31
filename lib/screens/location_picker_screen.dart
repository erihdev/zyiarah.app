import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:zyiarah/services/location_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final String serviceName;
  final int? hours;
  final DateTime? serviceDate;
  final double? amount;
  final String? zoneName;

  const LocationPickerScreen({
    super.key, 
    required this.serviceName,
    this.hours,
    this.serviceDate,
    this.amount,
    this.zoneName,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  Timer? _debounce;
  List<dynamic> _searchResults = [];
  LatLng _selectedLatLng = const LatLng(24.7136, 46.6753); // Default: Riyadh
  bool _isMapReady = false;

  final String _mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';

  @override
  void initState() {
    super.initState();
    _setInitialLocation();
  }

  Future<void> _setInitialLocation() async {
    final position = await ZyiarahLocationService().getCurrentLocation();
    if (position != null) {
      setState(() {
        _selectedLatLng = LatLng(position.latitude, position.longitude);
        _isMapReady = true;
      });
      _mapController.move(_selectedLatLng, 15.0);
    } else {
      setState(() => _isMapReady = true);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    try {
      final url = Uri.parse(
          'https://api.mapbox.com/search/geocode/v6/forward?q=${Uri.encodeComponent(query)}&access_token=$_mapboxToken&language=ar&country=sa');
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _searchResults = data['features'] ?? [];
        });
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
      });
    }
  }

  void _selectSearchResult(dynamic feature) {
    final coordinates = feature['geometry']['coordinates'];
    final double lng = coordinates[0].toDouble();
    final double lat = coordinates[1].toDouble();
    
    final newLatLng = LatLng(lat, lng);
    setState(() {
      _selectedLatLng = newLatLng;
      _searchResults = [];
      _searchController.clear();
    });
    _mapController.move(newLatLng, 15.0);
    FocusScope.of(context).unfocus();
  }

  void _confirmLocation() {
    final geoPoint = GeoPoint(_selectedLatLng.latitude, _selectedLatLng.longitude);
    if (widget.hours != null) {
      Navigator.pop(context, {
        'location': geoPoint,
        'hours': widget.hours,
        'serviceDate': widget.serviceDate,
        'amount': widget.amount,
        'zoneName': widget.zoneName,
      });
    } else {
      Navigator.pop(context, geoPoint);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("تحديد موقع - ${widget.serviceName}"),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            if (_isMapReady)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedLatLng,
                  initialZoom: 15.0,
                  onPositionChanged: (position, hasGesture) {
                    if (hasGesture) {
                      setState(() {
                        _selectedLatLng = position.center;
                      });
                    }
                  },
                ),
                children: [
                   TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$_mapboxToken',
                    additionalOptions: {'accessToken': _mapboxToken},
                  ),
                ],
              ),
            
            // Fixed marker in center
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_on, color: Color(0xFF50B498), size: 45),
              ),
            ),

            // Search Bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: "ابحث عن شارع، حي، أو معلم...",
                        prefixIcon: Icon(Icons.search, color: Color(0xFF5D1B5E)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 15),
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final feature = _searchResults[index];
                          final props = feature['properties'];
                          return ListTile(
                            title: Text(props['name'] ?? props['full_address'] ?? ''),
                            subtitle: Text(props['place_formatted'] ?? ''),
                            onTap: () => _selectSearchResult(feature),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Confirm Button
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _confirmLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5D1B5E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: roundedRectangleCircular(20),
                ),
                child: const Text("تأكيد هذا الموقع", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for consistent rounding
  OutlinedBorder roundedRectangleCircular(double radius) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }
}
