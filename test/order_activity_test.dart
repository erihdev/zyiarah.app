import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/driver_schedule.dart';
import 'package:zyiarah/utils/order_activity.dart';
import 'package:zyiarah/utils/order_lifecycle.dart';

/// يُجرّد التعليقاتَ سطراً كاملاً ثمّ يَلتقطُ النصوصَ داخل مجموعةٍ مُسمّاة.
Set<String> _dartSet(String src, String name) {
  final body = src.split('\n').where((l) {
    final t = l.trimLeft();
    return !t.startsWith('//') && !t.startsWith('///');
  }).join('\n');
  final i = body.indexOf('$name = {');
  expect(i, greaterThan(-1), reason: 'لم تُوجد المجموعة $name');
  final j = body.indexOf('};', i);
  final block = body.substring(i, j);
  return RegExp("'([a-z_]+)'")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

Set<String> _tsSet(String src, String name) {
  final body = src.split('\n').where((l) {
    final t = l.trimLeft();
    return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
  }).join('\n');
  final i = body.indexOf('$name: readonly string[] = [');
  expect(i, greaterThan(-1), reason: 'لم تُوجد المجموعة $name في المرآة');
  final j = body.indexOf('];', i);
  final block = body.substring(i, j);
  return RegExp("'([a-z_]+)'")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final dartSrc = File('lib/utils/order_activity.dart').readAsStringSync();
  final tsSrc =
      File('admin_panel/src/utils/orderActivity.ts').readAsStringSync();
  final insights =
      File('lib/screens/admin/admin_insights_screen.dart').readAsStringSync();
  final ordersList =
      File('lib/screens/orders_list_screen.dart').readAsStringSync();
  final dashboard =
      File('admin_panel/src/pages/Dashboard.tsx').readAsStringSync();
  final storeService =
      File('lib/services/store_service.dart').readAsStringSync();

  group('القاعدة نفسها', () {
    test('الحالات المنتهية وحدها تُقرأ منتهية', () {
      for (final s in ['delivered', 'completed', 'cancelled', 'rejected']) {
        expect(orderIsOpen(s), isFalse, reason: s);
      }
    });

    test('كل حالة من دورة الحياة الحقيقية تُقرأ مفتوحة', () {
      // المجموعتان من `order_lifecycle.dart` + دورة المتجر + ما قبل الدفع.
      const live = [
        'pending',
        'awaiting_payment',
        'under_review',
        'assigned',
        'scheduled',
        'accepted',
        'on_the_way',
        'in_progress',
        'delivering',
        'processing',
        'shipped',
        'paid',
        'approved',
        'waiting_payment',
      ];
      for (final s in live) {
        expect(orderIsOpen(s), isTrue, reason: s);
      }
    });

    test('حالة لم تُولد بعد تُقرأ مفتوحة — وهذا هو الشق المُصلَح', () {
      // عينُ الخلل: التعدادُ أسقطَ بصمتٍ كلَّ حالةٍ أُضيفت بعده.
      for (final s in ['out_for_delivery', 'preparing', 'redelivery', 'زائدة']) {
        expect(orderIsOpen(s), isTrue, reason: s);
      }
    });

    test('الغائب والفارغ مفتوحان لا منتهيان', () {
      expect(orderIsOpen(null), isTrue);
      expect(orderIsOpen(''), isTrue);
      expect(orderIsOpen('  '), isTrue);
      expect(orderIsOpen(7), isTrue);
    });

    test('المسافات المحيطة لا تُغيّر الحكم', () {
      expect(orderIsOpen(' delivered '), isFalse);
      expect(orderIsOpen(' on_the_way '), isTrue);
    });

    test('«يَنتظرُ إجراءً» هو ما تَعرضُ له الإدارةُ زرّاً', () {
      for (final s in ['under_review', 'delivering', 'processing', 'shipped']) {
        expect(storeOrderNeedsAction(s), isTrue, reason: s);
      }
      // المدفوعُ غيرُ بعد، والمنتهي، وغيرُ الموجود — لا إجراء.
      for (final s in ['awaiting_payment', 'delivered', 'pending', '', 'x']) {
        expect(storeOrderNeedsAction(s), isFalse, reason: s);
      }
      expect(storeOrderNeedsAction(null), isFalse);
    });

    test('«المنتهي» و«يَنتظرُ إجراءً» لا يتقاطعان', () {
      expect(
          kTerminalOrderStatuses.intersection(kStoreNeedsActionStatuses), isEmpty);
    });

    test('refunded ليست حالةَ status — إدراجُها كان سيُعيد الخلل نفسه', () {
      expect(kTerminalOrderStatuses.contains('refunded'), isFalse);
      // والسببُ مكتوبٌ في الملف كي لا تُضاف لاحقاً «تكميلاً».
      expect(dartSrc.contains('payment_status'), isTrue);
    });
  });

  group('المرآة لا تَنفكّ', () {
    test('المجموعتان متطابقتان في الملفَّين', () {
      expect(_tsSet(tsSrc, 'TERMINAL_ORDER_STATUSES'),
          equals(_dartSet(dartSrc, 'kTerminalOrderStatuses')));
      expect(_tsSet(tsSrc, 'STORE_NEEDS_ACTION_STATUSES'),
          equals(_dartSet(dartSrc, 'kStoreNeedsActionStatuses')));
    });

    test('المجموعةُ الدارتيّةُ هي ما يَقرؤه الاختبارُ فعلاً', () {
      // كي لا يَمرَّ تطابقُ نصَّين بينما الكودُ يَستخدمُ مجموعةً ثالثة.
      expect(_dartSet(dartSrc, 'kTerminalOrderStatuses'),
          equals(kTerminalOrderStatuses));
      expect(_dartSet(dartSrc, 'kStoreNeedsActionStatuses'),
          equals(kStoreNeedsActionStatuses));
    });
  });

  group('مواضع الاستدعاء — قاعدةٌ لا تُستدعى قاعدةٌ ميتة', () {
    test('عدّاد «طلبات نشطة» يَمرّ بالقاعدة ثلاثَ مرّات', () {
      expect(RegExp(r'orderIsOpen\(').allMatches(insights).length, 3,
          reason: 'orders + maintenance_requests + store_orders');
      expect(insights.contains("import 'package:zyiarah/utils/order_activity.dart'"),
          isTrue);
    });

    test('لا تعدادَ متبقٍّ في عدّاد اللوحة', () {
      // أيٌّ من هذه الثلاثِ كان يُنتج العدَّ الناقص.
      expect(insights.contains("status == 'assigned'"), isFalse);
      expect(insights.contains("sStatus == 'processing'"), isFalse);
      expect(insights.contains("status == 'waiting_payment'"), isFalse);
    });

    test('تبويبا العميلة بالقاعدة، ولا قائمتَي حالاتٍ بعدها', () {
      expect(RegExp(r'orderIsOpen\(').allMatches(ordersList).length, 4,
          reason: 'شرطان في كلِّ تبويب');
      // الكودُ يَشرحُ القرارَ بتسميةِ القائمةِ المحذوفة، فنُجرّدُ التعليقَ قبل
      // البحث — وإلّا سَقطَ الحارسُ على توثيقِه (وقد سَقطَ).
      final code = ordersList.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      }).join('\n');
      expect(code.contains('activeStatuses'), isFalse);
      expect(code.contains('historyStatuses'), isFalse);
      // وبالمقابل: اللفظُ ما زال في النصِّ الخامّ، فلا يُفرّغُ التجريدُ الحارس.
      expect(ordersList.contains('historyStatuses'), isTrue);
    });

    test('بطاقةُ اللوحةِ تَستعلمُ المجموعةَ لا pending', () {
      expect(dashboard.contains("where('status', '==', 'pending')"), isFalse,
          reason: 'الشرطُ الصفريُّ الأبدي');
      expect(dashboard.contains('STORE_NEEDS_ACTION_STATUSES'), isTrue);
      expect(dashboard.contains("from '../utils/orderActivity'"), isTrue);
    });

    test('عنوانُ البطاقةِ لا يُسمّي خطوةَ موافقةٍ أُلغيت', () {
      expect(dashboard.contains('طلبات بانتظار الموافقة'), isFalse);
      expect(dashboard.contains('طلبات متجر تحتاج إجراء'), isTrue);
    });
  });

  group('بطاقاتُ «الطلبات» في لوحةِ المالك تَعدُّ ما يَقولُ عنوانُها', () {
    test('لا حالةَ ميتةً في عدّادِ البطاقات', () {
      final code = insights.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      }).join('\n');
      // `waiting_payment` (بلا `a` وبلا `approved_`) لا يَكتبُها شيءٌ على طلب.
      expect(RegExp(r"(?<![_a-z])waiting_payment").hasMatch(code), isFalse,
          reason: 'الاسمُ الحيُّ awaiting_payment');
      expect(code.contains("'status'] == 'pending'"), isFalse,
          reason: 'pending على طلبِ متجرٍ صفرٌ بنيويّ');
      // وبالمقابل: اللفظُ ما زال في التعليقِ الذي يَشرحُ إزالتَه.
      expect(insights.contains('waiting_payment'), isTrue);
    });

    test('بطاقةُ الإسنادِ تَعدُّ ما قبلَ الإسنادِ بلا سائق', () {
      expect(insights.contains('kPreDispatchStatuses.contains'), isTrue);
      expect(insights.contains("hasDriver"), isTrue,
          reason: 'طلبٌ له سائقٌ لا يَنتظرُ إسناداً');
      expect(insights.contains('طلبات بانتظار الإسناد'), isTrue);
      // العنوانُ القديمُ مذكورٌ في التعليقِ الذي يَشرحُ تغييرَه، فنُجرّدُ أوّلاً.
      final c = insights.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      }).join('\n');
      expect(c.contains('الطلبات المجدولة'), isFalse,
          reason: 'العنوانُ كان يُسمّي ما لا يَعدّ');
      expect(insights.contains('الطلبات المجدولة'), isTrue,
          reason: 'لو غابَ من الخامِّ فالتجريدُ حَجبَ شيئاً');
    });

    test('بطاقةُ المتجرِ تَمرُّ بالقاعدةِ المشتركة', () {
      expect(insights.contains('storeOrderNeedsAction('), isTrue);
      expect(insights.contains('طلبات متجر تحتاج إجراء'), isTrue);
    });

    test('بطاقةُ العقودِ تَعدُّ فعلاً، ولا صفرَ مكتوباً بيدِه', () {
      expect(insights.contains('count: 0,'), isFalse,
          reason: 'رقمٌ لم يَحسبْه أحد');
      expect(insights.contains('_pendingContracts'), isTrue);
      expect(insights.contains("collection('contracts')"), isTrue);
      expect(insights.contains('عقود بانتظار المراجعة'), isTrue);
    });

    test('عدُّ العقودِ `count()` بلا حقلٍ مُجمَّع فلا فهرسَ مركّباً', () {
      // الجملةُ وحدَها، حتّى فاصلتِها المنقوطة. وقعَ فخُّ الحدِّ هنا
      // **مرّتَين**: نافذةُ عدِّ أحرفٍ أوّلاً — كانت تَبتلعُ الاستعلامَ التالي
      // (وفيه `orderBy`) فتَسقطُ بلا سبب — ثمّ حدٌّ بنصٍّ حرفيٍّ هو `.get());`،
      // وأبطلَه إلحاقُ `.timeout(kNetCallTimeout)` بالقراءةِ نفسِها فعادت
      // الشريحةُ تَتجاوزُ الجملةَ إلى تاليتِها. والحدُّ الآن **بنيويّ**: نهايةُ
      // الجملةِ لا شكلُ آخرِ نداءٍ فيها.
      final i = insights.indexOf("collection('contracts')");
      final block = insights.substring(i, insights.indexOf(';', i) + 1);
      expect(block.contains('.count()'), isTrue);
      expect(block.contains('orderBy'), isFalse,
          reason: 'ترتيبٌ فوقَ مساواةٍ يَطلبُ فهرساً مركّباً');
      expect(block.contains('sum(') || block.contains('average('), isFalse);
    });
  });

  group('الأساس الذي بُنيت عليه القاعدة', () {
    test('طلبُ المتجرِ يُنشَأ awaiting_payment لا pending', () {
      // لو تغيّر هذا فالقاعدةُ تَحتاجُ مراجعةً لا إسكاتاً.
      expect(storeService.contains("'status': 'awaiting_payment'"), isTrue);
      expect(storeService.contains("'status': 'pending'"), isFalse);
    });
  });
  group('ولا نسخةَ يدويّةً رابعةً للقاعدةِ بلا مراجعة', () {
    test('المواضعُ الثلاثةُ الباقيةُ هي المعروفةُ وحدَها', () {
      // ثلاثةُ فحوصٍ يدويّةٍ للانتهاءِ ما زالت في `lib/`، و**كلُّها صحيحةٌ في
      // موضعِها** لأنّها تَقرأ `orders` وحدَها، و`delivered`/`rejected` لا
      // يُكتبانِ عليها أبداً. فلا تُلمَس: لمسُ شفرةٍ سليمةٍ بلا خللٍ خلفَها
      // مخاطرةٌ بلا مقابل. لكنّ رابعةً تَظهرُ غداً على `store_orders` تَعدُّ
      // `delivered` نشطاً — وهذا الفحصُ يُجبرُ على مراجعتِها.
      const known = {
        'lib/screens/admin/admin_more_screen.dart',
        'lib/screens/driver_dashboard.dart',
      };
      final found = <String>{};
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // **في السطرِ نفسِه**: فحصُ الانتهاءِ تعبيرٌ منطقيٌّ واحد. ومطابقةُ
        // الملفِّ كلِّه التقطت `admin_order_details_screen` — وفيها
        // `oldStatus != 'cancelled'` و`!= 'completed'` في سطرَين مختلفَين،
        // وهو فحصُ **انتقالِ** حالةٍ لا فحصُ انتهاء.
        for (final l in f.readAsStringSync().split('\n')) {
          final t = l.trimLeft();
          if (t.startsWith('//') || t.startsWith('///')) continue;
          if (RegExp(r"!=\s*'completed'").hasMatch(l) &&
              RegExp(r"!=\s*'cancelled'").hasMatch(l)) {
            found.add(f.path.replaceAll('\\', '/'));
          }
        }
      }
      expect(found, equals(known),
          reason: 'نسخةٌ يدويّةٌ جديدةٌ للانتهاء: إن كانت على `orders` فأضِفها '
              'هنا، وإن كانت على `store_orders` فاستخدم `orderIsOpen` — '
              'وإلّا عُدَّ الطلبُ المُسلَّمُ نشطاً');
    });
  });

  group('قارئُ النسخِ اليدويّةِ وُسِّعَ ليَرى اللوحةَ والمجموعاتِ الحرفيّة', () {
    // **نتيجةٌ سالبةٌ تُسجَّلُ كما هي (2026-10-06).** مسحُ «قاعدةٌ لها موضعٌ
    // واحدٌ ونسخٌ بيَدٍ» وجدَ **ثلاثاً** لم يَرَها الفحصُ أعلاه: `isFinalStatus`
    // في صفحةِ طلباتِ اللوحة، و`DEAD` في لوحِ المواعيدِ الويبيّ،
    // و`_deadStatuses` في نظيرِه الدارتيّ — غابت عنه لأنّه يُطابِقُ
    // `!= 'completed'` **في سطرٍ واحد**، فمجموعةٌ حرفيّةٌ أو `===` تَمرّ.
    //
    // **وقد وُحِّدت ثمّ أُعيدت.** الحكمُ أعلاه صريحٌ ومُعلَّل: «كلُّها صحيحةٌ
    // في موضعِها لأنّها تَقرأ `orders` وحدَها، و`delivered`/`rejected` لا
    // يُكتبانِ عليها أبداً… فلا تُلمَس: لمسُ شفرةٍ سليمةٍ بلا خللٍ خلفَها
    // مخاطرةٌ بلا مقابل». والمسحُ لم يَأتِ بدليلٍ جديد — صفرُ كاتبٍ
    // لـ`delivered`/`rejected` على `orders` — فالحكمُ قائمٌ والتغييرُ رُدّ.
    //
    // والباقي هو ما يَستحقُّ البقاء: **القارئُ** يَرى الآن اللوحةَ كذلك
    // والمجموعاتِ الحرفيّة، فنسخةٌ **جديدةٌ** تُراجَعُ بدلَ أن تُكتَبَ بصمت.
    String code(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final t = l.trimLeft();
          return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*') ||
                  t.startsWith('{/*'))
              ? ''
              : l;
        })
        .join('\n');

    /// موضعُ القاعدةِ ومرآتُها.
    const homes = <String>[
      'lib/utils/order_activity.dart',
      'admin_panel/src/utils/orderActivity.ts',
    ];

    /// النسخُ القائمةُ **المعروفةُ وصحيحةُ الموضع** — ولكلٍّ سببُه. الحكمُ
    /// أعلاه: تَقرأُ `orders` وحدَها، ولا كاتبَ لـ`delivered`/`rejected`
    /// عليها. ورابعةٌ جديدةٌ تَسقطُ هذا الفحصَ فتُراجَع.
    const knownCopies = <String, String>{
      'lib/screens/admin/admin_more_screen.dart': 'عدّادُ «نشط» على orders',
      'lib/screens/driver_dashboard.dart': 'فلترٌ دفاعيٌّ بعد whereIn خادميّ',
      'lib/screens/admin/admin_schedule_board_screen.dart':
          'لوحُ المواعيدِ — مجموعةٌ حرفيّةٌ على orders',
      'admin_panel/src/pages/Orders.tsx': 'isFinalStatus + شرطا الإلغاء',
      'admin_panel/src/pages/ScheduleBoard.tsx': 'DEAD — لوحُ المواعيدِ الويبيّ',
      'lib/services/order_service.dart': 'شرطُ «هل يَجوزُ الإلغاء» لا «هل مفتوح»',
      'lib/screens/admin/admin_order_details_screen.dart':
          'تعدادٌ موجَبٌ لِما يَجوزُ للأدمنِ ضبطُه',
    };

    test('(س) مجموعةُ النسخِ اليدويّةِ كاملةً = المعروفةُ بأسبابِها', () {
      final files = <String>[
        ...Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => p.endsWith('.dart')),
        ...Directory('admin_panel/src')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .where((p) =>
                (p.endsWith('.ts') || p.endsWith('.tsx')) &&
                !p.contains('.test.')),
      ]..sort();
      expect(files.length, greaterThanOrEqualTo(150),
          reason: 'المسحُ لم يَقرأ شيئاً — حارسٌ أجوف');
      final found = <String>{};
      for (final f in files) {
        final path = f.replaceAll('\\', '/');
        if (homes.contains(path)) continue;
        for (final l in code(f).split('\n')) {
          if (!l.contains("'completed'") || !l.contains("'cancelled'")) continue;
          // استعلامُ Firestore بـ`whereIn`/`in` يُعدِّدُ بالضرورة: لا سبيلَ
          // لاستعلامِ «ليس في هذه المجموعة» (قرارٌ مسجَّلٌ في
          // `driver_schedule.dart`).
          if (l.contains('whereIn') || l.contains('"in"') || l.contains("'in'")) {
            continue;
          }
          found.add(path);
        }
      }
      expect(found, knownCopies.keys.toSet(),
          reason: 'نسخةٌ يدويّةٌ جديدةٌ للمجموعةِ المنتهية: إن كانت على '
              '`orders` فأضِفها هنا بسببِها، وإن كانت على `store_orders` '
              'فاستخدم `orderIsOpen` — وإلّا عُدَّ الطلبُ المُسلَّمُ نشطاً');
    });

    test('(ش) والموضعانِ ما زالا يَحملانِ القاعدةَ ذاتَها', () {
      for (final h in homes) {
        final src = code(h);
        expect(src.contains("'delivered'"), isTrue, reason: h);
        expect(src.contains("'rejected'"), isTrue, reason: h);
        expect(src.contains('orderIsOpen'), isTrue, reason: h);
      }
    });
  });
  // ═══ وحالاتُ النشاطِ كذلك: `whereIn` تَعدادٌ موجَبٌ لا بُدّ منه ═══
  //
  // `DriverSchedule.activeStatuses` تَشتقُّ القائمةَ من
  // `kActiveAssignedStatuses` بتعليقٍ يَقولُ سببَها: حالةٌ تُضافُ إلى دورةِ
  // الحياةِ غداً لا يَجوزُ أن تُسقِطَ مهمّةً عن هاتفِ السائقِ بصمت. ثمّ
  // كتبَت لوحةُ السائقِ ولوحةُ العميلةِ الأعضاءَ الخمسةَ **حرفيّاً** في
  // `whereIn` — فشاشةُ مهامِّه تَلتقطُ الحالةَ الجديدةَ ولوحتُه لا.
  //
  // وهذا **ليس** من بابِ «نسخةٌ صحيحةٌ في نطاقِها فلا تُلمَس» الذي رُدَّ به
  // توحيدُ المجموعةِ المنتهيةِ أعلاه: هناك لا اشتقاقَ قائمٌ ولا دليلَ
  // انحراف، وهنا الاشتقاقُ موجودٌ ومُعلَّلٌ ومكتوبٌ لهذا الخطرِ نفسِه.
  group('حالاتُ النشاطِ تُشتَقُّ مرّةً — ولا تعدادَ حرفيّاً لها', () {
    String bare(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final t = l.trimLeft();
          return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'))
              ? ''
              : l;
        })
        .join('\n');

    test('(ك) القائمةُ مُشتَقّةٌ من المجموعةِ لا مكتوبةٌ بيد', () {
      final String src = bare('lib/utils/order_lifecycle.dart');
      expect(
          RegExp(r'kActiveAssignedStatusList\s*=\s*\n?\s*'
                  r'kActiveAssignedStatuses\.toList\(')
              .hasMatch(src),
          isTrue,
          reason: 'القائمةُ لم تَعُدْ مُشتَقّةً — فحالةٌ تُضافُ للمجموعةِ لا '
              'تَبلغُ أيَّ استعلام');
      // والقِيمةُ هي القيمةُ: خمسةُ أعضاءَ بعينِهم.
      expect(kActiveAssignedStatusList.toSet(), kActiveAssignedStatuses);
    });

    test('(ل) والمُنادُون الثلاثةُ يُنادُونها', () {
      for (final p in const [
        'lib/models/driver_schedule.dart',
        'lib/screens/driver_dashboard.dart',
        'lib/screens/client_dashboard.dart',
      ]) {
        expect(bare(p).contains('kActiveAssignedStatusList'), isTrue,
            reason: '$p لا يُنادي القائمةَ المشترَكة');
      }
      // و`DriverSchedule.activeStatuses` تَبقى **قائمةً موجَبةً** — حارسُها
      // يَشدُّ ذلك لأنّ `whereIn` لا تَعرفُ «ليس في هذه المجموعة».
      expect(DriverSchedule.activeStatuses.toSet(), kActiveAssignedStatuses);
    });

    test('(م) ولا تعدادَ حرفيّاً لأعضاءِ المجموعةِ في `lib/`', () {
      // مجموعةٌ حرفيّةٌ أو قائمةٌ تَحوي الأعضاءَ الخمسةَ كلَّها داخلَ قوسٍ
      // واحدٍ — فالموضعُ الواحدُ يُعلِنُها بـ`{}` فلا يُطابَق.
      final List<String> offenders = [];
      int scanned = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        scanned++;
        final String src = bare(f.path);
        for (final m in RegExp(r'\[[^\[\]]*\]', dotAll: true).allMatches(src)) {
          final String inner = m.group(0)!;
          if (kActiveAssignedStatuses
              .every((s) => inner.contains("'$s'"))) {
            offenders.add(f.path.replaceAll('\\', '/'));
          }
        }
      }
      expect(scanned, greaterThanOrEqualTo(100),
          reason: 'المسحُ انحلّ ($scanned ملفّاً)');
      expect(offenders, isEmpty,
          reason: 'تعدادٌ حرفيٌّ لحالاتِ النشاطِ — استعمِلْ '
              '`kActiveAssignedStatusList`: ${offenders.join(", ")}');
    });
  });

}
