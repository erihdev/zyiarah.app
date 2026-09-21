import 'package:cloud_firestore/cloud_firestore.dart';

/// بند من «شروط وضوابط الخدمة والتعاقد» — مستند في مجموعة `service_policies`.
///
/// (تصميم Stitch، 2026-09-16) قبل هذا النموذج كانت الشروط كتلتي نصّ في
/// system_configs/main_settings: `contract_terms` تذهب إلى عقد PDF،
/// و`privacy_policy` إلى الموقع — ولا تصل أيٌّ منهما شاشة الشروط للعميل، التي
/// كان نصّها ثابتاً في الكود. هنا كل بند مستند مستقلّ: مصنَّف، قابل للتفعيل
/// بنداً بنداً، ويُعرض للعميل فور حفظه. الكتلتان القديمتان لم تُمسّا.
class ServicePolicy {
  final String id;
  final String title;
  final String body;
  final String category;
  final bool enabled;

  /// شارة «إلزامي قبل تأكيد الحجز» في التصميم. عرضٌ فقط حالياً: بوّابة الموافقة
  /// الفعلية في شاشتي الدفع صندوقٌ قائم أصلاً ولم يُربط بهذا الحقل — ربطه قرار
  /// منفصل لأنه يمسّ مسار الدفع (CP-3).
  final bool mandatoryBeforeBooking;
  final int order;
  final DateTime? updatedAt;

  const ServicePolicy({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.enabled,
    required this.mandatoryBeforeBooking,
    required this.order,
    this.updatedAt,
  });

  static const String collectionPath = 'service_policies';

  /// التصنيفات الأربعة كما في شرائح التصفية أعلى شاشة Stitch — مفاتيح ثابتة في
  /// المستند، وتسميات عربية للعرض. الترتيب هنا هو ترتيب الأقسام في شاشة العميل.
  static const Map<String, String> categoryLabels = {
    'contracts': 'العقود والاشتراكات',
    'privacy_safety': 'الخصوصية والسلامة',
    'cancellation_scheduling': 'الإلغاء والجدولة',
    'mountain_routes': 'المسارات الجبلية',
  };

  /// «موضع ونطاق الظهور» في حوار الإضافة — وصف لما يغطّيه كل تصنيف.
  static const Map<String, String> categoryScopes = {
    'contracts': 'باقات الزيارات وصلاحية العقد والاشتراك',
    'privacy_safety': 'اشتراطات الكوادر النسائية وخصوصية العائلة',
    'cancellation_scheduling': 'تعديل المواعيد والإلغاء والاسترداد',
    'mountain_routes': 'الوعورة والطقس والوصول للمواقع الجبلية',
  };

  static const String defaultCategory = 'contracts';

  static String labelOf(String category) =>
      categoryLabels[category] ?? category;

  factory ServicePolicy.fromMap(String id, Map<String, dynamic> m) {
    final rawCategory = m['category'];
    final category = rawCategory is String &&
            categoryLabels.containsKey(rawCategory)
        ? rawCategory
        : defaultCategory;
    final rawOrder = m['order'];
    final rawUpdated = m['updated_at'];
    return ServicePolicy(
      id: id,
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      category: category,
      enabled: m['enabled'] == true,
      mandatoryBeforeBooking: m['mandatory_before_booking'] == true,
      order: rawOrder is num ? rawOrder.toInt() : 0,
      updatedAt: rawUpdated is Timestamp ? rawUpdated.toDate() : null,
    );
  }

  factory ServicePolicy.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      ServicePolicy.fromMap(d.id, d.data() ?? const {});

  static List<ServicePolicy> fromQuery(QuerySnapshot<Map<String, dynamic>> q) =>
      q.docs.map(ServicePolicy.fromDoc).toList();

  /// ما يراه العميل: البنود المفعّلة فقط، مرتّبة بالتصنيف (ترتيب categoryLabels)
  /// ثم بـ order. الترتيب هنا لا في الاستعلام كي لا نحتاج فهرساً مركّباً.
  static List<ServicePolicy> visibleSorted(Iterable<ServicePolicy> all) {
    final keys = categoryLabels.keys.toList();
    return all.where((p) => p.enabled).toList()
      ..sort((a, b) {
        final byCategory =
            keys.indexOf(a.category).compareTo(keys.indexOf(b.category));
        return byCategory != 0 ? byCategory : a.order.compareTo(b.order);
      });
  }

  /// الحقول المكتوبة عند الحفظ — بلا `updated_at`، تضيفه الشاشة بطابع الخادم.
  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'category': category,
        'enabled': enabled,
        'mandatory_before_booking': mandatoryBeforeBooking,
        'order': order,
      };
}
