import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/service_policy.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// شاشة «الشروط والأحكام» — تُفتح من التسجيل قبل الدخول.
///
/// (تصميم Stitch، 2026-09-16) كانت ثلاث فقرات ثابتة في الكود لا تصلها الإدارة.
/// الآن تعرض بنود `service_policies` المفعّلة، مجمّعة بتصنيفها، فور حفظها في
/// AdminPoliciesScreen. بلا بنود (أو عند فشل القراءة) يبقى النصّ القديم كما كان
/// كي لا تُفتح الشاشة فارغة أبداً.
class ZyiarahTermsScreen extends StatefulWidget {
  /// للاختبارات: بثّ جاهز بدل Firestore. null = القراءة من `service_policies`.
  final Stream<List<ServicePolicy>>? policies;

  const ZyiarahTermsScreen({super.key, this.policies});

  @override
  State<ZyiarahTermsScreen> createState() => _ZyiarahTermsScreenState();
}

class _ZyiarahTermsScreenState extends State<ZyiarahTermsScreen> {
  late final Stream<List<ServicePolicy>> _stream;

  @override
  void initState() {
    super.initState();
    // الترتيب النهائي (تصنيف ثم order) في ServicePolicy.visibleSorted، فلا حاجة
    // لفهرس مركّب: الاستعلام يرتّب بـ order وحده.
    _stream = widget.policies ??
        FirebaseFirestore.instance
            .collection(ServicePolicy.collectionPath)
            .orderBy('order')
            .snapshots()
            .map(ServicePolicy.fromQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الشروط والأحكام',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: ZyiarahTheme.brand,
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<List<ServicePolicy>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final visible = snap.hasData
                ? ServicePolicy.visibleSorted(snap.data!)
                : const <ServicePolicy>[];
            if (visible.isEmpty) return const _LegacyTerms();
            return _PoliciesList(policies: visible);
          },
        ),
      ),
    );
  }
}

class _PoliciesList extends StatelessWidget {
  final List<ServicePolicy> policies;
  const _PoliciesList({required this.policies});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final category in ServicePolicy.categoryLabels.keys) {
      final items = policies.where((p) => p.category == category).toList();
      if (items.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: _sectionTitle(ServicePolicy.labelOf(category)),
      ));
      for (final p in items) {
        children.add(_PolicyTile(policy: p));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: children,
    );
  }
}

class _PolicyTile extends StatelessWidget {
  final ServicePolicy policy;
  const _PolicyTile({required this.policy});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(policy.title,
                  style: GoogleFonts.tajawal(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            if (policy.mandatoryBeforeBooking)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFB91C1C).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('إلزامي قبل تأكيد الحجز',
                    style: GoogleFonts.tajawal(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB91C1C))),
              ),
          ]),
          const SizedBox(height: 6),
          Text(policy.body,
              style: GoogleFonts.tajawal(
                  fontSize: 13.5, color: Colors.black87, height: 1.7)),
        ],
      ),
    );
  }
}

/// النصّ الذي كان ثابتاً في الشاشة قبل ربطها بـ service_policies — يبقى احتياطاً.
class _LegacyTerms extends StatelessWidget {
  const _LegacyTerms();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('1. مقدمة'),
          _sectionText(
              'مرحباً بكم في تطبيق زيارة. باستخدامكم لهذا التطبيق، فإنكم توافقون على الالتزام بالشروط والأحكام التالية...'),
          const SizedBox(height: 20),
          _sectionTitle('2. الخدمات'),
          _sectionText(
              'يقوم التطبيق بتقديم خدمات التنظيف المنزلي، الصيانة، والعقود الإلكترونية وفقاً للمعايير المتبعة...'),
          const SizedBox(height: 20),
          _sectionTitle('3. سياسة الدفع'),
          _sectionText(
              'يتم الدفع مقدَّماً عبر الوسائل المتاحة في التطبيق (مدى، فيزا، Apple Pay، STC Pay، تمارا، تابي، أو رصيد المحفظة)...'),
        ],
      ),
    );
  }
}

/// شاشة «سياسة الخصوصية».
///
/// الإدارة تنشر النصّ من إعدادات النظام إلى `public_content/privacy` (يقرؤه
/// zyiarah.com/privacy) — وكانت هذه الشاشة تتجاهله وتعرض نصّاً ثابتاً. الآن
/// تعرض المنشور نفسه، والثابت احتياطاً حين يغيب أو يتعذّر جلبه.
class ZyiarahPrivacyScreen extends StatefulWidget {
  /// للاختبارات: بثّ جاهز بدل Firestore. null = القراءة من `public_content/privacy`.
  final Stream<String?>? content;

  const ZyiarahPrivacyScreen({super.key, this.content});

  @override
  State<ZyiarahPrivacyScreen> createState() => _ZyiarahPrivacyScreenState();
}

class _ZyiarahPrivacyScreenState extends State<ZyiarahPrivacyScreen> {
  late final Stream<String?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.content ??
        FirebaseFirestore.instance
            .collection('public_content')
            .doc('privacy')
            .snapshots()
            .map((d) => d.data()?['content'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('سياسة الخصوصية',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: ZyiarahTheme.brand,
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<String?>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final published = snap.data?.trim() ?? '';
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: published.isNotEmpty
                    ? [_sectionText(published)]
                    : [
                        _sectionTitle('خصوصيتك تهمنا'),
                        _sectionText(
                            'نحن في تطبيق زيارة نلتزم بحماية بياناتك الشخصية وضمان سريتها. نقوم بجمع المعلومات اللازمة فقط لتقديم الخدمة وتحسين تجربتك...'),
                        const SizedBox(height: 20),
                        _sectionTitle('البيانات التي نجمعها'),
                        _sectionText(
                            'تشمل البيانات: الاسم، رقم الجوال، الموقع الجغرافي، وتاريخ الطلبات...'),
                      ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _sectionTitle(String title) {
  return Text(
    title,
    style: GoogleFonts.tajawal(
        fontSize: 18, fontWeight: FontWeight.bold, color: ZyiarahTheme.brand),
  );
}

Widget _sectionText(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(
      text,
      style: GoogleFonts.tajawal(
          fontSize: 14, color: Colors.black87, height: 1.6),
    ),
  );
}
