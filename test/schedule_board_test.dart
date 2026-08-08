import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// جدول المتابعة (طلب المالك 2026-08-08): «يشوفون بشكل يومي وأسبوعي وشهري
/// ويعرفون ماذا أمامهم». الجوهر أنه **استشرافي**: يبدأ من اليوم ويعرض القادم،
/// لا تقرير عن الماضي — ويبرز ما يحتاج تدخّلاً (بلا سائق).
void main() {
  final board = File('lib/screens/admin/admin_schedule_board_screen.dart')
      .readAsStringSync();
  final more =
      File('lib/screens/admin/admin_more_screen.dart').readAsStringSync();

  test('الطلبات نفسها ظاهرة لا أرقامها فقط', () {
    // تصحيح المالك: «الجدول يظهر الطلبات ليس فقط الأسعار». الطيّ الافتراضي كان
    // يُظهر عدداً لكل يوم، فيبدو الجدول إحصاءً آخر لا قائمة عمل.
    expect(board.contains('initiallyExpanded: true'), isTrue);
    // كل صف يحمل ما يُعرَّف به الطلب فعلاً.
    expect(board.contains("m['code']"), isTrue, reason: 'رقم الطلب');
    expect(board.contains("m['client_name']"), isTrue);
    expect(board.contains("m['client_phone']"), isTrue);
    expect(board.contains('_statusAr('), isTrue, reason: 'حالة الطلب بالعربية');
  });

  test('الإيراد ثانوي لا مؤشّر رئيسي', () {
    expect(board.contains('الإيراد المتوقع: '), isTrue,
        reason: 'سطر ملخّص أسفل المؤشرات لا بطاقة بحجمها');
  });

  test('المدَيات الثلاثة موجودة', () {
    for (final r in ['day', 'week', 'month']) {
      expect(board.contains('BoardRange.$r'), isTrue);
    }
    expect(board.contains("'اليوم'"), isTrue);
    expect(board.contains("'الأسبوع'"), isTrue);
    expect(board.contains("'الشهر'"), isTrue);
  });

  test('استشرافي: يبدأ من اليوم لا من الماضي', () {
    // بداية النطاق = منتصف ليلة اليوم، والنهاية = اليوم + مدة المدى.
    expect(board.contains('DateTime(n.year, n.month, n.day)'), isTrue);
    expect(board.contains('_start.add(Duration(days: _range.days))'), isTrue);
    expect(board.contains('isGreaterThanOrEqualTo: Timestamp.fromDate(_start)'),
        isTrue);
  });

  test('الحالات المنتهية لا تُعدّ ضمن «ما أمامنا»', () {
    expect(board.contains("'cancelled'"), isTrue);
    expect(board.contains("'rejected'"), isTrue);
    expect(board.contains("'completed'"), isTrue);
  });

  test('«بلا سائق» يقبل الاسمين ويعامل الفراغ كغير مُسنَد', () {
    // driver_id = '' كانت تُحسب مُسنَدة فيختفي الطلب من التنبيه الوحيد القابل للتصرّف.
    expect(board.contains("m['driver_id'] ?? m['driverId']"), isTrue);
    expect(board.contains('s.isEmpty) ? null : s'), isTrue);
  });

  test('«بلا سائق» يُنذر على الفشل الحقيقي فقط لا على الطبيعي', () {
    // الإسناد يقع عند قلب الطلب إلى «مدفوع» لا عند إنشائه؛ فغير المدفوع بلا سائق
    // سلوك صحيح، والطلب بلا موعد يُحوَّل عمداً إلى under_review لتُسنده الإدارة.
    // عدُّهما إنذاراً كاذباً يُفقد الرقم قيمته — وهو ما سأل عنه المالك.
    expect(board.contains('static bool _needsDriver('), isTrue);
    expect(board.contains("m['service_date'] == null) return false"), isTrue,
        reason: 'الطلب الإداري بلا موعد ليس فشل إسناد');
    expect(board.contains("m['is_paid'] == true || isSub"), isTrue,
        reason: 'المدفوع وزيارة الاشتراك وحدهما يستحقان الإنذار');
    // العدّاد وشارة اليوم ووسم الصف تستخدم القاعدة نفسها — وإلا تناقضت الأرقام.
    expect('_needsDriver('.allMatches(board).length, greaterThanOrEqualTo(4),
        reason: 'التعريف + العدّاد + شارة اليوم + وسم الصف');
    expect(board.contains('يُسنَد بعد الدفع'), isTrue,
        reason: 'وسم رمادي هادئ بدل الأحمر للحالة الطبيعية');
  });

  test('الاشتراكات تُفصل عن الطلبات العادية', () {
    // زيارة الاشتراك بلا إيراد جديد لكنها تستهلك سائقاً — خلطها يخفي الضغط.
    expect(board.contains("m['contract_id'] != null"), isTrue);
    expect(board.contains("m['payment_method'] == 'subscription'"), isTrue);
    expect(board.contains('زيارات اشتراكات'), isTrue);
  });

  test('الاستعلام محدود ويُنبَّه عند بلوغ الحدّ', () {
    expect(board.contains('_fetchLimit'), isTrue);
    expect(board.contains('.limit(_fetchLimit)'), isTrue);
    expect(board.contains('>= _fetchLimit'), isTrue,
        reason: 'القصّ الصامت يُقرأ «هذا كل شيء» وهو ليس كذلك');
  });

  test('لا فشل صامت عند خطأ الاستعلام', () {
    // بلا هذا تظهر الشاشة فارغة فتُفهم «لا مواعيد» — وهو أسوأ من رسالة خطأ.
    expect(board.contains('snap.hasError'), isTrue);
    expect(board.contains('تعذّر تحميل الجدول'), isTrue);
  });

  test('مُدرَج في قائمة الإدارة بأدوار صحيحة', () {
    expect(more.contains('AdminScheduleBoardScreen'), isTrue);
    expect(more.contains('جدول المتابعة'), isTrue);
    final i = more.indexOf('AdminScheduleBoardScreen()');
    final roles = more.substring(i, i + 160);
    expect(roles.contains('super_admin'), isTrue);
    expect(roles.contains('orders_manager'), isTrue);
  });
}
