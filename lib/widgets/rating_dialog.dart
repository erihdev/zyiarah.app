import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';

class ZyiarahRatingDialog extends StatefulWidget {
  final Function(double rating, String comment, {String? reason, File? evidence}) onSubmitted;

  const ZyiarahRatingDialog({super.key, required this.onSubmitted});

  @override
  State<ZyiarahRatingDialog> createState() => _ZyiarahRatingDialogState();
}

class _ZyiarahRatingDialogState extends State<ZyiarahRatingDialog> {
  double _rating = 5.0;
  final TextEditingController _commentCtrl = TextEditingController();
  String? _selectedReason;
  File? _evidenceImage;
  final bool _isUploading = false;

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
            
              const SizedBox(height: 20),
              if (_rating <= 2) ...[
                Text(ZyiarahStrings.lowRatingPrompt, style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red[700])),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedReason,
                  hint: Text(ZyiarahStrings.selectReasonHint, style: GoogleFonts.tajawal(fontSize: 13)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.red[50]?.withValues(alpha: 0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.red[100]!)),
                  ),
                  items: ZyiarahStrings.lowRatingReasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: GoogleFonts.tajawal(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => _selectedReason = val),
                ),
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);
                    if (picked != null) {
                      setState(() => _evidenceImage = File(picked.path));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_evidenceImage != null ? Icons.check_circle : Icons.add_a_photo_rounded, color: _evidenceImage != null ? Colors.green : Colors.grey),
                        const SizedBox(width: 10),
                        Text(
                          _evidenceImage != null ? ZyiarahStrings.evidenceAttached : ZyiarahStrings.attachEvidence,
                          style: GoogleFonts.tajawal(color: Colors.grey[700], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
              ],

            const SizedBox(height: 30),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              style: GoogleFonts.tajawal(fontSize: 14),
              decoration: InputDecoration(
                hintText: _rating <= 2.0 ? "هل تود إضافة المزيد من التفاصيل؟" : "أخبرنا المزيد (اختياري)...",
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
                onPressed: _isUploading ? null : () async {
                  if (_rating <= 2.0 && _selectedReason == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار سبب التقييم")));
                    return;
                  }
                  
                  ZyiarahCoreService.triggerHapticSuccess();
                  widget.onSubmitted(
                    _rating, 
                    _commentCtrl.text.trim(),
                    reason: _selectedReason,
                    evidence: _evidenceImage,
                  );
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
