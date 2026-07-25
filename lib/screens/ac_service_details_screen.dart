import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/ac_line.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';

/// صيانة وغسيل المكيفات — **طلب مباشر مسعّر**، لا طلب عرض سعر.
///
/// كانت البلاطة تفتح شاشة طلب عرض سعر تُنشئ `maintenance_requests` بـ `amount: 0.0`
/// و`status: 'under_review'`: العميلة ترسل طلباً، تنتظر الإدارة لتسعّره، ثم تدفع.
/// طلب العميل صريح: الإدارة تحدّد الأسعار مسبقاً، والعميلة تختار النوع والعدد وتدفع
/// فوراً ويُسنَد السائق تلقائياً.
///
/// ومسار عرض السعر كلّه (وصيانة الأجهزة المنزلية معه) حُذف بقرار المالك — لم يُستخدم قط.
class AcServiceDetailsScreen extends StatefulWidget {
  final String serviceName;
  const AcServiceDetailsScreen({super.key, this.serviceName = 'صيانة وغسيل المكيفات'});

  @override
  State<AcServiceDetailsScreen> createState() => _AcServiceDetailsScreenState();
}

class _AcServiceDetailsScreenState extends State<AcServiceDetailsScreen> {
  static const Color _brand = Color(0xFF006FBA);

  bool _isLoading = true;

  /// الأسعار الأربعة لهذه المنطقة. صفر/غائب = غير مسعّرة ⇒ التركيبة معطّلة.
  final Map<String, double> _prices = {};

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  /// حالة التحديد التلقائي — تُعرض بدل الصمت.
  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<Map<String, dynamic>> _zones = [];

  /// عدد المكيفات لكل تركيبة (مفتاحها حقل السعر). حلّت محلّ قائمة بنود تُضاف
  /// بزرّ ثم يُختار نوعها بتبديلات — بطلب المالك («غيّر هذه الطريقة»): الأنواع
  /// الأربعة تُعرض مباشرةً بأسعارها، والعميلة تزيد العدد فقط. لا إضافة، لا
  /// تبديل، لا حذف — كل الخيارات وأسعارها مرئية قبل أي لمسة.
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
      debugPrint('[AcService] fetchZones failed: $e');
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
    // صفّر عدّادات التركيبات التي فقدت سعرها في المنطقة الجديدة.
    _counts.removeWhere((field, _) => (_prices[field] ?? 0) <= 0);
  }

  bool _isEnabled(AcJob job, AcUnitType type) =>
      (_prices[acPriceField(job, type)] ?? 0) > 0;

  /// التركيبات بترتيب عرض ثابت: صيانة شباك، صيانة سبليت، غسيل شباك، غسيل سبليت.
  static const List<(AcJob, AcUnitType)> _combos = [
    (AcJob.maintenance, AcUnitType.window),
    (AcJob.maintenance, AcUnitType.split),
    (AcJob.wash, AcUnitType.window),
    (AcJob.wash, AcUnitType.split),
  ];

  int _countOf(AcJob job, AcUnitType type) =>
      _counts[acPriceField(job, type)] ?? 0;

  void _setCount(AcJob job, AcUnitType type, int v) {
    HapticFeedback.selectionClick();
    setState(() {
      _counts[acPriceField(job, type)] = v.clamp(0, 20);
      _selectedSlot = null; // المدة تغيّرت ⇒ الخانات تُعاد
    });
  }

  bool get _anyEnabled => AcJob.values
      .any((j) => AcUnitType.values.any((t) => _isEnabled(j, t)));

  /// تحديد تلقائي **يقول السبب عند الفشل** بدل `catch { /* silent */ }`.
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
          serviceName: 'تحديد موقع خدمة المكيفات',
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

  double get totalAmount => _combos.fold(0.0, (acc, c) {
        final field = acPriceField(c.$1, c.$2);
        return acc + (_counts[field] ?? 0) * (_prices[field] ?? 0);
      });

  // الأساس = مجموع الأسعار المُدخلة؛ الضريبة 15% **تُضاف** فوقه (قرار المالك).
  double get subTotal => totalAmount; // الأساس
  double get vat => totalAmount * 0.15; // 15% مضافة فوق الأساس
  double get grandTotal => totalAmount + vat; // ما يدفعه العميل (شامل الضريبة)

  int get totalUnits => _counts.values.fold(0, (a, v) => a + v);

  /// ساعة لكل مكيف، بحد أدنى ساعتين وسقف 8 (طول يوم العمل — وتجاوزه يُفرِغ خانات
  /// البدء 8→22 فلا تستطيع العميلة الحجز إطلاقاً).
  int get _durationHours => totalUnits.clamp(2, 8);


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
      'lines': [
        for (final (job, type) in _combos)
          if (_countOf(job, type) > 0)
            AcLine(job: job, type: type, count: _countOf(job, type))
                .toMap(_prices[acPriceField(job, type)] ?? 0),
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
                              if (totalUnits > 0) ...[
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
        Text('كل خدمة بسعرها لكل مكيف — زيدي العدد أمام ما تحتاجينه.',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 12),
        // الشبكة المباشرة: كل تركيبة مسعّرة صفٌّ بسعره وعدّاده. لا «إضافة بند» ثم
        // اختيار نوعه بتبديلات — كانت تُخفي الأسعار حتى يُقلَّب بينها (ملاحظة المالك).
        // غير المسعّرة في المنطقة لا تُعرض إطلاقاً: «بلا سعر ⇒ بلا بيع».
        ...[
          for (final (job, type) in _combos)
            if (_isEnabled(job, type)) _comboRow(job, type),
        ],
      ],
    );
  }

  Widget _comboRow(AcJob job, AcUnitType type) {
    final field = acPriceField(job, type);
    final price = _prices[field] ?? 0;
    final count = _countOf(job, type);
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
                job == AcJob.maintenance
                    ? Icons.build_rounded
                    : Icons.water_drop_rounded,
                size: 18,
                color: active ? _brand : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${job.label} مكيف ${type.label}',
                        style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: const Color(0xFF1E293B))),
                    Text('${price.toStringAsFixed(0)} ر.س للمكيف الواحد',
                        style: GoogleFonts.tajawal(
                            fontSize: 12, color: const Color(0xFF64748B))),
                  ],
                ),
              ),
              _stepper(Icons.remove_rounded, count > 0,
                  () => _setCount(job, type, count - 1)),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text('$count',
                    style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: active ? _brand : const Color(0xFFCBD5E1))),
              ),
              _stepper(Icons.add_rounded, count < 20,
                  () => _setCount(job, type, count + 1)),
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
              Text('${grandTotal.toStringAsFixed(2)} ر.س',
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
