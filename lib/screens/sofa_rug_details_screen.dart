import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/sqm_piece.dart';
import 'package:zyiarah/screens/location_picker_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/services/zone_locator_service.dart';
import 'package:zyiarah/widgets/booking_slot_picker.dart';
import 'package:zyiarah/widgets/zone_location_card.dart';

/// تنظيف الكنب والسجاد — **بالمتر المربع**، كل قطعة بمقاسها.
///
/// حلّ محلّ التسعير بالمتر الطولي (`sofaPrice`/`rugPrice` + عدّاد + و −). النظام القديم
/// أُزيل بالكامل بقرار صريح: إبقاء نظامَي تسعير معاً هو ما جعل الإدارة تسعّر حقولاً
/// لا يقرؤها أحد بينما يحاسب العميلَ حقلٌ موسوم «للنسخ القديمة فقط».
///
/// الطلب هنا **مباشر**: يمرّر `hours` و`serviceDate` إلى شاشة الدفع، وهذا ما يقلب
/// الطلب إلى `status: 'pending'` (لا `pending_admin_approval`) ويُفعّل فحص السعة
/// والإسناد التلقائي للسائق — نفس مسار الخدمة بالساعة تماماً.
class SofaRugCleaningDetailsScreen extends StatefulWidget {
  final String serviceName;
  const SofaRugCleaningDetailsScreen({super.key, required this.serviceName});

  @override
  State<SofaRugCleaningDetailsScreen> createState() =>
      _SofaRugCleaningDetailsScreenState();
}

