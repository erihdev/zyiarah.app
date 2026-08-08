import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';

/// حقل سعر ساعة العاملة الواحدة في وثيقة المنطقة — **قبل الضريبة**.
/// صفر/غائب = الخدمة غير مسعّرة لهذه المنطقة ⇒ لا تُباع فيها («بلا سعر ⇒ بلا بيع»).
const String kEventWorkerHourPriceField = 'eventWorkerHourPrice';

/// عاملات للمناسبات — خدمة مجدولة مسعّرة (طلب المالك): العميل يختار **العدد**
/// و**اليوم والساعة** والمدة، والسعر = العدد × الساعات × سعر ساعة العاملة في
/// منطقته. طلب مباشر مدفوع بإسناد سائق تلقائي مثل بقية الخدمات.
class EventWorkersDetailsScreen extends StatefulWidget {
  final String serviceName;
  const EventWorkersDetailsScreen(
      {super.key, this.serviceName = 'عاملات للمناسبات'});

  @override
  State<EventWorkersDetailsScreen> createState() =>
      _EventWorkersDetailsScreenState();
}

class _EventWorkersDetailsScreenState extends State<EventWorkersDetailsScreen> {
  static const Color _brand = Color(0xFF660033);

  /// حدود الاختيار — السقف 12 ساعة يطابق سقف باقات السكن، والحدّ الأدنى ساعتان
  /// لأن أقل من ذلك لا يغطي تنقّل الفريق.
  static const int kMinWorkers = 1;
  static const int kMaxWorkers = 10;
  static const int kMinHours = 2;
  static const int kMaxHours = 12;

  bool _isLoading = true;

  /// سعر ساعة العاملة الواحدة في المنطقة المختارة (قبل الضريبة). صفر = غير مسعّرة.
  double _hourRate = 0;

