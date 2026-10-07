import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// **شاشةُ تعذّرِ الإقلاع — بديلُ البياضِ الأبديّ.**
///
/// تُعرَضُ حين يَفشلُ `Firebase.initializeApp`، وهو الفشلُ الوحيدُ الذي
/// يَجعلُ التطبيقَ عاجزاً كلّيّاً (لا مصادقةَ ولا بيانات). وقبلَها كان الرميُ
/// يَخرجُ من `main()` **قبلَ `runApp`**، فلا يُرسَمُ شيءٌ إطلاقاً: نافذةٌ
/// بيضاءُ بلا رسالةٍ ولا مَخرج — ولا أثرَ في Crashlytics لأنّه لم يُفعَّلْ بعد.
///
/// **ولا تَعتمِدُ على شيءٍ مِمّا قد يَكونُ فشل:** لا Firebase، ولا Firestore،
/// ولا قراءةَ أصلٍ غيرِ الخطِّ المُضمَّن (`GoogleFonts` بلا جلبٍ شبكيٍّ —
/// `allowRuntimeFetching` مُطفأٌ قبلَها في `main`)، ولا `.env`. وTajawal
/// بوزنَيه هنا (400/700) من الأوزانِ المُضمَّنةِ في `pubspec.yaml`.
class ZyiarahBootFailureApp extends StatelessWidget {
  const ZyiarahBootFailureApp({super.key, this.onRetry});

  /// تُحقَنُ في الاختبار؛ وفي التطبيقِ تُعيدُ تشغيلَ التهيئةِ من أوّلِها.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 18),
                    Text(
                      'تعذّر تشغيل التطبيق',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF660033)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'لم نتمكّن من الاتصال بخدماتنا على هذا الجهاز. '
                      'تحقّقي من اتصالكِ بالإنترنت ثمّ أعيدي المحاولة.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontSize: 14, height: 1.7, color: Colors.black87),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('إعادة المحاولة',
                          style: GoogleFonts.tajawal(
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF660033),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
