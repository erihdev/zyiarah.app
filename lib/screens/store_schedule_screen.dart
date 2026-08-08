import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';

/// جدولة توصيل طلب **متجر الأدوات والتنظيف** (متجر العميل) — طلبٌ مجدول كبقية
/// الخدمات (قرار المالك 2026-07-21): العميل يختار العنوان ثم التاريخ والوقت،
/// ويُسنَد سائق يوصّل المنتجات في الموعد. يمرّ بنفس خطّ الخدمات المجدولة في
/// مجموعة `orders` (فحص سعة ⇒ pending ⇒ إسناد تلقائي ⇒ scheduled).
///
/// متجر **الشركات** يبقى طلباً مباشراً (store_orders + StorePaymentScreen) بلا
/// تغيير — هذه الشاشة لمتجر العميل فقط.
class StoreScheduleScreen extends StatefulWidget {
  /// أصناف السلة: [{id, name, quantity, price}] كما بنتها ورقة السلة.
  final List<Map<String, dynamic>> items;

  /// أسعار المتجر أساسٌ تُضاف عليها ضريبة 15% (كباقي الخدمات)؛ _grandTotal ما يدفعه العميل.
  final double total;

  const StoreScheduleScreen({
    super.key,
    required this.items,
    required this.total,
  });

  @override
  State<StoreScheduleScreen> createState() => _StoreScheduleScreenState();
}

class _StoreScheduleScreenState extends State<StoreScheduleScreen> {
  static const Color _brand = Color(0xFF660033);

  /// نافذة انشغال السائق بالتوصيل — تُحدّد الخانات الصالحة والسعة المشغولة. التوصيل
  /// أقصر من خدمة تنظيف، فساعتان نافذة معقولة (والحد الأدنى للخدمات ساعتان أيضاً).
  static const int _deliveryHours = 2;

  bool _isLoading = true;
  List<Map<String, dynamic>> _zones = [];

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  bool _isLocating = false;
  LocateFailure? _locateFailure;

  double get _subTotal => widget.total; // الأساس
  double get _vat => widget.total * 0.15; // 15% مضافة فوق الأساس
  double get _grandTotal => widget.total + _vat; // ما يدفعه العميل (شامل الضريبة)
  int get _totalQty =>
      widget.items.fold(0, (a, it) => a + ((it['quantity'] as num?)?.toInt() ?? 0));

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
      // **لا نبتلع فشل جلب المناطق بصمت**: كان الـ catch يكتفي بإطفاء الدوّار
      // فتُرسم الشاشة طبيعية بقائمة مناطق فارغة — زر «حدّد موقعي» يصبح ميتاً
      // وكل عنوان يُتَّهم زوراً «خارج نطاق توصيلنا» فيعلق عميل سلّته جاهزة.
      debugPrint('[StoreSchedule] fetchZones failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر تحميل مناطق التوصيل: $e',
              style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _attemptAutoLocation({bool userInitiated = false}) async {
    if (!mounted) return;
    // مناطق فارغة = فشل جلبها عند الفتح غالباً — كان return الصامت يجعل زرّ
    // «حدّد موقعي تلقائياً» ميتاً بلا أي أثر. عند طلبٍ صريح نعيد الجلب، وإن
    // استمر الفشل نعرض سبباً قابلاً لإعادة المحاولة بدل الصمت.
    if (_zones.isEmpty) {
      if (!userInitiated) return;
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[StoreSchedule] fetchZones retry failed: $e');
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
          serviceName: 'عنوان توصيل الطلب',
        ),
      ),
    );
    if (!mounted || result is! GeoPoint) return;

    // قائمة مناطق فارغة (فشل جلبها) تجعل matchZone يُرجع null لكل نقطة —
    // فيُتَّهم عميلٌ داخل نطاق التوصيل زوراً بأنه خارجه ولا يستطيع جدولة
    // توصيل سلّته. نعيد الجلب أولاً، وإن استمر الفشل نقول السبب الحقيقي.
    if (_zones.isEmpty) {
      try {
        _zones = await ZyiarahZoneLocator.fetchZones();
      } catch (e) {
        debugPrint('[StoreSchedule] fetchZones retry failed: $e');
      }
      if (!mounted) return;
      if (_zones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر تحميل مناطق التوصيل — تحقّق من اتصالك وأعد المحاولة',
              style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final zone = ZyiarahZoneLocator.matchZone(result, _zones);
    if (zone == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('نأسف، موقعك خارج نطاق توصيلنا حالياً',
            style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() {
      _selectedLocation = result;
      _selectedZoneName = zone['name'] as String?;
      _selectedSlot = null;
      _locateFailure = null;
    });
  }

  void _handleNext() {
    if (_selectedLocation == null) {
      _snack('يرجى تحديد عنوان التوصيل أولاً');
      return;
    }
    if (_selectedSlot == null) {
      _snack('اختر اليوم ووقت التوصيل');
      return;
    }

    // تفصيل المنتجات على الطلب — كي يراها السائق والإدارة (نوع خدمة جديد).
    final meta = {
      'kind': 'store_products',
      'total_qty': _totalQty,
      'items': [
        for (final it in widget.items)
          {
            'name': it['name'] ?? '-',
            'quantity': (it['quantity'] as num?)?.toInt() ?? 0,
            'unit_price': (it['price'] as num?)?.toDouble() ?? 0,
            'line_total': ((it['price'] as num?)?.toDouble() ?? 0) *
                ((it['quantity'] as num?)?.toInt() ?? 0),
          },
      ],
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          serviceName: 'طلب من المتجر',
          amount: _grandTotal, // الأساس + 15% — شاشة الدفع تعامله كإجمالي
          location: _selectedLocation!,
          zoneName: _selectedZoneName,
          // hours + serviceDate = طلب مجدول: فحص سعة ⇒ pending ⇒ إسناد سائق تلقائي.
          hours: _deliveryHours,
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
          title: Text('جدولة توصيل الطلب',
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
                            ZyiarahBookingSlotPicker(
                              zoneName: _selectedZoneName,
                              durationHours: _deliveryHours,
                              onSlotSelected: (dt) =>
                                  setState(() => _selectedSlot = dt),
                            ),
                            const SizedBox(height: 26),
                            _summaryCard(),
                            const SizedBox(height: 24),
                            _nextButton(),
                          ] else ...[
                            const SizedBox(height: 40),
                            Center(
                              child: Text('حدّد عنوان التوصيل لاختيار الموعد',
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
          'assets/images/store.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF1F5F9),
            child: const Icon(Icons.storefront_rounded,
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
          for (final it in widget.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${it['name'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(
                          fontSize: 13, color: const Color(0xFF1E293B)),
                    ),
                  ),
                  Text('×${(it['quantity'] as num?)?.toInt() ?? 0}',
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: const Color(0xFF64748B))),
                  const SizedBox(width: 12),
                  Text(
                      '${(((it['price'] as num?)?.toDouble() ?? 0) * ((it['quantity'] as num?)?.toInt() ?? 0)).toStringAsFixed(2)} ر.س',
                      style: GoogleFonts.tajawal(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _brand)),
                ],
              ),
            ),
          const Divider(height: 22),
          _row('عدد المنتجات:', '$_totalQty'),
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
              Text('${_subTotal.toStringAsFixed(2)} ر.س',
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
    final ready = _selectedLocation != null && _selectedSlot != null;
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
