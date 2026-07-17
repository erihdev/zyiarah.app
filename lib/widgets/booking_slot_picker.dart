import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

/// منتقي التاريخ والوقت مع الإتاحة الحقيقية من الخادم — **مصدر «اللون الأخضر» الوحيد.**
///
/// استُخرج ليُستعمل في كل خدمة تُحجز بموعد (الكنب والسجاد، المكيفات، وما يأتي)، لأن
/// تكرار هذا المنطق في كل شاشة هو بالضبط ما أنتج نظامَي تسعير متنازعَين في هذا المشروع.
///
/// **قاعدتان مثبَّتتان هنا:**
/// 1. **الأخضر وعدٌ بوجود سائق، لا «لا نعرف».** إن فشل جلب الإتاحة نعرض إعادة محاولة
///    ولا نرسم تقويماً أخضر — الشاشة القديمة كانت تبتلع الفشل فتبقى الأعداد فارغة
///    ⇒ `0 >= السقف` = false ⇒ كل التواريخ خضراء ⇒ العميل يحجز يوماً ممتلئاً.
/// 2. **الخانة متاحة فقط إن توفّر سائق طوال المدة كلها** لا ساعة البدء وحدها — وإلا
///    يصل السائق ولا يستطيع إكمال المدة.
///
/// السعة تأتي من `getHourlyAvailability` (Admin SDK) لأن قواعد Firestore تمنع العميل
/// من قراءة طلبات غيره، والاستعلام المباشر يُرفض كاملاً بـ permission-denied.
class ZyiarahBookingSlotPicker extends StatefulWidget {
  /// منطقة الخدمة — تُحفظ على الطلب (تسعير/فاتورة/كوبونات) ولا تؤثّر في السعة:
  /// السائقون بلا مناطق بقرار المالك، فالسعة رقم واحد للنشاط كلّه.
  final String? zoneName;

  /// مدة انشغال السائق بالطلب — تحدّد الخانات الصالحة والسعة المطلوبة.
  final int durationHours;

  /// يُستدعى بالموعد المختار، أو بـ null إذا أُلغي الاختيار (تغيّر التاريخ مثلاً).
  final ValueChanged<DateTime?> onSlotSelected;

  const ZyiarahBookingSlotPicker({
    super.key,
    required this.durationHours,
    required this.onSlotSelected,
    this.zoneName,
  });

  @override
  State<ZyiarahBookingSlotPicker> createState() => _ZyiarahBookingSlotPickerState();
}

class _ZyiarahBookingSlotPickerState extends State<ZyiarahBookingSlotPicker> {
  static const Color _brand = Color(0xFF5D1B5E);
  static const int _workStart = 8;
  static const int _workEnd = 22;
  static const int _horizonDays = 30;

  bool _loading = true;
  bool _error = false;

  Map<String, int> _dailyCounts = {};
  Map<String, int> _slotCounts = {};
  int _maxOrdersPerDay = 10;
  int _maxTeamsPerSlot = 0;

