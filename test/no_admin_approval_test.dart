import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (قرار المالك 2026-07-18) «احذف الاعتمادات لا أحتاجها في تطبيقي».
///
/// نظام الاعتماد اليدوي (pending_admin_approval) حُذف من الجذور: كل المنتجين
/// يكتبون pending فيدخل الطلب مسار الإسناد التلقائي مباشرة (فحص السعة ⇒
/// paid-flip اللحظي ⇒ التحرُّر الحدثي ⇒ المكنسة). حذفُ التبويب وحده كان سيترك
/// زيارات الاشتراك وطلبات المتجر تُنشأ بحالة لا يراها أحد.
String _stripComments(String src) {
  src = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return src.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}

void main() {
  test('شاشة الاعتماد محذوفة من المشروع', () {
    expect(File('lib/screens/admin/admin_approval_screen.dart').existsSync(),
        isFalse,
        reason: 'الشاشة حُذفت بقرار المالك — لا تُعاد');
  });

  test('لا أثر لحالة pending_admin_approval في كود التطبيق', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    // حارس ضد النجاح الكاذب: لو لم يُقرأ شيء فالفحص وهم.
    expect(dartFiles.length, greaterThan(50));
    for (final f in dartFiles) {
      final code = _stripComments(f.readAsStringSync());
      expect(code.contains('pending_admin_approval'), isFalse,
          reason: '${f.path} ما زال يتعامل مع حالة الاعتماد الميتة');
      expect(code.contains('AdminApprovalScreen'), isFalse,
          reason: '${f.path} ما زال يشير إلى شاشة الاعتماد المحذوفة');
    }
  });

  test('الخادم لا يُنتج الحالة ولا يقبلها', () {
    final fn = _stripComments(File('functions/index.js').readAsStringSync());
    expect(fn.contains('pending_admin_approval'), isFalse,
        reason: 'دالة خادمية ما زالت تُنشئ/تقبل حالة الاعتماد — '
            'زيارات الاشتراك وميسر يجب أن يكتبوا pending');
  });

  test('قواعد Firestore لا تسمح بإنشاء الحالة', () {
    final rules = _stripComments(File('firestore.rules').readAsStringSync());
    expect(rules.contains('pending_admin_approval'), isFalse,
        reason: 'قائمة سماح في القواعد ما زالت تقبل حالة الاعتماد');
  });

  // 2026-09-06: الحارس كان يفحص lib/ وindex.js وfirestore.rules فقط، فبقي
  // functions/test/rules.orders.test.js يُنشئ طلباً بالحالة الميتة: القاعدة
  // ترفضه على الحالة لا على is_paid، فيفشل الاختبار ويحجب — بسلسلة && —
  // عشرة فحوص للمحفظة بعده. ملفات الاختبار جزء من الجذور التي يجب تنظيفها.
  test('اختبارات المحاكي لا تستعمل الحالة الميتة', () {
    final jsFiles = Directory('functions/test')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .toList();
    // حارس ضد النجاح الكاذب: لو لم يُقرأ شيء فالفحص وهم.
    expect(jsFiles.length, greaterThan(3));
    for (final f in jsFiles) {
      final code = _stripComments(f.readAsStringSync());
      expect(code.contains('pending_admin_approval'), isFalse,
          reason: '${f.path} يبني حالة اختبار على حالة اعتماد محذوفة — '
              'القاعدة ترفضها فيفشل الاختبار لسبب غير الذي وُضع له');
    }
  });

  test('المنتجون يكتبون pending مباشرةً', () {
    final pay = File('lib/screens/payment_summary_screen.dart')
        .readAsStringSync();
    // **كان هذا عدّاً لموضعَين** (`>= 2`) — ومسارا الدفعِ صارا يَمُرّانِ
    // بحِملٍ واحدٍ (`_serviceOrderPayload`, 2026-10-08) فهبطَ العددُ إلى
    // واحد، فسقطَ الفحصُ على **جمعِ النسخِ** لا على عودةِ خطوةِ اعتماد.
    // ومقصودُه «المنتجُ يَكتبُ pending مباشرةً» يُشَدُّ الآن قدرةً:
    // الحِملُ الواحدُ يَكتبُها، ومُنادِياه اثنان — وسؤالُ «كم موضعاً
    // يُنشئُ طلباً؟» مُفوَّضٌ إلى `order_payload_single_site_test`.
    expect(pay.contains("'status': 'pending',"), isTrue,
        reason: 'حِملُ طلبِ الخدمةِ لم يَعُد يَكتبُ pending — عادت خطوةُ '
            'اعتمادٍ قبلَ الدفعِ أو تغيّرت الحالةُ الابتدائيّة');
    expect(RegExp(r'_serviceOrderPayload\(method:').allMatches(pay).length, 2,
        reason: 'مسارا الدفعِ في ملخّصِ الدفعِ يجب أن يَمُرّا بالحِملِ الواحد');
    // (تحديث لاحق بنفس اليوم) أُلغي طلب التوصيل المرتبط في orders كلياً —
    // المتجر المباشر يدير طلب المتجر نفسه (store_direct_flow_test يغطيه)،
    // فلا يجوز أن تُنشئ شاشة دفع المتجر أي مستند في orders.
    final store =
        File('lib/screens/store_payment_screen.dart').readAsStringSync();
    expect(store.contains("collection('orders').doc().set"), isFalse,
        reason: 'عودة طلب التوصيل المرتبط تعيد بطاقتين للعميل وسجلّين للإدارة');
  });

  test('إيقاعات الكرون في مواضعها الصحيحة (درس الأنكور غير الفريد)', () {
    // 2026-07-18: استبدالٌ نصّي أصاب أول "every 15 minutes" في الملف فقصّر
    // تذكيرات السائقين بدل المكنسة، وحارسٌ فحص الملف كله فلم يلحظ. الفحص هنا
    // مُقيَّد بجسم كل دالة على حدة.
    final fn = File('functions/index.js').readAsStringSync();
    String body(String exportName) {
      final i = fn.indexOf('exports.$exportName');
      expect(i, greaterThan(-1), reason: '$exportName مفقودة');
      final end = fn.indexOf('exports.', i + 10);
      return fn.substring(i, end > i ? end : fn.length);
    }

    expect(body('sweepUnassignedPaidOrders').contains('"every 5 minutes"'),
        isTrue,
        reason: 'المكنسة (الضمان الأخير) إيقاعها 5 دقائق — سؤال المالك');
    expect(body('remindDriversUpcomingTasks').contains('"every 15 minutes"'),
        isTrue,
        reason: 'تذكيرات السائقين تبقى كل 15 دقيقة — لا تتأثر بإيقاع المكنسة');
  });
}
