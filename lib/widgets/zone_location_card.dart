import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

/// سطرُ موقعِ الخدمة: **التحديدُ تلقائيٌّ** عند فتحِ الشاشة، ولا يظهرُ للعميلةِ
/// إلّا سطرٌ صغيرٌ بنتيجتِه — لا بطاقةَ ولا عنوانَ ولا زرَّ «حدّد موقعي».
///
/// (قرارُ المالك: كانت هنا بطاقةٌ مؤطَّرةٌ بعنوانِ «موقع تقديم الخدمة» وزرَّين
/// كبيرَين؛ والمطلوبُ أن يُحدَّدَ الموقعُ وحدَه بلا واجهةٍ تطلبُ منها شيئاً.)
///
/// **لا طريقَ مسدود:** إن تعذّرَ التحديدُ ظهرَ السببُ الفعليُّ في سطرٍ واحد،
/// وتحتَه روابطُ نصّيّةٌ صغيرة — «إعادة المحاولة» دائماً (موصولةٌ بـ
/// `onLocateMe`)، و«الإعدادات» حين يكونُ الإذنُ مرفوضاً نهائيّاً، و«من الخريطة».
/// فمن فتحت الإعداداتَ وسمحت ثمّ عادت تَجدُ ما تُعيدُ به المحاولة.
class ZyiarahZoneLocationCard extends StatelessWidget {
  static const Color _brand = Color(0xFF660033);

  /// جارٍ التحديد الآن.
  final bool isLocating;

  /// اسم المنطقة المطابَقة، أو null إن لم تُحدَّد بعد.
  final String? zoneName;

  /// سبب آخر تعذّر، أو null إن لم تُحاوَل/نجحت.
  final LocateFailure? failure;

  /// إعادةُ التحديد — يطلب الإذن صراحةً.
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

  Widget _link(String label, VoidCallback onTap, {Color color = _brand}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // **لا سطرَ موقعٍ في شاشةِ الخدمةِ إلّا حين لا موقعَ أصلاً** (قرار المالك
    // 2026-10-24). الموقعُ يُحدَّدُ مرّةً عند فتحِ التطبيقِ ويَظهرُ أعلى
    // الرئيسيّة (`ClientLocation` + `ClientLocationChip`)؛ فلا «جارٍ تحديد
    // موقعك…» ولا «المنطقة: … تغيير» هنا. وخارجَ النطاقِ تقولُ الشاشةُ
    // نفسُها «الخدمة غير متاحة في منطقتك» — لا سطرانِ لشيءٍ واحد.
    //
    // يبقى السطرُ في حالةٍ واحدة: تعذّرُ القراءةِ (إذنٌ مرفوض، GPS مطفأ،
    // مهلة) فلا موقعَ تُبنى عليه الشاشة — وبلاه صفحةٌ فارغةٌ بلا مخرج.
    if (isLocating || zoneName != null || failure == null) {
      return const SizedBox.shrink();
    }
    if (failure == LocateFailure.outOfServiceArea) {
      return const SizedBox.shrink();
    }

    final needsSettings = failure?.needsSettings == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_off_outlined, size: 18, color: Color(0xFFB45309)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(failure?.message ?? 'لم يُحدَّد موقعك بعد',
                  style: GoogleFonts.tajawal(
                      fontSize: 12, color: const Color(0xFF92400E), height: 1.6)),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            if (needsSettings)
              _link('الإعدادات', () => ZyiarahZoneLocator.openSettings(),
                  color: const Color(0xFFB45309)),
            _link('إعادة المحاولة', onLocateMe),
            _link('من الخريطة', onPickManually),
          ],
        ),
      ],
    );
  }
}
