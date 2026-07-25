import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/utils/jazan_boundary.dart';

class LocationPickerScreen extends StatefulWidget {
  final String serviceName;
  final int? hours;
  final DateTime? serviceDate;
  final double? amount;
  final String? zoneName;
  final int workerCount;
  final double? radius;
  final Color? circleColor;

  const LocationPickerScreen({
    super.key, 
    required this.serviceName,
    this.hours,
    this.serviceDate,
    this.amount,
    this.zoneName,
    this.workerCount = 1,
    this.radius,
    this.circleColor,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  Timer? _debounce;
  List<dynamic> _searchResults = [];
  // الافتراضي: مدينة جازان — الخدمة محصورة بمنطقة جازان (كان الرياض خارج النطاق).
  LatLng _selectedLatLng = const LatLng(16.8894, 42.5706);
  bool _isMapReady = false;
  // هل حدّد المستخدم موقعه فعلاً (GPS دقيق / تحريك الخريطة / نتيجة بحث)؟ لتفادي
  // اعتماد الموقع الافتراضي (الرياض) بصمت لمستخدم في مدينة أخرى.
  bool _userSelected = false;

  /// سبب تعذّر التحديد التلقائي — يُعرض بدل ترك الدبوس على الرياض بلا تفسير.
  LocateFailure? _locateFailure;
  bool _isLocating = false;

  final String _mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';

  @override
  void initState() {
    super.initState();
    _locateMe();
  }

  /// يضع الدبوس على موقع المستخدم — **ويقول لماذا إن لم يستطع.**
  ///
  /// كان مسار الفشل صامتاً تماماً: يسقط على الرياض (24.71, 46.67) فيرى مستخدمٌ في
  /// جازان خريطة الرياض بلا كلمة واحدة عن السبب — فيظنّ أن التطبيق يعرض مكاناً
  /// عشوائياً. (تحذير `_userSelected` يمنع تأكيد الافتراضي بصمت، لكنه علاجُ عرَضٍ
  /// سببُه هذا الصمت.)
  ///
  /// ولم يكن ثمّة زرّ «موقعي» إطلاقاً: إن فشل التحديد مرّة، فلا سبيل لإعادة المحاولة
  /// بعد منح الإذن سوى إغلاق الشاشة وفتحها.
  ///
  /// المُحدِّد المشترك يعطينا المهلة نفسها وتصنيف الأسباب نفسه في كل الشاشات.
  /// [userInitiated] من زرّ «موقعي» يطلب الإذن صراحةً.
  Future<void> _locateMe({bool userInitiated = false}) async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _locateFailure = null;
    });

    // نستعمل المُحدِّد المشترك: نفس المهلة ونفس تصنيف الأسباب في كل الشاشات.
    final res = await ZyiarahZoneLocator.locate(const [],
        requestPermission: userInitiated);
    if (!mounted) return;

    // zones فارغة ⇒ outOfServiceArea يعني «حُدِّد الموقع بنجاح» هنا: هذه الشاشة
    // تختار نقطة على الخريطة ولا تعنيها المناطق.
    final GeoPoint? loc = res.location;
    if (loc != null) {
      setState(() {
        _selectedLatLng = LatLng(loc.latitude, loc.longitude);
        _userSelected = true;
        _isMapReady = true;
        _isLocating = false;
        _locateFailure = null;
      });
      _mapController.move(_selectedLatLng, 16.0);
      return;
    }

