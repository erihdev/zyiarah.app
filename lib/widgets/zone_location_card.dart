import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

/// بطاقة موقع الخدمة: تحدّد تلقائياً، وتقول **لماذا** إن تعذّر، وتعطي إجراءً.
///
/// حلّت محلّ ثلاث نسخ متطابقة كانت تعرض «لم يُحدَّد موقعك بعد — اختره من الزر
/// بالأسفل» لكل الأسباب على السواء: الخدمة مطفأة، الإذن مرفوض، GPS لم يستجب،
/// خارج النطاق… كلها رسالة واحدة لا تدلّ على شيء، وبلا سجلّ يكشف السبب.
class ZyiarahZoneLocationCard extends StatelessWidget {
  static const Color _brand = Color(0xFF660033);

  /// جارٍ التحديد الآن.
  final bool isLocating;

  /// اسم المنطقة المطابَقة، أو null إن لم تُحدَّد بعد.
  final String? zoneName;

  /// سبب آخر تعذّر، أو null إن لم تُحاوَل/نجحت.
  final LocateFailure? failure;

  /// «حدّد موقعي تلقائياً» — يطلب الإذن صراحةً.
  final VoidCallback onLocateMe;

  /// «تحديد من الخريطة».
  final VoidCallback onPickManually;

  const ZyiarahZoneLocationCard({
    super.key,
    required this.isLocating,
    required this.onLocateMe,
    required this.onPickManually,
    this.zoneName,
    this.failure,
  });

  @override
  Widget build(BuildContext context) {
    final located = zoneName != null;
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
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: _brand)),
          const SizedBox(height: 10),
          if (isLocating)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
                ),
                const SizedBox(width: 10),
                Text('جارٍ تحديد موقعك…',
                    style: GoogleFonts.tajawal(
                        fontSize: 13, color: const Color(0xFF64748B))),
              ],
            )
          else if (located)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('المنطقة: $zoneName',
                      style: GoogleFonts.tajawal(
                          color: const Color(0xFF059669),
                          fontWeight: FontWeight.bold)),
                ),
              ],
            )
          else if (failure != null)
            // **السبب الفعلي** بدل رسالة واحدة تصلح لكل شيء.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(failure!.message,
                      style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: const Color(0xFF92400E),
                          height: 1.6)),
                ),
              ],
            )
          else
            Text('لم يُحدَّد موقعك بعد',
                style: GoogleFonts.tajawal(
                    fontSize: 13, color: const Color(0xFF64748B))),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!located && failure?.needsSettings == true)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => ZyiarahZoneLocator.openSettings(),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: Text('الإعدادات', style: GoogleFonts.tajawal()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isLocating ? null : onLocateMe,
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(located ? 'تحديث موقعي' : 'حدّد موقعي تلقائياً',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLocating ? null : onPickManually,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(located ? 'تغيير' : 'من الخريطة',
                      style: GoogleFonts.tajawal()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _brand,
                    side: BorderSide(color: _brand.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
