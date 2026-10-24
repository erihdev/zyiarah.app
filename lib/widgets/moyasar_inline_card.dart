import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moyasar/moyasar.dart';
import 'package:zyiarah/utils/moyasar_error_text.dart';

/// نموذجُ بطاقةِ ميسر **داخلَ بطاقةِ طريقةِ الدفعِ نفسِها** — لا شاشةَ ثانية.
///
/// كانت «بطاقة فيزا / مدى» تَفتحُ `MoyasarCardScreen`: ضغطةٌ على «تأكيد
/// وإتمام الدفع»، ثمّ صفحةٌ جديدةٌ فيها الحقولُ وزرُّ «ادفع» ثانٍ. فالعميلةُ
/// تَضغطُ زرَّ دفعٍ لا يَدفع، وتَنتقلُ إلى صفحةٍ لتَفعلَ ما كان يُمكنُ هنا
/// (بطلب المالك 2026-10-24). الحقولُ الآن تَظهرُ تحتَ الخيارِ حين يُختار،
/// وزرُّ ميسر هو زرُّ الدفعِ الوحيد.
///
/// والودجةُ لا تَعرفُ الطلب: المُنادي يَبني `config` (المبلغَ و`givenID`
/// والبياناتِ الوصفيّة) ويَقرّرُ ما بعدَ النجاح. والقاعدةُ الوحيدةُ هنا هي
/// قراءةُ النتيجة: ناجحةٌ (`paid`/`authorized`) أو رسالةٌ عربيّةٌ من
/// `moyasarErrorText` — لا نصَّ بوّابةٍ يَصِلُ العميلة.
class MoyasarInlineCard extends StatelessWidget {
  final PaymentConfig config;
  final void Function(String paymentId) onSuccess;

  /// الرسالةُ للعرض، والنتيجةُ الخامُ لمن يَحتاجُ قرارَ `givenIdConsumed`
  /// أو تسجيلَ «نتيجةٍ مجهولة».
  final void Function(MoyasarErrorText error, Object? raw) onFailure;

  /// سببُ المنعِ إن لم تَتحقّق شروطُ الدفعِ بعد (الموافقةُ، العنوان…):
  /// الحقولُ تُعتَّمُ ولا تُلمَس، والضغطةُ تُظهرُ السبب. فزرُّ ميسر يَشحنُ
  /// فوراً، ولا شيءَ بعدَه يَستطيعُ أن يَقولَ «لم تُوافقي على الشروط».
  final String? blockedReason;

  const MoyasarInlineCard({
    super.key,
    required this.config,
    required this.onSuccess,
    required this.onFailure,
    this.blockedReason,
  });

  void _handleResult(dynamic result) {
    if (result is PaymentResponse &&
        (result.status == PaymentStatus.paid ||
            result.status == PaymentStatus.authorized)) {
      onSuccess(result.id);
      return;
    }
    final e = moyasarErrorText(result);
    debugPrint('[card] ${e.detail}');
    onFailure(e, result);
  }

  @override
  Widget build(BuildContext context) {
    // **الويب لا يَستطيعُ خطوةَ البنك.** بعد «ادفع» تُعيدُ ميسر حالةَ
    // `initiated` وتَدفعُ حزمتُها `ThreeDSWebView` — و`webview_flutter` بلا
    // منصّةٍ على الويب، فتُرسَمُ شاشةٌ رماديّةٌ مكانَ صفحةِ رمزِ البنك
    // (معاينةُ 2026-10-24). ولا عميلةَ تَدفعُ من الويب: النطاقُ العامُّ صفحةُ
    // تعريف، وتطبيقُ Flutter على الويب معاينةٌ وحدَها. فالقولُ الصادقُ هنا
    // أفضلُ من حقولٍ تَقبلُ البطاقةَ ثمّ تَتجمّد.
    if (kIsWeb) return _webNotice();
    final form = _form();
    final reason = blockedReason;
    if (reason == null) return form;
    return Stack(
      children: [
        form,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(reason, style: GoogleFonts.tajawal())),
            ),
            child: Opacity(
              opacity: 0.5,
              child: Container(color: const Color(0xFFF1F5F9)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _webNotice() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.phone_iphone_rounded, color: Color(0xFFC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الدفع بالبطاقة يتمّ من تطبيق زيارة على الجوال — خطوة تحقّق '
              'البنك لا تعمل في المتصفح.',
              style: GoogleFonts.tajawal(
                  fontSize: 13, color: const Color(0xFF9A3412), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF660033), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.green.shade700, size: 15),
              const SizedBox(width: 6),
              Text(
                'دفع آمن ومشفّر عبر ميسر',
                style: GoogleFonts.tajawal(
                    fontSize: 12, color: Colors.green.shade700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CreditCard(
            config: config,
            // الاتّجاهُ يُشتقُّ من اللغة (`ar` ⇒ RTL) داخلَ الحزمة.
            locale: const Localization.ar(),
            onPaymentResult: _handleResult,
          ),
        ],
      ),
    );
  }
}