  int _workers = 2;
  int _hours = 4;

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<Map<String, dynamic>> _zones = [];

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
      // لا نبتلع الفشل بصمت: قائمة مناطق فارغة تجعل زرّ الموقع ميتاً وتتّهم كل
      // موقع زوراً بأنه «خارج النطاق».
      debugPrint('[EventWorkers] fetchZones failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر تحميل مناطق الخدمة: $e',
              style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// **بلا سعر ⇒ بلا بيع.** لا قيمة افتراضية عند الغياب.
  void _applyZone(Map<String, dynamic> zone) {
    _hourRate =
        (zone[kEventWorkerHourPriceField] as num?)?.toDouble() ?? 0;
  }

  bool get _isPriced => _hourRate > 0;

  Future<void> _attemptAutoLocation({bool userInitiated = false}) async {
    if (!mounted) return;
    if (_zones.isEmpty) {
      if (!userInitiated) return;
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[EventWorkers] fetchZones retry failed: $e');
      }
      if (!mounted) return;
      if (_zones.isEmpty) {
        setState(() {
          _isLocating = false;
          _locateFailure = LocateFailure.unknown;
        });
        return;
      }
    }
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
          serviceName: 'تحديد موقع المناسبة',
        ),
      ),
    );
    if (!mounted || result is! GeoPoint) return;

    if (_zones.isEmpty) {
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[EventWorkers] fetchZones retry failed: $e');
      }
      if (!mounted) return;
      if (_zones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'تعذّر تحميل مناطق الخدمة — تحقّقي من اتصالك وأعيدي المحاولة',
              style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

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

  /// الأساس (قبل الضريبة) = العدد × الساعات × سعر الساعة. الضريبة **تُضاف** فوقه.
  double get totalAmount => _workers * _hours * _hourRate;
  double get subTotal => totalAmount;
  double get grandTotal =>
      ((totalAmount * 1.15) * 100).roundToDouble() / 100;

  void _setWorkers(int v) {
    HapticFeedback.selectionClick();
    setState(() {
      _workers = v.clamp(kMinWorkers, kMaxWorkers);
      // عدد العاملات لا يغيّر المدة، لكن السعة تُحسب بعدد الأفراد المطلوبين —
      // فنُعيد اختيار الخانة كي يُعاد فحص التوفّر بالعدد الجديد.
      _selectedSlot = null;
    });
  }

  void _setHours(int v) {
    HapticFeedback.selectionClick();
    setState(() {
      _hours = v.clamp(kMinHours, kMaxHours);
      _selectedSlot = null; // المدة تغيّرت ⇒ خانات البدء تُعاد
    });
  }

  void _handleNext() {
    if (_selectedLocation == null) {
      _snack('يرجى تحديد موقع المناسبة أولاً');
      return;
    }
    if (!_isPriced || totalAmount <= 0) {
      _snack('الخدمة غير مسعّرة في منطقتك حالياً');
      return;
    }
    if (_selectedSlot == null) {
      _snack('اختر اليوم ووقت البدء');
      return;
    }

    final meta = {
      'kind': 'event_workers',
      'workers': _workers,
      'event_hours': _hours,
      // السعر مرجعي للعرض في لوحة الإدارة ولوحة السائق؛ الخادم يعيد حسابه من
      // وثيقة المنطقة ولا يثق بهذا الرقم.
      'hour_rate': _hourRate,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          serviceName: '${widget.serviceName} (${_selectedZoneName ?? ''})',
          amount: grandTotal, // الأساس + 15% — شاشة الدفع تعامله كإجمالي
          location: _selectedLocation!,
          zoneName: _selectedZoneName,
          // hours + serviceDate = طلب مباشر مجدول: فحص سعة ⇒ pending ⇒ إسناد تلقائي.
          hours: _hours,
          workerCount: _workers,
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
                            if (!_isPriced)
                              _unpricedBanner()
                            else ...[
                              _stepperCard(
                                title: 'عدد العاملات',
                                icon: Icons.groups_rounded,
                                value: _workers,
                                min: kMinWorkers,
                                max: kMaxWorkers,
                                suffix: _workersLabel(_workers),
                                onChanged: _setWorkers,
                              ),
                              const SizedBox(height: 16),
                              _stepperCard(
                                title: 'عدد الساعات',
                                icon: Icons.schedule_rounded,
                                value: _hours,
                                min: kMinHours,
                                max: kMaxHours,
                                suffix: _hours == 2
                                    ? 'ساعتان'
                                    : _hours <= 10
                                        ? '$_hours ساعات'
                                        : '$_hours ساعة',
                                onChanged: _setHours,
                              ),
                              const SizedBox(height: 26),
                              ZyiarahBookingSlotPicker(
                                zoneName: _selectedZoneName,
                                durationHours: _hours,
                                onSlotSelected: (dt) =>
                                    setState(() => _selectedSlot = dt),
                              ),
                              const SizedBox(height: 26),
                              _summaryCard(),
                              const SizedBox(height: 24),
                              _nextButton(),
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

  /// عدد العاملات بصيغة عربية سليمة (مفرد/مثنّى/جمع).
  static String _workersLabel(int n) => n == 1
      ? 'عاملة واحدة'
      : n == 2
          ? 'عاملتان'
          : n <= 10
              ? '$n عاملات'
              : '$n عاملة';

  Widget _header() => SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.asset(
          'assets/images/cleaning_hero.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF1F5F9),
            child: const Icon(Icons.celebration_rounded,
                color: Color(0xFF475569), size: 60),
          ),
        ),
      );

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
                const Icon(Icons.celebration_rounded, size: 18, color: _brand),
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
                'عاملات لخدمة مناسباتك: التقديم والضيافة وترتيب المكان وتنظيفه '
                'أثناء المناسبة وبعدها. تختارين العدد والمدة واليوم والساعة، '
                'والسعر يُحسب لكل عاملة في الساعة.',
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
        child: Text('خدمة عاملات المناسبات غير متاحة في منطقتك حالياً.',
            style: GoogleFonts.tajawal(
                color: const Color(0xFF92400E), height: 1.6, fontSize: 13)),
      );

  /// عدّاد ‎−/+‎ بحدود صريحة — الزرّ المعطَّل يُعتَّم بدل أن يبدو حيّاً ولا يستجيب.
  Widget _stepperCard({
    required String title,
    required IconData icon,
    required int value,
    required int min,
    required int max,
    required String suffix,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: const Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(suffix,
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          _stepBtn(Icons.remove_rounded,
              enabled: value > min, onTap: () => onChanged(value - 1)),
          SizedBox(
            width: 44,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900, fontSize: 20, color: _brand)),
          ),
          _stepBtn(Icons.add_rounded,
              enabled: value < max, onTap: () => onChanged(value + 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon,
          {required bool enabled, required VoidCallback onTap}) =>
      Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 20, color: const Color(0xFF334155)),
            ),
          ),
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
          _row('عدد العاملات:', _workersLabel(_workers)),
          const SizedBox(height: 8),
          _row('سعر ساعة العاملة:', '${_hourRate.toStringAsFixed(2)} ر.س'),
          const Divider(height: 22, thickness: 2, color: Color(0xFFE2E8F0)),
          // كل الأسعار المعروضة للعميل **قبل الضريبة** (قرار المالك)؛ الضريبة
          // والإجمالي الشامل يظهران في «تفاصيل الفاتورة» بشاشة إتمام الطلب فقط.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي قبل الضريبة:',
                  style: GoogleFonts.tajawal(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B))),
              Text('${subTotal.toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontSize: 21, fontWeight: FontWeight.w900, color: _brand)),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('تُضاف ضريبة القيمة المضافة 15% عند إتمام الطلب',
                style: GoogleFonts.tajawal(
                    fontSize: 11, color: const Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.tajawal(
                  fontSize: 13, color: const Color(0xFF64748B))),
          Text(value,
              style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B))),
        ],
      );

  Widget _nextButton() => SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _handleNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text('متابعة إلى الدفع',
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );
}
