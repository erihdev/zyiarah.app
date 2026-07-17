// حارس دائم: **الدفع عند الاستلام محذوف من الجذور** — لا يعود، ولو بسطر واحد.
//
// قرار المالك: «احذف ميزة الدفع عند الاستلام من الجذور، لا يريده العميل مني».
// الدفع مقدَّم دائماً (بطاقة / Apple Pay / STC Pay / تمارا / تابي / محفظة).
//
// لماذا حارس وليس حذفاً فقط؟ لأن الميزة كانت **قد أُزيلت من الواجهة مرّة من قبل**
// («خيار الدفع عند الاستلام أُزيل بطلب الإدارة») بينما بقي كل المنطق تحتها حيّاً:
// حوار الرمز لدى السائق، ومفتاح cod_enabled في لوحتَي الإدارة، وصلاحيات كتابة
// is_paid للسائق في firestore.rules. إزالةُ الزر وحده تترك ميزةً حيّة بلا باب —
// وأخطرها أن السائق يظلّ قادراً على تعليم الطلب «مدفوع».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يزيل التعليقات: التعليقات هنا **تشرح ما حُذف**، ففحص المصدر الخام يسقط الحارس
/// على شرحه هو — إنذار كاذب يدفع لتعطيل الحارس فيصير أسوأ من لا شيء.
String _code(String path) {
  final src = File(path).readAsStringSync();
  return src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

List<File> _sources(String dir, List<String> exts) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => exts.any((e) => f.path.endsWith(e)))
    .toList();

void main() {
  // الملفّات التي يُسمح فيها بذكر waiting_payment_cod: شاهد قبر للبيانات التاريخية فقط.
  // طلبٌ قديم بهذه الحالة يجب أن يظلّ **مقروءاً** في الواجهة بدل عرض حالة خامّة —
  // لكن لا يجوز لأي شيفرة أن **تُنشئ** هذه الحالة من جديد.
  const legacyLabelFiles = {
    'lib/utils/status_util.dart',
    'lib/screens/admin/admin_maintenance_screen.dart',
    'lib/screens/orders_list_screen.dart',
    'lib/screens/admin/admin_store_orders_screen.dart',
    'admin_panel/src/pages/Maintenance.tsx',
  };

  test('لا كود يختار «الدفع عند الاستلام» أو ينشئ حالته', () {
    final offenders = <String>[];
    final files = [
      ..._sources('lib', ['.dart']),
      ..._sources('admin_panel/src', ['.tsx', '.ts']),
      File('functions/index.js'),
    ];
    for (final f in files) {
      final rel = f.path.replaceAll(r'\', '/').replaceAll(RegExp(r'^.*?(?=lib/|admin_panel/|functions/)'), '');
      final code = _code(f.path);

      // (أ) ممنوعة **في كل مكان**: هذه هي الميزة نفسها — اختيارها، مفاتيحها،
      //     رمزها، تأكيد تحصيلها، وإشعاره. لا مبرّر لبقاء أيٍّ منها بعد الحذف.
      for (final needle in [
        "'cod'", '"cod"',
        'cod_enabled', 'payment_pin', 'cash_confirmed', 'cash_collected_by',
        'notifyAdminOfCashCollection',
      ]) {
        if (code.contains(needle)) offenders.add('$rel  ←  $needle');
      }

      // (ب) مسموحة **كتسمية تاريخية فقط**: قيمٌ قد تحملها مستندات قديمة. تركها
      //     مقروءةً يمنع عرض حالة خامّة للإدارة؛ لكن لا يجوز لأي شيفرة أن تُنشئها.
      for (final legacy in ['waiting_payment_cod', 'cash_on_delivery']) {
        if (code.contains(legacy) &&
            !legacyLabelFiles.any((allowed) => rel.endsWith(allowed))) {
          offenders.add('$rel  ←  $legacy (خارج ملفّات الشاهد)');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '\n\nالدفع عند الاستلام محذوف من الجذور بقرار المالك.\n'
          'هذه المواضع تُعيده:\n  • ${offenders.join('\n  • ')}\n',
    );
  });

  test('السائق لا يستطيع تعليم الطلب «مدفوع» — القواعد لا تسمح بأي حقل دفع', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('Driver (Direct Dispatch)');
    expect(i, greaterThan(-1), reason: 'قاعدة السائق اختفت — حدِّث الحارس');
    final block = rules.substring(i, rules.indexOf(']);', i));
    for (final field in [
      "'is_paid'", "'paid_at'", "'cash_collected_by'",
      "'cash_confirmed'", "'cash_confirmed_at'",
      "'payment_pin'", "'payment_pin_generated_at'",
    ]) {
      expect(block.contains(field), isFalse,
          reason: 'السائق يستطيع كتابة $field — كانت صلاحية COD، '
              'وبقاؤها بعد حذفها يعني أن السائق يعلّم الطلب مدفوعاً بلا تحصيل.');
    }
  });

  test('قاعدة السائق تسمح بـ completed_distance_m — وإلا تعطّل الإكمال', () {
    // hasOnly ترفض **المعاملة كاملة** لأي مفتاح خارج القائمة. و driver_dashboard
    // يكتب completed_distance_m عند الإكمال متى توفّر GPS ⇒ غيابه من القائمة كان
    // يُفشل إكمال الطلب لدى كل سائق يعمل GPS جهازه، وينجح لمن لا يعمل.
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('Driver (Direct Dispatch)');
    final block = rules.substring(i, rules.indexOf(']);', i));
    expect(block.contains("'completed_distance_m'"), isTrue);

    final driver = _code('lib/screens/driver_dashboard.dart');
    expect(driver.contains("'completed_distance_m'"), isTrue,
        reason: 'إن توقّف السائق عن كتابته فأزِله من القواعد أيضاً — قائمة تسمح بما لا يُكتب تتعفّن');
  });

  test('لا نصّ يَعِد العميلة بالدفع عند الاستلام', () {
    final offenders = <String>[];
    for (final f in [
      ..._sources('lib/screens', ['.dart']),
      ..._sources('admin_panel/src', ['.tsx']),
    ]) {
      final rel = f.path.replaceAll(r'\', '/').replaceAll(RegExp(r'^.*?(?=lib/|admin_panel/)'), '');
      if (legacyLabelFiles.any((a) => rel.endsWith(a))) continue;
      final code = _code(f.path);
      // الشروط والأحكام كانت تَعِد به صراحةً — وعدٌ تعاقدي لم نعد نفي به.
      if (code.contains('الدفع عند الاستلام') || code.contains('عند الاستلام')) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty,
        reason: 'نصّ يَعِد بخدمة محذوفة: $offenders');
  });
}
