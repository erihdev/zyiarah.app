import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/service_model.dart';

/// كتالوج الخدمات — **للعرض فقط**.
///
/// كانت هذه الشاشة تَعِد بثلاثة أشياء لا يفعلها أيٌّ منها:
///
/// 1. **مفتاح «إخفاء الخدمة»** — يكتب `is_active` ويقول «تم إخفاء الخدمة». لا أحد
///    يقرأ الحقل: شبكة خدمات العميلة نصوص مكتوبة في الشيفرة
///    (`client_dashboard._buildDefaultStaticGrid`). فالخدمة تبقى معروضة وتُطلب،
///    والإدارة مقتنعة أنها أوقفتها. **أخطر ما في الشاشة** — لذلك أُزيل المفتاح.
/// 2. **تعديل التسعير** — يكتب `base_price`/`price_text` ويقول «تم التحديث الجذري ✅».
///    مجموعة `services` لا تُقرأ في تطبيق العميلة إطلاقاً (`ZyiarahService` مستعمل في
///    هذا الملف وحده). الأسعار الحقيقية في `service_zones` لكل منطقة.
/// 3. **شارة «الأكثر طلباً»** — لم تكن بيانات: شرطها `title.contains("تنظيف")`.
///
/// أُزيلت الثلاثة. ما بقي: عرض صادق + بيان يقول أين يُضبط كل شيء فعلاً.
/// (نفس ما فُعل ببطاقة التسعير الميتة في `admin_panel/src/pages/Services.tsx`.)
class AdminServicesScreen extends StatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  State<AdminServicesScreen> createState() => _AdminServicesScreenState();
}

class _AdminServicesScreenState extends State<AdminServicesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Color _brand = Color(0xFF006FBA);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('كتالوج الخدمات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _honestNotice(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('services').orderBy('order_index').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('تعذّر تحميل الكتالوج، تحقّق من الاتصال',
                          style: GoogleFonts.tajawal(color: Colors.grey)),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: _brand));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cleaning_services_outlined,
                              size: 72, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('لا توجد خدمات في الكتالوج',
                              style: GoogleFonts.tajawal(color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final service = ZyiarahService.fromMap(
                        docs[i].id,
                        docs[i].data() as Map<String, dynamic>,
                      );
                      return _serviceCard(service);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _honestNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.tajawal(
                    fontSize: 12, color: const Color(0xFF92400E), height: 1.7),
                children: const [
                  TextSpan(
                      text: 'هذه القائمة للعرض فقط.\n',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '• الأسعار تُضبط لكل منطقة من '),
                  TextSpan(
                      text: '«نطاقات التغطية»',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ' — الكنب والسجاد بالمتر المربع، والمكيفات لكل وحدة.\n'),
                  TextSpan(
                      text: '• الخدمات المعروضة للعميلة ثابتة داخل التطبيق ولا تتأثر بهذه القائمة.\n'),
                  TextSpan(text: '• لتعطيل خدمة في منطقة: اجعل سعرها '),
                  TextSpan(
                      text: 'صفراً',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ' في تلك المنطقة.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(ZyiarahService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(ZyiarahService.getIcon(service.iconName),
                color: _brand, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.title,
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: const Color(0xFF0F172A))),
                if (service.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(service.subtitle,
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: const Color(0xFF94A3B8))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
