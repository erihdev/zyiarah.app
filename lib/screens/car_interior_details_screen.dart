import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/car_line.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';

/// تنظيف داخلية السيارة — **خدمة مجدولة مسعّرة** على نمط المكيفات: تنظيف عميق
/// لمراتب السيارة وأسقفها. الإدارة تسعّر ثلاثة أحجام (صغيرة/وسط/كبيرة) لكل منطقة،
/// والعميل يختار الحجم والعدد **ويحدّد يوماً ووقتاً** ويدفع فوراً ويُسنَد السائق
/// تلقائياً — مثل بقية الخدمات (قرار المالك). «بلا سعر ⇒ بلا بيع».
class CarInteriorDetailsScreen extends StatefulWidget {
  final String serviceName;
  const CarInteriorDetailsScreen(
      {super.key, this.serviceName = 'تنظيف داخلية السيارة'});

  @override
  State<CarInteriorDetailsScreen> createState() =>
      _CarInteriorDetailsScreenState();
}

class _CarInteriorDetailsScreenState extends State<CarInteriorDetailsScreen> {
  static const Color _brand = Color(0xFF006FBA);

  bool _isLoading = true;

  /// الأسعار الثلاثة لهذه المنطقة. صفر/غائب = غير مسعّرة ⇒ الحجم معطّل.
  final Map<String, double> _prices = {};

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<Map<String, dynamic>> _zones = [];

