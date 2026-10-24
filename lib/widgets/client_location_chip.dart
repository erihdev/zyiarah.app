import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/services/client_location.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

/// موقعُ العميلةِ أعلى الرئيسيّة: نقطةٌ واسمُ المنطقة (قرار المالك 2026-10-24).
///
/// هنا وحدَه يُطلَبُ إذنُ الموقعِ — عند فتحِ التطبيق — وهنا يُغيَّرُ من
/// الخريطة. شاشاتُ الخدماتِ تَقرأُ النتيجةَ من [ClientLocation] ولا تَرسمُ
/// سطرَ موقع. وعند العودةِ إلى التطبيقِ قراءةٌ صامتةٌ تَلتقطُ التنقّلَ بين
/// المحافظاتِ (ولا تَطغى على اختيارٍ من الخريطة).
///
/// | الحالة | النقطة | النصّ |
/// |---|---|---|
/// | داخلَ منطقةِ خدمة | خضراء | اسمُ المنطقة |
/// | خارجَ النطاق | كهرمانيّة | «خارج نطاق الخدمة» |
/// | جارٍ / لم يُحدَّد | رماديّة | «جارٍ تحديد موقعك…» / «حدّدي موقعك» |
class ClientLocationChip extends StatefulWidget {
  const ClientLocationChip({super.key});

  @override
  State<ClientLocationChip> createState() => _ClientLocationChipState();
}

class _ClientLocationChipState extends State<ClientLocationChip>
    with WidgetsBindingObserver {
  final ClientLocation _loc = ClientLocation.instance;
  List<Map<String, dynamic>> _zones = const [];

  static const _green = Color(0xFF059669);
  static const _amber = Color(0xFFD97706);
  static const _grey = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loc.addListener(_onChange);
    _start();
  }

  @override
  void dispose() {
    _loc.removeListener(_onChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<bool> _ensureZones() async {
    if (_zones.isNotEmpty) return true;
    try {
      _zones = await ZyiarahZoneLocator.fetchZones();
    } catch (e) {
      debugPrint('[ClientLocationChip] fetchZones failed: $e');
    }
    return _zones.isNotEmpty;
  }

  /// أوّلُ فتحٍ للتطبيق: الإذنُ مرّةً هنا لا في كلِّ شاشة.
  ///
  /// يُنادى من `initState` بلا انتظار — فلا يَرمي (قاعدةُ «ما لا يُنتظَرُ
  /// لا يَرمي»): الفشلُ يُسجَّلُ والنقطةُ تبقى رماديّةً «حدّدي موقعك».
  Future<void> _start() async {
    try {
      if (!await _ensureZones()) return;
      await _loc.ensure(_zones);
    } catch (e) {
      debugPrint('[ClientLocationChip] start failed: $e');
    }
  }

  Future<void> _refreshSilently() async {
    try {
      await _loc.refresh(_zones);
    } catch (e) {
      debugPrint('[ClientLocationChip] refresh failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _zones.isNotEmpty) {
      _refreshSilently(); // بلا نافذةِ إذن، ولا تَمحو نقطةً خضراءَ بفشلٍ عابر
    }
  }

  Future<void> _change() async {
    final current = _loc.result?.location;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          serviceName: 'تحديد موقعك',
          initialLocation: current,
        ),
      ),
    );
    if (!mounted || result is! GeoPoint) return;
    if (!await _ensureZones()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر تحميل مناطق الخدمة — تحقّقي من اتصالك وأعيدي المحاولة',
            style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final zone = ZyiarahZoneLocator.matchZone(result, _zones);
    if (!mounted) return;
    if (zone == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('هذا الموقع خارج نطاق خدماتنا حالياً',
            style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
      return;
    }
    _loc.setManual(result, zone);
  }

  @override
  Widget build(BuildContext context) {
    final r = _loc.result;
    final (Color dot, String label) = _loc.isLocating && r == null
        ? (_grey, 'جارٍ تحديد موقعك…')
        : r == null
            ? (_grey, 'حدّدي موقعك')
            : r.isSuccess
                ? (_green, r.zoneName ?? 'موقعك')
                : r.failure == LocateFailure.outOfServiceArea
                    ? (_amber, 'خارج نطاق الخدمة')
                    : (_grey, 'حدّدي موقعك');

    return Semantics(
      button: true,
      label: 'موقعك: $label — اضغطي للتغيير',
      child: InkWell(
        onTap: _change,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tajawal(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: dot == _grey ? const Color(0xFF64748B) : dot,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: dot == _grey ? const Color(0xFF64748B) : dot),
            ],
          ),
        ),
      ),
    );
  }
}
