// حارس: مسار «طلب عرض السعر» (maintenance_requests) محذوف — لا يعود.
//
// قرار المالك: «احذفها نهائياً». وقد أثبتت البيانات الحيّة صحّته: المجموعة تحوي
// مستندين فقط، كلاهما «غسيل مكيفات» بحالة under_review من اختبار قديم — و**ولا طلب
// صيانة أجهزة منزلية واحد**. الخدمة لم تُستخدم قط.
//
// المكيفات صارت طلباً مباشراً مسعّراً (AcServiceDetailsScreen). صيانة الأجهزة
// المنزلية أُلغيت. لم تبقَ شاشةٌ تُنشئ مستنداً في هذه المجموعة.
//
// **القراءة التاريخية مسموحة عمداً**: التحليلات (إيرادات ماضية) والبحث وتفاصيل الطلب
// تقرأ الأرشيف. هذا نفس مبدأ شواهد القبر في no_cod_test: الميزة تموت، والتاريخ يبقى
// مقروءاً. الممنوع هو **الإنشاء**.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

List<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('الشاشات والخدمات المحذوفة لم تعد موجودة', () {
    for (final gone in [
      'lib/screens/maintenance_request_screen.dart',
      'lib/services/maintenance_listener_service.dart',
      'lib/screens/admin/admin_maintenance_screen.dart',
      'admin_panel/src/pages/Maintenance.tsx',
    ]) {
      expect(File(gone).existsSync(), isFalse, reason: '$gone عاد للوجود');
    }
  });

  test('لا شيء يُنشئ طلب صيانة أو يمرّر maintenanceId', () {
    final offenders = <String>[];
    for (final f in _dart('lib')) {
      final rel = f.path.replaceAll(r'\', '/').replaceAll(RegExp(r'^.*?(?=lib/)'), '');
      final code = _code(f.path);
      if (code.contains('maintenanceId')) offenders.add('$rel ← maintenanceId');
      if (RegExp(r"collection\('maintenance_requests'\)\s*\.\s*doc\([^)]*\)\s*\.\s*(set|add|update)")
          .hasMatch(code)) {
        offenders.add('$rel ← كتابة في maintenance_requests');
      }
      if (code.contains("collection('maintenance_requests').add(")) {
        offenders.add('$rel ← إنشاء طلب صيانة');
      }
    }
    expect(offenders, isEmpty,
        reason: '\nمسار عرض السعر محذوف. هذه المواضع تُعيده:\n  • ${offenders.join('\n  • ')}\n');
  });

  test('العميلة لا تصل شاشة طلب صيانة من أي مدخل', () {
    final dash = _code('lib/screens/client_dashboard.dart');
    expect(dash.contains('ZyiarahMaintenanceRequestScreen'), isFalse);
    expect(dash.contains("routeType == '/maintenance'"), isFalse,
        reason: 'بانر /maintenance كان يفتح الشاشة المحذوفة');
    expect(dash.contains('_buildMaintenanceAlertCard'), isFalse,
        reason: 'بطاقة «سعّرت الإدارة طلبك — ادفع الآن» بلا مسار يُنشئه');

    final popup = _code('lib/services/popup_service.dart');
    expect(popup.contains('ZyiarahMaintenanceRequestScreen'), isFalse);
    expect(popup.contains('AcServiceDetailsScreen'), isTrue,
        reason: "بانر 'maintenance' يجب أن يوجّه للمكيفات — بانر بلا وجهة = فشل صامت");
  });

  test('القواعد: المجموعة أرشيف — لا إنشاء ولا تعديل', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /maintenance_requests/{requestId}');
    expect(i, greaterThan(-1), reason: 'قاعدة المجموعة اختفت — حدِّث الحارس');
    final block = rules.substring(i, rules.indexOf('}', rules.indexOf('allow delete', i)));
    expect(block.contains('allow create, update: if false;'), isTrue,
        reason: 'باب خلفي: إنشاء مستندات لا تعرضها أي شاشة إدارية');
    expect(block.contains('allow read: if isAdmin();'), isTrue,
        reason: 'التحليلات والبحث يقرآن الأرشيف — لا تُغلق القراءة');
  });

  test('تبويب «قسم الصيانة» أُزيل من طلبات العميلة', () {
    final ol = _code('lib/screens/orders_list_screen.dart');
    expect(ol.contains('قسم الصيانة'), isFalse);
    expect(ol.contains('_buildMaintenanceTab'), isFalse);
    expect(ol.contains('TabController(length: 2'), isTrue,
        reason: 'طول التبويبات يجب أن يطابق عددها وإلا انهارت الشاشة');
  });
}
