import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/ac_line.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';

/// صيانة وغسيل المكيفات — **طلب مباشر مسعّر**، لا طلب عرض سعر.
///
/// كانت البلاطة تفتح `ZyiarahMaintenanceRequestScreen` التي تُنشئ
/// `maintenance_requests` بـ `amount: 0.0` و`status: 'under_review'`: العميلة ترسل
/// طلباً، تنتظر الإدارة لتسعّره، ثم تدفع. طلب العميل صريح: الإدارة تحدّد الأسعار
/// مسبقاً، والعميلة تختار النوع والعدد وتدفع فوراً ويُسنَد السائق تلقائياً.
///
/// صيانة الأجهزة المنزلية بقيت على مسار عرض السعر — لا يمكن تسعيرها مسبقاً بصدق.
class AcServiceDetailsScreen extends StatefulWidget {
  final String serviceName;
  const AcServiceDetailsScreen({super.key, this.serviceName = 'صيانة وغسيل المكيفات'});

  @override
  State<AcServiceDetailsScreen> createState() => _AcServiceDetailsScreenState();
}

class _AcServiceDetailsScreenState extends State<AcServiceDetailsScreen> {
  static const Color _brand = Color(0xFF5D1B5E);

  bool _isLoading = true;

  /// الأسعار الأربعة لهذه المنطقة. صفر/غائب = غير مسعّرة ⇒ التركيبة معطّلة.
  final Map<String, double> _prices = {};

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  List<Map<String, dynamic>> _zones = [];
  final List<AcLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('service_zones')
          .where('enabled', isEqualTo: true)
          .get();
      if (!mounted) return;
      final sorted = snapshot.docs.map((d) => d.data()).toList()
        ..sort((a, b) =>
            (a['rank'] as int? ?? 0).compareTo(b['rank'] as int? ?? 0));
      setState(() {
        _zones = sorted;
        _isLoading = false;
      });
      _attemptAutoLocation();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// **بلا سعر ⇒ بلا بيع.** لا قيمة افتراضية عند الغياب: بيعُ خدمة برقمٍ لم تعتمده
  /// الإدارة لهذه المنطقة أسوأ من إظهارها «غير متاحة».
  void _applyZone(Map<String, dynamic> zone) {
    _prices.clear();
    for (final job in AcJob.values) {
      for (final type in AcUnitType.values) {
        final field = acPriceField(job, type);
        _prices[field] = (zone[field] as num?)?.toDouble() ?? 0;
      }
    }
    // أبقِ فقط البنود التي ما زالت مسعّرة في المنطقة الجديدة.
    _lines.removeWhere((l) => _priceOf(l) <= 0);
  }

  double _priceOf(AcLine l) => _prices[acPriceField(l.job, l.type)] ?? 0;

  bool _isEnabled(AcJob job, AcUnitType type) =>
      (_prices[acPriceField(job, type)] ?? 0) > 0;

  bool get _anyEnabled => AcJob.values
      .any((j) => AcUnitType.values.any((t) => _isEnabled(j, t)));

  Map<String, dynamic>? _matchZone(GeoPoint loc) {
    Map<String, dynamic>? matched;
    double minDistance = double.infinity;
    for (final z in _zones) {
      final center = z['centerLoc'];
      if (center is! GeoPoint) continue;
      final radius = ((z['radiusKm'] as num?)?.toDouble() ?? 15.0) * 1000;
      final distance = Geolocator.distanceBetween(
          loc.latitude, loc.longitude, center.latitude, center.longitude);
      if (distance <= radius && distance < minDistance) {
        minDistance = distance;
        matched = z;
      }
    }
    return matched;
  }

  Future<void> _attemptAutoLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = GeoPoint(pos.latitude, pos.longitude);
      final zone = _matchZone(loc);
      if (zone == null || !mounted) return;

