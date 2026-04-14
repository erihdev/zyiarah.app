import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ZyiarahPermissionSheet extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String buttonText;
  final VoidCallback onAction;

  const ZyiarahPermissionSheet({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.buttonText,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 40),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 22, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey.shade600, height: 1.6),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                onAction();
              },
              child: Text(buttonText, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("تخطي الآن", style: GoogleFonts.tajawal(color: Colors.grey)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
