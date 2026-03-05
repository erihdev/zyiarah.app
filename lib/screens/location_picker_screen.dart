import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationPickerScreen extends StatefulWidget {
  final String serviceName;
  const LocationPickerScreen({super.key, required this.serviceName});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

import 'package:flutter_dotenv/flutter_dotenv.dart';

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  final String _mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final url = Uri.parse(
          'https://api.mapbox.com/search/geocode/v6/forward?q=${Uri.encodeComponent(query)}&access_token=$_mapboxToken&language=ar&country=sa');
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _searchResults = data['features'] ?? [];
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _selectLocation(dynamic feature) {
    final coordinates = feature['geometry']['coordinates'];
    // Mapbox returns [longitude, latitude]
    final double lng = coordinates[0];
    final double lat = coordinates[1];
    
    final geoPoint = GeoPoint(lat, lng);
    Navigator.pop(context, geoPoint);
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
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: "ابحث عن شارع، حي، أو معلم...",
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1E3A8A)),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final feature = _searchResults[index];
                  final properties = feature['properties'];
                  
                  final title = properties['name'] ?? properties['full_address'] ?? 'موقع غير معروف';
                  final subtitle = properties['place_formatted'] ?? '';

                  return ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.blueAccent),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                    onTap: () => _selectLocation(feature),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