  late DateTime _selectedDate;
  int? _selectedHour;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _load();
  }

  @override
  void didUpdateWidget(covariant ZyiarahBookingSlotPicker old) {
    super.didUpdateWidget(old);
    // المدة تغيّر عدد الساعات المطلوب توفّرها ⇒ تُعيد حساب الخانات. (المنطقة لم تعد
    // تؤثّر في السعة، لكن تغيّرها يعني اختياراً جديداً فنُلغي الموعد المحدَّد.)
    if (old.zoneName != widget.zoneName || old.durationHours != widget.durationHours) {
      _clearSelection();
      _load();
    }
  }

  void _clearSelection() {
    _selectedHour = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSlotSelected(null));
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final now = DateTime.now();
      final fmt = intl.DateFormat('yyyy-MM-dd');
      final res = await FirebaseFunctions.instance
          .httpsCallable('getHourlyAvailability')
          .call({
            'startDate': fmt.format(now),
            'endDate': fmt.format(now.add(const Duration(days: _horizonDays + 1))),
          })
          .timeout(const Duration(seconds: 20));

      final data = res.data as Map;
      final daily = (data['dailyCounts'] as Map? ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      final slots = (data['slotCounts'] as Map? ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));

      if (!mounted) return;
      setState(() {
        _dailyCounts = daily;
        _slotCounts = slots;
        _maxOrdersPerDay = (data['maxOrdersPerDay'] as num?)?.toInt() ?? 10;
        _maxTeamsPerSlot = (data['maxTeamsPerSlot'] as num?)?.toInt() ?? 0;
        _loading = false;
        // لو صار التاريخ المختار ممتلئاً، انتقل لأول يوم متاح بدل ترك اختيار ميّت.
        if (_isDayFull(_selectedDate)) {
          for (int i = 1; i <= _horizonDays; i++) {
            final c = now.add(Duration(days: i));
            if (!_isDayFull(c)) {
              _selectedDate = c;
              break;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('[BookingSlotPicker] getHourlyAvailability failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true; // لا تقويم أخضر كاذب — إعادة محاولة صريحة.
      });
    }
  }

  String _key(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);

  bool _isDayFull(DateTime d) => (_dailyCounts[_key(d)] ?? 0) >= _maxOrdersPerDay;

  /// متاح فقط إن توفّر سائق حرّ في **كل ساعة** من ساعات المدة.
  bool _isSlotFree(DateTime day, int startHour) {
    if (_maxTeamsPerSlot <= 0) return false; // لا سائق نشط أصلاً
    final dateKey = _key(day);
    for (int h = startHour; h < startHour + widget.durationHours; h++) {
      final k = '${dateKey}_${h.toString().padLeft(2, '0')}:00';
      if ((_slotCounts[k] ?? 0) >= _maxTeamsPerSlot) return false;
    }
    return true;
  }

  List<int> _startHours() {
    final last = _workEnd - widget.durationHours;
    if (last < _workStart) return const [];
    return List.generate(last - _workStart + 1, (i) => _workStart + i);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (_error) return _errorBanner();
    if (_loading) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }
    if (_maxTeamsPerSlot <= 0) return _noDriversBanner();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('اختاري اليوم'),
        const SizedBox(height: 10),
        _dateStrip(),
        const SizedBox(height: 22),
        _label('اختاري وقت البدء'),
        Text(
          'المدة المتوقّعة ${widget.durationHours} ساعة',
          style: GoogleFonts.tajawal(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        _slotGrid(),
      ],
    );
  }

  Widget _label(String t) => Text(
        t,
        style: GoogleFonts.tajawal(
            fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
      );

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تعذّر تحميل المواعيد المتاحة.\nتحقّقي من اتصالك وأعيدي المحاولة.',
              style: GoogleFonts.tajawal(
                  fontSize: 13, color: const Color(0xFF991B1B), height: 1.5),
            ),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('إعادة', style: GoogleFonts.tajawal()),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Widget _noDriversBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لا يوجد فريق متاح حالياً. تواصلي معنا لتحديد موعد.',
              style: GoogleFonts.tajawal(
                  fontSize: 13, color: const Color(0xFF92400E), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateStrip() {
    final now = DateTime.now();
    const dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    return SizedBox(
      height: 82,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _horizonDays,
        itemBuilder: (context, i) {
          final date = now.add(Duration(days: i + 1));
          final selected = _sameDay(_selectedDate, date);
          final full = _isDayFull(date);
          return GestureDetector(
            onTap: () {
              if (full) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('هذا اليوم محجوز بالكامل، اختاري تاريخاً آخر.',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ));
                return;
              }
              HapticFeedback.lightImpact();
              setState(() {
                _selectedDate = date;
                _selectedHour = null;
              });
              widget.onSlotSelected(null);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 58,
              decoration: BoxDecoration(
                color: selected
                    ? _brand
                    : full
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _brand
                      : full
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFA7F3D0),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayNames[date.weekday % 7],
                    style: GoogleFonts.tajawal(
                      fontSize: 11,
                      color: selected
                          ? Colors.white70
                          : full
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: GoogleFonts.tajawal(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _slotGrid() {
    final hours = _startHours();
    if (hours.isEmpty) {
      return Text(
        'مدة الخدمة أطول من ساعات العمل المتاحة — تواصلي معنا.',
        style: GoogleFonts.tajawal(fontSize: 13, color: const Color(0xFFB45309)),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: hours.map((h) {
        final free = _isSlotFree(_selectedDate, h);
        final selected = _selectedHour == h;
        return GestureDetector(
          onTap: free
              ? () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedHour = h);
                  widget.onSlotSelected(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    h,
                  ));
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? _brand
                  : free
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _brand
                    : free
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFE2E8F0),
                width: 1.5,
              ),
            ),
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold,
                color: selected
                    ? Colors.white
                    : free
                        ? const Color(0xFF059669)
                        : const Color(0xFFCBD5E1),
                decoration: free ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