      setState(() {
        _selectedLocation = loc;
        _selectedZoneName = zone['name'] as String?;
        _applyZone(zone);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تحديد موقعك تلقائياً: $_selectedZoneName',
            style: GoogleFonts.tajawal()),
        backgroundColor: _brand,
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      // التحديد اليدوي متاح دائماً.
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(
          serviceName: 'تحديد موقع خدمة المكيفات',
        ),
      ),
    );
    if (!mounted || result is! GeoPoint) return;

    final zone = _matchZone(result);
    if (zone == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('نأسف، موقعك خارج نطاق خدماتنا حالياً',
            style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() {
      _selectedLocation = result;
      _selectedZoneName = zone['name'] as String?;
      _applyZone(zone);
      _selectedSlot = null; // المنطقة تغيّرت ⇒ السعة تغيّرت
    });
  }

  double get totalAmount =>
      _lines.fold(0.0, (acc, l) => acc + l.lineTotal(_priceOf(l)));

  double get subTotal => totalAmount / 1.15;
  double get vat => totalAmount - subTotal;

  int get totalUnits => _lines.fold(0, (acc, l) => acc + l.count);

  /// ساعة لكل مكيف، بحد أدنى ساعتين وسقف 8 (طول يوم العمل — وتجاوزه يُفرِغ خانات
  /// البدء 8→22 فلا تستطيع العميلة الحجز إطلاقاً).
  int get _durationHours => totalUnits.clamp(2, 8);

  void _addLine() {
    // أول تركيبة مسعّرة — لا نُضيف بنداً لا يمكن بيعه.
    for (final job in AcJob.values) {
      for (final type in AcUnitType.values) {
        if (_isEnabled(job, type)) {
          HapticFeedback.selectionClick();
          setState(() => _lines.add(AcLine(job: job, type: type)));
          return;
        }
      }
    }
  }

  void _handleNext() {
    if (_selectedLocation == null) {
      _snack('يرجى تحديد موقعك أولاً');
      return;
    }
    if (totalAmount <= 0) {
      _snack('أضيفي مكيفاً واحداً على الأقل');
      return;
    }
    if (_selectedSlot == null) {
      _snack('اختاري اليوم ووقت البدء');
      return;
    }

    final meta = {
      'kind': 'ac_service',
      'total_units': totalUnits,
      'lines': _lines.map((l) => l.toMap(_priceOf(l))).toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          serviceName: '${widget.serviceName} (${_selectedZoneName ?? ''})',
          amount: totalAmount,
          location: _selectedLocation!,
          zoneName: _selectedZoneName,
          // hours + serviceDate = طلب مباشر: فحص سعة ⇒ pending ⇒ إسناد تلقائي.
          hours: _durationHours,
          serviceDate: _selectedSlot,
          serviceMeta: meta,
        ),
      ),
    ).then((success) {
      if (success == true && mounted) Navigator.pop(context, true);
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m, style: GoogleFonts.tajawal())));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(widget.serviceName,
              style: GoogleFonts.tajawal(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3D1040), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _brand))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _header(),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _locationCard(),
                          if (_selectedLocation != null) ...[
                            const SizedBox(height: 26),
                            if (!_anyEnabled)
                              _unpricedBanner()
                            else ...[
                              _linesSection(),
                              const SizedBox(height: 26),
                              if (_lines.isNotEmpty) ...[
                                ZyiarahBookingSlotPicker(
                                  zoneName: _selectedZoneName,
                                  durationHours: _durationHours,
                                  onSlotSelected: (dt) =>
                                      setState(() => _selectedSlot = dt),
                                ),
                                const SizedBox(height: 26),
                                _summaryCard(),
                                const SizedBox(height: 24),
                                _nextButton(),
                              ],
                            ],
                          ] else ...[
                            const SizedBox(height: 40),
                            Center(
                              child: Text('حدّدي موقعك لعرض أسعار منطقتك',
                                  style: GoogleFonts.tajawal(color: Colors.grey)),
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.asset(
          'assets/images/company_cleaning.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF1F5F9),
            child: const Icon(Icons.ac_unit_rounded,
                color: Color(0xFF475569), size: 60),
          ),
        ),
      );

  Widget _locationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('موقع تقديم الخدمة',
              style:
                  GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _brand)),
          const SizedBox(height: 8),
          if (_selectedLocation != null)
            Text('المنطقة: $_selectedZoneName',
                style: GoogleFonts.tajawal(
                    color: const Color(0xFF059669), fontWeight: FontWeight.bold))
          else
            Text('لم يتم تحديد الموقع بعد',
                style: GoogleFonts.tajawal(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(
                _selectedLocation == null ? 'تحديد الموقع' : 'تغيير الموقع',
                style: GoogleFonts.tajawal()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unpricedBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text('خدمة المكيفات غير متاحة في منطقتك حالياً.',
            style: GoogleFonts.tajawal(
                color: const Color(0xFF92400E), height: 1.6, fontSize: 13)),
      );

  Widget _linesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('المكيفات المطلوبة',
            style: GoogleFonts.tajawal(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B))),
        Text('اختاري نوع العمل ونوع المكيف والعدد — ويمكنك إضافة أكثر من نوع.',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 12),
        ...List.generate(_lines.length, (i) => _lineCard(i)),
        if (_lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('لم تُضِف أي مكيف بعد.',
                style: GoogleFonts.tajawal(
                    fontSize: 12, color: const Color(0xFF94A3B8))),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addLine,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('إضافة مكيف', style: GoogleFonts.tajawal()),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            side: BorderSide(color: _brand.withValues(alpha: 0.4)),
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _lineCard(int i) {
    final line = _lines[i];
    final unit = _priceOf(line);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.ac_unit_rounded, size: 18, color: _brand),
              const SizedBox(width: 8),
              Text('مكيف ${i + 1}',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B))),
              const Spacer(),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _lines.removeAt(i);
                    _selectedSlot = null; // المدة تغيّرت ⇒ الخانات تُعاد
                  });
                },
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: Color(0xFFDC2626)),
                visualDensity: VisualDensity.compact,
                tooltip: 'حذف',
              ),
            ],
          ),
          const SizedBox(height: 4),
          _segmented<AcJob>(
            values: AcJob.values,
            current: line.job,
            labelOf: (v) => v.label,
            enabledOf: (v) => _isEnabled(v, line.type),
            onPick: (v) => setState(() {
              _lines[i] = line.copyWith(job: v);
              _selectedSlot = null;
            }),
          ),
          const SizedBox(height: 8),
          _segmented<AcUnitType>(
            values: AcUnitType.values,
            current: line.type,
            labelOf: (v) => v.label,
            enabledOf: (v) => _isEnabled(line.job, v),
            onPick: (v) => setState(() {
              _lines[i] = line.copyWith(type: v);
              _selectedSlot = null;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${unit.toStringAsFixed(0)} ر.س للمكيف',
                  style: GoogleFonts.tajawal(
                      fontSize: 12, color: const Color(0xFF94A3B8))),
              Row(
                children: [
                  _stepper(Icons.remove_rounded, line.count > 1, () {
                    setState(() {
                      _lines[i] = line.copyWith(count: line.count - 1);
                      _selectedSlot = null;
                    });
                  }),
                  Container(
                    width: 44,
                    alignment: Alignment.center,
                    child: Text('${line.count}',
                        style: GoogleFonts.tajawal(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  _stepper(Icons.add_rounded, line.count < 20, () {
                    setState(() {
                      _lines[i] = line.copyWith(count: line.count + 1);
                      _selectedSlot = null;
                    });
                  }),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(line.label,
                  style: GoogleFonts.tajawal(
                      fontSize: 12, color: const Color(0xFF64748B))),
              Text('${line.lineTotal(unit).toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold, color: _brand)),
            ],
          ),
        ],
      ),
    );
  }

  /// مُبدِّل خيارين. الخيار غير المسعّر في هذه المنطقة يظهر معطّلاً بدل أن يُختار
  /// ثم يُفاجَأ به السعر صفراً.
  Widget _segmented<T>({
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required bool Function(T) enabledOf,
    required void Function(T) onPick,
  }) {
    return Row(
      children: values.map((v) {
        final selected = v == current;
        final enabled = enabledOf(v);
        return Expanded(
          child: GestureDetector(
            onTap: enabled && !selected
                ? () {
                    HapticFeedback.selectionClick();
                    onPick(v);
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? _brand
                    : enabled
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? _brand : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Text(
                  enabled ? labelOf(v) : '${labelOf(v)} — غير متاح',
                  style: GoogleFonts.tajawal(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? Colors.white
                        : enabled
                            ? const Color(0xFF475569)
                            : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _stepper(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled
                ? _brand.withValues(alpha: 0.1)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 18,
              color: enabled ? _brand : const Color(0xFFCBD5E1)),
        ),
      );

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)
        ],
      ),
      child: Column(
        children: [
          _row('عدد المكيفات:', '$totalUnits'),
          const Divider(height: 22),
          _row('المجموع الفرعي:', '${subTotal.toStringAsFixed(2)} ر.س'),
          const SizedBox(height: 8),
          _row('ضريبة القيمة المضافة (15%):', '${vat.toStringAsFixed(2)} ر.س',
              muted: true),
          const Divider(height: 22, thickness: 2, color: Color(0xFFE2E8F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي المطلوب:',
                  style: GoogleFonts.tajawal(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B))),
              Text('${totalAmount.toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontSize: 21, fontWeight: FontWeight.w900, color: _brand)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool muted = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.tajawal(
                  color: muted ? Colors.grey : const Color(0xFF64748B),
                  fontSize: 13)),
          Text(value,
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold,
                  color: muted ? Colors.grey : const Color(0xFF1E293B),
                  fontSize: 13)),
        ],
      );

  Widget _nextButton() {
    final ready = totalAmount > 0 && _selectedSlot != null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: ready ? _handleNext : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brand,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: ready ? 4 : 0,
        ),
        child: Text('متابعة لملخص الدفع',
            style: GoogleFonts.tajawal(
                fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}