class _SofaRugCleaningDetailsScreenState
    extends State<SofaRugCleaningDetailsScreen> {
  static const Color _brand = Color(0xFF5D1B5E);

  bool _isLoading = true;

  double _sofaSqmPrice = 0;
  double _rugSqmPrice = 0;

  String? _selectedZoneName;
  GeoPoint? _selectedLocation;
  DateTime? _selectedSlot;

  /// حالة التحديد التلقائي — تُعرض بدل الصمت.
  bool _isLocating = false;
  LocateFailure? _locateFailure;

  List<Map<String, dynamic>> _zones = [];
  final List<SqmPiece> _pieces = [const SqmPiece(kind: SqmPieceKind.sofa)];

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
      debugPrint('[SofaRug] fetchZones failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// السعر من المنطقة. **صفر أو غائب = الخدمة غير مسعّرة هنا** فتُعطَّل — وهذا ما يَعِد
  /// به نصّ لوحة الإدارة، وقد كان وعداً كاذباً إلى أن صارت هذه الشاشة تقرأ الحقلين فعلاً.
  ///
  /// **لا نستعمل قيمة افتراضية عند الغياب عمداً.** الشاشة القديمة كانت `?? 35` فتبيع
  /// بسعرٍ لم تعتمده الإدارة قط لأي منطقة يخلو مستندها من الحقل — والعميلة تُحاسَب عليه.
  /// أن تظهر الخدمة «غير متاحة» أصدق من أن تُباع برقمٍ لم يقرّه أحد.
  void _applyZone(Map<String, dynamic> zone) {
    _sofaSqmPrice = (zone['sofaSqmPrice'] as num?)?.toDouble() ?? 0;
    _rugSqmPrice = (zone['rugSqmPrice'] as num?)?.toDouble() ?? 0;
  }

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
          serviceName: 'تحديد موقع تنفيذ خدمة الكنب والسجاد',
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
      _selectedSlot = null; // المنطقة تغيّرت ⇒ الموعد يُعاد اختياره
      _locateFailure = null;
    });
  }

  double _priceFor(SqmPieceKind k) =>
      k == SqmPieceKind.sofa ? _sofaSqmPrice : _rugSqmPrice;

  bool _kindEnabled(SqmPieceKind k) => _priceFor(k) > 0;

  bool get _anyKindEnabled =>
      _kindEnabled(SqmPieceKind.sofa) || _kindEnabled(SqmPieceKind.rug);

  /// شامل ضريبة القيمة المضافة — موحّد مع باقي الخدمات و ZATCA: المبلغ المُدخل من
  /// الإدارة هو ما يدفعه العميل، والضريبة تُحتسب قسمةً (متضمَّنة) لا إضافةً.
  double get totalAmount => _pieces
      .where((p) => p.isComplete)
      .fold(0.0, (acc, p) => acc + p.priceWith(_priceFor(p.kind)));

  double get subTotal => totalAmount / 1.15;
  double get vat => totalAmount - subTotal;

  double get totalArea =>
      _pieces.where((p) => p.isComplete).fold(0.0, (s, p) => s + p.area);

  /// مدة انشغال السائق. تكبر مع المساحة كي لا يُسنَد له عملُ يومٍ في ساعتين:
  /// ساعتان لأي عمل دون 10 م²، ثم ساعة إضافية لكل 10 م² كاملة، بسقف 8 ساعات
  /// (طول يوم العمل — وتجاوزه يُفرِغ قائمة خانات البدء 8→22).
  int get _durationHours => (2 + (totalArea / 10).floor()).clamp(2, 8);

  void _addPiece(SqmPieceKind kind) {
    HapticFeedback.selectionClick();
    setState(() => _pieces.add(SqmPiece(kind: kind)));
  }

  void _removePiece(int i) {
    HapticFeedback.lightImpact();
    setState(() => _pieces.removeAt(i));
  }

  void _handleNext() {
    if (_selectedLocation == null) {
      _snack('يرجى تحديد موقعك أولاً');
      return;
    }
    if (totalAmount <= 0) {
      _snack('أدخلي طول وعرض قطعة واحدة على الأقل');
      return;
    }
    if (_selectedSlot == null) {
      _snack('اختاري اليوم ووقت البدء');
      return;
    }

    final meta = {
      'kind': 'sofa_rug_sqm',
      'total_area_sqm': double.parse(totalArea.toStringAsFixed(2)),
      'sofa_price_per_sqm': _sofaSqmPrice,
      'rug_price_per_sqm': _rugSqmPrice,
      'pieces': _pieces
          .where((p) => p.isComplete)
          .map((p) => p.toMap(_priceFor(p.kind)))
          .toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          serviceName: '${widget.serviceName} (${_selectedZoneName ?? ''})',
          amount: totalAmount,
          location: _selectedLocation!,
          zoneName: _selectedZoneName,
          // hours + serviceDate = طلب مباشر: فحص سعة، status 'pending'، إسناد تلقائي.
          hours: _durationHours,
          serviceDate: _selectedSlot,
          serviceMeta: meta,
        ),
      ),
    ).then((success) {
      if (success == true && mounted) Navigator.pop(context, true);
    });
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m, style: GoogleFonts.tajawal())));
  }

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
                            if (!_anyKindEnabled)
                              _unpricedBanner()
                            else ...[
                              _piecesSection(),
                              const SizedBox(height: 26),
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
                          ] else ...[
                            const SizedBox(height: 40),
                            Center(
                              child: Text(
                                'حدّدي موقعك لعرض أسعار منطقتك',
                                style: GoogleFonts.tajawal(color: Colors.grey),
                              ),
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

  Widget _header() => Hero(
        tag: 'svc-assets/images/sofa_cleaning.png',
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: Image.asset(
            'assets/images/sofa_cleaning.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFF1E9FE),
              child: const Icon(Icons.chair, color: Color(0xFF8B5CF6), size: 60),
            ),
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
        child: Text(
          'هذه الخدمة غير متاحة في منطقتك حالياً.',
          style: GoogleFonts.tajawal(
              color: const Color(0xFF92400E), height: 1.6, fontSize: 13),
        ),
      );

  /// بطاقة «كيف يُحسب السعر؟» — بأسعار منطقة العميلة نفسها ومثال محسوب منها.
  ///
  /// كان سعر المتر يظهر بخطّ صغير بجانب كل قطعة فقط، فلا تفهم العميلة الأساس الذي
  /// بُني عليه الإجمالي (ملاحظة المالك بعد تجربة العميل). الشرح بالمثال الحيّ —
  /// بأرقام منطقتها لا أرقام افتراضية — يجيب «كيف؟» قبل أن تُسأل.
  Widget _pricingExplainer() {
    final rows = <Widget>[];
    void addRow(String label, double perSqm) {
      if (perSqm <= 0) return;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.tajawal(
                    fontSize: 13, color: const Color(0xFF1E293B))),
            Text('${_trim(perSqm)} ر.س لكل متر مربع',
                style: GoogleFonts.tajawal(
                    fontSize: 13, fontWeight: FontWeight.bold, color: _brand)),
          ],
        ),
      ));
    }

    addRow('الكنب', _sofaSqmPrice);
    addRow('السجاد', _rugSqmPrice);

    // المثال بسعر منطقتها الفعلي: كنبة 2م × 1.5م.
    final examplePrice = _sofaSqmPrice > 0 ? _sofaSqmPrice : _rugSqmPrice;
    final exampleKind = _sofaSqmPrice > 0 ? 'كنبة' : 'سجادة';
    final exampleTotal = (3 * examplePrice).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_rounded,
                  size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              Text('كيف يُحسب السعر؟',
                  style: GoogleFonts.tajawal(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF059669))),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
          const Divider(height: 16, color: Color(0xFFBBF7D0)),
          Text('السعر = الطول × العرض × سعر المتر المربع',
              style: GoogleFonts.tajawal(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF166534))),
          const SizedBox(height: 3),
          Text(
            'مثال: $exampleKind بطول 2م وعرض 1.5م = 3 م² × ${_trim(examplePrice)} = $exampleTotal ر.س',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: const Color(0xFF166534), height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _piecesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pricingExplainer(),
        Text('القطع المطلوب تنظيفها',
            style: GoogleFonts.tajawal(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B))),
        Text('أدخلي طول وعرض كل قطعة — لا يوجد حد أدنى.',
            style: GoogleFonts.tajawal(
                fontSize: 12, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 12),
        ...List.generate(_pieces.length, (i) => _pieceCard(i)),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_kindEnabled(SqmPieceKind.sofa))
              Expanded(child: _addButton(SqmPieceKind.sofa)),
            if (_kindEnabled(SqmPieceKind.sofa) && _kindEnabled(SqmPieceKind.rug))
              const SizedBox(width: 10),
            if (_kindEnabled(SqmPieceKind.rug))
              Expanded(child: _addButton(SqmPieceKind.rug)),
          ],
        ),
      ],
    );
  }

  Widget _addButton(SqmPieceKind kind) => OutlinedButton.icon(
        onPressed: () => _addPiece(kind),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text('إضافة ${kind.label}', style: GoogleFonts.tajawal()),
        style: OutlinedButton.styleFrom(
          foregroundColor: _brand,
          side: BorderSide(color: _brand.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _pieceCard(int i) {
    final piece = _pieces[i];
    final price = _priceFor(piece.kind);
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
              Icon(
                piece.kind == SqmPieceKind.sofa
                    ? Icons.chair_rounded
                    : Icons.texture_rounded,
                size: 18,
                color: _brand,
              ),
              const SizedBox(width: 8),
              Text('${piece.kind.label} ${i + 1}',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B))),
              const SizedBox(width: 8),
              Text('(${price.toStringAsFixed(0)} ر.س/م²)',
                  style: GoogleFonts.tajawal(
                      fontSize: 12, color: const Color(0xFF94A3B8))),
              const Spacer(),
              if (_pieces.length > 1)
                IconButton(
                  onPressed: () => _removePiece(i),
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Color(0xFFDC2626)),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'حذف',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _dimField(
                  label: 'الطول (م)',
                  value: piece.length,
                  onChanged: (v) => setState(
                      () => _pieces[i] = piece.copyWith(length: v)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('×',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8))),
              ),
              Expanded(
                child: _dimField(
                  label: 'العرض (م)',
                  value: piece.width,
                  onChanged: (v) =>
                      setState(() => _pieces[i] = piece.copyWith(width: v)),
                ),
              ),
            ],
          ),
          if (piece.isComplete) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // المعادلة كاملة لا الناتج وحده: «3.00 م²» المجرّدة لا تقول للعميلة
                // كيف صارت 105 ر.س — فتظنّ الرقم اعتباطياً. الحساب المرئي يبني الثقة.
                Expanded(
                  child: Text(
                    '${_trim(piece.length)}م × ${_trim(piece.width)}م'
                    ' = ${piece.area.toStringAsFixed(2)} م² × ${_trim(price)} ر.س',
                    style: GoogleFonts.tajawal(
                        fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ),
                Text(
                  '${piece.priceWith(price).toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontSize: 18, fontWeight: FontWeight.w900, color: _brand),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dimField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return TextFormField(
      initialValue: value == 0 ? '' : _trim(value),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}([.,]\d{0,2})?')),
      ],
      style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.tajawal(fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      // الفاصلة العربية شائعة في لوحات المفاتيح — نقبلها كفاصلة عشرية بدل رفضها.
      onChanged: (t) => onChanged(double.tryParse(t.replaceAll(',', '.')) ?? 0),
    );
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _summaryCard() {
    final complete = _pieces.where((p) => p.isComplete).length;
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
          _row('عدد القطع:', '$complete'),
          const SizedBox(height: 8),
          _row('المساحة الإجمالية:', '${totalArea.toStringAsFixed(2)} م²'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
