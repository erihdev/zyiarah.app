import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

class ZyiarahRatingDialog extends StatefulWidget {
  final Function(double rating, String comment) onSubmitted;

  const ZyiarahRatingDialog({super.key, required this.onSubmitted});

  @override
  State<ZyiarahRatingDialog> createState() => _ZyiarahRatingDialogState();
}

class _ZyiarahRatingDialogState extends State<ZyiarahRatingDialog> {
  double _rating = 5.0;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text("كيف كانت تجربتك مع زيارة؟", style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            const SizedBox(height: 8),
            Text("تقييمك يساعدنا على تقديم خدمة أفضل دائماً", style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 30),
            
            // Star Rating Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () {
                    setState(() => _rating = index + 1.0);
                    ZyiarahCoreService.triggerHapticSelection();
                  },
                  icon: Icon(
                    index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: index < _rating ? Colors.amber : Colors.grey[300],
                    size: 45,
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 30),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              style: GoogleFonts.tajawal(fontSize: 14),
              decoration: InputDecoration(
                hintText: "أخبرنا المزيد (اختياري)...",
                hintStyle: GoogleFonts.tajawal(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
            const SizedBox(height: 30),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  ZyiarahCoreService.triggerHapticSuccess();
                  widget.onSubmitted(_rating, _commentCtrl.text.trim());
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: Text("إرسال التقييم", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