    setState(() {
      _isLocating = false;
      _isMapReady = true; // تُعرض الخريطة دائماً — الاختيار اليدوي متاح
      _locateFailure = res.failure;
    });
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
          // bbox: قصر نتائج البحث على منطقة جازان فقط (لا مدن/مناطق أخرى).
          'https://api.mapbox.com/search/geocode/v6/forward?q=${Uri.encodeComponent(query)}&access_token=$_mapboxToken&language=ar&country=sa'
          '&bbox=${kJazanSw.longitude},${kJazanSw.latitude},${kJazanNe.longitude},${kJazanNe.latitude}');
      
      // بمهلة: طلب معلّق كان يترك البحث بلا استجابة إلى الأبد.
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return; // حارس ضروري: setState بعد إغلاق الشاشة يرمي
      setState(() {
        _searchResults =
            response.statusCode == 200 ? (json.decode(response.body)['features'] ?? []) : [];
      });
    } catch (e) {
      debugPrint('[LocationPicker] search failed: $e');
      // كان setState هنا بلا حارس mounted، فيرمي داخل الـ catch نفسه — استثناء
      // ثانٍ لا يلتقطه أحد بينما نحن أصلاً في مسار معالجة خطأ.
      if (!mounted) return;
      setState(() => _searchResults = []);
    }
  }

  void _selectSearchResult(dynamic feature) {
    // احرس ضد نتيجة بحث بلا geometry/إحداثيات → تجنّب انهيار المنتقي وسط الحجز.
    final geometry = feature is Map ? feature['geometry'] : null;
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (coordinates is! List || coordinates.length < 2) return;
    final double lng = (coordinates[0] as num).toDouble();
    final double lat = (coordinates[1] as num).toDouble();

    final newLatLng = LatLng(lat, lng);
    setState(() {
      _selectedLatLng = newLatLng;
      _userSelected = true;
      _searchResults = [];
      _searchController.clear();
    });
    _mapController.move(newLatLng, 15.0);
    FocusScope.of(context).unfocus();
  }

  void _confirmLocation() async {
    // إن لم يحدّد المستخدم موقعه (GPS مرفوض ولم يحرّك الخريطة) نحذّره قبل اعتماد
    // الموقع الافتراضي — منعاً لإرسال الفريق لمدينة خاطئة بصمت.
    if (!_userSelected) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حدّد موقعك على الخريطة'),
            content: const Text(
                'لم تُحدِّد موقعك بعد. حرّك الخريطة على موقعك الصحيح لتفادي وصول الفريق '
                'لمكان خاطئ. هل تريد المتابعة بالموقع الظاهر حالياً؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('أُحدّد موقعي')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('متابعة')),
            ],
          ),
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;
    // الخدمة محصورة بمنطقة جازان — لا يُعتمد موقعٌ خارج حدودها الإدارية.
    if (!isInJazan(_selectedLatLng)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الموقع خارج نطاق منطقة جازان — حرّك الخريطة داخل حدود المنطقة'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final geoPoint = GeoPoint(_selectedLatLng.latitude, _selectedLatLng.longitude);
    if (widget.hours != null) {
      Navigator.pop(context, {
        'location': geoPoint,
        'hours': widget.hours,
        'serviceDate': widget.serviceDate,
        'amount': widget.amount,
        'zoneName': widget.zoneName,
        'workerCount': widget.workerCount,
      });
    } else {
      Navigator.pop(context, geoPoint);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("تحديد موقع - ${widget.serviceName}"),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            // دوّار صريح بدل شاشة بيضاء: قبل هذا لم يكن يُرسَم شيء إطلاقاً ريثما
            // يُحسم الموقع — فيبدو التطبيق معلّقاً وهو ينتظر GPS.
            if (!_isMapReady)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF660033)),
                    SizedBox(height: 14),
                    Text('جارٍ تحديد موقعك…',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                  ],
                ),
              ),
            if (_isMapReady)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedLatLng,
                  initialZoom: 15.0,
                  // قفل الكاميرا داخل منطقة جازان (بهامش طفيف) — لا تحريك لأي منطقة أخرى.
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      LatLng(kJazanSw.latitude - 0.15, kJazanSw.longitude - 0.15),
                      LatLng(kJazanNe.latitude + 0.15, kJazanNe.longitude + 0.15),
                    ),
                  ),
                  onPositionChanged: (position, hasGesture) {
                    if (hasGesture) {
                      setState(() {
                        _selectedLatLng = position.center;
                        _userSelected = true;
                      });
                    }
                  },
                ),
                children: [
                   // بلاطات OSM القياسية: أسماء محلية (عربية في السعودية) بدل بلاطات
                   // Mapbox النقطية الإنجليزية — وتوحيدٌ مع بقية خرائط التطبيق.
                   TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.zyiarah.zyiarah',
                  ),
                  // قناع «خارج جازان»: مستطيل واسع بثقوبٍ = حلقات المنطقة — يُعتِّم كل
                  // ما حول جازان فلا تظهر إلا محافظاتها وقراها وهجرها، مع حدّ بنفسجي.
                  PolygonLayer(polygons: [
                    Polygon(
                      points: [
                        const LatLng(10, 35), const LatLng(10, 50),
                        const LatLng(25, 50), const LatLng(25, 35),
                      ],
                      holePointsList: kJazanRings,
                      color: const Color(0xCCF1F5F9),
                    ),
                  ]),
                  PolylineLayer(polylines: [
                    for (final ring in kJazanRings)
                      Polyline(
                        points: ring,
                        strokeWidth: 2.5,
                        color: const Color(0xFF660033),
                      ),
                  ]),
                  if (widget.radius != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _selectedLatLng,
                          radius: widget.radius! * 1000, // Convert km to meters
                          useRadiusInMeter: true,
                          color: (widget.circleColor ?? Colors.blue).withValues(alpha: 0.3),
                          borderColor: widget.circleColor ?? Colors.blue,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                ],
              ),
            
            // سبب بقاء الدبوس على الموقع الافتراضي — بدل صمتٍ يبدو عطلاً عشوائياً.
            if (_isMapReady && _locateFailure != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 96,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 18, color: Color(0xFFB45309)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_locateFailure!.message}\nحرّكي الخريطة لتضعي الدبوس على موقعك.',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF92400E), height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // زرّ «موقعي» — كان غائباً تماماً: إن فشل التحديد التلقائي مرّة، لم يكن
            // للمستخدم أي وسيلة لإعادة المحاولة بعد منح الإذن سوى إغلاق الشاشة.
            Positioned(
              left: 16,
              bottom: 96,
              child: FloatingActionButton(
                heroTag: 'locate_me_fab',
                onPressed: _isLocating ? null : () => _locateMe(userInitiated: true),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF660033),
                tooltip: 'موقعي الحالي',
                child: _isLocating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF660033)),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
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
                        prefixIcon: Icon(Icons.search, color: Color(0xFF660033)),
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
                  backgroundColor: const Color(0xFF660033),
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
