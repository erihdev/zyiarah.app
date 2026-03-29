import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ZyiarahTermsScreen extends StatelessWidget {
  const ZyiarahTermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الشروط والأحكام', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF4A0E0E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('1. مقدمة'),
              _buildSectionText('مرحباً بكم في تطبيق زيارة. باستخدامكم لهذا التطبيق، فإنكم توافقون على الالتزام بالشروط والأحكام التالية...'),
              const SizedBox(height: 20),
              _buildSectionTitle('2. الخدمات'),
              _buildSectionText('يقوم التطبيق بتقديم خدمات التنظيف المنزلي، الصيانة، والعقود الإلكترونية وفقاً للمعايير المتبعة...'),
              const SizedBox(height: 20),
              _buildSectionTitle('3. سياسة الدفع'),
              _buildSectionText('يتم الدفع عبر الوسائل المتاحة في التطبيق (مدى، فيزا، تمارا، أو الدفع عند الاستلام في حالات محددة)...'),
              // Add more sections as needed
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4A0E0E)),
    );
  }

  Widget _buildSectionText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        style: GoogleFonts.tajawal(fontSize: 14, color: Colors.black87, height: 1.6),
      ),
    );
  }
}

class ZyiarahPrivacyScreen extends StatelessWidget {
  const ZyiarahPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('سياسة الخصوصية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF4A0E0E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('خصوصيتك تهمنا'),
              _buildSectionText('نحن في تطبيق زيارة نلتزم بحماية بياناتك الشخصية وضمان سريتها. نقوم بجمع المعلومات اللازمة فقط لتقديم الخدمة وتحسين تجربتك...'),
              const SizedBox(height: 20),
              _buildSectionTitle('البيانات التي نجمعها'),
              _buildSectionText('تشمل البيانات: الاسم، رقم الجوال، الموقع الجغرافي، وتاريخ الطلبات...'),
              // Add more sections as needed
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4A0E0E)),
    );
  }

  Widget _buildSectionText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        style: GoogleFonts.tajawal(fontSize: 14, color: Colors.black87, height: 1.6),
      ),
    );
  }
}