  /// عدد السيارات لكل حجم (مفتاحه حقل السعر) — شبكة العدّادات المباشرة نفسها
  /// التي اعتمدها المالك للمكيفات: كل الأحجام بأسعارها مرئية قبل أي لمسة.
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    try {
      final zones = await ZyiarahZoneLocator.fetchZones();
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _isLoading = false;
      });
      _attemptAutoLocation();
    } catch (e) {
      debugPrint('[CarInterior] fetchZones failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// **بلا سعر ⇒ بلا بيع.** لا قيمة افتراضية عند الغياب.
  void _applyZone(Map<String, dynamic> zone) {
    _prices.clear();
    for (final size in CarSize.values) {
      final field = carPriceField(size);
      _prices[field] = (zone[field] as num?)?.toDouble() ?? 0;
    }
    _counts.removeWhere((field, _) => (_prices[field] ?? 0) <= 0);
  }

  bool _isEnabled(CarSize size) => (_prices[carPriceField(size)] ?? 0) > 0;

  int _countOf(CarSize size) => _counts[carPriceField(size)] ?? 0;

  void _setCount(CarSize size, int v) {
    HapticFeedback.selectionClick();
    setState(() {
      _counts[carPriceField(size)] = v.clamp(0, 10);
      _selectedSlot = null; // المدة تغيّرت ⇒ خانات البدء تُعاد
    });
  }

  bool get _anyEnabled => CarSize.values.any(_isEnabled);

  Future<void> _attemptAutoLocation({bool userInitiated = false}) async {
    if (!mounted || _zones.isEmpty) return;
    setState(() {
      _isLocating = true;
      _locateFailure = null;
    });

    final res = await ZyiarahZoneLocator.locate(_zones,
        requestPermission: userInitiated);
    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _isLocating = false;
        _locateFailure = res.failure;
        if (res.location != null) _selectedLocation = res.location;
      });
      return;
    }

    setState(() {
      _selectedLocation = res.location;
      _selectedZoneName = res.zoneName;
      _applyZone(res.zone!);
      _selectedSlot = null;
      _isLocating = false;
      _locateFailure = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم تحديد موقعك تلقائياً: $_selectedZoneName',
          style: GoogleFonts.tajawal()),
      backgroundColor: _brand,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(
          serviceName: 'تحديد موقع تنظيف السيارة',
        ),
      ),
    );
    if (!mounted || result is! GeoPoint) return;

    final zone = ZyiarahZoneLocator.matchZone(result, _zones);
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
      _selectedSlot = null;
      _locateFailure = null;
    });
  }

  double get totalAmount => CarSize.values.fold(0.0, (acc, s) {
        final field = carPriceField(s);
        return acc + (_counts[field] ?? 0) * (_prices[field] ?? 0);
      });

  // الأساس = مجموع الأسعار المُدخلة؛ الضريبة 15% **تُضاف** فوقه (قرار المالك).
  double get subTotal => totalAmount; // الأساس
  double get vat => totalAmount * 0.15; // 15% مضافة فوق الأساس
  double get grandTotal => totalAmount + vat; // ما يدفعه العميل (شامل الضريبة)

  int get totalCars => _counts.values.fold(0, (a, v) => a + v);

  /// ساعة لكل سيارة، بحدٍّ أدنى ساعتين وسقف 8 (نفس منطق المكيفات — تجاوز 8 يُفرغ
  /// خانات البدء 8→22 فلا يستطيع العميل الحجز).
  int get _durationHours => totalCars.clamp(2, 8);

  void _handleNext() {
    if (_selectedLocation == null) {
      _snack('يرجى تحديد موقعك أولاً');
      return;
    }
    if (totalAmount <= 0) {
      _snack('أضف سيارة واحدة على الأقل');
      return;
    }
    if (_selectedSlot == null) {
      _snack('اختر اليوم ووقت البدء');
      return;
    }

    final meta = {
      'kind': 'car_interior',
      'total_cars': totalCars,
      'lines': [
        for (final size in CarSize.values)
          if (_countOf(size) > 0)
            CarLine(size: size, count: _countOf(size))
                .toMap(_prices[carPriceField(size)] ?? 0),
      ],
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          serviceName: '${widget.serviceName} (${_selectedZoneName ?? ''})',
          amount: grandTotal, // الأساس + 15% — شاشة الدفع تعامله كإجمالي
          location: _selectedLocation!,
          zoneName: _selectedZoneName,
          // hours + serviceDate = طلب مباشر مجدول: فحص سعة ⇒ pending ⇒ إسناد
          // تلقائي ⇒ scheduled (مثل بقية الخدمات).
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
                          _aboutCard(),
                          const SizedBox(height: 18),
                          _locationCard(),
                          if (_selectedLocation != null) ...[
                            const SizedBox(height: 26),
                            if (!_anyEnabled)
                              _unpricedBanner()
                            else ...[
                              _linesSection(),
                              const SizedBox(height: 26),
                              if (totalCars > 0) ...[
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
                              child: Text('حدّد موقعك لعرض أسعار منطقتك',
                                  style:
                                      GoogleFonts.tajawal(color: Colors.grey)),
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
          'assets/images/car_cleaning.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF1F5F9),
            child: const Icon(Icons.directions_car_filled_rounded,
                color: Color(0xFF475569), size: 60),
          ),
        ),
      );

  /// التعريف الذي طلبه المالك: ما الذي تشمله الخدمة بالضبط.
  Widget _aboutCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _brand.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _brand.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car_filled_rounded,
                    size: 18, color: _brand),
                const SizedBox(width: 8),
                Text('ما الذي تشمله الخدمة؟',
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _brand)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'تنظيف عميق لداخلية السيارة: المراتب (المقاعد) — في موقعك.',
                style: GoogleFonts.tajawal(
                    fontSize: 12.5,
                    height: 1.7,
                    color: const Color(0xFF475569))),
          ],
        ),
      );

  Widget _locationCard() => ZyiarahZoneLocationCard(
        isLocating: _isLocating,
        zoneName: _selectedZoneName,
        failure: _locateFailure,
        onLocateMe: () => _attemptAutoLocation(userInitiated: true),
        onPickManually: _pickLocation,
      );

  Widget _unpricedBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text('خدمة تنظيف السيارات غير متاحة في منطقتك حالياً.',
            style: GoogleFonts.tajawal(
                color: const Color(0xFF92400E), height: 1.6, fontSize: 13)),
      );

  Widget _linesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('السيارات المطلوبة',
            style: GoogleFonts.tajawal(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B))),
        Text('كل حجم بسعره للسيارة الواحدة — زد العدد أمام ما تحتاجه.',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 12),
        // الأحجام المسعّرة فقط تُعرض: «بلا سعر ⇒ بلا بيع».
        ...[
          for (final size in CarSize.values)
            if (_isEnabled(size)) _sizeRow(size),
        ],
      ],
    );
  }

  Widget _sizeRow(CarSize size) {
    final field = carPriceField(size);
    final price = _prices[field] ?? 0;
    final count = _countOf(size);
    final active = count > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? _brand : const Color(0xFFE2E8F0),
          width: active ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                switch (size) {
                  CarSize.small => Icons.directions_car_rounded,
                  CarSize.medium => Icons.airport_shuttle_rounded,
                  CarSize.large => Icons.local_shipping_rounded,
                },
                size: 18,
                color: active ? _brand : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('سيارة ${size.label}',
                        style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: const Color(0xFF1E293B))),
                    Text('${price.toStringAsFixed(0)} ر.س للسيارة الواحدة',
                        style: GoogleFonts.tajawal(
                            fontSize: 12, color: const Color(0xFF64748B))),
                  ],
                ),
              ),
              _stepper(Icons.remove_rounded, count > 0,
                  () => _setCount(size, count - 1)),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text('$count',
                    style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: active ? _brand : const Color(0xFFCBD5E1))),
              ),
              _stepper(Icons.add_rounded, count < 10,
                  () => _setCount(size, count + 1)),
            ],
          ),
          if (active) ...[
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$count × ${price.toStringAsFixed(0)} ر.س',
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: const Color(0xFF64748B))),
                Text('${(count * price).toStringAsFixed(2)} ر.س',
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold, color: _brand)),
              ],
            ),
          ],
        ],
      ),
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
              size: 18, color: enabled ? _brand : const Color(0xFFCBD5E1)),
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
          _row('عدد السيارات:', '$totalCars'),
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
              Text('${grandTotal.toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: _brand)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: ready ? 4 : 0,
        ),
        child: Text('متابعة لملخص الدفع',
            style: GoogleFonts.tajawal(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }
}
