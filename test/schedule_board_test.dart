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

  group('تكافؤ لوحة الويب', () {
    final web = File('admin_panel/src/pages/ScheduleBoard.tsx').readAsStringSync();

    test('الجدول موجود في الويب أيضاً ومربوط بمسار وقائمة', () {
      expect(File('admin_panel/src/App.tsx').readAsStringSync()
          .contains('<ScheduleBoard />'), isTrue);
      expect(File('admin_panel/src/components/Layout.tsx').readAsStringSync()
          .contains("path: '/schedule'"), isTrue);
      expect(File('admin_panel/src/config/access.ts').readAsStringSync()
          .contains("'/schedule'"), isTrue, reason: 'بلا صلاحيات لا يفتحه أحد');
    });

    test('قاعدة «بلا سائق» مطابقة للتطبيق حرفياً', () {
      // اختلافها بين الواجهتين يعني رقمين متناقضين لنفس اليوم.
      expect(web.contains('needsDriver'), isTrue);
      expect(web.contains('!o.service_date) return false'), isTrue);
      expect(web.contains("o.is_paid === true || isSub(o)"), isTrue);
      expect(web.contains('يُسنَد بعد الدفع'), isTrue);
    });

    test('نفس المدَيات ونفس الحدّ ونفس الحالات المنتهية', () {
      for (final l in ['اليوم', 'الأسبوع', 'الشهر']) {
        expect(web.contains("'$l'"), isTrue);
      }
      expect(web.contains('FETCH_LIMIT'), isTrue);
      expect(web.contains('>= FETCH_LIMIT'), isTrue);
      for (final s in ['cancelled', 'rejected', 'completed']) {
        expect(web.contains("'$s'"), isTrue);
      }
    });

    test('الطلبات نفسها ظاهرة ولا فشل صامت', () {
      expect(web.contains('o.code'), isTrue);
      expect(web.contains('o.client_phone'), isTrue);
      expect(web.contains('statusAr'), isTrue);
      expect(web.contains('تعذّر تحميل الجدول'), isTrue);
    });
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
